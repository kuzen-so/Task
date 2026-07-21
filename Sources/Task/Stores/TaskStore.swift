import Foundation
@preconcurrency import Combine

@MainActor
final class TaskStore: ObservableObject {
    @Published var tasks: [TaskItem] = []

    var activeTasks: [TaskItem] { tasks.filter { !$0.isCompleted } }
    var completedTasks: [TaskItem] { tasks.filter { $0.isCompleted } }

    private let saveQueue = DispatchQueue(label: "com.kuzen.task.save")
    private var saveWorkItem: DispatchWorkItem?
    private var timer: Timer?

    private var remindersSyncTimer: DispatchSourceTimer?
    private var remindersServiceCancellable: AnyCancellable?
    private var isSyncingReminders = false

    var remindersService: RemindersService? {
        didSet {
            remindersServiceCancellable?.cancel()
            remindersServiceCancellable = nil

            if let service = remindersService {
                remindersServiceCancellable = service.$isAuthorized
                    .removeDuplicates()
                    .sink { [weak self] isAuthorized in
                        self?.updateRemindersSyncTimer(isAuthorized: isAuthorized)
                        if isAuthorized {
                            self?.syncReminders()
                        }
                    }
            }

            updateRemindersSyncTimer()
        }
    }
    var onTaskCompleted: ((TaskItem) -> Void)?

    init() {
        registerDefaultSettings()
        load()
        startTimerIfNeeded()
        updateRemindersSyncTimer()
    }

    private func registerDefaultSettings() {
        UserDefaults.standard.register(defaults: [
            "remindersAutoSyncEnabled": true,
            "remindersSyncIntervalSeconds": 60.0,
            Constants.Island.eventAlertEnabledDefaultsKey: true,
            Constants.Island.topDockSideDefaultsKey: "center"
        ])
    }

    deinit {
        MainActor.assumeIsolated {
            remindersSyncTimer?.cancel()
            remindersServiceCancellable?.cancel()
        }
    }

    // MARK: - CRUD

    func submitNewTask(_ title: String) -> Bool {
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return false }
        add(title: trimmed)
        return true
    }

    func add(title: String) {
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }

        let task = TaskItem(title: trimmed)

        if let service = remindersService, service.isAuthorized {
            Task {
                do {
                    let reminderID = try await service.createReminder(title: trimmed)
                    await MainActor.run {
                        if let index = self.tasks.firstIndex(where: { $0.id == task.id }) {
                            self.tasks[index].reminderID = reminderID
                            self.save()
                        }
                    }
                } catch {
                    print("Failed to create reminder: \(error)")
                }
            }
        }

        tasks.append(task)
        setActive(task)
        save()
    }

    func complete(_ task: TaskItem) {
        guard let index = tasks.firstIndex(where: { $0.id == task.id }) else { return }
        guard !tasks[index].isCompleted else { return }

        tasks[index].isCompleted = true
        tasks[index].completedAt = Date()
        tasks[index].isActive = false

        if let reminderID = tasks[index].reminderID {
            Task {
                do {
                    try await remindersService?.completeReminder(id: reminderID)
                } catch {
                    print("Failed to complete reminder: \(error)")
                }
            }
        }

        onTaskCompleted?(tasks[index])
        save()
        startTimerIfNeeded()
    }

    func uncomplete(_ task: TaskItem) {
        guard let index = tasks.firstIndex(where: { $0.id == task.id }) else { return }
        tasks[index].isCompleted = false
        tasks[index].completedAt = nil
        save()
    }

    func delete(_ task: TaskItem) {
        if let reminderID = task.reminderID {
            Task {
                do {
                    try await remindersService?.deleteReminder(id: reminderID)
                } catch {
                    print("Failed to delete reminder: \(error)")
                }
            }
        }

        tasks.removeAll { $0.id == task.id }
        save()
        startTimerIfNeeded()
    }

    func setActive(_ task: TaskItem?) {
        for index in tasks.indices {
            tasks[index].isActive = (task != nil && tasks[index].id == task?.id)
        }
        startTimerIfNeeded()
        save()
    }

    func importReminders() {
        guard let service = remindersService, service.isAuthorized else { return }
        Task {
            do {
                let items = try await service.fetchIncompleteReminders()
                await MainActor.run {
                    for item in items {
                        guard !item.title.isEmpty else { continue }
                        guard !self.tasks.contains(where: { $0.reminderID == item.identifier }) else { continue }
                        let task = TaskItem(
                            title: item.title,
                            reminderID: item.identifier
                        )
                        self.tasks.append(task)
                    }
                    self.save()
                }
            } catch {
                print("Failed to import reminders: \(error)")
            }
        }
    }

    // MARK: - Reminders Sync

    func updateRemindersSyncTimer(isAuthorized: Bool? = nil) {
        remindersSyncTimer?.cancel()
        remindersSyncTimer = nil

        let effectiveAuthorized = isAuthorized ?? remindersService?.isAuthorized ?? false
        guard remindersService != nil, effectiveAuthorized else { return }

        let isEnabled = UserDefaults.standard.bool(forKey: "remindersAutoSyncEnabled")
        guard isEnabled else { return }

        let interval = UserDefaults.standard.double(forKey: "remindersSyncIntervalSeconds")
        let effectiveInterval = interval > 0 ? interval : 60.0

        let newTimer = DispatchSource.makeTimerSource(queue: DispatchQueue.main)
        newTimer.schedule(deadline: .now() + effectiveInterval, repeating: effectiveInterval)
        newTimer.setEventHandler { [weak self] in
            Task { @MainActor in
                self?.syncReminders()
            }
        }
        newTimer.activate()
        remindersSyncTimer = newTimer
    }

    func syncReminders() {
        guard !isSyncingReminders else { return }
        guard let service = remindersService, service.isAuthorized else { return }

        isSyncingReminders = true

        Task {
            defer { isSyncingReminders = false }
            do {
                let items = try await service.fetchIncompleteReminders()
                await MainActor.run {
                    self.mergeReminders(items)
                }
            } catch {
                print("Failed to sync reminders: \(error)")
            }
        }
    }

    private func mergeReminders(_ items: [ReminderImportItem]) {
        let fetchedByID = Dictionary(uniqueKeysWithValues: items.map { ($0.identifier, $0) })

        var didChange = false

        // 1. Update or complete local tasks linked to reminders.
        for index in tasks.indices {
            guard let reminderID = tasks[index].reminderID else { continue }

            if let item = fetchedByID[reminderID] {
                if tasks[index].title != item.title {
                    tasks[index].title = item.title
                    didChange = true
                }
            } else {
                // Reminder was completed or deleted externally.
                if !tasks[index].isCompleted {
                    tasks[index].isCompleted = true
                    tasks[index].completedAt = Date()
                    tasks[index].isActive = false
                    tasks[index].reminderID = nil
                    didChange = true
                }
            }
        }

        // 2. Import new reminders that are not linked yet.
        for item in items {
            guard !item.title.isEmpty else { continue }
            guard !tasks.contains(where: { $0.reminderID == item.identifier }) else { continue }
            let task = TaskItem(title: item.title, reminderID: item.identifier)
            tasks.append(task)
            didChange = true
        }

        if didChange {
            save()
            startTimerIfNeeded()
        }
    }

    // MARK: - Timer

    private var timerTaskID: UUID?
    /// 当前计时段的起始时间；用时间戳记账代替每秒定时器，消除常驻 1s 定时器的 CPU 唤醒。
    private var activeSegmentStartedAt: Date?
    /// 已计时但尚未写入模型的秒数；攒满 60 秒或计时停止时统一 flush，
    /// 避免频繁修改 @Published tasks 导致整个灵动岛视图重建。
    private var pendingElapsed: TimeInterval = 0

    private func startTimerIfNeeded() {
        flushPendingElapsed()
        timer?.invalidate()
        timer = nil
        timerTaskID = nil
        activeSegmentStartedAt = nil

        guard let activeTask = tasks.first(where: { $0.isActive && !$0.isCompleted }) else { return }
        timerTaskID = activeTask.id
        activeSegmentStartedAt = Date()

        // 每分钟把累计时长写入模型；时长按时间戳计算，定时器晚触发/被系统合并都不影响准确性。
        let newTimer = Timer.scheduledTimer(withTimeInterval: 60.0, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.flushPendingElapsed()
            }
        }
        newTimer.tolerance = 10
        timer = newTimer
    }

    /// 按时间戳把上一段计时累加进 pendingElapsed。
    private func accumulateActiveSegment() {
        guard let startedAt = activeSegmentStartedAt else { return }
        let now = Date()
        pendingElapsed += now.timeIntervalSince(startedAt)
        activeSegmentStartedAt = now
    }

    /// 把累计的计时增量写入模型并保存（每分钟一次，或计时停止/切换任务时）。
    private func flushPendingElapsed() {
        accumulateActiveSegment()
        defer { pendingElapsed = 0 }
        guard pendingElapsed > 0, let id = timerTaskID,
              let index = tasks.firstIndex(where: { $0.id == id }) else { return }
        tasks[index].elapsedTime += pendingElapsed
        save()
    }

    // MARK: - Persistence

    func save() {
        saveWorkItem?.cancel()
        let snapshot = tasks
        let workItem = DispatchWorkItem { [weak self] in
            self?.performSave(snapshot)
        }
        saveWorkItem = workItem
        saveQueue.asyncAfter(deadline: .now() + Constants.saveDebounceInterval, execute: workItem)
    }

    func flushSave() {
        flushPendingElapsed()
        saveWorkItem?.cancel()
        saveWorkItem = nil
        performSave(tasks)
    }

    private var tasksFileURL: URL {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let appDir = appSupport.appendingPathComponent(Constants.appSupportDirName, isDirectory: true)
        return appDir.appendingPathComponent(Constants.tasksFileName)
    }

    private func ensureDirectoryExists(at directory: URL) {
        if !FileManager.default.fileExists(atPath: directory.path) {
            try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        }
    }

    private func performSave(_ snapshot: [TaskItem]) {
        guard let encoded = try? JSONEncoder().encode(snapshot) else { return }

        let fileURL = tasksFileURL
        let directory = fileURL.deletingLastPathComponent()
        ensureDirectoryExists(at: directory)

        let tempURL = fileURL.appendingPathExtension("tmp")
        do {
            try encoded.write(to: tempURL, options: .atomic)
            try FileManager.default.replaceItem(at: fileURL, withItemAt: tempURL, backupItemName: nil, options: [], resultingItemURL: nil)
        } catch {
            try? encoded.write(to: fileURL, options: .atomic)
        }
    }

    private func load() {
        let fileURL = tasksFileURL
        let directory = fileURL.deletingLastPathComponent()
        ensureDirectoryExists(at: directory)

        guard let data = try? Data(contentsOf: fileURL),
              let decoded = try? JSONDecoder().decode([TaskItem].self, from: data)
        else { return }

        tasks = decoded
    }
}

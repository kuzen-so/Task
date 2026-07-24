import Foundation
import Combine
import EventKit

/// 通过 EventKit 读取 Calendar.app 的事件，支持重复日程展开。
@MainActor
final class CalendarService: ObservableObject {
    @Published private(set) var todayEvents: [CalendarEvent] = []
    @Published private(set) var upcomingEvents: [CalendarEvent] = []
    @Published private(set) var selectedDateEvents: [CalendarEvent] = []
    @Published private(set) var stripEvents: [CalendarEvent] = []
    @Published private(set) var isAuthorized = false
    @Published private(set) var availableCalendarNames: [String] = []
    @Published private(set) var hiddenCalendarNames: Set<String> = []

    private let eventStore = EKEventStore()
    private let hiddenCalendarsKey = "hiddenCalendarNames"

    /// 保证同时只有一个刷新任务在执行。
    private var fetchTask: Task<Void, Never>?
    private var pendingRequest: RefreshRequest?
    /// 最近一次刷新的选中日期，EventKit 变更通知触发刷新时沿用。
    private var lastSelectedDate: Date = Date()
    /// EventKit 变更通知的防抖（一次 iCloud 同步常连发多条通知）。
    private var storeChangeWorkItem: DispatchWorkItem?

    private struct RefreshRequest {
        let selectedDate: Date
        let stripDays: Int
        let upcomingDays: Int
    }

    init() {
        if let hidden = UserDefaults.standard.stringArray(forKey: hiddenCalendarsKey) {
            hiddenCalendarNames = Set(hidden)
        }
        updateAuthorizationStatus()
        // 日历数据库一变（含其他设备经 iCloud 同步进来的）就即时刷新，
        // FloatingIslandManager 的周期静默刷新只作兜底。
        NotificationCenter.default.addObserver(
            forName: .EKEventStoreChanged,
            object: eventStore,
            queue: nil
        ) { [weak self] _ in
            Task { @MainActor in
                self?.scheduleStoreChangeRefresh()
            }
        }
    }

    private func scheduleStoreChangeRefresh() {
        storeChangeWorkItem?.cancel()
        let workItem = DispatchWorkItem { [weak self] in
            guard let self = self, self.isAuthorized else { return }
            self.refreshAll(centeredOn: self.lastSelectedDate)
        }
        storeChangeWorkItem = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0, execute: workItem)
    }

    // MARK: - Authorization

    func updateAuthorizationStatus() {
        isAuthorized = Self.isAuthorizedStatus(EKEventStore.authorizationStatus(for: .event))
    }

    func requestAccess() async -> Bool {
        let status = EKEventStore.authorizationStatus(for: .event)
        if Self.isAuthorizedStatus(status) {
            isAuthorized = true
            return true
        }

        let granted = await withCheckedContinuation { continuation in
            eventStore.requestAccess(to: .event) { granted, _ in
                continuation.resume(returning: granted)
            }
        }
        isAuthorized = granted
        return granted
    }

    private static func isAuthorizedStatus(_ status: EKAuthorizationStatus) -> Bool {
        if #available(macOS 14.0, *) {
            return status == .authorized || status == .fullAccess
        } else {
            return status == .authorized
        }
    }

    // MARK: - Calendar Selection

    func hideCalendar(named name: String) {
        hiddenCalendarNames.insert(name)
        saveHiddenCalendars()
    }

    func showCalendar(named name: String) {
        hiddenCalendarNames.remove(name)
        saveHiddenCalendars()
    }

    func refreshAvailableCalendars() {
        guard isAuthorized else { return }
        let names = eventStore.calendars(for: .event)
            .map(\.title)
            .sorted()
        availableCalendarNames = names
    }

    private func saveHiddenCalendars() {
        UserDefaults.standard.set(Array(hiddenCalendarNames), forKey: hiddenCalendarsKey)
    }

    // MARK: - Public refresh entry point

    /// 一次性刷新所有日历数据。内部会串行执行，避免并发刷新。
    func refreshAll(centeredOn selectedDate: Date, stripDays: Int = 5, upcomingDays: Int = 14) {
        lastSelectedDate = selectedDate
        guard isAuthorized else {
            todayEvents = []
            selectedDateEvents = []
            upcomingEvents = []
            stripEvents = []
            pendingRequest = nil
            return
        }

        if let pending = pendingRequest {
            guard pending.selectedDate != selectedDate
                    || pending.stripDays != stripDays
                    || pending.upcomingDays != upcomingDays else { return }
        }

        pendingRequest = RefreshRequest(selectedDate: selectedDate, stripDays: stripDays, upcomingDays: upcomingDays)

        guard fetchTask == nil else { return }

        // 串行消费请求队列：循环取出 pendingRequest 执行，执行期间新来的请求会覆盖
        // pendingRequest 并在下一轮被处理。不能在 defer 里回调 refreshAll——那样
        // pendingRequest 在执行完后依然非 nil，会形成无休止的自触发刷新循环，拖满 CPU。
        fetchTask = Task { @MainActor [weak self] in
            guard let self = self else { return }
            while let request = self.pendingRequest {
                self.pendingRequest = nil
                await self.performRefresh(centeredOn: request.selectedDate,
                                          stripDays: request.stripDays,
                                          upcomingDays: request.upcomingDays)
            }
            self.fetchTask = nil
        }
    }

    // MARK: - Individual refresh helpers (all route through refreshAll)

    func refreshTodayEvents() {
        refreshAll(centeredOn: Date(), stripDays: 5, upcomingDays: 14)
    }

    func refreshSelectedDateEvents(_ date: Date) {
        refreshAll(centeredOn: date, stripDays: 5, upcomingDays: 14)
    }

    func refreshUpcomingEvents(days: Int = 14) {
        refreshAll(centeredOn: Date(), stripDays: 5, upcomingDays: days)
    }

    func refreshStripEvents(centeredOn date: Date, days: Int = 5) {
        refreshAll(centeredOn: date, stripDays: days, upcomingDays: 14)
    }

    // MARK: - Fetch logic

    private func performRefresh(centeredOn selectedDate: Date, stripDays: Int, upcomingDays: Int) async {
        guard isAuthorized else {
            todayEvents = []
            selectedDateEvents = []
            upcomingEvents = []
            stripEvents = []
            return
        }

        let calendar = Calendar.current
        let now = Date()

        let todayStart = calendar.startOfDay(for: now)
        let todayEnd = calendar.date(byAdding: .day, value: 1, to: todayStart) ?? todayStart

        let selectedStart = calendar.startOfDay(for: selectedDate)
        let selectedEnd = calendar.date(byAdding: .day, value: 1, to: selectedStart) ?? selectedStart

        let upcomingStart = todayStart
        let upcomingEnd = calendar.date(byAdding: .day, value: upcomingDays, to: upcomingStart) ?? upcomingStart

        let stripHalf = stripDays / 2
        let stripStart = calendar.date(byAdding: .day, value: -stripHalf, to: selectedDate) ?? selectedDate
        let stripEnd = calendar.date(byAdding: .day, value: stripDays - stripHalf, to: stripStart) ?? stripStart

        // 合并所有子范围，只发一次 EventKit 查询
        let unionStart = min(todayStart, selectedStart, upcomingStart, stripStart)
        let unionEnd = max(todayEnd, selectedEnd, upcomingEnd, stripEnd)

        do {
            let allEvents = try await fetchEvents(start: unionStart, end: unionEnd)

            // @Published 赋值即触发视图更新，内容没变时不发布，避免无谓的重绘。
            let newTodayEvents = allEvents
                .filter { $0.startDate < todayEnd && $0.endDate > todayStart }
                .sorted { $0.startDate < $1.startDate }

            let newSelectedDateEvents = allEvents
                .filter { $0.startDate < selectedEnd && $0.endDate > selectedStart }
                .sorted { $0.startDate < $1.startDate }

            let newUpcomingEvents = allEvents
                .filter { $0.startDate >= now && $0.startDate < upcomingEnd }
                .sorted { $0.startDate < $1.startDate }

            let newStripEvents = allEvents
                .filter { $0.startDate < stripEnd && $0.endDate > stripStart }
                .sorted { $0.startDate < $1.startDate }

            if todayEvents != newTodayEvents { todayEvents = newTodayEvents }
            if selectedDateEvents != newSelectedDateEvents { selectedDateEvents = newSelectedDateEvents }
            if upcomingEvents != newUpcomingEvents { upcomingEvents = newUpcomingEvents }
            if stripEvents != newStripEvents { stripEvents = newStripEvents }
        } catch {
            Self.log("performRefresh: failed error=\(error)")
            todayEvents = []
            selectedDateEvents = []
            upcomingEvents = []
            stripEvents = []
        }
    }

    private func fetchEvents(start: Date, end: Date) async throws -> [CalendarEvent] {
        // EventKit 的 events(matching:) 是同步阻塞 API，放到后台队列执行，
        // 避免在主线程上长时间占用 CPU（登录启动时尤其敏感）。
        await Task.detached(priority: .userInitiated) { [hiddenCalendarNames] in
            let store = EKEventStore()
            let visibleCalendars = store.calendars(for: .event)
                .filter { !hiddenCalendarNames.contains($0.title) }

            let predicate = store.predicateForEvents(withStart: start, end: end, calendars: visibleCalendars)
            let ekEvents = store.events(matching: predicate)

            return ekEvents.map { event in
                let uniqueID = "\(event.eventIdentifier ?? UUID().uuidString)|\(event.startDate.timeIntervalSince1970)"
                return CalendarEvent(
                    id: uniqueID,
                    title: event.title ?? "无标题",
                    startDate: event.startDate,
                    endDate: event.endDate,
                    isAllDay: event.isAllDay,
                    calendarName: event.calendar.title
                )
            }
        }.value
    }

    // MARK: - Helpers

    private nonisolated static func log(_ message: String) {
        #if DEBUG
        let timestamp = ISO8601DateFormatter().string(from: Date())
        let line = "[\(timestamp)] \(message)\n"
        print(line, terminator: "")

        let url = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
            .appendingPathComponent("com.kuzen.task", isDirectory: true)
            .appendingPathComponent("calendar.log")
        try? FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        if let data = line.data(using: .utf8) {
            if FileManager.default.fileExists(atPath: url.path) {
                if let handle = try? FileHandle(forWritingTo: url) {
                    handle.seekToEndOfFile()
                    handle.write(data)
                    handle.closeFile()
                }
            } else {
                try? data.write(to: url)
            }
        }
        #endif
    }
}

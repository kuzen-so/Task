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

        fetchTask = Task { @MainActor [weak self] in
            guard let self = self else { return }
            defer {
                self.fetchTask = nil
                if let next = self.pendingRequest {
                    let request = next
                    self.pendingRequest = nil
                    self.refreshAll(centeredOn: request.selectedDate,
                                    stripDays: request.stripDays,
                                    upcomingDays: request.upcomingDays)
                }
            }
            await self.performRefresh(centeredOn: selectedDate,
                                      stripDays: stripDays,
                                      upcomingDays: upcomingDays)
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

            todayEvents = allEvents
                .filter { $0.startDate < todayEnd && $0.endDate > todayStart }
                .sorted { $0.startDate < $1.startDate }

            selectedDateEvents = allEvents
                .filter { $0.startDate < selectedEnd && $0.endDate > selectedStart }
                .sorted { $0.startDate < $1.startDate }

            upcomingEvents = allEvents
                .filter { $0.startDate >= now && $0.startDate < upcomingEnd }
                .sorted { $0.startDate < $1.startDate }

            stripEvents = allEvents
                .filter { $0.startDate < stripEnd && $0.endDate > stripStart }
                .sorted { $0.startDate < $1.startDate }
        } catch {
            Self.log("performRefresh: failed error=\(error)")
            todayEvents = []
            selectedDateEvents = []
            upcomingEvents = []
            stripEvents = []
        }
    }

    private func fetchEvents(start: Date, end: Date) async throws -> [CalendarEvent] {
        let visibleCalendars = eventStore.calendars(for: .event)
            .filter { !hiddenCalendarNames.contains($0.title) }

        let predicate = eventStore.predicateForEvents(withStart: start, end: end, calendars: visibleCalendars)
        let ekEvents = eventStore.events(matching: predicate)

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
    }

    // MARK: - Helpers

    private nonisolated static func log(_ message: String) {
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
    }
}

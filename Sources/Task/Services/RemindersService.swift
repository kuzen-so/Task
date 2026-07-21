import Foundation
import Combine
import EventKit

/// 通过 EventKit 直接读写系统提醒事项数据库，不启动 Reminders.app。
/// 首次运行时会弹出「Task 想访问你的提醒事项」权限框，授权后可在
/// 系统设置 → 隐私与安全性 → 提醒事项 中管理。
@MainActor
final class RemindersService: ObservableObject {
    @Published private(set) var isAuthorized = false

    private let eventStore = EKEventStore()

    init() {
        // 只读取本地权限状态，不触碰 Reminders.app。
        updateAuthorizationStatus()
    }

    /// 应用启动完成后调用。EventKit 查询权限不依赖 Reminders.app，
    /// 无需再等待，保留此方法仅为兼容 AppDelegate 的调用。
    func prepareAfterLaunch() {
        updateAuthorizationStatus()
    }

    // MARK: - Authorization

    func updateAuthorizationStatus() {
        isAuthorized = Self.isAuthorizedStatus(EKEventStore.authorizationStatus(for: .reminder))
    }

    /// 触发系统权限请求。返回 true 表示已经/刚刚授权。
    func requestAccess() async -> Bool {
        let status = EKEventStore.authorizationStatus(for: .reminder)
        if Self.isAuthorizedStatus(status) {
            isAuthorized = true
            return true
        }

        let granted: Bool
        if #available(macOS 14.0, *) {
            granted = await withCheckedContinuation { continuation in
                eventStore.requestFullAccessToReminders { granted, _ in
                    continuation.resume(returning: granted)
                }
            }
        } else {
            granted = await withCheckedContinuation { continuation in
                eventStore.requestAccess(to: .reminder) { granted, _ in
                    continuation.resume(returning: granted)
                }
            }
        }
        isAuthorized = granted
        return granted
    }

    private static func isAuthorizedStatus(_ status: EKAuthorizationStatus) -> Bool {
        if #available(macOS 14.0, *) {
            return status == .authorized || status == .fullAccess
        }
        return status == .authorized
    }

    // MARK: - Operations

    /// 在默认列表新建提醒，返回 calendarItemIdentifier。
    func createReminder(title: String) async throws -> String {
        guard isAuthorized else {
            throw RemindersError.notAuthorized
        }

        let reminder = EKReminder(eventStore: eventStore)
        reminder.title = title
        reminder.calendar = eventStore.defaultCalendarForNewReminders()
        try eventStore.save(reminder, commit: true)
        return reminder.calendarItemIdentifier
    }

    func completeReminder(id: String) async throws {
        guard isAuthorized else { return }
        guard let reminder = eventStore.calendarItem(withIdentifier: id) as? EKReminder else { return }

        reminder.isCompleted = true
        try eventStore.save(reminder, commit: true)
    }

    func deleteReminder(id: String) async throws {
        guard isAuthorized else { return }
        guard let reminder = eventStore.calendarItem(withIdentifier: id) as? EKReminder else { return }

        try eventStore.remove(reminder, commit: true)
    }

    /// 拉取默认列表中所有未完成的提醒。
    func fetchIncompleteReminders() async throws -> [ReminderImportItem] {
        guard isAuthorized else {
            throw RemindersError.notAuthorized
        }

        let calendars: [EKCalendar]? = eventStore.defaultCalendarForNewReminders().map { [$0] }
        let predicate = eventStore.predicateForIncompleteReminders(
            withDueDateStarting: nil,
            ending: nil,
            calendars: calendars
        )

        let reminders: [EKReminder] = try await withCheckedThrowingContinuation { continuation in
            eventStore.fetchReminders(matching: predicate) { reminders in
                continuation.resume(returning: reminders ?? [])
            }
        }

        return reminders.compactMap { reminder in
            guard let title = reminder.title, !title.isEmpty else { return nil }
            return ReminderImportItem(title: title, identifier: reminder.calendarItemIdentifier)
        }
    }
}

struct ReminderImportItem: Sendable {
    let title: String
    let identifier: String
}

enum RemindersError: Error, LocalizedError {
    case notAuthorized
    case eventKitFailed(Error)

    var errorDescription: String? {
        switch self {
        case .notAuthorized:
            return "没有获得访问「提醒事项」的权限。"
        case .eventKitFailed(let error):
            return "提醒事项操作失败：\(error.localizedDescription)"
        }
    }
}

import Foundation
import AppKit
import Combine

/// 使用 AppleScript 直接控制「提醒事项」App，绕过 EventKit 权限限制。
/// 首次运行时会弹出「是否允许 Task 控制 Reminders」的权限框，授权后可在
/// 系统设置 → 隐私与安全性 → 自动化 中管理。
@MainActor
final class RemindersService: ObservableObject {
    @Published private(set) var isAuthorized = false

    private let bundleID = "com.kuzen.task"

    init() {
        // 不在 init 中执行 AppleScript；登录启动时 Reminders.app 可能尚未就绪，
        // 立即探测会导致阻塞或被系统终止。权限状态留到应用启动完成后再懒加载。
    }

    /// 应用启动完成且主界面就绪后再调用，避免在登录启动早期访问 Reminders.app。
    func prepareAfterLaunch() {
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 1_500_000_000)
            updateAuthorizationStatus()
        }
    }

    private nonisolated static func log(_ message: String) {
        let timestamp = ISO8601DateFormatter().string(from: Date())
        let line = "[\(timestamp)] \(message)\n"
        print(line, terminator: "")

        let url = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
            .appendingPathComponent("com.kuzen.task", isDirectory: true)
            .appendingPathComponent("reminders.log")
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

    /// AppleScript 自动化权限没有同步查询 API，这里通过尝试执行一个 harmless 脚本来判断。
    /// 如果脚本能返回结果，说明已经授权；如果被拒绝，会返回错误。
    func updateAuthorizationStatus() {
        Task {
            let script = """
            tell application "Reminders"
                return name of default list
            end tell
            """
            do {
                _ = try await runAppleScript(script)
                self.isAuthorized = true
            } catch {
                Self.log("updateAuthorizationStatus: not authorized, \(error)")
                self.isAuthorized = false
            }
        }
    }

    /// 触发权限请求：直接执行一次 AppleScript，系统会弹出权限框。
    /// 返回 true 表示已经/刚刚授权。
    func requestAccess() async -> Bool {
        Self.log("requestAccess: activating app")
        NSApplication.shared.activate(ignoringOtherApps: true)

        let script = """
        tell application "Reminders"
            return name of default list
        end tell
        """

        Self.log("requestAccess: running probe script")
        do {
            _ = try await runAppleScript(script)
            Self.log("requestAccess: authorized")
            isAuthorized = true
            return true
        } catch {
            Self.log("requestAccess: denied/error=\(error)")
            isAuthorized = false
            return false
        }
    }

    func createReminder(title: String) async throws -> String {
        guard isAuthorized else {
            throw RemindersError.notAuthorized
        }

        let escaped = appleScriptEscape(title)
        let script = """
        tell application "Reminders"
            set newReminder to make new reminder with properties {name:"\(escaped)"}
            return id of newReminder
        end tell
        """

        let id = try await runAppleScript(script)
        Self.log("createReminder: created id=\(id)")
        return id
    }

    func completeReminder(id: String) async throws {
        guard isAuthorized else { return }

        let escaped = appleScriptEscape(id)
        let script = """
        tell application "Reminders"
            set r to first reminder whose id is "\(escaped)"
            set completed of r to true
        end tell
        """

        do {
            _ = try await runAppleScript(script)
        } catch {
            Self.log("completeReminder: failed error=\(error)")
            throw RemindersError.appleScriptFailed(error)
        }
    }

    func deleteReminder(id: String) async throws {
        guard isAuthorized else { return }

        let escaped = appleScriptEscape(id)
        let script = """
        tell application "Reminders"
            set r to first reminder whose id is "\(escaped)"
            delete r
        end tell
        """

        do {
            _ = try await runAppleScript(script)
        } catch {
            Self.log("deleteReminder: failed error=\(error)")
            throw RemindersError.appleScriptFailed(error)
        }
    }

    func fetchIncompleteReminders() async throws -> [ReminderImportItem] {
        guard isAuthorized else {
            throw RemindersError.notAuthorized
        }

        let script = """
        tell application "Reminders"
            set output to ""
            set remList to reminders of default list whose completed is false
            repeat with r in remList
                set output to output & id of r & "\t" & name of r & "\n"
            end repeat
            return output
        end tell
        """

        let text = try await runAppleScript(script)
        let items = parseReminderList(text)
        Self.log("fetchIncompleteReminders: fetched \(items.count) items")
        return items
    }

    // MARK: - Helpers

    private nonisolated func runAppleScript(_ source: String) async throws -> String {
        try await withCheckedThrowingContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                let process = Process()
                process.launchPath = "/usr/bin/osascript"
                process.arguments = ["-e", source]

                let outputPipe = Pipe()
                let errorPipe = Pipe()
                process.standardOutput = outputPipe
                process.standardError = errorPipe

                do {
                    try process.run()
                    process.waitUntilExit()

                    let outputData = outputPipe.fileHandleForReading.readDataToEndOfFile()
                    let errorData = errorPipe.fileHandleForReading.readDataToEndOfFile()
                    let output = String(data: outputData, encoding: .utf8) ?? ""
                    let errorOutput = String(data: errorData, encoding: .utf8) ?? ""

                    if process.terminationStatus == 0 {
                        continuation.resume(returning: output.trimmingCharacters(in: .whitespacesAndNewlines))
                    } else {
                        let message = errorOutput.isEmpty ? output : errorOutput
                        let error = NSError(
                            domain: "AppleScript",
                            code: Int(process.terminationStatus),
                            userInfo: [NSLocalizedDescriptionKey: message]
                        )
                        continuation.resume(throwing: error)
                    }
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
    }

    private nonisolated func appleScriptEscape(_ string: String) -> String {
        string
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
            .replacingOccurrences(of: "\r", with: "\\r")
            .replacingOccurrences(of: "\n", with: "\\n")
    }

    private func parseReminderList(_ text: String) -> [ReminderImportItem] {
        var items: [ReminderImportItem] = []
        let lines = text.split(separator: "\n", omittingEmptySubsequences: true)
        for line in lines {
            let parts = line.split(separator: "\t", maxSplits: 1, omittingEmptySubsequences: false)
            guard parts.count == 2 else { continue }
            let id = String(parts[0])
            let title = String(parts[1])
            guard !title.isEmpty else { continue }
            items.append(ReminderImportItem(title: title, identifier: id))
        }
        return items
    }
}

struct ReminderImportItem: Sendable {
    let title: String
    let identifier: String
}

enum RemindersError: Error, LocalizedError {
    case notAuthorized
    case appleScriptFailed(Error)

    var errorDescription: String? {
        switch self {
        case .notAuthorized:
            return "没有获得控制「提醒事项」App 的权限。"
        case .appleScriptFailed(let error):
            return "AppleScript 执行失败：\(error.localizedDescription)"
        }
    }
}

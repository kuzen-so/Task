import Foundation
import ServiceManagement

@MainActor
final class LaunchAtLoginManager: ObservableObject {
    static let shared = LaunchAtLoginManager()

    private let legacyLabel = "com.kuzen.task.launchatlogin"
    private let legacyPlistURL: URL = {
        FileManager.default.urls(for: .libraryDirectory, in: .userDomainMask)
            .first!
            .appendingPathComponent("LaunchAgents", isDirectory: true)
            .appendingPathComponent("com.kuzen.task.launchatlogin.plist")
    }()

    private let service = SMAppService.mainApp

    @Published private(set) var status: SMAppService.Status
    @Published private(set) var lastError: String?

    var isEnabled: Bool {
        status == .enabled || status == .requiresApproval
    }

    private init() {
        status = service.status
        cleanUpLegacyLaunchAgentIfNeeded()
    }

    func setEnabled(_ enabled: Bool) {
        lastError = nil

        do {
            if enabled {
                try service.register()
            } else {
                try service.unregister()
            }
        } catch {
            lastError = error.localizedDescription
        }

        status = service.status
    }

    // MARK: - Legacy LaunchAgent cleanup

    private func cleanUpLegacyLaunchAgentIfNeeded() {
        let key = "com.kuzen.task.legacyLaunchAgentCleaned"
        guard !UserDefaults.standard.bool(forKey: key) else { return }
        UserDefaults.standard.set(true, forKey: key)

        let fileManager = FileManager.default
        let plistURL = legacyPlistURL
        let label = legacyLabel
        guard fileManager.fileExists(atPath: plistURL.path) else { return }

        // 登录启动早期不要阻塞主线程执行 launchctl / 文件删除。
        Task.detached {
            let domain = "gui/\(getuid())"
            let process = Process()
            process.launchPath = "/bin/launchctl"
            process.arguments = ["bootout", domain, label]
            process.standardOutput = FileHandle.nullDevice
            process.standardError = FileHandle.nullDevice

            do {
                try process.run()
                process.waitUntilExit()
            } catch {
                // Ignore unload errors; the agent may not be loaded.
            }

            try? fileManager.removeItem(at: plistURL)
        }
    }
}

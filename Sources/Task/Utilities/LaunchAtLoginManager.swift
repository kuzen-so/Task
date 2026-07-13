import Foundation

@MainActor
final class LaunchAtLoginManager: ObservableObject {
    static let shared = LaunchAtLoginManager()

    private let label = "com.kuzen.task.launchatlogin"
    private let launchAgentsDir: URL = {
        FileManager.default.urls(for: .libraryDirectory, in: .userDomainMask).first!
            .appendingPathComponent("LaunchAgents", isDirectory: true)
    }()

    private var plistURL: URL {
        launchAgentsDir.appendingPathComponent("\(label).plist")
    }

    @Published private(set) var isEnabled: Bool = false

    private init() {
        isEnabled = checkEnabled()
    }

    func toggle() async {
        if isEnabled {
            await disable()
        } else {
            await enable()
        }
        isEnabled = checkEnabled()
    }

    private func checkEnabled() -> Bool {
        FileManager.default.fileExists(atPath: plistURL.path)
    }

    private func enable() async {
        guard let executableURL = Bundle.main.executableURL else {
            print("Failed to enable launch at login: cannot determine executable path")
            return
        }

        let plist: [String: Any] = [
            "Label": label,
            "ProgramArguments": [
                executableURL.path
            ],
            "WorkingDirectory": executableURL.deletingLastPathComponent().path,
            "RunAtLoad": true,
            "KeepAlive": false,
            "StandardOutPath": logFileURL(pathComponent: "launch.out.log").path,
            "StandardErrorPath": logFileURL(pathComponent: "launch.err.log").path
        ]

        do {
            try FileManager.default.createDirectory(at: launchAgentsDir, withIntermediateDirectories: true)
            try FileManager.default.createDirectory(at: logFileURL(pathComponent: "").deletingLastPathComponent(), withIntermediateDirectories: true)
            let data = try PropertyListSerialization.data(fromPropertyList: plist, format: .xml, options: 0)
            try data.write(to: plistURL, options: .atomic)

            try await runLaunchctl(arguments: ["load", plistURL.path])
        } catch {
            print("Failed to enable launch at login: \(error)")
        }
    }

    private func disable() async {
        do {
            if FileManager.default.fileExists(atPath: plistURL.path) {
                try await runLaunchctl(arguments: ["unload", plistURL.path])
                try FileManager.default.removeItem(at: plistURL)
            }
        } catch {
            print("Failed to disable launch at login: \(error)")
        }
    }

    private nonisolated func runLaunchctl(arguments: [String]) async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            DispatchQueue.global(qos: .userInitiated).async {
                let process = Process()
                process.launchPath = "/bin/launchctl"
                process.arguments = arguments

                do {
                    try process.run()
                    process.waitUntilExit()
                    if process.terminationStatus == 0 {
                        continuation.resume()
                    } else {
                        let error = NSError(
                            domain: "LaunchAtLogin",
                            code: Int(process.terminationStatus),
                            userInfo: [NSLocalizedDescriptionKey: "launchctl exited with status \(process.terminationStatus)"]
                        )
                        continuation.resume(throwing: error)
                    }
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
    }

    private nonisolated func logFileURL(pathComponent: String) -> URL {
        FileManager.default.urls(for: .libraryDirectory, in: .userDomainMask).first!
            .appendingPathComponent("Logs", isDirectory: true)
            .appendingPathComponent("com.kuzen.task", isDirectory: true)
            .appendingPathComponent(pathComponent)
    }
}

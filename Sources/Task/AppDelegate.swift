import SwiftUI
import AppKit

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private let taskStore = TaskStore()
    private let remindersService = RemindersService()
    private let calendarService = CalendarService()
    private var settingsWindow: NSWindow?

    // Status bar
    private var statusItem: NSStatusItem?
    private var popover: NSPopover?
    private var eventMonitor: EventMonitor?

    func applicationDidFinishLaunching(_ notification: Notification) {
        // 尽早触发 LaunchAtLoginManager 初始化，完成旧版 LaunchAgent 清理。
        _ = LaunchAtLoginManager.shared

        // 登录启动时系统窗口服务器/菜单栏可能尚未完全就绪，保守延后；
        // 普通启动则放到下一个 runloop 即可，避免固定 0.6s 的玄学等待。
        let isLoginLaunch = Self.isLaunchedByLoginItem()
        let delay: TimeInterval = isLoginLaunch ? 1.2 : 0

        DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self] in
            self?.performInitialSetup()
        }
    }

    private func performInitialSetup() {
        setupServiceConnections()
        setupSettingsNotification()

        // 分阶段初始化：先状态栏，再浮动窗口。
        // 若窗口服务器尚未就绪（screens 为空），跳过浮动岛并在屏幕参数变化时重建。
        setupStatusBar()
        // NSPopover 与 NSHostingController 在登录启动早期与 NSStatusBarWindow
        // 建立关系时容易触发释放问题，改为在 showPopover() 中按需创建。
        setupEventMonitor()
        setupFloatingIsland()
    }

    /// SMAppService.mainAppService 不会传递任何启动参数或环境变量，因此用启动时系统已运行时间
    /// 作为启发式判断：开机后 60 秒内启动视为登录自启。
    private nonisolated static func isLaunchedByLoginItem() -> Bool {
        ProcessInfo.processInfo.systemUptime < 60
    }

    private func setupSettingsNotification() {
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(showSettings),
            name: .showTaskSettings,
            object: nil
        )
    }

    private func setupServiceConnections() {
        taskStore.remindersService = remindersService
        // 完成任务的反馈由灵动岛左栏舞台区的 Logo 动画承担（v1.8.0 起），
        // 不再弹出全屏 emoji 庆祝动画。
        calendarService.updateAuthorizationStatus()
        remindersService.prepareAfterLaunch()
    }

    // MARK: - Status Bar

    private func setupStatusBar() {
        // 登录启动时状态栏/窗口服务器可能尚未就绪，若 screens 为空则延后重试。
        guard !NSScreen.screens.isEmpty else {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
                self?.setupStatusBar()
            }
            return
        }

        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)

        if let button = statusItem?.button {
            let image: NSImage
            if let path = Bundle.main.path(forResource: "statusbar_icon", ofType: "png"),
               let loaded = NSImage(contentsOfFile: path) {
                loaded.isTemplate = false
                loaded.size = NSSize(width: 18, height: 18)
                image = loaded
            } else {
                image = NSImage(systemSymbolName: "die.face.2.fill", accessibilityDescription: "Task")!
            }
            button.image = image
            button.action = #selector(togglePopover)
            button.target = self
        }
    }

    private func setupPopover() {
        let newPopover = NSPopover()
        newPopover.behavior = .transient
        newPopover.contentSize = NSSize(
            width: Constants.statusBarPopoverWidth,
            height: Constants.statusBarPopoverHeight
        )
        newPopover.contentViewController = NSHostingController(
            rootView: StatusBarMenuView(
                calendarService: calendarService,
                onOpenSettings: { [weak self] in
                    self?.showSettings()
                },
                onQuit: {
                    NSApplication.shared.terminate(nil)
                }
            )
        )
        popover = newPopover
    }

    private func setupEventMonitor() {
        eventMonitor = EventMonitor(mask: [.leftMouseDown, .rightMouseDown]) { [weak self] _ in
            if let self = self, let popover = self.popover, popover.isShown {
                self.closePopover()
            }
        }
    }

    @objc private func togglePopover() {
        if let popover = popover, popover.isShown {
            closePopover()
        } else {
            showPopover()
        }
    }

    private func showPopover() {
        if popover == nil {
            setupPopover()
        }
        if let button = statusItem?.button {
            popover?.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
            eventMonitor?.start()
        }
    }

    private func closePopover() {
        popover?.performClose(nil)
        eventMonitor?.stop()
    }

    // MARK: - Floating Island

    private func setupFloatingIsland() {
        FloatingIslandManager.shared.setup(
            store: taskStore,
            calendarService: calendarService
        ) { [weak self] task in
            self?.taskStore.toggleActive(task)
        }
    }

    @objc func showSettings() {
        closePopover()
        NSApp.activate(ignoringOtherApps: true)

        if settingsWindow == nil {
            let window = NSWindow(
                contentRect: NSRect(x: 0, y: 0, width: 340, height: 560),
                styleMask: [.titled, .closable, .resizable],
                backing: .buffered,
                defer: false
            )
            window.title = "Task 设置"
            window.isReleasedWhenClosed = false
            window.level = .popUpMenu
            window.center()
            window.contentViewController = NSHostingController(rootView: SettingsView(
                taskStore: taskStore,
                remindersService: remindersService,
                calendarService: calendarService
            ))
            settingsWindow = window
        }

        settingsWindow?.makeKeyAndOrderFront(nil)
        settingsWindow?.orderFrontRegardless()
    }

    func applicationWillTerminate(_ notification: Notification) {
        taskStore.flushSave()
    }
}

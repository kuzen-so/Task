import SwiftUI
import AppKit

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private let celebrationOverlay = CelebrationOverlay()

    private let taskStore = TaskStore()
    private let remindersService = RemindersService()
    private let calendarService = CalendarService()
    private var settingsWindow: NSWindow?

    // Status bar
    private var statusItem: NSStatusItem?
    private var popover: NSPopover?
    private var eventMonitor: EventMonitor?

    func applicationDidFinishLaunching(_ notification: Notification) {
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
        setupPopover()
        setupEventMonitor()
        setupFloatingIsland()
    }

    /// 通过判断父进程是否为 launchd(1) 来识别是否由 LaunchAgent 开机自启。
    private nonisolated static func isLaunchedByLoginItem() -> Bool {
        getppid() == 1
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
        taskStore.onTaskCompleted = { [weak self] task in
            self?.showCelebration(for: task)
        }
        calendarService.updateAuthorizationStatus()
        remindersService.prepareAfterLaunch()
    }

    // MARK: - Status Bar

    private func setupStatusBar() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)

        if let button = statusItem?.button {
            let iconPath = Bundle.main.path(forResource: "statusbar_icon", ofType: "png")
            if let path = iconPath, let image = NSImage(contentsOfFile: path) {
                image.isTemplate = false
                image.size = NSSize(width: 18, height: 18)
                button.image = image
            } else {
                button.image = NSImage(
                    systemSymbolName: "dice.fill",
                    accessibilityDescription: "Task"
                )
            }
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
            self?.taskStore.setActive(task)
        }
    }

    private func showCelebration(for task: TaskItem) {
        guard let window = FloatingIslandManager.shared.visibleContentFrame else { return }
        let sourceFrame = NSRect(
            x: window.midX,
            y: window.minY,
            width: 0,
            height: 0
        )
        celebrationOverlay.show(near: sourceFrame)
    }

    @objc func showSettings() {
        closePopover()
        NSApp.activate(ignoringOtherApps: true)

        if settingsWindow == nil {
            let window = NSWindow(
                contentRect: NSRect(x: 0, y: 0, width: 320, height: 420),
                styleMask: [.titled, .closable],
                backing: .buffered,
                defer: false
            )
            window.title = "Task 设置"
            window.isReleasedWhenClosed = false
            window.level = .popUpMenu
            window.center()
            window.contentViewController = NSHostingController(rootView: SettingsView(calendarService: calendarService))
            settingsWindow = window
        }

        settingsWindow?.makeKeyAndOrderFront(nil)
        settingsWindow?.orderFrontRegardless()
    }

    func applicationWillTerminate(_ notification: Notification) {
        taskStore.flushSave()
    }
}

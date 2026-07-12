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
        // 延迟初始化，避免开机自启时与系统菜单栏竞争导致崩溃
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) { [weak self] in
            self?.performInitialSetup()
        }
    }

    private func performInitialSetup() {
        setupServiceConnections()
        setupStatusBar()
        setupPopover()
        setupEventMonitor()
        setupFloatingIsland()
        setupSettingsNotification()
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
        remindersService.updateAuthorizationStatus()
        calendarService.updateAuthorizationStatus()
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

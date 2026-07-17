import SwiftUI
import AppKit
import Combine

@MainActor
final class FloatingIslandManager: ObservableObject {
    static let shared = FloatingIslandManager()

    private var floatingWindow: NSWindow?
    private var screenChangeWorkItem: DispatchWorkItem?
    private var collapseWorkItem: DispatchWorkItem?

    private var isVisible = false
    @Published var isExpanded = false
    @Published private(set) var expandedHeight: CGFloat = Constants.Island.minExpandedHeight

    private var taskStore: TaskStore?
    private var calendarService: CalendarService?
    private var onSelectTask: ((TaskItem) -> Void)?
    private var cancellables = Set<AnyCancellable>()

    private var isTransitioning = false

    private init() {}

    func setup(store: TaskStore, calendarService: CalendarService, onSelectTask: @escaping (TaskItem) -> Void) {
        self.taskStore = store
        self.calendarService = calendarService
        self.onSelectTask = onSelectTask

        store.$tasks
            .sink { [weak self] _ in
                self?.updateExpandedHeight(animated: true)
            }
            .store(in: &cancellables)

        isVisible = true
        updateExpandedHeight(animated: false)

        // 登录启动时屏幕可能尚未就绪，若创建失败则稍后由屏幕参数变化通知重建。
        if targetScreen() == nil {
            Self.log("setup: no screen available yet, deferring window creation")
        } else {
            createFloatingWindow()
        }
        observeAppState()
        observeScreenChanges()
    }

    func show() {
        isVisible = true
        floatingWindow?.orderFrontRegardless()
    }

    func hide() {
        isVisible = false
        if isExpanded {
            collapse()
        }
        floatingWindow?.orderOut(nil)
    }

    // MARK: - App State

    private func observeAppState() {
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleAppDeactivation),
            name: NSApplication.didResignActiveNotification,
            object: nil
        )
    }

    @objc private func handleAppDeactivation() {
        if isExpanded {
            collapse()
        }
    }

    // MARK: - Hover Detection

    // hover 检测由 IslandTrackingView 的 NSTrackingArea 完成（见 updateContentView），
    // 鼠标移动/进出窗口时回调 performHoverCheck。

    private func performHoverCheck() {
        guard !isTransitioning, let window = floatingWindow else { return }

        let mouseLoc = NSEvent.mouseLocation
        // 只检测实际内容区域，加一点边距避免边缘过于敏感。
        let checkFrame = currentContentFrame(in: window).insetBy(dx: -4, dy: -4)
        let inContent = checkFrame.contains(mouseLoc)

        if inContent && !isExpanded {
            cancelPendingCollapse()
            expand()
        } else if !inContent && isExpanded {
            scheduleCollapse()
        } else if inContent && isExpanded {
            cancelPendingCollapse()
        }
    }

    private func currentContentFrame(in window: NSWindow) -> NSRect {
        let size = currentContentSize
        return NSRect(
            x: window.frame.midX - size.width / 2,
            y: window.frame.maxY - size.height,
            width: size.width,
            height: size.height
        )
    }

    private var currentContentSize: NSSize {
        isExpanded
            ? NSSize(width: Constants.Island.expandedWidth, height: expandedHeight)
            : NSSize(width: Constants.Island.collapsedWidth, height: Constants.Island.collapsedHeight)
    }

    private var collapsedSize: NSSize {
        NSSize(width: Constants.Island.collapsedWidth, height: Constants.Island.collapsedHeight)
    }

    private var expandedSize: NSSize {
        NSSize(width: Constants.Island.expandedWidth, height: expandedHeight)
    }

    private func scheduleCollapse() {
        guard collapseWorkItem == nil else { return }
        let workItem = DispatchWorkItem { [weak self] in
            self?.collapse()
            self?.collapseWorkItem = nil
        }
        collapseWorkItem = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + Constants.Island.hoverOutDelay, execute: workItem)
    }

    private func cancelPendingCollapse() {
        collapseWorkItem?.cancel()
        collapseWorkItem = nil
    }

    // MARK: - Expand / Collapse

    private func expand() {
        guard !isExpanded, !isTransitioning else { return }
        isTransitioning = true
        isExpanded = true
        DispatchQueue.main.asyncAfter(deadline: .now() + Constants.Island.animationDuration + 0.05) { [weak self] in
            self?.isTransitioning = false
            self?.floatingWindow?.makeKey()
            NSApplication.shared.activate(ignoringOtherApps: true)
        }
    }

    private func collapse() {
        guard isExpanded, !isTransitioning else { return }
        isTransitioning = true
        isExpanded = false
        DispatchQueue.main.asyncAfter(deadline: .now() + Constants.Island.animationDuration + 0.05) { [weak self] in
            self?.isTransitioning = false
        }
    }

    private func updateExpandedHeight(animated: Bool) {
        // 展开高度固定，不再随任务数量变化；任务列表内部滚动。
        expandedHeight = Constants.Island.fixedExpandedHeight
    }

    // MARK: - Window Management

    private func createFloatingWindow() {
        guard let screen = targetScreen() else { return }

        // 窗口保持展开大小不变，由 SwiftUI 内容动画实现自然展开/收起，避免窗口 resize 与内容动画不同步导致跳动。
        let windowSize = NSSize(
            width: Constants.Island.expandedWidth,
            height: expandedHeight
        )
        let windowFrame = NSRect(origin: .zero, size: windowSize)

        let window = FloatingIslandWindow(
            contentRect: windowFrame,
            styleMask: [.borderless, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )

        window.backgroundColor = .clear
        window.isOpaque = false
        window.hasShadow = false
        window.level = .popUpMenu
        window.collectionBehavior = [.fullScreenAuxiliary, .stationary, .canJoinAllSpaces]
        window.isMovableByWindowBackground = false
        window.appearance = NSAppearance(named: .darkAqua)

        updateContentView(for: window)

        floatingWindow = window
        positionWindow(window, on: screen)
        Self.log("window frame=\(window.frame) screen=\(screen.frame)")
        window.orderFrontRegardless()
    }

    private func positionWindow(_ window: NSWindow, on screen: NSScreen) {
        window.setFrameOrigin(NSPoint(
            x: screen.frame.midX - window.frame.width / 2,
            y: screen.frame.maxY - window.frame.height
        ))
    }

    private func updateContentView(for window: NSWindow) {
        Self.log("updateContentView called")
        guard let store = taskStore, let calendarService = calendarService else {
            Self.log("updateContentView early return")
            return
        }

        let contentView = FloatingIslandView(
            store: store,
            manager: self,
            calendarService: calendarService,
            onSelectTask: { [weak self] task in
                self?.onSelectTask?(task)
            },
            onRequestFocus: { [weak self] in
                self?.focusNewTaskField()
            }
        )

        let hostingView = NSHostingView(rootView: contentView)
        hostingView.frame = window.contentLayoutRect
        hostingView.autoresizingMask = [.width, .height]
        hostingView.wantsLayer = true
        hostingView.layer?.masksToBounds = true

        // 用 IslandTrackingView 包裹 hostingView，通过 NSTrackingArea 检测鼠标移动/进出。
        // 实际展开/收起判断由 performHoverCheck 根据内容区域精确计算，避免提前展开。
        let trackingView = IslandTrackingView(frame: window.contentLayoutRect)
        trackingView.autoresizingMask = [.width, .height]
        trackingView.addSubview(hostingView)
        trackingView.hoverChanged = { [weak self] in
            self?.performHoverCheck()
        }

        window.contentView = trackingView
        Self.log("trackingView frame=\(trackingView.frame) hostingView frame=\(hostingView.frame)")
    }

    private func focusNewTaskField() {
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { [weak self] in
            guard let window = self?.floatingWindow else { return }
            window.makeFirstResponder(nil)
            guard let textField = self?.findTextField(in: window.contentView) else { return }
            window.makeFirstResponder(textField)
        }
    }

    private func findTextField(in view: NSView?) -> NSTextField? {
        guard let view = view else { return nil }
        if let textField = view as? NSTextField, textField.isEditable {
            return textField
        }
        for subview in view.subviews {
            if let found = findTextField(in: subview) {
                return found
            }
        }
        return nil
    }

    // MARK: - Window Frame Access

    var windowFrame: NSRect? {
        floatingWindow?.frame
    }

    var visibleContentFrame: NSRect? {
        guard let window = floatingWindow else { return nil }
        return currentContentFrame(in: window)
    }

    // MARK: - Screen

    private func targetScreen() -> NSScreen? {
        NSScreen.screens.first(where: { $0.frame.origin == .zero }) ?? NSScreen.screens.first
    }

    private func observeScreenChanges() {
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleScreenChange),
            name: NSApplication.didChangeScreenParametersNotification,
            object: nil
        )
    }

    @objc private func handleScreenChange() {
        screenChangeWorkItem?.cancel()
        let workItem = DispatchWorkItem { [weak self] in
            guard let self = self else { return }
            if self.floatingWindow == nil, self.isVisible {
                self.createFloatingWindow()
            } else {
                self.rebuildWindow()
            }
        }
        screenChangeWorkItem = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3, execute: workItem)
    }

    private func rebuildWindow() {
        let wasExpanded = isExpanded
        isExpanded = false

        if let window = floatingWindow {
            // 复用已有窗口，避免关闭/释放导致的 autorelease 崩溃。
            updateContentView(for: window)
            if let screen = targetScreen() {
                positionWindow(window, on: screen)
            }
            if wasExpanded {
                expand()
            }
        } else {
            createFloatingWindow()
            if wasExpanded {
                expand()
            }
        }
    }

    private static func log(_ message: String) {
        let timestamp = ISO8601DateFormatter().string(from: Date())
        let line = "[\(timestamp)] [Island] \(message)\n"
        let url = URL(fileURLWithPath: "/tmp/task_island_debug.log")
        if let data = line.data(using: .utf8) {
            if FileManager.default.fileExists(atPath: url.path),
               let handle = try? FileHandle(forWritingTo: url) {
                handle.seekToEndOfFile()
                handle.write(data)
                handle.closeFile()
            } else {
                try? data.write(to: url)
            }
        }
    }
}

// MARK: - Floating Island Window

/// 允许成为 key window 的边框less窗口，这样里面的 TextField 才能接收键盘输入。
final class FloatingIslandWindow: NSWindow {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }

    override init(contentRect: NSRect, styleMask style: NSWindow.StyleMask, backing backingStoreType: NSWindow.BackingStoreType, defer flag: Bool) {
        super.init(contentRect: contentRect, styleMask: style, backing: backingStoreType, defer: flag)
        self.isReleasedWhenClosed = false
    }
}

// MARK: - Island Tracking View

/// 包裹 SwiftUI hosting view 并监听鼠标进入/离开，用于触发灵动岛展开/收起。
/// 使用 NSTrackingArea 比 NSEvent.addGlobalMonitorForEvents 更可靠，不需要辅助功能权限。
final class IslandTrackingView: NSView {
    var hoverChanged: (() -> Void)?

    private var trackingArea: NSTrackingArea?

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let trackingArea = trackingArea {
            removeTrackingArea(trackingArea)
        }
        let newTrackingArea = NSTrackingArea(
            rect: bounds,
            options: [
                .mouseEnteredAndExited,
                .mouseMoved,
                .activeAlways,
                .inVisibleRect
            ],
            owner: self,
            userInfo: nil
        )
        addTrackingArea(newTrackingArea)
        trackingArea = newTrackingArea
    }

    override func mouseEntered(with event: NSEvent) {
        hoverChanged?()
    }

    override func mouseMoved(with event: NSEvent) {
        hoverChanged?()
    }

    override func mouseExited(with event: NSEvent) {
        hoverChanged?()
    }
}

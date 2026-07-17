import SwiftUI
import AppKit
import Combine
import QuartzCore

/// 吸附边集合。角落实可同时含水平+垂直边；空集表示自由悬浮。
/// 顶部吸附保持拖拽时的水平位置（可停在其他灵动岛软件旁边），不参与自动居中。
struct DockEdges: OptionSet {
    let rawValue: Int
    static let top = DockEdges(rawValue: 1 << 0)
    static let left = DockEdges(rawValue: 1 << 1)
    static let right = DockEdges(rawValue: 1 << 2)
    static let bottom = DockEdges(rawValue: 1 << 3)
}

/// 内容在窗口内的水平对齐：吸附左/右边缘时面板从边缘向内展开，避免探出屏幕。
enum IslandHorizontalAlignment {
    case leading, center, trailing
}

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

    // MARK: - Position State

    /// 当前吸附边组合（角落实可同时含水平+垂直边）；空集表示自由悬浮。
    private var dockEdges: DockEdges = .top
    /// 胶囊中心坐标；nil 表示使用默认顶部居中。
    private var pillCenter: CGPoint?

    /// 供 SwiftUI 内容对齐使用：底部吸附/低位悬浮时内容改为从窗口底部向上展开。
    @Published private(set) var contentAtBottom = false
    @Published private(set) var contentHorizontal: IslandHorizontalAlignment = .center

    // MARK: - Drag State

    private var isMouseDownOnIsland = false
    private var isDragging = false
    /// 拖拽刚结束时鼠标还停在岛上，等移出内容区后再恢复悬停展开，避免一松手就展开。
    private var suppressHoverUntilExit = false
    private var dragStartMouse: NSPoint = .zero
    private var dragStartPillCenter: CGPoint = .zero

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
        restorePosition()

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
        // 鼠标按下（潜在拖拽）与拖拽期间暂停悬停展开/收起。
        guard !isTransitioning, !isMouseDownOnIsland, !isDragging, let window = floatingWindow else { return }

        let mouseLoc = NSEvent.mouseLocation
        // 只检测实际内容区域，加一点边距避免边缘过于敏感。
        let checkFrame = currentContentFrame(in: window).insetBy(dx: -4, dy: -4)
        let inContent = checkFrame.contains(mouseLoc)

        if suppressHoverUntilExit {
            if !inContent { suppressHoverUntilExit = false }
            return
        }

        if inContent && !isExpanded {
            cancelPendingCollapse()
            expand()
        } else if !inContent && isExpanded {
            scheduleCollapse()
        } else if inContent && isExpanded {
            cancelPendingCollapse()
        }
    }

    private var pillSize: NSSize { collapsedSize }
    private var windowSize: NSSize { NSSize(width: Constants.Island.expandedWidth, height: expandedHeight) }

    /// 窗口恒为展开大小，由胶囊中心 + 当前对齐方式推导窗口 frame。
    private func windowFrame(forPillCenter center: CGPoint) -> NSRect {
        let size = windowSize
        let x: CGFloat
        switch contentHorizontal {
        case .leading: x = center.x - pillSize.width / 2
        case .trailing: x = center.x + pillSize.width / 2 - size.width
        case .center: x = center.x - size.width / 2
        }
        let y: CGFloat = contentAtBottom
            ? center.y - pillSize.height / 2
            : center.y + pillSize.height / 2 - size.height
        return NSRect(origin: NSPoint(x: x, y: y), size: size)
    }

    /// 与 windowFrame 互逆：从窗口 frame 反推胶囊（收起态内容）frame。
    private func currentPillFrame(in window: NSWindow) -> NSRect {
        contentFrame(size: pillSize, in: window)
    }

    private func currentContentFrame(in window: NSWindow) -> NSRect {
        contentFrame(size: currentContentSize, in: window)
    }

    private func contentFrame(size: NSSize, in window: NSWindow) -> NSRect {
        let x: CGFloat
        switch contentHorizontal {
        case .leading: x = window.frame.minX
        case .trailing: x = window.frame.maxX - size.width
        case .center: x = window.frame.midX - size.width / 2
        }
        let y: CGFloat = contentAtBottom ? window.frame.minY : window.frame.maxY - size.height
        return NSRect(x: x, y: y, width: size.width, height: size.height)
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
            // 动画期间 mouseExited 会被 isTransitioning guard 丢弃（鼠标快速划过时），
            // 结束后重新检测一次，若鼠标已离开则补触发收起。
            self?.performHoverCheck()
        }
    }

    private func collapse() {
        guard isExpanded, !isTransitioning else { return }
        isTransitioning = true
        isExpanded = false
        DispatchQueue.main.asyncAfter(deadline: .now() + Constants.Island.animationDuration + 0.05) { [weak self] in
            self?.isTransitioning = false
            // 同理：收起动画期间鼠标若重新进入，补触发展开。
            // 但 App 已失活（如 Cmd+Tab 切走）时不补，避免和失活收起互相打架。
            if NSApplication.shared.isActive {
                self?.performHoverCheck()
            }
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
        applyRestPosition()
        Self.log("window frame=\(window.frame) screen=\(screen.frame)")
        window.orderFrontRegardless()
    }

    // MARK: - Positioning

    private func applyRestPosition(animated: Bool = false) {
        guard let window = floatingWindow, let screen = window.screen ?? targetScreen() else { return }
        updateContentAlignment()
        let center = pillCenter ?? defaultPillCenter(on: screen)
        pillCenter = center
        let frame = windowFrame(forPillCenter: center)
        if animated {
            NSAnimationContext.runAnimationGroup { ctx in
                ctx.duration = Constants.Island.snapAnimationDuration
                ctx.timingFunction = CAMediaTimingFunction(name: .easeOut)
                window.animator().setFrame(frame, display: true)
            }
        } else {
            window.setFrame(frame, display: true)
        }
    }

    /// 默认位置：屏幕顶部居中，胶囊顶贴屏幕上缘（与旧版固定行为一致）。
    private func defaultPillCenter(on screen: NSScreen) -> CGPoint {
        CGPoint(x: screen.frame.midX, y: screen.frame.maxY - pillSize.height / 2)
    }

    /// 由吸附边推导内容对齐：吸底边向上展开；吸左/右边从边缘向内展开；自由悬浮按下方剩余空间决定。
    private func updateContentAlignment() {
        if dockEdges.contains(.left) {
            contentHorizontal = .leading
        } else if dockEdges.contains(.right) {
            contentHorizontal = .trailing
        } else {
            contentHorizontal = .center
        }

        if dockEdges.contains(.bottom) {
            contentAtBottom = true
        } else if dockEdges.contains(.top) {
            contentAtBottom = false
        } else {
            contentAtBottom = !expandedFitsBelow()
        }
    }

    /// 自由悬浮时展开面板向下是否放得下（窗口恒为展开高度）。
    private func expandedFitsBelow() -> Bool {
        guard let center = pillCenter, let screen = floatingWindow?.screen ?? targetScreen() else { return true }
        return center.y + pillSize.height / 2 - windowSize.height >= screen.visibleFrame.minY
    }

    /// 拖拽过程中约束胶囊中心，保证（不可见的）窗口整体不超出屏幕。
    private func clampedPillCenter(_ center: CGPoint, on screen: NSScreen) -> CGPoint {
        let vf = screen.visibleFrame
        let w = windowSize.width
        let h = windowSize.height
        let halfPill = pillSize.height / 2

        var x = center.x
        var y = center.y
        if w <= vf.width {
            x = min(max(x, vf.minX + w / 2), vf.maxX - w / 2)
        }
        if contentAtBottom {
            y = min(max(y, vf.minY + halfPill), screen.frame.maxY + halfPill - h)
        } else {
            y = min(max(y, vf.minY + h - halfPill), screen.frame.maxY - halfPill)
        }
        return CGPoint(x: x, y: y)
    }

    // MARK: - Position Persistence

    private func restorePosition() {
        let defaults = UserDefaults.standard
        guard defaults.object(forKey: Constants.Island.dockEdgeDefaultsKey) != nil else { return }

        // 顶部吸附同样要恢复水平位置（可停在其他灵动岛软件旁边），否则重启后会回到默认居中。
        let edges = DockEdges(rawValue: defaults.integer(forKey: Constants.Island.dockEdgeDefaultsKey))
        let center = CGPoint(
            x: defaults.double(forKey: Constants.Island.pillCenterXDefaultsKey),
            y: defaults.double(forKey: Constants.Island.pillCenterYDefaultsKey)
        )
        guard isPillCenterOnAnyScreen(center) else { return }

        dockEdges = edges
        pillCenter = center
    }

    private func persistPosition() {
        guard let center = pillCenter else { return }
        let defaults = UserDefaults.standard
        defaults.set(dockEdges.rawValue, forKey: Constants.Island.dockEdgeDefaultsKey)
        defaults.set(Double(center.x), forKey: Constants.Island.pillCenterXDefaultsKey)
        defaults.set(Double(center.y), forKey: Constants.Island.pillCenterYDefaultsKey)
    }

    /// 屏幕配置变化后若位置已出屏（如拔掉外接屏），回退到默认顶部居中。
    private func validateRestPosition() {
        if let center = pillCenter, !isPillCenterOnAnyScreen(center) {
            dockEdges = .top
            pillCenter = nil
        }
    }

    private func isPillCenterOnAnyScreen(_ center: CGPoint) -> Bool {
        NSScreen.screens.contains {
            $0.visibleFrame.insetBy(dx: -pillSize.width, dy: -pillSize.height).contains(center)
        }
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
        trackingView.mouseDownHandler = { [weak self] point in
            self?.islandMouseDown(at: point)
        }
        trackingView.mouseDraggedHandler = { [weak self] point in
            self?.islandMouseDragged(at: point)
        }
        trackingView.mouseUpHandler = { [weak self] point in
            self?.islandMouseUp(at: point)
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

    // MARK: - Dragging

    /// 鼠标在岛内容区域按下（由 IslandTrackingView 转发）。按下期间暂停悬停展开，
    /// 移动超过 dragThreshold 才判定为拖拽，不影响正常点击。
    func islandMouseDown(at mouse: NSPoint) {
        // 窗口恒为展开大小，只有按在可见内容（胶囊/展开面板）上才允许拖拽，
        // 否则透明区域的点击会意外把岛拖走。
        guard let window = floatingWindow,
              currentContentFrame(in: window).insetBy(dx: -4, dy: -4).contains(mouse) else { return }
        isMouseDownOnIsland = true
        dragStartMouse = mouse
        let pill = currentPillFrame(in: window)
        dragStartPillCenter = CGPoint(x: pill.midX, y: pill.midY)
    }

    func islandMouseDragged(at mouse: NSPoint) {
        guard isMouseDownOnIsland else { return }
        if !isDragging {
            let distance = hypot(mouse.x - dragStartMouse.x, mouse.y - dragStartMouse.y)
            guard distance >= Constants.Island.dragThreshold else { return }
            beginDrag()
        }
        dragMoved(to: mouse)
    }

    func islandMouseUp(at mouse: NSPoint) {
        isMouseDownOnIsland = false
        if isDragging {
            endDrag()
            suppressHoverUntilExit = true
        } else {
            // 普通点击：恢复按下期间被暂停的悬停逻辑。
            performHoverCheck()
        }
    }

    private func beginDrag() {
        cancelPendingCollapse()
        isDragging = true
        // 拖拽即脱离吸附，回到自由悬浮对齐；展开状态下先收起成胶囊跟着鼠标走。
        dockEdges = []
        if isExpanded {
            isExpanded = false
        }
    }

    private func dragMoved(to mouse: NSPoint) {
        guard let window = floatingWindow else { return }
        var center = CGPoint(
            x: dragStartPillCenter.x + (mouse.x - dragStartMouse.x),
            y: dragStartPillCenter.y + (mouse.y - dragStartMouse.y)
        )
        pillCenter = center
        updateContentAlignment()
        if let screen = window.screen ?? targetScreen() {
            center = clampedPillCenter(center, on: screen)
            pillCenter = center
        }
        window.setFrameOrigin(windowFrame(forPillCenter: center).origin)
    }

    /// 松手：靠近屏幕四边则动画吸附；顶部吸附保持当前水平位置，方便停在其他灵动岛软件旁边。
    private func endDrag() {
        isDragging = false
        guard let window = floatingWindow, let center = pillCenter,
              let screen = window.screen ?? targetScreen() else { return }

        let vf = screen.visibleFrame
        let threshold = Constants.Island.snapThreshold
        var edges: DockEdges = []
        var target = center

        if center.x - vf.minX < threshold {
            edges.insert(.left)
            target.x = vf.minX + pillSize.width / 2
        } else if vf.maxX - center.x < threshold {
            edges.insert(.right)
            target.x = vf.maxX - pillSize.width / 2
        }
        if center.y - vf.minY < threshold {
            edges.insert(.bottom)
            target.y = vf.minY + pillSize.height / 2
        } else if screen.frame.maxY - center.y < threshold {
            edges.insert(.top)
            target.y = screen.frame.maxY - pillSize.height / 2
        }

        dockEdges = edges
        pillCenter = target
        persistPosition()

        updateContentAlignment()
        let frame = windowFrame(forPillCenter: target)
        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = Constants.Island.snapAnimationDuration
            ctx.timingFunction = CAMediaTimingFunction(name: .easeOut)
            window.animator().setFrame(frame, display: true)
        }
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
            validateRestPosition()
            applyRestPosition()
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
    var mouseDownHandler: ((NSPoint) -> Void)?
    var mouseDraggedHandler: ((NSPoint) -> Void)?
    var mouseUpHandler: ((NSPoint) -> Void)?

    private var trackingArea: NSTrackingArea?

    /// 应用未激活时也直接收到第一次点击，这样才能从岛背景区域发起拖拽。
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

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

    // 空白区域的鼠标事件会沿响应链冒泡到这里（SwiftUI 按钮/输入框/滚动区会自己消费，
    // 不会触发拖拽），超过 dragThreshold 后由 manager 判定为拖拽。
    override func mouseDown(with event: NSEvent) {
        mouseDownHandler?(NSEvent.mouseLocation)
    }

    override func mouseDragged(with event: NSEvent) {
        mouseDraggedHandler?(NSEvent.mouseLocation)
    }

    override func mouseUp(with event: NSEvent) {
        mouseUpHandler?(NSEvent.mouseLocation)
    }
}

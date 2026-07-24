import SwiftUI
import AppKit
import Combine
import QuartzCore

extension Notification.Name {
    /// 设置里改了顶部停靠位置（居中/刘海左侧/刘海右侧），岛需要回到新的默认位置。
    static let islandTopDockSideChanged = Notification.Name("com.kuzen.task.islandTopDockSideChanged")
}

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
    // 展开高度固定，不随任务数量变化；任务列表内部滚动。
    @Published private(set) var expandedHeight: CGFloat = Constants.Island.fixedExpandedHeight

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

        isVisible = true
        restorePosition()

        // 登录启动时屏幕可能尚未就绪，若创建失败则稍后由屏幕参数变化通知重建。
        if targetScreen() == nil {
            Self.log("setup: no screen available yet, deferring window creation")
        } else {
            createFloatingWindow()
        }
        observeAppState()
        observeScreenChanges()

        calendarService.$todayEvents
            .sink { [weak self] _ in
                self?.evaluateEventAlert()
            }
            .store(in: &cancellables)
        startEventAlertTimer()
        startCalendarIdleRefreshTimer()
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleTopDockSideChange),
            name: .islandTopDockSideChanged,
            object: nil
        )
        lastSnapEnabled = UserDefaults.standard.bool(forKey: Constants.Island.alwaysSnapEnabledDefaultsKey)
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleDefaultsChange),
            name: UserDefaults.didChangeNotification,
            object: nil
        )
    }

    /// 磁铁开关上次已知状态：从关到开的瞬间，若岛还浮着就立刻吸回顶部。
    private var lastSnapEnabled = false

    @objc private func handleDefaultsChange() {
        let on = UserDefaults.standard.bool(forKey: Constants.Island.alwaysSnapEnabledDefaultsKey)
        defer { lastSnapEnabled = on }
        guard on != lastSnapEnabled else { return }
        if !on {
            pendingSnapOnExit = false
            return
        }
        if isExpanded {
            // 不马上收起：挂起，等鼠标离开岛区域后再收起+吸附（见 performHoverCheck）。
            pendingSnapOnExit = true
        } else {
            snapToTopEdge(animated: true)
        }
    }

    /// 磁铁打开时岛正处于展开态：挂起，等鼠标离开后再收起+吸附。
    private var pendingSnapOnExit = false

    /// 立刻吸附到顶部（磁铁刚打开 / 启动校正时用），保持当前水平位置。
    private func snapToTopEdge(animated: Bool) {
        guard let window = floatingWindow, let screen = window.screen ?? targetScreen() else { return }
        let currentCenter = pillCenter ?? CGPoint(x: window.frame.midX, y: window.frame.midY)
        let target = CGPoint(x: currentCenter.x, y: screen.frame.maxY - pillSize.height / 2)
        dockEdges = [.top]
        pillCenter = target
        persistPosition()
        updateContentAlignment()
        let frame = windowFrame(forPillCenter: target)
        if animated {
            startDropletSnap(to: frame, in: window)
        } else {
            window.setFrame(frame, display: true)
        }
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

        // 磁铁刚打开时岛是展开的：等鼠标真正离开后再收起+吸附。
        if pendingSnapOnExit, !inContent {
            pendingSnapOnExit = false
            if isExpanded {
                collapse()
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + Constants.Island.animationDuration + 0.05) { [weak self] in
                guard let self = self, !self.isDragging,
                      UserDefaults.standard.bool(forKey: Constants.Island.alwaysSnapEnabledDefaultsKey) else { return }
                self.snapToTopEdge(animated: true)
            }
            return
        }

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
    /// 窗口 = 展开内容 + 四周 shadowPadding 透明边距（供投影渲染）。
    private var windowSize: NSSize {
        NSSize(
            width: Constants.Island.expandedWidth + Constants.Island.shadowPadding * 2,
            height: expandedHeight + Constants.Island.shadowPadding * 2
        )
    }

    /// 窗口恒为「展开大小+投影边距」不变，由胶囊中心 + 当前对齐方式推导窗口 frame。
    /// 内容在窗口内四边各内缩 shadowPadding。
    private func windowFrame(forPillCenter center: CGPoint) -> NSRect {
        let size = windowSize
        let pad = Constants.Island.shadowPadding
        let x: CGFloat
        switch contentHorizontal {
        case .leading: x = center.x - pillSize.width / 2 - pad
        case .trailing: x = center.x + pillSize.width / 2 + pad - size.width
        case .center: x = center.x - size.width / 2
        }
        let y: CGFloat = contentAtBottom
            ? center.y - pillSize.height / 2 - pad
            : center.y + pillSize.height / 2 + pad - size.height
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
        let pad = Constants.Island.shadowPadding
        let x: CGFloat
        switch contentHorizontal {
        case .leading: x = window.frame.minX + pad
        case .trailing: x = window.frame.maxX - pad - size.width
        case .center: x = window.frame.midX - size.width / 2
        }
        let y: CGFloat = contentAtBottom ? window.frame.minY + pad : window.frame.maxY - pad - size.height
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
        // 悬停展开即视为已读日程提醒。
        if alertEvent != nil {
            alertEvent = nil
        }
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

    // MARK: - Window Management

    private func createFloatingWindow() {
        guard let screen = targetScreen() else { return }

        // 窗口保持「展开大小+投影边距」不变，由 SwiftUI 内容动画实现自然展开/收起，
        // 避免窗口 resize 与内容动画不同步导致跳动。
        let windowFrame = NSRect(origin: .zero, size: windowSize)

        let window = FloatingIslandWindow(
            contentRect: windowFrame,
            styleMask: [.borderless, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )

        window.backgroundColor = .clear
        window.isOpaque = false
        // 投影由 SwiftUI 画在窗口内的透明边距里（窗口服务器阴影太弱且不可调）。
        window.hasShadow = false
        window.level = .popUpMenu
        window.collectionBehavior = [.fullScreenAuxiliary, .stationary, .canJoinAllSpaces]
        window.isMovableByWindowBackground = false
        window.appearance = NSAppearance(named: .darkAqua)

        updateContentView(for: window)

        floatingWindow = window
        applyRestPosition()
        // 磁铁开着但记住的位置是悬浮态（上次关着时停的）：启动即校正回顶部。
        if UserDefaults.standard.bool(forKey: Constants.Island.alwaysSnapEnabledDefaultsKey), dockEdges != [.top] {
            snapToTopEdge(animated: false)
        }
        Self.log("window frame=\(window.frame) screen=\(screen.frame)")
        window.orderFrontRegardless()
    }

    // MARK: - Positioning

    private func applyRestPosition(animated: Bool = false) {
        guard let window = floatingWindow, let screen = window.screen ?? targetScreen() else { return }
        let center = pillCenter ?? defaultPillCenter(on: screen)
        pillCenter = center
        updateContentAlignment()
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

    /// 默认位置：屏幕顶部，胶囊顶贴屏幕上缘。水平位置由设置决定：居中（默认）或停靠刘海
    /// 左/右侧（用 auxiliaryTopLeftArea/RightArea 精确定位），避让其他灵动岛软件。
    private func defaultPillCenter(on screen: NSScreen) -> CGPoint {
        let y = screen.frame.maxY - pillSize.height / 2
        let side = UserDefaults.standard.string(forKey: Constants.Island.topDockSideDefaultsKey) ?? "center"
        let x: CGFloat
        switch side {
        case "left":
            if let area = screen.auxiliaryTopLeftArea, area.width >= pillSize.width {
                x = area.midX
            } else {
                x = screen.visibleFrame.minX + pillSize.width / 2 + 12
            }
        case "right":
            if let area = screen.auxiliaryTopRightArea, area.width >= pillSize.width {
                x = area.midX
            } else {
                x = screen.visibleFrame.maxX - pillSize.width / 2 - 12
            }
        default:
            x = screen.frame.midX
        }
        return CGPoint(x: x, y: y)
    }

    /// 由吸附边推导内容对齐：吸底边向上展开；吸左/右边从边缘向内展开；自由悬浮按下方剩余空间决定。
    /// 顶部吸附/悬浮时若展开面板居中会超出屏幕（如停靠刘海一侧），自动改为从对应边缘向内展开。
    private func updateContentAlignment() {
        if dockEdges.contains(.left) {
            contentHorizontal = .leading
        } else if dockEdges.contains(.right) {
            contentHorizontal = .trailing
        } else {
            contentHorizontal = .center
            if let center = pillCenter, let screen = floatingWindow?.screen ?? targetScreen() {
                let halfWidth = Constants.Island.expandedWidth / 2
                let vf = screen.visibleFrame
                if center.x - halfWidth < vf.minX {
                    contentHorizontal = .leading
                } else if center.x + halfWidth > vf.maxX {
                    contentHorizontal = .trailing
                }
            }
        }

        if dockEdges.contains(.bottom) {
            contentAtBottom = true
        } else if dockEdges.contains(.top) {
            contentAtBottom = false
        } else {
            contentAtBottom = !expandedFitsBelow()
        }
    }

    /// 自由悬浮时展开面板向下是否放得下（内容高度，不含投影边距）。
    private func expandedFitsBelow() -> Bool {
        guard let center = pillCenter, let screen = floatingWindow?.screen ?? targetScreen() else { return true }
        return center.y + pillSize.height / 2 - expandedHeight >= screen.visibleFrame.minY
    }

    /// 拖拽过程中约束胶囊中心。只约束可见内容（胶囊/展开面板）不出屏幕；
    /// 透明大窗口可以随意探出屏幕（不挡点击，投影被裁一点也无所谓）。
    private func clampedPillCenter(_ center: CGPoint, on screen: NSScreen) -> CGPoint {
        let vf = screen.visibleFrame
        let halfPillW = pillSize.width / 2
        let halfPillH = pillSize.height / 2

        var x = center.x
        var y = center.y
        x = min(max(x, vf.minX + halfPillW), vf.maxX - halfPillW)
        if contentAtBottom {
            y = min(max(y, vf.minY + halfPillH), screen.frame.maxY + halfPillH - expandedHeight)
        } else {
            y = min(max(y, vf.minY + expandedHeight - halfPillH), screen.frame.maxY - halfPillH)
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
        trackingView.rightMouseDownHandler = { [weak self] event in
            self?.islandRightMouseDown(with: event)
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

    // MARK: - Event Alert（模仿 Vibe Island：需要你了就发光，不展开、不抢焦点）

    /// 当前正在提醒的日程：开始前 leadTime 内（或刚开始 graceTime 内）触发，
    /// 胶囊发光脉冲并显示日程标题；用户悬停展开即视为已读。
    @Published private(set) var alertEvent: CalendarEvent?
    /// 本次运行已提醒过的日程 id，避免重复发光。
    private var alertedEventIDs = Set<String>()
    private var eventAlertTimer: DispatchSourceTimer?
    private var calendarIdleRefreshTimer: DispatchSourceTimer?

    private func startEventAlertTimer() {
        let timer = DispatchSource.makeTimerSource(queue: .main)
        timer.schedule(deadline: .now() + Constants.Island.eventAlertCheckInterval,
                       repeating: Constants.Island.eventAlertCheckInterval)
        timer.setEventHandler { [weak self] in
            Task { @MainActor in
                self?.evaluateEventAlert()
            }
        }
        timer.activate()
        eventAlertTimer = timer
    }

    /// 未展开时日历数据只在 onAppear/展开时刷新，提醒会失效；这里每 5 分钟静默刷新一次。
    private func startCalendarIdleRefreshTimer() {
        let timer = DispatchSource.makeTimerSource(queue: .main)
        timer.schedule(deadline: .now() + Constants.Island.calendarIdleRefreshInterval,
                       repeating: Constants.Island.calendarIdleRefreshInterval)
        timer.setEventHandler { [weak self] in
            Task { @MainActor in
                guard let self = self, let service = self.calendarService, service.isAuthorized else { return }
                service.refreshAll(centeredOn: Date())
            }
        }
        timer.activate()
        calendarIdleRefreshTimer = timer
    }

    private func evaluateEventAlert() {
        guard UserDefaults.standard.bool(forKey: Constants.Island.eventAlertEnabledDefaultsKey) else {
            alertEvent = nil
            return
        }
        let now = Date()
        if let current = alertEvent {
            // 开始超过宽限期后自动撤下。
            if current.startDate < now.addingTimeInterval(-Constants.Island.eventAlertGraceTime) {
                alertEvent = nil
            } else {
                return
            }
        }
        let windowStart = now.addingTimeInterval(-Constants.Island.eventAlertGraceTime)
        let windowEnd = now.addingTimeInterval(Constants.Island.eventAlertLeadTime)
        guard let next = calendarService?.todayEvents.first(where: {
            !$0.isAllDay
                && $0.startDate >= windowStart
                && $0.startDate <= windowEnd
                && !alertedEventIDs.contains($0.id)
        }) else { return }
        alertEvent = next
        alertedEventIDs.insert(next.id)
    }

    /// 设置里改了顶部停靠位置：清掉保存的位置，回到新的默认位置。
    @objc private func handleTopDockSideChange() {
        dockEdges = .top
        pillCenter = nil
        let defaults = UserDefaults.standard
        defaults.removeObject(forKey: Constants.Island.dockEdgeDefaultsKey)
        defaults.removeObject(forKey: Constants.Island.pillCenterXDefaultsKey)
        defaults.removeObject(forKey: Constants.Island.pillCenterYDefaultsKey)
        if isExpanded {
            collapse()
        }
        updateContentAlignment()
        applyRestPosition(animated: true)
    }

    // MARK: - Window Frame Access

    var windowFrame: NSRect? {
        floatingWindow?.frame
    }

    var visibleContentFrame: NSRect? {
        guard let window = floatingWindow else { return nil }
        return currentContentFrame(in: window)
    }

    // MARK: - Context Menu

    /// 右键弹原生菜单：设置 / 退出。
    /// 只在展开态的顶部标题栏（状态栏）触发——动画舞台/任务列表/日历区右键容易误触。
    private func islandRightMouseDown(with event: NSEvent) {
        guard isExpanded,
              let window = floatingWindow,
              let contentView = window.contentView else { return }
        let content = currentContentFrame(in: window)
        let header = NSRect(x: content.minX,
                            y: content.maxY - Constants.Island.headerHeight,
                            width: content.width,
                            height: Constants.Island.headerHeight)
        guard header.contains(NSEvent.mouseLocation) else { return }

        // 菜单弹出期间别触发悬停收起。
        cancelPendingCollapse()

        let menu = NSMenu()
        let settingsItem = NSMenuItem(title: "设置…", action: #selector(openSettingsFromMenu), keyEquivalent: "")
        settingsItem.target = self
        menu.addItem(settingsItem)
        menu.addItem(.separator())
        let quitItem = NSMenuItem(title: "退出 Task", action: #selector(quitAppFromMenu), keyEquivalent: "")
        quitItem.target = self
        menu.addItem(quitItem)

        let pointInView = contentView.convert(event.locationInWindow, from: nil)
        menu.popUp(positioning: nil, at: pointInView, in: contentView)
    }

    @objc private func openSettingsFromMenu() {
        NotificationCenter.default.post(name: .showTaskSettings, object: nil)
    }

    @objc private func quitAppFromMenu() {
        NSApplication.shared.terminate(nil)
    }

    // MARK: - Dragging

    /// 鼠标在岛内容区域按下（由 IslandTrackingView 转发）。按下期间暂停悬停展开，
    /// 移动超过 dragThreshold 才判定为拖拽，不影响正常点击。
    /// 展开状态下只有顶部标题栏可拖动岛：任务列表区域要留给行的拖动排序手势，
    /// 否则两个拖拽同时抢手势。
    /// 自由移动开关：键不存在视为开（默认可拖）。
    private var isFreeMoveEnabled: Bool {
        let defaults = UserDefaults.standard
        return defaults.object(forKey: Constants.Island.freeMoveEnabledDefaultsKey) == nil
            || defaults.bool(forKey: Constants.Island.freeMoveEnabledDefaultsKey)
    }

    func islandMouseDown(at mouse: NSPoint) {
        // 自由移动关闭时岛锁死：不进入按下/拖拽状态，悬停展开与点击不受影响。
        guard isFreeMoveEnabled else { return }
        // 窗口恒为展开大小，只有按在可见内容（胶囊/展开面板）上才允许拖拽，
        // 否则透明区域的点击会意外把岛拖走。
        guard let window = floatingWindow,
              currentContentFrame(in: window).insetBy(dx: -4, dy: -4).contains(mouse) else { return }
        if isExpanded {
            let content = currentContentFrame(in: window)
            let header = NSRect(x: content.minX,
                                y: content.maxY - Constants.Island.headerHeight,
                                width: content.width,
                                height: Constants.Island.headerHeight)
            guard header.contains(mouse) else { return }
        }
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
        cancelDropletSnap()
        pendingSnapOnExit = false
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

    /// 松手：只在靠近顶部时动画吸附；左右下三边不吸（容易和 Dock 冲突）。
    /// 顶部吸附保持当前水平位置，方便停在其他灵动岛软件旁边。
    private func endDrag() {
        isDragging = false
        guard let window = floatingWindow, let center = pillCenter,
              let screen = window.screen ?? targetScreen() else { return }

        var edges: DockEdges = []
        var target = center

        // 吸附只吃顶部：左右下三边容易和 Dock 冲突。水平位置保持不动，方便躲其他灵动岛。
        if UserDefaults.standard.bool(forKey: Constants.Island.alwaysSnapEnabledDefaultsKey) {
            // 必吸顶：不管松手时在哪都动画回顶部。
            edges = [.top]
            target.y = screen.frame.maxY - pillSize.height / 2
        } else {
            // 靠近顶部才吸。
            if screen.frame.maxY - center.y < Constants.Island.snapThreshold {
                edges = [.top]
                target.y = screen.frame.maxY - pillSize.height / 2
            }
        }

        dockEdges = edges
        pillCenter = target
        persistPosition()

        updateContentAlignment()
        let frame = windowFrame(forPillCenter: target)
        if edges.isEmpty {
            window.setFrame(frame, display: true)
        } else {
            startDropletSnap(to: frame, in: window)
        }
    }

    // MARK: - Droplet Snap（水滴入水吸附动画）

    /// 飞行中标志：View 层据此把胶囊沿运动方向拉长。
    @Published private(set) var snapFlying = false
    /// 触水信号：数值变化即触发一次压扁+果冻回弹（由 View 层执行形变动画）。
    @Published private(set) var jellyImpact = 0

    private var snapTimer: Timer?
    private var snapFromY: CGFloat = 0
    private var snapTargetFrame: NSRect = .zero
    private var snapStartTime: CFTimeInterval = 0
    private var jellyFired = false

    /// 吸附动画：back-out 缓动带小过冲，胶囊顶部短暂「潜入」屏幕边缘再回落；
    /// 飞行中 View 把胶囊拉长，接近水面时触发压扁回弹，合起来像水滴入水。
    /// 用 60Hz Timer 驱动逐帧动画（CADisplayLink 需 macOS 14，本项目最低 13）。
    private func startDropletSnap(to targetFrame: NSRect, in window: NSWindow) {
        cancelDropletSnap()
        let total = targetFrame.origin.y - window.frame.origin.y
        guard abs(total) > 1 else {
            window.setFrame(targetFrame, display: true)
            return
        }
        snapFromY = window.frame.origin.y
        snapTargetFrame = targetFrame
        snapStartTime = CACurrentMediaTime()
        jellyFired = false
        snapFlying = true
        let timer = Timer(timeInterval: 1.0 / 60.0, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.dropletTick()
            }
        }
        RunLoop.main.add(timer, forMode: .common)
        snapTimer = timer
    }

    private func cancelDropletSnap() {
        snapTimer?.invalidate()
        snapTimer = nil
        snapFlying = false
    }

    private func dropletTick() {
        guard let window = floatingWindow else {
            cancelDropletSnap()
            return
        }
        let raw = (CACurrentMediaTime() - snapStartTime) / Constants.Island.snapFlightDuration
        let t = CGFloat(min(max(raw, 0), 1))
        // back-out：f(t) = 1 + (s+1)(t-1)³ + s(t-1)²，t≈0.67 处到过冲峰值
        let s: CGFloat = 1.1
        let u = t - 1
        var p = 1 + (s + 1) * u * u * u + s * u * u
        // 过冲深度封顶，避免远距离拖动时潜入过深
        let total = snapTargetFrame.origin.y - snapFromY
        if total > 0, (p - 1) * total > Constants.Island.snapMaxOvershoot {
            p = 1 + Constants.Island.snapMaxOvershoot / total
        }
        var frame = snapTargetFrame
        frame.origin.y = snapFromY + total * p
        window.setFrame(frame, display: true)

        // 接近水面（78%）时触发压扁+回弹，与位置回落同步
        if !jellyFired, t >= 0.78 {
            jellyFired = true
            jellyImpact += 1
        }
        if raw >= 1 {
            window.setFrame(snapTargetFrame, display: true)
            cancelDropletSnap()
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
        #if DEBUG
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
        #endif
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
    var rightMouseDownHandler: ((NSEvent) -> Void)?

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

    // SwiftUI 视图不消费右键，事件沿响应链到这里，由 manager 弹菜单。
    override func rightMouseDown(with event: NSEvent) {
        rightMouseDownHandler?(event)
    }
}

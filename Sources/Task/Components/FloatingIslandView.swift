import SwiftUI
import AppKit

extension Notification.Name {
    static let showTaskSettings = Notification.Name("com.kuzen.task.showSettings")
}

struct FloatingIslandView: View {
    @ObservedObject var store: TaskStore
    @ObservedObject var manager: FloatingIslandManager
    @ObservedObject var calendarService: CalendarService
    var onSelectTask: (TaskItem) -> Void
    var onRequestFocus: (() -> Void)?

    @State private var newTaskTitle: String = ""
    @AppStorage("showTaskCountHeader") private var showTaskCountHeader: Bool = true
    @AppStorage("islandFreeMoveEnabled") private var islandFreeMoveEnabled: Bool = true
    @AppStorage("islandAlwaysSnapEnabled") private var islandAlwaysSnapEnabled: Bool = false
    @State private var calendarDays: [Date] = []
    @State private var selectedDate: Date = Date()
    @State private var stripCenterOffset: Int = 0
    /// 拖动排序中正在被拖的任务 id（onDrag 同步赋值，dropEntered 里实时换位要用）。
    @State private var draggingTaskID: UUID?
    /// 水滴吸附形变：飞行拉长 → 触水压扁 → 果冻回弹。jellyArmed 标记本次飞行以触水收尾，
    /// snapFlying 回落时不再重复复位形变。
    @State private var jellyX: CGFloat = 1
    @State private var jellyY: CGFloat = 1
    @State private var jellyArmed = false

    private var today: Date { Date() }
    private var calendar: Calendar { Calendar.current }
    private var islandShape: some Shape {
        if manager.isExpanded {
            return AnyShape(
                RoundedRectangle(cornerRadius: Constants.Island.expandedCornerRadius, style: .continuous)
            )
        } else {
            return AnyShape(
                RoundedRectangle(cornerRadius: Constants.Island.collapsedBottomCornerRadius, style: .continuous)
            )
        }
    }

    /// 内容在窗口内的对齐：窗口恒为展开大小，收起时只有对齐角落的胶囊可见。
    /// 顶部吸附/自由悬浮 → 顶部居中向下展开；底部吸附 → 底部向上展开；左/右吸附 → 从对应边缘向内展开。
    private var contentAlignment: Alignment {
        let horizontal: HorizontalAlignment
        switch manager.contentHorizontal {
        case .leading: horizontal = .leading
        case .center: horizontal = .center
        case .trailing: horizontal = .trailing
        }
        return Alignment(horizontal: horizontal, vertical: manager.contentAtBottom ? .bottom : .top)
    }

    var body: some View {
        ZStack {
            // 岛体投影：同一个圆角矩形「填充+模糊+偏移」垫在内容底下。
            // 必须放在 ZStack 内、.animation 之前——和内容同一个动画事务，
            // 否则投影不跟弹簧动画，展开时会岔成两个时间线。
            islandShape
                .fill(Color.black.opacity(Constants.Island.Shadow.bodyAmbientOpacity))
                .blur(radius: Constants.Island.Shadow.bodyAmbientRadius)
                .offset(y: Constants.Island.Shadow.bodyAmbientYOffset)
            islandShape
                .fill(Color.black.opacity(Constants.Island.Shadow.bodyTightOpacity))
                .blur(radius: Constants.Island.Shadow.bodyTightRadius)
                .offset(y: Constants.Island.Shadow.bodyTightYOffset)

            ZStack {
                Color.black

                if manager.isExpanded {
                    expandedContent
                        // 展开：等面板弹到 ~60% 再淡入内容，避免小胶囊里就挤出信息；
                        // 收起：内容快速淡出，不跟着面板一起被挤扁。
                        .transition(.asymmetric(
                            insertion: .opacity.animation(.easeIn(duration: 0.18).delay(0.24)),
                            removal: .opacity.animation(.easeOut(duration: 0.12))
                        ))
                } else {
                    collapsedContent
                        // 同理：收回到胶囊大小附近再显示胶囊内容，展开时立刻让位。
                        .transition(.asymmetric(
                            insertion: .opacity.animation(.easeIn(duration: 0.15).delay(0.28)),
                            removal: .opacity.animation(.easeOut(duration: 0.10))
                        ))
                }
            }
            .clipShape(islandShape)
            .overlay {
                // 日程临近提醒：胶囊发光脉冲（不展开、不抢焦点），悬停展开即已读。
                if manager.alertEvent != nil && !manager.isExpanded {
                    IslandPulseOverlay(cornerRadius: Constants.Island.collapsedBottomCornerRadius)
                }
            }
        }
        .frame(
            width: manager.isExpanded ? Constants.Island.expandedWidth : Constants.Island.collapsedWidth,
            height: manager.isExpanded ? manager.expandedHeight : Constants.Island.collapsedHeight
        )
        // 水滴吸附形变：锚点钉在接触面（吸顶时钉住顶边），只影响收起态胶囊的视觉。
        .scaleEffect(x: jellyX, y: jellyY, anchor: manager.contentAtBottom ? .bottom : .top)
        .animation(.spring(response: 0.42, dampingFraction: 0.8), value: manager.isExpanded)
        .animation(.spring(response: 0.38, dampingFraction: 0.8), value: manager.expandedHeight)
        // 窗口恒为「展开大小+投影边距」，内容按吸附边对齐后再四边内缩，留出投影渲染空间
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: contentAlignment)
        .padding(Constants.Island.shadowPadding)
        .ignoresSafeArea()
        .onAppear {
            stripCenterOffset = 0
            calendarDays = CalendarDayStrip.makeSevenDays(centeredOn: today)
            selectedDate = today
            calendarService.refreshAll(centeredOn: today)
        }
        .onChange(of: manager.isExpanded) { isExpanded in
            if isExpanded {
                stripCenterOffset = 0
                selectedDate = today
                calendarDays = CalendarDayStrip.makeSevenDays(centeredOn: today)
                calendarService.refreshAll(centeredOn: today)
                onRequestFocus?()
            } else {
                newTaskTitle = ""
                selectedDate = today
            }
        }
        .onChange(of: manager.snapFlying) { flying in
            if flying {
                // 飞行中：沿运动方向拉长，像水滴被水面吸住
                withAnimation(.easeIn(duration: 0.28)) { jellyX = 0.94; jellyY = 1.18 }
            } else if jellyArmed {
                // 本次飞行以触水收尾，形变由 jellyImpact 的回弹负责复位
                jellyArmed = false
            } else {
                // 飞行中断（还没触水又开拖）：直接回原形
                withAnimation(.easeOut(duration: 0.15)) { jellyX = 1; jellyY = 1 }
            }
        }
        .onChange(of: manager.jellyImpact) { _ in
            jellyArmed = true
            // 触水瞬间压扁，再果冻回弹
            withAnimation(.easeOut(duration: 0.07)) { jellyX = 1.22; jellyY = 0.78 }
            withAnimation(.spring(response: 0.55, dampingFraction: 0.35).delay(0.07)) { jellyX = 1; jellyY = 1 }
        }
        .onChange(of: selectedDate) { newDate in
            calendarService.refreshAll(centeredOn: newDate)
        }
    }

    // MARK: - Collapsed

    /// 收起态分级显示（模仿 Vibe Island：不展开也有信息量）：
    /// 日程提醒（橙色）> 1 小时内日程（蓝色倒计时）> 进行中任务 > 默认图标+任务数。
    private var collapsedContent: some View {
        TimelineView(.periodic(from: .now, by: 30)) { context in
            let now = context.date
            if let alert = manager.alertEvent {
                eventPillContent(alert, now: now, accent: .orange)
            } else if let event = nextEvent(at: now) {
                eventPillContent(event, now: now, accent: .blue)
            } else if let active = store.tasks.first(where: { $0.isActive && !$0.isCompleted }) {
                activeTaskPillContent(active)
            } else {
                defaultPillContent
            }
        }
    }

    /// 1 小时内将开始或正在进行中的最近一个日程。
    private func nextEvent(at now: Date) -> CalendarEvent? {
        calendarService.todayEvents.first(where: {
            !$0.isAllDay && $0.endDate > now && $0.startDate < now.addingTimeInterval(3600)
        })
    }

    private func eventPillContent(_ event: CalendarEvent, now: Date, accent: Color) -> some View {
        HStack(spacing: 6) {
            Circle()
                .fill(accent)
                .frame(width: 6, height: 6)

            Text(countdownText(for: event, at: now))
                .font(IslandStyles.bodyFont(size: 12, weight: .semibold))
                .foregroundColor(accent)
                .fixedSize()

            Text(event.title)
                .font(IslandStyles.bodyFont(size: 12, weight: .medium))
                .foregroundColor(.white.opacity(0.85))
                .lineLimit(1)
                .truncationMode(.tail)

            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(.horizontal, 12)
    }

    private func countdownText(for event: CalendarEvent, at now: Date) -> String {
        if event.startDate <= now && now < event.endDate {
            return "进行中"
        }
        let minutes = max(1, Int(ceil(event.startDate.timeIntervalSince(now) / 60)))
        return "\(minutes)分后"
    }

    private func activeTaskPillContent(_ task: TaskItem) -> some View {
        ZStack {
            // 不显示任务名：标题太长会顶爆胶囊布局，固定显示「工作中」，居中。
            Text("工作中")
                .font(IslandStyles.bodyFont(size: 12, weight: .medium))
                .foregroundColor(.white.opacity(0.85))
                .lineLimit(1)
                .fixedSize()

            HStack(spacing: 6) {
                ActivePillLogo()

                Spacer(minLength: 0)

                Text("\(store.activeTasks.count)")
                    .font(IslandStyles.bodyFont(size: 13, weight: .semibold))
                    .foregroundColor(IslandStyles.secondaryText)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(.horizontal, 12)
    }

    private var defaultPillContent: some View {
        HStack(spacing: 5) {
            PillLogo()

            Spacer()

            Text("\(store.activeTasks.count)")
                .font(IslandStyles.bodyFont(size: 13, weight: .semibold))
                .foregroundColor(.white)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(.horizontal, 12)
    }

    // MARK: - Expanded

    private var expandedContent: some View {
        let contentWidth = Constants.Island.expandedContentWidth
        return VStack(spacing: 0) {
            HStack(spacing: 0) {
                expandedHeader
                    .padding(.horizontal, 16)
                    .padding(.top, 18)
                    .padding(.bottom, 12)
                    .frame(width: contentWidth * 0.6)
                calendarHeader
                    .padding(.horizontal, 16)
                    .padding(.top, 18)
                    .padding(.bottom, 12)
                    .frame(width: contentWidth * 0.4)
            }

            HStack(spacing: 0) {
                leftBody
                    .frame(width: contentWidth * 0.6)

                rightBody
                    .frame(width: contentWidth * 0.4)
            }
            .frame(maxHeight: .infinity)
        }
        // 比面板窄一点并在面板内居中，两侧/底部留出呼吸空间
        .padding(.bottom, 12)
        .frame(width: contentWidth)
        .frame(maxHeight: .infinity)
    }

    // MARK: - Left Body (Stage + Tasks)

    /// 左栏上下分区：上 1/3 是 Logo 动画舞台，下 2/3 是任务列表 + 输入框。
    private var leftBody: some View {
        GeometryReader { geometry in
            VStack(spacing: 0) {
                LogoStageView(store: store)
                    .frame(height: geometry.size.height / 3)

                VStack(spacing: 0) {
                    taskList
                        .padding(.horizontal, 16)
                        .padding(.top, 10)
                        .frame(maxHeight: .infinity)

                    newTaskArea
                        .padding(.horizontal, 16)
                        .padding(.top, 10)
                        .padding(.bottom, 10)
                }
                .frame(height: geometry.size.height * 2 / 3)
            }
        }
    }

    private var expandedHeader: some View {
        HStack {
            if showTaskCountHeader {
                // 标题直接给信息量：剩余待办数。文字压暗，数字用蓝色保持醒目。
                (Text("当前待办事项还剩 ")
                    + Text("\(store.activeTasks.count)").foregroundColor(.blue)
                    + Text(" 条"))
                    .font(IslandStyles.titleFont(size: 16, weight: .bold))
                    .foregroundColor(.white.opacity(0.55))
            }

            Spacer()
        }
    }

    private var taskList: some View {
        GeometryReader { geometry in
            ScrollView(.vertical, showsIndicators: false) {
                let activeTasks = store.activeTasks
                VStack(spacing: 6) {
                    if activeTasks.isEmpty {
                        emptyState
                    } else {
                        ForEach(activeTasks) { task in
                            IslandTaskRow(
                                task: task,
                                isActive: task.isActive,
                                onToggle: { store.complete(task) },
                                onActivate: { onSelectTask(task) },
                                onDelete: { store.delete(task) }
                            )
                            .transition(.move(edge: .top).combined(with: .opacity))
                            .onDrag {
                                draggingTaskID = task.id
                                return NSItemProvider(object: task.id.uuidString as NSString)
                            }
                            .onDrop(of: ["public.text"], delegate: TaskReorderDropDelegate(
                                targetID: task.id,
                                store: store,
                                draggingID: $draggingTaskID
                            ))
                        }

                        // 列表末尾的拖放区：拖到这里实时排到最后。
                        Color.clear
                            .frame(height: 20)
                            .onDrop(of: ["public.text"], delegate: TaskReorderDropDelegate(
                                targetID: nil,
                                store: store,
                                draggingID: $draggingTaskID
                            ))
                    }
                }
                .frame(minHeight: activeTasks.isEmpty ? geometry.size.height : nil, alignment: .top)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var emptyState: some View {
        VStack(spacing: 0) {
            Spacer()

            VStack(spacing: 10) {
                Image(systemName: "checklist")
                    .font(.system(size: 24, weight: .medium))
                    .foregroundColor(IslandStyles.secondaryText)

                Text("还没有任务")
                    .font(IslandStyles.bodyFont(size: 14, weight: .medium))
                    .foregroundColor(IslandStyles.secondaryText)

                Text("在下方输入新任务")
                    .font(IslandStyles.bodyFont(size: 11, weight: .regular))
                    .foregroundColor(IslandStyles.tertiaryText)
            }

            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var newTaskArea: some View {
        HStack(spacing: 10) {
            IslandGlassInput(text: $newTaskTitle, placeholder: "新任务", onSubmit: addTask)

            if !newTaskTitle.isEmpty {
                Button(action: addTask) {
                    Text("添加")
                }
                .buttonStyle(IslandGlassButtonStyle())
                .transition(.scale.combined(with: .opacity))
            }
        }
    }

    // MARK: - Right Column (Calendar)

    private var rightBody: some View {
        VStack(spacing: 0) {
            calendarDayStrip
                .padding(.horizontal, 16)
                .padding(.top, 12)

            selectedDateHeader

            if calendarService.isAuthorized {
                eventList
                    .padding(.horizontal, 16)
                    .padding(.top, 8)
                    .padding(.bottom, 16)
                    .frame(maxHeight: .infinity)
            } else {
                calendarUnauthorizedState
                    .padding(.horizontal, 16)
                    .frame(maxHeight: .infinity)
            }
        }
    }

    private var calendarUnauthorizedState: some View {
        VStack(spacing: 8) {
            Image(systemName: "calendar.badge.exclamationmark")
                .font(.system(size: 24))
                .foregroundColor(IslandStyles.secondaryText)

            Text("点右上角齿轮关联日历")
                .font(IslandStyles.bodyFont(size: 13, weight: .medium))
                .foregroundColor(IslandStyles.secondaryText)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var selectedDateHeader: some View {
        HStack(spacing: 8) {
            Button(action: { shiftStrip(by: -1) }) {
                Image(systemName: "chevron.left")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundColor(IslandStyles.tertiaryText)
                    .frame(width: 20, height: 20)
                    .background(Color.white.opacity(0.06))
                    .clipShape(Circle())
            }
            .buttonStyle(.plain)

            Text(dateTitle(for: selectedDate))
                .font(IslandStyles.bodyFont(size: 12, weight: .medium))
                .foregroundColor(IslandStyles.secondaryText)

            Spacer()

            if calendarService.isAuthorized {
                Text("\(calendarService.selectedDateEvents.count) 个日程")
                    .font(IslandStyles.bodyFont(size: 11, weight: .regular))
                    .foregroundColor(IslandStyles.tertiaryText)
            }

            Button(action: { shiftStrip(by: 1) }) {
                Image(systemName: "chevron.right")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundColor(IslandStyles.tertiaryText)
                    .frame(width: 20, height: 20)
                    .background(Color.white.opacity(0.06))
                    .clipShape(Circle())
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 16)
        .padding(.top, 8)
    }

    private func shiftStrip(by days: Int) {
        stripCenterOffset += days
        let center = calendar.date(byAdding: .day, value: stripCenterOffset, to: today) ?? today
        let newDays = CalendarDayStrip.makeSevenDays(centeredOn: center)
        calendarDays = newDays
        selectedDate = newDays[3]
        calendarService.refreshAll(centeredOn: selectedDate)
    }

    /// 每次 body 重绘都 new DateFormatter 太贵，静态缓存一个。
    private static let dateTitleFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "M月d日 EEEE"
        formatter.locale = Locale(identifier: "zh_CN")
        return formatter
    }()

    private func dateTitle(for date: Date) -> String {
        Self.dateTitleFormatter.string(from: date)
    }

    private var calendarDayStrip: some View {
        CalendarDayStrip(
            days: calendarDays,
            today: today,
            selectedDate: $selectedDate,
            events: calendarService.stripEvents,
            onSelect: { date in
                calendarService.refreshSelectedDateEvents(date)
            }
        )
    }

    private var calendarHeader: some View {
        HStack(spacing: 8) {
            Spacer()

            // 自由移动（漂浮岛）快捷开关：开着可拖拽，关掉锁死。锁定时橙色提醒。
            Button { islandFreeMoveEnabled.toggle() } label: {
                Image(systemName: islandFreeMoveEnabled ? "lock.open" : "lock.fill")
            }
            .buttonStyle(IslandIconButtonStyle(
                color: islandFreeMoveEnabled ? IslandStyles.secondaryText : .orange,
                size: 13
            ))
            .help(islandFreeMoveEnabled ? "自由移动已开启，点击锁定岛" : "岛已锁定，点击解锁")

            // 吸附岛快捷开关：开着拖拽松手必吸顶部。蓝色=已开启。
            Button { islandAlwaysSnapEnabled.toggle() } label: {
                Image(systemName: "arrow.up.to.line")
            }
            .buttonStyle(IslandIconButtonStyle(
                color: islandAlwaysSnapEnabled ? .blue : IslandStyles.secondaryText,
                size: 13
            ))
            .help("总是吸附到顶部")
            .disabled(!islandFreeMoveEnabled)
            .opacity(islandFreeMoveEnabled ? 1 : 0.35)

            Button(action: openSettings) {
                Image(systemName: "gear")
            }
            .buttonStyle(IslandIconButtonStyle(size: 13))
        }
    }

    private var eventList: some View {
        EventListView(
            events: calendarService.selectedDateEvents,
            upcomingEvents: []
        )
    }

    // MARK: - Actions

    private func addTask() {
        if store.submitNewTask(newTaskTitle) {
            newTaskTitle = ""
        }
    }

    private func openSettings() {
        NotificationCenter.default.post(name: .showTaskSettings, object: nil)
    }
}

// MARK: - AnyShape Helper

/// 进行中任务的胶囊图标：小方块白脸持续左右摇摆（替代原来的绿色律动条）。
private struct ActivePillLogo: View {
    @State private var swaying = false

    var body: some View {
        IslandLogo(size: 13)
            .rotationEffect(.degrees(swaying ? 12 : -12))
            .onAppear {
                withAnimation(.easeInOut(duration: 0.45).repeatForever(autoreverses: true)) {
                    swaying = true
                }
            }
    }
}

/// 胶囊左边的小 Logo：收起（从大变回小）插入时「睁大」两下打招呼。
/// 注意：这个 Logo 只在没有计时任务时才会出现在胶囊上（计时中显示摇摆图标 + 任务名），
/// 所以出现即「没任务」，固定眨眼，不用再判断任务数。
private struct PillLogo: View {
    /// 没任务时的「睁大」：小尺寸下眨眼/压扁都看不出来，直接整体放大再缩回。
    @State private var widened = false

    var body: some View {
        IslandLogo(size: 13)
            .scaleEffect(widened ? 1.45 : 1.0)
            .onAppear {
                // 胶囊内容淡入有 ~0.28s 延迟，等显现后再开始；
                // 且 onAppear 里立刻 withAnimation 不生效，要延迟一拍。
                blink(times: 2, after: 0.4)
            }
    }

    private func blink(times: Int, after initialDelay: Double) {
        for index in 0..<times {
            let at = initialDelay + Double(index) * 0.4
            DispatchQueue.main.asyncAfter(deadline: .now() + at) {
                withAnimation(.spring(response: 0.25, dampingFraction: 0.6)) {
                    widened = true
                }
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + at + 0.22) {
                withAnimation(.spring(response: 0.25, dampingFraction: 0.7)) {
                    widened = false
                }
            }
        }
    }
}

/// 日程提醒的呼吸光圈（macOS 13 兼容的 repeatForever 动画）。
private struct IslandPulseOverlay: View {
    let cornerRadius: CGFloat
    @State private var glowing = false

    var body: some View {
        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
            .strokeBorder(Color.orange.opacity(glowing ? 0.15 : 0.85), lineWidth: 1.5)
            .shadow(color: Color.orange.opacity(glowing ? 0.15 : 0.55), radius: glowing ? 2 : 8)
            .onAppear {
                withAnimation(.easeInOut(duration: 0.9).repeatForever(autoreverses: true)) {
                    glowing = true
                }
            }
    }
}

/// 拖动排序代理：拖拽划过目标行时实时换位（跟手），而不是松手才换。
/// targetID 为 nil 表示列表末尾的拖放区。
private struct TaskReorderDropDelegate: DropDelegate {
    let targetID: UUID?
    let store: TaskStore
    @Binding var draggingID: UUID?

    func dropEntered(info: DropInfo) {
        guard let draggingID = draggingID else { return }
        withAnimation(.easeOut(duration: 0.15)) {
            if let targetID = targetID {
                guard draggingID != targetID else { return }
                store.moveTask(withID: draggingID, before: targetID)
            } else {
                store.moveTaskToEnd(withID: draggingID)
            }
        }
    }

    func dropUpdated(info: DropInfo) -> DropProposal? {
        DropProposal(operation: .move)
    }

    func performDrop(info: DropInfo) -> Bool {
        draggingID = nil
        return true
    }
}

struct AnyShape: Shape {
    private let path: @Sendable (CGRect) -> Path

    init<S: Shape>(_ shape: S) {
        self.path = { rect in shape.path(in: rect) }
    }

    func path(in rect: CGRect) -> Path {
        path(rect)
    }
}

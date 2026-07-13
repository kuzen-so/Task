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
    @State private var calendarDays: [Date] = []
    @State private var selectedDate: Date = Date()
    @State private var stripCenterOffset: Int = 0

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

    var body: some View {
        ZStack {
            Color.black
                .clipShape(islandShape)

            if manager.isExpanded {
                expandedContent
                    .transition(.opacity.animation(.easeInOut(duration: 0.2)))
            } else {
                collapsedContent
                    .transition(.opacity.animation(.easeInOut(duration: 0.15)))
            }
        }
        .frame(
            width: manager.isExpanded ? Constants.Island.expandedWidth : Constants.Island.collapsedWidth,
            height: manager.isExpanded ? manager.expandedHeight : Constants.Island.collapsedHeight
        )
        .animation(.spring(response: 0.42, dampingFraction: 0.8), value: manager.isExpanded)
        .animation(.spring(response: 0.38, dampingFraction: 0.8), value: manager.expandedHeight)
        .clipShape(islandShape)
        // 窗口已经是展开大小，内容靠顶部对齐，模拟从屏幕顶部向下展开
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
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
        .onChange(of: selectedDate) { newDate in
            calendarService.refreshAll(centeredOn: newDate)
        }
    }

    // MARK: - Collapsed

    private var collapsedContent: some View {
        HStack(spacing: 5) {
            Image(systemName: "dice.fill")
                .font(.system(size: 12, weight: .semibold))
                .foregroundColor(.white)

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
        VStack(spacing: 0) {
            HStack(spacing: 0) {
                expandedHeader
                    .padding(.horizontal, 20)
                    .padding(.top, 18)
                    .padding(.bottom, 12)
                    .frame(width: Constants.Island.expandedWidth * 0.6)
                calendarHeader
                    .padding(.horizontal, 16)
                    .padding(.top, 18)
                    .padding(.bottom, 12)
                    .frame(width: Constants.Island.expandedWidth * 0.4)
            }

            HStack(spacing: 0) {
                leftBody
                    .frame(width: Constants.Island.expandedWidth * 0.6)

                rightBody
                    .frame(width: Constants.Island.expandedWidth * 0.4)
            }
            .frame(maxHeight: .infinity)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Left Body (Tasks)

    private var leftBody: some View {
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
    }

    private var expandedHeader: some View {
        HStack {
            HStack(spacing: 8) {
                Image(systemName: "dice.fill")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundColor(.white)

                Text("Task")
                    .font(IslandStyles.titleFont(size: 16, weight: .bold))
                    .foregroundColor(.white)
            }

            Spacer()
        }
    }

    private var taskList: some View {
        ScrollView(.vertical, showsIndicators: false) {
            VStack(spacing: 6) {
                let activeTasks = store.activeTasks

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
                    }
                }
            }
            .padding(.vertical, 4)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var emptyState: some View {
        VStack(spacing: 10) {
            Image(systemName: "checklist")
                .font(.system(size: 28, weight: .medium))
                .foregroundColor(IslandStyles.secondaryText)

            Text("还没有任务")
                .font(IslandStyles.bodyFont(size: 14, weight: .medium))
                .foregroundColor(IslandStyles.secondaryText)

            Text("在下方输入新任务")
                .font(IslandStyles.bodyFont(size: 11, weight: .regular))
                .foregroundColor(IslandStyles.tertiaryText)
        }
        .frame(maxWidth: .infinity, minHeight: Constants.Island.emptyStateHeight)
        .frame(maxHeight: .infinity)
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

            eventList
                .padding(.horizontal, 16)
                .padding(.top, 8)
                .padding(.bottom, 16)
                .frame(maxHeight: .infinity)

            calendarFooter
                .padding(.horizontal, 16)
                .padding(.bottom, 14)
        }
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

            if calendar.isDate(selectedDate, inSameDayAs: today) {
                Text("今天")
                    .font(IslandStyles.bodyFont(size: 11, weight: .semibold))
                    .foregroundColor(.blue)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(Color.blue.opacity(0.12))
                    .cornerRadius(4)
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

    private func dateTitle(for date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "M月d日 EEEE"
        formatter.locale = Locale(identifier: "zh_CN")
        return formatter.string(from: date)
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
        HStack {
            Spacer()

            Button(action: openSettings) {
                Image(systemName: "gear")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(IslandStyles.secondaryText)
                    .frame(width: 26, height: 26)
                    .background(Color.white.opacity(0.06))
                    .clipShape(Circle())
            }
            .buttonStyle(.plain)
        }
    }

    private var eventList: some View {
        EventListView(
            events: calendarService.selectedDateEvents,
            upcomingEvents: []
        )
    }

    private var calendarFooter: some View {
        HStack {
            Spacer()

            if !calendarService.isAuthorized {
                Text("点击右上角按钮关联日历")
                    .font(IslandStyles.bodyFont(size: 11))
                    .foregroundColor(IslandStyles.tertiaryText)
            } else {
                Text("\(calendarService.selectedDateEvents.count) 个日程")
                    .font(IslandStyles.bodyFont(size: 11))
                    .foregroundColor(IslandStyles.tertiaryText)
            }
        }
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

struct AnyShape: Shape {
    private let path: @Sendable (CGRect) -> Path

    init<S: Shape>(_ shape: S) {
        self.path = { rect in shape.path(in: rect) }
    }

    func path(in rect: CGRect) -> Path {
        path(rect)
    }
}

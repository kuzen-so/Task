import SwiftUI
import AppKit
import ServiceManagement


struct SettingsView: View {
    @ObservedObject var taskStore: TaskStore
    @ObservedObject var remindersService: RemindersService
    @ObservedObject var calendarService: CalendarService
    @StateObject private var launchManager = LaunchAtLoginManager.shared

    @AppStorage("taskHighlightStyle") private var highlightStyle: TaskHighlightStyle = .leftBar
    @AppStorage("taskCheckboxStyle") private var checkboxStyle: TaskCheckboxStyle = .circle
    @AppStorage("remindersAutoSyncEnabled") private var remindersAutoSyncEnabled: Bool = true
    @AppStorage("remindersSyncIntervalSeconds") private var remindersSyncIntervalSeconds: Double = 900.0
    @AppStorage("islandTopDockSide") private var islandTopDockSide: String = "center"
    @AppStorage("islandEventAlertEnabled") private var islandEventAlertEnabled: Bool = true
    @AppStorage("islandFreeMoveEnabled") private var islandFreeMoveEnabled: Bool = true
    @AppStorage("islandAlwaysSnapEnabled") private var islandAlwaysSnapEnabled: Bool = false
    @AppStorage("showTaskCountHeader") private var showTaskCountHeader: Bool = true
    @AppStorage("soundEffectsEnabled") private var soundEffectsEnabled: Bool = true

    private var launchToggleBinding: Binding<Bool> {
        Binding(
            get: { launchManager.isEnabled },
            set: { newValue in
                launchManager.setEnabled(newValue)
            }
        )
    }

    private var syncIntervalOptions: [(label: String, value: Double)] {
        [
            ("1 分钟", 60),
            ("5 分钟", 300),
            ("15 分钟", 900),
            ("1 小时", 3600)
        ]
    }

    /// 版本号只维护 build_app.sh 一处，这里从 Bundle 读。
    private var appVersion: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "未知"
    }

    var body: some View {
        Form {
            Section("通用") {
                Toggle("开机自启动", isOn: launchToggleBinding)

                Toggle("操作音效（添加/完成/删除）", isOn: $soundEffectsEnabled)

                if launchManager.status == .requiresApproval {
                    HStack(alignment: .top, spacing: 8) {
                        Image(systemName: "exclamationmark.triangle")
                            .foregroundColor(.orange)
                        VStack(alignment: .leading, spacing: 4) {
                            Text("需要在「系统设置 → 通用 → 登录项」中允许 Task 自动启动。")
                                .font(.caption)
                                .foregroundColor(.secondary)
                            Button("打开系统设置") {
                                SMAppService.openSystemSettingsLoginItems()
                            }
                            .buttonStyle(.plain)
                            .font(.caption)
                            .foregroundColor(.accentColor)
                        }
                    }
                }

                if let error = launchManager.lastError {
                    Text(error)
                        .font(.caption)
                        .foregroundColor(.red)
                }
            }

            Section("灵动岛") {
                Picker("顶部停靠位置", selection: $islandTopDockSide) {
                    Text("居中").tag("center")
                    Text("刘海左侧").tag("left")
                    Text("刘海右侧").tag("right")
                }
                .pickerStyle(.segmented)
                .onChange(of: islandTopDockSide) { _ in
                    NotificationCenter.default.post(name: .islandTopDockSideChanged, object: nil)
                }

                Toggle("自由移动（漂浮岛）", isOn: $islandFreeMoveEnabled)

                Toggle("总是吸附到顶部", isOn: $islandAlwaysSnapEnabled)
                    .disabled(!islandFreeMoveEnabled)

                Toggle("日程临近时发光提醒", isOn: $islandEventAlertEnabled)

                Toggle("显示待办总数（面板左上角标题）", isOn: $showTaskCountHeader)

                Text("关闭自由移动后岛固定在原地不可拖动；开启吸附后拖拽松手必吸到顶部。和其他灵动岛软件（如 Vibe Island）同时使用时，可把停靠位置改到刘海一侧避让。")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            Section("任务外观") {
                Picker("高亮样式", selection: $highlightStyle) {
                    ForEach(TaskHighlightStyle.allCases) { style in
                        Text(style.title).tag(style)
                    }
                }

                Picker("复选框样式", selection: $checkboxStyle) {
                    ForEach(TaskCheckboxStyle.allCases) { style in
                        Text(style.title).tag(style)
                    }
                }
                .pickerStyle(.segmented)
            }

            Section("日历") {
                permissionRow(
                    name: "日历",
                    isAuthorized: calendarService.isAuthorized
                ) {
                    let granted = await calendarService.requestAccess()
                    if granted {
                        calendarService.refreshAvailableCalendars()
                        calendarService.refreshAll(centeredOn: Date())
                    }
                    return granted
                }

                if calendarService.isAuthorized {
                    Button("立即刷新日程") {
                        calendarService.refreshAll(centeredOn: Date())
                    }

                    if !calendarService.availableCalendarNames.isEmpty {
                        Text("显示日历")
                            .font(.caption)
                            .foregroundColor(.secondary)

                        ScrollView(.vertical, showsIndicators: true) {
                            VStack(alignment: .leading, spacing: 6) {
                                ForEach(calendarService.availableCalendarNames, id: \.self) { name in
                                    Toggle(name, isOn: Binding(
                                        get: { !calendarService.hiddenCalendarNames.contains(name) },
                                        set: { isOn in
                                            if isOn {
                                                calendarService.showCalendar(named: name)
                                            } else {
                                                calendarService.hideCalendar(named: name)
                                            }
                                            calendarService.refreshAll(centeredOn: Date())
                                        }
                                    ))
                                }
                            }
                        }
                        .frame(height: min(CGFloat(calendarService.availableCalendarNames.count) * 24 + 8, 120))
                    }
                }
            }

            Section("提醒事项") {
                permissionRow(
                    name: "提醒事项",
                    isAuthorized: remindersService.isAuthorized
                ) {
                    let granted = await remindersService.requestAccess()
                    if granted {
                        taskStore.syncReminders()
                    }
                    return granted
                }

                if remindersService.isAuthorized {
                    Toggle("自动同步", isOn: $remindersAutoSyncEnabled)
                        .onChange(of: remindersAutoSyncEnabled) { _ in
                            taskStore.updateRemindersSyncTimer()
                        }

                    Picker("同步频率", selection: $remindersSyncIntervalSeconds) {
                        ForEach(syncIntervalOptions, id: \.value) { option in
                            Text(option.label).tag(option.value)
                        }
                    }
                    .pickerStyle(.segmented)
                    .onChange(of: remindersSyncIntervalSeconds) { _ in
                        taskStore.updateRemindersSyncTimer()
                    }

                    Button("立即同步") {
                        taskStore.syncReminders()
                    }

                    Text("外部变更会即时同步（EventKit 通知），这里的频率只是兜底轮询。权限在「系统设置 → 隐私与安全性 → 提醒事项」中管理。")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }

            Section("关于") {
                HStack {
                    Text("版本")
                    Spacer()
                    Text(appVersion)
                        .foregroundColor(.secondary)
                }
            }
        }
        .formStyle(.grouped)
        .scrollIndicators(.hidden)
        // 必须给显式宽度：没有固有尺寸时，AppKit 会把窗口缩成标题栏大小。
        .frame(width: 440)
        .onAppear {
            // 只刷新本地已授权状态，不在这里自动弹权限框——权限请求必须由用户点按钮发起。
            calendarService.updateAuthorizationStatus()
            remindersService.updateAuthorizationStatus()
            calendarService.refreshAvailableCalendars()
        }
    }

    /// 统一的权限状态行：已授权显示绿勾；未授权显示「请求权限」按钮，被拒后弹系统设置引导。
    @ViewBuilder
    private func permissionRow(
        name: String,
        isAuthorized: Bool,
        request: @escaping () async -> Bool
    ) -> some View {
        HStack(spacing: 6) {
            if isAuthorized {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundColor(.green)
                Text("已授权")
                    .foregroundColor(.secondary)
            } else {
                Image(systemName: "exclamationmark.circle")
                    .foregroundColor(.secondary)
                Text("未授权")
                    .foregroundColor(.secondary)

                Spacer()

                Button("请求权限") {
                    Task { @MainActor in
                        let granted = await request()
                        if !granted {
                            showAuthDeniedAlert(for: name)
                        }
                    }
                }
                .controlSize(.small)
            }
        }
    }

    private func showAuthDeniedAlert(for appName: String) {
        let alert = NSAlert()
        alert.messageText = "未获得访问权限"
        alert.informativeText = "需要到系统设置 → 隐私与安全性 → \(appName) 中允许 Task 访问。"
        alert.alertStyle = .warning
        alert.addButton(withTitle: "去设置")
        alert.addButton(withTitle: "取消")

        let response = alert.runModal()
        if response == .alertFirstButtonReturn {
            let pane = appName == "提醒事项" ? "Privacy_Reminders" : "Privacy_Calendars"
            let urls = [
                URL(string: "x-apple.systempreferences:com.apple.preference.security?\(pane)"),
                URL(string: "x-apple.systempreferences:com.apple.settings.PrivacySecurity.extension"),
                URL(string: "x-apple.systempreferences:com.apple.Settings.PrivacySecurity.extension"),
                URL(string: "x-apple.systempreferences:com.apple.preference.security")
            ]
            for url in urls.compactMap({ $0 }) {
                if NSWorkspace.shared.open(url) {
                    break
                }
            }
        }
    }
}

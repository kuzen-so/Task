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
    @AppStorage("remindersSyncIntervalSeconds") private var remindersSyncIntervalSeconds: Double = 60.0
    @AppStorage("islandTopDockSide") private var islandTopDockSide: String = "center"
    @AppStorage("islandEventAlertEnabled") private var islandEventAlertEnabled: Bool = true

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
            ("30 秒", 30),
            ("1 分钟", 60),
            ("5 分钟", 300),
            ("15 分钟", 900)
        ]
    }

    var body: some View {
        Form {
            Section(header: Text("通用").font(.headline)) {
                Toggle("开机自启动", isOn: launchToggleBinding)

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
                    .padding(.top, 4)
                }

                if let error = launchManager.lastError {
                    Text(error)
                        .font(.caption)
                        .foregroundColor(.red)
                        .padding(.top, 4)
                }
            }
            .padding(.vertical, 8)

            Section(header: Text("灵动岛").font(.headline)) {
                Picker("顶部停靠位置", selection: $islandTopDockSide) {
                    Text("居中").tag("center")
                    Text("刘海左侧").tag("left")
                    Text("刘海右侧").tag("right")
                }
                .pickerStyle(.segmented)
                .onChange(of: islandTopDockSide) { _ in
                    NotificationCenter.default.post(name: .islandTopDockSideChanged, object: nil)
                }

                Toggle("日程临近时发光提醒", isOn: $islandEventAlertEnabled)

                Text("和其他灵动岛软件（如 Vibe Island）同时使用时，可把停靠位置改到刘海一侧避让。")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            .padding(.vertical, 8)

            Section(header: Text("任务外观").font(.headline)) {
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
            .padding(.vertical, 8)

            Section(header: Text("日历").font(.headline)) {
                HStack {
                    Text(calendarService.isAuthorized ? "已授权" : "未授权")
                        .foregroundColor(.secondary)
                    Spacer()
                    Button("读取日历") {
                        Task { @MainActor in
                            if calendarService.isAuthorized {
                                calendarService.refreshAll(centeredOn: Date())
                            } else {
                                let granted = await calendarService.requestAccess()
                                if granted {
                                    calendarService.refreshAvailableCalendars()
                                    calendarService.refreshAll(centeredOn: Date())
                                } else {
                                    showAuthDeniedAlert(for: "日历")
                                }
                            }
                        }
                    }
                }

                if !calendarService.availableCalendarNames.isEmpty {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("显示日历")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                            .padding(.top, 4)

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
            .padding(.vertical, 8)
            .onAppear {
                calendarService.refreshAvailableCalendars()
                if !calendarService.isAuthorized {
                    Task { @MainActor in
                        _ = await calendarService.requestAccess()
                        calendarService.refreshAvailableCalendars()
                        calendarService.refreshAll(centeredOn: Date())
                    }
                }
            }

            Section(header: Text("提醒事项").font(.headline)) {
                HStack {
                    Text(remindersService.isAuthorized ? "已授权" : "未授权")
                        .foregroundColor(remindersService.isAuthorized ? .green : .secondary)
                    Spacer()
                    Button("请求权限") {
                        Task { @MainActor in
                            let granted = await remindersService.requestAccess()
                            if granted {
                                taskStore.syncReminders()
                            } else {
                                showAuthDeniedAlert(for: "提醒事项")
                            }
                        }
                    }
                }

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
                .disabled(!remindersService.isAuthorized)

                Text("权限在「系统设置 → 隐私与安全性 → 提醒事项」中管理。")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            .padding(.vertical, 8)
            .onAppear {
                if !remindersService.isAuthorized {
                    Task { @MainActor in
                        let granted = await remindersService.requestAccess()
                        if granted {
                            taskStore.syncReminders()
                        }
                    }
                }
            }

            Section(header: Text("关于").font(.headline)) {
                HStack {
                    Text("版本")
                    Spacer()
                    Text("1.5.0")
                        .foregroundColor(.secondary)
                }
            }
            .padding(.vertical, 8)

            Section {
                Button("退出 Task") {
                    NSApplication.shared.terminate(nil)
                }
                .buttonStyle(.borderless)
                .foregroundColor(.red)
            }
            .padding(.vertical, 8)
        }
        .padding()
        .frame(width: 340)
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

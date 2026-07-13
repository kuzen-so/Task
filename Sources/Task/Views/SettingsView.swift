import SwiftUI
import AppKit

struct SettingsView: View {
    @ObservedObject var calendarService: CalendarService
    @StateObject private var launchManager = LaunchAtLoginManager.shared
    @State private var isOn: Bool = false

    @AppStorage("taskHighlightStyle") private var highlightStyle: TaskHighlightStyle = .leftBar
    @AppStorage("taskCheckboxStyle") private var checkboxStyle: TaskCheckboxStyle = .circle

    var body: some View {
        Form {
            Section(header: Text("通用").font(.headline)) {
                Toggle("开机自启动", isOn: $isOn)
                    .onChange(of: isOn) { newValue in
                        Task { @MainActor in
                            if newValue != launchManager.isEnabled {
                                await launchManager.toggle()
                                isOn = launchManager.isEnabled
                            }
                        }
                    }
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

            Section(header: Text("关于").font(.headline)) {
                HStack {
                    Text("版本")
                    Spacer()
                    Text("1.2.0")
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
        .frame(width: 340, height: 460)
        .onAppear {
            isOn = launchManager.isEnabled
        }
    }

    private func showAuthDeniedAlert(for appName: String) {
        let alert = NSAlert()
        alert.messageText = "未获得自动化权限"
        alert.informativeText = "需要到系统设置 → 隐私与安全性 → 自动化 中允许 Task 控制「\(appName)」。"
        alert.alertStyle = .warning
        alert.addButton(withTitle: "去设置")
        alert.addButton(withTitle: "取消")

        let response = alert.runModal()
        if response == .alertFirstButtonReturn {
            let urls = [
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

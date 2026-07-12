import SwiftUI
import AppKit

struct StatusBarMenuView: View {
    @ObservedObject var calendarService: CalendarService
    var onOpenSettings: () -> Void
    var onQuit: () -> Void

    @State private var currentMonth = Date()

    private let calendar = Calendar.current
    private let monthFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy 年 M 月"
        return formatter
    }()

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Button(action: previousMonth) {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundColor(IslandStyles.secondaryText)
                }
                .buttonStyle(.plain)

                Spacer()

                Text(monthFormatter.string(from: currentMonth))
                    .font(IslandStyles.titleFont(size: 14, weight: .bold))
                    .foregroundColor(.white)

                Spacer()

                Button(action: nextMonth) {
                    Image(systemName: "chevron.right")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundColor(IslandStyles.secondaryText)
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 12)
            .padding(.top, 12)
            .padding(.bottom, 10)

            Divider()
                .overlay(IslandStyles.dividerColor)
                .padding(.horizontal, 12)

            // Calendar
            MonthCalendarView(
                currentMonth: $currentMonth,
                today: Date(),
                events: calendarService.upcomingEvents
            )
            .padding(.horizontal, 8)
            .padding(.vertical, 10)

            Divider()
                .overlay(IslandStyles.dividerColor)
                .padding(.horizontal, 12)

            // Upcoming events
            UpcomingEventsList(events: calendarService.upcomingEvents)
                .padding(.top, 10)
                .frame(maxHeight: .infinity)

            // Toolbar
            HStack {
                Button(action: onOpenSettings) {
                    Image(systemName: "gear")
                        .font(.system(size: 14))
                        .foregroundColor(IslandStyles.secondaryText)
                }
                .buttonStyle(.plain)

                Spacer()

                Button(action: { calendarService.refreshAll(centeredOn: Date()) }) {
                    Image(systemName: "arrow.clockwise")
                        .font(.system(size: 14))
                        .foregroundColor(IslandStyles.secondaryText)
                }
                .buttonStyle(.plain)

                Spacer()

                Button(action: onQuit) {
                    Image(systemName: "power")
                        .font(.system(size: 14))
                        .foregroundColor(Color.red.opacity(0.8))
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
        }
        .frame(width: Constants.statusBarPopoverWidth, height: Constants.statusBarPopoverHeight)
        .background(Color(white: 0.10))
        .onAppear {
            calendarService.refreshAll(centeredOn: Date())
        }
    }

    private func previousMonth() {
        if let date = calendar.date(byAdding: .month, value: -1, to: currentMonth) {
            currentMonth = date
        }
    }

    private func nextMonth() {
        if let date = calendar.date(byAdding: .month, value: 1, to: currentMonth) {
            currentMonth = date
        }
    }
}

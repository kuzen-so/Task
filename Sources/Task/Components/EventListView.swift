import SwiftUI

struct EventListView: View {
    let events: [CalendarEvent]
    let upcomingEvents: [CalendarEvent]

    var body: some View {
        VStack(spacing: 0) {
            if events.isEmpty {
                if upcomingEvents.isEmpty {
                    emptyState
                } else {
                    upcomingList
                }
            } else {
                ScrollView(.vertical, showsIndicators: false) {
                    VStack(spacing: 6) {
                        ForEach(events) { event in
                            EventRow(event: event)
                        }
                    }
                    .padding(.vertical, 4)
                }
            }
        }
    }

    private var emptyState: some View {
        VStack(spacing: 8) {
            Image(systemName: "calendar.badge.clock")
                .font(.system(size: 24))
                .foregroundColor(IslandStyles.secondaryText)

            Text("当天没有日程")
                .font(IslandStyles.bodyFont(size: 13, weight: .medium))
                .foregroundColor(IslandStyles.secondaryText)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var upcomingList: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("即将到来")
                .font(IslandStyles.bodyFont(size: 11, weight: .semibold))
                .foregroundColor(IslandStyles.tertiaryText)
                .padding(.horizontal, 10)

            ScrollView(.vertical, showsIndicators: false) {
                VStack(spacing: 6) {
                    ForEach(upcomingEvents.prefix(5)) { event in
                        EventRow(event: event)
                    }
                }
                .padding(.vertical, 4)
            }
        }
    }
}

/// 单条日程：左侧 3px 蓝细条（与任务行左侧语言一致），无卡片底，hover 才出底。
private struct EventRow: View {
    let event: CalendarEvent
    @State private var isHovered = false

    private static let timeFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm"
        return formatter
    }()

    var body: some View {
        HStack(spacing: 10) {
            RoundedRectangle(cornerRadius: 1.5, style: .continuous)
                .fill(Color.blue)
                .frame(width: 3, height: 28)

            VStack(alignment: .leading, spacing: 3) {
                Text(event.title)
                    .font(IslandStyles.bodyFont(size: 13, weight: .medium))
                    .foregroundColor(.white)
                    .lineLimit(1)

                Text(timeString(for: event))
                    .font(IslandStyles.bodyFont(size: 11, weight: .regular))
                    .foregroundColor(IslandStyles.tertiaryText)
            }

            Spacer(minLength: 0)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(isHovered ? Color.white.opacity(0.05) : Color.clear)
        )
        .onHover { hovering in
            isHovered = hovering
        }
        .animation(.easeOut(duration: 0.15), value: isHovered)
    }

    private func timeString(for event: CalendarEvent) -> String {
        if event.isAllDay {
            return "全天"
        }
        let dateText = DateFormatter.localizedString(from: event.startDate, dateStyle: .short, timeStyle: .none)
        return "\(dateText) \(Self.timeFormatter.string(from: event.startDate)) – \(Self.timeFormatter.string(from: event.endDate))"
    }
}

import SwiftUI

struct UpcomingEventsList: View {
    let events: [CalendarEvent]

    private let dateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "MM/dd"
        return formatter
    }()

    private let timeFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm"
        return formatter
    }()

    private let weekdayFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "EEE"
        return formatter
    }()

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("即将到来")
                .font(IslandStyles.titleFont(size: 12, weight: .semibold))
                .foregroundColor(IslandStyles.secondaryText)
                .padding(.horizontal, 12)
                .padding(.bottom, 8)

            if events.isEmpty {
                Text("暂无 upcoming 日程")
                    .font(IslandStyles.bodyFont(size: 12))
                    .foregroundColor(IslandStyles.tertiaryText)
                    .padding(.horizontal, 12)
            } else {
                ScrollView(.vertical, showsIndicators: false) {
                    VStack(spacing: 8) {
                        ForEach(events.prefix(10)) { event in
                            eventRow(event)
                        }
                    }
                    .padding(.horizontal, 12)
                }
            }
        }
    }

    private func eventRow(_ event: CalendarEvent) -> some View {
        HStack(spacing: 10) {
            VStack(spacing: 2) {
                Text(weekdayFormatter.string(from: event.startDate))
                    .font(IslandStyles.bodyFont(size: 10, weight: .medium))
                    .foregroundColor(IslandStyles.tertiaryText)

                Text(dateFormatter.string(from: event.startDate))
                    .font(IslandStyles.bodyFont(size: 12, weight: .bold))
                    .foregroundColor(.white)
            }
            .frame(width: 36)

            RoundedRectangle(cornerRadius: 2, style: .continuous)
                .fill(Color.orange)
                .frame(width: 3)

            VStack(alignment: .leading, spacing: 2) {
                Text(event.title)
                    .font(IslandStyles.bodyFont(size: 12, weight: .medium))
                    .foregroundColor(.white)
                    .lineLimit(1)

                Text(timeString(for: event))
                    .font(IslandStyles.bodyFont(size: 10))
                    .foregroundColor(IslandStyles.tertiaryText)
            }

            Spacer(minLength: 0)
        }
        .padding(.vertical, 6)
    }

    private func timeString(for event: CalendarEvent) -> String {
        if event.isAllDay {
            return "全天"
        }
        return "\(timeFormatter.string(from: event.startDate)) – \(timeFormatter.string(from: event.endDate))"
    }
}

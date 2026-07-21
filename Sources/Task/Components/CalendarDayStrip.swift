import SwiftUI

struct CalendarDayStrip: View {
    let days: [Date]
    let today: Date
    @Binding var selectedDate: Date
    var events: [CalendarEvent] = []
    var onSelect: ((Date) -> Void)? = nil

    private let calendar = Calendar.current

    var body: some View {
        HStack(spacing: 8) {
            ForEach(days, id: \.self) { day in
                dayCell(for: day)
            }
        }
    }

    private func dayCell(for day: Date) -> some View {
        let isToday = calendar.isDate(day, inSameDayAs: today)
        let isSelected = calendar.isDate(day, inSameDayAs: selectedDate)
        let weekday = calendar.shortWeekdaySymbols[calendar.component(.weekday, from: day) - 1]
        let dayNumber = calendar.component(.day, from: day)
        let hasEvents = events.contains {
            let eventStart = calendar.startOfDay(for: $0.startDate)
            let eventEnd = calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: $0.endDate)) ?? $0.endDate
            let dayStart = calendar.startOfDay(for: day)
            let dayEnd = calendar.date(byAdding: .day, value: 1, to: dayStart) ?? dayStart
            return eventStart < dayEnd && eventEnd > dayStart
        }

        return Button(action: {
            withAnimation(.easeOut(duration: 0.15)) {
                selectedDate = day
            }
            onSelect?(day)
        }) {
            VStack(spacing: 4) {
                Text(weekday)
                    .font(IslandStyles.bodyFont(size: 10, weight: .medium))
                    .foregroundColor(isToday ? .white : IslandStyles.tertiaryText)

                Text("\(dayNumber)")
                    .font(IslandStyles.titleFont(size: 15, weight: .bold))
                    .foregroundColor(isToday ? .white : (isSelected ? .white : IslandStyles.secondaryText))

                if hasEvents {
                    Circle()
                        .fill(isToday ? Color.white : Color.blue)
                        .frame(width: 4, height: 4)
                } else {
                    Color.clear.frame(width: 4, height: 4)
                }
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 8)
            .background(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(isToday ? Color.blue : (isSelected ? Color.white.opacity(0.12) : Color.clear))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .stroke(isToday ? Color.blue.opacity(0.5) : (isSelected ? Color.white.opacity(0.18) : Color.white.opacity(0.06)), lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
    }
}

extension CalendarDayStrip {
    static func makeFiveDays(centeredOn date: Date, calendar: Calendar = .current) -> [Date] {
        let start = calendar.date(byAdding: .day, value: -2, to: date) ?? date
        return (0..<5).compactMap { offset in
            calendar.date(byAdding: .day, value: offset, to: start)
        }
    }

    static func makeSevenDays(centeredOn date: Date, calendar: Calendar = .current) -> [Date] {
        let start = calendar.date(byAdding: .day, value: -3, to: date) ?? date
        return (0..<7).compactMap { offset in
            calendar.date(byAdding: .day, value: offset, to: start)
        }
    }
}

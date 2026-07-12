import SwiftUI

struct MonthCalendarView: View {
    @Binding var currentMonth: Date
    let today: Date
    let events: [CalendarEvent]

    private let calendar = Calendar.current
    private let weekdaySymbols = Calendar.current.shortWeekdaySymbols

    var body: some View {
        VStack(spacing: 10) {
            weekdayHeader

            LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 7), spacing: 6) {
                ForEach(daysForMonth(), id: \.self) { dayItem in
                    dayCell(dayItem)
                }
            }
        }
    }

    private var weekdayHeader: some View {
        HStack {
            ForEach(weekdaySymbols, id: \.self) { symbol in
                Text(symbol)
                    .font(IslandStyles.bodyFont(size: 10, weight: .medium))
                    .foregroundColor(IslandStyles.tertiaryText)
                    .frame(maxWidth: .infinity)
            }
        }
    }

    private func dayCell(_ item: DayItem) -> some View {
        let isToday = calendar.isDate(item.date, inSameDayAs: today)
        let isCurrentMonth = item.isCurrentMonth
        let hasEvents = events.contains { calendar.isDate($0.startDate, inSameDayAs: item.date) }

        return VStack(spacing: 2) {
            Text("\(calendar.component(.day, from: item.date))")
                .font(IslandStyles.bodyFont(size: 12, weight: isToday ? .bold : .medium))
                .foregroundColor(isToday ? .white : (isCurrentMonth ? .white : IslandStyles.tertiaryText))
                .frame(width: 26, height: 26)
                .background(
                    Circle()
                        .fill(isToday ? Color.blue : Color.clear)
                )

            if hasEvents {
                Circle()
                    .fill(Color.orange)
                    .frame(width: 4, height: 4)
            } else {
                Circle()
                    .fill(Color.clear)
                    .frame(width: 4, height: 4)
            }
        }
        .frame(height: 36)
        .contentShape(Rectangle())
        .onTapGesture {
            currentMonth = item.date
        }
    }

    private func daysForMonth() -> [DayItem] {
        guard let monthInterval = calendar.dateInterval(of: .month, for: currentMonth) else { return [] }

        let firstDayOfMonth = monthInterval.start
        let firstWeekday = calendar.component(.weekday, from: firstDayOfMonth)
        let offset = firstWeekday - calendar.firstWeekday
        let adjustedOffset = (offset + 7) % 7

        var days: [DayItem] = []

        // Previous month padding
        for i in 0..<adjustedOffset {
            if let date = calendar.date(byAdding: .day, value: -(adjustedOffset - i), to: firstDayOfMonth) {
                days.append(DayItem(date: date, isCurrentMonth: false))
            }
        }

        // Current month
        var date = firstDayOfMonth
        while date < monthInterval.end {
            days.append(DayItem(date: date, isCurrentMonth: true))
            guard let next = calendar.date(byAdding: .day, value: 1, to: date) else { break }
            date = next
        }

        // Next month padding to fill 6 rows (42 cells)
        let remaining = 42 - days.count
        if remaining > 0, let lastDate = days.last?.date {
            for i in 1...remaining {
                if let date = calendar.date(byAdding: .day, value: i, to: lastDate) {
                    days.append(DayItem(date: date, isCurrentMonth: false))
                }
            }
        }

        return days
    }
}

private struct DayItem: Hashable {
    let date: Date
    let isCurrentMonth: Bool

    func hash(into hasher: inout Hasher) {
        hasher.combine(date)
    }

    static func == (lhs: DayItem, rhs: DayItem) -> Bool {
        lhs.date == rhs.date
    }
}

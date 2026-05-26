// Symtrace — Co-created by Mason × AI.

import SwiftUI

/// One calendar month: title + weekday header row + day grid. Leading nil
/// padding lines the first day up under its actual weekday column.
struct MonthView: View {
    let monthStart: Date
    let entriesByKey: [String: DailyEntry]
    let onTapDay: (Date) -> Void

    private static let columns: [GridItem] = Array(
        repeating: GridItem(.flexible(), spacing: 4),
        count: 7
    )

    /// Locale-aware short weekday symbols, rotated so the first column matches
    /// `Calendar.firstWeekday` (Sunday in en_US, Monday in many EU locales).
    private static let weekdayHeaders: [String] = {
        let cal = Calendar.current
        let symbols = cal.veryShortStandaloneWeekdaySymbols
        let firstIndex = cal.firstWeekday - 1
        return Array(symbols[firstIndex...] + symbols[..<firstIndex])
    }()

    private var monthTitle: String {
        monthStart.formatted(.dateTime.year().month(.wide))
    }

    private var paddedDays: [Date?] {
        let cal = Calendar.current
        let firstWeekday = cal.component(.weekday, from: monthStart)
        let leadingPadding = (firstWeekday - cal.firstWeekday + 7) % 7
        guard let range = cal.range(of: .day, in: .month, for: monthStart) else { return [] }

        var days: [Date?] = Array(repeating: nil, count: leadingPadding)
        for offset in 0..<range.count {
            days.append(cal.date(byAdding: .day, value: offset, to: monthStart))
        }
        return days
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(monthTitle)
                .font(.title3.bold())
                .padding(.horizontal, 16)

            LazyVGrid(columns: Self.columns, spacing: 4) {
                ForEach(0..<Self.weekdayHeaders.count, id: \.self) { index in
                    Text(Self.weekdayHeaders[index])
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity)
                        .accessibilityHidden(true)
                }

                ForEach(0..<paddedDays.count, id: \.self) { index in
                    if let day = paddedDays[index] {
                        let key = DailyEntry.dayKey(for: day)
                        DayCell(
                            day: day,
                            entry: entriesByKey[key],
                            isToday: Calendar.current.isDateInToday(day),
                            isFuture: day > Date(),
                            onTap: { onTapDay(day) }
                        )
                    } else {
                        Color.clear
                            .aspectRatio(1, contentMode: .fit)
                    }
                }
            }
            .padding(.horizontal, 16)
        }
    }
}

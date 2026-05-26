// Symtrace — Co-created by Mason × AI.

import SwiftUI

/// Single calendar cell. Colored square + day number, optional ring for
/// today. Future days render dimmed and disabled — no logs ever exist there.
struct DayCell: View {
    let day: Date
    let entry: DailyEntry?
    let isToday: Bool
    let isFuture: Bool
    let onTap: () -> Void

    private var dayNumber: Int {
        Calendar.current.component(.day, from: day)
    }

    private var maxSeverity: Int? {
        SymptomDayColor.maxSeverity(for: entry)
    }

    var body: some View {
        Button(action: onTap) {
            ZStack {
                RoundedRectangle(cornerRadius: 8)
                    .fill(SymptomDayColor.color(forMaxSeverity: maxSeverity))

                if isToday {
                    RoundedRectangle(cornerRadius: 8)
                        .strokeBorder(Color.accentColor, lineWidth: 2)
                }

                Text("\(dayNumber)")
                    .font(.callout.weight(.medium))
                    .foregroundStyle(SymptomDayColor.textColor(forMaxSeverity: maxSeverity))
            }
            .aspectRatio(1, contentMode: .fit)
            .opacity(isFuture ? 0.35 : 1)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(isFuture)
        .accessibilityLabel(accessibilityLabel)
    }

    private var accessibilityLabel: String {
        let dateText = day.formatted(.dateTime.weekday(.wide).month().day())
        let severityText = SymptomDayColor.severityLabel(maxSeverity)
        return "\(dateText), \(severityText)"
    }
}

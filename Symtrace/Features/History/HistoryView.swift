// Symtrace — Co-created by Mason × AI.

import SwiftUI
import SwiftData

/// History root: vertical stack of months, newest first, with a color legend
/// pinned at the bottom. Tapping any past or current day opens the day-detail
/// sheet (read-only in this slice; Edit comes in a later phase).
struct HistoryView: View {
    @Environment(\.modelContext) private var modelContext
    let goToToday: () -> Void

    @Query(sort: [SortDescriptor(\DailyEntry.date, order: .reverse)])
    private var entries: [DailyEntry]

    @State private var selectedDay: SelectedDay?

    private var entriesByKey: [String: DailyEntry] {
        // `dayKey` is logically unique, but there's no schema-level constraint
        // (no `@Attribute(.unique)` on `DailyEntry.dayKey` yet — deferred until
        // we have a one-shot dedup migration to pair with it). If duplicates
        // ever slip in via a sync conflict, a regression, or a stray insert,
        // crash in debug so we notice, but keep the most recently updated
        // entry in release so users don't get a fatal launch on bad data.
        Dictionary(entries.map { ($0.dayKey, $0) }, uniquingKeysWith: { a, b in
            assertionFailure("Duplicate DailyEntry for dayKey \(a.dayKey): \(a.id) vs \(b.id)")
            return a.updatedAt >= b.updatedAt ? a : b
        })
    }

    /// Months to render, newest first. Always shows current month plus at
    /// least 2 prior months so the calendar feels populated on day one.
    private var visibleMonths: [Date] {
        let cal = Calendar.current
        let now = Date()
        let currentMonth = cal.startOfMonth(now)
        let earliestEntry = entries.last?.date ?? now
        let earliestEntryMonth = cal.startOfMonth(earliestEntry)
        let twoMonthsBack = cal.date(byAdding: .month, value: -2, to: currentMonth) ?? currentMonth
        let startMonth = min(earliestEntryMonth, twoMonthsBack)

        var months: [Date] = []
        var cursor = currentMonth
        while cursor >= startMonth {
            months.append(cursor)
            guard let previous = cal.date(byAdding: .month, value: -1, to: cursor) else { break }
            cursor = previous
        }
        return months
    }

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 24) {
                ForEach(visibleMonths, id: \.self) { monthStart in
                    MonthView(
                        monthStart: monthStart,
                        entriesByKey: entriesByKey,
                        onTapDay: { day in
                            if Calendar.current.isDateInToday(day) {
                                goToToday()
                            } else {
                                selectedDay = SelectedDay(date: day)
                            }
                        }
                    )
                }

                LegendView()
                    .padding(.horizontal, 16)
                    .padding(.top, 8)
            }
            .padding(.vertical, 16)
        }
        .navigationTitle("History")
        .navigationBarTitleDisplayMode(.inline)
        .sheet(item: $selectedDay) { selection in
            DayDetailView(date: selection.date)
                .presentationDetents([.large])
        }
    }
}

private struct SelectedDay: Identifiable, Equatable {
    let date: Date
    var id: String { DailyEntry.dayKey(for: date) }
}

// MARK: - Legend

private struct LegendView: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Color = highest symptom severity that day")
                .font(.footnote)
                .foregroundStyle(.secondary)
            HStack(spacing: 10) {
                LegendChip(severity: nil, label: "—")
                LegendChip(severity: 0, label: "0")
                LegendChip(severity: 1, label: "1")
                LegendChip(severity: 2, label: "2")
                LegendChip(severity: 3, label: "3")
                LegendChip(severity: 4, label: "4")
            }
        }
    }
}

private struct LegendChip: View {
    let severity: Int?
    let label: String

    var body: some View {
        VStack(spacing: 2) {
            RoundedRectangle(cornerRadius: 4)
                .fill(SymptomDayColor.color(forMaxSeverity: severity))
                .frame(width: 24, height: 24)
            Text(label)
                .font(.caption2)
                .foregroundStyle(.secondary)
                .monospacedDigit()
        }
    }
}

// MARK: - Calendar utility

private extension Calendar {
    func startOfMonth(_ date: Date) -> Date {
        let components = self.dateComponents([.year, .month], from: date)
        return self.date(from: components) ?? date
    }
}

#Preview {
    NavigationStack {
        HistoryView(goToToday: {})
    }
    .modelContainer(for: [
        SymptomDefinition.self,
        TriggerDefinition.self,
        Medication.self,
        DailyEntry.self,
        SymptomLog.self,
        MedicationLog.self,
        TriggerValue.self,
    ], inMemory: true)
}

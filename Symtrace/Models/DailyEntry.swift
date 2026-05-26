// Symtrace — Co-created by Mason × AI.

import Foundation
import SwiftData

/// Optional overall day rating. Logged separately from individual symptoms.
enum DayRating: String, Codable, CaseIterable, Identifiable {
    case bad, ok, good
    var id: String { rawValue }

    var label: String {
        switch self {
        case .bad: return "Bad"
        case .ok: return "OK"
        case .good: return "Good"
        }
    }
}

/// One per calendar day. Aggregates the day's logs and optional context
/// (sleep, day rating, free-text note). Looked up by `dayKey` ("yyyy-MM-dd").
@Model
final class DailyEntry {
    var id: UUID = UUID()
    var dayKey: String = ""
    var date: Date = Date()
    var sleepHours: Double? = nil
    var dayRatingRaw: String? = nil
    var note: String? = nil
    var createdAt: Date = Date()
    var updatedAt: Date = Date()

    @Relationship(deleteRule: .cascade, inverse: \SymptomLog.entry)
    var symptomLogs: [SymptomLog]? = []
    @Relationship(deleteRule: .cascade, inverse: \MedicationLog.entry)
    var medicationLogs: [MedicationLog]? = []
    @Relationship(deleteRule: .cascade, inverse: \TriggerValue.entry)
    var triggerValues: [TriggerValue]? = []

    init(
        id: UUID = UUID(),
        date: Date = Date(),
        sleepHours: Double? = nil,
        dayRating: DayRating? = nil,
        note: String? = nil,
        createdAt: Date = Date(),
        updatedAt: Date = Date()
    ) {
        let startOfDay = Calendar.current.startOfDay(for: date)
        self.id = id
        self.dayKey = DailyEntry.dayKey(for: startOfDay)
        self.date = startOfDay
        self.sleepHours = sleepHours
        self.dayRatingRaw = dayRating?.rawValue
        self.note = note
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }

    var dayRating: DayRating? {
        get { dayRatingRaw.flatMap(DayRating.init(rawValue:)) }
        set { dayRatingRaw = newValue?.rawValue }
    }

    /// Single source of truth for "is there real data for this day?" — drives
    /// calendar coloring, the day-detail sheet's empty state, and (later) the
    /// doctor PDF/CSV export filter. Without this, the calendar and sheet can
    /// disagree (e.g. green cell that opens to "Nothing logged"), and exports
    /// silently include opened-but-unlogged days as fake "good" days.
    ///
    /// Severity-0 logs do not count: lazy creation means logs only exist when
    /// the user actually moved a slider, so a stray 0 should never persist.
    /// The `severity > 0` guard is kept as defense-in-depth.
    var hasContent: Bool {
        if dayRating != nil { return true }
        if sleepHours != nil { return true }
        if let logs = symptomLogs, logs.contains(where: { $0.severity > 0 }) { return true }
        if let triggers = triggerValues, triggers.contains(where: { $0.value > 0 }) { return true }
        if let meds = medicationLogs, !meds.isEmpty { return true }
        if let note, !note.isEmpty { return true }
        return false
    }

    /// Stable per-day key, locale-independent ("2026-05-24"). Used for upsert lookups.
    static func dayKey(for date: Date) -> String {
        let cal = Calendar.current
        let comps = cal.dateComponents([.year, .month, .day], from: date)
        let y = comps.year ?? 0
        let m = comps.month ?? 0
        let d = comps.day ?? 0
        return String(format: "%04d-%02d-%02d", y, m, d)
    }
}

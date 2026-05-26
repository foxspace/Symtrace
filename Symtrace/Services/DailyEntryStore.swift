// Symtrace — Co-created by Mason × AI.

import Foundation
import SwiftData

/// All Today-screen and past-day writes go through this struct so save and
/// upsert semantics stay consistent.
///
/// Lazy creation invariant: nothing materializes until the user actually
/// changes a value.
/// - `DailyEntry` is created on first write (via `entry(for:)` /
///   `todayEntry()`), not on view load. Read paths use `existingEntry(for:)`.
/// - `SymptomLog` and `TriggerValue` are created on first non-zero write and
///   deleted when the user dials them back to zero. A symptom with no log on
///   a given day is indistinguishable from severity 0.
@MainActor
struct DailyEntryStore {
    let context: ModelContext

    // MARK: Daily entries (read)

    /// Today's entry if it exists. Does not create.
    func existingTodayEntry() throws -> DailyEntry? {
        let startOfToday = Calendar.current.startOfDay(for: Date())
        return try existingEntry(forDayStartingAt: startOfToday)
    }

    /// Entry for an arbitrary calendar date if it exists. Does not create.
    func existingEntry(for date: Date) throws -> DailyEntry? {
        let startOfDay = Calendar.current.startOfDay(for: date)
        return try existingEntry(forDayStartingAt: startOfDay)
    }

    /// Yesterday's entry if it exists. Used by "Same as yesterday".
    func yesterdayEntry() throws -> DailyEntry? {
        guard let yesterday = Calendar.current.date(byAdding: .day, value: -1, to: Date()) else {
            return nil
        }
        let startOfYesterday = Calendar.current.startOfDay(for: yesterday)
        return try existingEntry(forDayStartingAt: startOfYesterday)
    }

    private func existingEntry(forDayStartingAt startOfDay: Date) throws -> DailyEntry? {
        let key = DailyEntry.dayKey(for: startOfDay)
        var descriptor = FetchDescriptor<DailyEntry>(
            predicate: #Predicate { $0.dayKey == key }
        )
        descriptor.fetchLimit = 1
        return try context.fetch(descriptor).first
    }

    // MARK: Daily entries (create-on-miss)

    /// Today's `DailyEntry`, creating it if missing. Use only from write paths
    /// (form materialization, quick actions) — never from view load.
    func todayEntry() throws -> DailyEntry {
        let startOfToday = Calendar.current.startOfDay(for: Date())
        return try entry(forDayStartingAt: startOfToday)
    }

    /// `DailyEntry` for an arbitrary calendar date, creating it if missing.
    /// Use only from write paths.
    func entry(for date: Date) throws -> DailyEntry {
        let startOfDay = Calendar.current.startOfDay(for: date)
        return try entry(forDayStartingAt: startOfDay)
    }

    private func entry(forDayStartingAt startOfDay: Date) throws -> DailyEntry {
        if let existing = try existingEntry(forDayStartingAt: startOfDay) {
            return existing
        }
        let new = DailyEntry(date: startOfDay)
        context.insert(new)
        try context.save()
        return new
    }

    // MARK: Per-symptom / per-trigger upsert (lazy)

    /// Set a symptom's severity for a day.
    /// - Severity 0 deletes any existing log (no log = no symptom).
    /// - Non-zero updates the existing log or creates a new one.
    /// Returns the log if one exists after the call, else nil.
    @discardableResult
    func setSymptomSeverity(
        _ severity: Int,
        for symptom: SymptomDefinition,
        on entry: DailyEntry
    ) -> SymptomLog? {
        let symptomID = symptom.id
        let existing = entry.symptomLogs?.first(where: { $0.symptom?.id == symptomID })

        if severity == 0 {
            if let existing { context.delete(existing) }
            return nil
        }

        if let existing {
            existing.severity = severity
            existing.updatedAt = Date()
            return existing
        }

        let log = SymptomLog(severity: severity, entry: entry, symptom: symptom)
        context.insert(log)
        return log
    }

    /// Set a trigger's value for a day.
    /// - Value 0 deletes any existing record.
    /// - Non-zero updates the existing value or creates a new one.
    @discardableResult
    func setTriggerValue(
        _ value: Double,
        for trigger: TriggerDefinition,
        on entry: DailyEntry
    ) -> TriggerValue? {
        let triggerID = trigger.id
        let existing = entry.triggerValues?.first(where: { $0.trigger?.id == triggerID })

        if value == 0 {
            if let existing { context.delete(existing) }
            return nil
        }

        if let existing {
            existing.value = value
            existing.updatedAt = Date()
            return existing
        }

        let new = TriggerValue(value: value, entry: entry, trigger: trigger)
        context.insert(new)
        return new
    }

    // MARK: Quick actions

    /// Copy yesterday's day rating, sleep, and any *real* (>0) symptom and
    /// trigger entries into today. Notes are intentionally not copied — they
    /// describe a specific day and shouldn't carry forward silently.
    func copyYesterdayToToday() throws {
        guard let yesterday = try yesterdayEntry(), yesterday.hasContent else { return }
        let today = try todayEntry()

        today.sleepHours = yesterday.sleepHours
        today.dayRatingRaw = yesterday.dayRatingRaw

        for log in yesterday.symptomLogs ?? [] {
            guard let symptom = log.symptom, !symptom.isArchived else { continue }
            guard log.severity > 0 else { continue }
            setSymptomSeverity(log.severity, for: symptom, on: today)
        }
        for value in yesterday.triggerValues ?? [] {
            guard let trigger = value.trigger, !trigger.isArchived else { continue }
            guard value.value > 0 else { continue }
            setTriggerValue(value.value, for: trigger, on: today)
        }
        today.updatedAt = Date()
        try context.save()
    }

    /// "Feeling fine today" — single-tap path that marks the day as good and
    /// removes any existing symptom logs (no symptoms = no log rows). Sleep and
    /// triggers are left untouched so the user keeps existing values.
    func quickLogFeelingFine() throws {
        let today = try todayEntry()
        today.dayRating = .good

        for log in today.symptomLogs ?? [] {
            context.delete(log)
        }
        today.updatedAt = Date()
        try context.save()
    }

    // MARK: Delete

    /// Remove a `DailyEntry` and — via SwiftData's cascade rule — every
    /// `SymptomLog`, `TriggerValue`, and `MedicationLog` attached to it.
    /// Routed through the store so the daily-entry write surface stays uniform
    /// (every other mutation goes through here too) and so v3 sync has a single
    /// place to add tombstone semantics later.
    func deleteEntry(_ entry: DailyEntry) throws {
        context.delete(entry)
        try context.save()
    }

    // MARK: Save

    func save() {
        do { try context.save() } catch {
            assertionFailure("Save failed: \(error)")
        }
    }
}

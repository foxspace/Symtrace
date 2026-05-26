// Symtrace — Co-created by Mason × AI.

import SwiftUI
import SwiftData

/// Day detail / editor for a single calendar day.
///
/// Replaces the previous read-only `DayDetailSheet` + form-based
/// `EditEntryView` split. Editing happens *in place*: each row shows the
/// current value (or "—" if not logged) and tapping it opens a focused sheet
/// for that one field. This matches the user's mental model for past-day
/// editing — "fix this one thing about Tuesday" — far better than re-opening
/// today's form with all defaults pre-filled.
///
/// Lazy creation invariant carries over: opening the view never persists
/// anything. Each commit helper calls `materializeEntry()` which creates the
/// `DailyEntry` on first write. Editing a non-zero value back to 0 deletes
/// the underlying `SymptomLog` / `TriggerValue` (via `DailyEntryStore`).
///
/// `@Query` keeps the view reactive — after each edit sheet commits, the
/// query's prediate re-evaluates and the row re-renders with the new value.
struct DayDetailView: View {
    let date: Date

    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext

    @Query private var entries: [DailyEntry]

    @Query(
        filter: #Predicate<SymptomDefinition> { $0.isActive && !$0.isArchived },
        sort: [SortDescriptor(\SymptomDefinition.sortOrder)]
    )
    private var activeSymptoms: [SymptomDefinition]

    @Query(
        filter: #Predicate<TriggerDefinition> { $0.isActive && !$0.isArchived },
        sort: [SortDescriptor(\TriggerDefinition.sortOrder)]
    )
    private var activeTriggers: [TriggerDefinition]

    @State private var editTarget: EditTarget?
    @State private var showingDeleteConfirmation = false

    init(date: Date) {
        self.date = date
        let key = DailyEntry.dayKey(for: date)
        var descriptor = FetchDescriptor<DailyEntry>(
            predicate: #Predicate { $0.dayKey == key }
        )
        descriptor.fetchLimit = 1
        _entries = Query(descriptor)
    }

    private var entry: DailyEntry? { entries.first }
    private var store: DailyEntryStore { DailyEntryStore(context: modelContext) }

    var body: some View {
        NavigationStack {
            List {
                contextSection
                if !activeSymptoms.isEmpty { symptomsSection }
                if !activeTriggers.isEmpty { triggersSection }
                noteSection
                if entry != nil { deleteSection }
            }
            .navigationTitle(formattedDate)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                        .fontWeight(.semibold)
                }
            }
            .sheet(item: $editTarget) { target in
                editSheet(for: target)
            }
            .confirmationDialog(
                "Delete this day's entry?",
                isPresented: $showingDeleteConfirmation,
                titleVisibility: .visible
            ) {
                Button("Delete", role: .destructive, action: deleteEntry)
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("Removes the day rating, sleep, symptoms, triggers, and note for this day. The calendar cell will go back to gray.")
            }
        }
    }

    // MARK: - Sections

    private var contextSection: some View {
        Section("How's your day?") {
            DetailRow(label: "Day rating",
                      value: entry?.dayRating?.label ?? "—",
                      hasValue: entry?.dayRating != nil) {
                editTarget = .dayRating
            }
            DetailRow(label: "Sleep",
                      value: sleepDisplay,
                      hasValue: entry?.sleepHours != nil,
                      monospacedValue: true) {
                editTarget = .sleep
            }
        }
    }

    private var symptomsSection: some View {
        Section("Symptoms") {
            ForEach(activeSymptoms) { symptom in
                let value = severity(for: symptom)
                SymptomRow(
                    symptom: symptom,
                    severity: value,
                    onTap: { editTarget = .symptom(symptom) }
                )
                .swipeActions(edge: .trailing) {
                    if value > 0 {
                        Button("Remove", role: .destructive) {
                            commitSymptomSeverity(0, for: symptom)
                        }
                    }
                }
            }
        }
    }

    private var triggersSection: some View {
        Section("Triggers") {
            ForEach(activeTriggers) { trigger in
                let value = triggerValue(for: trigger)
                TriggerRow(
                    trigger: trigger,
                    value: value,
                    onTap: { editTarget = .trigger(trigger) }
                )
                .swipeActions(edge: .trailing) {
                    if value > 0 {
                        Button("Remove", role: .destructive) {
                            commitTriggerValue(0, for: trigger)
                        }
                    }
                }
            }
        }
    }

    private var noteSection: some View {
        Section("Note") {
            Button {
                editTarget = .note
            } label: {
                Group {
                    if let note = entry?.note, !note.isEmpty {
                        Text(note)
                            .foregroundStyle(.primary)
                            .lineLimit(4)
                            .multilineTextAlignment(.leading)
                    } else {
                        Text("Tap to add a note")
                            .foregroundStyle(.secondary)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        }
    }

    private var deleteSection: some View {
        Section {
            Button(role: .destructive) {
                showingDeleteConfirmation = true
            } label: {
                HStack {
                    Spacer()
                    Label("Delete this day's entry", systemImage: "trash")
                    Spacer()
                }
            }
        }
    }

    // MARK: - Edit sheet routing

    @ViewBuilder
    private func editSheet(for target: EditTarget) -> some View {
        switch target {
        case .dayRating:
            DayRatingEditSheet(initial: entry?.dayRating, onCommit: commitDayRating)
        case .sleep:
            SleepEditSheet(initial: entry?.sleepHours, onCommit: commitSleep)
        case .symptom(let symptom):
            SymptomEditSheet(
                symptom: symptom,
                initial: severity(for: symptom),
                onCommit: { commitSymptomSeverity($0, for: symptom) }
            )
        case .trigger(let trigger):
            TriggerEditSheet(
                trigger: trigger,
                initial: triggerValue(for: trigger),
                onCommit: { commitTriggerValue($0, for: trigger) }
            )
        case .note:
            NoteEditSheet(initial: entry?.note ?? "", onCommit: commitNote)
        }
    }

    // MARK: - Commit helpers

    /// Returns the entry, creating one if it doesn't exist yet. Called from
    /// every commit helper so writes only ever materialize on real edits.
    private func materializeEntry() -> DailyEntry {
        if let entry { return entry }
        do {
            return try store.entry(for: date)
        } catch {
            assertionFailure("materializeEntry failed: \(error)")
            return DailyEntry(date: date)
        }
    }

    private func commitDayRating(_ rating: DayRating?) {
        // Don't materialize a fresh entry just to write nil → nil.
        if entry == nil, rating == nil { return }
        let e = materializeEntry()
        e.dayRating = rating
        e.updatedAt = Date()
        store.save()
    }

    private func commitSleep(_ hours: Double?) {
        if entry == nil, hours == nil { return }
        let e = materializeEntry()
        e.sleepHours = hours
        e.updatedAt = Date()
        store.save()
    }

    private func commitSymptomSeverity(_ severity: Int, for symptom: SymptomDefinition) {
        if entry == nil, severity == 0 { return }
        let e = materializeEntry()
        store.setSymptomSeverity(severity, for: symptom, on: e)
        e.updatedAt = Date()
        store.save()
    }

    private func commitTriggerValue(_ value: Double, for trigger: TriggerDefinition) {
        if entry == nil, value == 0 { return }
        let e = materializeEntry()
        store.setTriggerValue(value, for: trigger, on: e)
        e.updatedAt = Date()
        store.save()
    }

    private func commitNote(_ text: String) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        let value: String? = trimmed.isEmpty ? nil : text
        if entry == nil, value == nil { return }
        let e = materializeEntry()
        e.note = value
        e.updatedAt = Date()
        store.save()
    }

    private func deleteEntry() {
        guard let entry else { return }
        do {
            try store.deleteEntry(entry)
        } catch {
            assertionFailure("Delete failed: \(error)")
            return
        }
        // Auto-dismiss back to History — matches iOS convention for
        // post-delete navigation (Reminders, Mail, Notes all dismiss the
        // detail view). The calendar cell will re-color gray immediately
        // via @Query, confirming the deletion.
        dismiss()
    }

    // MARK: - Lookups

    private func severity(for symptom: SymptomDefinition) -> Int {
        let symptomID = symptom.id
        return entry?.symptomLogs?
            .first(where: { $0.symptom?.id == symptomID })?
            .severity ?? 0
    }

    private func triggerValue(for trigger: TriggerDefinition) -> Double {
        let triggerID = trigger.id
        return entry?.triggerValues?
            .first(where: { $0.trigger?.id == triggerID })?
            .value ?? 0
    }

    private var sleepDisplay: String {
        guard let hours = entry?.sleepHours else { return "—" }
        return String(format: "%.1f h", hours)
    }

    private var formattedDate: String {
        date.formatted(.dateTime.weekday(.wide).month(.wide).day().year())
    }
}

// MARK: - Edit target

/// Identifies which field the per-row sheet is currently editing. `Identifiable`
/// + `.sheet(item:)` gives us automatic dismiss when the binding goes nil.
private enum EditTarget: Identifiable {
    case dayRating
    case sleep
    case symptom(SymptomDefinition)
    case trigger(TriggerDefinition)
    case note

    var id: String {
        switch self {
        case .dayRating: return "dayRating"
        case .sleep: return "sleep"
        case .symptom(let s): return "symptom-\(s.id.uuidString)"
        case .trigger(let t): return "trigger-\(t.id.uuidString)"
        case .note: return "note"
        }
    }
}

// MARK: - Rows

/// Generic label + value row used for Day rating, Sleep, and any other
/// single-value field. `.contentShape(Rectangle())` makes the entire row
/// — including the label side — a single tap target, which is the standard
/// iOS Settings pattern for tappable list rows.
private struct DetailRow: View {
    let label: String
    let value: String
    let hasValue: Bool
    var monospacedValue: Bool = false
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            HStack {
                Text(label)
                    .foregroundStyle(.primary)
                Spacer()
                if monospacedValue {
                    Text(value)
                        .monospacedDigit()
                        .foregroundStyle(hasValue ? .primary : .secondary)
                } else {
                    Text(value)
                        .foregroundStyle(hasValue ? .primary : .secondary)
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

private struct SymptomRow: View {
    let symptom: SymptomDefinition
    let severity: Int
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            HStack {
                Text(symptom.name)
                    .foregroundStyle(.primary)
                Spacer()
                if severity > 0 {
                    Text("\(severity)/4")
                        .monospacedDigit()
                        .foregroundStyle(.primary)
                        .fontWeight(.medium)
                } else {
                    Text("—")
                        .foregroundStyle(.secondary)
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(severity > 0
            ? "\(symptom.name), severity \(severity) of 4"
            : "\(symptom.name), not logged")
        .accessibilityHint("Double tap to change.")
    }
}

private struct TriggerRow: View {
    let trigger: TriggerDefinition
    let value: Double
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            HStack {
                Text(trigger.name)
                    .foregroundStyle(.primary)
                Spacer()
                if value > 0 {
                    Text("\(Int(value))/10")
                        .monospacedDigit()
                        .foregroundStyle(.primary)
                        .fontWeight(.medium)
                } else {
                    Text("—")
                        .foregroundStyle(.secondary)
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(value > 0
            ? "\(trigger.name), level \(Int(value)) of 10"
            : "\(trigger.name), not logged")
        .accessibilityHint("Double tap to change.")
    }
}

// MARK: - Edit sheets

private struct DayRatingEditSheet: View {
    let initial: DayRating?
    let onCommit: (DayRating?) -> Void

    @State private var selection: DayRating?
    @Environment(\.dismiss) private var dismiss

    init(initial: DayRating?, onCommit: @escaping (DayRating?) -> Void) {
        self.initial = initial
        self.onCommit = onCommit
        self._selection = State(initialValue: initial)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Picker("Day rating", selection: $selection) {
                        Text("—").tag(DayRating?.none)
                        ForEach(DayRating.allCases) { rating in
                            Text(rating.label).tag(DayRating?.some(rating))
                        }
                    }
                    .pickerStyle(.inline)
                    .labelsHidden()
                }
            }
            .navigationTitle("Day rating")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Save") {
                        onCommit(selection)
                        dismiss()
                    }
                    .fontWeight(.semibold)
                }
            }
        }
        .presentationDetents([.medium])
    }
}

private struct SleepEditSheet: View {
    let initial: Double?
    let onCommit: (Double?) -> Void

    @State private var hours: Double
    @Environment(\.dismiss) private var dismiss

    init(initial: Double?, onCommit: @escaping (Double?) -> Void) {
        self.initial = initial
        self.onCommit = onCommit
        self._hours = State(initialValue: initial ?? 7.5)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Stepper(value: $hours, in: 0...14, step: 0.5) {
                        HStack {
                            Text("Hours")
                            Spacer()
                            Text(String(format: "%.1f h", hours))
                                .monospacedDigit()
                                .foregroundStyle(.secondary)
                        }
                    }
                }
                if initial != nil {
                    Section {
                        Button("Clear", role: .destructive) {
                            onCommit(nil)
                            dismiss()
                        }
                    }
                }
            }
            .navigationTitle("Sleep")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Save") {
                        onCommit(hours)
                        dismiss()
                    }
                    .fontWeight(.semibold)
                }
            }
        }
        .presentationDetents([.medium])
    }
}

private struct SymptomEditSheet: View {
    let symptom: SymptomDefinition
    let initial: Int
    let onCommit: (Int) -> Void

    @State private var severity: Int
    @Environment(\.dismiss) private var dismiss

    init(symptom: SymptomDefinition, initial: Int, onCommit: @escaping (Int) -> Void) {
        self.symptom = symptom
        self.initial = initial
        self.onCommit = onCommit
        self._severity = State(initialValue: initial)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Picker("Severity", selection: $severity) {
                        ForEach(0...4, id: \.self) { level in
                            Text("\(level)").tag(level)
                        }
                    }
                    .pickerStyle(.segmented)

                    HStack {
                        Text("Severity")
                        Spacer()
                        Text(severityLabel(for: severity))
                            .foregroundStyle(.secondary)
                    }
                } footer: {
                    Text("Setting severity to 0 removes this symptom from the day.")
                        .font(.footnote)
                }
            }
            .navigationTitle(symptom.name)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Save") {
                        onCommit(severity)
                        dismiss()
                    }
                    .fontWeight(.semibold)
                }
            }
        }
        .presentationDetents([.medium])
    }

    private func severityLabel(for value: Int) -> String {
        switch value {
        case 0: return "None"
        case 1: return "Mild"
        case 2: return "Moderate"
        case 3: return "Severe"
        case 4: return "Very severe"
        default: return "—"
        }
    }
}

private struct TriggerEditSheet: View {
    let trigger: TriggerDefinition
    let initial: Double
    let onCommit: (Double) -> Void

    @State private var value: Double
    @Environment(\.dismiss) private var dismiss

    init(trigger: TriggerDefinition, initial: Double, onCommit: @escaping (Double) -> Void) {
        self.trigger = trigger
        self.initial = initial
        self.onCommit = onCommit
        self._value = State(initialValue: initial)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    HStack {
                        Text("Level")
                        Spacer()
                        Text("\(Int(value))/10")
                            .monospacedDigit()
                            .foregroundStyle(.secondary)
                    }
                    Slider(value: $value, in: 0...10, step: 1)
                } footer: {
                    Text("Setting to 0 removes this trigger from the day.")
                        .font(.footnote)
                }
            }
            .navigationTitle(trigger.name)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Save") {
                        onCommit(value.rounded())
                        dismiss()
                    }
                    .fontWeight(.semibold)
                }
            }
        }
        .presentationDetents([.medium])
    }
}

private struct NoteEditSheet: View {
    let initial: String
    let onCommit: (String) -> Void

    @State private var text: String
    @FocusState private var isFocused: Bool
    @Environment(\.dismiss) private var dismiss

    init(initial: String, onCommit: @escaping (String) -> Void) {
        self.initial = initial
        self.onCommit = onCommit
        self._text = State(initialValue: initial)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField(
                        "Anything else worth jotting down?",
                        text: $text,
                        axis: .vertical
                    )
                    .lineLimit(3...10)
                    .focused($isFocused)
                }
            }
            .navigationTitle("Note")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Save") {
                        onCommit(text)
                        dismiss()
                    }
                    .fontWeight(.semibold)
                }
            }
            .onAppear { isFocused = true }
        }
        .presentationDetents([.medium, .large])
    }
}

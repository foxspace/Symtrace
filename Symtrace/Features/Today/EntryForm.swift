// Symtrace — Co-created by Mason × AI.

import SwiftUI
import SwiftData

/// The form body shared by Today (`TodayView`) and past-day editing
/// (`EditEntryView`). Same sections, same autosave, same row components.
///
/// Lazy creation invariant: `entry` is optional. Nothing is persisted until
/// the user actually moves a control. The first interaction calls
/// `materializeEntry()` which creates the `DailyEntry` and writes back through
/// the binding so the parent view starts holding the real entry.
///
/// Symptom and trigger rows use *virtual* bindings: severity/value 0 means
/// "no log row exists." Setting a non-zero value creates the log; resetting
/// to zero deletes it. This keeps the database honest — there are no
/// phantom severity-0 rows from days the user merely opened the app.
///
/// `showsQuickActions` is the only structural difference between Today and
/// past-day editing: "Same as yesterday" / "Feeling fine" only make sense
/// when the anchor date is today.
struct EntryForm: View {
    @Binding var entry: DailyEntry?
    let dateForNewEntry: Date
    let activeSymptoms: [SymptomDefinition]
    let activeTriggers: [TriggerDefinition]
    let showsQuickActions: Bool
    let hasYesterday: Bool
    let store: DailyEntryStore
    let onQuickAction: () -> Void

    @State private var pendingQuickAction: QuickAction?

    var body: some View {
        Form {
            if showsQuickActions {
                quickActions
            }
            dayRatingSection
            symptomsSection
            sleepSection
            if !activeTriggers.isEmpty {
                triggersSection
            }
            noteSection
        }
        .confirmationDialog(
            pendingQuickAction?.confirmTitle ?? "",
            isPresented: Binding(
                get: { pendingQuickAction != nil },
                set: { if !$0 { pendingQuickAction = nil } }
            ),
            titleVisibility: .visible,
            presenting: pendingQuickAction
        ) { action in
            Button(action.confirmButton, role: .destructive) {
                perform(action)
                pendingQuickAction = nil
            }
            Button("Cancel", role: .cancel) { pendingQuickAction = nil }
        } message: { action in
            Text(action.confirmMessage)
        }
    }

    // MARK: - Materialization

    /// Returns the `DailyEntry`, creating it on first call. Called from every
    /// binding setter so a value never has to wait for the user to "commit"
    /// elsewhere — the moment they change anything, the entry exists.
    private func materializeEntry() -> DailyEntry {
        if let entry { return entry }
        do {
            let new = try store.entry(for: dateForNewEntry)
            entry = new
            return new
        } catch {
            assertionFailure("materializeEntry failed: \(error)")
            let fallback = DailyEntry(date: dateForNewEntry)
            entry = fallback
            return fallback
        }
    }

    // MARK: - Sections

    private var quickActions: some View {
        Section("Quick log") {
            HStack(spacing: 8) {
                // "Same as yesterday" is always shown so the layout doesn't
                // shift on Day 1 vs. Day 2+ and so users learn the feature
                // exists from the start. Disabled when there's nothing
                // meaningful to copy from yesterday.
                Button {
                    request(.copyYesterday)
                } label: {
                    Label("Same as yesterday", systemImage: "arrow.uturn.backward")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .disabled(!hasYesterday)

                Button {
                    request(.feelingFine)
                } label: {
                    Label("Feeling fine", systemImage: "sun.max")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
            }
            // Stack icon-on-top so longer labels like "Same as yesterday" fit
            // on one line — horizontal `.titleAndIcon` wraps at half-width on
            // iPhone, which looks broken.
            .labelStyle(QuickActionLabelStyle())
            .listRowInsets(EdgeInsets(top: 8, leading: 12, bottom: 8, trailing: 12))
        }
    }

    // MARK: - Quick actions

    /// Run the shortcut immediately on an empty entry — that's the whole point
    /// of a one-tap accelerator. But both shortcuts overwrite/clear existing
    /// data, so when the day already has content, confirm first to avoid
    /// silently wiping what the user just logged.
    private func request(_ action: QuickAction) {
        if entry?.hasContent == true {
            pendingQuickAction = action
        } else {
            perform(action)
        }
    }

    private func perform(_ action: QuickAction) {
        do {
            switch action {
            case .copyYesterday: try store.copyYesterdayToToday()
            case .feelingFine: try store.quickLogFeelingFine()
            }
            onQuickAction()
        } catch {
            assertionFailure("\(action) failed: \(error)")
        }
    }

    private var dayRatingSection: some View {
        Section("How's your day?") {
            Picker("Day rating", selection: dayRatingBinding) {
                Text("—").tag(DayRating?.none)
                ForEach(DayRating.allCases) { rating in
                    Text(rating.label).tag(DayRating?.some(rating))
                }
            }
            .pickerStyle(.segmented)
        }
    }

    private var symptomsSection: some View {
        Section("Symptoms") {
            if activeSymptoms.isEmpty {
                Text("No active symptoms. Add some in Settings later.")
                    .foregroundStyle(.secondary)
            } else {
                ForEach(activeSymptoms) { symptom in
                    SymptomLogRow(
                        symptom: symptom,
                        severity: severityBinding(for: symptom)
                    )
                }
            }
        }
    }

    private var sleepSection: some View {
        Section("Sleep") {
            Stepper(
                value: sleepBinding,
                in: 0...14,
                step: 0.5
            ) {
                HStack {
                    Text("Hours")
                    Spacer()
                    Text(sleepLabel(for: entry?.sleepHours))
                        .monospacedDigit()
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    private var triggersSection: some View {
        Section("Triggers") {
            ForEach(activeTriggers) { trigger in
                TriggerSliderRow(
                    trigger: trigger,
                    value: triggerValueBinding(for: trigger)
                )
            }
        }
    }

    private var noteSection: some View {
        Section("Note (optional)") {
            TextField(
                "Anything else worth jotting down?",
                text: noteBinding,
                axis: .vertical
            )
            .lineLimit(1...4)
        }
    }

    // MARK: - Bindings

    private var dayRatingBinding: Binding<DayRating?> {
        Binding(
            get: { entry?.dayRating },
            set: { newValue in
                let e = materializeEntry()
                e.dayRating = newValue
                e.updatedAt = Date()
                store.save()
            }
        )
    }

    private var sleepBinding: Binding<Double> {
        Binding(
            get: { entry?.sleepHours ?? 7.5 },
            set: { newValue in
                let e = materializeEntry()
                e.sleepHours = newValue
                e.updatedAt = Date()
                store.save()
            }
        )
    }

    private var noteBinding: Binding<String> {
        Binding(
            get: { entry?.note ?? "" },
            set: { newValue in
                let trimmed = newValue.isEmpty ? nil : newValue
                // Avoid materializing a new entry just because the field
                // momentarily got a value and was cleared again.
                if entry == nil, trimmed == nil { return }
                let e = materializeEntry()
                e.note = trimmed
                e.updatedAt = Date()
                store.save()
            }
        )
    }

    private func severityBinding(for symptom: SymptomDefinition) -> Binding<Int> {
        Binding(
            get: {
                guard let entry else { return 0 }
                let symptomID = symptom.id
                return entry.symptomLogs?
                    .first(where: { $0.symptom?.id == symptomID })?
                    .severity ?? 0
            },
            set: { newValue in
                // Don't materialize an entry if the user dragged from 0 → 0.
                if entry == nil, newValue == 0 { return }
                let e = materializeEntry()
                store.setSymptomSeverity(newValue, for: symptom, on: e)
                e.updatedAt = Date()
                store.save()
            }
        )
    }

    private func triggerValueBinding(for trigger: TriggerDefinition) -> Binding<Double> {
        Binding(
            get: {
                guard let entry else { return 0 }
                let triggerID = trigger.id
                return entry.triggerValues?
                    .first(where: { $0.trigger?.id == triggerID })?
                    .value ?? 0
            },
            set: { newValue in
                let snapped = newValue.rounded()
                if entry == nil, snapped == 0 { return }
                let e = materializeEntry()
                store.setTriggerValue(snapped, for: trigger, on: e)
                e.updatedAt = Date()
                store.save()
            }
        )
    }

    private func sleepLabel(for hours: Double?) -> String {
        guard let hours else { return "—" }
        return String(format: "%.1f h", hours)
    }
}

// MARK: - Quick action

/// The two Today shortcuts. Both rewrite the day, so each carries the copy for
/// the confirmation shown when it would overwrite an entry that already has data.
private enum QuickAction: Identifiable {
    case copyYesterday
    case feelingFine

    var id: String {
        switch self {
        case .copyYesterday: return "copyYesterday"
        case .feelingFine: return "feelingFine"
        }
    }

    var confirmTitle: String {
        switch self {
        case .copyYesterday: return "Replace today's entry?"
        case .feelingFine: return "Clear today's symptoms?"
        }
    }

    var confirmMessage: String {
        switch self {
        case .copyYesterday:
            return "This overwrites today's rating, sleep, symptoms, and triggers with yesterday's."
        case .feelingFine:
            return "This removes every symptom logged today and marks the day as Good."
        }
    }

    var confirmButton: String {
        switch self {
        case .copyYesterday: return "Replace"
        case .feelingFine: return "Mark as fine"
        }
    }
}

// MARK: - Label styles

/// Stacks icon above title so quick-action buttons can use full-length labels
/// ("Same as yesterday", "Feeling fine") without wrapping at half-width on
/// iPhone. Sized to feel comparable to a stock `.titleAndIcon` button row.
private struct QuickActionLabelStyle: LabelStyle {
    func makeBody(configuration: Configuration) -> some View {
        VStack(spacing: 4) {
            configuration.icon
                .font(.title3)
            configuration.title
                .font(.callout)
                .lineLimit(1)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 4)
    }
}

// MARK: - Rows

struct SymptomLogRow: View {
    let symptom: SymptomDefinition
    @Binding var severity: Int

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(symptom.name)
                .font(.body)
            Picker("Severity", selection: $severity) {
                ForEach(0...4, id: \.self) { level in
                    Text("\(level)").tag(level)
                }
            }
            .pickerStyle(.segmented)
        }
        .padding(.vertical, 2)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(symptom.name), severity \(severity) of 4")
    }
}

struct TriggerSliderRow: View {
    let trigger: TriggerDefinition
    @Binding var value: Double

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(trigger.name)
                Spacer()
                Text("\(Int(value))")
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
            }
            Slider(value: $value, in: 0...10, step: 1)
        }
        .padding(.vertical, 2)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(trigger.name), level \(Int(value)) of 10")
    }
}

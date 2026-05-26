// Symtrace — Co-created by Mason × AI.

import SwiftUI
import SwiftData

/// Two-screen, low-friction onboarding: a welcome card and a single symptom
/// picker. Everything else (triggers, medications) is discovered later in
/// Settings so a tired first-time user reaches the Today screen in seconds.
/// Tapping through without changing anything still leaves a working app,
/// because the picker pre-selects Headache, Fatigue, and Anxiety on first run.
struct OnboardingView: View {
    @AppStorage("hasCompletedOnboarding") private var hasCompletedOnboarding = false
    @Environment(\.modelContext) private var modelContext

    @Query(sort: [SortDescriptor(\SymptomDefinition.sortOrder)])
    private var existingSymptoms: [SymptomDefinition]

    @State private var step = 0
    @State private var selected: Set<String> = []
    @State private var customName = ""
    @State private var didPrime = false

    /// Common chronic-illness symptoms offered as one-tap chips. The seeded
    /// presets are included so the picker shows them whether or not the seed
    /// has run yet.
    private let suggestions = [
        "Headache", "Fatigue", "Anxiety",
        "Pain", "Nausea", "Brain fog", "Insomnia", "Dizziness"
    ]

    var body: some View {
        VStack(spacing: 0) {
            if step == 0 {
                welcome
            } else {
                symptomPicker
            }
        }
        .onAppear(perform: primeSelectionIfNeeded)
    }

    // MARK: Step 1 — Welcome

    private var welcome: some View {
        VStack(spacing: 24) {
            Spacer()
            Image(systemName: "waveform.path.ecg")
                .font(.system(size: 64, weight: .light))
                .foregroundStyle(.tint)
            VStack(spacing: 12) {
                Text("Symtrace")
                    .font(.largeTitle.bold())
                Text("Track symptoms in seconds.\nBring a clear timeline to your doctor.")
                    .font(.title3)
                    .multilineTextAlignment(.center)
                    .foregroundStyle(.secondary)
            }
            Label("Everything stays private on your device.", systemImage: "lock.fill")
                .font(.subheadline)
                .foregroundStyle(.secondary)
            Spacer()
            Button {
                withAnimation { step = 1 }
            } label: {
                Text("Get started")
                    .font(.headline)
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
        }
        .padding(28)
    }

    // MARK: Step 2 — Symptom picker

    private var symptomPicker: some View {
        VStack(spacing: 0) {
            VStack(spacing: 8) {
                Text("What do you want to track?")
                    .font(.title2.bold())
                    .multilineTextAlignment(.center)
                Text("Tap to choose. You can change these anytime in Settings.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
            .padding(.top, 32)
            .padding(.horizontal, 28)

            ScrollView {
                FlowChips(
                    items: orderedChips,
                    isSelected: { selected.contains($0) },
                    onTap: toggle
                )
                .padding(20)

                HStack {
                    TextField("Add your own", text: $customName)
                        .textFieldStyle(.roundedBorder)
                        .onSubmit(addCustom)
                    Button("Add", action: addCustom)
                        .disabled(trimmedCustom.isEmpty)
                }
                .padding(.horizontal, 20)
            }

            Button {
                commitAndFinish()
            } label: {
                Text(selected.isEmpty ? "Skip for now" : "Start tracking")
                    .font(.headline)
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .padding(20)
        }
    }

    /// Suggestions first (stable order), then any custom symptoms the user added.
    private var orderedChips: [String] {
        let extras = selected.filter { !suggestions.contains($0) }.sorted()
        return suggestions + extras
    }

    private var trimmedCustom: String {
        customName.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    // MARK: Actions

    /// Seed the selection from whatever already exists (the presets), so the
    /// user sees them pre-checked. Runs once.
    private func primeSelectionIfNeeded() {
        guard !didPrime else { return }
        didPrime = true
        let existing = existingSymptoms.map(\.name)
        selected = existing.isEmpty
            ? ["Headache", "Fatigue", "Anxiety"]
            : Set(existing)
    }

    private func toggle(_ name: String) {
        if selected.contains(name) {
            selected.remove(name)
        } else {
            selected.insert(name)
        }
    }

    private func addCustom() {
        let name = trimmedCustom
        guard !name.isEmpty else { return }
        selected.insert(name)
        customName = ""
    }

    /// Reconcile the chosen set against the seeded rows: delete what was
    /// unchecked, insert what's new. Safe because no logs exist yet.
    private func commitAndFinish() {
        let existingByName = Dictionary(
            existingSymptoms.map { ($0.name, $0) },
            uniquingKeysWith: { first, _ in first }
        )

        for symptom in existingSymptoms where !selected.contains(symptom.name) {
            modelContext.delete(symptom)
        }

        var order = existingSymptoms.count
        for name in selected where existingByName[name] == nil {
            modelContext.insert(SymptomDefinition(name: name, sortOrder: order))
            order += 1
        }

        try? modelContext.save()
        hasCompletedOnboarding = true
    }
}

// MARK: - Wrapping chip layout

/// Lightweight wrapping layout so symptom chips flow onto multiple lines
/// without a fixed grid. iOS 17 `Layout` conformance keeps it dependency-free.
private struct FlowChips: View {
    let items: [String]
    let isSelected: (String) -> Bool
    let onTap: (String) -> Void

    var body: some View {
        FlowLayout(spacing: 10) {
            ForEach(items, id: \.self) { item in
                let on = isSelected(item)
                Button { onTap(item) } label: {
                    HStack(spacing: 6) {
                        if on { Image(systemName: "checkmark") }
                        Text(item)
                    }
                    .font(.callout.weight(.medium))
                    .padding(.horizontal, 14)
                    .padding(.vertical, 9)
                    .background(
                        Capsule().fill(on ? Color.accentColor : Color(.secondarySystemBackground))
                    )
                    .foregroundStyle(on ? Color.white : Color.primary)
                }
                .buttonStyle(.plain)
            }
        }
    }
}

private struct FlowLayout: Layout {
    var spacing: CGFloat = 8

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout Void) -> CGSize {
        let maxWidth = proposal.width ?? .infinity
        var rows: [[CGSize]] = [[]]
        var x: CGFloat = 0
        for view in subviews {
            let size = view.sizeThatFits(.unspecified)
            if x + size.width > maxWidth, !rows[rows.count - 1].isEmpty {
                rows.append([])
                x = 0
            }
            rows[rows.count - 1].append(size)
            x += size.width + spacing
        }
        let height = rows.reduce(into: CGFloat(0)) { partial, row in
            partial += (row.map(\.height).max() ?? 0) + spacing
        }
        return CGSize(width: maxWidth == .infinity ? x : maxWidth,
                      height: max(0, height - spacing))
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout Void) {
        var x = bounds.minX
        var y = bounds.minY
        var rowHeight: CGFloat = 0
        for view in subviews {
            let size = view.sizeThatFits(.unspecified)
            if x + size.width > bounds.maxX, x > bounds.minX {
                x = bounds.minX
                y += rowHeight + spacing
                rowHeight = 0
            }
            view.place(at: CGPoint(x: x, y: y), proposal: ProposedViewSize(size))
            x += size.width + spacing
            rowHeight = max(rowHeight, size.height)
        }
    }
}

// MARK: - Preview

#Preview {
    OnboardingView()
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

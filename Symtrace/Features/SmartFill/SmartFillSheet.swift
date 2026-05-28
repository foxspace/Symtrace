// Symtrace — Co-created by Mason × AI.

import SwiftUI

/// Review sheet for Smart-fill suggestions extracted from a free-form note.
///
/// The user sees every proposed change (`current → suggested`), can uncheck
/// any they don't want, and applies the rest. **No write happens before
/// Apply** — this is the safety contract that keeps the parser's mistakes
/// from polluting the doctor PDF.
struct SmartFillSheet: View {
    let note: String
    let suggestions: [ParsedSuggestion]
    let onApply: ([ParsedSuggestion]) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var selected: Set<String>

    init(
        note: String,
        suggestions: [ParsedSuggestion],
        onApply: @escaping ([ParsedSuggestion]) -> Void
    ) {
        self.note = note
        self.suggestions = suggestions
        self.onApply = onApply
        // Default to all suggestions selected — user opts out, not in.
        _selected = State(initialValue: Set(suggestions.map(\.id)))
    }

    var body: some View {
        NavigationStack {
            Group {
                if suggestions.isEmpty {
                    ContentUnavailableView(
                        "No suggestions",
                        systemImage: "wand.and.sparkles",
                        description: Text("We couldn't pick out any symptoms, sleep, or day-rating cues from your note. You can still log them by tapping the rows directly.")
                    )
                } else {
                    list
                }
            }
            .navigationTitle("Smart-fill")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button(applyLabel) {
                        let chosen = suggestions.filter { selected.contains($0.id) }
                        onApply(chosen)
                        dismiss()
                    }
                    .fontWeight(.semibold)
                    .disabled(selected.isEmpty)
                }
            }
        }
        .presentationDetents([.medium, .large])
    }

    private var applyLabel: String {
        selected.isEmpty ? "Apply" : "Apply \(selected.count)"
    }

    private var list: some View {
        List {
            Section("From your note") {
                Text(note)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .lineLimit(4)
            }
            Section {
                ForEach(suggestions) { suggestion in
                    SuggestionRow(
                        suggestion: suggestion,
                        isSelected: selected.contains(suggestion.id),
                        onToggle: {
                            if selected.contains(suggestion.id) {
                                selected.remove(suggestion.id)
                            } else {
                                selected.insert(suggestion.id)
                            }
                        }
                    )
                }
            } header: {
                Text("Suggestions")
            } footer: {
                Text("Uncheck anything that doesn't match what you meant. Nothing is saved until you tap Apply.")
                    .font(.footnote)
            }
        }
    }
}

private struct SuggestionRow: View {
    let suggestion: ParsedSuggestion
    let isSelected: Bool
    let onToggle: () -> Void

    var body: some View {
        Button(action: onToggle) {
            HStack(spacing: 12) {
                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .foregroundStyle(isSelected ? Color.accentColor : Color.secondary)
                    .font(.title3)
                VStack(alignment: .leading, spacing: 2) {
                    Text(suggestion.fieldLabel)
                        .foregroundStyle(.primary)
                    HStack(spacing: 4) {
                        Text(suggestion.currentDisplay)
                            .foregroundStyle(.secondary)
                            .monospacedDigit()
                        Image(systemName: "arrow.right")
                            .font(.caption)
                            .foregroundStyle(.tertiary)
                        Text(suggestion.suggestedDisplay)
                            .foregroundStyle(.primary)
                            .fontWeight(.medium)
                            .monospacedDigit()
                    }
                    .font(.subheadline)
                }
                Spacer()
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

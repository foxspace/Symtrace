// Symtrace — Co-created by Mason × AI.

import SwiftUI

/// Full-screen brain-dump → Smart-fill flow, surfaced as the third Quick log
/// path on Today (alongside "Same as yesterday" and "Feeling fine").
///
/// Why this exists: with on-device Smart-fill in place, a free-form note is no
/// longer a comment — it's a *third way to log a day fast*. Burying it at the
/// bottom of the form (where notes traditionally live) hid the flow from
/// users who might prefer typing on flare or brain-fog days when tapping
/// through five sliders is more cognitive load than typing one sentence.
///
/// This sheet has **one primary action**: Smart-fill. A separate Save button
/// would be a lower-quality duplicate (Smart-fill already saves the text on
/// every path), and offering both creates a "which one do I tap?" moment
/// every time. So:
///
/// 1. User types into the editor (pre-filled with today's existing note).
/// 2. **Smart-fill** (top-right) — runs `NoteParser`. If suggestions exist,
///    opens `SmartFillSheet` for review and Apply commits *both* the text
///    (as the note) and the confirmed suggestions in one transaction. If
///    no suggestions are found, the typed text is still saved as the day's
///    note and the sheet dismisses — no dead-end empty review screen.
/// 3. **Cancel** — discards typing entirely.
///
/// Apply is a single round-trip back to the parent (`onSave`) so the parent
/// owns lazy materialization + persistence — same path manual edits use,
/// which preserves the lazy-creation invariant.
///
/// Pure-journal text still has a home: the note field at the bottom of the
/// Today form. This sheet is specifically the brain-dump → structured-data
/// path, and shouldn't pretend to be a general note editor.
struct DescribeYourDaySheet: View {
    let initialText: String
    let symptoms: [SymptomDefinition]
    let triggers: [TriggerDefinition]
    let currentEntry: DailyEntry?
    /// (textToSaveAsNote, confirmedSuggestionsToApply). Empty suggestions
    /// means "save text only"; non-empty means "save text + apply these."
    let onSave: (String, [ParsedSuggestion]) -> Void

    @State private var text: String
    @State private var pendingReview: SmartFillReviewContext?
    @FocusState private var editorFocused: Bool
    @Environment(\.dismiss) private var dismiss

    init(
        initialText: String,
        symptoms: [SymptomDefinition],
        triggers: [TriggerDefinition],
        currentEntry: DailyEntry?,
        onSave: @escaping (String, [ParsedSuggestion]) -> Void
    ) {
        self.initialText = initialText
        self.symptoms = symptoms
        self.triggers = triggers
        self.currentEntry = currentEntry
        self.onSave = onSave
        self._text = State(initialValue: initialText)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField(
                        "How are you feeling? Try: \"Bad headache, slept 5h, stress was high.\"",
                        text: $text,
                        axis: .vertical
                    )
                    .lineLimit(6...18)
                    .focused($editorFocused)
                } footer: {
                    Text("Smart-fill scans for symptoms (severity 1–4), sleep hours, day rating, and trigger levels. Your typed note is saved either way.")
                        .font(.footnote)
                }
            }
            .navigationTitle("Describe your day")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        runSmartFill()
                    } label: {
                        // Sparkles + iridescent gradient borrows Apple's
                        // emerging AI visual language (Writing Tools, Apple
                        // Intelligence) so the action reads as "this is the
                        // smart one" at a glance. The gradient is scoped to
                        // the icon — the system handles button-level disabled
                        // opacity automatically, so the whole thing fades
                        // correctly when there's no text to parse.
                        Label {
                            Text("Smart-fill")
                        } icon: {
                            Image(systemName: "sparkles")
                                .foregroundStyle(smartFillIconStyle)
                        }
                        .labelStyle(.titleAndIcon)
                    }
                    .fontWeight(.semibold)
                    .disabled(!hasContent)
                }
            }
            // Sheet animation + first-responder timing fight each other on
            // iOS 17/18 — set focus after a short delay so the keyboard
            // animates in cleanly rather than racing the sheet present.
            .task {
                try? await Task.sleep(for: .milliseconds(300))
                editorFocused = true
            }
            .sheet(item: $pendingReview) { ctx in
                SmartFillSheet(
                    note: ctx.note,
                    suggestions: ctx.suggestions,
                    onApply: { confirmed in
                        // Single transaction: parent writes the typed text as
                        // the note AND applies every confirmed suggestion.
                        // Inner sheet auto-dismisses; this dismiss closes the
                        // outer one too.
                        onSave(text, confirmed)
                        dismiss()
                    }
                )
            }
        }
        .presentationDetents([.large])
    }

    // MARK: - State helpers

    private var hasContent: Bool {
        !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    /// Iridescent gradient used on the sparkles icon. Pulled out as a
    /// computed `AnyShapeStyle` so the same look can be reused if we surface
    /// Smart-fill anywhere else (e.g. a future History or Export entry point).
    private var smartFillIconStyle: AnyShapeStyle {
        AnyShapeStyle(
            LinearGradient(
                colors: [.purple, .pink, .orange],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        )
    }

    // MARK: - Smart-fill

    private func runSmartFill() {
        guard hasContent else { return }
        editorFocused = false
        let parser = NoteParser()
        let suggestions = parser.parse(
            note: text,
            symptoms: symptoms,
            triggers: triggers,
            currentEntry: currentEntry
        )

        // No suggestions → don't open an empty review sheet. Just save the
        // typed text as today's note and dismiss; the user sees Today's note
        // field reflect their entry, which is the same outcome they'd get if
        // they'd typed there directly. Footer copy sets this expectation
        // ahead of time so the silent dismiss isn't surprising.
        if suggestions.isEmpty {
            onSave(text, [])
            dismiss()
            return
        }

        pendingReview = SmartFillReviewContext(note: text, suggestions: suggestions)
    }
}

// MARK: - Review context

/// Identifiable wrapper so `.sheet(item:)` handles present/dismiss without us
/// juggling a separate isPresented bool plus a payload. Scoped to this file
/// because no other view needs it.
private struct SmartFillReviewContext: Identifiable {
    let id = UUID()
    let note: String
    let suggestions: [ParsedSuggestion]
}

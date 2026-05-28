// Symtrace — Co-created by Mason × AI.

import Foundation

/// A single suggested change extracted from a free-form note.
///
/// Suggestions are *proposals* — they always pass through the user's review
/// in `SmartFillSheet` before any data is written. This is non-negotiable for
/// a health app: if a typo or misread phrase produces a wrong suggestion, the
/// user catches it before it lands in the doctor PDF.
enum ParsedSuggestion: Identifiable, Equatable {
    case symptom(SymptomDefinition, current: Int, suggested: Int)
    case trigger(TriggerDefinition, current: Double, suggested: Double)
    case sleep(current: Double?, suggested: Double)
    case dayRating(current: DayRating?, suggested: DayRating)

    var id: String {
        switch self {
        case .symptom(let s, _, _): return "symptom-\(s.id.uuidString)"
        case .trigger(let t, _, _): return "trigger-\(t.id.uuidString)"
        case .sleep: return "sleep"
        case .dayRating: return "dayRating"
        }
    }

    /// Human-readable label for the row, e.g. "Headache".
    var fieldLabel: String {
        switch self {
        case .symptom(let s, _, _): return s.name
        case .trigger(let t, _, _): return t.name
        case .sleep: return "Sleep"
        case .dayRating: return "Day rating"
        }
    }

    /// Display string for the current value (or "—" if unset).
    var currentDisplay: String {
        switch self {
        case .symptom(_, let current, _):
            return current > 0 ? "\(current)/4" : "—"
        case .trigger(_, let current, _):
            return current > 0 ? "\(Int(current))/10" : "—"
        case .sleep(let current, _):
            return current.map { String(format: "%.1f h", $0) } ?? "—"
        case .dayRating(let current, _):
            return current?.label ?? "—"
        }
    }

    /// Display string for the suggested value.
    var suggestedDisplay: String {
        switch self {
        case .symptom(_, _, let suggested):
            return "\(suggested)/4"
        case .trigger(_, _, let suggested):
            return "\(Int(suggested))/10"
        case .sleep(_, let suggested):
            return String(format: "%.1f h", suggested)
        case .dayRating(_, let suggested):
            return suggested.label
        }
    }

    /// True iff applying this suggestion would actually change the entry.
    /// Used to filter out no-ops before showing them to the user.
    var changesValue: Bool {
        switch self {
        case .symptom(_, let current, let suggested): return current != suggested
        case .trigger(_, let current, let suggested): return current != suggested
        case .sleep(let current, let suggested): return current != suggested
        case .dayRating(let current, let suggested): return current != suggested
        }
    }

    static func == (lhs: ParsedSuggestion, rhs: ParsedSuggestion) -> Bool {
        lhs.id == rhs.id
    }
}

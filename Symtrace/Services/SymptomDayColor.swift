// Symtrace — Co-created by Mason × AI.

import SwiftUI

/// Single source of truth for "how bad was this day?" coloring used in the
/// calendar grid (and later: PDF doctor report). Severity drives the color
/// because it's the per-symptom signal a clinician actually reads — `dayRating`
/// is a subjective overlay we may layer on as a small accent dot in v1.1.
enum SymptomDayColor {
    /// Highest severity logged for the day.
    /// - Returns `nil` when there's no entry or the entry has no real content
    ///   (calendar paints these gray = "no entry").
    /// - Returns `0` when the user logged something — sleep, day rating, a
    ///   note, or anything — but didn't record any symptoms above 0
    ///   (calendar paints green = "logged, no symptoms"). This is the
    ///   "Feeling fine" case.
    /// - Otherwise returns the max severity of the day's symptom logs.
    ///
    /// Pairs with the lazy creation invariant: severity-0 logs don't exist,
    /// so a non-empty `symptomLogs` always means at least one real symptom.
    static func maxSeverity(for entry: DailyEntry?) -> Int? {
        guard let entry, entry.hasContent else { return nil }
        let maxSymptom = (entry.symptomLogs ?? []).map(\.severity).max() ?? 0
        return maxSymptom
    }

    /// Color mapping per plan §"Day coloring rule": single-axis from gray
    /// (no entry) → green (no symptoms) → red (very severe). Designed to stay
    /// legible when printed in black-and-white inside the doctor PDF.
    static func color(forMaxSeverity severity: Int?) -> Color {
        switch severity {
        case .none:
            return Color(.systemGray5)
        case .some(0):
            return Color.green.opacity(0.55)
        case .some(1):
            return Color.yellow.opacity(0.7)
        case .some(2):
            return Color.orange.opacity(0.7)
        case .some(3):
            return Color.orange
        case .some(let value) where value >= 4:
            return Color.red.opacity(0.85)
        default:
            return Color(.systemGray5)
        }
    }

    /// Foreground color used by the day number label so contrast holds at
    /// every cell color (white on red, primary elsewhere).
    static func textColor(forMaxSeverity severity: Int?) -> Color {
        guard let severity, severity >= 4 else { return .primary }
        return .white
    }

    /// Localized label for accessibility/readouts.
    static func severityLabel(_ severity: Int?) -> String {
        switch severity {
        case .none: return "no entry"
        case .some(0): return "no symptoms"
        case .some(1): return "mild"
        case .some(2): return "moderate"
        case .some(3): return "severe"
        case .some(let value) where value >= 4: return "very severe"
        default: return "unknown"
        }
    }
}

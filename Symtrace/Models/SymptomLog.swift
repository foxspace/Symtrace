// Symtrace — Co-created by Mason × AI.

import Foundation
import SwiftData

/// One severity record for a single symptom on a single day.
/// Severity scale: 0 = none, 1–4 = mild → severe.
@Model
final class SymptomLog {
    var id: UUID = UUID()
    var severity: Int = 0
    var note: String? = nil
    var loggedAt: Date = Date()
    var updatedAt: Date = Date()

    var entry: DailyEntry?
    var symptom: SymptomDefinition?

    init(
        id: UUID = UUID(),
        severity: Int = 0,
        note: String? = nil,
        loggedAt: Date = Date(),
        updatedAt: Date = Date(),
        entry: DailyEntry? = nil,
        symptom: SymptomDefinition? = nil
    ) {
        self.id = id
        self.severity = severity
        self.note = note
        self.loggedAt = loggedAt
        self.updatedAt = updatedAt
        self.entry = entry
        self.symptom = symptom
    }
}

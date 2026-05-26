// Symtrace — Co-created by Mason × AI.

import Foundation
import SwiftData

/// User medication (name + optional dosage). v1 logs only — no reminders.
/// `reminderTimes` is added in v1.1.
@Model
final class Medication {
    var id: UUID = UUID()
    var name: String = ""
    var dosage: String? = nil
    var isArchived: Bool = false
    var sortOrder: Int = 0
    var createdAt: Date = Date()
    var updatedAt: Date = Date()

    @Relationship(deleteRule: .cascade, inverse: \MedicationLog.medication)
    var logs: [MedicationLog]? = []

    init(
        id: UUID = UUID(),
        name: String,
        dosage: String? = nil,
        isArchived: Bool = false,
        sortOrder: Int = 0,
        createdAt: Date = Date(),
        updatedAt: Date = Date()
    ) {
        self.id = id
        self.name = name
        self.dosage = dosage
        self.isArchived = isArchived
        self.sortOrder = sortOrder
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }
}

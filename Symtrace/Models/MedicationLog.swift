// Symtrace — Co-created by Mason × AI.

import Foundation
import SwiftData

enum MedicationLogStatus: String, Codable, CaseIterable, Identifiable {
    case taken
    case skipped
    var id: String { rawValue }

    var label: String {
        switch self {
        case .taken: return "Taken"
        case .skipped: return "Skipped"
        }
    }
}

/// Whether a medication was taken or skipped on a specific day.
@Model
final class MedicationLog {
    var id: UUID = UUID()
    var statusRaw: String = MedicationLogStatus.taken.rawValue
    var loggedAt: Date = Date()
    var updatedAt: Date = Date()

    var entry: DailyEntry?
    var medication: Medication?

    init(
        id: UUID = UUID(),
        status: MedicationLogStatus = .taken,
        loggedAt: Date = Date(),
        updatedAt: Date = Date(),
        entry: DailyEntry? = nil,
        medication: Medication? = nil
    ) {
        self.id = id
        self.statusRaw = status.rawValue
        self.loggedAt = loggedAt
        self.updatedAt = updatedAt
        self.entry = entry
        self.medication = medication
    }

    var status: MedicationLogStatus {
        get { MedicationLogStatus(rawValue: statusRaw) ?? .taken }
        set { statusRaw = newValue.rawValue }
    }
}

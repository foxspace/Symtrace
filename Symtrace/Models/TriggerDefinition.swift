// Symtrace — Co-created by Mason × AI.

import Foundation
import SwiftData

/// User-defined contextual factor (e.g. Stress, Caffeine).
/// v1: stored as 0–10 scale value on each daily entry.
@Model
final class TriggerDefinition {
    var id: UUID = UUID()
    var name: String = ""
    var isActive: Bool = true
    var isArchived: Bool = false
    var sortOrder: Int = 0
    var createdAt: Date = Date()
    var updatedAt: Date = Date()

    @Relationship(deleteRule: .cascade, inverse: \TriggerValue.trigger)
    var values: [TriggerValue]? = []

    init(
        id: UUID = UUID(),
        name: String,
        isActive: Bool = true,
        isArchived: Bool = false,
        sortOrder: Int = 0,
        createdAt: Date = Date(),
        updatedAt: Date = Date()
    ) {
        self.id = id
        self.name = name
        self.isActive = isActive
        self.isArchived = isArchived
        self.sortOrder = sortOrder
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }
}

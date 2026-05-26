// Symtrace — Co-created by Mason × AI.

import Foundation
import SwiftData

/// Value for a single trigger on a single day. v1 uses a 0–10 scale.
@Model
final class TriggerValue {
    var id: UUID = UUID()
    var value: Double = 0
    var loggedAt: Date = Date()
    var updatedAt: Date = Date()

    var entry: DailyEntry?
    var trigger: TriggerDefinition?

    init(
        id: UUID = UUID(),
        value: Double = 0,
        loggedAt: Date = Date(),
        updatedAt: Date = Date(),
        entry: DailyEntry? = nil,
        trigger: TriggerDefinition? = nil
    ) {
        self.id = id
        self.value = value
        self.loggedAt = loggedAt
        self.updatedAt = updatedAt
        self.entry = entry
        self.trigger = trigger
    }
}

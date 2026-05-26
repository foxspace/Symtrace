// Symtrace — Co-created by Mason × AI.

import SwiftUI
import SwiftData

@main
struct SymtraceApp: App {
    let sharedModelContainer: ModelContainer = {
        let schema = Schema([
            SymptomDefinition.self,
            TriggerDefinition.self,
            Medication.self,
            DailyEntry.self,
            SymptomLog.self,
            MedicationLog.self,
            TriggerValue.self,
        ])
        let configuration = ModelConfiguration(
            schema: schema,
            isStoredInMemoryOnly: false
        )

        do {
            let container = try ModelContainer(
                for: schema,
                configurations: [configuration]
            )
            migrateOnboardingFlagIfNeeded(container: container)
            return container
        } catch {
            fatalError("Failed to create ModelContainer: \(error)")
        }
    }()

    var body: some Scene {
        WindowGroup {
            ContentView()
        }
        .modelContainer(sharedModelContainer)
    }
}

/// One-shot migration for testers who installed Symtrace before onboarding
/// existed. If the symptom table already has data and the onboarding flag
/// hasn't been set, treat them as already onboarded so they don't see the
/// flow on the next launch. New installs (empty store) fall through to
/// onboarding as expected.
@MainActor
private func migrateOnboardingFlagIfNeeded(container: ModelContainer) {
    let defaults = UserDefaults.standard
    let key = "hasCompletedOnboarding"
    guard !defaults.bool(forKey: key) else { return }

    let context = ModelContext(container)
    let count = (try? context.fetchCount(FetchDescriptor<SymptomDefinition>())) ?? 0
    if count > 0 {
        defaults.set(true, forKey: key)
    }
}

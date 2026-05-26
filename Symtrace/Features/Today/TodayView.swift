// Symtrace — Co-created by Mason × AI.

import SwiftUI
import SwiftData

/// Today screen: the <10s logging path. Every interaction autosaves so the
/// user can dismiss the app at any moment without losing data.
///
/// The today entry is loaded *lazily*: opening the app no longer creates a
/// `DailyEntry`. The form binds to an optional entry and only materializes one
/// when the user actually changes a value (see `EntryForm.materializeEntry`).
struct TodayView: View {
    @Environment(\.modelContext) private var modelContext

    @Query(
        filter: #Predicate<SymptomDefinition> { $0.isActive && !$0.isArchived },
        sort: [SortDescriptor(\SymptomDefinition.sortOrder)]
    )
    private var activeSymptoms: [SymptomDefinition]

    @Query(
        filter: #Predicate<TriggerDefinition> { $0.isActive && !$0.isArchived },
        sort: [SortDescriptor(\TriggerDefinition.sortOrder)]
    )
    private var activeTriggers: [TriggerDefinition]

    @State private var today: DailyEntry?
    @State private var hasYesterday = false

    private var store: DailyEntryStore { DailyEntryStore(context: modelContext) }

    var body: some View {
        EntryForm(
            entry: $today,
            dateForNewEntry: Calendar.current.startOfDay(for: Date()),
            activeSymptoms: activeSymptoms,
            activeTriggers: activeTriggers,
            showsQuickActions: true,
            hasYesterday: hasYesterday,
            store: store,
            onQuickAction: load
        )
        // Today is a leaf tab — no pushable destinations, no toolbar
        // items. Hiding the nav bar reclaims ~50pt for actual logging
        // content. Date context lives in the safe-area inset below.
        .toolbar(.hidden, for: .navigationBar)
        .safeAreaInset(edge: .top, spacing: 0) {
            Text(Date().formatted(.dateTime.weekday(.wide).month(.wide).day()))
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .center)
                .padding(.top, 8)
                .padding(.bottom, 4)
                .background(.bar)
        }
        .onAppear(perform: load)
    }

    private func load() {
        do {
            today = try store.existingTodayEntry()
            hasYesterday = (try store.yesterdayEntry())?.hasContent ?? false
        } catch {
            assertionFailure("TodayView load failed: \(error)")
        }
    }
}

#Preview {
    TodayView()
        .modelContainer(for: [
            SymptomDefinition.self,
            TriggerDefinition.self,
            Medication.self,
            DailyEntry.self,
            SymptomLog.self,
            MedicationLog.self,
            TriggerValue.self,
        ], inMemory: true)
}

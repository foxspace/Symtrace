// Symtrace — Co-created by Mason × AI.

import SwiftUI
import SwiftData

/// Root shell. Shows onboarding on first launch; afterwards hosts the
/// four-tab main navigation (Today / History / Export / Settings).
enum AppTab { case today, history, export, settings }

struct ContentView: View {
    @AppStorage("hasCompletedOnboarding") private var hasCompletedOnboarding: Bool = false
    @State private var selectedTab: AppTab = .today

    var body: some View {
        Group {
            if hasCompletedOnboarding {
                TabView(selection: $selectedTab) {
                    NavigationStack {
                        TodayView()
                    }
                    .tabItem { Label("Today", systemImage: "square.and.pencil") }
                    .tag(AppTab.today)
                    NavigationStack {
                        HistoryView(goToToday: { selectedTab = .today })
                    }
                    .tabItem { Label("History", systemImage: "calendar") }
                    .tag(AppTab.history)
                    NavigationStack {
                        ExportView()
                    }
                    .tabItem { Label("Export", systemImage: "square.and.arrow.up") }
                    .tag(AppTab.export)
                    NavigationStack {
                        SettingsView()
                    }
                    .tabItem { Label("Settings", systemImage: "gearshape") }
                    .tag(AppTab.settings)
                }
            } else {
                OnboardingView()
            }
        }
        .animation(.easeInOut, value: hasCompletedOnboarding)
    }
}

#Preview {
    ContentView()
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

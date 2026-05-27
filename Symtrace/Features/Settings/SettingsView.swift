// Symtrace — Co-created by Mason × AI.

import SwiftUI
import SwiftData

/// Root Settings screen. Reachable from the gear icon on Today.
/// Each manage row pushes a dedicated screen for that entity type.
struct SettingsView: View {
    var body: some View {
        List {
            Section("Manage") {
                NavigationLink {
                    SymptomSettingsView()
                } label: {
                    Label("Symptoms", systemImage: "heart.text.square")
                }
                NavigationLink {
                    TriggerSettingsView()
                } label: {
                    Label("Triggers", systemImage: "bolt.heart")
                }
                NavigationLink {
                    MedicationSettingsView()
                } label: {
                    Label("Medications", systemImage: "pills")
                }
            }

            Section("Privacy") {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Stored only on this device.")
                        .font(.subheadline)
                    Text("Symtrace does not sync, share, or upload your data. Cloud backup is planned for a future version and will be opt-in.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
                .padding(.vertical, 2)
            }

            Section("About") {
                LabeledContent("Version", value: appVersion)
                LabeledContent("Created by", value: "Foxspace")
            }
        }
        .navigationTitle("Settings")
    }

    private var appVersion: String {
        let short = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0.1"
        let build = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "1"
        return "\(short) (\(build))"
    }
}

#Preview {
    NavigationStack {
        SettingsView()
    }
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

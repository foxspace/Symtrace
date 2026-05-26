// Symtrace — Co-created by Mason × AI.

import SwiftUI
import SwiftData

/// Manage medication definitions. Meds have only `isArchived` (no
/// `isActive` toggle) — every non-archived med is fair game for daily logging.
/// Push reminders are out of scope for v1; they ship in v1.1.
struct MedicationSettingsView: View {
    @Environment(\.modelContext) private var modelContext

    @Query(
        filter: #Predicate<Medication> { !$0.isArchived },
        sort: [SortDescriptor(\Medication.sortOrder)]
    )
    private var active: [Medication]

    @Query(
        filter: #Predicate<Medication> { $0.isArchived },
        sort: [SortDescriptor(\Medication.name)]
    )
    private var archived: [Medication]

    @State private var newName = ""
    @FocusState private var addFocused: Bool

    var body: some View {
        List {
            Section {
                ForEach(active) { medication in
                    MedicationRow(medication: medication, onArchive: { archive(medication) })
                }
                .onMove(perform: reorder)

                addRow
            } header: {
                Text("Active")
            } footer: {
                Text("Push reminders arrive in a later version. v1 supports the daily Taken / Skipped log only.")
            }

            if !archived.isEmpty {
                Section {
                    NavigationLink {
                        ArchivedMedicationsView()
                    } label: {
                        LabeledContent("Archived", value: "\(archived.count)")
                    }
                }
            }
        }
        .navigationTitle("Medications")
        .toolbar { EditButton() }
        .overlay {
            if active.isEmpty && archived.isEmpty {
                ContentUnavailableView(
                    "No medications yet",
                    systemImage: "pills",
                    description: Text("Tap the + row to add the meds you want to log.")
                )
            }
        }
    }

    private var addRow: some View {
        HStack {
            Image(systemName: "plus.circle.fill")
                .foregroundStyle(.tint)
            TextField("Add medication", text: $newName)
                .focused($addFocused)
                .submitLabel(.done)
                .onSubmit(addNew)
        }
    }

    private func addNew() {
        let trimmed = newName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        guard !active.contains(where: { $0.name.caseInsensitiveCompare(trimmed) == .orderedSame }) else {
            newName = ""
            return
        }
        let next = Medication(name: trimmed, sortOrder: active.count)
        modelContext.insert(next)
        newName = ""
        addFocused = true
        save()
    }

    private func reorder(from source: IndexSet, to destination: Int) {
        var ordered = active
        ordered.move(fromOffsets: source, toOffset: destination)
        for (index, medication) in ordered.enumerated() where medication.sortOrder != index {
            medication.sortOrder = index
            medication.updatedAt = Date()
        }
        save()
    }

    private func archive(_ medication: Medication) {
        medication.isArchived = true
        medication.updatedAt = Date()
        save()
    }

    private func save() {
        do { try modelContext.save() } catch {
            assertionFailure("MedicationSettings save failed: \(error)")
        }
    }
}

// MARK: - Active row

private struct MedicationRow: View {
    @Bindable var medication: Medication
    let onArchive: () -> Void
    @Environment(\.modelContext) private var modelContext

    var body: some View {
        TextField("Name", text: $medication.name)
            .onChange(of: medication.name) { _, _ in
                medication.updatedAt = Date()
                try? modelContext.save()
            }
            .swipeActions(edge: .trailing) {
                Button(role: .destructive, action: onArchive) {
                    Label("Archive", systemImage: "archivebox")
                }
            }
            .accessibilityLabel(medication.name)
    }
}

// MARK: - Archived

private struct ArchivedMedicationsView: View {
    @Environment(\.modelContext) private var modelContext

    @Query(
        filter: #Predicate<Medication> { $0.isArchived },
        sort: [SortDescriptor(\Medication.name)]
    )
    private var archived: [Medication]

    var body: some View {
        List {
            if archived.isEmpty {
                ContentUnavailableView(
                    "Nothing archived",
                    systemImage: "archivebox",
                    description: Text("Archived medications stay in history and exports.")
                )
            } else {
                ForEach(archived) { medication in
                    HStack {
                        Text(medication.name)
                        Spacer()
                        Button("Unarchive") { unarchive(medication) }
                            .buttonStyle(.bordered)
                            .controlSize(.small)
                    }
                }
            }
        }
        .navigationTitle("Archived medications")
    }

    private func unarchive(_ medication: Medication) {
        medication.isArchived = false
        medication.updatedAt = Date()
        do { try modelContext.save() } catch {
            assertionFailure("Unarchive failed: \(error)")
        }
    }
}

// Symtrace — Co-created by Mason × AI.

import SwiftUI
import SwiftData

/// Manage symptom definitions: rename, reorder, toggle "Show on Today",
/// archive, and add new ones inline. Archive is preferred over delete so
/// historical logs and exports stay intact (plan §"Evolving symptoms").
struct SymptomSettingsView: View {
    @Environment(\.modelContext) private var modelContext

    @Query(
        filter: #Predicate<SymptomDefinition> { !$0.isArchived },
        sort: [SortDescriptor(\SymptomDefinition.sortOrder)]
    )
    private var active: [SymptomDefinition]

    @Query(
        filter: #Predicate<SymptomDefinition> { $0.isArchived },
        sort: [SortDescriptor(\SymptomDefinition.name)]
    )
    private var archived: [SymptomDefinition]

    @State private var newName = ""
    @FocusState private var addFocused: Bool

    var body: some View {
        List {
            Section {
                ForEach(active) { symptom in
                    SymptomRow(symptom: symptom, onArchive: { archive(symptom) })
                }
                .onMove(perform: reorder)

                addRow
            } header: {
                Text("Active")
            } footer: {
                Text("Active symptoms appear on the Today screen. Archive to hide everywhere except history & exports.")
            }

            if !archived.isEmpty {
                Section {
                    NavigationLink {
                        ArchivedSymptomsView()
                    } label: {
                        LabeledContent("Archived", value: "\(archived.count)")
                    }
                }
            }
        }
        .navigationTitle("Symptoms")
        .toolbar { EditButton() }
    }

    private var addRow: some View {
        HStack {
            Image(systemName: "plus.circle.fill")
                .foregroundStyle(.tint)
            TextField("Add symptom", text: $newName)
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
        let next = SymptomDefinition(name: trimmed, sortOrder: active.count)
        modelContext.insert(next)
        newName = ""
        addFocused = true
        save()
    }

    private func reorder(from source: IndexSet, to destination: Int) {
        var ordered = active
        ordered.move(fromOffsets: source, toOffset: destination)
        for (index, symptom) in ordered.enumerated() where symptom.sortOrder != index {
            symptom.sortOrder = index
            symptom.updatedAt = Date()
        }
        save()
    }

    private func archive(_ symptom: SymptomDefinition) {
        symptom.isArchived = true
        symptom.isActive = false
        symptom.updatedAt = Date()
        save()
    }

    private func save() {
        do { try modelContext.save() } catch {
            assertionFailure("SymptomSettings save failed: \(error)")
        }
    }
}

// MARK: - Active row

private struct SymptomRow: View {
    @Bindable var symptom: SymptomDefinition
    let onArchive: () -> Void
    @Environment(\.modelContext) private var modelContext

    var body: some View {
        HStack {
            TextField("Name", text: $symptom.name)
                .onChange(of: symptom.name) { _, _ in
                    symptom.updatedAt = Date()
                    try? modelContext.save()
                }
            Toggle("Show on Today", isOn: $symptom.isActive)
                .labelsHidden()
                .onChange(of: symptom.isActive) { _, _ in
                    symptom.updatedAt = Date()
                    try? modelContext.save()
                }
        }
        .swipeActions(edge: .trailing) {
            Button(role: .destructive, action: onArchive) {
                Label("Archive", systemImage: "archivebox")
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(symptom.name), \(symptom.isActive ? "shown on Today" : "hidden from Today")")
    }
}

// MARK: - Archived

private struct ArchivedSymptomsView: View {
    @Environment(\.modelContext) private var modelContext

    @Query(
        filter: #Predicate<SymptomDefinition> { $0.isArchived },
        sort: [SortDescriptor(\SymptomDefinition.name)]
    )
    private var archived: [SymptomDefinition]

    var body: some View {
        List {
            if archived.isEmpty {
                ContentUnavailableView(
                    "Nothing archived",
                    systemImage: "archivebox",
                    description: Text("Archived symptoms appear here. Their past logs are kept for history and exports.")
                )
            } else {
                ForEach(archived) { symptom in
                    HStack {
                        Text(symptom.name)
                        Spacer()
                        Button("Unarchive") {
                            unarchive(symptom)
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                    }
                }
            }
        }
        .navigationTitle("Archived symptoms")
    }

    private func unarchive(_ symptom: SymptomDefinition) {
        symptom.isArchived = false
        symptom.isActive = true
        symptom.updatedAt = Date()
        do { try modelContext.save() } catch {
            assertionFailure("Unarchive failed: \(error)")
        }
    }
}

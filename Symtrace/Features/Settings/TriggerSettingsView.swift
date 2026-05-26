// Symtrace — Co-created by Mason × AI.

import SwiftUI
import SwiftData

/// Manage trigger definitions. Mirrors `SymptomSettingsView`; kept as a
/// separate file because SwiftData @Model + #Predicate doesn't generalize
/// cleanly across entity types.
struct TriggerSettingsView: View {
    @Environment(\.modelContext) private var modelContext

    @Query(
        filter: #Predicate<TriggerDefinition> { !$0.isArchived },
        sort: [SortDescriptor(\TriggerDefinition.sortOrder)]
    )
    private var active: [TriggerDefinition]

    @Query(
        filter: #Predicate<TriggerDefinition> { $0.isArchived },
        sort: [SortDescriptor(\TriggerDefinition.name)]
    )
    private var archived: [TriggerDefinition]

    @State private var newName = ""
    @FocusState private var addFocused: Bool

    var body: some View {
        List {
            Section {
                ForEach(active) { trigger in
                    TriggerRow(trigger: trigger, onArchive: { archive(trigger) })
                }
                .onMove(perform: reorder)

                addRow
            } header: {
                Text("Active")
            } footer: {
                Text("Up to two active triggers show on Today (slider 0–10). Beyond that, set extras to “Hidden” or archive them.")
            }

            if !archived.isEmpty {
                Section {
                    NavigationLink {
                        ArchivedTriggersView()
                    } label: {
                        LabeledContent("Archived", value: "\(archived.count)")
                    }
                }
            }
        }
        .navigationTitle("Triggers")
        .toolbar { EditButton() }
    }

    private var addRow: some View {
        HStack {
            Image(systemName: "plus.circle.fill")
                .foregroundStyle(.tint)
            TextField("Add trigger (e.g. Caffeine)", text: $newName)
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
        let next = TriggerDefinition(name: trimmed, sortOrder: active.count)
        modelContext.insert(next)
        newName = ""
        addFocused = true
        save()
    }

    private func reorder(from source: IndexSet, to destination: Int) {
        var ordered = active
        ordered.move(fromOffsets: source, toOffset: destination)
        for (index, trigger) in ordered.enumerated() where trigger.sortOrder != index {
            trigger.sortOrder = index
            trigger.updatedAt = Date()
        }
        save()
    }

    private func archive(_ trigger: TriggerDefinition) {
        trigger.isArchived = true
        trigger.isActive = false
        trigger.updatedAt = Date()
        save()
    }

    private func save() {
        do { try modelContext.save() } catch {
            assertionFailure("TriggerSettings save failed: \(error)")
        }
    }
}

// MARK: - Active row

private struct TriggerRow: View {
    @Bindable var trigger: TriggerDefinition
    let onArchive: () -> Void
    @Environment(\.modelContext) private var modelContext

    var body: some View {
        HStack {
            TextField("Name", text: $trigger.name)
                .onChange(of: trigger.name) { _, _ in
                    trigger.updatedAt = Date()
                    try? modelContext.save()
                }
            Toggle("Show on Today", isOn: $trigger.isActive)
                .labelsHidden()
                .onChange(of: trigger.isActive) { _, _ in
                    trigger.updatedAt = Date()
                    try? modelContext.save()
                }
        }
        .swipeActions(edge: .trailing) {
            Button(role: .destructive, action: onArchive) {
                Label("Archive", systemImage: "archivebox")
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(trigger.name), \(trigger.isActive ? "shown on Today" : "hidden from Today")")
    }
}

// MARK: - Archived

private struct ArchivedTriggersView: View {
    @Environment(\.modelContext) private var modelContext

    @Query(
        filter: #Predicate<TriggerDefinition> { $0.isArchived },
        sort: [SortDescriptor(\TriggerDefinition.name)]
    )
    private var archived: [TriggerDefinition]

    var body: some View {
        List {
            if archived.isEmpty {
                ContentUnavailableView(
                    "Nothing archived",
                    systemImage: "archivebox",
                    description: Text("Archived triggers stay in history and exports.")
                )
            } else {
                ForEach(archived) { trigger in
                    HStack {
                        Text(trigger.name)
                        Spacer()
                        Button("Unarchive") { unarchive(trigger) }
                            .buttonStyle(.bordered)
                            .controlSize(.small)
                    }
                }
            }
        }
        .navigationTitle("Archived triggers")
    }

    private func unarchive(_ trigger: TriggerDefinition) {
        trigger.isArchived = false
        trigger.isActive = true
        trigger.updatedAt = Date()
        do { try modelContext.save() } catch {
            assertionFailure("Unarchive failed: \(error)")
        }
    }
}

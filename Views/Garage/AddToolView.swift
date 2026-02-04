import SwiftUI
import CoreData

/// View for creating a new tool entry in the Garage.
/// Saves directly to Core Data via the managed object context.
/// Supports optional group assignment for organizing tools in nested groups.
struct AddToolView: View {
    @Environment(\.managedObjectContext) private var viewContext
    @Environment(\.dismiss) private var dismiss

    /// Fetch all tool groups for the group picker
    @FetchRequest(
        sortDescriptors: [
            NSSortDescriptor(keyPath: \ToolGroup.sortOrder, ascending: true),
            NSSortDescriptor(keyPath: \ToolGroup.name, ascending: true)
        ],
        animation: .default
    )
    private var allGroups: FetchedResults<ToolGroup>

    @State private var name: String = ""
    @State private var ownershipType: String = "personal"
    @State private var borrowedFrom: String = ""
    @State private var notes: String = ""
    @State private var aliasText: String = ""
    @State private var selectedGroup: ToolGroup?
    @State private var showingError = false
    @State private var errorMessage = ""
    @State private var showingSuccess = false
    @State private var savedToolName = ""

    /// Optional pre-selected group (when adding tool from within a group)
    var initialGroup: ToolGroup?

    private let ownershipOptions = ["personal", "shop", "borrowed"]

    var body: some View {
        NavigationStack {
            Form {
                // MARK: - Tool Name
                Section(header: Text("Tool Name")) {
                    TextField("e.g., 3/8\" Torque Wrench", text: $name)
                        .font(.body)
                        .autocorrectionDisabled()
                }

                // MARK: - Group Assignment
                if !allGroups.isEmpty {
                    Section(header: Text("Tool Group (Optional)")) {
                        Picker("Group", selection: $selectedGroup) {
                            Text("No Group").tag(nil as ToolGroup?)
                            ForEach(allGroups, id: \.objectID) { group in
                                Text(groupDisplayName(for: group))
                                    .tag(group as ToolGroup?)
                            }
                        }
                    }
                }

                // MARK: - Ownership
                Section(header: Text("Ownership")) {
                    Picker("Type", selection: $ownershipType) {
                        Text("Personal").tag("personal")
                        Text("Shop").tag("shop")
                        Text("Borrowed").tag("borrowed")
                    }
                    .pickerStyle(.segmented)

                    if ownershipType == "borrowed" {
                        TextField("Borrowed from...", text: $borrowedFrom)
                            .font(.body)
                    }
                }

                // MARK: - Aliases
                Section(header: Text("Aliases (Optional)")) {
                    TextField("e.g., Dog Bone, Torque Adapter", text: $aliasText, axis: .vertical)
                        .font(.body)
                        .lineLimit(2...4)
                    Text("Comma-separated alternate names for this tool")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }

                // MARK: - Notes
                Section(header: Text("Notes (Optional)")) {
                    TextField("Size, spec, or other notes", text: $notes, axis: .vertical)
                        .lineLimit(3...6)
                }
            }
            .navigationTitle("Add Tool")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cancel") {
                        dismiss()
                    }
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Save") {
                        saveTool()
                    }
                    .fontWeight(.semibold)
                    .disabled(name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
            .alert("Error", isPresented: $showingError) {
                Button("OK") { }
            } message: {
                Text(errorMessage)
            }
            .alert("Tool Saved!", isPresented: $showingSuccess) {
                Button("OK") {
                    dismiss()
                }
            } message: {
                Text("'\(savedToolName)' has been added to your Garage.")
            }
            .onAppear {
                if let initial = initialGroup {
                    selectedGroup = initial
                }
            }
        }
    }

    // MARK: - Helpers

    /// Builds a display name showing the group hierarchy path (e.g., "1/4-inch Drive > Shallow Sockets")
    private func groupDisplayName(for group: ToolGroup) -> String {
        var path = [group.name ?? "Unnamed"]
        var current = group
        while let parent = current.parentGroup {
            path.insert(parent.name ?? "Unnamed", at: 0)
            current = parent
        }
        return path.joined(separator: " > ")
    }

    // MARK: - Save

    private func saveTool() {
        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedName.isEmpty else {
            errorMessage = "Tool name cannot be empty."
            showingError = true
            return
        }

        let tool = Tool(context: viewContext)
        tool.id = UUID()
        tool.name = trimmedName
        tool.ownershipType = ownershipType
        tool.createdAt = Date()
        tool.group = selectedGroup

        if ownershipType == "borrowed" && !borrowedFrom.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            tool.borrowedFrom = borrowedFrom.trimmingCharacters(in: .whitespacesAndNewlines)
        }

        let trimmedNotes = notes.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmedNotes.isEmpty {
            tool.notes = trimmedNotes
        }

        // Parse aliases from comma-separated text
        let parsedAliases = aliasText
            .split(separator: ",")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        if !parsedAliases.isEmpty {
            tool.aliases = parsedAliases as NSArray
        }

        do {
            try viewContext.save()
            print("AddToolView: Saved tool '\(trimmedName)' to Core Data (group: \(selectedGroup?.name ?? "none"))")
            savedToolName = trimmedName
            showingSuccess = true
        } catch {
            viewContext.rollback()
            errorMessage = "Failed to save tool: \(error.localizedDescription)"
            showingError = true
            print("AddToolView: Save failed, rolled back - \(error)")
        }
    }
}

#Preview {
    AddToolView()
        .environment(\.managedObjectContext, PersistenceController.preview.container.viewContext)
}

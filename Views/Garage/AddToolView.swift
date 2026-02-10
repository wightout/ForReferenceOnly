import SwiftUI
import Foundation
import SwiftData
import PhotosUI

/// View for creating a new tool entry in the Garage.
/// Saves directly to Core Data via the managed object context.
/// Supports optional set assignment for organizing tools in nested sets.
/// Feature #130: Renamed from "Tool Group" to "Tool Set" throughout UI.
/// Feature #133: Tool Sets only show matching ownership (Personal sets for Personal tools, Shop sets for Shop tools).
struct AddToolView: View {
    @Environment(\.modelContext) private var viewContext
    @Environment(\.dismiss) private var dismiss

    /// Fetch all tool sets for the set picker
    @Query(sort: [SortDescriptor(\FROToolGroup.sortOrder, order: .forward), SortDescriptor(\FROToolGroup.name, order: .forward)])
    private var allGroups: [FROToolGroup]

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
    @State private var photoImages: [UIImage] = []

    /// Optional pre-selected set (when adding tool from within a set)
    var initialGroup: ToolGroup?

    private let ownershipOptions = ["personal", "shop", "borrowed"]

    /// Feature #133: Filtered Tool Sets that match the current ownership type.
    /// A Personal tool can only be added to a Personal Tool Set.
    /// A Shop tool can only be added to a Shop Tool Set.
    /// Borrowed tools cannot be added to any Tool Set.
    private var matchingGroups: [ToolGroup] {
        Array(allGroups).filter { group in
            let groupOwnership = group.ownershipType
            return groupOwnership == ownershipType
        }
    }

    var body: some View {
        NavigationStack {
            Form {
                // MARK: - Tool Name
                Section {
                    TextField("e.g., 3/8\" Torque Wrench", text: $name)
                        .font(.body)
                        .autocorrectionDisabled()
                } header: {
                    Text("Tool Name")
                }

                // MARK: - Ownership
                // Feature #121: The ownership section must come before group assignment.
                // If "Borrowed" is selected, the group picker is hidden (borrowed tools cannot be in groups).
                Section {
                    Picker("Type", selection: $ownershipType) {
                        Text("Personal").tag("personal")
                        Text("Shop").tag("shop")
                        Text("Borrowed").tag("borrowed")
                    }
                    .pickerStyle(.segmented)
                    .accessibilityIdentifier("addToolOwnershipPicker")

                    // Feature #104: Borrowed from field autocompletes from previous entries
                    if ownershipType == "borrowed" {
                        BorrowedFromAutocompleteField(
                            borrowedFrom: $borrowedFrom,
                            placeholder: "Borrowed from...",
                            accessibilityPrefix: "addTool_"
                        )
                    }
                } header: {
                    Text("Ownership")
                }
                // Feature #121: When ownership changes to "borrowed", clear any selected set
                // Feature #133: When ownership changes, clear the selected set if it doesn't match
                .onChange(of: ownershipType) { oldValue, newValue in
                    if newValue == "borrowed" && selectedGroup != nil {
                        selectedGroup = nil
                    } else if let group = selectedGroup {
                        // Feature #133: Clear selection if the group ownership doesn't match the new tool ownership
                        let groupOwnership = group.ownershipType
                        if groupOwnership != newValue {
                            selectedGroup = nil
                        }
                    }
                }

                // MARK: - Set Assignment
                // Feature #121: Set picker is only shown for Personal and Shop tools.
                // Feature #130: Renamed from "Tool Group" to "Tool Set".
                // Feature #133: Only show Tool Sets matching the tool's ownership type.
                // Borrowed tools cannot be added to Tool Sets - they remain standalone in the Borrowed section.
                if ownershipType != "borrowed" {
                    Section {
                        if matchingGroups.isEmpty {
                            // No matching Tool Sets available
                            HStack(spacing: 8) {
                                Image(systemName: "folder.badge.questionmark")
                                    .foregroundColor(.secondary)
                                Text("No \(ownershipType == "personal" ? "Personal" : "Shop") Tool Sets available")
                                    .foregroundColor(.secondary)
                            }
                            .font(.subheadline)
                            .padding(.vertical, 4)
                            .accessibilityIdentifier("noMatchingGroupsMessage")
                        } else {
                            Picker("Set", selection: $selectedGroup) {
                                Text("No Set").tag(nil as ToolGroup?)
                                ForEach(matchingGroups, id: \.id) { group in
                                    Text(groupDisplayName(for: group))
                                        .tag(group as ToolGroup?)
                                }
                            }
                            .accessibilityIdentifier("addToolGroupPicker")
                        }
                    } header: {
                        Text("Tool Set (Optional)")
                    } footer: {
                        // Feature #133: Explain why only certain sets are shown
                        Text("\(ownershipType == "personal" ? "Personal" : "Shop") tools can only be added to \(ownershipType == "personal" ? "Personal" : "Shop") Tool Sets.")
                            .font(.caption)
                            .foregroundColor(.secondary)
                            .accessibilityIdentifier("addToolGroupFooter")
                    }
                }

                // MARK: - Aliases
                Section {
                    TextField("e.g., Dog Bone, Torque Adapter", text: $aliasText, axis: .vertical)
                        .font(.body)
                        .lineLimit(2...4)
                    Text("Comma-separated alternate names for this tool")
                        .font(.caption)
                        .foregroundColor(.secondary)
                } header: {
                    Text("Aliases (Optional)")
                }

                // MARK: - Notes
                Section {
                    TextField("Size, spec, or other notes", text: $notes, axis: .vertical)
                        .lineLimit(3...6)
                } header: {
                    Text("Notes (Optional)")
                }

                // MARK: - Photos
                ToolPhotoEditorSection(images: $photoImages)
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

    /// Builds a display name showing the set hierarchy path (e.g., "1/4-inch Drive > Shallow Sockets")
    private func groupDisplayName(for group: ToolGroup) -> String {
        var path = [group.name]
        var current = group
        while let parent = current.parentGroup {
            path.insert(parent.name, at: 0)
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

        let tool = FROTool(name: trimmedName, ownershipType: ownershipType)
        viewContext.insert(tool)
        // Feature #121: Borrowed tools cannot be in sets - enforce this rule
        tool.group = (ownershipType == "borrowed") ? nil : selectedGroup
        // Feature #96: Mark as in Garage so it appears in filtered lists
        tool.isInGarage = true

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
            tool.aliases = parsedAliases
        }

        do {
            try viewContext.save()

            // Save photos after Core Data save (tool needs valid ID)
            if !photoImages.isEmpty {
                try ToolPhotoService.shared.saveAllPhotos(photoImages, for: tool, context: viewContext)
            }

            print("AddToolView: Saved tool '\(trimmedName)' to Core Data (group: \(selectedGroup?.name ?? "none"), photos: \(photoImages.count))")
            savedToolName = trimmedName
            showingSuccess = true
        } catch {
            errorMessage = "Failed to save tool: \(error.localizedDescription)"
            showingError = true
            print("AddToolView: Save failed, rolled back - \(error)")
        }
    }
}

#Preview {
    AddToolView()
        
}

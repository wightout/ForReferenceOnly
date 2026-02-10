import SwiftUI
import PhotosUI

/// View for editing an existing tool entry in the Garage.
/// Pre-populates fields with existing data and saves changes to Core Data.
/// Feature #121: If ownership is changed to "borrowed", the tool is removed from any group.
/// Feature #122: If ownership is changed to "borrowed", the tool is also removed from any Tool Kits.
/// Feature #133: If ownership changes and no longer matches the Tool Set, remove from the set.
struct EditToolView: View {
    @Environment(\.modelContext) private var viewContext
    @Environment(\.dismiss) private var dismiss

    @Bindable var tool: Tool

    @State private var name: String = ""
    @State private var ownershipType: String = "personal"
    @State private var borrowedFrom: String = ""
    @State private var notes: String = ""
    @State private var aliasText: String = ""
    @State private var showingError = false
    @State private var errorMessage = ""
    @State private var showingSuccess = false
    @State private var savedToolName = ""
    @State private var showingPurchaseConfirmation = false
    @State private var showingPurchaseSuccess = false

    // Photo management
    @State private var photoImages: [UIImage] = []
    @State private var photosLoaded = false

    // Feature #121: Track if tool was in a group before editing
    @State private var originalGroupName: String? = nil
    @State private var willBeRemovedFromGroup: Bool = false

    // Feature #122: Track if tool was in any kits before editing
    @State private var originalKitCount: Int = 0
    @State private var willBeRemovedFromKits: Bool = false

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

                // MARK: - Ownership
                Section(header: Text("Ownership")) {
                    Picker("Type", selection: $ownershipType) {
                        Text("Personal").tag("personal")
                        Text("Shop").tag("shop")
                        Text("Borrowed").tag("borrowed")
                    }
                    .pickerStyle(.segmented)
                    .accessibilityIdentifier("editToolOwnershipPicker")
                    // Feature #121: Track when ownership changes to borrowed while tool is in a group
                    // Feature #122: Also track when tool is in any kits
                    // Feature #133: Track when ownership no longer matches the Tool Set's ownership
                    .onChange(of: ownershipType) { oldValue, newValue in
                        // Check if tool will be removed from group due to borrowed status
                        // OR due to ownership mismatch (Feature #133)
                        if let group = tool.group {
                            let groupOwnership = group.ownershipType
                            willBeRemovedFromGroup = (newValue == "borrowed") || (groupOwnership != newValue)
                        } else {
                            willBeRemovedFromGroup = false
                        }
                        let kitCount = tool.toolKits?.count ?? 0
                        willBeRemovedFromKits = (newValue == "borrowed" && kitCount > 0)
                    }

                    // Feature #104: Borrowed from field autocompletes from previous entries
                    if ownershipType == "borrowed" {
                        TextField("Borrowed from...", text: $borrowedFrom)
                            .textInputAutocapitalization(.words)
                            .autocorrectionDisabled()
                            .accessibilityIdentifier("editTool_borrowedFrom")
                    }

                    // Feature #121 & #133: Warning when tool will be removed from group
                    if willBeRemovedFromGroup, let groupName = tool.group?.name {
                        HStack(spacing: 8) {
                            Image(systemName: "exclamationmark.triangle.fill")
                                .foregroundColor(Color(red: 0.976, green: 0.451, blue: 0.086)) // Safety orange
                            // Feature #133: Different message based on reason for removal
                            if ownershipType == "borrowed" {
                                Text("This tool will be removed from '\(groupName)' because borrowed tools cannot be in Tool Sets.")
                                    .font(.caption)
                                    .foregroundColor(Color(red: 0.976, green: 0.451, blue: 0.086))
                            } else {
                                Text("This tool will be removed from '\(groupName)' because \(ownershipType == "personal" ? "Personal" : "Shop") tools can only be in \(ownershipType == "personal" ? "Personal" : "Shop") Tool Sets.")
                                    .font(.caption)
                                    .foregroundColor(Color(red: 0.976, green: 0.451, blue: 0.086))
                            }
                        }
                        .padding(.vertical, 4)
                        .accessibilityIdentifier("editTool_groupRemovalWarning")
                    }

                    // Feature #122: Warning when changing to borrowed while in kits
                    if willBeRemovedFromKits {
                        let kitCount = tool.toolKits?.count ?? 0
                        HStack(spacing: 8) {
                            Image(systemName: "exclamationmark.triangle.fill")
                                .foregroundColor(Color(red: 0.976, green: 0.451, blue: 0.086)) // Safety orange
                            Text("This tool will be removed from \(kitCount) kit\(kitCount == 1 ? "" : "s") because borrowed tools cannot be in kits.")
                                .font(.caption)
                                .foregroundColor(Color(red: 0.976, green: 0.451, blue: 0.086))
                        }
                        .padding(.vertical, 4)
                        .accessibilityIdentifier("editTool_kitRemovalWarning")
                    }
                }

                // MARK: - Quick Actions (Purchase)
                // Only shown when the tool is currently borrowed
                if tool.ownershipType == "borrowed" {
                    Section(header: Text("Quick Actions")) {
                        Button {
                            showingPurchaseConfirmation = true
                        } label: {
                            HStack(spacing: 8) {
                                Image(systemName: "cart.badge.checkmark")
                                    .font(.body)
                                Text("Mark as Purchased")
                                    .font(.body)
                                    .fontWeight(.medium)
                            }
                            .foregroundColor(Color(red: 0.133, green: 0.773, blue: 0.369))
                        }
                        .accessibilityIdentifier("editTool_markAsPurchasedButton")

                        Text("Converts this borrowed tool to personal. All job records will automatically update.")
                            .font(.caption)
                            .foregroundColor(.secondary)
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

                // MARK: - Photos
                ToolPhotoEditorSection(images: $photoImages)
            }
            .navigationTitle("Edit Tool")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cancel") {
                        dismiss()
                    }
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Save") {
                        saveChanges()
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
            .alert("Tool Updated!", isPresented: $showingSuccess) {
                Button("OK") {
                    dismiss()
                }
            } message: {
                Text("'\(savedToolName)' has been updated successfully.")
            }
            .alert("Mark as Purchased?", isPresented: $showingPurchaseConfirmation) {
                Button("Cancel", role: .cancel) { }
                Button("Mark as Purchased") {
                    ToolService().markAsPurchased(tool)
                    // Update local state to reflect the change
                    ownershipType = "personal"
                    borrowedFrom = ""
                    willBeRemovedFromGroup = false
                    willBeRemovedFromKits = false
                    showingPurchaseSuccess = true
                }
            } message: {
                Text("'\(tool.name)' will be converted from borrowed to personal. All job records will automatically reflect this change.")
            }
            .alert("Tool Purchased!", isPresented: $showingPurchaseSuccess) {
                Button("OK") {
                    dismiss()
                }
            } message: {
                Text("'\(tool.name)' is now a personal tool.")
            }
            .onAppear {
                // Pre-populate fields with existing tool data
                name = tool.name
                ownershipType = tool.ownershipType
                borrowedFrom = tool.borrowedFrom ?? ""
                notes = tool.notes ?? ""
                if let aliases = tool.aliases {
                    aliasText = aliases.joined(separator: ", ")
                }
                // Feature #121: Track original group for warning display
                originalGroupName = tool.group?.name
                // Feature #122: Track original kit count for warning display
                originalKitCount = tool.toolKits?.count ?? 0

                // Load existing photos
                if !photosLoaded {
                    let loaded = ToolPhotoService.shared.loadAllPhotos(for: tool)
                    photoImages = loaded.map { $0.image }
                    photosLoaded = true
                }
            }
        }
    }

    // MARK: - Save Changes

    private func saveChanges() {
        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedName.isEmpty else {
            errorMessage = "Tool name cannot be empty."
            showingError = true
            return
        }

        tool.name = trimmedName
        tool.ownershipType = ownershipType

        // Feature #121 & #122 & #133: Handle group/kit removal based on ownership
        if ownershipType == "borrowed" {
            let trimmedBorrowed = borrowedFrom.trimmingCharacters(in: .whitespacesAndNewlines)
            tool.borrowedFrom = trimmedBorrowed.isEmpty ? nil : trimmedBorrowed

            // Feature #121: Remove from any group - borrowed tools are standalone
            if tool.group != nil {
                let removedGroupName = tool.group?.name ?? "unknown"
                tool.group = nil
                print("EditToolView: Removed tool '\(trimmedName)' from group '\(removedGroupName)' due to borrowed ownership")
            }

            // Feature #122: Remove from any kits - borrowed tools cannot be in kits
            if let kits = tool.toolKits, !kits.isEmpty {
                let kitNames = kits.map { $0.name }.joined(separator: ", ")
                tool.toolKits = []
                print("EditToolView: Removed tool '\(trimmedName)' from \(kits.count) kit(s): [\(kitNames)] due to borrowed ownership")
            }
        } else {
            tool.borrowedFrom = nil

            // Feature #133: Remove from group if ownership no longer matches the group's ownership
            if let group = tool.group {
                let groupOwnership = group.ownershipType
                if groupOwnership != ownershipType {
                    let removedGroupName = group.name
                    tool.group = nil
                    print("EditToolView: Removed tool '\(trimmedName)' from group '\(removedGroupName)' due to ownership mismatch (\(ownershipType) tool in \(groupOwnership) group)")
                }
            }
        }

        let trimmedNotes = notes.trimmingCharacters(in: .whitespacesAndNewlines)
        tool.notes = trimmedNotes.isEmpty ? nil : trimmedNotes

        // Parse and save aliases
        let parsedAliases = aliasText
            .split(separator: ",")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        tool.aliases = parsedAliases.isEmpty ? nil : parsedAliases

        do {
            try viewContext.save()

            // Save photos after Core Data save (tool needs valid ID)
            if !photoImages.isEmpty {
                try ToolPhotoService.shared.saveAllPhotos(photoImages, for: tool, context: viewContext)
            } else if ToolPhotoService.shared.hasPhotos(tool) {
                // User removed all photos
                ToolPhotoService.shared.deleteAllPhotos(for: tool.id)
                tool.photoFileNames = nil
                try viewContext.save()
            }

            print("EditToolView: Updated tool '\(trimmedName)' (\(ownershipType)) in Core Data")
            savedToolName = trimmedName
            showingSuccess = true
        } catch {
            errorMessage = "Failed to save changes: \(error.localizedDescription)"
            showingError = true
            print("EditToolView: Save failed, rolled back - \(error)")
        }
    }
}

#Preview {
    let tool = FROTool(name: "Test Wrench", ownershipType: "personal", notes: "Standard wrench")
    EditToolView(tool: tool)
        .modelContainer(for: [FROTool.self, FROJob.self, FROToolGroup.self, FROToolKit.self, FROConsumable.self, FROChemical.self, FROPart.self], inMemory: true)
}

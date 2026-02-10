import SwiftUI
import Foundation
import SwiftData
import PhotosUI

/// View for editing an existing tool set in the Garage.
/// Feature #107: Allows changing the measurement type (SAE or Metric).
/// Feature #130: Renamed from "Tool Group" to "Tool Set" throughout UI.
/// Feature #131: Allows changing the ownership type (Personal/Shop).
/// Feature #138: When ownership changes, removes tools that don't match the new ownership.
struct EditToolGroupView: View {
    @Environment(\.modelContext) private var viewContext
    @Environment(\.dismiss) private var dismiss

    /// The tool group being edited
    @Bindable var toolGroup: ToolGroup

    @State private var name: String = ""
    @State private var measurementType: MeasurementType = .sae
    @State private var ownershipType: ToolGroupOwnershipType = .personal
    @State private var toolType: String = ""
    @State private var showingError = false
    @State private var errorMessage = ""

    // Feature #138: Track ownership changes and tools that will be removed
    @State private var originalOwnershipType: ToolGroupOwnershipType = .personal
    @State private var showingOwnershipWarning = false
    @State private var toolsToRemoveCount: Int = 0
    /// When true, ownership change updates all tools instead of removing them
    @State private var changeAllToolsOwnership = false

    // Photos
    @State private var photoImages: [UIImage] = []
    @State private var photosLoaded = false

    // Inline tool management
    @State private var newToolsText: String = ""
    @State private var toolsToRemoveFromSet: Set<UUID> = []

    /// Fetch all tool groups for autocomplete suggestions
    @Query(sort: [SortDescriptor(\FROToolGroup.sortOrder, order: .forward), SortDescriptor(\FROToolGroup.name, order: .forward)])
    private var allToolGroups: [FROToolGroup]

    /// All unique group names excluding the current group being edited
    private var otherGroupNames: [String] {
        let names = allToolGroups
            .filter { $0.id != toolGroup.id }
            .compactMap { $0.name }
            .filter { !$0.isEmpty }
        let uniqueNames = Set(names)
        return uniqueNames.sorted { $0.localizedCaseInsensitiveCompare($1) == .orderedAscending }
    }

    /// Computed property returning matching group names based on user input.
    private var matchingGroups: [String] {
        let trimmedInput = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmedInput.count >= 2 else { return [] }

        let lowercasedInput = trimmedInput.lowercased()
        return otherGroupNames.filter { groupName in
            groupName.lowercased().contains(lowercasedInput)
        }
    }

    /// Whether to show the suggestions/warning dropdown
    private var showSuggestions: Bool {
        let trimmedInput = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmedInput.count >= 2 else { return false }
        guard !matchingGroups.isEmpty else { return false }
        return true
    }

    /// Feature #138: Get all tools in this Tool Set
    private var toolsInSet: [Tool] {
        (toolGroup.tools).map { Array($0) } ?? []
    }

    /// Feature #138: Count tools that don't match the current selected ownership type
    /// These tools will be removed if the ownership change is saved
    private var mismatchedToolsCount: Int {
        toolsInSet.filter { tool in
            let toolOwnership = tool.ownershipType
            return toolOwnership != ownershipType.rawValue
        }.count
    }

    /// Feature #138: Get names of tools that will be removed (for display in warning)
    private var mismatchedToolNames: [String] {
        toolsInSet.filter { tool in
            let toolOwnership = tool.ownershipType
            return toolOwnership != ownershipType.rawValue
        }.compactMap { $0.name }
    }

    /// Feature #138: Whether ownership has changed from original and will cause tool removal
    private var ownershipWillRemoveTools: Bool {
        ownershipType != originalOwnershipType && mismatchedToolsCount > 0
    }

    /// Tools currently in this set, excluding those marked for removal, sorted by name
    private var currentToolsDisplay: [Tool] {
        toolsInSet
            .filter { !toolsToRemoveFromSet.contains($0.id) }
            .sorted { $0.name < $1.name }
    }

    /// Tools marked for removal from the set
    private var toolsMarkedForRemoval: [Tool] {
        toolsInSet.filter { toolsToRemoveFromSet.contains($0.id) }
    }

    /// Measurement type for this group
    private var groupMeasurementType: MeasurementType {
        MeasurementType(rawValue: toolGroup.measurementType ?? "sae") ?? .sae
    }

    /// Parsed new tool sizes from multi-line input
    private var parsedNewToolSizes: [String] {
        ToolNameFormatter.parseLineSeparatedSizes(newToolsText)
    }

    /// Preview of new formatted tool names
    private var previewNewToolNames: [String] {
        parsedNewToolSizes.map { ToolNameFormatter.formatToolName($0, measurementType: measurementType) }
    }

    var body: some View {
        NavigationStack {
            Form {
                // MARK: - Set Name
                Section(header: Text("Set Name")) {
                    TextField("e.g., 1/4-inch Drive", text: $name)
                        .font(.body)
                        .autocorrectionDisabled()
                        .accessibilityIdentifier("editToolGroupNameField")

                    // Autocomplete warning about similar groups
                    if showSuggestions {
                        VStack(alignment: .leading, spacing: 0) {
                            HStack(spacing: 6) {
                                Image(systemName: "exclamationmark.triangle.fill")
                                    .font(.caption)
                                    .foregroundColor(Color(red: 0.976, green: 0.451, blue: 0.086))
                                Text("Similar sets exist:")
                                    .font(.caption)
                                    .fontWeight(.medium)
                                    .foregroundColor(Color(red: 0.976, green: 0.451, blue: 0.086))
                            }
                            .padding(.horizontal, 12)
                            .padding(.top, 8)
                            .padding(.bottom, 4)

                            ForEach(matchingGroups.prefix(5), id: \.self) { suggestion in
                                HStack(spacing: 10) {
                                    Image(systemName: "folder.fill")
                                        .font(.caption)
                                        .foregroundColor(Color(red: 0.145, green: 0.388, blue: 0.922))

                                    Text(suggestion)
                                        .font(.subheadline)
                                        .foregroundColor(.primary)

                                    Spacer()
                                }
                                .padding(.horizontal, 12)
                                .padding(.vertical, 8)

                                if suggestion != matchingGroups.prefix(5).last {
                                    Divider()
                                        .padding(.leading, 12)
                                }
                            }

                            if matchingGroups.count > 5 {
                                Text("+ \(matchingGroups.count - 5) more matching sets")
                                    .font(.caption2)
                                    .foregroundColor(.secondary)
                                    .padding(.horizontal, 12)
                                    .padding(.vertical, 6)
                            }
                        }
                        .background(Color(UIColor.secondarySystemBackground))
                        .cornerRadius(8)
                    }
                }

                // MARK: - Ownership Type
                // Feature #131: Tool Sets have ownership property (Personal/Shop)
                // Feature #138: Shows warning when changing ownership would remove tools
                Section(header: Text("Ownership")) {
                    Picker("Ownership", selection: $ownershipType) {
                        ForEach(ToolGroupOwnershipType.allCases) { type in
                            Text(type.displayName).tag(type)
                        }
                    }
                    .pickerStyle(.segmented)
                    .accessibilityIdentifier("editToolGroupOwnershipPicker")

                    // Help text describing ownership
                    HStack(spacing: 8) {
                        Image(systemName: ownershipType == .personal ? "person.fill" : "building.2.fill")
                            .font(.caption)
                            .foregroundColor(Color(red: 0.145, green: 0.388, blue: 0.922))
                        Text(ownershipType.description)
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    .padding(.vertical, 4)
                    .accessibilityIdentifier("editToolGroupOwnershipDescription")

                    // Feature #138: Warning when ownership change will affect tools
                    if ownershipWillRemoveTools {
                        VStack(alignment: .leading, spacing: 8) {
                            HStack(spacing: 8) {
                                Image(systemName: "info.circle.fill")
                                    .foregroundColor(Color(red: 0.145, green: 0.388, blue: 0.922)) // Industrial blue
                                Text("\(mismatchedToolsCount) \(originalOwnershipType.displayName) tool\(mismatchedToolsCount == 1 ? "" : "s") in this set")
                                    .font(.subheadline)
                                    .fontWeight(.semibold)
                                    .foregroundColor(Color(red: 0.145, green: 0.388, blue: 0.922))
                            }

                            Text("When saving, you can change \(mismatchedToolsCount == 1 ? "this tool" : "all \(mismatchedToolsCount) tools") to \(ownershipType.displayName) or remove \(mismatchedToolsCount == 1 ? "it" : "them") from the set.")
                                .font(.caption)
                                .foregroundColor(.secondary)

                            // Show tool names if not too many
                            if mismatchedToolsCount <= 5 && !mismatchedToolNames.isEmpty {
                                Text("Affected tools: \(mismatchedToolNames.joined(separator: ", "))")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                                    .padding(.top, 2)
                            } else if mismatchedToolsCount > 5 {
                                Text("Affected tools: \(mismatchedToolNames.prefix(3).joined(separator: ", ")) and \(mismatchedToolsCount - 3) more...")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                                    .padding(.top, 2)
                            }
                        }
                        .padding(.vertical, 8)
                        .accessibilityIdentifier("editToolGroup_ownershipChangeWarning")
                    }
                }

                // MARK: - Tool Type
                Section(header: Text("Tool Type (Optional)")) {
                    TextField("e.g., Socket, Wrench, Screwdriver", text: $toolType)
                        .autocorrectionDisabled()
                        .accessibilityIdentifier("editToolGroup_toolTypeField")

                    HStack(spacing: 8) {
                        Image(systemName: "tag")
                            .font(.caption)
                            .foregroundColor(Color(red: 0.145, green: 0.388, blue: 0.922))
                        Text("Singular name for each tool in this set. Appended to tool names on PDF exports and when tools are removed from the set.")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    .padding(.vertical, 4)
                    .accessibilityIdentifier("editToolGroup_toolTypeDescription")
                }

                // MARK: - Measurement Type
                Section(header: Text("Measurement Type")) {
                    Picker("Measurement", selection: $measurementType) {
                        ForEach(MeasurementType.allCases) { type in
                            Text(type.displayName).tag(type)
                        }
                    }
                    .pickerStyle(.segmented)
                    .accessibilityIdentifier("editMeasurementTypePicker")

                    HStack(spacing: 8) {
                        Image(systemName: "ruler")
                            .font(.caption)
                            .foregroundColor(Color(red: 0.145, green: 0.388, blue: 0.922))
                        Text(measurementType.examples)
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    .padding(.vertical, 4)
                    .accessibilityIdentifier("editMeasurementTypeExamples")
                }

                // MARK: - Parent Info (read-only)
                if let parent = toolGroup.parentGroup {
                    Section(header: Text("Parent Set")) {
                        HStack {
                            Image(systemName: "folder.fill")
                                .foregroundColor(Color(red: 0.145, green: 0.388, blue: 0.922))
                            Text(parent.name)
                                .foregroundColor(.secondary)

                            Spacer()

                            if let parentMeasurement = parent.measurementType {
                                Text(MeasurementType(rawValue: parentMeasurement)?.displayName ?? "SAE")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                        }
                    }
                }

                // MARK: - Set Info
                Section(header: Text("Set Info")) {
                    let childGroupCount = (toolGroup.childGroups)?.count ?? 0

                    HStack {
                        Image(systemName: "wrench.fill")
                            .foregroundColor(Color(red: 0.145, green: 0.388, blue: 0.922))
                            .font(.caption)
                        Text("Tools in this set:")
                        Spacer()
                        Text("\(currentToolsDisplay.count)")
                            .foregroundColor(.secondary)
                    }

                    HStack {
                        Image(systemName: "folder.fill")
                            .foregroundColor(Color(red: 0.145, green: 0.388, blue: 0.922))
                            .font(.caption)
                        Text("Sub-sets:")
                        Spacer()
                        Text("\(childGroupCount)")
                            .foregroundColor(.secondary)
                    }
                }

                // MARK: - Tools in Set
                Section {
                    if currentToolsDisplay.isEmpty && toolsMarkedForRemoval.isEmpty {
                        Text("No tools in this set")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                            .accessibilityIdentifier("editToolGroup_noToolsMessage")
                    }

                    ForEach(currentToolsDisplay, id: \.id) { tool in
                        HStack(spacing: 10) {
                            Image(systemName: "wrench.fill")
                                .font(.caption)
                                .foregroundColor(Color(red: 0.145, green: 0.388, blue: 0.922))
                            Text(tool.name)
                                .font(.body)
                            Spacer()
                            Button(action: { toolsToRemoveFromSet.insert(tool.id) }) {
                                Image(systemName: "xmark.circle.fill")
                                    .foregroundColor(.secondary)
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel("Remove \(tool.name) from set")
                        }
                    }

                    // Tools marked for removal
                    if !toolsMarkedForRemoval.isEmpty {
                        HStack(spacing: 6) {
                            Image(systemName: "exclamationmark.triangle.fill")
                                .font(.caption)
                                .foregroundColor(Color(red: 0.976, green: 0.451, blue: 0.086))
                            Text("Marked for Removal (\(toolsMarkedForRemoval.count))")
                                .font(.caption)
                                .fontWeight(.medium)
                                .foregroundColor(Color(red: 0.976, green: 0.451, blue: 0.086))
                        }
                        .padding(.top, 4)

                        ForEach(toolsMarkedForRemoval, id: \.id) { tool in
                            HStack(spacing: 10) {
                                Image(systemName: "wrench.fill")
                                    .font(.caption)
                                    .foregroundColor(Color(red: 0.976, green: 0.451, blue: 0.086).opacity(0.5))
                                Text(tool.name)
                                    .font(.body)
                                    .strikethrough()
                                    .foregroundColor(.secondary)
                                Spacer()
                                Button(action: { toolsToRemoveFromSet.remove(tool.id) }) {
                                    Image(systemName: "arrow.uturn.backward.circle")
                                        .foregroundColor(Color(red: 0.145, green: 0.388, blue: 0.922))
                                }
                                .buttonStyle(.plain)
                                .accessibilityLabel("Undo remove \(tool.name)")
                            }
                        }
                    }
                } header: {
                    Text("Tools in Set")
                } footer: {
                    Text("Removed tools will be ungrouped but remain in your Garage.")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }

                // MARK: - Add New Tools
                Section {
                    TextField("One size per line, e.g.:\n1/4\n5/16\n3/8", text: $newToolsText, axis: .vertical)
                        .font(.body)
                        .autocorrectionDisabled()
                        .lineLimit(3...10)
                        .accessibilityIdentifier("editToolGroup_newToolSizesField")

                    Text("Enter one size per line. Auto-formatted as \(measurementType.displayName).")
                        .font(.caption)
                        .foregroundColor(.secondary)

                    // Example hint
                    HStack(spacing: 8) {
                        Image(systemName: "lightbulb.fill")
                            .font(.caption)
                            .foregroundColor(Color(red: 0.976, green: 0.451, blue: 0.086))
                        Text("Example: \(measurementType == .metric ? "8\n10\n12\n14" : "1/4\n5/16\n3/8\n1/2")")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                } header: {
                    Text("Add New Tools")
                } footer: {
                    Text("New tools will be created as \(ownershipType.displayName) tools, matching the set's ownership.")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }

                // MARK: - New Tools Preview
                if !parsedNewToolSizes.isEmpty {
                    Section(header: Text("Preview (\(parsedNewToolSizes.count) new tools)")) {
                        ForEach(Array(previewNewToolNames.prefix(20).enumerated()), id: \.offset) { index, toolName in
                            HStack(spacing: 10) {
                                Image(systemName: "wrench.fill")
                                    .font(.caption)
                                    .foregroundColor(Color(red: 0.145, green: 0.388, blue: 0.922))
                                Text(toolName)
                                    .font(.subheadline)
                            }
                            .accessibilityIdentifier("editToolGroup_newToolPreview_\(index)")
                        }

                        if previewNewToolNames.count > 20 {
                            Text("+ \(previewNewToolNames.count - 20) more tools")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                    }
                }

                // MARK: - Photos
                ToolPhotoEditorSection(images: $photoImages)
            }
            .navigationTitle("Edit Tool Set")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cancel") {
                        dismiss()
                    }
                    .accessibilityIdentifier("editToolGroup_cancelButton")
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Save") {
                        // Feature #138: Show confirmation if ownership change will remove tools
                        if ownershipWillRemoveTools {
                            toolsToRemoveCount = mismatchedToolsCount
                            showingOwnershipWarning = true
                        } else {
                            saveChanges()
                        }
                    }
                    .fontWeight(.semibold)
                    .disabled(name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    .accessibilityIdentifier("editToolGroup_saveButton")
                }
            }
            .alert("Error", isPresented: $showingError) {
                Button("OK") { }
            } message: {
                Text(errorMessage)
            }
            // Feature #138: Confirmation alert when ownership change will affect tools
            .alert("Ownership Change", isPresented: $showingOwnershipWarning) {
                Button("Change All Tools", role: .none) {
                    changeAllToolsOwnership = true
                    saveChanges()
                }
                .accessibilityIdentifier("editToolGroup_changeAllButton")
                Button("Remove \(toolsToRemoveCount) Tool\(toolsToRemoveCount == 1 ? "" : "s")", role: .destructive) {
                    changeAllToolsOwnership = false
                    saveChanges()
                }
                .accessibilityIdentifier("editToolGroup_confirmRemoveButton")
                Button("Cancel", role: .cancel) {
                    ownershipType = originalOwnershipType
                }
            } message: {
                Text("This set has \(toolsToRemoveCount) \(originalOwnershipType.displayName) tool\(toolsToRemoveCount == 1 ? "" : "s"). You can change \(toolsToRemoveCount == 1 ? "it" : "them all") to \(ownershipType.displayName), or remove \(toolsToRemoveCount == 1 ? "it" : "them") from the set.")
            }
            .onAppear {
                loadCurrentValues()
            }
        }
    }

    // MARK: - Load Current Values

    private func loadCurrentValues() {
        name = toolGroup.name
        if let storedType = toolGroup.measurementType,
           let type = MeasurementType(rawValue: storedType) {
            measurementType = type
        } else {
            measurementType = .sae
        }
        // Load tool type
        toolType = toolGroup.toolType ?? ""

        // Feature #131: Load ownership type
        // Feature #138: Also track original ownership for detecting changes
        if let ownership = ToolGroupOwnershipType(rawValue: toolGroup.ownershipType) {
            ownershipType = ownership
            originalOwnershipType = ownership
        } else {
            ownershipType = .personal
            originalOwnershipType = .personal
        }

        // Load existing photos
        if !photosLoaded {
            let groupID = toolGroup.id
            photoImages = ToolPhotoService.shared.loadAllPhotos(forEntityID: groupID).map { $0.image }
            photosLoaded = true
        }
    }

    // MARK: - Save Changes

    private func saveChanges() {
        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedName.isEmpty else {
            errorMessage = "Set name cannot be empty."
            showingError = true
            return
        }

        toolGroup.name = trimmedName
        toolGroup.measurementType = measurementType.rawValue
        let trimmedToolType = toolType.trimmingCharacters(in: .whitespacesAndNewlines)
        toolGroup.toolType = trimmedToolType.isEmpty ? nil : trimmedToolType

        // Feature #138: If ownership is changing, handle mismatched tools
        let ownershipChanged = ownershipType != originalOwnershipType
        var ownershipChangeCount = 0

        if ownershipChanged {
            let mismatchedTools = toolsInSet.filter { tool in
                let toolOwnership = tool.ownershipType
                return toolOwnership != ownershipType.rawValue
            }
            ownershipChangeCount = mismatchedTools.count

            if changeAllToolsOwnership {
                // User chose "Change All Tools" — update each tool's ownership to match the set
                for tool in mismatchedTools {
                    tool.ownershipType = ownershipType.rawValue
                }
                if !mismatchedTools.isEmpty {
                    let names = mismatchedTools.compactMap { $0.name }
                    print("EditToolGroupView: Changed ownership of \(mismatchedTools.count) tool(s) to '\(ownershipType.rawValue)': [\(names.joined(separator: ", "))]")
                }
            } else {
                // User chose "Remove Tools" — remove mismatched tools from set (tools stay in Garage)
                for tool in mismatchedTools {
                    tool.group = nil
                }
                if !mismatchedTools.isEmpty {
                    let names = mismatchedTools.compactMap { $0.name }
                    print("EditToolGroupView: Feature #138 - Removed \(mismatchedTools.count) tool(s) from '\(trimmedName)' due to ownership change to '\(ownershipType.rawValue)': [\(names.joined(separator: ", "))]")
                }
            }
            changeAllToolsOwnership = false
        }

        // Feature #131: Save ownership type
        toolGroup.ownershipType = ownershipType.rawValue

        // Remove tools manually marked for removal (ungroup, don't delete)
        for toolID in toolsToRemoveFromSet {
            if let tool = fetchByPersistentID(Tool.self, id: toolID, context: viewContext) {
                let toolName = tool.name
                tool.group = nil
                print("EditToolGroupView: Removed '\(toolName)' from set")
            }
        }

        // Create new inline tools
        let newToolSizes = parsedNewToolSizes
        for size in newToolSizes {
            let toolName = ToolNameFormatter.formatToolName(size, measurementType: measurementType)
            let tool = FROTool(name: toolName, ownershipType: ownershipType.rawValue)
            tool.group = toolGroup
            viewContext.insert(tool)
        }

        if !newToolSizes.isEmpty {
            print("EditToolGroupView: Creating \(newToolSizes.count) new inline tools in set '\(trimmedName)'")
        }

        // Save photos for the group
        do {
            let fileNames = try ToolPhotoService.shared.saveAllPhotos(photoImages, forEntityID: toolGroup.id)
            toolGroup.photoFileNames = fileNames.isEmpty ? nil : fileNames
            print("EditToolGroupView: Saved \(fileNames.count) photo(s) for set '\(trimmedName)'")
        } catch {
            print("EditToolGroupView: Failed to save photos - \(error)")
        }

        do {
            try viewContext.save()
            var logParts: [String] = ["Updated group '\(trimmedName)' with ownership '\(ownershipType.rawValue)' and measurement type '\(measurementType.rawValue)'"]
            if ownershipChanged && ownershipChangeCount > 0 {
                logParts.append("Ownership change affected \(ownershipChangeCount) tool(s)")
            }
            if !toolsToRemoveFromSet.isEmpty {
                logParts.append("Manually removed \(toolsToRemoveFromSet.count) tool(s) from set")
            }
            if !newToolSizes.isEmpty {
                logParts.append("Created \(newToolSizes.count) new tool(s)")
            }
            print("EditToolGroupView: \(logParts.joined(separator: ". "))")
            dismiss()
        } catch {
            errorMessage = "Failed to save changes: \(error.localizedDescription)"
            showingError = true
            print("EditToolGroupView: Save failed, rolled back - \(error)")
        }
    }
}

#Preview {
    let group = FROToolGroup(name: "1/4-inch Drive Sockets", sortOrder: 0, ownershipType: "personal")
    EditToolGroupView(toolGroup: group)
        .modelContainer(for: [FROTool.self, FROJob.self, FROToolGroup.self, FROToolKit.self, FROConsumable.self, FROChemical.self, FROPart.self], inMemory: true)
}

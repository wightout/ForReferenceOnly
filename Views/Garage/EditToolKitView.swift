import SwiftUI
import Foundation
import SwiftData
import PhotosUI

/// View for editing an existing tool kit in the Garage.
/// Feature #132: Allows viewing/changing the ownership type (Personal/Shop).
/// Feature #139: When ownership changes, removes tools that don't match the new ownership
/// and displays a warning to the user before confirming the change.
struct EditToolKitView: View {
    @Environment(\.modelContext) private var viewContext
    @Environment(\.dismiss) private var dismiss

    /// The tool kit being edited
    @Bindable var toolKit: ToolKit

    @State private var name: String = ""
    @State private var descriptionText: String = ""
    @State private var toolType: String = ""
    @State private var ownershipType: ToolKitOwnershipType = .personal
    @State private var showingError = false
    @State private var errorMessage = ""

    // Feature #139: Track ownership changes and tools that will be removed
    @State private var originalOwnershipType: ToolKitOwnershipType = .personal
    @State private var showingOwnershipWarning = false
    @State private var toolsToRemoveCount: Int = 0
    /// When true, ownership change updates all tools instead of removing them
    @State private var changeAllToolsOwnership = false

    // Photos
    @State private var photoImages: [UIImage] = []
    @State private var photosLoaded = false

    // Inline tool management
    @State private var showingToolPicker = false
    @State private var selectedNewToolIDs: Set<UUID> = []
    @State private var newToolsText: String = ""
    @State private var newToolsMeasurementType: MeasurementType = .sae
    @State private var toolsToRemoveFromKit: Set<UUID> = []

    /// Fetch all tools for the picker
    @Query(sort: \FROTool.name, order: .forward)
    private var allTools: [FROTool]

    private let industrialBlue = Color(red: 0.145, green: 0.388, blue: 0.922)
    private let steelGray = Color(red: 0.392, green: 0.455, blue: 0.545)
    private let safetyOrange = Color(red: 0.976, green: 0.451, blue: 0.086)
    private let kitColor = Color(red: 0.133, green: 0.545, blue: 0.133) // Green

    /// Feature #139: Get all tools in this Tool Kit
    private var toolsInKit: [Tool] {
        (toolKit.tools).map { Array($0) } ?? []
    }

    /// Feature #139: Count tools that don't match the current selected ownership type
    /// These tools will be removed if the ownership change is saved
    private var mismatchedToolsCount: Int {
        toolsInKit.filter { tool in
            let toolOwnership = tool.ownershipType
            return toolOwnership != ownershipType.rawValue
        }.count
    }

    /// Feature #139: Get names of tools that will be removed (for display in warning)
    private var mismatchedToolNames: [String] {
        toolsInKit.filter { tool in
            let toolOwnership = tool.ownershipType
            return toolOwnership != ownershipType.rawValue
        }.compactMap { $0.name }
    }

    /// Feature #139: Whether ownership has changed from original and will cause tool removal
    private var ownershipWillRemoveTools: Bool {
        ownershipType != originalOwnershipType && mismatchedToolsCount > 0
    }

    /// Tools currently in the kit, excluding those marked for removal, sorted by name
    private var currentKitToolsDisplay: [Tool] {
        toolsInKit
            .filter { !toolsToRemoveFromKit.contains($0.id) }
            .sorted { $0.name < $1.name }
    }

    /// Tools marked for removal from the kit
    private var toolsMarkedForRemoval: [Tool] {
        toolsInKit.filter { toolsToRemoveFromKit.contains($0.id) }
    }

    /// Newly selected existing tools (via picker), not already in the kit
    private var newlySelectedTools: [Tool] {
        let existingKitToolIDs = Set(toolsInKit.map { $0.id })
        return allTools
            .filter { selectedNewToolIDs.contains($0.id) }
            .filter { !existingKitToolIDs.contains($0.id) }
    }

    /// Parsed new tool sizes from multi-line input
    private var parsedNewToolSizes: [String] {
        ToolNameFormatter.parseLineSeparatedSizes(newToolsText)
    }

    /// Preview of new tool names
    private var previewNewToolNames: [String] {
        parsedNewToolSizes.map { ToolNameFormatter.formatToolName($0, measurementType: newToolsMeasurementType) }
    }

    var body: some View {
        NavigationStack {
            Form {
                // MARK: - Kit Name
                Section(header: Text("Kit Name")) {
                    TextField("e.g., Hydraulic Pump R&R Kit", text: $name)
                        .font(.body)
                        .autocorrectionDisabled()
                        .accessibilityIdentifier("editToolKitNameField")
                }

                // MARK: - Description
                Section(header: Text("Description (Optional)")) {
                    TextField("What is this kit used for?", text: $descriptionText, axis: .vertical)
                        .lineLimit(3...6)
                        .font(.body)
                        .accessibilityIdentifier("editToolKitDescriptionField")
                }

                // MARK: - Tool Type
                Section(header: Text("Tool Type (Optional)")) {
                    TextField("e.g., Socket, Wrench, Screwdriver", text: $toolType)
                        .autocorrectionDisabled()
                        .accessibilityIdentifier("editToolKit_toolTypeField")

                    HStack(spacing: 8) {
                        Image(systemName: "tag")
                            .font(.caption)
                            .foregroundColor(kitColor)
                        Text("Singular name for each tool in this kit. Appended to tool names on PDF exports and when tools are removed from the kit.")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    .padding(.vertical, 4)
                    .accessibilityIdentifier("editToolKit_toolTypeDescription")
                }

                // MARK: - Ownership Type
                // Feature #139: Shows warning when changing ownership would remove tools
                Section(header: Text("Ownership")) {
                    Picker("Ownership", selection: $ownershipType) {
                        ForEach(ToolKitOwnershipType.allCases) { type in
                            Text(type.displayName).tag(type)
                        }
                    }
                    .pickerStyle(.segmented)
                    .accessibilityIdentifier("editToolKitOwnershipPicker")

                    // Help text describing ownership
                    HStack(spacing: 8) {
                        Image(systemName: ownershipType == .personal ? "person.fill" : "building.2.fill")
                            .font(.caption)
                            .foregroundColor(industrialBlue)
                        Text(ownershipType.description)
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    .padding(.vertical, 4)
                    .accessibilityIdentifier("editToolKitOwnershipDescription")

                    // Feature #139: Warning when ownership change will affect tools
                    if ownershipWillRemoveTools {
                        VStack(alignment: .leading, spacing: 8) {
                            HStack(spacing: 8) {
                                Image(systemName: "info.circle.fill")
                                    .foregroundColor(industrialBlue)
                                Text("\(mismatchedToolsCount) \(originalOwnershipType.displayName) tool\(mismatchedToolsCount == 1 ? "" : "s") in this kit")
                                    .font(.subheadline)
                                    .fontWeight(.semibold)
                                    .foregroundColor(industrialBlue)
                            }

                            Text("When saving, you can change \(mismatchedToolsCount == 1 ? "this tool" : "all \(mismatchedToolsCount) tools") to \(ownershipType.displayName) or remove \(mismatchedToolsCount == 1 ? "it" : "them") from the kit.")
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
                        .accessibilityIdentifier("editToolKit_ownershipChangeWarning")
                    }
                }

                // MARK: - Tools in Kit
                Section {
                    if currentKitToolsDisplay.isEmpty && toolsMarkedForRemoval.isEmpty && newlySelectedTools.isEmpty {
                        Text("No tools in this kit")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                            .accessibilityIdentifier("editToolKit_noToolsMessage")
                    }

                    // Current tools with remove buttons
                    ForEach(currentKitToolsDisplay, id: \.id) { tool in
                        HStack(spacing: 10) {
                            Image(systemName: "wrench.fill")
                                .font(.caption)
                                .foregroundColor(industrialBlue)
                            Text(tool.name)
                                .font(.body)
                            Spacer()
                            Button(action: { toolsToRemoveFromKit.insert(tool.id) }) {
                                Image(systemName: "xmark.circle.fill")
                                    .foregroundColor(.secondary)
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel("Remove \(tool.name) from kit")
                        }
                    }

                    // Tools marked for removal
                    if !toolsMarkedForRemoval.isEmpty {
                        HStack(spacing: 6) {
                            Image(systemName: "exclamationmark.triangle.fill")
                                .font(.caption)
                                .foregroundColor(safetyOrange)
                            Text("Marked for Removal (\(toolsMarkedForRemoval.count))")
                                .font(.caption)
                                .fontWeight(.medium)
                                .foregroundColor(safetyOrange)
                        }
                        .padding(.top, 4)

                        ForEach(toolsMarkedForRemoval, id: \.id) { tool in
                            HStack(spacing: 10) {
                                Image(systemName: "wrench.fill")
                                    .font(.caption)
                                    .foregroundColor(safetyOrange.opacity(0.5))
                                Text(tool.name)
                                    .font(.body)
                                    .strikethrough()
                                    .foregroundColor(.secondary)
                                Spacer()
                                Button(action: { toolsToRemoveFromKit.remove(tool.id) }) {
                                    Image(systemName: "arrow.uturn.backward.circle")
                                        .foregroundColor(industrialBlue)
                                }
                                .buttonStyle(.plain)
                                .accessibilityLabel("Undo remove \(tool.name)")
                            }
                        }
                    }

                    // Newly selected existing tools (from picker)
                    if !newlySelectedTools.isEmpty {
                        HStack(spacing: 6) {
                            Image(systemName: "plus.circle.fill")
                                .font(.caption)
                                .foregroundColor(Color(red: 0.133, green: 0.545, blue: 0.133))
                            Text("Newly Selected (\(newlySelectedTools.count))")
                                .font(.caption)
                                .fontWeight(.medium)
                                .foregroundColor(Color(red: 0.133, green: 0.545, blue: 0.133))
                        }
                        .padding(.top, 4)

                        ForEach(newlySelectedTools, id: \.id) { tool in
                            HStack(spacing: 10) {
                                Image(systemName: "wrench.fill")
                                    .font(.caption)
                                    .foregroundColor(Color(red: 0.133, green: 0.545, blue: 0.133))
                                Text(tool.name)
                                    .font(.body)
                                Spacer()
                                Button(action: { selectedNewToolIDs.remove(tool.id) }) {
                                    Image(systemName: "xmark.circle.fill")
                                        .foregroundColor(.secondary)
                                }
                                .buttonStyle(.plain)
                                .accessibilityLabel("Remove \(tool.name) from selection")
                            }
                        }
                    }

                    // Add existing tools button
                    Button(action: { showingToolPicker = true }) {
                        HStack {
                            Image(systemName: "plus.circle.fill")
                                .foregroundColor(industrialBlue)
                            Text("Add Existing Tools")
                                .foregroundColor(industrialBlue)
                            Spacer()
                            Image(systemName: "chevron.right")
                                .foregroundColor(.secondary)
                                .font(.caption)
                        }
                    }
                    .accessibilityIdentifier("editToolKit_addExistingToolsButton")
                } header: {
                    Text("Tools in Kit")
                } footer: {
                    Text("Removed tools stay in your Garage. A tool can belong to multiple kits.")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }

                // MARK: - Create New Tools
                Section {
                    Picker("Measurement", selection: $newToolsMeasurementType) {
                        ForEach(MeasurementType.allCases) { type in
                            Text(type.displayName).tag(type)
                        }
                    }
                    .pickerStyle(.segmented)
                    .accessibilityIdentifier("editToolKit_measurementTypePicker")

                    TextField("One size per line, e.g.:\n1/4\n5/16\n3/8", text: $newToolsText, axis: .vertical)
                        .font(.body)
                        .autocorrectionDisabled()
                        .lineLimit(3...10)
                        .accessibilityIdentifier("editToolKit_newToolSizesField")

                    Text("Enter one size per line. Auto-formatted as \(newToolsMeasurementType.displayName).")
                        .font(.caption)
                        .foregroundColor(.secondary)

                    // Example hint
                    HStack(spacing: 8) {
                        Image(systemName: "lightbulb.fill")
                            .font(.caption)
                            .foregroundColor(safetyOrange)
                        Text("Example: \(newToolsMeasurementType == .metric ? "8\n10\n12\n14" : "1/4\n5/16\n3/8\n1/2")")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                } header: {
                    Text("Create New Tools")
                } footer: {
                    Text("New tools will be created in your Garage as \(ownershipType.displayName) tools and added to this kit.")
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
                                    .foregroundColor(industrialBlue)
                                Text(toolName)
                                    .font(.subheadline)
                            }
                            .accessibilityIdentifier("editToolKit_newToolPreview_\(index)")
                        }

                        if previewNewToolNames.count > 20 {
                            Text("+ \(previewNewToolNames.count - 20) more tools")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                    }
                }

                // MARK: - Kit Info
                Section(header: Text("Kit Info")) {
                    HStack {
                        Image(systemName: "calendar")
                            .foregroundColor(industrialBlue)
                            .font(.caption)
                        Text("Created:")
                        Spacer()
                        Text(toolKit.createdAt, style: .date)
                            .foregroundColor(.secondary)
                    }
                }

                // MARK: - Photos
                ToolPhotoEditorSection(images: $photoImages)
            }
            .navigationTitle("Edit Tool Kit")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cancel") {
                        dismiss()
                    }
                    .accessibilityIdentifier("editToolKit_cancelButton")
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Save") {
                        // Feature #139: Show confirmation if ownership change will remove tools
                        if ownershipWillRemoveTools {
                            toolsToRemoveCount = mismatchedToolsCount
                            showingOwnershipWarning = true
                        } else {
                            saveChanges()
                        }
                    }
                    .fontWeight(.semibold)
                    .disabled(name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    .accessibilityIdentifier("editToolKit_saveButton")
                }
            }
            .alert("Error", isPresented: $showingError) {
                Button("OK") { }
            } message: {
                Text(errorMessage)
            }
            // Feature #139: Confirmation alert when ownership change will affect tools
            .alert("Ownership Change", isPresented: $showingOwnershipWarning) {
                Button("Change All Tools", role: .none) {
                    changeAllToolsOwnership = true
                    saveChanges()
                }
                .accessibilityIdentifier("editToolKit_changeAllButton")
                Button("Remove \(toolsToRemoveCount) Tool\(toolsToRemoveCount == 1 ? "" : "s")", role: .destructive) {
                    changeAllToolsOwnership = false
                    saveChanges()
                }
                .accessibilityIdentifier("editToolKit_confirmRemoveButton")
                Button("Cancel", role: .cancel) {
                    ownershipType = originalOwnershipType
                }
            } message: {
                Text("This kit has \(toolsToRemoveCount) \(originalOwnershipType.displayName) tool\(toolsToRemoveCount == 1 ? "" : "s"). You can change \(toolsToRemoveCount == 1 ? "it" : "them all") to \(ownershipType.displayName), or remove \(toolsToRemoveCount == 1 ? "it" : "them") from the kit.")
            }
            .sheet(isPresented: $showingToolPicker) {
                ToolKitToolPickerView(selectedToolIDs: $selectedNewToolIDs, kitOwnershipType: ownershipType.rawValue)
                    .modelContainer(for: [FROTool.self, FROJob.self, FROToolGroup.self, FROToolKit.self, FROConsumable.self, FROChemical.self, FROPart.self], inMemory: true)
            }
            .onChange(of: ownershipType) { _, _ in
                // Clear tool management state when ownership changes
                toolsToRemoveFromKit.removeAll()
                selectedNewToolIDs.removeAll()
                newToolsText = ""
            }
            .onAppear {
                loadCurrentValues()
            }
        }
    }

    // MARK: - Load Current Values

    private func loadCurrentValues() {
        name = toolKit.name
        descriptionText = toolKit.descriptionText ?? ""
        toolType = toolKit.toolType ?? ""

        // Load ownership type - Feature #139: Also track original ownership for detecting changes
        if let ownership = ToolKitOwnershipType(rawValue: toolKit.ownershipType) {
            ownershipType = ownership
            originalOwnershipType = ownership
        } else {
            ownershipType = .personal
            originalOwnershipType = .personal
        }

        // Load existing photos
        if !photosLoaded {
            let kitID = toolKit.id
            photoImages = ToolPhotoService.shared.loadAllPhotos(forEntityID: kitID).map { $0.image }
            photosLoaded = true
        }
    }

    // MARK: - Save Changes

    private func saveChanges() {
        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedName.isEmpty else {
            errorMessage = "Kit name cannot be empty."
            showingError = true
            return
        }

        toolKit.name = trimmedName
        toolKit.descriptionText = descriptionText.isEmpty ? nil : descriptionText
        let trimmedToolType = toolType.trimmingCharacters(in: .whitespacesAndNewlines)
        toolKit.toolType = trimmedToolType.isEmpty ? nil : trimmedToolType

        // Feature #139: If ownership is changing, handle mismatched tools
        let ownershipChanged = ownershipType != originalOwnershipType
        var ownershipChangeCount = 0

        if ownershipChanged {
            let mismatchedTools = toolsInKit.filter { tool in
                let toolOwnership = tool.ownershipType
                return toolOwnership != ownershipType.rawValue
            }
            ownershipChangeCount = mismatchedTools.count

            if changeAllToolsOwnership {
                // User chose "Change All Tools" — update each tool's ownership to match the kit
                for tool in mismatchedTools {
                    tool.ownershipType = ownershipType.rawValue
                }
                if !mismatchedTools.isEmpty {
                    let names = mismatchedTools.compactMap { $0.name }
                    print("EditToolKitView: Changed ownership of \(mismatchedTools.count) tool(s) to '\(ownershipType.rawValue)': [\(names.joined(separator: ", "))]")
                }
            } else {
                // User chose "Remove Tools" — remove mismatched tools from kit (tools stay in Garage)
                let mismatchedIDs = Set(mismatchedTools.map { $0.id })
                toolKit.tools = toolKit.tools?.filter { !mismatchedIDs.contains($0.id) }
                if !mismatchedTools.isEmpty {
                    let names = mismatchedTools.map { $0.name }
                    print("EditToolKitView: Feature #139 - Removed \(mismatchedTools.count) tool(s) from '\(trimmedName)' due to ownership change to '\(ownershipType.rawValue)': [\(names.joined(separator: ", "))]")
                }
            }
            changeAllToolsOwnership = false
        }

        // Save ownership type
        toolKit.ownershipType = ownershipType.rawValue

        // Remove tools manually marked for removal (relationship only, stays in Garage)
        if !toolsToRemoveFromKit.isEmpty {
            toolKit.tools = toolKit.tools?.filter { !toolsToRemoveFromKit.contains($0.id) }
            for toolID in toolsToRemoveFromKit {
                if let tool = fetchByPersistentID(FROTool.self, id: toolID, context: viewContext) {
                    print("EditToolKitView: Removed '\(tool.name)' from kit")
                }
            }
        }

        // Add newly selected existing tools
        for toolID in selectedNewToolIDs {
            if let tool = fetchByPersistentID(FROTool.self, id: toolID, context: viewContext) {
                let existingIDs = Set((toolKit.tools ?? []).map { $0.id })
                if !existingIDs.contains(toolID) {
                    if toolKit.tools == nil { toolKit.tools = [] }
                    toolKit.tools?.append(tool)
                }
            }
        }

        // Create new inline tools and add to kit
        let newToolSizes = parsedNewToolSizes
        for size in newToolSizes {
            let toolName = ToolNameFormatter.formatToolName(size, measurementType: newToolsMeasurementType)
            let tool = FROTool(name: toolName, ownershipType: ownershipType.rawValue)
            viewContext.insert(tool)
            if toolKit.tools == nil { toolKit.tools = [] }
            toolKit.tools?.append(tool)
        }

        if !newToolSizes.isEmpty {
            print("EditToolKitView: Creating \(newToolSizes.count) new inline tools for kit '\(trimmedName)'")
        }

        // Save photos for the kit
        do {
            let fileNames = try ToolPhotoService.shared.saveAllPhotos(photoImages, forEntityID: toolKit.id)
            toolKit.photoFileNames = fileNames.isEmpty ? nil : fileNames
            print("EditToolKitView: Saved \(fileNames.count) photo(s) for kit '\(trimmedName)'")
        } catch {
            print("EditToolKitView: Failed to save photos - \(error)")
        }

        do {
            try viewContext.save()
            var logParts: [String] = ["Updated kit '\(trimmedName)' with ownership '\(ownershipType.rawValue)'"]
            if ownershipChanged && ownershipChangeCount > 0 {
                logParts.append("Ownership change affected \(ownershipChangeCount) tool(s)")
            }
            if !toolsToRemoveFromKit.isEmpty {
                logParts.append("Manually removed \(toolsToRemoveFromKit.count) tool(s)")
            }
            if !selectedNewToolIDs.isEmpty {
                logParts.append("Added \(newlySelectedTools.count) existing tool(s)")
            }
            if !newToolSizes.isEmpty {
                logParts.append("Created \(newToolSizes.count) new tool(s)")
            }
            print("EditToolKitView: \(logParts.joined(separator: ". "))")
            dismiss()
        } catch {
            errorMessage = "Failed to save changes: \(error.localizedDescription)"
            showingError = true
            print("EditToolKitView: Save failed, rolled back - \(error)")
        }
    }
}

// MARK: - ToolKitOwnershipType Enum

/// Ownership type for Tool Kits, similar to ToolGroupOwnershipType.
/// Feature #132 & #139: Used for ownership property and filtering tools.
enum ToolKitOwnershipType: String, CaseIterable, Identifiable {
    case personal = "personal"
    case shop = "shop"
    case imported = "imported"

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .personal: return "Personal"
        case .shop: return "Shop"
        case .imported: return "Imported"
        }
    }

    var description: String {
        switch self {
        case .personal: return "Personal kits contain tools you own personally."
        case .shop: return "Shop kits contain shared shop tools."
        case .imported: return "Imported kits contain tools from another mechanic's job."
        }
    }
}

#Preview {
    let kit = FROToolKit(name: "Hydraulic Pump R&R Kit", ownershipType: "personal")
    EditToolKitView(toolKit: kit)
        .modelContainer(for: [FROTool.self, FROJob.self, FROToolGroup.self, FROToolKit.self, FROConsumable.self, FROChemical.self, FROPart.self], inMemory: true)
}

import SwiftUI
import Foundation
import SwiftData
import PhotosUI

/// View for creating a new tool kit in the Garage.
/// Allows naming the kit, adding a description, selecting ownership type, and selecting tools to include.
///
/// Feature #106: Uses ToolKitNameAutocompleteField to show existing toolkit names
/// as autocomplete suggestions, helping avoid duplicate toolkits.
///
/// Feature #132: Adds ownership property picker (Personal/Shop) to determine which
/// section the kit appears in and which tools can be added.
struct AddToolKitView: View {
    @Environment(\.modelContext) private var viewContext
    @Environment(\.dismiss) private var dismiss

    @State private var name: String = ""
    @State private var descriptionText: String = ""
    @State private var toolType: String = ""
    @State private var ownershipType: String = "personal"  // Feature #132: Default to Personal
    @State private var selectedToolIDs: Set<UUID> = []
    @State private var showingToolPicker = false
    @State private var showingError = false
    @State private var errorMessage = ""

    // Photos
    @State private var photoImages: [UIImage] = []

    // Inline tool creation
    @State private var newToolsText: String = ""
    @State private var newToolsMeasurementType: MeasurementType = .sae

    /// Fetch all tools sorted by name for selection
    @Query(sort: \FROTool.name, order: .forward)
    private var allTools: [FROTool]

    private let industrialBlue = Color(red: 0.145, green: 0.388, blue: 0.922)

    var body: some View {
        NavigationStack {
            Form {
                // MARK: - Kit Name
                // Feature #106: Autocomplete field shows existing toolkit names to avoid duplicates
                Section(header: Text("Kit Name")) {
                    ToolKitNameAutocompleteField(
                        text: $name,
                        placeholder: "e.g., Hydraulic Pump R&R Kit",
                        accessibilityId: "addToolKitNameField"
                    )
                }

                // MARK: - Description
                Section(header: Text("Description (Optional)")) {
                    TextField("What is this kit used for?", text: $descriptionText, axis: .vertical)
                        .lineLimit(3...6)
                        .font(.body)
                }

                // MARK: - Tool Type
                Section(header: Text("Tool Type (Optional)")) {
                    TextField("e.g., Socket, Wrench, Screwdriver", text: $toolType)
                        .autocorrectionDisabled()
                        .accessibilityIdentifier("addToolKit_toolTypeField")

                    HStack(spacing: 8) {
                        Image(systemName: "tag")
                            .font(.caption)
                            .foregroundColor(industrialBlue)
                        Text("Singular name for each tool in this kit. Appended to tool names on PDF exports and when tools are removed from the kit.")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    .padding(.vertical, 4)
                    .accessibilityIdentifier("addToolKit_toolTypeDescription")
                }

                // MARK: - Ownership (Feature #132)
                Section {
                    Picker("Ownership", selection: $ownershipType) {
                        Text("Personal").tag("personal")
                        Text("Shop").tag("shop")
                    }
                    .pickerStyle(.segmented)
                    .accessibilityIdentifier("toolKitOwnershipPicker")
                    // Feature #134: Clear selected tools when ownership changes
                    // because tools must match kit ownership
                    .onChange(of: ownershipType) { _, _ in
                        // Clear tool selections and new tools text when ownership type changes
                        // since tools must match kit ownership type
                        selectedToolIDs.removeAll()
                        newToolsText = ""
                    }
                } header: {
                    Text("Ownership")
                } footer: {
                    Text("Personal kits contain tools you own personally. Shop kits contain shared shop tools.")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }

                // MARK: - Tools Section
                Section {
                    if selectedToolIDs.isEmpty {
                        Button(action: { showingToolPicker = true }) {
                            HStack {
                                Image(systemName: "wrench.fill")
                                    .foregroundColor(industrialBlue)
                                Text("Select Tools")
                                    .foregroundColor(industrialBlue)
                                Spacer()
                                Image(systemName: "chevron.right")
                                    .foregroundColor(.secondary)
                                    .font(.caption)
                            }
                        }
                    } else {
                        ForEach(selectedTools, id: \.id) { tool in
                            HStack {
                                Image(systemName: "wrench.fill")
                                    .foregroundColor(industrialBlue)
                                    .font(.caption)
                                Text(tool.name)
                                    .font(.body)
                                Spacer()
                                Button(action: { selectedToolIDs.remove(tool.id) }) {
                                    Image(systemName: "xmark.circle.fill")
                                        .foregroundColor(.secondary)
                                }
                                .buttonStyle(.plain)
                            }
                        }

                        Button(action: { showingToolPicker = true }) {
                            HStack {
                                Image(systemName: "plus.circle.fill")
                                    .foregroundColor(industrialBlue)
                                Text("Add More Tools")
                                    .foregroundColor(industrialBlue)
                            }
                        }
                    }
                } header: {
                    Text("Existing Tools")
                } footer: {
                    Text("Select existing tools from your Garage. A tool can belong to multiple kits.")
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
                    .accessibilityIdentifier("addToolKit_measurementTypePicker")

                    TextField("One size per line, e.g.:\n1/4\n5/16\n3/8", text: $newToolsText, axis: .vertical)
                        .font(.body)
                        .autocorrectionDisabled()
                        .lineLimit(3...10)
                        .accessibilityIdentifier("addToolKit_newToolSizesField")

                    Text("Enter one size per line. Auto-formatted as \(newToolsMeasurementType.displayName).")
                        .font(.caption)
                        .foregroundColor(.secondary)

                    // Example hint
                    HStack(spacing: 8) {
                        Image(systemName: "lightbulb.fill")
                            .font(.caption)
                            .foregroundColor(Color(red: 0.976, green: 0.451, blue: 0.086))
                        Text("Example: \(newToolsMeasurementType == .metric ? "8\n10\n12\n14" : "1/4\n5/16\n3/8\n1/2")")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                } header: {
                    Text("Create New Tools")
                } footer: {
                    Text("New tools will be created in your Garage as \(ownershipDisplayName) tools and added to this kit.")
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
                            .accessibilityIdentifier("addToolKit_newToolPreview_\(index)")
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
            .navigationTitle("Create Tool Kit")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cancel") {
                        dismiss()
                    }
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Save") {
                        saveToolKit()
                    }
                    .fontWeight(.semibold)
                    .disabled(name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
            .sheet(isPresented: $showingToolPicker) {
                // Feature #134: Pass kit ownership type to filter tools matching ownership
                ToolKitToolPickerView(selectedToolIDs: $selectedToolIDs, kitOwnershipType: ownershipType)
                    
            }
            .alert("Error", isPresented: $showingError) {
                Button("OK") { }
            } message: {
                Text(errorMessage)
            }
        }
    }

    // MARK: - Computed Properties

    /// Tools that are currently selected, sorted by size then name
    private var selectedTools: [Tool] {
        allTools.filter { selectedToolIDs.contains($0.id) }.sortedBySize()
    }

    /// Parsed new tool sizes from multi-line input
    private var parsedNewToolSizes: [String] {
        ToolNameFormatter.parseLineSeparatedSizes(newToolsText)
    }

    /// Preview of new formatted tool names
    private var previewNewToolNames: [String] {
        parsedNewToolSizes.map { ToolNameFormatter.formatToolName($0, measurementType: newToolsMeasurementType) }
    }

    /// Display name for kit ownership
    private var ownershipDisplayName: String {
        ownershipType == "personal" ? "Personal" : "Shop"
    }

    // MARK: - Save

    private func saveToolKit() {
        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedName.isEmpty else {
            errorMessage = "Kit name cannot be empty."
            showingError = true
            return
        }

        let trimmedToolType = toolType.trimmingCharacters(in: .whitespacesAndNewlines)
        let toolKit = FROToolKit(
            name: trimmedName,
            descriptionText: descriptionText.isEmpty ? nil : descriptionText,
            ownershipType: ownershipType,
            toolType: trimmedToolType.isEmpty ? nil : trimmedToolType
        )
        viewContext.insert(toolKit)

        // Link selected existing tools (many-to-many relationship)
        var linkedTools: [FROTool] = []
        for toolID in selectedToolIDs {
            if let tool = fetchByPersistentID(FROTool.self, id: toolID, context: viewContext) {
                linkedTools.append(tool)
            }
        }

        // Create new inline tools and add to kit
        let newToolSizes = parsedNewToolSizes
        for size in newToolSizes {
            let toolName = ToolNameFormatter.formatToolName(size, measurementType: newToolsMeasurementType)
            let tool = FROTool(name: toolName, ownershipType: ownershipType)
            viewContext.insert(tool)
            linkedTools.append(tool)
        }
        toolKit.tools = linkedTools

        if !newToolSizes.isEmpty {
            print("AddToolKitView: Creating \(newToolSizes.count) new inline tools for kit '\(trimmedName)'")
        }

        // Save photos for the kit
        if !photoImages.isEmpty {
            do {
                let fileNames = try ToolPhotoService.shared.saveAllPhotos(photoImages, forEntityID: toolKit.id)
                toolKit.photoFileNames = fileNames.isEmpty ? nil : fileNames
                print("AddToolKitView: Saved \(fileNames.count) photo(s) for kit '\(trimmedName)'")
            } catch {
                print("AddToolKitView: Failed to save photos - \(error)")
            }
        }

        do {
            try viewContext.save()
            print("AddToolKitView: Saved tool kit '\(trimmedName)' (\(ownershipType)) with \(selectedToolIDs.count) existing + \(newToolSizes.count) new tools")
            dismiss()
        } catch {
            errorMessage = "Failed to save tool kit: \(error.localizedDescription)"
            showingError = true
            print("AddToolKitView: Save failed, rolled back - \(error)")
        }
    }
}

// MARK: - Tool Picker for Tool Kits

/// Multi-select tool picker for adding tools to a kit.
/// Feature #122: Only shows Personal and Shop tools — Borrowed tools cannot be added to Tool Kits.
/// Feature #134: Only shows tools matching the kit's ownership type.
///   - Personal Tool Kit: Only Personal tools
///   - Shop Tool Kit: Only Shop tools
/// This prevents confusion about ownership within organized tool kits.
struct ToolKitToolPickerView: View {
    @Environment(\.modelContext) private var viewContext
    @Environment(\.dismiss) private var dismiss

    @Binding var selectedToolIDs: Set<UUID>

    /// Feature #134: The ownership type of the kit being edited
    let kitOwnershipType: String

    /// Fetch all tools - we'll filter based on kit ownership in the computed property
    @Query(sort: \FROTool.name, order: .forward)
    private var tools: [FROTool]

    /// Feature #122 + #134: Only tools matching the kit's ownership type, sorted by size then name.
    /// Borrowed tools are always excluded. Personal kits only show Personal tools.
    /// Shop kits only show Shop tools.
    private var sortedTools: [Tool] {
        Array(tools).filter { $0.ownershipType == kitOwnershipType }.sortedBySize()
    }

    private let industrialBlue = Color(red: 0.145, green: 0.388, blue: 0.922)
    private let steelGray = Color(red: 0.392, green: 0.455, blue: 0.545)

    /// Feature #122: Count of borrowed tools excluded from selection
    private var borrowedToolCount: Int {
        tools.filter { $0.ownershipType == "borrowed" }.count
    }

    /// Feature #134: Count of tools with different ownership (excluded from selection)
    private var otherOwnershipToolCount: Int {
        let otherType = kitOwnershipType == "personal" ? "shop" : "personal"
        return tools.filter { $0.ownershipType == otherType }.count
    }

    /// Feature #134: Human-readable kit ownership label
    private var kitOwnershipLabel: String {
        kitOwnershipType == "personal" ? "Personal" : "Shop"
    }

    /// Feature #134: Human-readable other ownership label
    private var otherOwnershipLabel: String {
        kitOwnershipType == "personal" ? "Shop" : "Personal"
    }

    var body: some View {
        NavigationStack {
            List {
                // Feature #122 + #134: If there are no selectable tools matching kit ownership
                if sortedTools.isEmpty {
                    Section {
                        if tools.isEmpty {
                            // No tools at all in Garage
                            Text("No tools in Garage yet.\nAdd \(kitOwnershipLabel) tools first, then create a kit.")
                                .font(.subheadline)
                                .foregroundColor(.secondary)
                                .multilineTextAlignment(.center)
                                .padding()
                                .accessibilityIdentifier("noToolsInGarageMessage")
                        } else {
                            // Feature #134: No tools matching kit ownership - show helpful message
                            VStack(spacing: 12) {
                                Image(systemName: "info.circle.fill")
                                    .font(.title)
                                    .foregroundColor(Color(red: 0.976, green: 0.451, blue: 0.086))
                                Text("No \(kitOwnershipLabel) tools available")
                                    .font(.headline)
                                    .accessibilityIdentifier("noMatchingOwnershipTitle")

                                // Feature #134: Explain why tools are excluded
                                VStack(spacing: 4) {
                                    if otherOwnershipToolCount > 0 {
                                        Text("\(otherOwnershipLabel) tools (\(otherOwnershipToolCount)) cannot be added to a \(kitOwnershipLabel) kit.")
                                            .font(.subheadline)
                                            .foregroundColor(.secondary)
                                            .multilineTextAlignment(.center)
                                            .accessibilityIdentifier("otherOwnershipExcludedMessage")
                                    }
                                    if borrowedToolCount > 0 {
                                        Text("Borrowed tools (\(borrowedToolCount)) cannot be added to any kit.")
                                            .font(.subheadline)
                                            .foregroundColor(.secondary)
                                            .multilineTextAlignment(.center)
                                            .accessibilityIdentifier("borrowedToolsExcludedMessage")
                                    }
                                }

                                Text("Add \(kitOwnershipLabel) tools to your Garage to include them in this kit.")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                                    .accessibilityIdentifier("addMatchingToolsHint")
                            }
                            .padding()
                            .accessibilityIdentifier("noMatchingToolsMessage")
                        }
                    }
                } else {
                    // Feature #134: Section header shows which ownership type is displayed
                    Section {
                        ForEach(sortedTools, id: \.id) { tool in
                            Button(action: { toggleTool(tool) }) {
                                HStack {
                                    Image(systemName: selectedToolIDs.contains(tool.id) ? "checkmark.circle.fill" : "circle")
                                        .foregroundColor(selectedToolIDs.contains(tool.id) ? industrialBlue : .secondary)
                                        .font(.title3)

                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(tool.name)
                                            .font(.body)
                                            .foregroundColor(.primary)

                                        if let notes = tool.notes, !notes.isEmpty {
                                            Text(notes)
                                                .font(.caption)
                                                .foregroundColor(.secondary)
                                                .lineLimit(1)
                                        }
                                    }

                                    Spacer()

                                    // Ownership badge
                                    Text(ownershipLabel(for: tool))
                                        .font(.caption2)
                                        .padding(.horizontal, 6)
                                        .padding(.vertical, 2)
                                        .background(ownershipColor(for: tool).opacity(0.15))
                                        .foregroundColor(ownershipColor(for: tool))
                                        .clipShape(Capsule())
                                }
                            }
                            .buttonStyle(.plain)
                            .accessibilityIdentifier("toolKitToolPickerRow_\(tool.id.uuidString)")
                        }
                    } header: {
                        // Feature #134: Show which ownership type tools are listed
                        Text("\(kitOwnershipLabel) Tools")
                            .accessibilityIdentifier("toolKitToolPickerSectionHeader")
                    } footer: {
                        // Feature #134: Explain what's excluded from selection
                        VStack(alignment: .leading, spacing: 2) {
                            if otherOwnershipToolCount > 0 {
                                Text("\(otherOwnershipLabel) tools (\(otherOwnershipToolCount)) not shown — \(kitOwnershipLabel) kits only contain \(kitOwnershipLabel) tools.")
                                    .accessibilityIdentifier("otherOwnershipExcludedFooter")
                            }
                            if borrowedToolCount > 0 {
                                Text("Borrowed tools (\(borrowedToolCount)) not shown — they cannot be added to kits.")
                                    .accessibilityIdentifier("borrowedToolsExcludedFooter")
                            }
                        }
                    }
                }
            }
            .listStyle(.insetGrouped)
            .navigationTitle("Select Tools")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Done") {
                        dismiss()
                    }
                    .fontWeight(.semibold)
                }
            }
        }
    }

    private func toggleTool(_ tool: Tool) {
        if selectedToolIDs.contains(tool.id) {
            selectedToolIDs.remove(tool.id)
        } else {
            selectedToolIDs.insert(tool.id)
        }
    }

    private func ownershipLabel(for tool: Tool) -> String {
        switch tool.ownershipType {
        case "personal": return "Personal"
        case "shop": return "Shop"
        case "borrowed": return "Borrowed"
        case "imported": return "Imported"
        default: return "Personal"
        }
    }

    private func ownershipColor(for tool: Tool) -> Color {
        switch tool.ownershipType {
        case "personal": return Color(red: 0.145, green: 0.388, blue: 0.922)
        case "shop": return Color(red: 0.392, green: 0.455, blue: 0.545)
        case "borrowed": return Color(red: 0.976, green: 0.451, blue: 0.086)
        case "imported": return Color(red: 0.608, green: 0.318, blue: 0.878)
        default: return .blue
        }
    }
}

#Preview {
    AddToolKitView()
        
}

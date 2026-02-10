import SwiftUI
import Foundation
import SwiftData
import PhotosUI

/// Measurement type for tool groups — determines how tool sizes are displayed and formatted.
/// SAE uses inch-standard (e.g., 3/8", 1/2") while Metric uses millimeters (e.g., 10mm, 12mm).
enum MeasurementType: String, CaseIterable, Identifiable {
    case sae = "sae"
    case metric = "metric"

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .sae: return "SAE (Inch)"
        case .metric: return "Metric (mm)"
        }
    }

    /// The unit suffix for this measurement type
    var unitSuffix: String {
        switch self {
        case .sae: return "\""
        case .metric: return "mm"
        }
    }

    /// Example sizes for this measurement type
    var examples: String {
        switch self {
        case .sae: return "e.g., 3/8\", 1/2\", 9/16\""
        case .metric: return "e.g., 10mm, 12mm, 14mm"
        }
    }
}

/// Ownership type for tool groups (Tool Sets) — determines which section they appear in.
/// Feature #131: Tool Sets have ownership property (Personal/Shop).
enum ToolGroupOwnershipType: String, CaseIterable, Identifiable {
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
        case .personal: return "Your personal tools"
        case .shop: return "Tools from the shop"
        case .imported: return "Tools imported from another mechanic's job"
        }
    }
}

/// View for creating a new tool set in the Garage.
/// Supports creating top-level sets or sub-sets under an existing parent.
/// Feature #105: Includes autocomplete suggestions to warn about existing similar sets.
/// Feature #107: Includes measurement type selection (SAE or Metric).
/// Feature #130: Renamed from "Tool Group" to "Tool Set" throughout UI.
/// Feature #131: Includes ownership type selection (Personal/Shop).
struct AddToolGroupView: View {
    @Environment(\.modelContext) private var viewContext
    @Environment(\.dismiss) private var dismiss

    @State private var name: String = ""
    @State private var measurementType: MeasurementType = .sae
    @State private var ownershipType: ToolGroupOwnershipType = .personal
    @State private var toolType: String = ""
    @State private var showingError = false
    @State private var errorMessage = ""
    @State private var toolsText: String = ""
    @State private var photoImages: [UIImage] = []

    /// Optional parent group — if set, the new group will be a sub-group
    var parentGroup: ToolGroup?

    /// Fetch all tool groups to provide autocomplete suggestions
    @Query(sort: [SortDescriptor(\FROToolGroup.sortOrder, order: .forward), SortDescriptor(\FROToolGroup.name, order: .forward)])
    private var allToolGroups: [FROToolGroup]

    /// All unique group names (excluding the current parent if editing a sub-group)
    private var allGroupNames: [String] {
        let names = allToolGroups.compactMap { $0.name }.filter { !$0.isEmpty }
        let uniqueNames = Set(names)
        return uniqueNames.sorted { $0.localizedCaseInsensitiveCompare($1) == .orderedAscending }
    }

    /// Computed property returning matching group names based on user input.
    /// Uses case-insensitive contains matching for better UX.
    private var matchingGroups: [String] {
        let trimmedInput = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmedInput.count >= 2 else { return [] }

        let lowercasedInput = trimmedInput.lowercased()
        return allGroupNames.filter { groupName in
            groupName.lowercased().contains(lowercasedInput)
        }
    }

    /// Whether to show the suggestions/warning dropdown
    private var showSuggestions: Bool {
        let trimmedInput = name.trimmingCharacters(in: .whitespacesAndNewlines)
        // Show suggestions when:
        // 1. Input has at least 2 characters
        // 2. There are matching suggestions
        guard trimmedInput.count >= 2 else { return false }
        guard !matchingGroups.isEmpty else { return false }
        return true
    }

    /// Parsed tool sizes from multi-line input (one per line)
    private var parsedToolSizes: [String] {
        ToolNameFormatter.parseLineSeparatedSizes(toolsText)
    }

    /// Preview of formatted tool names that will be created
    private var previewToolNames: [String] {
        parsedToolSizes.map { ToolNameFormatter.formatToolName($0, measurementType: measurementType) }
    }

    var body: some View {
        NavigationStack {
            Form {
                // MARK: - Set Name
                Section(header: Text("Set Name")) {
                    TextField("e.g., 1/4-inch Drive", text: $name)
                        .font(.body)
                        .autocorrectionDisabled()
                        .accessibilityIdentifier("toolGroupNameField")

                    // MARK: - Autocomplete Suggestions (Warning about similar groups)
                    if showSuggestions {
                        VStack(alignment: .leading, spacing: 0) {
                            // Warning header
                            HStack(spacing: 6) {
                                Image(systemName: "exclamationmark.triangle.fill")
                                    .font(.caption)
                                    .foregroundColor(Color(red: 0.976, green: 0.451, blue: 0.086)) // Safety orange
                                Text("Similar sets exist:")
                                    .font(.caption)
                                    .fontWeight(.medium)
                                    .foregroundColor(Color(red: 0.976, green: 0.451, blue: 0.086))
                            }
                            .padding(.horizontal, 12)
                            .padding(.top, 8)
                            .padding(.bottom, 4)
                            .accessibilityIdentifier("toolGroupSuggestionsHeader")

                            // Suggestion rows (limit to 5)
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
                                .accessibilityIdentifier("toolGroupSuggestion_\(suggestion)")
                                .accessibilityLabel("Existing set: \(suggestion)")

                                // Divider between suggestions
                                if suggestion != matchingGroups.prefix(5).last {
                                    Divider()
                                        .padding(.leading, 12)
                                }
                            }

                            // Show count if there are more matches
                            if matchingGroups.count > 5 {
                                Text("+ \(matchingGroups.count - 5) more matching sets")
                                    .font(.caption2)
                                    .foregroundColor(.secondary)
                                    .padding(.horizontal, 12)
                                    .padding(.vertical, 6)
                                    .accessibilityIdentifier("toolGroupMoreMatchesLabel")
                            }

                            // Informational tip
                            Text("You can still create a new set with this name.")
                                .font(.caption2)
                                .foregroundColor(.secondary)
                                .padding(.horizontal, 12)
                                .padding(.vertical, 6)
                                .accessibilityIdentifier("toolGroupSuggestionsTip")
                        }
                        .background(Color(UIColor.secondarySystemBackground))
                        .cornerRadius(8)
                        .accessibilityIdentifier("toolGroupSuggestionsContainer")
                    }
                }

                // MARK: - Ownership Type
                // Feature #131: Tool Sets have ownership property (Personal/Shop)
                Section(header: Text("Ownership")) {
                    Picker("Ownership", selection: $ownershipType) {
                        ForEach(ToolGroupOwnershipType.allCases) { type in
                            Text(type.displayName).tag(type)
                        }
                    }
                    .pickerStyle(.segmented)
                    .accessibilityIdentifier("toolGroupOwnershipPicker")

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
                    .accessibilityIdentifier("toolGroupOwnershipDescription")
                }

                // MARK: - Tool Type
                Section(header: Text("Tool Type (Optional)")) {
                    TextField("e.g., Socket, Wrench, Screwdriver", text: $toolType)
                        .autocorrectionDisabled()
                        .accessibilityIdentifier("toolGroupToolTypeField")

                    HStack(spacing: 8) {
                        Image(systemName: "tag")
                            .font(.caption)
                            .foregroundColor(Color(red: 0.145, green: 0.388, blue: 0.922))
                        Text("Singular name for each tool in this set. Appended to tool names on PDF exports and when tools are removed from the set.")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    .padding(.vertical, 4)
                    .accessibilityIdentifier("toolGroupToolTypeDescription")
                }

                // MARK: - Measurement Type
                Section(header: Text("Measurement Type")) {
                    Picker("Measurement", selection: $measurementType) {
                        ForEach(MeasurementType.allCases) { type in
                            Text(type.displayName).tag(type)
                        }
                    }
                    .pickerStyle(.segmented)
                    .accessibilityIdentifier("measurementTypePicker")

                    // Help text showing examples
                    HStack(spacing: 8) {
                        Image(systemName: "ruler")
                            .font(.caption)
                            .foregroundColor(Color(red: 0.145, green: 0.388, blue: 0.922))
                        Text(measurementType.examples)
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    .padding(.vertical, 4)
                    .accessibilityIdentifier("measurementTypeExamples")
                }

                // MARK: - Parent Info
                if let parent = parentGroup {
                    Section(header: Text("Parent Set")) {
                        HStack {
                            Image(systemName: "folder.fill")
                                .foregroundColor(Color(red: 0.145, green: 0.388, blue: 0.922))
                            Text(parent.name)
                                .foregroundColor(.secondary)

                            Spacer()

                            // Show parent's measurement type if set
                            if let parentMeasurement = parent.measurementType {
                                Text(MeasurementType(rawValue: parentMeasurement)?.displayName ?? "SAE")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                        }
                    }
                }

                // MARK: - Inline Tool Creation
                Section {
                    TextField("One size per line, e.g.:\n1/4\n5/16\n3/8", text: $toolsText, axis: .vertical)
                        .font(.body)
                        .autocorrectionDisabled()
                        .lineLimit(3...10)
                        .accessibilityIdentifier("inlineToolSizesField")

                    Text("Enter one tool size per line. Sizes auto-format based on measurement type.")
                        .font(.caption)
                        .foregroundColor(.secondary)

                    // Example hint based on measurement type
                    HStack(spacing: 8) {
                        Image(systemName: "lightbulb.fill")
                            .font(.caption)
                            .foregroundColor(Color(red: 0.976, green: 0.451, blue: 0.086))
                        Text("Example: \(measurementType == .metric ? "8\n10\n12\n14" : "1/4\n5/16\n3/8\n1/2")")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    .accessibilityIdentifier("inlineToolExampleHint")
                } header: {
                    Text("Tools (Optional)")
                } footer: {
                    Text("Tools will be created as \(ownershipType.displayName) tools, matching the set's ownership.")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }

                // MARK: - Tool Preview
                if !parsedToolSizes.isEmpty {
                    Section(header: Text("Preview (\(parsedToolSizes.count) tools)")) {
                        ForEach(Array(previewToolNames.prefix(20).enumerated()), id: \.offset) { index, toolName in
                            HStack(spacing: 10) {
                                Image(systemName: "wrench.fill")
                                    .font(.caption)
                                    .foregroundColor(Color(red: 0.145, green: 0.388, blue: 0.922))
                                Text(toolName)
                                    .font(.subheadline)
                            }
                            .accessibilityIdentifier("inlineToolPreview_\(index)")
                        }

                        if previewToolNames.count > 20 {
                            Text("+ \(previewToolNames.count - 20) more tools")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                    }
                }

                // MARK: - Photos
                ToolPhotoEditorSection(images: $photoImages)
            }
            .navigationTitle(parentGroup != nil ? "Add Sub-Set" : "Add Tool Set")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cancel") {
                        dismiss()
                    }
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Save") {
                        saveGroup()
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
        }
    }

    // MARK: - Save

    private func saveGroup() {
        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedName.isEmpty else {
            errorMessage = "Set name cannot be empty."
            showingError = true
            return
        }

        let group = FROToolGroup(
            name: trimmedName,
            sortOrder: 0,
            ownershipType: ownershipType.rawValue
        )
        group.measurementType = measurementType.rawValue
        let trimmedToolType = toolType.trimmingCharacters(in: .whitespacesAndNewlines)
        group.toolType = trimmedToolType.isEmpty ? nil : trimmedToolType
        group.parentGroup = parentGroup
        viewContext.insert(group)

        // Set sort order to be after existing siblings
        let siblingCount: Int
        if let parent = parentGroup {
            siblingCount = parent.childGroups?.count ?? 0
        } else {
            // Count existing top-level groups
            let descriptor = FetchDescriptor<FROToolGroup>(predicate: #Predicate { $0.parentGroup == nil })
            siblingCount = (try? viewContext.fetchCount(descriptor)) ?? 0
        }
        group.sortOrder = siblingCount

        // Create inline tools if any sizes were entered
        let toolSizes = parsedToolSizes
        for size in toolSizes {
            let toolName = ToolNameFormatter.formatToolName(size, measurementType: measurementType)
            let tool = FROTool(name: toolName, ownershipType: ownershipType.rawValue)
            tool.group = group
            viewContext.insert(tool)
        }

        if !toolSizes.isEmpty {
            print("AddToolGroupView: Creating \(toolSizes.count) inline tools in set '\(trimmedName)'")
        }

        // Save photos for the group
        if !photoImages.isEmpty {
            let groupID = group.id
            do {
                let fileNames = try ToolPhotoService.shared.saveAllPhotos(photoImages, forEntityID: groupID)
                group.photoFileNames = fileNames.isEmpty ? nil : fileNames
                print("AddToolGroupView: Saved \(fileNames.count) photo(s) for set '\(trimmedName)'")
            } catch {
                print("AddToolGroupView: Failed to save photos - \(error)")
            }
        }

        do {
            try viewContext.save()
            print("AddToolGroupView: Saved group '\(trimmedName)' with ownership '\(ownershipType.rawValue)' and measurement type '\(measurementType.rawValue)' with \(toolSizes.count) tools to Core Data")
            dismiss()
        } catch {
            errorMessage = "Failed to save set: \(error.localizedDescription)"
            showingError = true
            print("AddToolGroupView: Save failed, rolled back - \(error)")
        }
    }
}

#Preview {
    AddToolGroupView()
        
}

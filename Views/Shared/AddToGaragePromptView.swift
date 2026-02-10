import SwiftUI
import Foundation
import SwiftData

/// Data structure representing an on-the-fly item that can be added to Garage.
/// Used to track selection state in the prompt dialog.
struct OnTheFlyItem: Identifiable {
    let id: UUID
    let name: String
    let type: ItemType
    let category: String?
    var isSelected: Bool
    /// For tools: optional set assignment (Feature #97, Feature #130 renamed)
    var selectedGroupID: UUID?
    /// For tools: optional toolkit assignment (Feature #97)
    var selectedToolKitID: UUID?
    /// For consumables: selected category to apply when adding to Garage (Feature #98)
    var selectedConsumableCategory: String?
    /// For chemicals: selected category to apply when adding to Garage (Feature #98)
    var selectedChemicalCategory: String?

    enum ItemType: String {
        case tool = "Tool"
        case consumable = "Consumable"
        case chemical = "Chemical"

        var icon: String {
            switch self {
            case .tool: return "wrench.fill"
            case .consumable: return "bolt.fill"
            case .chemical: return "drop.fill"
            }
        }

        var color: Color {
            switch self {
            case .tool: return Color(red: 0.145, green: 0.388, blue: 0.922)
            case .consumable: return Color(red: 0.976, green: 0.451, blue: 0.086)
            case .chemical: return Color(red: 0.133, green: 0.773, blue: 0.369)
            }
        }
    }
}

/// A prompt view that appears after saving a job when on-the-fly items were created.
/// Allows the user to choose which new items to add to their Garage inventory.
/// Feature #96: Prompt to add new on-the-fly items to Garage after saving job.
/// Feature #97: Allows assigning tools to tool sets and toolkits when adding to Garage.
/// Feature #130: Renamed from "Tool Group" to "Tool Set" throughout UI.
struct AddToGaragePromptView: View {
    @Environment(\.modelContext) private var viewContext
    @Environment(\.dismiss) private var dismiss

    /// Fetch all tool sets for assignment (Feature #97, Feature #130 renamed)
    @Query(sort: [SortDescriptor(\FROToolGroup.sortOrder, order: .forward), SortDescriptor(\FROToolGroup.name, order: .forward)])
    private var allGroups: [FROToolGroup]

    /// Fetch all toolkits for assignment (Feature #97)
    @Query(sort: \FROToolKit.name, order: .forward)
    private var allToolKits: [FROToolKit]

    /// The on-the-fly items to potentially add to Garage
    @State private var items: [OnTheFlyItem]

    /// Whether any items were successfully added
    @State private var hasAddedItems = false

    /// Callback when the prompt is dismissed
    let onDismiss: () -> Void

    /// Initialize with items grouped by type
    init(
        tools: [Tool] = [],
        consumables: [Consumable] = [],
        chemicals: [Chemical] = [],
        onDismiss: @escaping () -> Void
    ) {
        var allItems: [OnTheFlyItem] = []

        // Add tools
        for tool in tools {
            allItems.append(OnTheFlyItem(
                id: tool.id,
                name: tool.name,
                type: .tool,
                category: ownershipLabel(for: tool.ownershipType),
                isSelected: true,  // Default to selected
                selectedGroupID: nil,  // Feature #97: No set by default
                selectedToolKitID: nil,  // Feature #97: No toolkit by default
                selectedConsumableCategory: nil,
                selectedChemicalCategory: nil
            ))
        }

        // Add consumables
        for consumable in consumables {
            allItems.append(OnTheFlyItem(
                id: consumable.id,
                name: consumable.name,
                type: .consumable,
                category: consumableCategoryLabel(for: consumable.category),
                isSelected: true,  // Default to selected
                selectedGroupID: nil,
                selectedToolKitID: nil,
                selectedConsumableCategory: consumable.category,  // Feature #98: Initialize with current category
                selectedChemicalCategory: nil
            ))
        }

        // Add chemicals
        for chemical in chemicals {
            allItems.append(OnTheFlyItem(
                id: chemical.id,
                name: chemical.name,
                type: .chemical,
                category: chemicalCategoryLabel(for: chemical.category),
                isSelected: true,  // Default to selected
                selectedGroupID: nil,
                selectedToolKitID: nil,
                selectedConsumableCategory: nil,
                selectedChemicalCategory: chemical.category  // Feature #98: Initialize with current category
            ))
        }

        _items = State(initialValue: allItems)
        self.onDismiss = onDismiss
    }

    /// Count of selected items
    private var selectedCount: Int {
        items.filter { $0.isSelected }.count
    }

    /// Whether any items are selected
    private var hasSelections: Bool {
        selectedCount > 0
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                // Header explanation
                VStack(spacing: 8) {
                    Image(systemName: "tray.and.arrow.down.fill")
                        .font(.system(size: 36))
                        .foregroundColor(Color(red: 0.145, green: 0.388, blue: 0.922))

                    Text("Add to Your Garage?")
                        .font(.title2)
                        .fontWeight(.bold)

                    Text("You created \(items.count) new item\(items.count == 1 ? "" : "s") for this job. Would you like to add them to your Garage for future use?")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal)
                }
                .padding(.top, 20)
                .padding(.bottom, 16)

                Divider()

                // Items list with checkboxes
                List {
                    ForEach($items) { $item in
                        ItemRow(
                            item: $item,
                            allGroups: Array(allGroups),
                            allToolKits: Array(allToolKits)
                        )
                    }
                }
                .listStyle(.insetGrouped)

                // Action buttons
                VStack(spacing: 12) {
                    // Add Selected button
                    Button(action: addSelectedToGarage) {
                        HStack {
                            Image(systemName: "plus.circle.fill")
                            Text(hasSelections ? "Add \(selectedCount) to Garage" : "Add to Garage")
                        }
                        .font(.headline)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                        .background(hasSelections ? Color(red: 0.145, green: 0.388, blue: 0.922) : Color.gray)
                        .foregroundColor(.white)
                        .cornerRadius(12)
                    }
                    .disabled(!hasSelections)
                    .accessibilityIdentifier("addSelectedToGarageButton")
                    .accessibilityLabel("Add \(selectedCount) selected items to Garage")

                    // Skip button
                    Button(action: skipAndDismiss) {
                        Text("Skip — Don't Add to Garage")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 10)
                    }
                    .accessibilityIdentifier("skipAddToGarageButton")
                    .accessibilityLabel("Skip, don't add items to Garage")
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 16)
                .background(Color(UIColor.systemBackground))
            }
            .navigationBarHidden(true)
        }
    }

    /// A row displaying an item with a checkbox toggle
    /// For tools, also shows group and toolkit pickers (Feature #97)
    private struct ItemRow: View {
        @Binding var item: OnTheFlyItem
        let allGroups: [ToolGroup]
        let allToolKits: [ToolKit]

        private let industrialBlue = Color(red: 0.145, green: 0.388, blue: 0.922)
        private let steelGray = Color(red: 0.392, green: 0.455, blue: 0.545)

        var body: some View {
            VStack(alignment: .leading, spacing: 8) {
                // Main row with checkbox
                Button(action: {
                    item.isSelected.toggle()
                }) {
                    HStack(spacing: 12) {
                        // Checkbox
                        Image(systemName: item.isSelected ? "checkmark.circle.fill" : "circle")
                            .font(.title2)
                            .foregroundColor(item.isSelected ? industrialBlue : .secondary)

                        // Type icon
                        Image(systemName: item.type.icon)
                            .font(.body)
                            .foregroundColor(item.type.color)
                            .frame(width: 24)

                        // Item details
                        VStack(alignment: .leading, spacing: 2) {
                            Text(item.name)
                                .font(.body)
                                .fontWeight(.medium)
                                .foregroundColor(.primary)

                            HStack(spacing: 8) {
                                // Type badge
                                Text(item.type.rawValue)
                                    .font(.caption2)
                                    .fontWeight(.medium)
                                    .padding(.horizontal, 6)
                                    .padding(.vertical, 2)
                                    .background(item.type.color.opacity(0.15))
                                    .foregroundColor(item.type.color)
                                    .clipShape(Capsule())

                                // Category if available
                                if let category = item.category {
                                    Text(category)
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                }
                            }
                        }

                        Spacer()
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("garageItemRow_\(item.name)")
                .accessibilityLabel("\(item.name), \(item.type.rawValue), \(item.isSelected ? "selected" : "not selected")")
                .accessibilityHint("Tap to toggle selection")

                // Feature #97: Show set and toolkit pickers for selected tools
                // Feature #122: Borrowed tools cannot be in sets or kits, so hide pickers for them
                if item.type == .tool && item.isSelected {
                    // Check if this is a borrowed tool by looking at the category label
                    let isBorrowedTool = item.category == "Borrowed"

                    VStack(alignment: .leading, spacing: 6) {
                        // Tool Set Picker - hidden for borrowed tools (Feature #122, Feature #130 renamed)
                        if !allGroups.isEmpty && !isBorrowedTool {
                            HStack(spacing: 8) {
                                Image(systemName: "folder.fill")
                                    .font(.caption)
                                    .foregroundColor(steelGray)
                                    .frame(width: 20)

                                Text("Set:")
                                    .font(.caption)
                                    .foregroundColor(.secondary)

                                Picker("Tool Set", selection: $item.selectedGroupID) {
                                    Text("No Set").tag(nil as UUID?)
                                    ForEach(allGroups, id: \.id) { group in
                                        Text(groupDisplayName(for: group))
                                            .tag(group.id as UUID?)
                                    }
                                }
                                .pickerStyle(.menu)
                                .tint(industrialBlue)
                                .accessibilityIdentifier("toolGroupPicker_\(item.name)")
                            }
                        }

                        // ToolKit Picker - hidden for borrowed tools (Feature #122)
                        if !allToolKits.isEmpty && !isBorrowedTool {
                            HStack(spacing: 8) {
                                Image(systemName: "shippingbox.fill")
                                    .font(.caption)
                                    .foregroundColor(steelGray)
                                    .frame(width: 20)

                                Text("Toolkit:")
                                    .font(.caption)
                                    .foregroundColor(.secondary)

                                Picker("ToolKit", selection: $item.selectedToolKitID) {
                                    Text("No Toolkit").tag(nil as UUID?)
                                    ForEach(allToolKits, id: \.id) { kit in
                                        Text(kit.name)
                                            .tag(kit.id as UUID?)
                                    }
                                }
                                .pickerStyle(.menu)
                                .tint(industrialBlue)
                                .accessibilityIdentifier("toolKitPicker_\(item.name)")
                            }
                        }

                        // Feature #122: Info text for borrowed tools explaining why no set/kit pickers
                        if isBorrowedTool {
                            HStack(spacing: 6) {
                                Image(systemName: "info.circle.fill")
                                    .font(.caption)
                                    .foregroundColor(Color(red: 0.976, green: 0.451, blue: 0.086))
                                Text("Borrowed tools cannot be added to sets or kits.")
                                    .font(.caption2)
                                    .foregroundColor(.secondary)
                            }
                            .padding(.leading, 4)
                            .accessibilityIdentifier("borrowedToolNoKitInfo_\(item.name)")
                        }
                        // Info text if no sets or kits exist (for non-borrowed tools only)
                        else if allGroups.isEmpty && allToolKits.isEmpty {
                            Text("Tip: Create tool sets and kits in Garage to organize your tools.")
                                .font(.caption2)
                                .foregroundColor(.secondary)
                                .padding(.leading, 28)
                        }
                    }
                    .padding(.leading, 36)
                    .padding(.top, 4)
                }

                // Feature #98: Show category picker for selected consumables
                if item.type == .consumable && item.isSelected {
                    VStack(alignment: .leading, spacing: 6) {
                        HStack(spacing: 8) {
                            Image(systemName: "tag.fill")
                                .font(.caption)
                                .foregroundColor(steelGray)
                                .frame(width: 20)

                            Text("Category:")
                                .font(.caption)
                                .foregroundColor(.secondary)

                            Picker("Consumable Category", selection: Binding(
                                get: { item.selectedConsumableCategory ?? "other" },
                                set: { item.selectedConsumableCategory = $0 }
                            )) {
                                Text("Safety Wire").tag("safety_wire")
                                Text("Cotter Pin").tag("cotter_pin")
                                Text("O-Ring").tag("o_ring")
                                Text("Seal").tag("seal")
                                Text("Other").tag("other")
                            }
                            .pickerStyle(.menu)
                            .tint(Color(red: 0.976, green: 0.451, blue: 0.086))
                            .accessibilityIdentifier("consumableCategoryPicker_\(item.name)")
                        }

                        Text("Select a category to organize this consumable in your Garage")
                            .font(.caption2)
                            .foregroundColor(.secondary)
                            .padding(.leading, 28)
                    }
                    .padding(.leading, 36)
                    .padding(.top, 4)
                }

                // Feature #98: Show category picker for selected chemicals
                if item.type == .chemical && item.isSelected {
                    VStack(alignment: .leading, spacing: 6) {
                        HStack(spacing: 8) {
                            Image(systemName: "tag.fill")
                                .font(.caption)
                                .foregroundColor(steelGray)
                                .frame(width: 20)

                            Text("Category:")
                                .font(.caption)
                                .foregroundColor(.secondary)

                            Picker("Chemical Category", selection: Binding(
                                get: { item.selectedChemicalCategory ?? "other" },
                                set: { item.selectedChemicalCategory = $0 }
                            )) {
                                Text("Fluid").tag("fluid")
                                Text("Lubricant").tag("lubricant")
                                Text("Cleaner").tag("cleaner")
                                Text("Sealant").tag("sealant")
                                Text("Other").tag("other")
                            }
                            .pickerStyle(.menu)
                            .tint(Color(red: 0.133, green: 0.773, blue: 0.369))
                            .accessibilityIdentifier("chemicalCategoryPicker_\(item.name)")
                        }

                        Text("Select a category to organize this chemical in your Garage")
                            .font(.caption2)
                            .foregroundColor(.secondary)
                            .padding(.leading, 28)
                    }
                    .padding(.leading, 36)
                    .padding(.top, 4)
                }
            }
        }

        /// Builds a display name showing the set hierarchy path
        private func groupDisplayName(for group: ToolGroup) -> String {
            var path = [group.name]
            var current = group
            while let parent = current.parentGroup {
                path.insert(parent.name, at: 0)
                current = parent
            }
            return path.joined(separator: " > ")
        }
    }

    /// Adds the selected items to Garage by setting isInGarage = true
    /// Feature #97: Also assigns tools to selected sets and toolkits
    private func addSelectedToGarage() {
        var addedCount = 0

        for item in items where item.isSelected {
            switch item.type {
            case .tool:
                if let tool = fetchByPersistentID(FROTool.self, id: item.id, context: viewContext) {
                    tool.isInGarage = true
                    addedCount += 1

                    // Feature #97: Assign to selected tool set
                    if let groupID = item.selectedGroupID,
                       let group = fetchByPersistentID(FROToolGroup.self, id: groupID, context: viewContext) {
                        tool.group = group
                        print("AddToGaragePromptView: Assigned tool '\(tool.name)' to group '\(group.name)'")
                    }

                    // Feature #97: Assign to selected toolkit
                    if let toolKitID = item.selectedToolKitID,
                       let toolKit = fetchByPersistentID(FROToolKit.self, id: toolKitID, context: viewContext) {
                        if tool.toolKits == nil { tool.toolKits = [] }
                        tool.toolKits?.append(toolKit)
                        print("AddToGaragePromptView: Assigned tool '\(tool.name)' to toolkit '\(toolKit.name)'")
                    }

                    print("AddToGaragePromptView: Added tool '\(tool.name)' to Garage")
                }
            case .consumable:
                if let consumable = fetchByPersistentID(FROConsumable.self, id: item.id, context: viewContext) {
                    consumable.isInGarage = true
                    addedCount += 1

                    // Feature #98: Apply selected category if different from current
                    if let selectedCategory = item.selectedConsumableCategory {
                        let previousCategory = consumable.category
                        consumable.category = selectedCategory
                        if previousCategory != selectedCategory {
                            print("AddToGaragePromptView: Updated consumable '\(consumable.name)' category from '\(previousCategory)' to '\(selectedCategory)'")
                        }
                    }

                    print("AddToGaragePromptView: Added consumable '\(consumable.name)' to Garage with category '\(consumable.category)'")
                }
            case .chemical:
                if let chemical = fetchByPersistentID(FROChemical.self, id: item.id, context: viewContext) {
                    chemical.isInGarage = true
                    addedCount += 1

                    // Feature #98: Apply selected category if different from current
                    if let selectedCategory = item.selectedChemicalCategory {
                        let previousCategory = chemical.category
                        chemical.category = selectedCategory
                        if previousCategory != selectedCategory {
                            print("AddToGaragePromptView: Updated chemical '\(chemical.name)' category from '\(previousCategory)' to '\(selectedCategory)'")
                        }
                    }

                    print("AddToGaragePromptView: Added chemical '\(chemical.name)' to Garage with category '\(chemical.category)'")
                }
            }
        }

        // Save changes to Core Data
        if viewContext.hasChanges {
            do {
                try viewContext.save()
                print("AddToGaragePromptView: Successfully added \(addedCount) items to Garage")
                hasAddedItems = true
            } catch {
                print("AddToGaragePromptView: Failed to save - \(error)")
            }
        }

        onDismiss()
        dismiss()
    }

    /// Dismisses the prompt without adding items to Garage
    private func skipAndDismiss() {
        print("AddToGaragePromptView: User skipped adding items to Garage")
        onDismiss()
        dismiss()
    }
}

// MARK: - Helper Functions

private func ownershipLabel(for ownershipType: String?) -> String {
    switch ownershipType {
    case "personal": return "Personal"
    case "shop": return "Shop"
    case "borrowed": return "Borrowed"
    case "imported": return "Imported"
    default: return "Personal"
    }
}

private func consumableCategoryLabel(for category: String?) -> String {
    switch category {
    case "safety_wire": return "Safety Wire"
    case "cotter_pin": return "Cotter Pin"
    case "o_ring": return "O-Ring"
    case "seal": return "Seal"
    case "other": return "Other"
    default: return "Other"
    }
}

private func chemicalCategoryLabel(for category: String?) -> String {
    switch category {
    case "fluid": return "Fluid"
    case "lubricant": return "Lubricant"
    case "cleaner": return "Cleaner"
    case "sealant": return "Sealant"
    case "other": return "Other"
    default: return "Other"
    }
}

// MARK: - Preview

#if DEBUG
struct AddToGaragePromptView_Previews: PreviewProvider {
    static var previews: some View {
        AddToGaragePromptView(
            onDismiss: { }
        )
        
    }
}
#endif

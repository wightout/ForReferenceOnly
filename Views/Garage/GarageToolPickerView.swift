import SwiftUI
import Foundation
import SwiftData

/// A picker view that presents all tools from the Garage for selection.
/// Used when creating/editing job records to pull tools from inventory.
/// Supports creating new tools on-the-fly from within the picker (Feature #91).
/// Shows matching tools from Garage as user types for duplicate prevention (Feature #94).
/// Feature #140: Tool Sets appear as collapsible groups in the picker.
/// Feature #141: Tool Kits appear as collapsible groups in the picker.
/// Feature #164: Search bar at top allows quick filtering of tools by name.
/// Feature #167: Search also matches Tool Set names - auto-expands with all tools visible.
/// Feature #168: Search also matches Tool Kit names - auto-expands with all tools visible.
/// Feature #169: When searching for a tool inside a set, the set appears expanded with ALL tools visible.
/// Feature #171: Search bar has clear button (X) - provided automatically by SwiftUI .searchable modifier.
/// Feature #172: Search bar uses standard iOS styling (magnifying glass, rounded corners, gray background).
/// Feature #173: Search preserves selections - localSelection state is independent of searchText.
///               When user searches and selects tools, then clears the search, all selections persist.
struct GarageToolPickerView: View {
    @Environment(\.modelContext) private var viewContext
    @Environment(\.dismiss) private var dismiss

    /// Feature #164: Search text for filtering tools
    @State private var searchText: String = ""

    /// Fetch all tools (will be sorted by size then name in display)
    @Query(sort: \FROTool.name, order: .forward)
    private var allTools: [FROTool]

    /// Feature #140: Fetch all tool groups (Tool Sets) for collapsible display
    @Query(sort: [SortDescriptor(\FROToolGroup.sortOrder, order: .forward), SortDescriptor(\FROToolGroup.name, order: .forward)])
    private var allToolGroups: [FROToolGroup]

    /// Feature #141: Fetch all tool kits for collapsible display
    @Query(sort: \FROToolKit.name, order: .forward)
    private var allToolKits: [FROToolKit]

    /// Tools sorted by size then name
    private var sortedTools: [Tool] {
        Array(allTools).sortedBySize()
    }

    // MARK: - Feature #164: Search Filtering

    /// Feature #164: Checks if a tool matches the current search text.
    /// Matches against tool name and aliases using case-insensitive contains.
    private func toolMatchesSearch(_ tool: Tool) -> Bool {
        let trimmedSearch = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedSearch.isEmpty else { return true }

        let lowercasedSearch = trimmedSearch.lowercased()

        // Check main name
        if tool.name.lowercased().contains(lowercasedSearch) {
            return true
        }

        // Also check aliases
        if let aliases = tool.aliases {
            for alias in aliases {
                if alias.lowercased().contains(lowercasedSearch) {
                    return true
                }
            }
        }

        return false
    }

    /// Feature #164: Whether search is active (user has typed something)
    private var isSearchActive: Bool {
        !searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    /// Feature #140: Tool Sets with at least one tool
    private var toolSetsWithTools: [ToolGroup] {
        Array(allToolGroups).filter { group in
            guard let tools = group.tools else { return false }
            return !tools.isEmpty
        }
    }

    /// Feature #164: Tool Sets filtered by search text (only show sets that have matching tools)
    /// Feature #167: Also matches Tool Set names - if the Tool Set name matches, include it and show all its tools
    private var filteredToolSets: [ToolGroup] {
        guard isSearchActive else { return toolSetsWithTools }
        let lowercasedSearch = searchText.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return toolSetsWithTools.filter { group in
            // Feature #167: Check if Tool Set name matches search
            if group.name.lowercased().contains(lowercasedSearch) {
                return true
            }
            // Also check if any tool within the set matches the search
            guard let tools = group.tools else { return false }
            return tools.contains { toolMatchesSearch($0) }
        }
    }

    /// Feature #167: Checks if a Tool Set's name matches the current search text.
    /// Used to determine if the Tool Set should be auto-expanded when its name matches.
    private func toolSetNameMatchesSearch(_ toolSet: ToolGroup) -> Bool {
        guard isSearchActive else { return false }
        let lowercasedSearch = searchText.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return toolSet.name.lowercased().contains(lowercasedSearch)
    }

    /// Feature #141: Tool Kits with at least one tool
    private var toolKitsWithTools: [ToolKit] {
        Array(allToolKits).filter { kit in
            guard let tools = kit.tools else { return false }
            return !tools.isEmpty
        }
    }

    /// Feature #164: Tool Kits filtered by search text (only show kits that have matching tools)
    /// Feature #168: Also matches Tool Kit names - if the Tool Kit name matches, include it and show all its tools
    private var filteredToolKits: [ToolKit] {
        guard isSearchActive else { return toolKitsWithTools }
        let lowercasedSearch = searchText.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return toolKitsWithTools.filter { kit in
            // Feature #168: Check if Tool Kit name matches search
            if kit.name.lowercased().contains(lowercasedSearch) {
                return true
            }
            // Also check if any tool within the kit matches the search
            guard let tools = kit.tools else { return false }
            return tools.contains { toolMatchesSearch($0) }
        }
    }

    /// Feature #168: Checks if a Tool Kit's name matches the current search text.
    /// Used to determine if the Tool Kit should be auto-expanded when its name matches.
    private func toolKitNameMatchesSearch(_ toolKit: ToolKit) -> Bool {
        guard isSearchActive else { return false }
        let lowercasedSearch = searchText.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return toolKit.name.lowercased().contains(lowercasedSearch)
    }

    /// Feature #140: Tools that are NOT in any Tool Set (ungrouped tools)
    /// Feature #141: Also excludes tools that are in Tool Kits from the "Individual Tools" section
    /// since they'll be shown under their respective Kit
    private var ungroupedTools: [Tool] {
        Array(allTools).filter { tool in
            // Tool must not be in a Tool Set
            guard tool.group == nil else { return false }
            // Tool must not be in any Tool Kit with tools
            guard let toolKits = tool.toolKits else { return true }
            // If the tool is only in empty kits, show it in ungrouped
            return toolKits.allSatisfy { kit in
                guard let kitTools = kit.tools else { return true }
                return kitTools.isEmpty
            }
        }.sortedBySize()
    }

    /// Feature #164: Ungrouped tools filtered by search text
    private var filteredUngroupedTools: [Tool] {
        guard isSearchActive else { return ungroupedTools }
        return ungroupedTools.filter { toolMatchesSearch($0) }
    }

    /// Binding to the set of selected tool object IDs
    @Binding var selectedToolIDs: Set<UUID>

    /// Local tracking of selections (copy on appear, apply on confirm)
    /// Feature #173: This state is INDEPENDENT of searchText - selections persist regardless of search/filter state.
    /// Searching only filters the displayed tools; it never modifies localSelection.
    @State private var localSelection: Set<UUID> = []

    // MARK: - Tool Set Expansion State (Feature #140)

    /// Tracks which Tool Sets are expanded. Tool Sets are collapsed by default for a shorter list.
    @State private var expandedToolSets: Set<UUID> = []

    // MARK: - Tool Kit Expansion State (Feature #141)

    /// Tracks which Tool Kits are expanded. Tool Kits are collapsed by default for a shorter list.
    @State private var expandedToolKits: Set<UUID> = []

    // MARK: - New Tool Creation State (Feature #91)

    /// Whether the inline tool creation form is showing
    @State private var showingNewToolForm = false

    /// New tool name being entered
    @State private var newToolName: String = ""

    /// New tool ownership type
    @State private var newToolOwnership: String = "personal"

    /// Who the tool is borrowed from (only used when ownership is "borrowed")
    @State private var newToolBorrowedFrom: String = ""

    /// Error state for new tool creation
    @State private var showingNewToolError = false
    @State private var newToolErrorMessage = ""

    /// Whether a new tool is currently being saved
    @State private var isSavingNewTool = false

    // MARK: - Autocomplete Suggestions State (Feature #94)

    /// Computed property that returns matching tools based on the typed name.
    /// Uses case-insensitive contains match for partial matching.
    private var matchingTools: [Tool] {
        let trimmedInput = newToolName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmedInput.count >= 2 else { return [] }

        let lowercasedInput = trimmedInput.lowercased()
        return allTools.filter { tool in
            let toolName = tool.name
            // Check main name
            if toolName.lowercased().contains(lowercasedInput) {
                return true
            }
            // Also check aliases
            if let aliases = tool.aliases {
                for alias in aliases {
                    if alias.lowercased().contains(lowercasedInput) {
                        return true
                    }
                }
            }
            return false
        }.sortedBySize()
    }

    /// Whether to show the suggestions dropdown
    private var showSuggestions: Bool {
        showingNewToolForm && newToolName.trimmingCharacters(in: .whitespacesAndNewlines).count >= 2
    }

    // MARK: - Extracted Section Views (helps Swift type-checker)

    /// Add New Tool section — extracted to reduce body complexity
    @ViewBuilder
    private var addNewToolSection: some View {
        Section {
            if showingNewToolForm {
                // Inline form for creating a new tool
                VStack(alignment: .leading, spacing: 12) {
                    // Tool Name Field
                    TextField("Tool name (e.g., 9/16 combination wrench)", text: $newToolName)
                        .font(.body)
                        .autocorrectionDisabled()
                        .accessibilityIdentifier("newToolNameField")
                        .accessibilityLabel("New tool name")

                            // MARK: - Autocomplete Suggestions (Feature #94)
                            if showSuggestions {
                                VStack(alignment: .leading, spacing: 0) {
                                    if matchingTools.isEmpty {
                                        // No matches indicator
                                        HStack(spacing: 8) {
                                            Image(systemName: "magnifyingglass")
                                                .font(.caption)
                                                .foregroundColor(.secondary)
                                            Text("No matching tools in Garage")
                                                .font(.caption)
                                                .foregroundColor(.secondary)
                                        }
                                        .padding(.horizontal, 12)
                                        .padding(.vertical, 10)
                                        .frame(maxWidth: .infinity, alignment: .leading)
                                        .background(Color(UIColor.secondarySystemBackground))
                                        .cornerRadius(8)
                                        .accessibilityIdentifier("noMatchingSuggestionsLabel")
                                    } else {
                                        // Show matching suggestions
                                        VStack(alignment: .leading, spacing: 0) {
                                            HStack {
                                                Image(systemName: "lightbulb.fill")
                                                    .font(.caption)
                                                    .foregroundColor(Color(red: 0.976, green: 0.451, blue: 0.086))
                                                Text("Existing tools matching '\(newToolName.trimmingCharacters(in: .whitespacesAndNewlines))':")
                                                    .font(.caption)
                                                    .foregroundColor(.secondary)
                                            }
                                            .padding(.horizontal, 12)
                                            .padding(.top, 8)
                                            .padding(.bottom, 4)
                                            .accessibilityIdentifier("matchingSuggestionsHeader")

                                            ForEach(matchingTools.prefix(5), id: \.id) { tool in
                                                Button(action: {
                                                    selectExistingTool(tool)
                                                }) {
                                                    HStack(spacing: 10) {
                                                        Image(systemName: "wrench.fill")
                                                            .font(.caption)
                                                            .foregroundColor(Color(red: 0.145, green: 0.388, blue: 0.922))

                                                        VStack(alignment: .leading, spacing: 2) {
                                                            Text(tool.name)
                                                                .font(.subheadline)
                                                                .fontWeight(.medium)
                                                                .foregroundColor(.primary)

                                                            // Show ownership badge inline
                                                            Text(ownershipLabel(for: tool))
                                                                .font(.caption2)
                                                                .foregroundColor(ownershipColor(for: tool))
                                                        }

                                                        Spacer()

                                                        // Indicate this will add the existing tool
                                                        if localSelection.contains(tool.id) {
                                                            Image(systemName: "checkmark.circle.fill")
                                                                .foregroundColor(Color(red: 0.133, green: 0.773, blue: 0.369))
                                                        } else {
                                                            Text("Add")
                                                                .font(.caption)
                                                                .fontWeight(.medium)
                                                                .foregroundColor(Color(red: 0.145, green: 0.388, blue: 0.922))
                                                        }
                                                    }
                                                    .padding(.horizontal, 12)
                                                    .padding(.vertical, 8)
                                                    .contentShape(Rectangle())
                                                }
                                                .buttonStyle(.plain)
                                                .accessibilityIdentifier("toolSuggestion_\(tool.name)")
                                                .accessibilityLabel("Select \(tool.name) from Garage")
                                                .accessibilityHint("Adds existing tool instead of creating a new one")

                                                if tool != matchingTools.prefix(5).last {
                                                    Divider()
                                                        .padding(.leading, 34)
                                                }
                                            }

                                            // Show count if there are more matches
                                            if matchingTools.count > 5 {
                                                Text("+ \(matchingTools.count - 5) more matches")
                                                    .font(.caption2)
                                                    .foregroundColor(.secondary)
                                                    .padding(.horizontal, 12)
                                                    .padding(.vertical, 6)
                                                    .accessibilityIdentifier("moreMatchesLabel")
                                            }
                                        }
                                        .background(Color(UIColor.secondarySystemBackground))
                                        .cornerRadius(8)
                                        .accessibilityIdentifier("toolSuggestionsContainer")
                                    }
                                }
                            }

                            // Ownership Picker
                            Picker("Ownership", selection: $newToolOwnership) {
                                Text("Personal").tag("personal")
                                Text("Shop").tag("shop")
                                Text("Borrowed").tag("borrowed")
                            }
                            .pickerStyle(.segmented)
                            .accessibilityIdentifier("newToolOwnershipPicker")
                            .accessibilityLabel("Tool ownership type")

                            // Feature #104: Borrowed From Field with autocomplete (shown only when "borrowed" is selected)
                            if newToolOwnership == "borrowed" {
                                BorrowedFromAutocompleteField(
                                    borrowedFrom: $newToolBorrowedFrom,
                                    placeholder: "Borrowed from...",
                                    accessibilityPrefix: "newToolPicker_"
                                )
                            }

                            // Action Buttons
                            HStack(spacing: 12) {
                                Button(action: {
                                    // Cancel - reset and hide form
                                    resetNewToolForm()
                                }) {
                                    Text("Cancel")
                                        .frame(maxWidth: .infinity)
                                        .padding(.vertical, 8)
                                }
                                .buttonStyle(.bordered)
                                .accessibilityIdentifier("cancelNewToolButton")

                                Button(action: {
                                    saveNewTool()
                                }) {
                                    if isSavingNewTool {
                                        ProgressView()
                                            .progressViewStyle(CircularProgressViewStyle())
                                            .frame(maxWidth: .infinity)
                                            .padding(.vertical, 8)
                                    } else {
                                        Text("Create & Add")
                                            .fontWeight(.semibold)
                                            .frame(maxWidth: .infinity)
                                            .padding(.vertical, 8)
                                    }
                                }
                                .buttonStyle(.borderedProminent)
                                .disabled(newToolName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || isSavingNewTool)
                                .accessibilityIdentifier("createAndAddToolButton")
                                .accessibilityLabel("Create and add tool to job")
                            }
                        }
                        .padding(.vertical, 4)
                    } else {
                        // Button to show the new tool form
                        Button(action: {
                            withAnimation {
                                showingNewToolForm = true
                            }
                        }) {
                            HStack {
                                Image(systemName: "plus.circle.fill")
                                    .font(.title3)
                                    .foregroundColor(Color(red: 0.145, green: 0.388, blue: 0.922))
                                Text("Create New Tool")
                                    .fontWeight(.medium)
                                    .foregroundColor(Color(red: 0.145, green: 0.388, blue: 0.922))
                                Spacer()
                            }
                            .padding(.vertical, 4)
                        }
                        .accessibilityIdentifier("createNewToolButton")
                        .accessibilityLabel("Create New Tool")
                        .accessibilityHint("Opens a form to create a new tool and add it to this job")
                    }
        } header: {
            Text("Add New Tool")
        }
    }

    /// Tool Sets section — extracted to reduce body complexity
    @ViewBuilder
    private var toolSetsSection: some View {
        if !filteredToolSets.isEmpty {
            Section {
                ForEach(filteredToolSets, id: \.id) { toolSet in
                    ToolSetCollapsibleRow(
                        toolSet: toolSet,
                        isExpanded: expandedToolSets.contains(toolSet.id) || toolSetNameMatchesSearch(toolSet),
                        localSelection: $localSelection,
                        searchText: searchText,
                        onToggleExpand: { toggleExpandToolSet(toolSet.id) },
                        onForceExpand: { forceExpandToolSet(toolSet.id) },
                        onToggleToolSelection: { toolObjectID in toggleSelection(toolObjectID) },
                        onSelectAll: { selectAllToolsInSet(toolSet) },
                        onDeselectAll: { deselectAllToolsInSet(toolSet) }
                    )
                }
            } header: {
                Text("Tool Sets (\(filteredToolSets.count))")
            } footer: {
                Text("Tap a Tool Set to expand and see tools inside")
                    .font(.caption)
            }
        }
    }

    /// Tool Kits section — extracted to reduce body complexity
    @ViewBuilder
    private var toolKitsSection: some View {
        if !filteredToolKits.isEmpty {
            Section {
                ForEach(filteredToolKits, id: \.id) { toolKit in
                    ToolKitCollapsibleRow(
                        toolKit: toolKit,
                        isExpanded: expandedToolKits.contains(toolKit.id) || toolKitNameMatchesSearch(toolKit),
                        localSelection: $localSelection,
                        searchText: searchText,
                        onToggleExpand: { toggleExpandToolKit(toolKit.id) },
                        onForceExpand: { forceExpandToolKit(toolKit.id) },
                        onToggleToolSelection: { toolObjectID in toggleSelection(toolObjectID) },
                        onSelectAll: { selectAllToolsInKit(toolKit) },
                        onDeselectAll: { deselectAllToolsInKit(toolKit) }
                    )
                }
            } header: {
                Text("Tool Kits (\(filteredToolKits.count))")
            } footer: {
                Text("Tap a Tool Kit to expand and see tools inside")
                    .font(.caption)
            }
        }
    }

    var body: some View {
        NavigationStack {
            List {
                addNewToolSection
                toolSetsSection
                toolKitsSection

                // MARK: - Ungrouped Tools Section (Feature #164)
                if !filteredUngroupedTools.isEmpty {
                    Section {
                        ForEach(filteredUngroupedTools, id: \.id) { tool in
                            ToolSelectionRow(
                                tool: tool,
                                isSelected: localSelection.contains(tool.id)
                            )
                            .contentShape(Rectangle())
                            .onTapGesture {
                                toggleSelection(tool.id)
                            }
                        }
                    } header: {
                        Text("Individual Tools (\(filteredUngroupedTools.count))")
                    }
                }

                // MARK: - Empty State
                if allTools.isEmpty {
                    Section {
                        VStack(spacing: 8) {
                            Image(systemName: "wrench.and.screwdriver")
                                .font(.system(size: 30))
                                .foregroundColor(Color(red: 0.392, green: 0.455, blue: 0.545))
                            Text("No tools in Garage yet")
                                .font(.subheadline)
                                .foregroundColor(.secondary)
                            Text("Create a new tool above to get started")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 16)
                    } header: {
                        Text("From Garage")
                    }
                }

                // MARK: - No Search Results State
                if isSearchActive && filteredToolSets.isEmpty && filteredToolKits.isEmpty && filteredUngroupedTools.isEmpty && !allTools.isEmpty {
                    Section {
                        VStack(spacing: 8) {
                            Image(systemName: "magnifyingglass")
                                .font(.system(size: 30))
                                .foregroundColor(Color(red: 0.392, green: 0.455, blue: 0.545))
                            Text("No tools matching '\(searchText.trimmingCharacters(in: .whitespacesAndNewlines))'")
                                .font(.subheadline)
                                .foregroundColor(.secondary)
                            Text("Try a different search term or create a new tool")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 16)
                        .accessibilityIdentifier("noSearchResultsView")
                    } header: {
                        Text("Search Results")
                    }
                }
            }
            .listStyle(.insetGrouped)
            .navigationTitle("Select Tools")
            .navigationBarTitleDisplayMode(.inline)
            // Feature #164: Search bar at top for filtering tools
            // Feature #171: SwiftUI .searchable automatically provides a clear button (X)
            // that appears when text is entered, allowing users to quickly clear the search.
            // The clear button is built-in iOS behavior - no custom implementation needed.
            // Feature #172: Uses standard iOS search bar styling via SwiftUI .searchable modifier.
            // This automatically provides: magnifying glass icon, rounded corners, gray background.
            .searchable(
                text: $searchText,
                placement: .navigationBarDrawer(displayMode: .always),
                prompt: "Search tools..."
            )
            .accessibilityIdentifier("toolPickerSearchBar")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        dismiss()
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done (\(localSelection.count))") {
                        selectedToolIDs = localSelection
                        dismiss()
                    }
                    .fontWeight(.semibold)
                }
            }
            .onAppear {
                localSelection = selectedToolIDs
            }
            // Prevent accidental swipe-to-dismiss when selections have been made
            .interactiveDismissDisabled(localSelection != selectedToolIDs)
            // Feature #164: Auto-expand Tool Sets and Tool Kits when searching
            .onChange(of: searchText) { oldValue, newValue in
                let trimmedNew = newValue.trimmingCharacters(in: .whitespacesAndNewlines)
                let trimmedOld = oldValue.trimmingCharacters(in: .whitespacesAndNewlines)

                // When search becomes active (user types something), expand all filtered sets/kits
                if trimmedOld.isEmpty && !trimmedNew.isEmpty {
                    // Auto-expand all Tool Sets that have matching tools
                    for toolSet in filteredToolSets {
                        expandedToolSets.insert(toolSet.id)
                    }
                    // Auto-expand all Tool Kits that have matching tools
                    for toolKit in filteredToolKits {
                        expandedToolKits.insert(toolKit.id)
                    }
                }
                // When search is cleared, collapse all (return to default state)
                else if !trimmedOld.isEmpty && trimmedNew.isEmpty {
                    expandedToolSets.removeAll()
                    expandedToolKits.removeAll()
                }
                // When search text changes, ensure all matching sets/kits are expanded
                else if !trimmedNew.isEmpty {
                    for toolSet in filteredToolSets {
                        expandedToolSets.insert(toolSet.id)
                    }
                    for toolKit in filteredToolKits {
                        expandedToolKits.insert(toolKit.id)
                    }
                }
            }
            .alert("Error", isPresented: $showingNewToolError) {
                Button("OK") { }
            } message: {
                Text(newToolErrorMessage)
            }
        }
    }

    private func toggleSelection(_ objectID: UUID) {
        if localSelection.contains(objectID) {
            localSelection.remove(objectID)
        } else {
            localSelection.insert(objectID)
        }
    }

    // MARK: - Expand/Collapse Helpers

    private func toggleExpandToolSet(_ objectID: UUID) {
        withAnimation(.easeInOut(duration: 0.2)) {
            if expandedToolSets.contains(objectID) {
                expandedToolSets.remove(objectID)
            } else {
                expandedToolSets.insert(objectID)
            }
        }
    }

    private func forceExpandToolSet(_ objectID: UUID) {
        let _ = withAnimation(.easeInOut(duration: 0.2)) {
            expandedToolSets.insert(objectID)
        }
    }

    private func toggleExpandToolKit(_ objectID: UUID) {
        withAnimation(.easeInOut(duration: 0.2)) {
            if expandedToolKits.contains(objectID) {
                expandedToolKits.remove(objectID)
            } else {
                expandedToolKits.insert(objectID)
            }
        }
    }

    private func forceExpandToolKit(_ objectID: UUID) {
        let _ = withAnimation(.easeInOut(duration: 0.2)) {
            expandedToolKits.insert(objectID)
        }
    }

    // MARK: - Select All / Deselect All Methods (Feature #148, #149, #150, #151)

    /// Feature #148: Selects all tools within a Tool Set
    private func selectAllToolsInSet(_ toolSet: ToolGroup) {
        guard let tools = toolSet.tools else { return }
        for tool in tools {
            localSelection.insert(tool.id)
        }
        print("GarageToolPickerView: Selected all \(tools.count) tools in Tool Set '\(toolSet.name)'")
    }

    /// Feature #150: Deselects all tools within a Tool Set
    private func deselectAllToolsInSet(_ toolSet: ToolGroup) {
        guard let tools = toolSet.tools else { return }
        var deselectedCount = 0
        for tool in tools {
            if localSelection.remove(tool.id) != nil {
                deselectedCount += 1
            }
        }
        print("GarageToolPickerView: Deselected \(deselectedCount) tools in Tool Set '\(toolSet.name)'")
    }

    /// Feature #149: Selects all tools within a Tool Kit
    private func selectAllToolsInKit(_ toolKit: ToolKit) {
        guard let tools = toolKit.tools else { return }
        for tool in tools {
            localSelection.insert(tool.id)
        }
        print("GarageToolPickerView: Selected all \(tools.count) tools in Tool Kit '\(toolKit.name)'")
    }

    /// Feature #151: Deselects all tools within a Tool Kit
    private func deselectAllToolsInKit(_ toolKit: ToolKit) {
        guard let tools = toolKit.tools else { return }
        var deselectedCount = 0
        for tool in tools {
            if localSelection.remove(tool.id) != nil {
                deselectedCount += 1
            }
        }
        print("GarageToolPickerView: Deselected \(deselectedCount) tools in Tool Kit '\(toolKit.name)'")
    }

    // MARK: - New Tool Creation Methods (Feature #91)

    /// Resets the new tool form to its initial state
    private func resetNewToolForm() {
        newToolName = ""
        newToolOwnership = "personal"
        newToolBorrowedFrom = ""
        showingNewToolForm = false
        isSavingNewTool = false
    }

    // MARK: - Autocomplete Methods (Feature #94)

    /// Selects an existing tool from the suggestions instead of creating a new one.
    /// Adds the tool to the selection and resets the form.
    private func selectExistingTool(_ tool: Tool) {
        // Add to local selection (user taps Done to commit)
        localSelection.insert(tool.id)
        print("GarageToolPickerView: Selected existing tool '\(tool.name)' from suggestions")

        // Collapse the create form so user can see the checkmark
        withAnimation {
            resetNewToolForm()
        }
    }

    /// Returns human-readable ownership label for a tool
    private func ownershipLabel(for tool: Tool) -> String {
        switch tool.ownershipType {
        case "personal": return "Personal"
        case "shop": return "Shop"
        case "borrowed":
            if let from = tool.borrowedFrom, !from.isEmpty {
                return "Borrowed from \(from)"
            }
            return "Borrowed"
        case "imported": return "Imported"
        default: return "Personal"
        }
    }

    /// Returns the color for ownership badge
    private func ownershipColor(for tool: Tool) -> Color {
        switch tool.ownershipType {
        case "personal": return Color(red: 0.145, green: 0.388, blue: 0.922)
        case "shop": return Color(red: 0.392, green: 0.455, blue: 0.545)
        case "borrowed": return Color(red: 0.976, green: 0.451, blue: 0.086)
        case "imported": return Color(red: 0.608, green: 0.318, blue: 0.878)
        default: return .blue
        }
    }

    /// Creates a new tool in Core Data and auto-selects it
    private func saveNewTool() {
        let trimmedName = newToolName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedName.isEmpty else {
            newToolErrorMessage = "Tool name cannot be empty."
            showingNewToolError = true
            return
        }

        // Prevent double-tap
        guard !isSavingNewTool else { return }
        isSavingNewTool = true

        // Create the new tool in SwiftData
        // Mark as not in Garage initially - user will be prompted after job save (Feature #96)
        let borrowedFrom: String? = (newToolOwnership == "borrowed") ? {
            let trimmed = newToolBorrowedFrom.trimmingCharacters(in: .whitespacesAndNewlines)
            return trimmed.isEmpty ? nil : trimmed
        }() : nil

        let tool = FROTool(
            name: trimmedName,
            ownershipType: newToolOwnership,
            borrowedFrom: borrowedFrom,
            isInGarage: false
        )
        viewContext.insert(tool)

        do {
            try viewContext.save()
            print("GarageToolPickerView: Created new tool '\(trimmedName)' with ownership '\(newToolOwnership)'")

            // Auto-select the newly created tool (user taps Done to commit)
            localSelection.insert(tool.id)
            print("GarageToolPickerView: Created and auto-selected new tool in picker")

            // Collapse the create form so the user can see the new item checked in the list
            withAnimation {
                resetNewToolForm()
            }
        } catch {
            isSavingNewTool = false
            newToolErrorMessage = "Failed to create tool: \(error.localizedDescription)"
            showingNewToolError = true
            print("GarageToolPickerView: Failed to save new tool - \(error)")
        }
    }
}

/// A row showing a tool with a checkmark for selection state.
struct ToolSelectionRow: View {
    @Bindable var tool: Tool
    let isSelected: Bool

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(tool.name)
                    .font(.body)
                    .fontWeight(.medium)

                HStack(spacing: 8) {
                    // Ownership badge
                    Text(ownershipLabel)
                        .font(.caption2)
                        .fontWeight(.medium)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(ownershipColor.opacity(0.15))
                        .foregroundColor(ownershipColor)
                        .clipShape(Capsule())

                    if let notes = tool.notes, !notes.isEmpty {
                        Text(notes)
                            .font(.caption)
                            .foregroundColor(.secondary)
                            .lineLimit(1)
                    }
                }
            }

            Spacer()

            if isSelected {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundColor(Color(red: 0.145, green: 0.388, blue: 0.922))
                    .font(.title3)
            } else {
                Image(systemName: "circle")
                    .foregroundColor(.secondary)
                    .font(.title3)
            }
        }
        .padding(.vertical, 4)
    }

    private var ownershipLabel: String {
        switch tool.ownershipType {
        case "personal": return "Personal"
        case "shop": return "Shop"
        case "borrowed": return "Borrowed"
        case "imported": return "Imported"
        default: return "Personal"
        }
    }

    private var ownershipColor: Color {
        switch tool.ownershipType {
        case "personal": return Color(red: 0.145, green: 0.388, blue: 0.922)
        case "shop": return Color(red: 0.392, green: 0.455, blue: 0.545)
        case "borrowed": return Color(red: 0.976, green: 0.451, blue: 0.086)
        case "imported": return Color(red: 0.608, green: 0.318, blue: 0.878)
        default: return .blue
        }
    }
}

// MARK: - Tool Set Collapsible Row (Feature #140, #167)

/// A row representing a Tool Set that can be expanded/collapsed to show/hide tools within it.
/// When collapsed, shows the Tool Set name with a chevron indicator.
/// When expanded, shows the Tool Set header and all tools within it indented below.
/// Feature #148: When expanded, shows a "Select All" button to select all tools in the set.
/// Feature #150: When expanded and tools are selected, shows a "Deselect All" button.
/// Feature #164: Filters tools based on search text when active.
/// Feature #167: Auto-expands and shows all tools when Tool Set name matches search.
struct ToolSetCollapsibleRow: View {
    @Bindable var toolSet: ToolGroup
    let isExpanded: Bool
    @Binding var localSelection: Set<UUID>
    let searchText: String  // Feature #164: Search text for filtering
    let onToggleExpand: () -> Void
    let onForceExpand: () -> Void  // Force-expand without toggling (used by checkbox)
    let onToggleToolSelection: (UUID) -> Void
    let onSelectAll: () -> Void  // Feature #148: Select All callback
    let onDeselectAll: () -> Void  // Feature #150: Deselect All callback

    /// Tri-state checkbox icon for set selection
    private var checkboxIcon: String {
        if selectedCount == 0 {
            return "circle"
        } else if selectedCount == toolsInSet.count {
            return "checkmark.circle.fill"
        } else {
            return "minus.circle.fill"
        }
    }

    /// Tri-state checkbox color
    private var checkboxColor: Color {
        if selectedCount == 0 {
            return .secondary
        } else {
            return Color(red: 0.145, green: 0.388, blue: 0.922) // Industrial blue
        }
    }

    /// Feature #164: Checks if a tool matches the search text
    private func toolMatchesSearch(_ tool: Tool) -> Bool {
        let trimmedSearch = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedSearch.isEmpty else { return true }

        let lowercasedSearch = trimmedSearch.lowercased()

        // Check main name
        if tool.name.lowercased().contains(lowercasedSearch) {
            return true
        }

        // Also check aliases
        if let aliases = tool.aliases {
            for alias in aliases {
                if alias.lowercased().contains(lowercasedSearch) {
                    return true
                }
            }
        }

        return false
    }

    /// Feature #167: Checks if the Tool Set's name matches the current search text
    private var toolSetNameMatchesSearch: Bool {
        let trimmedSearch = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedSearch.isEmpty else { return false }
        let lowercasedSearch = trimmedSearch.lowercased()
        return toolSet.name.lowercased().contains(lowercasedSearch)
    }

    /// Tools within this Tool Set, sorted by size
    /// Feature #167: Show ALL tools when Tool Set name matches search
    /// Feature #169: Show ALL tools when ANY tool in the set matches search
    /// (The set appears because filteredToolSets includes it - so show all tools)
    private var toolsInSet: [Tool] {
        guard let tools = toolSet.tools else { return [] }
        let allToolsInSet = Array(tools).sortedBySize()
        // Feature #169: Always show ALL tools in an expanded Tool Set
        // The Tool Set only appears in the filtered list if:
        // - The Tool Set name matches the search (Feature #167), OR
        // - At least one tool within matches the search
        // In both cases, show all tools so user can see the complete set
        return allToolsInSet
    }

    /// Count of selected tools within this Tool Set (filtered)
    private var selectedCount: Int {
        toolsInSet.filter { localSelection.contains($0.id) }.count
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Tool Set Header (always visible) — split into checkbox + row tap targets
            HStack(spacing: 0) {
                // Tri-state checkbox — tappable independently
                Button(action: {
                    if selectedCount == toolsInSet.count {
                        // All selected → deselect all
                        onDeselectAll()
                    } else {
                        // None or partial → select all + auto-expand
                        onSelectAll()
                        if !isExpanded {
                            onForceExpand()
                        }
                    }
                }) {
                    Image(systemName: checkboxIcon)
                        .font(.title3)
                        .foregroundColor(checkboxColor)
                        .frame(width: 36, height: 36)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("toolSetCheckbox_\(toolSet.name)")
                .accessibilityLabel(selectedCount == 0 ? "Select all tools in \(toolSet.name)" : selectedCount == toolsInSet.count ? "Deselect all tools in \(toolSet.name)" : "\(selectedCount) of \(toolsInSet.count) selected in \(toolSet.name)")

                // Row content — tapping expands/collapses
                Button(action: onToggleExpand) {
                    HStack(spacing: 12) {
                        // Chevron indicator (rotates when expanded)
                        Image(systemName: "chevron.right")
                            .font(.caption)
                            .fontWeight(.semibold)
                            .foregroundColor(Color(red: 0.145, green: 0.388, blue: 0.922))
                            .rotationEffect(.degrees(isExpanded ? 90 : 0))
                            .animation(.easeInOut(duration: 0.2), value: isExpanded)
                            .accessibilityHidden(true)

                        // Tool Set icon
                        Image(systemName: "square.grid.2x2.fill")
                            .font(.body)
                            .foregroundColor(Color(red: 0.145, green: 0.388, blue: 0.922))

                        VStack(alignment: .leading, spacing: 2) {
                            Text(toolSet.name)
                                .font(.body)
                                .fontWeight(.medium)
                                .foregroundColor(.primary)

                            HStack(spacing: 4) {
                                Text("\(toolsInSet.count) tool\(toolsInSet.count == 1 ? "" : "s")")
                                    .font(.caption)
                                    .foregroundColor(.secondary)

                                // Feature #145: Selection count badge uses industrial blue accent color
                                if selectedCount > 0 {
                                    Text("• \(selectedCount) selected")
                                        .font(.caption)
                                        .fontWeight(.medium)
                                        .foregroundColor(Color(red: 0.145, green: 0.388, blue: 0.922))
                                }
                            }
                        }

                        Spacer()

                        // Measurement type badge if present
                        if let measurementType = toolSet.measurementType, !measurementType.isEmpty {
                            Text(measurementType.uppercased())
                                .font(.caption2)
                                .fontWeight(.medium)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(Color(red: 0.145, green: 0.388, blue: 0.922).opacity(0.15))
                                .foregroundColor(Color(red: 0.145, green: 0.388, blue: 0.922))
                                .clipShape(Capsule())
                        }
                    }
                    .padding(.vertical, 8)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
            .accessibilityIdentifier("toolSetRow_\(toolSet.name)")
            .accessibilityLabel("\(toolSet.name) with \(toolsInSet.count) tools, \(isExpanded ? "expanded" : "collapsed")")
            .accessibilityHint(isExpanded ? "Tap to collapse" : "Tap to expand and see tools")

            // Tools within the set (only shown when expanded)
            if isExpanded {
                VStack(alignment: .leading, spacing: 0) {
                    // Feature #148: Select All button / Feature #150: Deselect All button
                    if !toolsInSet.isEmpty {
                        HStack(spacing: 8) {
                            // Show "Select All" if not all tools are selected
                            if selectedCount < toolsInSet.count {
                                Button(action: onSelectAll) {
                                    HStack(spacing: 6) {
                                        Image(systemName: "checkmark.circle")
                                            .font(.caption)
                                        Text("Select All")
                                            .font(.caption)
                                            .fontWeight(.medium)
                                    }
                                    .foregroundColor(Color(red: 0.145, green: 0.388, blue: 0.922))
                                    .padding(.horizontal, 10)
                                    .padding(.vertical, 6)
                                    .background(Color(red: 0.145, green: 0.388, blue: 0.922).opacity(0.1))
                                    .cornerRadius(6)
                                }
                                .buttonStyle(.plain)
                                .accessibilityIdentifier("selectAllToolSet_\(toolSet.name)")
                                .accessibilityLabel("Select all \(toolsInSet.count) tools in \(toolSet.name)")
                                .accessibilityHint("Selects all tools in this Tool Set at once")
                            }

                            // Feature #150: Show "Deselect All" if any tools are selected
                            if selectedCount > 0 {
                                Button(action: onDeselectAll) {
                                    HStack(spacing: 6) {
                                        Image(systemName: "xmark.circle")
                                            .font(.caption)
                                        Text("Deselect All")
                                            .font(.caption)
                                            .fontWeight(.medium)
                                    }
                                    .foregroundColor(Color(red: 0.933, green: 0.267, blue: 0.267)) // Red color for deselect
                                    .padding(.horizontal, 10)
                                    .padding(.vertical, 6)
                                    .background(Color(red: 0.933, green: 0.267, blue: 0.267).opacity(0.1))
                                    .cornerRadius(6)
                                }
                                .buttonStyle(.plain)
                                .accessibilityIdentifier("deselectAllToolSet_\(toolSet.name)")
                                .accessibilityLabel("Deselect all \(selectedCount) tools in \(toolSet.name)")
                                .accessibilityHint("Removes all tool selections from this Tool Set at once")
                            }
                        }
                        .padding(.leading, 6)
                        .padding(.bottom, 8)
                    }

                    ForEach(toolsInSet, id: \.id) { tool in
                        ToolInSetSelectionRow(
                            tool: tool,
                            isSelected: localSelection.contains(tool.id)
                        )
                        .contentShape(Rectangle())
                        .onTapGesture {
                            onToggleToolSelection(tool.id)
                        }

                        // Divider between tools (except after last)
                        if tool != toolsInSet.last {
                            Divider()
                                .padding(.leading, 44)
                        }
                    }
                }
                .padding(.leading, 28) // Indent tools under the Tool Set
                .padding(.vertical, 4)
                .background(Color(UIColor.secondarySystemBackground).opacity(0.5))
                .cornerRadius(8)
                .accessibilityIdentifier("toolSetExpandedContent_\(toolSet.name)")
            }
        }
    }
}

/// A row for a tool that's displayed inside an expanded Tool Set.
/// Similar to ToolSelectionRow but with visual indication it's inside a group.
struct ToolInSetSelectionRow: View {
    @Bindable var tool: Tool
    let isSelected: Bool

    var body: some View {
        HStack(spacing: 10) {
            // Indent marker
            Rectangle()
                .fill(Color(red: 0.145, green: 0.388, blue: 0.922).opacity(0.3))
                .frame(width: 3)
                .cornerRadius(1.5)

            VStack(alignment: .leading, spacing: 2) {
                Text(tool.name)
                    .font(.subheadline)
                    .fontWeight(.medium)

                HStack(spacing: 8) {
                    // Ownership badge
                    Text(ownershipLabel)
                        .font(.caption2)
                        .fontWeight(.medium)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(ownershipColor.opacity(0.15))
                        .foregroundColor(ownershipColor)
                        .clipShape(Capsule())

                    if let notes = tool.notes, !notes.isEmpty {
                        Text(notes)
                            .font(.caption)
                            .foregroundColor(.secondary)
                            .lineLimit(1)
                    }
                }
            }

            Spacer()

            if isSelected {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundColor(Color(red: 0.145, green: 0.388, blue: 0.922))
                    .font(.title3)
            } else {
                Image(systemName: "circle")
                    .foregroundColor(.secondary)
                    .font(.title3)
            }
        }
        .padding(.vertical, 6)
        .accessibilityIdentifier("toolInSet_\(tool.name)")
        .accessibilityLabel("\(tool.name), \(ownershipLabel), \(isSelected ? "selected" : "not selected")")
        .accessibilityHint("Tap to \(isSelected ? "deselect" : "select") this tool")
    }

    private var ownershipLabel: String {
        switch tool.ownershipType {
        case "personal": return "Personal"
        case "shop": return "Shop"
        case "borrowed": return "Borrowed"
        case "imported": return "Imported"
        default: return "Personal"
        }
    }

    private var ownershipColor: Color {
        switch tool.ownershipType {
        case "personal": return Color(red: 0.145, green: 0.388, blue: 0.922)
        case "shop": return Color(red: 0.392, green: 0.455, blue: 0.545)
        case "borrowed": return Color(red: 0.976, green: 0.451, blue: 0.086)
        case "imported": return Color(red: 0.608, green: 0.318, blue: 0.878)
        default: return .blue
        }
    }
}

// MARK: - Tool Kit Collapsible Row (Feature #141, #168)

/// A row representing a Tool Kit that can be expanded/collapsed to show/hide tools within it.
/// When collapsed, shows the Tool Kit name with a chevron indicator.
/// When expanded, shows the Tool Kit header and all tools within it indented below.
/// Feature #149: When expanded, shows a "Select All" button to select all tools in the kit.
/// Feature #151: When expanded and tools are selected, shows a "Deselect All" button.
/// Feature #164: Filters tools based on search text when active.
/// Feature #168: Auto-expands and shows all tools when Tool Kit name matches search.
struct ToolKitCollapsibleRow: View {
    @Bindable var toolKit: ToolKit
    let isExpanded: Bool
    @Binding var localSelection: Set<UUID>
    let searchText: String  // Feature #164: Search text for filtering
    let onToggleExpand: () -> Void
    let onForceExpand: () -> Void  // Force-expand without toggling (used by checkbox)
    let onToggleToolSelection: (UUID) -> Void
    let onSelectAll: () -> Void  // Feature #149: Select All callback
    let onDeselectAll: () -> Void  // Feature #151: Deselect All callback

    /// Tri-state checkbox icon for kit selection
    private var checkboxIcon: String {
        if selectedCount == 0 {
            return "circle"
        } else if selectedCount == toolsInKit.count {
            return "checkmark.circle.fill"
        } else {
            return "minus.circle.fill"
        }
    }

    /// Tri-state checkbox color
    private var checkboxColor: Color {
        if selectedCount == 0 {
            return .secondary
        } else {
            return Color(red: 0.133, green: 0.545, blue: 0.133) // Forest green
        }
    }

    /// Feature #164: Checks if a tool matches the search text
    private func toolMatchesSearch(_ tool: Tool) -> Bool {
        let trimmedSearch = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedSearch.isEmpty else { return true }

        let lowercasedSearch = trimmedSearch.lowercased()

        // Check main name
        if tool.name.lowercased().contains(lowercasedSearch) {
            return true
        }

        // Also check aliases
        if let aliases = tool.aliases {
            for alias in aliases {
                if alias.lowercased().contains(lowercasedSearch) {
                    return true
                }
            }
        }

        return false
    }

    /// Feature #168: Checks if the Tool Kit's name matches the current search text
    private var toolKitNameMatchesSearch: Bool {
        let trimmedSearch = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedSearch.isEmpty else { return false }
        let lowercasedSearch = trimmedSearch.lowercased()
        return toolKit.name.lowercased().contains(lowercasedSearch)
    }

    /// Tools within this Tool Kit, sorted by size
    /// Feature #168: Show ALL tools when Tool Kit name matches search
    /// Feature #169: Show ALL tools when ANY tool in the kit matches search
    /// (The kit appears because filteredToolKits includes it - so show all tools)
    private var toolsInKit: [Tool] {
        guard let tools = toolKit.tools else { return [] }
        let allToolsInKit = Array(tools).sortedBySize()
        // Feature #169: Always show ALL tools in an expanded Tool Kit
        // The Tool Kit only appears in the filtered list if:
        // - The Tool Kit name matches the search (Feature #168), OR
        // - At least one tool within matches the search
        // In both cases, show all tools so user can see the complete kit
        return allToolsInKit
    }

    /// Count of selected tools within this Tool Kit (filtered)
    private var selectedCount: Int {
        toolsInKit.filter { localSelection.contains($0.id) }.count
    }

    /// Kit ownership type for display
    private var ownershipLabel: String {
        switch toolKit.ownershipType {
        case "personal": return "Personal"
        case "shop": return "Shop"
        default: return "Personal"
        }
    }

    /// Kit ownership color
    private var ownershipColor: Color {
        switch toolKit.ownershipType {
        case "personal": return Color(red: 0.145, green: 0.388, blue: 0.922)
        case "shop": return Color(red: 0.392, green: 0.455, blue: 0.545)
        default: return Color(red: 0.145, green: 0.388, blue: 0.922)
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Tool Kit Header (always visible) — split into checkbox + row tap targets
            HStack(spacing: 0) {
                // Tri-state checkbox — tappable independently
                Button(action: {
                    if selectedCount == toolsInKit.count {
                        // All selected → deselect all
                        onDeselectAll()
                    } else {
                        // None or partial → select all + auto-expand
                        onSelectAll()
                        if !isExpanded {
                            onForceExpand()
                        }
                    }
                }) {
                    Image(systemName: checkboxIcon)
                        .font(.title3)
                        .foregroundColor(checkboxColor)
                        .frame(width: 36, height: 36)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("toolKitCheckbox_\(toolKit.name)")
                .accessibilityLabel(selectedCount == 0 ? "Select all tools in \(toolKit.name)" : selectedCount == toolsInKit.count ? "Deselect all tools in \(toolKit.name)" : "\(selectedCount) of \(toolsInKit.count) selected in \(toolKit.name)")

                // Row content — tapping expands/collapses
                Button(action: onToggleExpand) {
                    HStack(spacing: 12) {
                        // Chevron indicator (rotates when expanded)
                        Image(systemName: "chevron.right")
                            .font(.caption)
                            .fontWeight(.semibold)
                            .foregroundColor(Color(red: 0.133, green: 0.545, blue: 0.133)) // Forest green for kits
                            .rotationEffect(.degrees(isExpanded ? 90 : 0))
                            .animation(.easeInOut(duration: 0.2), value: isExpanded)
                            .accessibilityHidden(true)

                        // Tool Kit icon (bag icon to distinguish from Tool Sets)
                        Image(systemName: "bag.fill")
                            .font(.body)
                            .foregroundColor(Color(red: 0.133, green: 0.545, blue: 0.133)) // Forest green

                        VStack(alignment: .leading, spacing: 2) {
                            Text(toolKit.name)
                                .font(.body)
                                .fontWeight(.medium)
                                .foregroundColor(.primary)

                            HStack(spacing: 4) {
                                Text("\(toolsInKit.count) tool\(toolsInKit.count == 1 ? "" : "s")")
                                    .font(.caption)
                                    .foregroundColor(.secondary)

                                // Feature #145: Selection count badge uses industrial blue accent color
                                if selectedCount > 0 {
                                    Text("• \(selectedCount) selected")
                                        .font(.caption)
                                        .fontWeight(.medium)
                                        .foregroundColor(Color(red: 0.145, green: 0.388, blue: 0.922))
                                }
                            }
                        }

                        Spacer()

                        // Ownership badge
                        Text(ownershipLabel)
                            .font(.caption2)
                            .fontWeight(.medium)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(ownershipColor.opacity(0.15))
                            .foregroundColor(ownershipColor)
                            .clipShape(Capsule())
                    }
                    .padding(.vertical, 8)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
            .accessibilityIdentifier("toolKitRow_\(toolKit.name)")
            .accessibilityLabel("\(toolKit.name) with \(toolsInKit.count) tools, \(isExpanded ? "expanded" : "collapsed")")
            .accessibilityHint(isExpanded ? "Tap to collapse" : "Tap to expand and see tools")

            // Tools within the kit (only shown when expanded)
            if isExpanded {
                VStack(alignment: .leading, spacing: 0) {
                    // Feature #149: Select All button / Feature #151: Deselect All button
                    if !toolsInKit.isEmpty {
                        HStack(spacing: 8) {
                            // Show "Select All" if not all tools are selected
                            if selectedCount < toolsInKit.count {
                                Button(action: onSelectAll) {
                                    HStack(spacing: 6) {
                                        Image(systemName: "checkmark.circle")
                                            .font(.caption)
                                        Text("Select All")
                                            .font(.caption)
                                            .fontWeight(.medium)
                                    }
                                    .foregroundColor(Color(red: 0.133, green: 0.545, blue: 0.133)) // Forest green for kits
                                    .padding(.horizontal, 10)
                                    .padding(.vertical, 6)
                                    .background(Color(red: 0.133, green: 0.545, blue: 0.133).opacity(0.1))
                                    .cornerRadius(6)
                                }
                                .buttonStyle(.plain)
                                .accessibilityIdentifier("selectAllToolKit_\(toolKit.name)")
                                .accessibilityLabel("Select all \(toolsInKit.count) tools in \(toolKit.name)")
                                .accessibilityHint("Selects all tools in this Tool Kit at once")
                            }

                            // Feature #151: Show "Deselect All" if any tools are selected
                            if selectedCount > 0 {
                                Button(action: onDeselectAll) {
                                    HStack(spacing: 6) {
                                        Image(systemName: "xmark.circle")
                                            .font(.caption)
                                        Text("Deselect All")
                                            .font(.caption)
                                            .fontWeight(.medium)
                                    }
                                    .foregroundColor(Color(red: 0.933, green: 0.267, blue: 0.267)) // Red color for deselect
                                    .padding(.horizontal, 10)
                                    .padding(.vertical, 6)
                                    .background(Color(red: 0.933, green: 0.267, blue: 0.267).opacity(0.1))
                                    .cornerRadius(6)
                                }
                                .buttonStyle(.plain)
                                .accessibilityIdentifier("deselectAllToolKit_\(toolKit.name)")
                                .accessibilityLabel("Deselect all \(selectedCount) tools in \(toolKit.name)")
                                .accessibilityHint("Removes all tool selections from this Tool Kit at once")
                            }
                        }
                        .padding(.leading, 6)
                        .padding(.bottom, 8)
                    }

                    ForEach(toolsInKit, id: \.id) { tool in
                        ToolInKitSelectionRow(
                            tool: tool,
                            isSelected: localSelection.contains(tool.id)
                        )
                        .contentShape(Rectangle())
                        .onTapGesture {
                            onToggleToolSelection(tool.id)
                        }

                        // Divider between tools (except after last)
                        if tool != toolsInKit.last {
                            Divider()
                                .padding(.leading, 44)
                        }
                    }
                }
                .padding(.leading, 28) // Indent tools under the Tool Kit
                .padding(.vertical, 4)
                .background(Color(UIColor.secondarySystemBackground).opacity(0.5))
                .cornerRadius(8)
                .accessibilityIdentifier("toolKitExpandedContent_\(toolKit.name)")
            }
        }
    }
}

/// A row for a tool that's displayed inside an expanded Tool Kit.
/// Similar to ToolInSetSelectionRow but with visual indication it's inside a kit (green accent).
struct ToolInKitSelectionRow: View {
    @Bindable var tool: Tool
    let isSelected: Bool

    var body: some View {
        HStack(spacing: 10) {
            // Indent marker (green for kits)
            Rectangle()
                .fill(Color(red: 0.133, green: 0.545, blue: 0.133).opacity(0.3)) // Forest green
                .frame(width: 3)
                .cornerRadius(1.5)

            VStack(alignment: .leading, spacing: 2) {
                Text(tool.name)
                    .font(.subheadline)
                    .fontWeight(.medium)

                HStack(spacing: 8) {
                    // Ownership badge
                    Text(ownershipLabel)
                        .font(.caption2)
                        .fontWeight(.medium)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(ownershipColor.opacity(0.15))
                        .foregroundColor(ownershipColor)
                        .clipShape(Capsule())

                    if let notes = tool.notes, !notes.isEmpty {
                        Text(notes)
                            .font(.caption)
                            .foregroundColor(.secondary)
                            .lineLimit(1)
                    }
                }
            }

            Spacer()

            if isSelected {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundColor(Color(red: 0.133, green: 0.545, blue: 0.133)) // Forest green
                    .font(.title3)
            } else {
                Image(systemName: "circle")
                    .foregroundColor(.secondary)
                    .font(.title3)
            }
        }
        .padding(.vertical, 6)
        .accessibilityIdentifier("toolInKit_\(tool.name)")
        .accessibilityLabel("\(tool.name), \(ownershipLabel), \(isSelected ? "selected" : "not selected")")
        .accessibilityHint("Tap to \(isSelected ? "deselect" : "select") this tool")
    }

    private var ownershipLabel: String {
        switch tool.ownershipType {
        case "personal": return "Personal"
        case "shop": return "Shop"
        case "borrowed": return "Borrowed"
        case "imported": return "Imported"
        default: return "Personal"
        }
    }

    private var ownershipColor: Color {
        switch tool.ownershipType {
        case "personal": return Color(red: 0.145, green: 0.388, blue: 0.922)
        case "shop": return Color(red: 0.392, green: 0.455, blue: 0.545)
        case "borrowed": return Color(red: 0.976, green: 0.451, blue: 0.086)
        case "imported": return Color(red: 0.608, green: 0.318, blue: 0.878)
        default: return .blue
        }
    }
}

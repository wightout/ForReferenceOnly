import SwiftUI
import Foundation
import SwiftData
import UniformTypeIdentifiers

/// Garage hub view — shows tools, consumables, and chemicals.
/// All three sections have full CRUD support.
struct GarageView: View {
    @Environment(\.modelContext) private var viewContext

    /// Fetch all tools sorted by name (only those marked as in Garage)
    /// Feature #96: Filters out on-the-fly items that user declined to add
    @Query(filter: #Predicate<FROTool> { $0.isInGarage == true }, sort: \FROTool.name, order: .forward)
    private var tools: [FROTool]

    /// Fetch all consumables sorted by name (only those marked as in Garage)
    /// Feature #96: Filters out on-the-fly items that user declined to add
    @Query(filter: #Predicate<FROConsumable> { $0.isInGarage == true }, sort: \FROConsumable.name, order: .forward)
    private var consumables: [FROConsumable]

    /// Fetch all chemicals sorted by name (only those marked as in Garage)
    /// Feature #96: Filters out on-the-fly items that user declined to add
    @Query(filter: #Predicate<FROChemical> { $0.isInGarage == true }, sort: \FROChemical.name, order: .forward)
    private var chemicals: [FROChemical]

    /// Fetch all tool groups sorted by sortOrder
    @Query(sort: [SortDescriptor(\FROToolGroup.sortOrder, order: .forward), SortDescriptor(\FROToolGroup.name, order: .forward)])
    private var allToolGroups: [FROToolGroup]

    /// Fetch all tool kits sorted by name
    @Query(sort: \FROToolKit.name, order: .forward)
    private var toolKits: [FROToolKit]

    @State private var showingAddTool = false
    @State private var showingAddToolKit = false
    @State private var showingAddConsumable = false
    @State private var showingAddChemical = false
    @State private var showingAddToolGroup = false
    @State private var addGroupParent: ToolGroup?
    @State private var toolToEdit: Tool?
    @State private var consumableToEdit: Consumable?
    @State private var chemicalToEdit: Chemical?
    @State private var toolGroupToEdit: ToolGroup?
    @State private var toolKitToEdit: ToolKit?  // Feature #139: Kit for editing ownership
    // bulkAddGroup removed — inline tool creation in AddToolGroupView/EditToolGroupView replaces BulkAddToolsToGroupView
    @State private var selectedSegment: Int

    // Delete confirmation and feedback state
    @State private var toolToDelete: Tool?
    @State private var showingDeleteToolConfirmation = false
    @State private var showingDeleteToolSuccess = false
    @State private var deletedToolName = ""
    @State private var showingConvertedToBorrowed = false
    @State private var convertedToolName = ""

    // Task #10: Tool Set delete confirmation state
    @State private var toolGroupToDelete: ToolGroup?
    @State private var showingDeleteGroupConfirmation = false
    // Task #10: Tool Kit delete confirmation state
    @State private var toolKitToDelete: ToolKit?
    @State private var showingDeleteKitConfirmation = false
    // Task #9: Expanded groups state
    @State private var expandedGroups: Set<UUID> = []

    // Multi-select export state
    @State private var isSelectMode = false
    @State private var selectedTools: Set<UUID> = []
    @State private var selectedToolSets: Set<UUID> = []
    @State private var selectedToolKits: Set<UUID> = []
    @State private var showingExportShareSheet = false
    @State private var exportFileURL: URL?

    // Tool import state
    @State private var showingToolImporter = false
    @State private var showingToolImportReview = false
    @State private var importParseResult: ToolImportService.ImportParseResult?
    @State private var showImportError = false
    @State private var importErrorMessage = ""
    @State private var showImportSuccess = false
    @State private var importedToolCount = 0

    private let segments = ["Tools", "Consumables", "Chemicals"]

    init() {
        // Support START_SEGMENT via command-line arg or env var for testing (0=Tools, 1=Consumables, 2=Chemicals)
        let args = ProcessInfo.processInfo.arguments
        var segFromArgs: Int?
        if let segArgIndex = args.firstIndex(of: "-startSegment"), segArgIndex + 1 < args.count,
           let seg = Int(args[segArgIndex + 1]), (0...2).contains(seg) {
            segFromArgs = seg
        }

        if let seg = segFromArgs {
            _selectedSegment = State(initialValue: seg)
        } else if let segStr = ProcessInfo.processInfo.environment["START_SEGMENT"],
           let seg = Int(segStr), (0...2).contains(seg) {
            _selectedSegment = State(initialValue: seg)
        } else {
            _selectedSegment = State(initialValue: 0)
        }
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                // FRO Banner
                HStack {
                    Spacer()
                    Text("FOR REFERENCE ONLY")
                        .font(.caption)
                        .fontWeight(.bold)
                        .foregroundColor(Color(red: 0.976, green: 0.451, blue: 0.086))
                        .padding(.horizontal, 12)
                        .padding(.vertical, 4)
                        .background(Color(red: 0.976, green: 0.451, blue: 0.086).opacity(0.2))
                        .cornerRadius(4)
                        .accessibilityLabel("For Reference Only disclaimer banner")
                    Spacer()
                }
                .padding(.top, 8)

                // Segmented control for sections
                Picker("Section", selection: $selectedSegment) {
                    ForEach(0..<segments.count, id: \.self) { index in
                        Text(segments[index]).tag(index)
                    }
                }
                .pickerStyle(.segmented)
                .padding(.horizontal)
                .padding(.top, 8)
                .accessibilityLabel("Garage section selector")
                .accessibilityHint("Select between Tools, Consumables, and Chemicals")

                // Content based on selected segment
                switch selectedSegment {
                case 0:
                    toolsSection
                case 1:
                    consumablesSection
                case 2:
                    chemicalsSection
                default:
                    EmptyView()
                }
            }
            .alert("Delete Tool Set?", isPresented: $showingDeleteGroupConfirmation) {
                Button("Cancel", role: .cancel) { toolGroupToDelete = nil }
                Button("Delete", role: .destructive) { if let group = toolGroupToDelete { performToolGroupDeletion(group) } }
            } message: {
                Text("Are you sure you want to delete '\(toolGroupToDelete?.name ?? "this set")'? Tools in this set will NOT be deleted \u{2014} they will remain in your Garage.")
            }
            .alert("Delete Tool Kit?", isPresented: $showingDeleteKitConfirmation) {
                Button("Cancel", role: .cancel) { toolKitToDelete = nil }
                Button("Delete", role: .destructive) { if let kit = toolKitToDelete { performToolKitDeletion(kit) } }
            } message: {
                Text("Are you sure you want to delete '\(toolKitToDelete?.name ?? "this kit")'? Tools in this kit will NOT be deleted \u{2014} they will remain in your Garage.")
            }
            .navigationTitle("Garage")
            .toolbar {
                // Leading toolbar: Select mode toggle (Tools tab only)
                ToolbarItem(placement: .navigationBarLeading) {
                    if selectedSegment == 0 && !tools.isEmpty {
                        Button(isSelectMode ? "Done" : "Select") {
                            withAnimation {
                                isSelectMode.toggle()
                                if !isSelectMode {
                                    selectedTools.removeAll()
                                    selectedToolSets.removeAll()
                                    selectedToolKits.removeAll()
                                }
                            }
                        }
                        .accessibilityIdentifier("selectModeButton")
                    }
                }

                ToolbarItem(placement: .navigationBarTrailing) {
                    if selectedSegment == 0 {
                        if isSelectMode {
                            // In select mode: show export button
                            Button {
                                exportSelectedTools()
                            } label: {
                                Label("Export", systemImage: "square.and.arrow.up")
                            }
                            .disabled(selectedTools.isEmpty && selectedToolSets.isEmpty && selectedToolKits.isEmpty)
                            .accessibilityLabel("Export selected tools")
                        } else {
                            Menu {
                                Button(action: { showingAddTool = true }) {
                                    Label("Add Tool", systemImage: "wrench")
                                }
                                Button(action: {
                                    addGroupParent = nil
                                    showingAddToolGroup = true
                                }) {
                                    Label("Add Tool Set", systemImage: "folder.badge.plus")
                                }
                                Button(action: { showingAddToolKit = true }) {
                                    Label("Add Tool Kit", systemImage: "bag.badge.plus")
                                }

                                Divider()

                                Button(action: { showingToolImporter = true }) {
                                    Label("Import Tools", systemImage: "square.and.arrow.down")
                                }
                            } label: {
                                Image(systemName: "plus")
                                    .font(.title3)
                            }
                            .accessibilityLabel("Add Tool, Set, Kit, or Import")
                        }
                    } else if selectedSegment == 1 {
                        Button(action: { showingAddConsumable = true }) {
                            Image(systemName: "plus")
                                .font(.title3)
                        }
                        .accessibilityLabel("Add Consumable")
                    } else if selectedSegment == 2 {
                        Button(action: { showingAddChemical = true }) {
                            Image(systemName: "plus")
                                .font(.title3)
                        }
                        .accessibilityLabel("Add Chemical")
                    }
                }
            }
            .sheet(isPresented: $showingAddTool) {
                AddToolView()
                    .modelContainer(for: [FROTool.self, FROJob.self, FROToolGroup.self, FROToolKit.self, FROConsumable.self, FROChemical.self, FROPart.self], inMemory: true)
            }
            .sheet(isPresented: $showingAddConsumable) {
                AddConsumableView()
                    .modelContainer(for: [FROTool.self, FROJob.self, FROToolGroup.self, FROToolKit.self, FROConsumable.self, FROChemical.self, FROPart.self], inMemory: true)
            }
            .sheet(isPresented: $showingAddChemical) {
                AddChemicalView()
                    .modelContainer(for: [FROTool.self, FROJob.self, FROToolGroup.self, FROToolKit.self, FROConsumable.self, FROChemical.self, FROPart.self], inMemory: true)
            }
            .sheet(item: $toolToEdit) { tool in
                EditToolView(tool: tool)
                    .modelContainer(for: [FROTool.self, FROJob.self, FROToolGroup.self, FROToolKit.self, FROConsumable.self, FROChemical.self, FROPart.self], inMemory: true)
            }
            .sheet(item: $consumableToEdit) { consumable in
                EditConsumableView(consumable: consumable)
                    .modelContainer(for: [FROTool.self, FROJob.self, FROToolGroup.self, FROToolKit.self, FROConsumable.self, FROChemical.self, FROPart.self], inMemory: true)
            }
            .sheet(item: $chemicalToEdit) { chemical in
                EditChemicalView(chemical: chemical)
                    .modelContainer(for: [FROTool.self, FROJob.self, FROToolGroup.self, FROToolKit.self, FROConsumable.self, FROChemical.self, FROPart.self], inMemory: true)
            }
            .sheet(isPresented: $showingAddToolGroup) {
                AddToolGroupView(parentGroup: addGroupParent)
                    .modelContainer(for: [FROTool.self, FROJob.self, FROToolGroup.self, FROToolKit.self, FROConsumable.self, FROChemical.self, FROPart.self], inMemory: true)
            }
            .sheet(isPresented: $showingAddToolKit) {
                AddToolKitView()
                    .modelContainer(for: [FROTool.self, FROJob.self, FROToolGroup.self, FROToolKit.self, FROConsumable.self, FROChemical.self, FROPart.self], inMemory: true)
            }
            .sheet(item: $toolGroupToEdit) { group in
                EditToolGroupView(toolGroup: group)
                    .modelContainer(for: [FROTool.self, FROJob.self, FROToolGroup.self, FROToolKit.self, FROConsumable.self, FROChemical.self, FROPart.self], inMemory: true)
            }
            // Feature #139: Edit tool kit sheet
            .sheet(item: $toolKitToEdit) { kit in
                EditToolKitView(toolKit: kit)
                    .modelContainer(for: [FROTool.self, FROJob.self, FROToolGroup.self, FROToolKit.self, FROConsumable.self, FROChemical.self, FROPart.self], inMemory: true)
            }
            // Bulk add tools sheet removed — inline tool creation in Add/Edit Tool Set replaces it
            .alert("Delete Tool?", isPresented: $showingDeleteToolConfirmation) {
                Button("Cancel", role: .cancel) {
                    toolToDelete = nil
                }
                Button("Delete", role: .destructive) {
                    if let tool = toolToDelete {
                        performToolDeletion(tool)
                    }
                }
            } message: {
                Text("Are you sure you want to delete '\(toolToDelete?.name ?? "this tool")'? If this tool is used in any jobs, it will be converted to a borrowed tool instead of being deleted.")
            }
            .alert("Tool Deleted", isPresented: $showingDeleteToolSuccess) {
                Button("OK") { }
            } message: {
                Text("'\(deletedToolName)' has been removed from your Garage.")
            }
            .alert("Tool Converted", isPresented: $showingConvertedToBorrowed) {
                Button("OK") { }
            } message: {
                Text("'\(convertedToolName)' is referenced in job records and has been converted to a borrowed tool instead of being deleted.")
            }
            // Export share sheet
            .sheet(isPresented: $showingExportShareSheet) {
                if let fileURL = exportFileURL {
                    ShareSheet(activityItems: [fileURL])
                }
            }
            // Import file picker (.frotool files)
            .fileImporter(
                isPresented: $showingToolImporter,
                allowedContentTypes: [UTType(exportedAs: "com.forreference.frotool"), .data],
                allowsMultipleSelection: false
            ) { result in
                switch result {
                case .success(let urls):
                    guard let url = urls.first else { return }
                    do {
                        importParseResult = try ToolImportService.shared.parseFrotoolBundle(at: url, context: viewContext)
                        showingToolImportReview = true
                    } catch {
                        importErrorMessage = error.localizedDescription
                        showImportError = true
                    }
                case .failure(let error):
                    importErrorMessage = error.localizedDescription
                    showImportError = true
                }
            }
            // Import review sheet
            .sheet(isPresented: $showingToolImportReview) {
                if let parseResult = importParseResult {
                    ToolImportReviewView(
                        parseResult: parseResult,
                        onImportComplete: { count in
                            importedToolCount = count
                            showImportSuccess = true
                        }
                    )
                    .modelContainer(for: [FROTool.self, FROJob.self, FROToolGroup.self, FROToolKit.self, FROConsumable.self, FROChemical.self, FROPart.self], inMemory: true)
                }
            }
            .alert("Import Error", isPresented: $showImportError) {
                Button("OK", role: .cancel) { }
            } message: {
                Text(importErrorMessage)
            }
            .alert("Tools Imported!", isPresented: $showImportSuccess) {
                Button("OK") { }
            } message: {
                Text("\(importedToolCount) tool\(importedToolCount == 1 ? "" : "s") imported successfully.")
            }
            // Bottom action bar for select mode
            .safeAreaInset(edge: .bottom) {
                if isSelectMode && selectedSegment == 0 {
                    selectModeActionBar
                }
            }
        }
    }

    // MARK: - Select Mode Action Bar

    /// Total count of selected items (tools + sets + kits) for the action bar
    private var totalSelectedCount: Int {
        selectedTools.count + selectedToolSets.count + selectedToolKits.count
    }

    /// Whether all selectable items are selected
    private var allItemsSelected: Bool {
        selectedTools.count == tools.count &&
        selectedToolSets.count == topLevelGroups.count &&
        selectedToolKits.count == toolKits.count
    }

    private var selectModeActionBar: some View {
        HStack {
            // Select all / deselect all
            Button {
                if allItemsSelected {
                    selectedTools.removeAll()
                    selectedToolSets.removeAll()
                    selectedToolKits.removeAll()
                } else {
                    selectedTools = Set(tools.map { $0.id })
                    selectedToolSets = Set(topLevelGroups.map { $0.id })
                    selectedToolKits = Set(toolKits.map { $0.id })
                }
            } label: {
                Text(allItemsSelected ? "Deselect All" : "Select All")
                    .font(.subheadline)
                    .fontWeight(.medium)
            }
            .accessibilityIdentifier("selectAllButton")

            Spacer()

            Text("\(totalSelectedCount) selected")
                .font(.subheadline)
                .foregroundColor(.secondary)

            Spacer()

            // Export button
            Button {
                exportSelectedTools()
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "square.and.arrow.up")
                    Text("Export")
                        .fontWeight(.semibold)
                }
                .font(.subheadline)
                .foregroundColor(.white)
                .padding(.horizontal, 16)
                .padding(.vertical, 8)
                .background(totalSelectedCount == 0 ? Color.gray : Color(red: 0.145, green: 0.388, blue: 0.922))
                .cornerRadius(8)
            }
            .disabled(totalSelectedCount == 0)
            .accessibilityIdentifier("exportButton")
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(.ultraThinMaterial)
    }

    // MARK: - Tool Row Helper (Select Mode)

    /// Returns either a selectable row (in select mode) or a NavigationLink row (in normal mode).
    /// Used for individual tool rows in personal, borrowed, and shop sections.
    @ViewBuilder
    private func toolRow(for tool: Tool, rowView: AnyView, prefix: String) -> some View {
        if isSelectMode {
            Button {
                if selectedTools.contains(tool.id) {
                    selectedTools.remove(tool.id)
                } else {
                    selectedTools.insert(tool.id)
                }
            } label: {
                HStack(spacing: 12) {
                    Image(systemName: selectedTools.contains(tool.id) ? "checkmark.circle.fill" : "circle")
                        .foregroundColor(selectedTools.contains(tool.id) ? Color(red: 0.145, green: 0.388, blue: 0.922) : .secondary)
                        .font(.title3)
                    rowView
                }
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("\(prefix)_\(tool.id.uuidString)")
        } else {
            NavigationLink(destination: ToolDetailView(tool: tool).modelContainer(for: [FROTool.self, FROJob.self, FROToolGroup.self, FROToolKit.self, FROConsumable.self, FROChemical.self, FROPart.self], inMemory: true)) {
                rowView
            }
            .accessibilityIdentifier("\(prefix)_\(tool.id.uuidString)")
            .swipeActions(edge: .leading) {
                Button {
                    toolToEdit = tool
                } label: {
                    Label("Edit", systemImage: "pencil")
                }
                .tint(.blue)
            }
            .contextMenu {
                Button(action: { toolToEdit = tool }) { Label("Edit Tool", systemImage: "pencil") }
                Button(action: { exportSingleTool(tool) }) { Label("Export", systemImage: "square.and.arrow.up") }
                Divider()
                Button(role: .destructive) { toolToDelete = tool; showingDeleteToolConfirmation = true } label: { Label("Delete", systemImage: "trash") }
            }
        }
    }

    // MARK: - Tool Set Row Helper (Select Mode)

    /// Returns either a selectable row (in select mode) or the default disclosure row (in normal mode).
    /// Used for ToolGroupRowView rows in personal and shop sections.
    @ViewBuilder
    private func toolSetRow(for group: ToolGroup, normalContent: @escaping () -> some View) -> some View {
        if isSelectMode {
            // Select mode: show checkbox + expandable set with child tool selection
            ToolGroupRowView(
                group: group,
                viewContext: viewContext,
                onEditTool: { _ in },
                onEditGroup: { _ in },
                onAddSubGroup: { _ in },
                onAddToolToGroup: { _ in },
                isSelectMode: true,
                isSetSelected: selectedToolSets.contains(group.id),
                selectedTools: $selectedTools,
                onToggleSetSelection: {
                    if selectedToolSets.contains(group.id) {
                        selectedToolSets.remove(group.id)
                    } else {
                        selectedToolSets.insert(group.id)
                    }
                }
            )
            .accessibilityIdentifier("selectToolSet_\(group.id.uuidString)")
        } else {
            normalContent()
        }
    }


    // MARK: - Tool Kit Row Helper (Select Mode)

    /// Returns either a selectable row (in select mode) or a NavigationLink (in normal mode).
    /// Used for ToolKit rows in personal and shop sections.
    @ViewBuilder
    private func toolKitRow(for kit: ToolKit, normalContent: @escaping () -> some View) -> some View {
        if isSelectMode {
            // Select mode: show checkbox + expandable kit with child tool selection
            SelectModeToolKitRow(
                kit: kit,
                viewContext: viewContext,
                isKitSelected: selectedToolKits.contains(kit.id),
                selectedTools: $selectedTools,
                onToggleKitSelection: {
                    if selectedToolKits.contains(kit.id) {
                        selectedToolKits.remove(kit.id)
                    } else {
                        selectedToolKits.insert(kit.id)
                    }
                }
            )
            .accessibilityIdentifier("selectToolKit_\(kit.id.uuidString)")
        } else {
            normalContent()
        }
    }


    // MARK: - Export

    private func exportSelectedTools() {
        var allToolsToExport: Set<UUID> = selectedTools

        // Resolve selected Tool Sets → their tools (recursively including sub-sets)
        for setID in selectedToolSets {
            if let group = fetchByPersistentID(ToolGroup.self, id: setID, context: viewContext) {
                collectTools(from: group, into: &allToolsToExport)
            }
        }

        // Resolve selected Tool Kits → their tools
        for kitID in selectedToolKits {
            if let kit = fetchByPersistentID(ToolKit.self, id: kitID, context: viewContext) {
                if let kitTools = kit.tools {
                    for tool in kitTools {
                        allToolsToExport.insert(tool.id)
                    }
                }
            }
        }

        let toolObjects = allToolsToExport.compactMap { fetchByPersistentID(Tool.self, id: $0, context: viewContext) }
        guard !toolObjects.isEmpty else { return }

        if let url = ToolExportService.shared.exportTools(toolObjects, context: viewContext) {
            exportFileURL = url
            showingExportShareSheet = true
            // Exit select mode after successful export
            isSelectMode = false
            selectedTools.removeAll()
            selectedToolSets.removeAll()
            selectedToolKits.removeAll()
        }
    }

    /// Recursively collects all tool objectIDs from a ToolGroup and its sub-groups.
    private func collectTools(from group: ToolGroup, into toolIDs: inout Set<UUID>) {
        // Add direct tools
        if let groupTools = group.tools {
            for tool in groupTools {
                toolIDs.insert(tool.id)
            }
        }
        // Recurse into child groups
        if let children = group.childGroups {
            for child in children {
                collectTools(from: child, into: &toolIDs)
            }
        }
    }

    // MARK: - Tools Section

    /// Feature #119: Personal tools filtered from the full tools list, sorted by size then name
    private var personalTools: [Tool] {
        tools.filter { $0.ownershipType == "personal" }.sortedBySize()
    }

    /// Feature #119: Borrowed tools filtered from the full tools list, sorted by size then name
    private var borrowedTools: [Tool] {
        tools.filter { $0.ownershipType == "borrowed" }.sortedBySize()
    }

    /// Feature #119: Shop tools filtered from the full tools list, sorted by size then name
    private var shopTools: [Tool] {
        tools.filter { $0.ownershipType == "shop" }.sortedBySize()
    }

    /// Non-borrowed tools (personal + shop) that are NOT in any group, sorted by size then name
    private var ungroupedOwnedTools: [Tool] {
        tools.filter { $0.ownershipType != "borrowed" && $0.group == nil }.sortedBySize()
    }

    /// Non-borrowed tools (personal + shop), sorted by size then name
    private var ownedTools: [Tool] {
        tools.filter { $0.ownershipType != "borrowed" }.sortedBySize()
    }

    /// Top-level tool groups (no parent)
    private var topLevelGroups: [ToolGroup] {
        allToolGroups.filter { $0.parentGroup == nil }
    }

    /// Feature #135: Personal Tool Sets - top-level groups with personal ownership
    private var personalToolSets: [ToolGroup] {
        allToolGroups.filter { $0.parentGroup == nil && $0.ownershipType == "personal" }
    }

    /// Feature #135: Shop Tool Sets - top-level groups with shop ownership
    private var shopToolSets: [ToolGroup] {
        allToolGroups.filter { $0.parentGroup == nil && $0.ownershipType == "shop" }
    }

    /// Feature #136: Personal Tool Kits - kits with personal ownership
    private var personalToolKits: [ToolKit] {
        Array(toolKits).filter { $0.ownershipType == "personal" }
    }

    /// Feature #136: Shop Tool Kits - kits with shop ownership
    private var shopToolKits: [ToolKit] {
        Array(toolKits).filter { $0.ownershipType == "shop" }
    }

    private func isGroupExpanded(_ groupID: UUID?) -> Binding<Bool> {
        Binding(
            get: { groupID != nil && expandedGroups.contains(groupID!) },
            set: { newValue in
                guard let id = groupID else { return }
                if newValue { expandedGroups.insert(id) } else { expandedGroups.remove(id) }
            }
        )
    }

    @ViewBuilder
    private var toolsSection: some View {
        if tools.isEmpty && topLevelGroups.isEmpty && toolKits.isEmpty {
            VStack(spacing: 16) {
                Spacer()
                Image(systemName: "wrench.and.screwdriver")
                    .font(.system(size: 60))
                    .foregroundColor(Color(red: 0.392, green: 0.455, blue: 0.545))
                Text("No Tools Yet")
                    .font(.title2)
                    .fontWeight(.semibold)
                Text("Start building your tool inventory.\nTap + to add your first tool.")
                    .font(.body)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
                Spacer()
            }
            .padding()
        } else {
            VStack(spacing: 0) {
                frequentlyBorrowedButton

                List {
                    personalToolsListSection
                    borrowedToolsListSection
                    shopToolsListSection
                }
                .listStyle(.insetGrouped)
                .onAppear {
                    if expandedGroups.isEmpty {
                        var allIDs: Set<UUID> = []
                        for group in allToolGroups { allIDs.insert(group.id) }
                        expandedGroups = allIDs
                    }
                }
            }
        }
    }

    // MARK: - Personal Tools List Section

    // Feature #119: Personal Tools section - Personal ownership with visible header
    // Feature #135: Personal Tool Sets appear within this section
    // Feature #136: Personal Tool Kits appear within this section
    @ViewBuilder
    private var personalToolsListSection: some View {
        Section {
            if personalTools.isEmpty && personalToolSets.isEmpty && personalToolKits.isEmpty {
                Text("No personal tools yet")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                    .padding(.vertical, 4)
                    .accessibilityIdentifier("personalToolsEmptyState")
            } else {
                // Feature #135: Personal Tool Sets appear first, grouped together
                ForEach(personalToolSets, id: \.id) { group in
                    toolSetRow(for: group) {
                        ToolGroupRowView(
                            group: group,
                            viewContext: viewContext,
                            onEditTool: { tool in toolToEdit = tool },
                            onEditGroup: { group in toolGroupToEdit = group },
                            onAddSubGroup: { parent in
                                addGroupParent = parent
                                showingAddToolGroup = true
                            },
                            onAddToolToGroup: { parent in
                                showingAddTool = true
                            },
                            onDeleteGroup: { group in toolGroupToDelete = group; showingDeleteGroupConfirmation = true },
                            onExportGroup: { group in exportToolGroup(group) },
                            expandedGroups: $expandedGroups
                        )
                    }
                    .accessibilityIdentifier("personalToolSet_\(group.id.uuidString)")
                }
                .onDelete(perform: isSelectMode ? nil : deletePersonalToolSets)

                // Feature #136: Personal Tool Kits appear after Tool Sets
                // Feature #139: Swipe and context menu to edit kit
                ForEach(personalToolKits, id: \.id) { kit in
                    toolKitRow(for: kit) {
                        NavigationLink(destination: ToolKitDetailView(toolKit: kit).modelContainer(for: [FROTool.self, FROJob.self, FROToolGroup.self, FROToolKit.self, FROConsumable.self, FROChemical.self, FROPart.self], inMemory: true)) {
                            ToolKitRowView(toolKit: kit)
                        }
                        .swipeActions(edge: .leading) {
                            Button {
                                toolKitToEdit = kit
                            } label: {
                                Label("Edit", systemImage: "pencil")
                            }
                            .tint(.blue)
                        }
                        .contextMenu {
                            Button(action: { toolKitToEdit = kit }) { Label("Edit Kit", systemImage: "pencil") }
                                .accessibilityIdentifier("editKit_\(kit.id.uuidString)")
                            Button(action: { exportToolKit(kit) }) { Label("Export Kit", systemImage: "square.and.arrow.up") }
                            Divider()
                            Button(role: .destructive) { toolKitToDelete = kit; showingDeleteKitConfirmation = true } label: { Label("Delete Kit", systemImage: "trash") }
                        }
                    }
                    .accessibilityIdentifier("personalToolKit_\(kit.id.uuidString)")
                }
                .onDelete(perform: isSelectMode ? nil : deletePersonalToolKits)

                // Individual personal tools (not in any group)
                ForEach(personalTools, id: \.id) { tool in
                    toolRow(for: tool, rowView: AnyView(ToolRowView(tool: tool)), prefix: "personalToolRow")
                }
                .onDelete(perform: deletePersonalTools)
            }
        } header: {
            HStack(spacing: 6) {
                Image(systemName: "person.fill")
                    .foregroundColor(Color(red: 0.145, green: 0.388, blue: 0.922)) // Industrial blue
                Text("Personal")
                    .foregroundColor(Color(red: 0.145, green: 0.388, blue: 0.922))
                // Feature #136: Count includes individual tools, tool sets, and tool kits
                Text("(\(personalTools.count + personalToolSets.count + personalToolKits.count))")
                    .foregroundColor(.secondary)
            }
            .font(.subheadline)
            .fontWeight(.semibold)
            .accessibilityIdentifier("personalSectionHeader")
        }
    }

    // MARK: - Borrowed Tools List Section

    // Feature #119: Borrowed Tools section - Borrowed ownership with visible header
    // Borrowed tools appear as standalone items (not in groups)
    @ViewBuilder
    private var borrowedToolsListSection: some View {
        Section {
            if borrowedTools.isEmpty {
                Text("No borrowed tools yet")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                    .padding(.vertical, 4)
                    .accessibilityIdentifier("borrowedToolsEmptyState")
            } else {
                ForEach(borrowedTools, id: \.id) { tool in
                    toolRow(for: tool, rowView: AnyView(BorrowedToolRowView(tool: tool)), prefix: "borrowedToolRow")
                }
                .onDelete(perform: deleteBorrowedTools)

                // Purchase Justification link
                NavigationLink(destination: PurchaseJustificationView().modelContainer(for: [FROTool.self, FROJob.self, FROToolGroup.self, FROToolKit.self, FROConsumable.self, FROChemical.self, FROPart.self], inMemory: true)) {
                    HStack(spacing: 12) {
                        Image(systemName: "chart.bar.doc.horizontal.fill")
                            .font(.body)
                            .foregroundColor(Color(red: 0.145, green: 0.388, blue: 0.922)) // Industrial blue
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Purchase Justification")
                                .font(.subheadline)
                                .fontWeight(.semibold)
                                .foregroundColor(.primary)
                            Text("View usage stats to justify purchases")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                        Spacer()
                    }
                    .padding(.vertical, 4)
                }
                .accessibilityIdentifier("purchaseJustificationLink")
            }
        } header: {
            HStack(spacing: 6) {
                Image(systemName: "arrow.left.arrow.right")
                    .foregroundColor(Color(red: 0.976, green: 0.451, blue: 0.086)) // Safety orange
                Text("Borrowed")
                    .foregroundColor(Color(red: 0.976, green: 0.451, blue: 0.086))
                Text("(\(borrowedTools.count))")
                    .foregroundColor(.secondary)
            }
            .font(.subheadline)
            .fontWeight(.semibold)
            .accessibilityIdentifier("borrowedSectionHeader")
        }
    }

    // MARK: - Shop Tools List Section

    // Feature #119: Shop Tools section - Shop ownership with visible header
    // Feature #135: Shop Tool Sets appear within this section
    // Feature #136: Shop Tool Kits appear within this section
    @ViewBuilder
    private var shopToolsListSection: some View {
        Section {
            if shopTools.isEmpty && shopToolSets.isEmpty && shopToolKits.isEmpty {
                Text("No shop tools yet")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                    .padding(.vertical, 4)
                    .accessibilityIdentifier("shopToolsEmptyState")
            } else {
                // Feature #135: Shop Tool Sets appear first, grouped together
                ForEach(shopToolSets, id: \.id) { group in
                    toolSetRow(for: group) {
                        ToolGroupRowView(
                            group: group,
                            viewContext: viewContext,
                            onEditTool: { tool in toolToEdit = tool },
                            onEditGroup: { group in toolGroupToEdit = group },
                            onAddSubGroup: { parent in
                                addGroupParent = parent
                                showingAddToolGroup = true
                            },
                            onAddToolToGroup: { parent in
                                showingAddTool = true
                            },
                            onDeleteGroup: { group in toolGroupToDelete = group; showingDeleteGroupConfirmation = true },
                            onExportGroup: { group in exportToolGroup(group) },
                            expandedGroups: $expandedGroups
                        )
                    }
                    .accessibilityIdentifier("shopToolSet_\(group.id.uuidString)")
                }
                .onDelete(perform: isSelectMode ? nil : deleteShopToolSets)

                // Feature #136: Shop Tool Kits appear after Tool Sets
                // Feature #139: Swipe and context menu to edit kit
                ForEach(shopToolKits, id: \.id) { kit in
                    toolKitRow(for: kit) {
                        NavigationLink(destination: ToolKitDetailView(toolKit: kit).modelContainer(for: [FROTool.self, FROJob.self, FROToolGroup.self, FROToolKit.self, FROConsumable.self, FROChemical.self, FROPart.self], inMemory: true)) {
                            ToolKitRowView(toolKit: kit)
                        }
                        .swipeActions(edge: .leading) {
                            Button {
                                toolKitToEdit = kit
                            } label: {
                                Label("Edit", systemImage: "pencil")
                            }
                            .tint(.blue)
                        }
                        .contextMenu {
                            Button(action: { toolKitToEdit = kit }) { Label("Edit Kit", systemImage: "pencil") }
                                .accessibilityIdentifier("editKit_\(kit.id.uuidString)")
                            Button(action: { exportToolKit(kit) }) { Label("Export Kit", systemImage: "square.and.arrow.up") }
                            Divider()
                            Button(role: .destructive) { toolKitToDelete = kit; showingDeleteKitConfirmation = true } label: { Label("Delete Kit", systemImage: "trash") }
                        }
                    }
                    .accessibilityIdentifier("shopToolKit_\(kit.id.uuidString)")
                }
                .onDelete(perform: isSelectMode ? nil : deleteShopToolKits)

                // Individual shop tools (not in any group)
                ForEach(shopTools, id: \.id) { tool in
                    toolRow(for: tool, rowView: AnyView(ToolRowView(tool: tool)), prefix: "shopToolRow")
                }
                .onDelete(perform: deleteShopTools)
            }
        } header: {
            HStack(spacing: 6) {
                Image(systemName: "building.2.fill")
                    .foregroundColor(Color(red: 0.392, green: 0.455, blue: 0.545)) // Steel gray
                Text("Shop")
                    .foregroundColor(Color(red: 0.392, green: 0.455, blue: 0.545))
                // Feature #136: Count includes individual tools, tool sets, and tool kits
                Text("(\(shopTools.count + shopToolSets.count + shopToolKits.count))")
                    .foregroundColor(.secondary)
            }
            .font(.subheadline)
            .fontWeight(.semibold)
            .accessibilityIdentifier("shopSectionHeader")
        }
    }

    // MARK: - Feature #123: Frequently Borrowed Button

    /// Button displayed at the top of the tools section for quick access to borrowed tool history.
    /// Always visible without scrolling, above all tool sections.
    private var frequentlyBorrowedButton: some View {
        NavigationLink(destination: PurchaseJustificationView().modelContainer(for: [FROTool.self, FROJob.self, FROToolGroup.self, FROToolKit.self, FROConsumable.self, FROChemical.self, FROPart.self], inMemory: true)) {
            HStack(spacing: 12) {
                // Icon with orange background circle
                ZStack {
                    Circle()
                        .fill(Color(red: 0.976, green: 0.451, blue: 0.086).opacity(0.15)) // Safety orange background
                        .frame(width: 40, height: 40)
                    Image(systemName: "arrow.left.arrow.right.circle.fill")
                        .font(.title3)
                        .foregroundColor(Color(red: 0.976, green: 0.451, blue: 0.086)) // Safety orange
                }

                VStack(alignment: .leading, spacing: 2) {
                    Text("Frequently Borrowed")
                        .font(.headline)
                        .foregroundColor(.primary)
                    Text("View usage stats to justify purchases")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }

                Spacer()

                // Borrowed count badge
                if borrowedTools.count > 0 {
                    Text("\(borrowedTools.count)")
                        .font(.caption)
                        .fontWeight(.bold)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(Color(red: 0.976, green: 0.451, blue: 0.086).opacity(0.15))
                        .foregroundColor(Color(red: 0.976, green: 0.451, blue: 0.086))
                        .clipShape(Capsule())
                }

                Image(systemName: "chevron.right")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .background(Color(.systemBackground))
            .cornerRadius(12)
            .shadow(color: .black.opacity(0.05), radius: 4, y: 2)
        }
        .buttonStyle(.plain)
        .padding(.horizontal)
        .padding(.top, 12)
        .padding(.bottom, 4)
        .accessibilityIdentifier("frequentlyBorrowedButton")
        .accessibilityLabel("Frequently Borrowed, \(borrowedTools.count) tools")
        .accessibilityHint("View borrowed tool history to help justify tool purchases")
    }

    // MARK: - Consumables Section

    /// All consumable category keys in display order
    private let consumableCategoryOrder = ["safety_wire", "cotter_pin", "o_ring", "seal", "other"]

    /// Group consumables by category
    private var consumablesByCategory: [String: [Consumable]] {
        var grouped: [String: [Consumable]] = [:]
        for consumable in consumables {
            let category = consumable.category
            if grouped[category] == nil {
                grouped[category] = []
            }
            grouped[category]?.append(consumable)
        }
        return grouped
    }

    /// Get human-readable label for consumable category
    private func consumableCategoryLabel(_ category: String) -> String {
        switch category {
        case "safety_wire": return "Safety Wire"
        case "cotter_pin": return "Cotter Pin"
        case "o_ring": return "O-Ring"
        case "seal": return "Seal"
        case "other": return "Other"
        default: return category.capitalized
        }
    }

    /// Get color for consumable category
    private func consumableCategoryColor(_ category: String) -> Color {
        switch category {
        case "safety_wire": return Color(red: 0.145, green: 0.388, blue: 0.922) // Industrial blue
        case "cotter_pin": return Color(red: 0.976, green: 0.451, blue: 0.086) // Safety orange
        case "o_ring": return Color(red: 0.133, green: 0.773, blue: 0.369) // Green
        case "seal": return Color(red: 0.392, green: 0.455, blue: 0.545) // Steel gray
        default: return Color(red: 0.392, green: 0.455, blue: 0.545)
        }
    }

    /// Get icon for consumable category
    private func consumableCategoryIcon(_ category: String) -> String {
        switch category {
        case "safety_wire": return "line.diagonal"
        case "cotter_pin": return "pin.fill"
        case "o_ring": return "circle"
        case "seal": return "seal.fill"
        default: return "bolt.fill"
        }
    }

    private var consumablesSection: some View {
        Group {
            if consumables.isEmpty {
                VStack(spacing: 16) {
                    Spacer()
                    Image(systemName: "bolt.fill")
                        .font(.system(size: 60))
                        .foregroundColor(Color(red: 0.392, green: 0.455, blue: 0.545)) // Steel gray
                    Text("No Consumables Yet")
                        .font(.title2)
                        .fontWeight(.semibold)
                    Text("Start building your consumable inventory.\nTap + to add safety wire, cotter pins, O-rings, and more.")
                        .font(.body)
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
                    Spacer()
                }
                .padding()
            } else {
                List {
                    // Display consumables grouped by category
                    ForEach(consumableCategoryOrder, id: \.self) { category in
                        if let categoryConsumables = consumablesByCategory[category], !categoryConsumables.isEmpty {
                            Section {
                                ForEach(categoryConsumables, id: \.id) { consumable in
                                    ConsumableRowView(consumable: consumable)
                                        .contentShape(Rectangle())
                                        .onTapGesture {
                                            consumableToEdit = consumable
                                        }
                                }
                                .onDelete { offsets in
                                    deleteConsumablesInCategory(category, at: offsets)
                                }
                            } header: {
                                HStack(spacing: 6) {
                                    Image(systemName: consumableCategoryIcon(category))
                                        .foregroundColor(consumableCategoryColor(category))
                                    Text(consumableCategoryLabel(category))
                                        .foregroundColor(consumableCategoryColor(category))
                                    Text("(\(categoryConsumables.count))")
                                        .foregroundColor(.secondary)
                                }
                                .font(.subheadline)
                                .fontWeight(.semibold)
                            }
                        }
                    }

                    // Handle any categories not in the predefined order
                    ForEach(Array(consumablesByCategory.keys.filter { !consumableCategoryOrder.contains($0) }), id: \.self) { category in
                        if let categoryConsumables = consumablesByCategory[category], !categoryConsumables.isEmpty {
                            Section {
                                ForEach(categoryConsumables, id: \.id) { consumable in
                                    ConsumableRowView(consumable: consumable)
                                        .contentShape(Rectangle())
                                        .onTapGesture {
                                            consumableToEdit = consumable
                                        }
                                }
                                .onDelete { offsets in
                                    deleteConsumablesInCategory(category, at: offsets)
                                }
                            } header: {
                                HStack(spacing: 6) {
                                    Image(systemName: consumableCategoryIcon(category))
                                        .foregroundColor(consumableCategoryColor(category))
                                    Text(consumableCategoryLabel(category))
                                        .foregroundColor(consumableCategoryColor(category))
                                    Text("(\(categoryConsumables.count))")
                                        .foregroundColor(.secondary)
                                }
                                .font(.subheadline)
                                .fontWeight(.semibold)
                            }
                        }
                    }
                }
                .listStyle(.insetGrouped)
            }
        }
    }

    /// Delete consumables from a specific category section
    private func deleteConsumablesInCategory(_ category: String, at offsets: IndexSet) {
        guard let categoryConsumables = consumablesByCategory[category] else { return }
        for index in offsets {
            let consumable = categoryConsumables[index]
            let name = consumable.name
            viewContext.delete(consumable)
            print("GarageView: Deleted consumable '\(name)' from category '\(category)'")
        }
        do {
            try viewContext.save()
        } catch {
            print("GarageView: Failed to delete consumable, rolled back - \(error)")
        }
    }

    // MARK: - Chemicals Section

    /// All chemical category keys in display order
    private let chemicalCategoryOrder = ["fluid", "lubricant", "cleaner", "sealant", "other"]

    /// Group chemicals by category
    private var chemicalsByCategory: [String: [Chemical]] {
        var grouped: [String: [Chemical]] = [:]
        for chemical in chemicals {
            let category = chemical.category
            if grouped[category] == nil {
                grouped[category] = []
            }
            grouped[category]?.append(chemical)
        }
        return grouped
    }

    /// Get human-readable label for chemical category
    private func chemicalCategoryLabel(_ category: String) -> String {
        switch category {
        case "fluid": return "Fluid"
        case "lubricant": return "Lubricant"
        case "cleaner": return "Cleaner"
        case "sealant": return "Sealant"
        case "other": return "Other"
        default: return category.capitalized
        }
    }

    /// Get color for chemical category
    private func chemicalCategoryColor(_ category: String) -> Color {
        switch category {
        case "fluid": return Color(red: 0.145, green: 0.388, blue: 0.922) // Industrial blue
        case "lubricant": return Color(red: 0.976, green: 0.451, blue: 0.086) // Safety orange
        case "cleaner": return Color(red: 0.133, green: 0.773, blue: 0.369) // Green
        case "sealant": return Color(red: 0.392, green: 0.455, blue: 0.545) // Steel gray
        default: return Color(red: 0.392, green: 0.455, blue: 0.545)
        }
    }

    /// Get icon for chemical category
    private func chemicalCategoryIcon(_ category: String) -> String {
        switch category {
        case "fluid": return "drop.fill"
        case "lubricant": return "oilcan.fill"
        case "cleaner": return "sparkles"
        case "sealant": return "seal.fill"
        default: return "drop.fill"
        }
    }

    private var chemicalsSection: some View {
        Group {
            if chemicals.isEmpty {
                VStack(spacing: 16) {
                    Spacer()
                    Image(systemName: "drop.fill")
                        .font(.system(size: 60))
                        .foregroundColor(Color(red: 0.392, green: 0.455, blue: 0.545)) // Steel gray
                    Text("No Chemicals Yet")
                        .font(.title2)
                        .fontWeight(.semibold)
                    Text("Start building your chemical inventory.\nTap + to add fluids, lubricants, cleaners, and sealants.")
                        .font(.body)
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
                    Spacer()
                }
                .padding()
            } else {
                List {
                    // Display chemicals grouped by category
                    ForEach(chemicalCategoryOrder, id: \.self) { category in
                        if let categoryChemicals = chemicalsByCategory[category], !categoryChemicals.isEmpty {
                            Section {
                                ForEach(categoryChemicals, id: \.id) { chemical in
                                    ChemicalRowView(chemical: chemical)
                                        .contentShape(Rectangle())
                                        .onTapGesture {
                                            chemicalToEdit = chemical
                                        }
                                }
                                .onDelete { offsets in
                                    deleteChemicalsInCategory(category, at: offsets)
                                }
                            } header: {
                                HStack(spacing: 6) {
                                    Image(systemName: chemicalCategoryIcon(category))
                                        .foregroundColor(chemicalCategoryColor(category))
                                    Text(chemicalCategoryLabel(category))
                                        .foregroundColor(chemicalCategoryColor(category))
                                    Text("(\(categoryChemicals.count))")
                                        .foregroundColor(.secondary)
                                }
                                .font(.subheadline)
                                .fontWeight(.semibold)
                            }
                        }
                    }

                    // Handle any categories not in the predefined order
                    ForEach(Array(chemicalsByCategory.keys.filter { !chemicalCategoryOrder.contains($0) }), id: \.self) { category in
                        if let categoryChemicals = chemicalsByCategory[category], !categoryChemicals.isEmpty {
                            Section {
                                ForEach(categoryChemicals, id: \.id) { chemical in
                                    ChemicalRowView(chemical: chemical)
                                        .contentShape(Rectangle())
                                        .onTapGesture {
                                            chemicalToEdit = chemical
                                        }
                                }
                                .onDelete { offsets in
                                    deleteChemicalsInCategory(category, at: offsets)
                                }
                            } header: {
                                HStack(spacing: 6) {
                                    Image(systemName: chemicalCategoryIcon(category))
                                        .foregroundColor(chemicalCategoryColor(category))
                                    Text(chemicalCategoryLabel(category))
                                        .foregroundColor(chemicalCategoryColor(category))
                                    Text("(\(categoryChemicals.count))")
                                        .foregroundColor(.secondary)
                                }
                                .font(.subheadline)
                                .fontWeight(.semibold)
                            }
                        }
                    }
                }
                .listStyle(.insetGrouped)
            }
        }
    }

    /// Delete chemicals from a specific category section
    private func deleteChemicalsInCategory(_ category: String, at offsets: IndexSet) {
        guard let categoryChemicals = chemicalsByCategory[category] else { return }
        for index in offsets {
            let chemical = categoryChemicals[index]
            let name = chemical.name
            viewContext.delete(chemical)
            print("GarageView: Deleted chemical '\(name)' from category '\(category)'")
        }
        do {
            try viewContext.save()
        } catch {
            print("GarageView: Failed to delete chemical, rolled back - \(error)")
        }
    }

    // MARK: - Actions

    /// Perform smart tool deletion after confirmation.
    /// If the tool has job references, it's converted to borrowed instead of being deleted.
    private func performToolDeletion(_ tool: Tool) {
        let name = tool.name
        let result = ToolService().smartDeleteTool(tool)

        switch result {
        case .deleted:
            print("GarageView: Deleted tool '\(name)' from Core Data")
            deletedToolName = name
            toolToDelete = nil
            showingDeleteToolSuccess = true
        case .convertedToBorrowed(let newName):
            print("GarageView: Converted tool '\(name)' to borrowed as '\(newName)'")
            convertedToolName = newName
            toolToDelete = nil
            showingConvertedToBorrowed = true
        }
    }

    /// Request delete confirmation for a tool from borrowed list
    private func requestDeleteBorrowedTool(at offsets: IndexSet) {
        let borrowed = borrowedTools
        if let index = offsets.first {
            toolToDelete = borrowed[index]
            showingDeleteToolConfirmation = true
        }
    }

    /// Request delete confirmation for a tool from ungrouped owned list
    private func requestDeleteUngroupedOwnedTool(at offsets: IndexSet) {
        let ungrouped = ungroupedOwnedTools
        if let index = offsets.first {
            toolToDelete = ungrouped[index]
            showingDeleteToolConfirmation = true
        }
    }

    private func deleteTools(at offsets: IndexSet) {
        for index in offsets {
            let tool = tools[index]
            viewContext.delete(tool)
        }
        do {
            try viewContext.save()
        } catch {
            print("GarageView: Failed to delete tool, rolled back - \(error)")
        }
    }

    /// Delete from the borrowed tools subsection (with confirmation)
    private func deleteBorrowedTools(at offsets: IndexSet) {
        requestDeleteBorrowedTool(at: offsets)
    }

    /// Feature #119: Delete from the personal tools section (with confirmation)
    private func deletePersonalTools(at offsets: IndexSet) {
        let personal = personalTools
        if let index = offsets.first {
            toolToDelete = personal[index]
            showingDeleteToolConfirmation = true
        }
    }

    /// Feature #119: Delete from the shop tools section (with confirmation)
    private func deleteShopTools(at offsets: IndexSet) {
        let shop = shopTools
        if let index = offsets.first {
            toolToDelete = shop[index]
            showingDeleteToolConfirmation = true
        }
    }

    /// Delete from the ungrouped owned (personal/shop) tools subsection (with confirmation)
    private func deleteUngroupedOwnedTools(at offsets: IndexSet) {
        requestDeleteUngroupedOwnedTool(at: offsets)
    }

    /// Delete from the owned (personal/shop) tools subsection
    private func deleteOwnedTools(at offsets: IndexSet) {
        let owned = ownedTools
        for index in offsets {
            viewContext.delete(owned[index])
        }
        do {
            try viewContext.save()
        } catch {
            print("GarageView: Failed to delete owned tool, rolled back - \(error)")
        }
    }

    /// Delete top-level tool groups
    private func deleteTopLevelGroups(at offsets: IndexSet) {
        let groups = topLevelGroups
        for index in offsets {
            viewContext.delete(groups[index])
        }
        do {
            try viewContext.save()
        } catch {
            print("GarageView: Failed to delete tool group, rolled back - \(error)")
        }
    }

    /// Feature #135: Delete personal tool sets from the personal section
    private func deletePersonalToolSets(at offsets: IndexSet) {
        let sets = personalToolSets
        for index in offsets {
            let toolSet = sets[index]
            let name = toolSet.name
            viewContext.delete(toolSet)
            print("GarageView: Deleted personal tool set '\(name)'")
        }
        do {
            try viewContext.save()
        } catch {
            print("GarageView: Failed to delete personal tool set, rolled back - \(error)")
        }
    }

    /// Feature #135: Delete shop tool sets from the shop section
    private func deleteShopToolSets(at offsets: IndexSet) {
        let sets = shopToolSets
        for index in offsets {
            let toolSet = sets[index]
            let name = toolSet.name
            viewContext.delete(toolSet)
            print("GarageView: Deleted shop tool set '\(name)'")
        }
        do {
            try viewContext.save()
        } catch {
            print("GarageView: Failed to delete shop tool set, rolled back - \(error)")
        }
    }

    /// Delete tool kits (used for general deletion if needed)
    private func deleteToolKits(at offsets: IndexSet) {
        for index in offsets {
            let kit = toolKits[index]
            let name = kit.name
            viewContext.delete(kit)
            print("GarageView: Deleted tool kit '\(name)'")
        }
        do {
            try viewContext.save()
        } catch {
            print("GarageView: Failed to delete tool kit, rolled back - \(error)")
        }
    }

    /// Feature #136: Delete personal tool kits from the personal section
    private func deletePersonalToolKits(at offsets: IndexSet) {
        let kits = personalToolKits
        for index in offsets {
            let kit = kits[index]
            let name = kit.name
            viewContext.delete(kit)
            print("GarageView: Deleted personal tool kit '\(name)'")
        }
        do {
            try viewContext.save()
        } catch {
            print("GarageView: Failed to delete personal tool kit, rolled back - \(error)")
        }
    }

    /// Feature #136: Delete shop tool kits from the shop section
    private func deleteShopToolKits(at offsets: IndexSet) {
        let kits = shopToolKits
        for index in offsets {
            let kit = kits[index]
            let name = kit.name
            viewContext.delete(kit)
            print("GarageView: Deleted shop tool kit '\(name)'")
        }
        do {
            try viewContext.save()
        } catch {
            print("GarageView: Failed to delete shop tool kit, rolled back - \(error)")
        }
    }

    // MARK: - Task #10: Export & Delete Helpers

    private func exportSingleTool(_ tool: Tool) {
        if let url = ToolExportService.shared.exportTools([tool], context: viewContext) {
            exportFileURL = url; showingExportShareSheet = true
        }
    }

    private func exportToolGroup(_ group: ToolGroup) {
        var toolIDs: Set<UUID> = []
        collectTools(from: group, into: &toolIDs)
        let toolObjects = toolIDs.compactMap { fetchByPersistentID(Tool.self, id: $0, context: viewContext) }
        guard !toolObjects.isEmpty else { return }
        if let url = ToolExportService.shared.exportTools(toolObjects, context: viewContext) {
            exportFileURL = url; showingExportShareSheet = true
        }
    }

    private func exportToolKit(_ kit: ToolKit) {
        guard let kitTools = kit.tools else { return }
        let toolArray = Array(kitTools)
        guard !toolArray.isEmpty else { return }
        if let url = ToolExportService.shared.exportTools(toolArray, context: viewContext) {
            exportFileURL = url; showingExportShareSheet = true
        }
    }

    private func performToolGroupDeletion(_ group: ToolGroup) {
        let name = group.name
        if let tools = group.tools { for tool in tools { tool.group = nil } }
        viewContext.delete(group)
        do { try viewContext.save(); print("GarageView: Deleted tool set '\(name)', tools preserved") }
        catch { viewContext.rollback(); print("GarageView: Failed to delete tool set '\(name)', rolled back - \(error)") }
        toolGroupToDelete = nil
    }

    private func performToolKitDeletion(_ kit: ToolKit) {
        let name = kit.name
        viewContext.delete(kit)
        do { try viewContext.save(); print("GarageView: Deleted tool kit '\(name)'") }
        catch { viewContext.rollback(); print("GarageView: Failed to delete tool kit '\(name)', rolled back - \(error)") }
        toolKitToDelete = nil
    }

}

// MARK: - Simplified Row for Select Mode

/// Simplified row view used when a Tool Set is shown in select mode.
/// Shows icon + name only, without the expand/collapse disclosure group.
private struct ToolKitRowStyleWrapper: View {
    let name: String
    let icon: String

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: icon)
                .foregroundColor(Color(red: 0.145, green: 0.388, blue: 0.922))
                .font(.body)
            Text(name)
                .font(.body)
                .foregroundColor(.primary)
            Spacer()
        }
    }
}

// MARK: - Select Mode Tool Kit Row

/// Expandable Tool Kit row for select mode with checkbox + expand/collapse.
private struct SelectModeToolKitRow: View {
    @Bindable var kit: ToolKit
    var viewContext: ModelContext
    let isKitSelected: Bool
    @Binding var selectedTools: Set<UUID>
    let onToggleKitSelection: () -> Void

    @State private var isExpanded: Bool = false

    private let kitColor = Color(red: 0.133, green: 0.545, blue: 0.133)

    private var kitTools: [Tool] {
        guard let tools = kit.tools else { return [] }
        return Array(tools).sortedBySize()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 0) {
                Button {
                    onToggleKitSelection()
                } label: {
                    Image(systemName: isKitSelected ? "checkmark.circle.fill" : "circle")
                        .foregroundColor(isKitSelected ? Color(red: 0.145, green: 0.388, blue: 0.922) : .secondary)
                        .font(.title3)
                        .frame(width: 36, height: 36)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)

                Button(action: { withAnimation(.easeInOut(duration: 0.2)) { isExpanded.toggle() } }) {
                    HStack(spacing: 8) {
                        Image(systemName: isExpanded ? "chevron.down" : "chevron.right")
                            .font(.caption)
                            .foregroundColor(.secondary)
                            .frame(width: 16)
                        Image(systemName: "bag.fill")
                            .foregroundColor(kitColor)
                            .font(.body)
                        Text(kit.name)
                            .font(.headline)
                            .foregroundColor(.primary)
                        Spacer()
                        Text("\(kitTools.count) tools")
                            .font(.caption)
                            .fontWeight(.medium)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 3)
                            .background(kitColor.opacity(0.15))
                            .foregroundColor(kitColor)
                            .clipShape(Capsule())
                    }
                    .padding(.vertical, 6)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }

            if isExpanded {
                VStack(alignment: .leading, spacing: 0) {
                    ForEach(kitTools, id: \.id) { tool in
                        Button {
                            if selectedTools.contains(tool.id) {
                                selectedTools.remove(tool.id)
                            } else {
                                selectedTools.insert(tool.id)
                            }
                        } label: {
                            HStack(spacing: 12) {
                                Image(systemName: selectedTools.contains(tool.id) ? "checkmark.circle.fill" : "circle")
                                    .foregroundColor(selectedTools.contains(tool.id) ? Color(red: 0.145, green: 0.388, blue: 0.922) : .secondary)
                                    .font(.title3)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(tool.name)
                                        .font(.subheadline)
                                        .fontWeight(.medium)
                                        .foregroundColor(.primary)
                                    Text(tool.ownershipType == "shop" ? "Shop" : "Personal")
                                        .font(.caption2)
                                        .foregroundColor(.secondary)
                                }
                                Spacer()
                            }
                            .padding(.vertical, 6)
                        }
                        .buttonStyle(.plain)
                        .padding(.leading, 20)
                        .accessibilityIdentifier("selectToolInKit_\(tool.id.uuidString)")
                    }
                }
            }
        }
    }
}


// MARK: - Tool Set Row View (Recursive, supports nested hierarchy)

/// Displays a tool set with expand/collapse, showing child sets and tools.
/// Supports arbitrary nesting depth.
/// Feature #107: Shows measurement type badge (SAE/Metric).
/// Feature #112: Remove tool from set via swipe action.
/// Feature #130: Renamed from "Tool Group" to "Tool Set" throughout UI.
struct ToolGroupRowView: View {
    @Bindable var group: ToolGroup
    var viewContext: ModelContext
    var onEditTool: (Tool) -> Void
    var onEditGroup: (ToolGroup) -> Void
    var onAddSubGroup: (ToolGroup) -> Void
    var onAddToolToGroup: (ToolGroup) -> Void
    var onDeleteGroup: ((ToolGroup) -> Void)? = nil
    var onExportGroup: ((ToolGroup) -> Void)? = nil
    var expandedGroups: Binding<Set<UUID>>? = nil

    // Select mode parameters (optional - default to non-select mode)
    var isSelectMode: Bool = false
    var isSetSelected: Bool = false
    var selectedTools: Binding<Set<UUID>> = .constant([])
    var onToggleSetSelection: (() -> Void)? = nil

    @AppStorage("showToolThumbnails") private var showToolThumbnails = true
    @State private var localIsExpanded: Bool = true
    @State private var thumbnail: UIImage?

    private var isExpanded: Bool {
        if let expandedGroups = expandedGroups { return expandedGroups.wrappedValue.contains(group.id) }
        return localIsExpanded
    }

    private func toggleExpanded() {
        withAnimation(.easeInOut(duration: 0.2)) {
            if let expandedGroups = expandedGroups {
                let id = group.id
                if expandedGroups.wrappedValue.contains(id) { expandedGroups.wrappedValue.remove(id) } else { expandedGroups.wrappedValue.insert(id) }
            } else { localIsExpanded.toggle() }
        }
    }

    // Feature #112: State for remove from group confirmation
    @State private var toolToRemoveFromGroup: Tool?
    @State private var showingRemoveFromGroupConfirmation = false

    /// Get the measurement type display name
    private var measurementTypeLabel: String {
        if let storedType = group.measurementType {
            switch storedType {
            case "metric": return "Metric"
            case "sae": return "SAE"
            default: return "SAE"
            }
        }
        return "SAE"
    }

    /// Color for measurement type badge
    private var measurementTypeColor: Color {
        if group.measurementType == "metric" {
            return Color(red: 0.133, green: 0.545, blue: 0.133) // Green
        }
        return Color(red: 0.145, green: 0.388, blue: 0.922) // Industrial blue
    }

    /// Sorted child groups
    private var childGroups: [ToolGroup] {
        guard let children = group.childGroups else { return [] }
        return children.sorted { g1, g2 in
            if g1.sortOrder != g2.sortOrder {
                return g1.sortOrder < g2.sortOrder
            }
            return g1.name < g2.name
        }
    }

    /// Tools directly in this group, sorted by size then name
    private var groupTools: [Tool] {
        guard let tools = group.tools else { return [] }
        return Array(tools).sortedBySize()
    }

    /// Total tool count including nested groups
    private var totalToolCount: Int {
        var count = groupTools.count
        for child in childGroups {
            count += countTools(in: child)
        }
        return count
    }

    private func countTools(in group: ToolGroup) -> Int {
        var count = (group.tools)?.count ?? 0
        if let children = group.childGroups {
            for child in children {
                count += countTools(in: child)
            }
        }
        return count
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Group header row with expand/collapse
            HStack(spacing: 0) {
                // Select mode: show set-level checkbox
                if isSelectMode {
                    Button {
                        onToggleSetSelection?()
                    } label: {
                        Image(systemName: isSetSelected ? "checkmark.circle.fill" : "circle")
                            .foregroundColor(isSetSelected ? Color(red: 0.145, green: 0.388, blue: 0.922) : .secondary)
                            .font(.title3)
                            .frame(width: 36, height: 36)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }

                // Expand/collapse button (works in both normal and select mode)
                Button(action: { toggleExpanded() }) {
                    HStack(spacing: 8) {
                        Image(systemName: isExpanded ? "chevron.down" : "chevron.right")
                            .font(.caption)
                            .foregroundColor(.secondary)
                            .frame(width: 16)

                        // Feature #137: Tool Sets use grid icon (or thumbnail photo) for visual distinction
                        if showToolThumbnails, let thumb = thumbnail {
                            Image(uiImage: thumb)
                                .resizable()
                                .aspectRatio(contentMode: .fill)
                                .frame(width: 32, height: 32)
                                .clipped()
                                .cornerRadius(6)
                                .accessibilityHidden(true)
                        } else {
                            Image(systemName: "square.grid.2x2.fill")
                                .foregroundColor(Color(red: 0.145, green: 0.388, blue: 0.922))
                                .font(.body)
                        }

                        Text(group.name)
                            .font(.headline)
                            .foregroundColor(.primary)

                        // Measurement type badge (Feature #107)
                        Text(measurementTypeLabel)
                            .font(.caption2)
                            .fontWeight(.medium)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(measurementTypeColor.opacity(0.15))
                            .foregroundColor(measurementTypeColor)
                            .clipShape(Capsule())
                            .accessibilityIdentifier("measurementTypeBadge_\(group.name)")

                        Spacer()

                        Text("\(totalToolCount)")
                            .font(.caption)
                            .foregroundColor(.secondary)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Color.secondary.opacity(0.15))
                            .clipShape(Capsule())
                    }
                    .padding(.vertical, 6)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
            .contextMenu {
                if !isSelectMode {
                    Button(action: { onEditGroup(group) }) { Label("Edit Set", systemImage: "pencil") }
                    Button(action: { onAddSubGroup(group) }) { Label("Add Sub-Set", systemImage: "folder.badge.plus") }
                    if let onExportGroup = onExportGroup {
                        Button(action: { onExportGroup(group) }) { Label("Export Set", systemImage: "square.and.arrow.up") }
                    }
                    if let onDeleteGroup = onDeleteGroup {
                        Divider()
                        Button(role: .destructive) { onDeleteGroup(group) } label: { Label("Delete Set", systemImage: "trash") }
                    }
                }
            }

            // Expanded content
            if isExpanded {
                VStack(alignment: .leading, spacing: 0) {
                    // Child groups (recursive)
                    ForEach(childGroups, id: \.id) { childGroup in
                        if isSelectMode {
                            ToolGroupRowView(
                                group: childGroup,
                                viewContext: viewContext,
                                onEditTool: onEditTool,
                                onEditGroup: onEditGroup,
                                onAddSubGroup: onAddSubGroup,
                                onAddToolToGroup: onAddToolToGroup,
                                expandedGroups: expandedGroups,
                                isSelectMode: true,
                                isSetSelected: false,
                                selectedTools: selectedTools,
                                onToggleSetSelection: {}
                            )
                            .padding(.leading, 20)
                        } else {
                            ToolGroupRowView(
                                group: childGroup,
                                viewContext: viewContext,
                                onEditTool: onEditTool,
                                onEditGroup: onEditGroup,
                                onAddSubGroup: onAddSubGroup,
                                onAddToolToGroup: onAddToolToGroup,
                                onDeleteGroup: onDeleteGroup,
                                onExportGroup: onExportGroup,
                                expandedGroups: expandedGroups
                            )
                            .padding(.leading, 20)
                        }
                    }

                    // Tools in this group
                    ForEach(groupTools, id: \.id) { tool in
                        if isSelectMode {
                            // Select mode: checkbox toggle instead of navigation
                            Button {
                                if selectedTools.wrappedValue.contains(tool.id) {
                                    selectedTools.wrappedValue.remove(tool.id)
                                } else {
                                    selectedTools.wrappedValue.insert(tool.id)
                                }
                            } label: {
                                HStack(spacing: 12) {
                                    Image(systemName: selectedTools.wrappedValue.contains(tool.id) ? "checkmark.circle.fill" : "circle")
                                        .foregroundColor(selectedTools.wrappedValue.contains(tool.id) ? Color(red: 0.145, green: 0.388, blue: 0.922) : .secondary)
                                        .font(.title3)
                                    GroupToolRowView(tool: tool, groupMeasurementType: group.measurementType)
                                }
                            }
                            .buttonStyle(.plain)
                            .padding(.leading, 20)
                            .accessibilityIdentifier("selectToolInSet_\(tool.id.uuidString)")
                        } else {
                            // Normal mode: NavigationLink to detail
                            NavigationLink(destination: ToolDetailView(tool: tool).modelContainer(for: [FROTool.self, FROJob.self, FROToolGroup.self, FROToolKit.self, FROConsumable.self, FROChemical.self, FROPart.self], inMemory: true)) {
                                GroupToolRowView(tool: tool, groupMeasurementType: group.measurementType)
                            }
                            .padding(.leading, 20)
                            .swipeActions(edge: .leading) {
                                Button {
                                    onEditTool(tool)
                                } label: {
                                    Label("Edit", systemImage: "pencil")
                                }
                                .tint(.blue)
                            }
                            // Feature #112: Trailing swipe action to remove from set
                            .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                                Button(role: .destructive) {
                                    toolToRemoveFromGroup = tool
                                    showingRemoveFromGroupConfirmation = true
                                } label: {
                                    Label("Remove from Set", systemImage: "folder.badge.minus")
                                }
                                .tint(.orange)
                                .accessibilityIdentifier("removeFromGroup_\(tool.id.uuidString)")
                            }
                        }
                    }
                }
            }
        }

        .onAppear {
            if showToolThumbnails && thumbnail == nil {
                thumbnail = ToolPhotoService.shared.loadThumbnail(forEntityID: group.id)
            }
        }
        // Feature #112: Confirmation dialog for removing tool from set
        .alert("Remove from Set?", isPresented: $showingRemoveFromGroupConfirmation) {
            Button("Cancel", role: .cancel) {
                toolToRemoveFromGroup = nil
            }
            Button("Remove", role: .destructive) {
                if let tool = toolToRemoveFromGroup {
                    removeToolFromGroup(tool)
                }
            }
        } message: {
            Text("Remove '\(toolToRemoveFromGroup?.name ?? "this tool")' from '\(group.name)'? The tool will remain in your Garage but won't be part of this set.")
        }
    }

    // MARK: - Feature #112: Remove Tool from Group

    /// Removes a tool from this group without deleting it from the Garage.
    /// The tool's group relationship is set to nil, and the context is saved.
    private func removeToolFromGroup(_ tool: Tool) {
        let toolName = tool.name
        let groupName = group.name

        // Clear the group relationship (tool remains in Garage)
        tool.group = nil

        do {
            try viewContext.save()
            print("ToolGroupRowView: Removed tool '\(toolName)' from group '\(groupName)'")
        } catch {
            print("ToolGroupRowView: Failed to remove tool '\(toolName)' from group '\(groupName)', rolled back - \(error)")
        }

        toolToRemoveFromGroup = nil
    }
}

// MARK: - Group Tool Row View (Feature #111)

/// Displays a tool within a group showing just size and indicator.
/// Feature #111: Tools within groups display as size and indicator only (e.g., '1/2"', '10mm').
/// The group name provides context, so individual tools stay clean and scannable.
/// Row height meets 44pt minimum tap target for gloved/greasy hands.
struct GroupToolRowView: View {
    @Bindable var tool: Tool
    let groupMeasurementType: String?

    /// Format the display size using the group's measurement type
    private var displayText: String {
        let toolName = tool.name
        return ToolSizeSortingService.formatSizeForGroup(toolName: toolName, groupMeasurementType: groupMeasurementType)
    }

    /// Determine if we should show notes (only if present)
    private var hasNotes: Bool {
        guard let notes = tool.notes, !notes.isEmpty else { return false }
        return true
    }

    private var accessibilityDescription: String {
        var parts: [String] = [displayText, ownershipLabel]
        if let borrowedFrom = tool.borrowedFrom, !borrowedFrom.isEmpty {
            parts.append("borrowed from \(borrowedFrom)")
        }
        return parts.joined(separator: ", ")
    }

    var body: some View {
        HStack(spacing: 12) {
            // Size display - prominent and clean
            Text(displayText)
                .font(.system(.headline, design: .rounded))
                .fontWeight(.semibold)
                .frame(minWidth: 50, alignment: .leading)
                .accessibilityIdentifier("groupToolSize_\(tool.id.uuidString)")

            Spacer()

            // Compact ownership badge
            Text(ownershipLabel)
                .font(.caption2)
                .fontWeight(.medium)
                .padding(.horizontal, 6)
                .padding(.vertical, 3)
                .background(ownershipColor.opacity(0.15))
                .foregroundColor(ownershipColor)
                .clipShape(Capsule())
                .accessibilityIdentifier("groupToolOwnership_\(tool.id.uuidString)")

            // Borrowed indicator if applicable
            if tool.ownershipType == "borrowed", let from = tool.borrowedFrom, !from.isEmpty {
                Text("(\(from))")
                    .font(.caption2)
                    .foregroundColor(ownershipColor)
                    .lineLimit(1)
                    .truncationMode(.tail)
            }
        }
        .padding(.vertical, 10)
        .frame(minHeight: 44)
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Tool size: \(accessibilityDescription)")
        .accessibilityHint("Double tap to view tool details")
        .accessibilityIdentifier("groupToolRow_\(tool.id.uuidString)")
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
        case "personal": return Color(red: 0.145, green: 0.388, blue: 0.922) // Industrial blue
        case "shop": return Color(red: 0.392, green: 0.455, blue: 0.545)     // Steel gray
        case "borrowed": return Color(red: 0.976, green: 0.451, blue: 0.086) // Safety orange
        case "imported": return Color(red: 0.608, green: 0.318, blue: 0.878) // Imported purple
        default: return .blue
        }
    }
}

// MARK: - Tool Row View

/// Displays a single tool in the list with name, ownership badge, notes, and optional thumbnail.
/// Row height meets 44pt minimum tap target for gloved/greasy hands.
/// Feature #137: Shows wrench icon (or thumbnail photo) for visual distinction from Tool Sets and Kits.
struct ToolRowView: View {
    @Bindable var tool: Tool
    @AppStorage("showToolThumbnails") private var showToolThumbnails = true

    @State private var thumbnail: UIImage?

    private var accessibilityDescription: String {
        var parts: [String] = [tool.name, ownershipLabel]
        if let borrowedFrom = tool.borrowedFrom, !borrowedFrom.isEmpty {
            parts.append("borrowed from \(borrowedFrom)")
        }
        return parts.joined(separator: ", ")
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 8) {
                // Thumbnail or wrench icon
                if showToolThumbnails, let thumb = thumbnail {
                    Image(uiImage: thumb)
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                        .frame(width: 40, height: 40)
                        .clipped()
                        .cornerRadius(6)
                        .accessibilityHidden(true)
                } else {
                    // Feature #137: Wrench icon for individual tools
                    Image(systemName: "wrench.fill")
                        .foregroundColor(ownershipColor)
                        .font(.body)
                        .frame(width: showToolThumbnails ? 40 : nil, height: showToolThumbnails ? 40 : nil)
                        .accessibilityHidden(true)
                }

                Text(tool.name)
                    .font(.headline)

                Spacer()

                // Ownership badge
                Text(ownershipLabel)
                    .font(.caption)
                    .fontWeight(.medium)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(ownershipColor.opacity(0.15))
                    .foregroundColor(ownershipColor)
                    .clipShape(Capsule())
            }

            if let borrowedFrom = tool.borrowedFrom, !borrowedFrom.isEmpty {
                Text("Borrowed from: \(borrowedFrom)")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            if let notes = tool.notes, !notes.isEmpty {
                Text(notes)
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .lineLimit(2)
            }
        }
        .padding(.vertical, 8)
        .frame(minHeight: 44)
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Tool: \(accessibilityDescription)")
        .accessibilityHint("Double tap to view tool details")
        .onAppear {
            if showToolThumbnails && thumbnail == nil {
                thumbnail = ToolPhotoService.shared.loadThumbnail(for: tool)
            }
        }
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
        case "personal": return Color(red: 0.145, green: 0.388, blue: 0.922) // Industrial blue
        case "shop": return Color(red: 0.392, green: 0.455, blue: 0.545)     // Steel gray
        case "borrowed": return Color(red: 0.976, green: 0.451, blue: 0.086) // Safety orange
        case "imported": return Color(red: 0.608, green: 0.318, blue: 0.878) // Imported purple
        default: return .blue
        }
    }
}

// MARK: - Borrowed Tool Row View

/// Displays a borrowed tool with prominent source attribution and optional thumbnail.
/// Visually distinguished from personal/shop tools with orange accent.
/// Row height meets 44pt minimum tap target for gloved/greasy hands.
/// Feature #137: Shows wrench icon (or thumbnail photo) for visual distinction from Tool Sets and Kits.
struct BorrowedToolRowView: View {
    @Bindable var tool: Tool
    @AppStorage("showToolThumbnails") private var showToolThumbnails = true

    @State private var thumbnail: UIImage?

    private let borrowedColor = Color(red: 0.976, green: 0.451, blue: 0.086) // Safety orange

    private var accessibilityDescription: String {
        var parts: [String] = ["Borrowed tool", tool.name]
        if let borrowedFrom = tool.borrowedFrom, !borrowedFrom.isEmpty {
            parts.append("from \(borrowedFrom)")
        }
        return parts.joined(separator: ", ")
    }

    var body: some View {
        HStack(spacing: 12) {
            // Orange accent bar
            RoundedRectangle(cornerRadius: 2)
                .fill(borrowedColor)
                .frame(width: 4)
                .accessibilityHidden(true)

            // Thumbnail or wrench icon
            if showToolThumbnails, let thumb = thumbnail {
                Image(uiImage: thumb)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .frame(width: 40, height: 40)
                    .clipped()
                    .cornerRadius(6)
                    .overlay(
                        RoundedRectangle(cornerRadius: 6)
                            .stroke(borrowedColor.opacity(0.3), lineWidth: 1)
                    )
                    .accessibilityHidden(true)
            } else {
                // Feature #137: Wrench icon for individual tools
                Image(systemName: "wrench.fill")
                    .foregroundColor(borrowedColor)
                    .font(.body)
                    .frame(width: showToolThumbnails ? 40 : nil, height: showToolThumbnails ? 40 : nil)
                    .accessibilityHidden(true)
            }

            VStack(alignment: .leading, spacing: 4) {
                Text(tool.name)
                    .font(.headline)

                // Source attribution — prominent display
                HStack(spacing: 4) {
                    Image(systemName: "person.fill")
                        .font(.caption2)
                        .foregroundColor(borrowedColor)
                    if let borrowedFrom = tool.borrowedFrom, !borrowedFrom.isEmpty {
                        Text("Borrowed from: \(borrowedFrom)")
                            .font(.subheadline)
                            .fontWeight(.medium)
                            .foregroundColor(borrowedColor)
                    } else {
                        Text("Borrowed (source unknown)")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                    }
                }

                if let notes = tool.notes, !notes.isEmpty {
                    Text(notes)
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .lineLimit(2)
                }
            }

            Spacer()

            // Borrowed badge
            Text("Borrowed")
                .font(.caption)
                .fontWeight(.medium)
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(borrowedColor.opacity(0.15))
                .foregroundColor(borrowedColor)
                .clipShape(Capsule())
        }
        .padding(.vertical, 8)
        .frame(minHeight: 44)
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
        .accessibilityLabel(accessibilityDescription)
        .accessibilityHint("Double tap to view tool details")
        .onAppear {
            if showToolThumbnails && thumbnail == nil {
                thumbnail = ToolPhotoService.shared.loadThumbnail(for: tool)
            }
        }
    }
}

// MARK: - Consumable Row View

/// Displays a single consumable in the list with name, category badge, and details.
/// Row height meets 44pt minimum tap target for gloved/greasy hands.
struct ConsumableRowView: View {
    @Bindable var consumable: Consumable

    private var accessibilityDescription: String {
        var parts: [String] = [consumable.name, categoryLabel]
        if let size = consumable.size, !size.isEmpty {
            parts.append("size \(size)")
        }
        if let spec = consumable.spec, !spec.isEmpty {
            parts.append("spec \(spec)")
        }
        return parts.joined(separator: ", ")
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(consumable.name)
                    .font(.headline)

                Spacer()

                // Category badge
                Text(categoryLabel)
                    .font(.caption)
                    .fontWeight(.medium)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(Color(red: 0.145, green: 0.388, blue: 0.922).opacity(0.15))
                    .foregroundColor(Color(red: 0.145, green: 0.388, blue: 0.922))
                    .clipShape(Capsule())
            }

            // Size and spec on one line if present
            let details = [
                consumable.size.map { "Size: \($0)" },
                consumable.spec.map { "Spec: \($0)" }
            ].compactMap { $0 }

            if !details.isEmpty {
                Text(details.joined(separator: " | "))
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            if let notes = consumable.notes, !notes.isEmpty {
                Text(notes)
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .lineLimit(2)
            }
        }
        .padding(.vertical, 8)
        .frame(minHeight: 44)
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Consumable: \(accessibilityDescription)")
        .accessibilityHint("Double tap to edit")
    }

    private var categoryLabel: String {
        switch consumable.category {
        case "safety_wire": return "Safety Wire"
        case "cotter_pin": return "Cotter Pin"
        case "o_ring": return "O-Ring"
        case "seal": return "Seal"
        case "other": return "Other"
        default: return consumable.category.capitalized
        }
    }
}

// MARK: - Chemical Row View

/// Displays a single chemical in the list with name, category badge, and details.
/// Row height meets 44pt minimum tap target for gloved/greasy hands.
struct ChemicalRowView: View {
    @Bindable var chemical: Chemical

    private var accessibilityDescription: String {
        var parts: [String] = [chemical.name, categoryLabel]
        if let size = chemical.size, !size.isEmpty {
            parts.append("size \(size)")
        }
        if let spec = chemical.spec, !spec.isEmpty {
            parts.append("spec \(spec)")
        }
        return parts.joined(separator: ", ")
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(chemical.name)
                    .font(.headline)

                Spacer()

                // Category badge
                Text(categoryLabel)
                    .font(.caption)
                    .fontWeight(.medium)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(categoryColor.opacity(0.15))
                    .foregroundColor(categoryColor)
                    .clipShape(Capsule())
            }

            // Size and spec on one line if present
            let details = [
                chemical.size.map { "Size: \($0)" },
                chemical.spec.map { "Spec: \($0)" }
            ].compactMap { $0 }

            if !details.isEmpty {
                Text(details.joined(separator: " | "))
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            if let notes = chemical.notes, !notes.isEmpty {
                Text(notes)
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .lineLimit(2)
            }
        }
        .padding(.vertical, 8)
        .frame(minHeight: 44)
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Chemical: \(accessibilityDescription)")
        .accessibilityHint("Double tap to edit")
    }

    private var categoryLabel: String {
        switch chemical.category {
        case "fluid": return "Fluid"
        case "lubricant": return "Lubricant"
        case "cleaner": return "Cleaner"
        case "sealant": return "Sealant"
        case "other": return "Other"
        default: return chemical.category.capitalized
        }
    }

    private var categoryColor: Color {
        switch chemical.category {
        case "fluid": return Color(red: 0.145, green: 0.388, blue: 0.922) // Industrial blue
        case "lubricant": return Color(red: 0.976, green: 0.451, blue: 0.086) // Safety orange
        case "cleaner": return Color(red: 0.133, green: 0.773, blue: 0.369) // Green
        case "sealant": return Color(red: 0.392, green: 0.455, blue: 0.545) // Steel gray
        default: return Color(red: 0.392, green: 0.455, blue: 0.545)
        }
    }
}

// MARK: - Tool Kit Row View

/// Displays a tool kit in the list with name, tool count, ownership badge, and description.
/// Feature #132: Shows ownership badge (Personal/Shop) to indicate kit ownership type.
struct ToolKitRowView: View {
    @Bindable var toolKit: ToolKit
    @AppStorage("showToolThumbnails") private var showToolThumbnails = true

    @State private var thumbnail: UIImage?

    private let kitColor = Color(red: 0.133, green: 0.545, blue: 0.133) // Green
    private let industrialBlue = Color(red: 0.145, green: 0.388, blue: 0.922)
    private let steelGray = Color(red: 0.392, green: 0.455, blue: 0.545)

    /// Tools in this kit, sorted by size then name
    private var kitTools: [Tool] {
        guard let tools = toolKit.tools else { return [] }
        return Array(tools).sortedBySize()
    }

    /// Feature #132: Ownership label
    private var ownershipLabel: String {
        switch toolKit.ownershipType {
        case "personal": return "Personal"
        case "shop": return "Shop"
        default: return "Personal"
        }
    }

    /// Feature #132: Ownership color
    private var ownershipColor: Color {
        switch toolKit.ownershipType {
        case "personal": return industrialBlue
        case "shop": return steelGray
        default: return industrialBlue
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                // Thumbnail or bag icon
                if showToolThumbnails, let thumb = thumbnail {
                    Image(uiImage: thumb)
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                        .frame(width: 32, height: 32)
                        .clipped()
                        .cornerRadius(6)
                        .accessibilityHidden(true)
                } else {
                    Image(systemName: "bag.fill")
                        .foregroundColor(kitColor)
                        .font(.body)
                        .accessibilityHidden(true)
                }

                Text(toolKit.name)
                    .font(.headline)

                Spacer()

                // Feature #132: Ownership badge
                Text(ownershipLabel)
                    .font(.caption2)
                    .fontWeight(.medium)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(ownershipColor.opacity(0.15))
                    .foregroundColor(ownershipColor)
                    .clipShape(Capsule())
                    .accessibilityIdentifier("toolKitOwnershipBadge_\(toolKit.id.uuidString)")

                // Tool count badge
                Text("\(kitTools.count) tools")
                    .font(.caption)
                    .fontWeight(.medium)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(kitColor.opacity(0.15))
                    .foregroundColor(kitColor)
                    .clipShape(Capsule())
            }

            if let description = toolKit.descriptionText, !description.isEmpty {
                Text(description)
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .lineLimit(2)
            }
        }
        .padding(.vertical, 4)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Tool kit: \(toolKit.name), \(ownershipLabel), \(kitTools.count) tools")
        .accessibilityHint("Double tap to view kit details")
        .onAppear {
            if showToolThumbnails && thumbnail == nil {
                thumbnail = ToolPhotoService.shared.loadThumbnail(forEntityID: toolKit.id)
            }
        }
    }
}

// MARK: - Tool Kit Detail View

/// Shows the full details of a tool kit and lists all tools in it.
/// Feature #113: Allows removing individual tools from the kit via swipe or button.
/// The tool remains in the Garage inventory, only the kit association is removed.
/// Feature #132: Displays kit ownership type (Personal/Shop).
struct ToolKitDetailView: View {
    @Environment(\.modelContext) private var viewContext
    @Bindable var toolKit: ToolKit

    private let kitColor = Color(red: 0.133, green: 0.545, blue: 0.133) // Green
    private let industrialBlue = Color(red: 0.145, green: 0.388, blue: 0.922)
    private let steelGray = Color(red: 0.392, green: 0.455, blue: 0.545)

    // Photos
    @State private var heroPhoto: UIImage?

    // Feature #113: State for remove confirmation dialog
    @State private var toolToRemove: Tool?

    // Feature #139: State for editing kit
    @State private var showingEditKit = false
    @State private var showingRemoveConfirmation = false
    @State private var showingRemoveSuccess = false
    @State private var removedToolName = ""

    /// Tools in this kit, sorted by size then name
    private var kitTools: [Tool] {
        guard let tools = toolKit.tools else { return [] }
        return Array(tools).sortedBySize()
    }

    /// Feature #132: Ownership label
    private var ownershipLabel: String {
        switch toolKit.ownershipType {
        case "personal": return "Personal"
        case "shop": return "Shop"
        default: return "Personal"
        }
    }

    /// Feature #132: Ownership color
    private var ownershipColor: Color {
        switch toolKit.ownershipType {
        case "personal": return industrialBlue
        case "shop": return steelGray
        default: return industrialBlue
        }
    }

    var body: some View {
        List {
            // Hero Photo Section
            if let photo = heroPhoto {
                Section {
                    Image(uiImage: photo)
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .frame(maxHeight: 200)
                        .frame(maxWidth: .infinity)
                        .clipped()
                        .cornerRadius(10)
                        .listRowInsets(EdgeInsets(top: 8, leading: 16, bottom: 8, trailing: 16))
                }
            }

            // Kit Info Section
            Section {
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Image(systemName: "bag.fill")
                            .foregroundColor(kitColor)
                            .font(.title2)
                        Text(toolKit.name)
                            .font(.title2)
                            .fontWeight(.bold)
                    }

                    if let description = toolKit.descriptionText, !description.isEmpty {
                        Text(description)
                            .font(.body)
                            .foregroundColor(.secondary)
                    }

                    // Feature #132: Ownership display
                    HStack {
                        Text("Ownership:")
                            .font(.caption)
                            .foregroundColor(.secondary)
                        Text(ownershipLabel)
                            .font(.caption)
                            .fontWeight(.medium)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(ownershipColor.opacity(0.15))
                            .foregroundColor(ownershipColor)
                            .clipShape(Capsule())
                            .accessibilityIdentifier("toolKitDetailOwnership")
                    }

                    HStack {
                        Text("Created:")
                            .font(.caption)
                            .foregroundColor(.secondary)
                            Text(toolKit.createdAt, style: .date)
                                .font(.caption)
                                .foregroundColor(.secondary)
                    }
                }
                .padding(.vertical, 4)
            }

            // Tools Section
            Section {
                if kitTools.isEmpty {
                    Text("No tools in this kit yet")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                        .padding(.vertical, 4)
                        .accessibilityIdentifier("toolKitEmptyState")
                } else {
                    ForEach(kitTools, id: \.id) { tool in
                        NavigationLink(destination: ToolDetailView(tool: tool).modelContainer(for: [FROTool.self, FROJob.self, FROToolGroup.self, FROToolKit.self, FROConsumable.self, FROChemical.self, FROPart.self], inMemory: true)) {
                            HStack {
                                Image(systemName: "wrench.fill")
                                    .foregroundColor(industrialBlue)
                                    .font(.caption)

                                VStack(alignment: .leading, spacing: 2) {
                                    Text(tool.name)
                                        .font(.body)

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
                        .accessibilityIdentifier("toolKitToolRow_\(tool.id.uuidString)")
                        // Feature #113: Swipe to remove tool from kit
                        .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                            Button(role: .destructive) {
                                toolToRemove = tool
                                showingRemoveConfirmation = true
                            } label: {
                                Label("Remove", systemImage: "minus.circle")
                            }
                            .tint(Color(red: 0.976, green: 0.451, blue: 0.086)) // Safety orange
                            .accessibilityIdentifier("removeToolFromKit_\(tool.id.uuidString)")
                        }
                        // Feature #113: Context menu with remove option
                        .contextMenu {
                            Button(role: .destructive) {
                                toolToRemove = tool
                                showingRemoveConfirmation = true
                            } label: {
                                Label("Remove from Kit", systemImage: "minus.circle")
                            }
                            .accessibilityIdentifier("contextMenuRemoveFromKit_\(tool.id.uuidString)")
                        }
                    }
                }
            } header: {
                HStack(spacing: 6) {
                    Image(systemName: "wrench.and.screwdriver")
                        .foregroundColor(industrialBlue)
                    Text("Tools in Kit")
                        .foregroundColor(industrialBlue)
                    Text("(\(kitTools.count))")
                        .foregroundColor(.secondary)
                        .accessibilityIdentifier("toolKitToolCount")
                }
                .font(.subheadline)
                .fontWeight(.semibold)
            } footer: {
                // Feature #113: Helpful hint about removal
                Text("Swipe left on a tool to remove it from this kit. The tool will remain in your Garage.")
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .accessibilityIdentifier("toolKitRemoveHint")
            }
        }
        .listStyle(.insetGrouped)
        .navigationTitle("Tool Kit")
        .navigationBarTitleDisplayMode(.inline)
        // Feature #139: Toolbar button to edit kit
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                Button(action: { showingEditKit = true }) {
                    Image(systemName: "pencil")
                        .font(.body)
                }
                .accessibilityLabel("Edit Tool Kit")
                .accessibilityIdentifier("editToolKitButton")
            }
        }
        .onAppear {
            if heroPhoto == nil {
                heroPhoto = ToolPhotoService.shared.loadPhoto(for: toolKit.id, at: 0)
            }
        }
        // Feature #139: Sheet for editing kit
        .sheet(isPresented: $showingEditKit) {
            EditToolKitView(toolKit: toolKit)
                .modelContainer(for: [FROTool.self, FROJob.self, FROToolGroup.self, FROToolKit.self, FROConsumable.self, FROChemical.self, FROPart.self], inMemory: true)
        }
        .onChange(of: showingEditKit) { _, isShowing in
            // Reload hero photo after editing (user may have changed photos)
            if !isShowing {
                heroPhoto = ToolPhotoService.shared.loadPhoto(for: toolKit.id, at: 0)
            }
        }
        // Feature #113: Confirmation dialog before removing tool from kit
        .alert("Remove Tool from Kit?", isPresented: $showingRemoveConfirmation) {
            Button("Cancel", role: .cancel) {
                toolToRemove = nil
            }
            Button("Remove", role: .destructive) {
                if let tool = toolToRemove {
                    removeToolFromKit(tool)
                }
            }
            .accessibilityIdentifier("confirmRemoveToolButton")
        } message: {
            Text("'\(toolToRemove?.name ?? "this tool")' will be removed from '\(toolKit.name)'. The tool will remain in your Garage inventory.")
        }
        // Feature #113: Success feedback after removal
        .alert("Tool Removed", isPresented: $showingRemoveSuccess) {
            Button("OK") { }
        } message: {
            Text("'\(removedToolName)' has been removed from this kit. It's still in your Garage.")
        }
    }

    // MARK: - Feature #113: Remove Tool from Kit

    /// Removes a tool from this kit's association without deleting the tool.
    /// The tool remains in the Garage inventory.
    private func removeToolFromKit(_ tool: Tool) {
        let toolName = tool.name
        let kitName = toolKit.name

        // Remove the relationship (tool stays in Garage, just removed from kit)
        toolKit.tools = toolKit.tools?.filter { $0.id != tool.id }

        do {
            try viewContext.save()
            print("ToolKitDetailView: Removed tool '\(toolName)' from kit '\(kitName)'")
            removedToolName = toolName
            toolToRemove = nil
            showingRemoveSuccess = true
        } catch {
            print("ToolKitDetailView: Failed to remove tool '\(toolName)' from kit '\(kitName)', rolled back - \(error)")
            toolToRemove = nil
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
        case "personal": return industrialBlue
        case "shop": return Color(red: 0.392, green: 0.455, blue: 0.545)
        case "borrowed": return Color(red: 0.976, green: 0.451, blue: 0.086)
        case "imported": return Color(red: 0.608, green: 0.318, blue: 0.878)
        default: return .blue
        }
    }
}

#Preview {
    GarageView()
        .modelContainer(for: [FROTool.self, FROJob.self, FROToolGroup.self, FROToolKit.self, FROConsumable.self, FROChemical.self, FROPart.self], inMemory: true)
}

import SwiftUI
import CoreData

/// Garage hub view — shows tools, consumables, and chemicals.
/// All three sections have full CRUD support.
struct GarageView: View {
    @Environment(\.managedObjectContext) private var viewContext

    /// Fetch all tools sorted by name
    @FetchRequest(
        sortDescriptors: [NSSortDescriptor(keyPath: \Tool.name, ascending: true)],
        animation: .default
    )
    private var tools: FetchedResults<Tool>

    /// Fetch all consumables sorted by name
    @FetchRequest(
        sortDescriptors: [NSSortDescriptor(keyPath: \Consumable.name, ascending: true)],
        animation: .default
    )
    private var consumables: FetchedResults<Consumable>

    /// Fetch all chemicals sorted by name
    @FetchRequest(
        sortDescriptors: [NSSortDescriptor(keyPath: \Chemical.name, ascending: true)],
        animation: .default
    )
    private var chemicals: FetchedResults<Chemical>

    /// Fetch all tool groups sorted by sortOrder
    @FetchRequest(
        sortDescriptors: [
            NSSortDescriptor(keyPath: \ToolGroup.sortOrder, ascending: true),
            NSSortDescriptor(keyPath: \ToolGroup.name, ascending: true)
        ],
        animation: .default
    )
    private var allToolGroups: FetchedResults<ToolGroup>

    /// Fetch all tool kits sorted by name
    @FetchRequest(
        sortDescriptors: [NSSortDescriptor(keyPath: \ToolKit.name, ascending: true)],
        animation: .default
    )
    private var toolKits: FetchedResults<ToolKit>

    @State private var showingAddTool = false
    @State private var showingAddToolKit = false
    @State private var showingAddConsumable = false
    @State private var showingAddChemical = false
    @State private var showingAddToolGroup = false
    @State private var addGroupParent: ToolGroup?
    @State private var toolToEdit: Tool?
    @State private var consumableToEdit: Consumable?
    @State private var chemicalToEdit: Chemical?
    @State private var selectedSegment: Int

    // Delete confirmation and feedback state
    @State private var toolToDelete: Tool?
    @State private var showingDeleteToolConfirmation = false
    @State private var showingDeleteToolSuccess = false
    @State private var deletedToolName = ""

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
                        .background(Color(red: 0.976, green: 0.451, blue: 0.086).opacity(0.1))
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
            .navigationTitle("Garage")
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    if selectedSegment == 0 {
                        Menu {
                            Button(action: { showingAddTool = true }) {
                                Label("Add Tool", systemImage: "wrench")
                            }
                            Button(action: {
                                addGroupParent = nil
                                showingAddToolGroup = true
                            }) {
                                Label("Add Tool Group", systemImage: "folder.badge.plus")
                            }
                            Button(action: { showingAddToolKit = true }) {
                                Label("Add Tool Kit", systemImage: "bag.badge.plus")
                            }
                        } label: {
                            Image(systemName: "plus")
                                .font(.title3)
                        }
                        .accessibilityLabel("Add Tool, Group, or Kit")
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
                    .environment(\.managedObjectContext, viewContext)
            }
            .sheet(isPresented: $showingAddConsumable) {
                AddConsumableView()
                    .environment(\.managedObjectContext, viewContext)
            }
            .sheet(isPresented: $showingAddChemical) {
                AddChemicalView()
                    .environment(\.managedObjectContext, viewContext)
            }
            .sheet(item: $toolToEdit) { tool in
                EditToolView(tool: tool)
                    .environment(\.managedObjectContext, viewContext)
            }
            .sheet(item: $consumableToEdit) { consumable in
                EditConsumableView(consumable: consumable)
                    .environment(\.managedObjectContext, viewContext)
            }
            .sheet(item: $chemicalToEdit) { chemical in
                EditChemicalView(chemical: chemical)
                    .environment(\.managedObjectContext, viewContext)
            }
            .sheet(isPresented: $showingAddToolGroup) {
                AddToolGroupView(parentGroup: addGroupParent)
                    .environment(\.managedObjectContext, viewContext)
            }
            .sheet(isPresented: $showingAddToolKit) {
                AddToolKitView()
                    .environment(\.managedObjectContext, viewContext)
            }
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
                Text("Are you sure you want to delete '\(toolToDelete?.name ?? "this tool")'? This action cannot be undone.")
            }
            .alert("Tool Deleted", isPresented: $showingDeleteToolSuccess) {
                Button("OK") { }
            } message: {
                Text("'\(deletedToolName)' has been removed from your Garage.")
            }
        }
    }

    // MARK: - Tools Section

    /// Borrowed tools filtered from the full tools list
    private var borrowedTools: [Tool] {
        tools.filter { $0.ownershipType == "borrowed" }
    }

    /// Non-borrowed tools (personal + shop) that are NOT in any group
    private var ungroupedOwnedTools: [Tool] {
        tools.filter { $0.ownershipType != "borrowed" && $0.group == nil }
    }

    /// Non-borrowed tools (personal + shop)
    private var ownedTools: [Tool] {
        tools.filter { $0.ownershipType != "borrowed" }
    }

    /// Top-level tool groups (no parent)
    private var topLevelGroups: [ToolGroup] {
        allToolGroups.filter { $0.parentGroup == nil }
    }

    private var toolsSection: some View {
        Group {
            if tools.isEmpty && topLevelGroups.isEmpty {
                VStack(spacing: 16) {
                    Spacer()
                    Image(systemName: "wrench.and.screwdriver")
                        .font(.system(size: 60))
                        .foregroundColor(Color(red: 0.392, green: 0.455, blue: 0.545)) // Steel gray
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
                List {
                    // Borrowed Tools Tracker section — visually distinguished
                    if !borrowedTools.isEmpty {
                        Section {
                            ForEach(borrowedTools, id: \.objectID) { tool in
                                NavigationLink(destination: ToolDetailView(tool: tool).environment(\.managedObjectContext, viewContext)) {
                                    BorrowedToolRowView(tool: tool)
                                }
                                .swipeActions(edge: .leading) {
                                    Button {
                                        toolToEdit = tool
                                    } label: {
                                        Label("Edit", systemImage: "pencil")
                                    }
                                    .tint(.blue)
                                }
                            }
                            .onDelete(perform: deleteBorrowedTools)

                            // Purchase Justification link
                            NavigationLink(destination: PurchaseJustificationView().environment(\.managedObjectContext, viewContext)) {
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
                        } header: {
                            HStack(spacing: 6) {
                                Image(systemName: "arrow.left.arrow.right")
                                    .foregroundColor(Color(red: 0.976, green: 0.451, blue: 0.086)) // Safety orange
                                Text("Borrowed Tools")
                                    .foregroundColor(Color(red: 0.976, green: 0.451, blue: 0.086))
                                Text("(\(borrowedTools.count))")
                                    .foregroundColor(.secondary)
                            }
                            .font(.subheadline)
                            .fontWeight(.semibold)
                        }
                    }

                    // Tool Groups section — nested hierarchy
                    if !topLevelGroups.isEmpty {
                        Section {
                            ForEach(topLevelGroups, id: \.objectID) { group in
                                ToolGroupRowView(
                                    group: group,
                                    viewContext: viewContext,
                                    onEditTool: { tool in toolToEdit = tool },
                                    onAddSubGroup: { parent in
                                        addGroupParent = parent
                                        showingAddToolGroup = true
                                    },
                                    onAddToolToGroup: { parent in
                                        // For now, use the standard add tool flow
                                        showingAddTool = true
                                    }
                                )
                            }
                            .onDelete(perform: deleteTopLevelGroups)
                        } header: {
                            HStack(spacing: 6) {
                                Image(systemName: "folder.fill")
                                    .foregroundColor(Color(red: 0.145, green: 0.388, blue: 0.922)) // Industrial blue
                                Text("Tool Groups")
                                    .foregroundColor(Color(red: 0.145, green: 0.388, blue: 0.922))
                                Text("(\(topLevelGroups.count))")
                                    .foregroundColor(.secondary)
                            }
                            .font(.subheadline)
                            .fontWeight(.semibold)
                        }
                    }

                    // Tool Kits section — named collections of tools for specific jobs
                    if !toolKits.isEmpty {
                        Section {
                            ForEach(toolKits, id: \.objectID) { kit in
                                NavigationLink(destination: ToolKitDetailView(toolKit: kit).environment(\.managedObjectContext, viewContext)) {
                                    ToolKitRowView(toolKit: kit)
                                }
                            }
                            .onDelete(perform: deleteToolKits)
                        } header: {
                            HStack(spacing: 6) {
                                Image(systemName: "bag.fill")
                                    .foregroundColor(Color(red: 0.133, green: 0.545, blue: 0.133)) // Green
                                Text("Tool Kits")
                                    .foregroundColor(Color(red: 0.133, green: 0.545, blue: 0.133))
                                Text("(\(toolKits.count))")
                                    .foregroundColor(.secondary)
                            }
                            .font(.subheadline)
                            .fontWeight(.semibold)
                        }
                    }

                    // Ungrouped My Tools section (personal + shop, not in any group)
                    Section {
                        if ungroupedOwnedTools.isEmpty && topLevelGroups.isEmpty {
                            Text("No personal or shop tools yet")
                                .font(.subheadline)
                                .foregroundColor(.secondary)
                                .padding(.vertical, 4)
                        } else if ungroupedOwnedTools.isEmpty {
                            Text("All tools are organized in groups")
                                .font(.subheadline)
                                .foregroundColor(.secondary)
                                .padding(.vertical, 4)
                        } else {
                            ForEach(ungroupedOwnedTools, id: \.objectID) { tool in
                                NavigationLink(destination: ToolDetailView(tool: tool).environment(\.managedObjectContext, viewContext)) {
                                    ToolRowView(tool: tool)
                                }
                                .swipeActions(edge: .leading) {
                                    Button {
                                        toolToEdit = tool
                                    } label: {
                                        Label("Edit", systemImage: "pencil")
                                    }
                                    .tint(.blue)
                                }
                            }
                            .onDelete(perform: deleteUngroupedOwnedTools)
                        }
                    } header: {
                        HStack(spacing: 6) {
                            Image(systemName: "wrench.and.screwdriver")
                                .foregroundColor(Color(red: 0.145, green: 0.388, blue: 0.922)) // Industrial blue
                            Text("My Tools")
                                .foregroundColor(Color(red: 0.145, green: 0.388, blue: 0.922))
                            Text("(\(ungroupedOwnedTools.count))")
                                .foregroundColor(.secondary)
                        }
                        .font(.subheadline)
                        .fontWeight(.semibold)
                    }
                }
                .listStyle(.insetGrouped)
            }
        }
    }

    // MARK: - Consumables Section

    /// All consumable category keys in display order
    private let consumableCategoryOrder = ["safety_wire", "cotter_pin", "o_ring", "seal", "other"]

    /// Group consumables by category
    private var consumablesByCategory: [String: [Consumable]] {
        var grouped: [String: [Consumable]] = [:]
        for consumable in consumables {
            let category = consumable.category ?? "other"
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
                                ForEach(categoryConsumables, id: \.objectID) { consumable in
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
                                ForEach(categoryConsumables, id: \.objectID) { consumable in
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
            let name = consumable.name ?? "unknown"
            viewContext.delete(consumable)
            print("GarageView: Deleted consumable '\(name)' from category '\(category)'")
        }
        do {
            try viewContext.save()
        } catch {
            viewContext.rollback()
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
            let category = chemical.category ?? "other"
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
                                ForEach(categoryChemicals, id: \.objectID) { chemical in
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
                                ForEach(categoryChemicals, id: \.objectID) { chemical in
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
            let name = chemical.name ?? "unknown"
            viewContext.delete(chemical)
            print("GarageView: Deleted chemical '\(name)' from category '\(category)'")
        }
        do {
            try viewContext.save()
        } catch {
            viewContext.rollback()
            print("GarageView: Failed to delete chemical, rolled back - \(error)")
        }
    }

    // MARK: - Actions

    /// Perform actual tool deletion after confirmation
    private func performToolDeletion(_ tool: Tool) {
        let name = tool.name ?? "unknown"
        viewContext.delete(tool)
        do {
            try viewContext.save()
            print("GarageView: Deleted tool '\(name)' from Core Data")
            deletedToolName = name
            toolToDelete = nil
            showingDeleteToolSuccess = true
        } catch {
            viewContext.rollback()
            print("GarageView: Failed to delete tool '\(name)', rolled back - \(error)")
            toolToDelete = nil
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
            viewContext.rollback()
            print("GarageView: Failed to delete tool, rolled back - \(error)")
        }
    }

    /// Delete from the borrowed tools subsection (with confirmation)
    private func deleteBorrowedTools(at offsets: IndexSet) {
        requestDeleteBorrowedTool(at: offsets)
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
            viewContext.rollback()
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
            viewContext.rollback()
            print("GarageView: Failed to delete tool group, rolled back - \(error)")
        }
    }

    /// Delete tool kits
    private func deleteToolKits(at offsets: IndexSet) {
        for index in offsets {
            let kit = toolKits[index]
            let name = kit.name ?? "unknown"
            viewContext.delete(kit)
            print("GarageView: Deleted tool kit '\(name)'")
        }
        do {
            try viewContext.save()
        } catch {
            viewContext.rollback()
            print("GarageView: Failed to delete tool kit, rolled back - \(error)")
        }
    }

}

// MARK: - Tool Group Row View (Recursive, supports nested hierarchy)

/// Displays a tool group with expand/collapse, showing child groups and tools.
/// Supports arbitrary nesting depth.
struct ToolGroupRowView: View {
    @ObservedObject var group: ToolGroup
    var viewContext: NSManagedObjectContext
    var onEditTool: (Tool) -> Void
    var onAddSubGroup: (ToolGroup) -> Void
    var onAddToolToGroup: (ToolGroup) -> Void

    @State private var isExpanded: Bool = true

    /// Sorted child groups
    private var childGroups: [ToolGroup] {
        guard let children = group.childGroups as? Set<ToolGroup> else { return [] }
        return children.sorted { g1, g2 in
            if g1.sortOrder != g2.sortOrder {
                return g1.sortOrder < g2.sortOrder
            }
            return (g1.name ?? "") < (g2.name ?? "")
        }
    }

    /// Tools directly in this group
    private var groupTools: [Tool] {
        guard let tools = group.tools as? Set<Tool> else { return [] }
        return tools.sorted { ($0.name ?? "") < ($1.name ?? "") }
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
        var count = (group.tools as? Set<Tool>)?.count ?? 0
        if let children = group.childGroups as? Set<ToolGroup> {
            for child in children {
                count += countTools(in: child)
            }
        }
        return count
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Group header row with expand/collapse
            Button(action: { withAnimation(.easeInOut(duration: 0.2)) { isExpanded.toggle() } }) {
                HStack(spacing: 8) {
                    Image(systemName: isExpanded ? "chevron.down" : "chevron.right")
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .frame(width: 16)

                    Image(systemName: "folder.fill")
                        .foregroundColor(Color(red: 0.145, green: 0.388, blue: 0.922))
                        .font(.body)

                    Text(group.name ?? "Unnamed Group")
                        .font(.headline)
                        .foregroundColor(.primary)

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
            }
            .buttonStyle(.plain)
            .contextMenu {
                Button(action: { onAddSubGroup(group) }) {
                    Label("Add Sub-Group", systemImage: "folder.badge.plus")
                }
            }

            // Expanded content
            if isExpanded {
                VStack(alignment: .leading, spacing: 0) {
                    // Child groups (recursive)
                    ForEach(childGroups, id: \.objectID) { childGroup in
                        ToolGroupRowView(
                            group: childGroup,
                            viewContext: viewContext,
                            onEditTool: onEditTool,
                            onAddSubGroup: onAddSubGroup,
                            onAddToolToGroup: onAddToolToGroup
                        )
                        .padding(.leading, 20)
                    }

                    // Tools in this group
                    ForEach(groupTools, id: \.objectID) { tool in
                        NavigationLink(destination: ToolDetailView(tool: tool).environment(\.managedObjectContext, viewContext)) {
                            ToolRowView(tool: tool)
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
                    }
                }
            }
        }
    }
}

// MARK: - Tool Row View

/// Displays a single tool in the list with name, ownership badge, and notes.
/// Row height meets 44pt minimum tap target for gloved/greasy hands.
struct ToolRowView: View {
    @ObservedObject var tool: Tool

    private var accessibilityDescription: String {
        var parts: [String] = [tool.name ?? "Unnamed Tool", ownershipLabel]
        if let borrowedFrom = tool.borrowedFrom, !borrowedFrom.isEmpty {
            parts.append("borrowed from \(borrowedFrom)")
        }
        return parts.joined(separator: ", ")
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(tool.name ?? "Unnamed Tool")
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
    }

    private var ownershipLabel: String {
        switch tool.ownershipType {
        case "personal": return "Personal"
        case "shop": return "Shop"
        case "borrowed": return "Borrowed"
        default: return "Personal"
        }
    }

    private var ownershipColor: Color {
        switch tool.ownershipType {
        case "personal": return Color(red: 0.145, green: 0.388, blue: 0.922) // Industrial blue
        case "shop": return Color(red: 0.392, green: 0.455, blue: 0.545)     // Steel gray
        case "borrowed": return Color(red: 0.976, green: 0.451, blue: 0.086) // Safety orange
        default: return .blue
        }
    }
}

// MARK: - Borrowed Tool Row View

/// Displays a borrowed tool with prominent source attribution.
/// Visually distinguished from personal/shop tools with orange accent.
/// Row height meets 44pt minimum tap target for gloved/greasy hands.
struct BorrowedToolRowView: View {
    @ObservedObject var tool: Tool

    private let borrowedColor = Color(red: 0.976, green: 0.451, blue: 0.086) // Safety orange

    private var accessibilityDescription: String {
        var parts: [String] = ["Borrowed tool", tool.name ?? "Unnamed Tool"]
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

            VStack(alignment: .leading, spacing: 4) {
                Text(tool.name ?? "Unnamed Tool")
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
    }
}

// MARK: - Consumable Row View

/// Displays a single consumable in the list with name, category badge, and details.
/// Row height meets 44pt minimum tap target for gloved/greasy hands.
struct ConsumableRowView: View {
    @ObservedObject var consumable: Consumable

    private var accessibilityDescription: String {
        var parts: [String] = [consumable.name ?? "Unnamed Consumable", categoryLabel]
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
                Text(consumable.name ?? "Unnamed Consumable")
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
        default: return consumable.category?.capitalized ?? "Other"
        }
    }
}

// MARK: - Chemical Row View

/// Displays a single chemical in the list with name, category badge, and details.
/// Row height meets 44pt minimum tap target for gloved/greasy hands.
struct ChemicalRowView: View {
    @ObservedObject var chemical: Chemical

    private var accessibilityDescription: String {
        var parts: [String] = [chemical.name ?? "Unnamed Chemical", categoryLabel]
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
                Text(chemical.name ?? "Unnamed Chemical")
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
        default: return chemical.category?.capitalized ?? "Other"
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

/// Displays a tool kit in the list with name, tool count, and description.
struct ToolKitRowView: View {
    @ObservedObject var toolKit: ToolKit

    private let kitColor = Color(red: 0.133, green: 0.545, blue: 0.133) // Green

    /// Tools in this kit
    private var kitTools: [Tool] {
        guard let tools = toolKit.tools as? Set<Tool> else { return [] }
        return tools.sorted { ($0.name ?? "") < ($1.name ?? "") }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Image(systemName: "bag.fill")
                    .foregroundColor(kitColor)
                    .font(.body)
                    .accessibilityHidden(true)

                Text(toolKit.name ?? "Unnamed Kit")
                    .font(.headline)

                Spacer()

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
        .accessibilityLabel("Tool kit: \(toolKit.name ?? "Unnamed Kit"), \(kitTools.count) tools")
        .accessibilityHint("Double tap to view kit details")
    }
}

// MARK: - Tool Kit Detail View

/// Shows the full details of a tool kit and lists all tools in it.
struct ToolKitDetailView: View {
    @Environment(\.managedObjectContext) private var viewContext
    @ObservedObject var toolKit: ToolKit

    private let kitColor = Color(red: 0.133, green: 0.545, blue: 0.133) // Green
    private let industrialBlue = Color(red: 0.145, green: 0.388, blue: 0.922)

    /// Tools in this kit, sorted by name
    private var kitTools: [Tool] {
        guard let tools = toolKit.tools as? Set<Tool> else { return [] }
        return tools.sorted { ($0.name ?? "") < ($1.name ?? "") }
    }

    var body: some View {
        List {
            // Kit Info Section
            Section {
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Image(systemName: "bag.fill")
                            .foregroundColor(kitColor)
                            .font(.title2)
                        Text(toolKit.name ?? "Unnamed Kit")
                            .font(.title2)
                            .fontWeight(.bold)
                    }

                    if let description = toolKit.descriptionText, !description.isEmpty {
                        Text(description)
                            .font(.body)
                            .foregroundColor(.secondary)
                    }

                    HStack {
                        Text("Created:")
                            .font(.caption)
                            .foregroundColor(.secondary)
                        if let createdAt = toolKit.createdAt {
                            Text(createdAt, style: .date)
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
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
                } else {
                    ForEach(kitTools, id: \.objectID) { tool in
                        NavigationLink(destination: ToolDetailView(tool: tool).environment(\.managedObjectContext, viewContext)) {
                            HStack {
                                Image(systemName: "wrench.fill")
                                    .foregroundColor(industrialBlue)
                                    .font(.caption)

                                VStack(alignment: .leading, spacing: 2) {
                                    Text(tool.name ?? "Unnamed Tool")
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
                }
                .font(.subheadline)
                .fontWeight(.semibold)
            }
        }
        .listStyle(.insetGrouped)
        .navigationTitle("Tool Kit")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func ownershipLabel(for tool: Tool) -> String {
        switch tool.ownershipType {
        case "personal": return "Personal"
        case "shop": return "Shop"
        case "borrowed": return "Borrowed"
        default: return "Personal"
        }
    }

    private func ownershipColor(for tool: Tool) -> Color {
        switch tool.ownershipType {
        case "personal": return industrialBlue
        case "shop": return Color(red: 0.392, green: 0.455, blue: 0.545)
        case "borrowed": return Color(red: 0.976, green: 0.451, blue: 0.086)
        default: return .blue
        }
    }
}

#Preview {
    GarageView()
        .environment(\.managedObjectContext, PersistenceController.preview.container.viewContext)
}

import SwiftUI
import CoreData

/// View for creating a new tool kit in the Garage.
/// Allows naming the kit, adding a description, and selecting tools to include.
struct AddToolKitView: View {
    @Environment(\.managedObjectContext) private var viewContext
    @Environment(\.dismiss) private var dismiss

    @State private var name: String = ""
    @State private var descriptionText: String = ""
    @State private var selectedToolIDs: Set<NSManagedObjectID> = []
    @State private var showingToolPicker = false
    @State private var showingError = false
    @State private var errorMessage = ""

    /// Fetch all tools sorted by name for selection
    @FetchRequest(
        sortDescriptors: [NSSortDescriptor(keyPath: \Tool.name, ascending: true)],
        animation: .default
    )
    private var allTools: FetchedResults<Tool>

    private let industrialBlue = Color(red: 0.145, green: 0.388, blue: 0.922)

    var body: some View {
        NavigationStack {
            Form {
                // MARK: - Kit Name
                Section(header: Text("Kit Name")) {
                    TextField("e.g., Hydraulic Pump R&R Kit", text: $name)
                        .font(.body)
                        .autocorrectionDisabled()
                }

                // MARK: - Description
                Section(header: Text("Description (Optional)")) {
                    TextField("What is this kit used for?", text: $descriptionText, axis: .vertical)
                        .lineLimit(3...6)
                        .font(.body)
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
                        ForEach(selectedTools, id: \.objectID) { tool in
                            HStack {
                                Image(systemName: "wrench.fill")
                                    .foregroundColor(industrialBlue)
                                    .font(.caption)
                                Text(tool.name ?? "Unnamed Tool")
                                    .font(.body)
                                Spacer()
                                Button(action: { selectedToolIDs.remove(tool.objectID) }) {
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
                    Text("Tools in Kit")
                } footer: {
                    Text("Select tools to include in this kit. A tool can belong to multiple kits.")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
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
                ToolKitToolPickerView(selectedToolIDs: $selectedToolIDs)
                    .environment(\.managedObjectContext, viewContext)
            }
            .alert("Error", isPresented: $showingError) {
                Button("OK") { }
            } message: {
                Text(errorMessage)
            }
        }
    }

    // MARK: - Computed Properties

    /// Tools that are currently selected
    private var selectedTools: [Tool] {
        allTools.filter { selectedToolIDs.contains($0.objectID) }
    }

    // MARK: - Save

    private func saveToolKit() {
        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedName.isEmpty else {
            errorMessage = "Kit name cannot be empty."
            showingError = true
            return
        }

        let toolKit = ToolKit(context: viewContext)
        toolKit.id = UUID()
        toolKit.name = trimmedName
        toolKit.descriptionText = descriptionText.isEmpty ? nil : descriptionText
        toolKit.createdAt = Date()

        // Link selected tools (many-to-many relationship)
        for toolID in selectedToolIDs {
            if let tool = viewContext.object(with: toolID) as? Tool {
                toolKit.addToTools(tool)
            }
        }

        do {
            try viewContext.save()
            print("AddToolKitView: Saved tool kit '\(trimmedName)' with \(selectedToolIDs.count) tools")
            dismiss()
        } catch {
            viewContext.rollback()
            errorMessage = "Failed to save tool kit: \(error.localizedDescription)"
            showingError = true
            print("AddToolKitView: Save failed, rolled back - \(error)")
        }
    }
}

// MARK: - Tool Picker for Tool Kits

/// Multi-select tool picker for adding tools to a kit
struct ToolKitToolPickerView: View {
    @Environment(\.managedObjectContext) private var viewContext
    @Environment(\.dismiss) private var dismiss

    @Binding var selectedToolIDs: Set<NSManagedObjectID>

    @FetchRequest(
        sortDescriptors: [NSSortDescriptor(keyPath: \Tool.name, ascending: true)],
        animation: .default
    )
    private var tools: FetchedResults<Tool>

    private let industrialBlue = Color(red: 0.145, green: 0.388, blue: 0.922)

    var body: some View {
        NavigationStack {
            List {
                if tools.isEmpty {
                    Text("No tools in Garage yet.\nAdd tools first, then create a kit.")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
                        .padding()
                } else {
                    ForEach(tools, id: \.objectID) { tool in
                        Button(action: { toggleTool(tool) }) {
                            HStack {
                                Image(systemName: selectedToolIDs.contains(tool.objectID) ? "checkmark.circle.fill" : "circle")
                                    .foregroundColor(selectedToolIDs.contains(tool.objectID) ? industrialBlue : .secondary)
                                    .font(.title3)

                                VStack(alignment: .leading, spacing: 2) {
                                    Text(tool.name ?? "Unnamed Tool")
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
        if selectedToolIDs.contains(tool.objectID) {
            selectedToolIDs.remove(tool.objectID)
        } else {
            selectedToolIDs.insert(tool.objectID)
        }
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
        case "personal": return Color(red: 0.145, green: 0.388, blue: 0.922)
        case "shop": return Color(red: 0.392, green: 0.455, blue: 0.545)
        case "borrowed": return Color(red: 0.976, green: 0.451, blue: 0.086)
        default: return .blue
        }
    }
}

#Preview {
    AddToolKitView()
        .environment(\.managedObjectContext, PersistenceController.preview.container.viewContext)
}

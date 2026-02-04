import SwiftUI
import CoreData

/// View for creating a new tool group in the Garage.
/// Supports creating top-level groups or sub-groups under an existing parent.
struct AddToolGroupView: View {
    @Environment(\.managedObjectContext) private var viewContext
    @Environment(\.dismiss) private var dismiss

    @State private var name: String = ""
    @State private var showingError = false
    @State private var errorMessage = ""

    /// Optional parent group — if set, the new group will be a sub-group
    var parentGroup: ToolGroup?

    var body: some View {
        NavigationStack {
            Form {
                // MARK: - Group Name
                Section(header: Text("Group Name")) {
                    TextField("e.g., 1/4-inch Drive", text: $name)
                        .font(.body)
                        .autocorrectionDisabled()
                }

                // MARK: - Parent Info
                if let parent = parentGroup {
                    Section(header: Text("Parent Group")) {
                        HStack {
                            Image(systemName: "folder.fill")
                                .foregroundColor(Color(red: 0.145, green: 0.388, blue: 0.922))
                            Text(parent.name ?? "Unknown Group")
                                .foregroundColor(.secondary)
                        }
                    }
                }
            }
            .navigationTitle(parentGroup != nil ? "Add Sub-Group" : "Add Tool Group")
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
            errorMessage = "Group name cannot be empty."
            showingError = true
            return
        }

        let group = ToolGroup(context: viewContext)
        group.id = UUID()
        group.name = trimmedName
        group.parentGroup = parentGroup

        // Set sort order to be after existing siblings
        let siblingCount: Int
        if let parent = parentGroup {
            siblingCount = (parent.childGroups as? Set<ToolGroup>)?.count ?? 0
        } else {
            // Count existing top-level groups
            let request = NSFetchRequest<ToolGroup>(entityName: "ToolGroup")
            request.predicate = NSPredicate(format: "parentGroup == nil")
            siblingCount = (try? viewContext.count(for: request)) ?? 0
        }
        group.sortOrder = Int32(siblingCount)

        do {
            try viewContext.save()
            print("AddToolGroupView: Saved group '\(trimmedName)' to Core Data")
            dismiss()
        } catch {
            viewContext.rollback()
            errorMessage = "Failed to save group: \(error.localizedDescription)"
            showingError = true
            print("AddToolGroupView: Save failed, rolled back - \(error)")
        }
    }
}

#Preview {
    AddToolGroupView()
        .environment(\.managedObjectContext, PersistenceController.preview.container.viewContext)
}

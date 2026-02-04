import SwiftUI

/// View for editing an existing tool entry in the Garage.
/// Pre-populates fields with existing data and saves changes to Core Data.
struct EditToolView: View {
    @Environment(\.managedObjectContext) private var viewContext
    @Environment(\.dismiss) private var dismiss

    @ObservedObject var tool: Tool

    @State private var name: String = ""
    @State private var ownershipType: String = "personal"
    @State private var borrowedFrom: String = ""
    @State private var notes: String = ""
    @State private var aliasText: String = ""
    @State private var showingError = false
    @State private var errorMessage = ""
    @State private var showingSuccess = false
    @State private var savedToolName = ""

    private let ownershipOptions = ["personal", "shop", "borrowed"]

    var body: some View {
        NavigationStack {
            Form {
                // MARK: - Tool Name
                Section(header: Text("Tool Name")) {
                    TextField("e.g., 3/8\" Torque Wrench", text: $name)
                        .font(.body)
                        .autocorrectionDisabled()
                }

                // MARK: - Ownership
                Section(header: Text("Ownership")) {
                    Picker("Type", selection: $ownershipType) {
                        Text("Personal").tag("personal")
                        Text("Shop").tag("shop")
                        Text("Borrowed").tag("borrowed")
                    }
                    .pickerStyle(.segmented)

                    if ownershipType == "borrowed" {
                        TextField("Borrowed from...", text: $borrowedFrom)
                            .font(.body)
                    }
                }

                // MARK: - Aliases
                Section(header: Text("Aliases (Optional)")) {
                    TextField("e.g., Dog Bone, Torque Adapter", text: $aliasText, axis: .vertical)
                        .font(.body)
                        .lineLimit(2...4)
                    Text("Comma-separated alternate names for this tool")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }

                // MARK: - Notes
                Section(header: Text("Notes (Optional)")) {
                    TextField("Size, spec, or other notes", text: $notes, axis: .vertical)
                        .lineLimit(3...6)
                }
            }
            .navigationTitle("Edit Tool")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cancel") {
                        dismiss()
                    }
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Save") {
                        saveChanges()
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
            .alert("Tool Updated!", isPresented: $showingSuccess) {
                Button("OK") {
                    dismiss()
                }
            } message: {
                Text("'\(savedToolName)' has been updated successfully.")
            }
            .onAppear {
                // Pre-populate fields with existing tool data
                name = tool.name ?? ""
                ownershipType = tool.ownershipType ?? "personal"
                borrowedFrom = tool.borrowedFrom ?? ""
                notes = tool.notes ?? ""
                if let aliases = tool.aliases as? [String] {
                    aliasText = aliases.joined(separator: ", ")
                }
            }
        }
    }

    // MARK: - Save Changes

    private func saveChanges() {
        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedName.isEmpty else {
            errorMessage = "Tool name cannot be empty."
            showingError = true
            return
        }

        tool.name = trimmedName
        tool.ownershipType = ownershipType

        if ownershipType == "borrowed" {
            let trimmedBorrowed = borrowedFrom.trimmingCharacters(in: .whitespacesAndNewlines)
            tool.borrowedFrom = trimmedBorrowed.isEmpty ? nil : trimmedBorrowed
        } else {
            tool.borrowedFrom = nil
        }

        let trimmedNotes = notes.trimmingCharacters(in: .whitespacesAndNewlines)
        tool.notes = trimmedNotes.isEmpty ? nil : trimmedNotes

        // Parse and save aliases
        let parsedAliases = aliasText
            .split(separator: ",")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        tool.aliases = parsedAliases.isEmpty ? nil : parsedAliases as NSArray

        do {
            try viewContext.save()
            print("EditToolView: Updated tool '\(trimmedName)' (\(ownershipType)) in Core Data")
            savedToolName = trimmedName
            showingSuccess = true
        } catch {
            viewContext.rollback()
            errorMessage = "Failed to save changes: \(error.localizedDescription)"
            showingError = true
            print("EditToolView: Save failed, rolled back - \(error)")
        }
    }
}

#Preview {
    let context = PersistenceController.preview.container.viewContext
    let tool = Tool(context: context)
    tool.id = UUID()
    tool.name = "Test Wrench"
    tool.ownershipType = "personal"
    tool.notes = "Standard wrench"
    tool.createdAt = Date()

    return EditToolView(tool: tool)
        .environment(\.managedObjectContext, context)
}

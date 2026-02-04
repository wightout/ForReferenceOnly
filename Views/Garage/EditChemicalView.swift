import SwiftUI

/// View for editing an existing chemical entry in the Garage.
/// Pre-populates fields with existing data and saves changes to Core Data.
struct EditChemicalView: View {
    @Environment(\.managedObjectContext) private var viewContext
    @Environment(\.dismiss) private var dismiss

    @ObservedObject var chemical: Chemical

    @State private var name: String = ""
    @State private var category: String = "other"
    @State private var size: String = ""
    @State private var spec: String = ""
    @State private var notes: String = ""
    @State private var showingError = false
    @State private var errorMessage = ""

    private let categoryOptions: [(value: String, label: String)] = [
        ("fluid", "Fluid"),
        ("lubricant", "Lubricant"),
        ("cleaner", "Cleaner"),
        ("sealant", "Sealant"),
        ("other", "Other")
    ]

    var body: some View {
        NavigationStack {
            Form {
                // MARK: - Chemical Name
                Section(header: Text("Chemical Name")) {
                    TextField("e.g., MIL-PRF-83282", text: $name)
                        .font(.body)
                        .autocorrectionDisabled()
                }

                // MARK: - Category
                Section(header: Text("Category")) {
                    Picker("Category", selection: $category) {
                        ForEach(categoryOptions, id: \.value) { option in
                            Text(option.label).tag(option.value)
                        }
                    }
                    .pickerStyle(.menu)
                }

                // MARK: - Size / Spec
                Section(header: Text("Size & Specification")) {
                    TextField("Size (e.g., 1 quart)", text: $size)
                        .font(.body)
                        .autocorrectionDisabled()
                    TextField("Spec / Part Number (e.g., MIL-PRF-83282)", text: $spec)
                        .font(.body)
                        .autocorrectionDisabled()
                }

                // MARK: - Notes
                Section(header: Text("Notes (Optional)")) {
                    TextField("Additional notes", text: $notes, axis: .vertical)
                        .lineLimit(3...6)
                }
            }
            .navigationTitle("Edit Chemical")
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
            .onAppear {
                // Pre-populate fields with existing chemical data
                name = chemical.name ?? ""
                category = chemical.category ?? "other"
                size = chemical.size ?? ""
                spec = chemical.spec ?? ""
                notes = chemical.notes ?? ""
            }
        }
    }

    // MARK: - Save Changes

    private func saveChanges() {
        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedName.isEmpty else {
            errorMessage = "Chemical name cannot be empty."
            showingError = true
            return
        }

        chemical.name = trimmedName
        chemical.category = category

        let trimmedSize = size.trimmingCharacters(in: .whitespacesAndNewlines)
        chemical.size = trimmedSize.isEmpty ? nil : trimmedSize

        let trimmedSpec = spec.trimmingCharacters(in: .whitespacesAndNewlines)
        chemical.spec = trimmedSpec.isEmpty ? nil : trimmedSpec

        let trimmedNotes = notes.trimmingCharacters(in: .whitespacesAndNewlines)
        chemical.notes = trimmedNotes.isEmpty ? nil : trimmedNotes

        do {
            try viewContext.save()
            print("EditChemicalView: Updated chemical '\(trimmedName)' in Core Data")
            dismiss()
        } catch {
            viewContext.rollback()
            errorMessage = "Failed to save changes: \(error.localizedDescription)"
            showingError = true
            print("EditChemicalView: Save failed, rolled back - \(error)")
        }
    }
}

#Preview {
    let context = PersistenceController.preview.container.viewContext
    let chemical = Chemical(context: context)
    chemical.id = UUID()
    chemical.name = "MIL-PRF-83282"
    chemical.category = "fluid"
    chemical.size = "1 quart"
    chemical.spec = "MIL-PRF-83282"
    chemical.notes = "Synthetic hydraulic fluid"
    chemical.createdAt = Date()

    return EditChemicalView(chemical: chemical)
        .environment(\.managedObjectContext, context)
}

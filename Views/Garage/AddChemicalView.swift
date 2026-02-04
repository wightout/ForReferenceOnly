import SwiftUI

/// View for creating a new chemical entry in the Garage.
/// Saves directly to Core Data via the managed object context.
struct AddChemicalView: View {
    @Environment(\.managedObjectContext) private var viewContext
    @Environment(\.dismiss) private var dismiss

    @State private var name: String = ""
    @State private var category: String = "other"
    @State private var size: String = ""
    @State private var spec: String = ""
    @State private var notes: String = ""
    @State private var showingError = false
    @State private var errorMessage = ""
    @State private var showingSuccess = false
    @State private var savedChemicalName = ""

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
            .navigationTitle("Add Chemical")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cancel") {
                        dismiss()
                    }
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Save") {
                        saveChemical()
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
            .alert("Chemical Saved!", isPresented: $showingSuccess) {
                Button("OK") {
                    dismiss()
                }
            } message: {
                Text("'\(savedChemicalName)' has been added to your Garage.")
            }
        }
    }

    // MARK: - Save

    private func saveChemical() {
        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedName.isEmpty else {
            errorMessage = "Chemical name cannot be empty."
            showingError = true
            return
        }

        let chemical = Chemical(context: viewContext)
        chemical.id = UUID()
        chemical.name = trimmedName
        chemical.category = category
        chemical.createdAt = Date()

        let trimmedSize = size.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmedSize.isEmpty {
            chemical.size = trimmedSize
        }

        let trimmedSpec = spec.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmedSpec.isEmpty {
            chemical.spec = trimmedSpec
        }

        let trimmedNotes = notes.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmedNotes.isEmpty {
            chemical.notes = trimmedNotes
        }

        do {
            try viewContext.save()
            print("AddChemicalView: Saved chemical '\(trimmedName)' to Core Data")
            savedChemicalName = trimmedName
            showingSuccess = true
        } catch {
            viewContext.rollback()
            errorMessage = "Failed to save chemical: \(error.localizedDescription)"
            showingError = true
            print("AddChemicalView: Save failed, rolled back - \(error)")
        }
    }
}

#Preview {
    AddChemicalView()
        .environment(\.managedObjectContext, PersistenceController.preview.container.viewContext)
}

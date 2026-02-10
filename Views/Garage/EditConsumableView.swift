import SwiftUI

/// View for editing an existing consumable entry in the Garage.
/// Pre-populates fields with existing data and saves changes to Core Data.
struct EditConsumableView: View {
    @Environment(\.modelContext) private var viewContext
    @Environment(\.dismiss) private var dismiss

    @Bindable var consumable: Consumable

    @State private var name: String = ""
    @State private var category: String = "other"
    @State private var size: String = ""
    @State private var spec: String = ""
    @State private var notes: String = ""
    @State private var showingError = false
    @State private var errorMessage = ""

    private let categoryOptions: [(value: String, label: String)] = [
        ("safety_wire", "Safety Wire"),
        ("cotter_pin", "Cotter Pin"),
        ("o_ring", "O-Ring"),
        ("seal", "Seal"),
        ("other", "Other")
    ]

    var body: some View {
        NavigationStack {
            Form {
                // MARK: - Consumable Name
                Section(header: Text("Consumable Name")) {
                    TextField("e.g., MS20995C32 Safety Wire", text: $name)
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
                    TextField("Size (e.g., .032 inch)", text: $size)
                        .font(.body)
                        .autocorrectionDisabled()
                    TextField("Spec / Part Number (e.g., MS20995C32)", text: $spec)
                        .font(.body)
                        .autocorrectionDisabled()
                }

                // MARK: - Notes
                Section(header: Text("Notes (Optional)")) {
                    TextField("Additional notes", text: $notes, axis: .vertical)
                        .lineLimit(3...6)
                }
            }
            .navigationTitle("Edit Consumable")
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
                // Pre-populate fields with existing consumable data
                name = consumable.name
                category = consumable.category
                size = consumable.size ?? ""
                spec = consumable.spec ?? ""
                notes = consumable.notes ?? ""
            }
        }
    }

    // MARK: - Save Changes

    private func saveChanges() {
        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedName.isEmpty else {
            errorMessage = "Consumable name cannot be empty."
            showingError = true
            return
        }

        consumable.name = trimmedName
        consumable.category = category

        let trimmedSize = size.trimmingCharacters(in: .whitespacesAndNewlines)
        consumable.size = trimmedSize.isEmpty ? nil : trimmedSize

        let trimmedSpec = spec.trimmingCharacters(in: .whitespacesAndNewlines)
        consumable.spec = trimmedSpec.isEmpty ? nil : trimmedSpec

        let trimmedNotes = notes.trimmingCharacters(in: .whitespacesAndNewlines)
        consumable.notes = trimmedNotes.isEmpty ? nil : trimmedNotes

        do {
            try viewContext.save()
            print("EditConsumableView: Updated consumable '\(trimmedName)' in Core Data")
            dismiss()
        } catch {
            errorMessage = "Failed to save changes: \(error.localizedDescription)"
            showingError = true
            print("EditConsumableView: Save failed, rolled back - \(error)")
        }
    }
}

#Preview {
    let consumable = FROConsumable(name: "MS20995C32 Safety Wire", category: "safety_wire")
    EditConsumableView(consumable: consumable)
        
}

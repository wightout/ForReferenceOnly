import SwiftUI

/// View for creating a new consumable entry in the Garage.
/// Saves directly to Core Data via the managed object context.
struct AddConsumableView: View {
    @Environment(\.modelContext) private var viewContext
    @Environment(\.dismiss) private var dismiss

    @State private var name: String = ""
    @State private var category: String = "other"
    @State private var size: String = ""
    @State private var spec: String = ""
    @State private var notes: String = ""
    @State private var showingError = false
    @State private var errorMessage = ""
    @State private var showingSuccess = false
    @State private var savedConsumableName = ""

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
            .navigationTitle("Add Consumable")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cancel") {
                        dismiss()
                    }
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Save") {
                        saveConsumable()
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
            .alert("Consumable Saved!", isPresented: $showingSuccess) {
                Button("OK") {
                    dismiss()
                }
            } message: {
                Text("'\(savedConsumableName)' has been added to your Garage.")
            }
        }
    }

    // MARK: - Save

    private func saveConsumable() {
        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedName.isEmpty else {
            errorMessage = "Consumable name cannot be empty."
            showingError = true
            return
        }

        let consumable = FROConsumable(name: trimmedName, category: category)
        viewContext.insert(consumable)

        let trimmedSize = size.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmedSize.isEmpty {
            consumable.size = trimmedSize
        }

        let trimmedSpec = spec.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmedSpec.isEmpty {
            consumable.spec = trimmedSpec
        }

        let trimmedNotes = notes.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmedNotes.isEmpty {
            consumable.notes = trimmedNotes
        }

        do {
            try viewContext.save()
            print("AddConsumableView: Saved consumable '\(trimmedName)' to Core Data")
            savedConsumableName = trimmedName
            showingSuccess = true
        } catch {
            errorMessage = "Failed to save consumable: \(error.localizedDescription)"
            showingError = true
            print("AddConsumableView: Save failed, rolled back - \(error)")
        }
    }
}

#Preview {
    AddConsumableView()
        
}

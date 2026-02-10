import SwiftUI
import Foundation
import SwiftData

/// A picker view that presents all chemicals from the Garage for selection.
/// Used when creating/editing job records to pull chemicals from inventory.
/// Includes an option to create a new chemical on-the-fly that will be immediately attached to the job.
struct GarageChemicalPickerView: View {
    @Environment(\.modelContext) private var viewContext
    @Environment(\.dismiss) private var dismiss

    /// Fetch all chemicals sorted by name
    @Query(sort: \FROChemical.name, order: .forward)
    private var allChemicals: [FROChemical]

    /// Binding to the set of selected chemical object IDs
    @Binding var selectedChemicalIDs: Set<UUID>

    /// Local tracking of selections (copy on appear, apply on confirm)
    @State private var localSelection: Set<UUID> = []

    /// Controls showing the "Create New Chemical" sheet
    @State private var showingCreateChemical = false

    var body: some View {
        NavigationStack {
            List {
                // MARK: - Create New Chemical Section
                Section {
                    Button(action: {
                        showingCreateChemical = true
                    }) {
                        HStack(spacing: 12) {
                            Image(systemName: "plus.circle.fill")
                                .font(.title2)
                                .foregroundColor(Color(red: 0.145, green: 0.388, blue: 0.922))
                            VStack(alignment: .leading, spacing: 2) {
                                Text("Create New Chemical")
                                    .font(.body)
                                    .fontWeight(.medium)
                                    .foregroundColor(.primary)
                                Text("Add a chemical that's not in your Garage")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                            Spacer()
                            Image(systemName: "chevron.right")
                                .foregroundColor(.secondary)
                                .font(.caption)
                        }
                        .padding(.vertical, 4)
                    }
                    .accessibilityIdentifier("createNewChemicalButton")
                    .accessibilityLabel("Create New Chemical")
                    .accessibilityHint("Opens form to create a new chemical and add it to this job")
                }

                // MARK: - Existing Chemicals Section
                if allChemicals.isEmpty {
                    Section {
                        VStack(spacing: 12) {
                            Image(systemName: "drop.fill")
                                .font(.system(size: 40))
                                .foregroundColor(Color(red: 0.392, green: 0.455, blue: 0.545))
                            Text("No Chemicals in Garage Yet")
                                .font(.subheadline)
                                .fontWeight(.medium)
                            Text("Create your first chemical above,\nor add chemicals in the Garage tab.")
                                .font(.caption)
                                .foregroundColor(.secondary)
                                .multilineTextAlignment(.center)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 20)
                    }
                } else {
                    Section(header: Text("Your Chemicals")) {
                        ForEach(allChemicals, id: \.id) { chemical in
                            ChemicalSelectionRow(
                                chemical: chemical,
                                isSelected: localSelection.contains(chemical.id)
                            )
                            .contentShape(Rectangle())
                            .onTapGesture {
                                toggleSelection(chemical.id)
                            }
                        }
                    }
                }
            }
            .listStyle(.insetGrouped)
            .navigationTitle("Select Chemicals")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        dismiss()
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done (\(localSelection.count))") {
                        selectedChemicalIDs = localSelection
                        dismiss()
                    }
                    .fontWeight(.semibold)
                }
            }
            .sheet(isPresented: $showingCreateChemical) {
                CreateChemicalOnTheFlyView(
                    onChemicalCreated: { newChemicalID in
                        // Immediately add the new chemical to the selection
                        localSelection.insert(newChemicalID)
                    }
                )
                
            }
            .onAppear {
                localSelection = selectedChemicalIDs
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
}

// MARK: - Create Chemical On-The-Fly View

/// A streamlined view for quickly creating a new chemical during job entry.
/// Only requires a name; category is optional with a default of "other".
/// The new chemical is created and immediately selected for the job.
/// Shows matching suggestions as user types to avoid duplicates (Feature #95).
struct CreateChemicalOnTheFlyView: View {
    @Environment(\.modelContext) private var viewContext
    @Environment(\.dismiss) private var dismiss

    /// Callback when a new chemical is created, provides the object ID
    let onChemicalCreated: (UUID) -> Void

    /// Callback when an existing chemical is selected from suggestions (Feature #95)
    var onExistingChemicalSelected: ((UUID) -> Void)?

    /// Fetch all chemicals for suggestions (Feature #95)
    @Query(sort: \FROChemical.name, order: .forward)
    private var allChemicals: [FROChemical]

    @State private var name: String = ""
    @State private var category: String = "other"
    @State private var showingError = false
    @State private var errorMessage = ""
    @State private var showingSuggestions = false

    private let categoryOptions: [(value: String, label: String)] = [
        ("fluid", "Fluid"),
        ("lubricant", "Lubricant"),
        ("cleaner", "Cleaner"),
        ("sealant", "Sealant"),
        ("other", "Other")
    ]

    private var canSave: Bool {
        !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    /// Computed property for matching chemicals based on typed name (Feature #95)
    private var matchingChemicals: [Chemical] {
        let trimmedSearch = name.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !trimmedSearch.isEmpty else { return [] }

        return allChemicals.filter { chemical in
            chemical.name.lowercased().contains(trimmedSearch)
        }
    }

    /// Returns a human-readable category label (Feature #95)
    private func categoryLabel(for cat: String) -> String {
        switch cat {
        case "fluid": return "Fluid"
        case "lubricant": return "Lubricant"
        case "cleaner": return "Cleaner"
        case "sealant": return "Sealant"
        case "other": return "Other"
        default: return "Other"
        }
    }

    var body: some View {
        NavigationStack {
            Form {
                // MARK: - Chemical Name (Required)
                Section(header: Text("Chemical Name")) {
                    TextField("e.g., MIL-PRF-81322 grease", text: $name)
                        .font(.body)
                        .autocorrectionDisabled()
                        .accessibilityIdentifier("newChemicalNameField")
                        .accessibilityLabel("Chemical name, required")
                        .onChange(of: name) { _, newValue in
                            // Show suggestions when typing (Feature #95)
                            showingSuggestions = !newValue.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                        }
                }

                // MARK: - Autocomplete Suggestions (Feature #95)
                if showingSuggestions && !matchingChemicals.isEmpty {
                    Section(header: Text("Existing Matches")) {
                        HStack(spacing: 6) {
                            Image(systemName: "lightbulb.fill")
                                .font(.caption)
                                .foregroundColor(Color(red: 0.976, green: 0.451, blue: 0.086))
                            Text("Did you mean one of these?")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                        .accessibilityIdentifier("chemicalSuggestionsHeader")

                        ForEach(matchingChemicals.prefix(5), id: \.id) { chemical in
                            Button(action: {
                                // Select existing chemical instead of creating new (Feature #95)
                                selectExistingChemical(chemical)
                            }) {
                                HStack {
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(chemical.name)
                                            .font(.body)
                                            .foregroundColor(.primary)
                                        if !chemical.category.isEmpty {
                                            Text(categoryLabel(for: chemical.category))
                                                .font(.caption)
                                                .foregroundColor(.secondary)
                                        }
                                    }
                                    Spacer()
                                    Image(systemName: "checkmark.circle")
                                        .foregroundColor(Color(red: 0.145, green: 0.388, blue: 0.922))
                                }
                            }
                            .accessibilityIdentifier("chemicalSuggestion_\(chemical.name)")
                            .accessibilityLabel("Select existing chemical: \(chemical.name)")
                        }

                        if matchingChemicals.count > 5 {
                            Text("+\(matchingChemicals.count - 5) more matches")
                                .font(.caption2)
                                .foregroundColor(.secondary)
                        }
                    }
                }

                // MARK: - Category (Optional)
                Section(header: Text("Category (Optional)")) {
                    Picker("Category", selection: $category) {
                        ForEach(categoryOptions, id: \.value) { option in
                            Text(option.label).tag(option.value)
                        }
                    }
                    .pickerStyle(.menu)
                    .accessibilityIdentifier("newChemicalCategoryPicker")
                }

                // MARK: - Info Text
                Section {
                    HStack(spacing: 8) {
                        Image(systemName: "info.circle")
                            .foregroundColor(Color(red: 0.145, green: 0.388, blue: 0.922))
                        Text("This chemical will be added to your Garage and attached to this job.")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
            }
            .navigationTitle("New Chemical")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        dismiss()
                    }
                    .accessibilityIdentifier("cancelNewChemicalButton")
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Add") {
                        createAndSelectChemical()
                    }
                    .fontWeight(.semibold)
                    .disabled(!canSave)
                    .accessibilityIdentifier("saveNewChemicalButton")
                }
            }
            .alert("Error", isPresented: $showingError) {
                Button("OK") { }
            } message: {
                Text(errorMessage)
            }
        }
    }

    /// Selects an existing chemical from suggestions instead of creating new (Feature #95)
    private func selectExistingChemical(_ chemical: Chemical) {
        print("CreateChemicalOnTheFlyView: Selected existing chemical '\(chemical.name)' from suggestions")

        // Use the existing chemical selection callback if available, otherwise use the creation callback
        if let onExistingSelected = onExistingChemicalSelected {
            onExistingSelected(chemical.id)
        } else {
            // Fall back to the creation callback (same effect - adds to selection)
            onChemicalCreated(chemical.id)
        }
        dismiss()
    }

    private func createAndSelectChemical() {
        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedName.isEmpty else {
            errorMessage = "Chemical name cannot be empty."
            showingError = true
            return
        }

        // Create the new chemical
        // Mark as not in Garage initially - user will be prompted after job save (Feature #96)
        let chemical = FROChemical(name: trimmedName, category: category, isInGarage: false)
        viewContext.insert(chemical)

        do {
            try viewContext.save()
            print("CreateChemicalOnTheFlyView: Created chemical '\(trimmedName)' with category '\(category)'")

            // Notify the parent view to add this chemical to the selection
            onChemicalCreated(chemical.id)
            dismiss()
        } catch {
            errorMessage = "Failed to create chemical: \(error.localizedDescription)"
            showingError = true
            print("CreateChemicalOnTheFlyView: Save failed, rolled back - \(error)")
        }
    }
}

/// A row showing a chemical with a checkmark for selection state.
struct ChemicalSelectionRow: View {
    @Bindable var chemical: Chemical
    let isSelected: Bool

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(chemical.name)
                    .font(.body)
                    .fontWeight(.medium)

                HStack(spacing: 8) {
                    // Category badge
                    Text(categoryLabel)
                        .font(.caption2)
                        .fontWeight(.medium)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(categoryColor.opacity(0.15))
                        .foregroundColor(categoryColor)
                        .clipShape(Capsule())

                    if let spec = chemical.spec, !spec.isEmpty {
                        Text(spec)
                            .font(.caption)
                            .foregroundColor(.secondary)
                            .lineLimit(1)
                    }

                    if let size = chemical.size, !size.isEmpty {
                        Text(size)
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

    private var categoryLabel: String {
        switch chemical.category {
        case "fluid": return "Fluid"
        case "lubricant": return "Lubricant"
        case "cleaner": return "Cleaner"
        case "sealant": return "Sealant"
        case "other": return "Other"
        default: return "Other"
        }
    }

    private var categoryColor: Color {
        switch chemical.category {
        case "fluid": return Color(red: 0.145, green: 0.388, blue: 0.922)
        case "lubricant": return Color(red: 0.976, green: 0.451, blue: 0.086)
        case "cleaner": return Color(red: 0.133, green: 0.773, blue: 0.369)
        case "sealant": return Color(red: 0.392, green: 0.455, blue: 0.545)
        default: return .gray
        }
    }
}

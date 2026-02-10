import SwiftUI
import Foundation
import SwiftData

/// A picker view that presents all consumables from the Garage for selection.
/// Used when creating/editing job records to pull consumables from inventory.
/// Also allows creating new consumables on-the-fly (Feature #92).
/// Shows matching suggestions as user types to avoid duplicates (Feature #95).
struct GarageConsumablePickerView: View {
    @Environment(\.modelContext) private var viewContext
    @Environment(\.dismiss) private var dismiss

    /// Fetch all consumables sorted by name
    @Query(sort: \FROConsumable.name, order: .forward)
    private var allConsumables: [FROConsumable]

    /// Binding to the set of selected consumable object IDs
    @Binding var selectedConsumableIDs: Set<UUID>

    /// Local tracking of selections (copy on appear, apply on confirm)
    @State private var localSelection: Set<UUID> = []

    /// State for creating new consumable on-the-fly
    @State private var showingCreateNew = false
    @State private var newConsumableName = ""
    @State private var newConsumableCategory = "other"
    @State private var showingNameRequired = false
    @State private var isSaving = false

    /// Controls whether to show the suggestions dropdown (Feature #95)
    @State private var showingSuggestions = false

    /// Tracks the most recently created consumable for visual feedback
    @State private var justCreatedID: UUID?

    /// Category options for new consumable picker
    private let categoryOptions: [(value: String, label: String)] = [
        ("safety_wire", "Safety Wire"),
        ("cotter_pin", "Cotter Pin"),
        ("o_ring", "O-Ring"),
        ("seal", "Seal"),
        ("other", "Other")
    ]

    /// Computed property for matching consumables based on typed name (Feature #95)
    private var matchingConsumables: [Consumable] {
        let trimmedSearch = newConsumableName.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !trimmedSearch.isEmpty else { return [] }

        return allConsumables.filter { consumable in
            let name = consumable.name.lowercased()
            // Match if the name contains the search text
            return name.contains(trimmedSearch)
        }
    }

    var body: some View {
        NavigationStack {
            List {
                // MARK: - Create New Consumable Section
                Section {
                    if showingCreateNew {
                        // Inline form to create new consumable
                        VStack(alignment: .leading, spacing: 12) {
                            TextField("Consumable name (e.g., 0.032 safety wire)", text: $newConsumableName)
                                .font(.body)
                                .textFieldStyle(.roundedBorder)
                                .autocorrectionDisabled()
                                .accessibilityIdentifier("newConsumableNameField")
                                .accessibilityLabel("New consumable name")
                                .onChange(of: newConsumableName) { _, newValue in
                                    if !newValue.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                                        showingNameRequired = false
                                        // Show suggestions when typing (Feature #95)
                                        showingSuggestions = true
                                    } else {
                                        showingSuggestions = false
                                    }
                                }

                            // MARK: - Autocomplete Suggestions (Feature #95)
                            if showingSuggestions && !matchingConsumables.isEmpty {
                                VStack(alignment: .leading, spacing: 0) {
                                    HStack(spacing: 6) {
                                        Image(systemName: "lightbulb.fill")
                                            .font(.caption)
                                            .foregroundColor(Color(red: 0.976, green: 0.451, blue: 0.086))
                                        Text("Existing consumables matching '\(newConsumableName)':")
                                            .font(.caption)
                                            .foregroundColor(.secondary)
                                    }
                                    .padding(.bottom, 6)
                                    .accessibilityIdentifier("consumableSuggestionsHeader")

                                    ForEach(matchingConsumables.prefix(5), id: \.id) { consumable in
                                        Button(action: {
                                            // Select existing consumable instead of creating new (Feature #95)
                                            selectExistingConsumable(consumable)
                                        }) {
                                            HStack {
                                                VStack(alignment: .leading, spacing: 2) {
                                                    Text(consumable.name)
                                                        .font(.body)
                                                        .foregroundColor(.primary)
                                                    Text(categoryLabel(for: consumable.category))
                                                        .font(.caption)
                                                        .foregroundColor(.secondary)
                                                }
                                                Spacer()
                                                Image(systemName: "plus.circle")
                                                    .foregroundColor(Color(red: 0.145, green: 0.388, blue: 0.922))
                                            }
                                            .padding(.vertical, 8)
                                            .padding(.horizontal, 10)
                                            .background(Color(UIColor.systemGray6))
                                            .cornerRadius(8)
                                        }
                                        .accessibilityIdentifier("consumableSuggestion_\(consumable.name)")
                                        .accessibilityLabel("Select existing consumable: \(consumable.name)")
                                    }

                                    if matchingConsumables.count > 5 {
                                        Text("+\(matchingConsumables.count - 5) more matches")
                                            .font(.caption2)
                                            .foregroundColor(.secondary)
                                            .padding(.top, 4)
                                    }
                                }
                                .padding(.vertical, 4)
                            }

                            if showingNameRequired {
                                Text("Name is required")
                                    .font(.caption)
                                    .foregroundColor(.red)
                                    .accessibilityIdentifier("consumableNameRequiredLabel")
                            }

                            Picker("Category", selection: $newConsumableCategory) {
                                ForEach(categoryOptions, id: \.value) { option in
                                    Text(option.label).tag(option.value)
                                }
                            }
                            .pickerStyle(.menu)
                            .accessibilityIdentifier("newConsumableCategoryPicker")

                            HStack(spacing: 12) {
                                Button(action: {
                                    withAnimation {
                                        showingCreateNew = false
                                        newConsumableName = ""
                                        newConsumableCategory = "other"
                                        showingNameRequired = false
                                    }
                                }) {
                                    Text("Cancel")
                                        .frame(maxWidth: .infinity)
                                        .padding(.vertical, 10)
                                        .background(Color(UIColor.systemGray5))
                                        .foregroundColor(.primary)
                                        .cornerRadius(8)
                                }
                                .accessibilityIdentifier("cancelNewConsumableButton")

                                Button(action: createAndSelectConsumable) {
                                    HStack {
                                        if isSaving {
                                            ProgressView()
                                                .progressViewStyle(CircularProgressViewStyle())
                                                .scaleEffect(0.8)
                                        }
                                        Text(isSaving ? "Creating..." : "Create & Add")
                                    }
                                    .frame(maxWidth: .infinity)
                                    .padding(.vertical, 10)
                                    .background(Color(red: 0.145, green: 0.388, blue: 0.922))
                                    .foregroundColor(.white)
                                    .cornerRadius(8)
                                }
                                .disabled(isSaving || newConsumableName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                                .accessibilityIdentifier("createAndAddConsumableButton")
                                .accessibilityLabel("Create and add consumable")
                            }
                        }
                        .padding(.vertical, 8)
                    } else {
                        // Button to show create new form
                        Button(action: {
                            withAnimation {
                                showingCreateNew = true
                            }
                        }) {
                            HStack(spacing: 12) {
                                Image(systemName: "plus.circle.fill")
                                    .font(.title2)
                                    .foregroundColor(Color(red: 0.145, green: 0.388, blue: 0.922))
                                VStack(alignment: .leading, spacing: 2) {
                                    Text("Create New Consumable")
                                        .font(.body)
                                        .fontWeight(.medium)
                                        .foregroundColor(.primary)
                                    Text("Add a consumable not in your Garage")
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                }
                                Spacer()
                                Image(systemName: "chevron.down")
                                    .foregroundColor(.secondary)
                                    .font(.caption)
                            }
                            .padding(.vertical, 4)
                        }
                        .accessibilityIdentifier("createNewConsumableButton")
                        .accessibilityLabel("Create New Consumable")
                        .accessibilityHint("Opens form to create a new consumable and add it to this job")
                    }
                } header: {
                    Text("Quick Add")
                }

                // MARK: - Existing Consumables Section
                if allConsumables.isEmpty && !showingCreateNew {
                    Section {
                        VStack(spacing: 12) {
                            Image(systemName: "bolt.fill")
                                .font(.system(size: 40))
                                .foregroundColor(Color(red: 0.392, green: 0.455, blue: 0.545))
                            Text("No Consumables in Garage")
                                .font(.body)
                                .fontWeight(.medium)
                            Text("Create a new consumable above, or add them in the Garage tab.")
                                .font(.caption)
                                .foregroundColor(.secondary)
                                .multilineTextAlignment(.center)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 20)
                    }
                } else if !allConsumables.isEmpty {
                    Section {
                        ForEach(allConsumables, id: \.id) { consumable in
                            ConsumableSelectionRow(
                                consumable: consumable,
                                isSelected: localSelection.contains(consumable.id),
                                isJustCreated: justCreatedID == consumable.id
                            )
                            .contentShape(Rectangle())
                            .onTapGesture {
                                toggleSelection(consumable.id)
                            }
                        }
                    } header: {
                        Text("From Garage (\(allConsumables.count))")
                    }
                }
            }
            .listStyle(.insetGrouped)
            .navigationTitle("Select Consumables")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        dismiss()
                    }
                    .accessibilityIdentifier("cancelConsumablePickerButton")
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done (\(localSelection.count))") {
                        selectedConsumableIDs = localSelection
                        dismiss()
                    }
                    .fontWeight(.semibold)
                    .disabled(localSelection.isEmpty)
                    .accessibilityIdentifier("doneConsumablePickerButton")
                }
            }
            .onAppear {
                localSelection = selectedConsumableIDs
            }
            // Prevent accidental swipe-to-dismiss when selections have been made
            .interactiveDismissDisabled(localSelection != selectedConsumableIDs)
        }
    }

    private func toggleSelection(_ objectID: UUID) {
        if localSelection.contains(objectID) {
            localSelection.remove(objectID)
        } else {
            localSelection.insert(objectID)
        }
    }

    /// Returns a human-readable category label (Feature #95)
    private func categoryLabel(for category: String) -> String {
        switch category {
        case "safety_wire": return "Safety Wire"
        case "cotter_pin": return "Cotter Pin"
        case "o_ring": return "O-Ring"
        case "seal": return "Seal"
        case "other": return "Other"
        default: return "Other"
        }
    }

    /// Selects an existing consumable from suggestions instead of creating new (Feature #95)
    /// Writes directly to the parent binding and dismisses.
    private func selectExistingConsumable(_ consumable: Consumable) {
        var finalSelection = localSelection
        finalSelection.insert(consumable.id)
        print("GarageConsumablePickerView: Selected existing consumable '\(consumable.name)' from suggestions")

        selectedConsumableIDs = finalSelection
        dismiss()
    }

    /// Creates a new consumable in Core Data and immediately adds it to the job.
    /// Feature #92: Create new consumable on-the-fly from job form.
    /// Writes directly to the parent binding and dismisses — no extra "Done" step needed.
    private func createAndSelectConsumable() {
        let trimmedName = newConsumableName.trimmingCharacters(in: .whitespacesAndNewlines)

        guard !trimmedName.isEmpty else {
            showingNameRequired = true
            return
        }

        guard !isSaving else { return }
        isSaving = true

        // Create new consumable in SwiftData
        // Mark as not in Garage initially - user will be prompted after job save (Feature #96)
        let consumable = FROConsumable(
            name: trimmedName,
            category: newConsumableCategory,
            isInGarage: false
        )
        viewContext.insert(consumable)

        do {
            try viewContext.save()
            let permanentID = consumable.id
            print("GarageConsumablePickerView: Created new consumable '\(trimmedName)' on-the-fly, objectID=\(permanentID)")

            // Write DIRECTLY to the parent binding — bypass localSelection entirely.
            // Also include any previously selected items from localSelection.
            var finalSelection = localSelection
            finalSelection.insert(permanentID)
            isSaving = false

            selectedConsumableIDs = finalSelection
            print("GarageConsumablePickerView: Wrote \(finalSelection.count) consumable(s) to parent binding, dismissing")
            dismiss()
        } catch {
            print("GarageConsumablePickerView: Failed to create consumable - \(error)")
            isSaving = false
        }
    }
}

/// A row showing a consumable with a checkmark for selection state.
struct ConsumableSelectionRow: View {
    @Bindable var consumable: Consumable
    let isSelected: Bool
    var isJustCreated: Bool = false

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(consumable.name)
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

                    if let size = consumable.size, !size.isEmpty {
                        Text(size)
                            .font(.caption)
                            .foregroundColor(.secondary)
                            .lineLimit(1)
                    }

                    if let spec = consumable.spec, !spec.isEmpty {
                        Text(spec)
                            .font(.caption)
                            .foregroundColor(.secondary)
                            .lineLimit(1)
                    }

                    // "Just added" indicator
                    if isJustCreated {
                        Text("Just added")
                            .font(.caption2)
                            .fontWeight(.semibold)
                            .foregroundColor(.green)
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
        .listRowBackground(isJustCreated ? Color(red: 0.145, green: 0.388, blue: 0.922).opacity(0.08) : nil)
    }

    private var categoryLabel: String {
        switch consumable.category {
        case "safety_wire": return "Safety Wire"
        case "cotter_pin": return "Cotter Pin"
        case "o_ring": return "O-Ring"
        case "seal": return "Seal"
        case "other": return "Other"
        default: return "Other"
        }
    }

    private var categoryColor: Color {
        switch consumable.category {
        case "safety_wire": return Color(red: 0.145, green: 0.388, blue: 0.922)
        case "cotter_pin": return Color(red: 0.392, green: 0.455, blue: 0.545)
        case "o_ring": return Color(red: 0.976, green: 0.451, blue: 0.086)
        case "seal": return Color(red: 0.133, green: 0.773, blue: 0.369)
        default: return .gray
        }
    }
}

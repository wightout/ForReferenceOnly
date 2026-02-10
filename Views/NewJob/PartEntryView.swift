import SwiftUI
import Foundation
import SwiftData

/// Sheet-based form for adding a part to a job.
/// Parts are NOT inventory items — they exist only in job context.
/// Autocomplete from previously used parts (by nomenclature or part number).
///
/// Feature #141: Parts on Jobs — recording parts used during maintenance.
struct PartEntryView: View {
    @Environment(\.modelContext) private var viewContext
    @Environment(\.dismiss) private var dismiss

    /// Binding to the set of selected part objectIDs in the parent view
    @Binding var selectedPartIDs: Set<UUID>

    // MARK: - Form Fields

    @State private var searchText: String = ""
    @State private var nomenclature: String = ""
    @State private var partNumber: String = ""
    @State private var alternatePartNumber: String = ""
    @State private var nsn: String = ""
    @State private var quantity: Int = 1
    @State private var unitOfMeasure: String = "EA"
    @State private var notes: String = ""

    @State private var showingError = false
    @State private var errorMessage = ""

    /// Available units of measure for the picker
    private let unitsOfMeasure = ["EA", "FT", "IN", "QT", "GAL", "LB", "OZ", "SET", "KIT", "PR", "PKG"]

    /// Fetch all existing Part entities for autocomplete
    @Query(sort: \FROPart.nomenclature, order: .forward)
    private var allParts: [FROPart]

    /// Unique parts for autocomplete (deduplicated by partNumber)
    private var uniqueParts: [Part] {
        var seen = Set<String>()
        var result: [Part] = []
        for part in allParts {
            let key = part.partNumber.lowercased()
            if !key.isEmpty && !seen.contains(key) {
                seen.insert(key)
                result.append(part)
            }
        }
        return result
    }

    /// Matching parts based on search text (nomenclature or part number)
    private var matchingParts: [Part] {
        let trimmed = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.count >= 2 else { return [] }
        let lowered = trimmed.lowercased()
        return uniqueParts.filter { part in
            part.nomenclature.lowercased().contains(lowered) ||
            part.partNumber.lowercased().contains(lowered)
        }
    }

    /// Whether to show autocomplete suggestions
    private var showSuggestions: Bool {
        let trimmed = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.count >= 2 else { return false }
        guard !matchingParts.isEmpty else { return false }
        return true
    }

    /// Whether the form has enough data to save
    private var canSave: Bool {
        !nomenclature.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
        !partNumber.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var body: some View {
        NavigationStack {
            Form {
                // MARK: - Search / Autocomplete
                Section {
                    TextField("Search by nomenclature or P/N...", text: $searchText)
                        .font(.body)
                        .autocorrectionDisabled()
                        .textInputAutocapitalization(.characters)
                        .accessibilityIdentifier("partSearchField")

                    if showSuggestions {
                        VStack(alignment: .leading, spacing: 0) {
                            HStack(spacing: 6) {
                                Image(systemName: "clock.arrow.circlepath")
                                    .font(.caption)
                                    .foregroundColor(Color(red: 0.145, green: 0.388, blue: 0.922))
                                Text("Previously used:")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                            .padding(.horizontal, 12)
                            .padding(.top, 8)
                            .padding(.bottom, 4)

                            ForEach(matchingParts.prefix(5), id: \.id) { part in
                                Button {
                                    prefillFrom(part)
                                } label: {
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(part.nomenclature)
                                            .font(.subheadline)
                                            .fontWeight(.medium)
                                            .foregroundColor(.primary)
                                        HStack(spacing: 8) {
                                            Text("P/N: \(part.partNumber)")
                                                .font(.caption)
                                                .foregroundColor(.secondary)
                                            if let alt = part.alternatePartNumber, !alt.isEmpty {
                                                Text("Alt: \(alt)")
                                                    .font(.caption)
                                                    .foregroundColor(.secondary)
                                            }
                                        }
                                    }
                                    .padding(.horizontal, 12)
                                    .padding(.vertical, 8)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .contentShape(Rectangle())
                                }
                                .buttonStyle(.plain)
                                .accessibilityLabel("Select \(part.nomenclature)")

                                if part.id != matchingParts.prefix(5).last?.id {
                                    Divider().padding(.leading, 12)
                                }
                            }

                            if matchingParts.count > 5 {
                                Text("+ \(matchingParts.count - 5) more")
                                    .font(.caption2)
                                    .foregroundColor(.secondary)
                                    .padding(.horizontal, 12)
                                    .padding(.vertical, 6)
                            }
                        }
                        .background(Color(UIColor.secondarySystemBackground))
                        .cornerRadius(8)
                    }
                } header: {
                    Text("Search Previous Parts")
                }

                // MARK: - Part Details
                Section {
                    TextField("Nomenclature (required)", text: $nomenclature)
                        .font(.body)
                        .autocorrectionDisabled()
                        .textInputAutocapitalization(.characters)
                        .accessibilityIdentifier("partNomenclatureField")

                    TextField("Part Number (required)", text: $partNumber)
                        .font(.body)
                        .autocorrectionDisabled()
                        .textInputAutocapitalization(.characters)
                        .accessibilityIdentifier("partNumberField")

                    TextField("Alternate Part Number", text: $alternatePartNumber)
                        .font(.body)
                        .autocorrectionDisabled()
                        .textInputAutocapitalization(.characters)
                        .accessibilityIdentifier("partAltPartNumberField")

                    TextField("NSN (National Stock Number)", text: $nsn)
                        .font(.body)
                        .autocorrectionDisabled()
                        .textInputAutocapitalization(.characters)
                        .accessibilityIdentifier("partNSNField")
                } header: {
                    Text("Part Information")
                }

                // MARK: - Quantity & Unit
                Section {
                    Stepper("Quantity: \(quantity)", value: $quantity, in: 1...999)
                        .accessibilityIdentifier("partQuantityStepper")

                    Picker("Unit of Measure", selection: $unitOfMeasure) {
                        ForEach(unitsOfMeasure, id: \.self) { unit in
                            Text(unit).tag(unit)
                        }
                    }
                    .accessibilityIdentifier("partUnitOfMeasurePicker")
                } header: {
                    Text("Quantity")
                }

                // MARK: - Notes
                Section {
                    TextField("Notes (optional)", text: $notes, axis: .vertical)
                        .font(.body)
                        .lineLimit(2...5)
                        .accessibilityIdentifier("partNotesField")
                } header: {
                    Text("Notes")
                }
            }
            .navigationTitle("Add Part")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cancel") {
                        dismiss()
                    }
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Add Part") {
                        savePart()
                    }
                    .fontWeight(.semibold)
                    .disabled(!canSave)
                }
            }
            .alert("Error", isPresented: $showingError) {
                Button("OK") { }
            } message: {
                Text(errorMessage)
            }
        }
    }

    // MARK: - Actions

    /// Pre-fills the form fields from an existing Part (autocomplete selection)
    private func prefillFrom(_ part: Part) {
        nomenclature = part.nomenclature
        partNumber = part.partNumber
        alternatePartNumber = part.alternatePartNumber ?? ""
        nsn = part.nsn ?? ""
        unitOfMeasure = part.unitOfMeasure ?? "EA"
        notes = ""
        quantity = 1
        searchText = ""
        print("PartEntryView: Pre-filled from existing part '\(part.nomenclature)' P/N: \(part.partNumber)")
    }

    /// Creates a new Part entity and adds it to the selected parts set
    private func savePart() {
        let trimmedNomenclature = nomenclature.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedPN = partNumber.trimmingCharacters(in: .whitespacesAndNewlines)

        guard !trimmedNomenclature.isEmpty else {
            errorMessage = "Nomenclature is required."
            showingError = true
            return
        }
        guard !trimmedPN.isEmpty else {
            errorMessage = "Part Number is required."
            showingError = true
            return
        }

        let part = FROPart(partNumber: trimmedPN, nomenclature: trimmedNomenclature, quantity: quantity)
        viewContext.insert(part)
        let trimmedAlt = alternatePartNumber.trimmingCharacters(in: .whitespacesAndNewlines)
        part.alternatePartNumber = trimmedAlt.isEmpty ? nil : trimmedAlt
        let trimmedNSN = nsn.trimmingCharacters(in: .whitespacesAndNewlines)
        part.nsn = trimmedNSN.isEmpty ? nil : trimmedNSN
        part.quantity = quantity
        part.unitOfMeasure = unitOfMeasure
        let trimmedNotes = notes.trimmingCharacters(in: .whitespacesAndNewlines)
        part.notes = trimmedNotes.isEmpty ? nil : trimmedNotes

        do {
            try viewContext.save()
            selectedPartIDs.insert(part.id)
            print("PartEntryView: Created part '\(trimmedNomenclature)' P/N: \(trimmedPN), qty: \(quantity)")
            dismiss()
        } catch {
            errorMessage = "Failed to save part: \(error.localizedDescription)"
            showingError = true
            print("PartEntryView: Save failed - \(error)")
        }
    }
}

#Preview {
    struct PreviewWrapper: View {
        @State private var partIDs: Set<UUID> = []
        var body: some View {
            PartEntryView(selectedPartIDs: $partIDs)
                
        }
    }
    return PreviewWrapper()
}

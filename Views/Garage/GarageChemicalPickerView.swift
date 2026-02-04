import SwiftUI
import CoreData

/// A picker view that presents all chemicals from the Garage for selection.
/// Used when creating/editing job records to pull chemicals from inventory.
struct GarageChemicalPickerView: View {
    @Environment(\.managedObjectContext) private var viewContext
    @Environment(\.dismiss) private var dismiss

    /// Fetch all chemicals sorted by name
    @FetchRequest(
        sortDescriptors: [NSSortDescriptor(keyPath: \Chemical.name, ascending: true)],
        animation: .default
    )
    private var allChemicals: FetchedResults<Chemical>

    /// Binding to the set of selected chemical object IDs
    @Binding var selectedChemicalIDs: Set<NSManagedObjectID>

    /// Local tracking of selections (copy on appear, apply on confirm)
    @State private var localSelection: Set<NSManagedObjectID> = []

    var body: some View {
        NavigationStack {
            Group {
                if allChemicals.isEmpty {
                    VStack(spacing: 16) {
                        Spacer()
                        Image(systemName: "drop.fill")
                            .font(.system(size: 50))
                            .foregroundColor(Color(red: 0.392, green: 0.455, blue: 0.545))
                        Text("No Chemicals in Garage")
                            .font(.title3)
                            .fontWeight(.semibold)
                        Text("Add chemicals in the Garage tab first,\nthen come back to link them to jobs.")
                            .font(.body)
                            .foregroundColor(.secondary)
                            .multilineTextAlignment(.center)
                        Spacer()
                    }
                    .padding()
                } else {
                    List {
                        ForEach(allChemicals, id: \.objectID) { chemical in
                            ChemicalSelectionRow(
                                chemical: chemical,
                                isSelected: localSelection.contains(chemical.objectID)
                            )
                            .contentShape(Rectangle())
                            .onTapGesture {
                                toggleSelection(chemical.objectID)
                            }
                        }
                    }
                    .listStyle(.insetGrouped)
                }
            }
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
                    .disabled(allChemicals.isEmpty)
                }
            }
            .onAppear {
                localSelection = selectedChemicalIDs
            }
        }
    }

    private func toggleSelection(_ objectID: NSManagedObjectID) {
        if localSelection.contains(objectID) {
            localSelection.remove(objectID)
        } else {
            localSelection.insert(objectID)
        }
    }
}

/// A row showing a chemical with a checkmark for selection state.
struct ChemicalSelectionRow: View {
    @ObservedObject var chemical: Chemical
    let isSelected: Bool

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(chemical.name ?? "Unnamed Chemical")
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

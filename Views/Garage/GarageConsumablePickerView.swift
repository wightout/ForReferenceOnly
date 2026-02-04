import SwiftUI
import CoreData

/// A picker view that presents all consumables from the Garage for selection.
/// Used when creating/editing job records to pull consumables from inventory.
struct GarageConsumablePickerView: View {
    @Environment(\.managedObjectContext) private var viewContext
    @Environment(\.dismiss) private var dismiss

    /// Fetch all consumables sorted by name
    @FetchRequest(
        sortDescriptors: [NSSortDescriptor(keyPath: \Consumable.name, ascending: true)],
        animation: .default
    )
    private var allConsumables: FetchedResults<Consumable>

    /// Binding to the set of selected consumable object IDs
    @Binding var selectedConsumableIDs: Set<NSManagedObjectID>

    /// Local tracking of selections (copy on appear, apply on confirm)
    @State private var localSelection: Set<NSManagedObjectID> = []

    var body: some View {
        NavigationStack {
            Group {
                if allConsumables.isEmpty {
                    VStack(spacing: 16) {
                        Spacer()
                        Image(systemName: "bolt.fill")
                            .font(.system(size: 50))
                            .foregroundColor(Color(red: 0.392, green: 0.455, blue: 0.545))
                        Text("No Consumables in Garage")
                            .font(.title3)
                            .fontWeight(.semibold)
                        Text("Add consumables in the Garage tab first,\nthen come back to link them to jobs.")
                            .font(.body)
                            .foregroundColor(.secondary)
                            .multilineTextAlignment(.center)
                        Spacer()
                    }
                    .padding()
                } else {
                    List {
                        ForEach(allConsumables, id: \.objectID) { consumable in
                            ConsumableSelectionRow(
                                consumable: consumable,
                                isSelected: localSelection.contains(consumable.objectID)
                            )
                            .contentShape(Rectangle())
                            .onTapGesture {
                                toggleSelection(consumable.objectID)
                            }
                        }
                    }
                    .listStyle(.insetGrouped)
                }
            }
            .navigationTitle("Select Consumables")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        dismiss()
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done (\(localSelection.count))") {
                        selectedConsumableIDs = localSelection
                        dismiss()
                    }
                    .fontWeight(.semibold)
                    .disabled(allConsumables.isEmpty)
                }
            }
            .onAppear {
                localSelection = selectedConsumableIDs
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

/// A row showing a consumable with a checkmark for selection state.
struct ConsumableSelectionRow: View {
    @ObservedObject var consumable: Consumable
    let isSelected: Bool

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(consumable.name ?? "Unnamed Consumable")
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

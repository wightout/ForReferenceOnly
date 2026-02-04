import SwiftUI
import CoreData

/// A picker view that presents all tools from the Garage for selection.
/// Used when creating/editing job records to pull tools from inventory.
struct GarageToolPickerView: View {
    @Environment(\.managedObjectContext) private var viewContext
    @Environment(\.dismiss) private var dismiss

    /// Fetch all tools sorted by name
    @FetchRequest(
        sortDescriptors: [NSSortDescriptor(keyPath: \Tool.name, ascending: true)],
        animation: .default
    )
    private var allTools: FetchedResults<Tool>

    /// Binding to the set of selected tool object IDs
    @Binding var selectedToolIDs: Set<NSManagedObjectID>

    /// Local tracking of selections (copy on appear, apply on confirm)
    @State private var localSelection: Set<NSManagedObjectID> = []

    var body: some View {
        NavigationStack {
            Group {
                if allTools.isEmpty {
                    VStack(spacing: 16) {
                        Spacer()
                        Image(systemName: "wrench.and.screwdriver")
                            .font(.system(size: 50))
                            .foregroundColor(Color(red: 0.392, green: 0.455, blue: 0.545))
                        Text("No Tools in Garage")
                            .font(.title3)
                            .fontWeight(.semibold)
                        Text("Add tools in the Garage tab first,\nthen come back to link them to jobs.")
                            .font(.body)
                            .foregroundColor(.secondary)
                            .multilineTextAlignment(.center)
                        Spacer()
                    }
                    .padding()
                } else {
                    List {
                        ForEach(allTools, id: \.objectID) { tool in
                            ToolSelectionRow(
                                tool: tool,
                                isSelected: localSelection.contains(tool.objectID)
                            )
                            .contentShape(Rectangle())
                            .onTapGesture {
                                toggleSelection(tool.objectID)
                            }
                        }
                    }
                    .listStyle(.insetGrouped)
                }
            }
            .navigationTitle("Select Tools")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        dismiss()
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done (\(localSelection.count))") {
                        selectedToolIDs = localSelection
                        dismiss()
                    }
                    .fontWeight(.semibold)
                    .disabled(allTools.isEmpty)
                }
            }
            .onAppear {
                localSelection = selectedToolIDs
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

/// A row showing a tool with a checkmark for selection state.
struct ToolSelectionRow: View {
    @ObservedObject var tool: Tool
    let isSelected: Bool

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(tool.name ?? "Unnamed Tool")
                    .font(.body)
                    .fontWeight(.medium)

                HStack(spacing: 8) {
                    // Ownership badge
                    Text(ownershipLabel)
                        .font(.caption2)
                        .fontWeight(.medium)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(ownershipColor.opacity(0.15))
                        .foregroundColor(ownershipColor)
                        .clipShape(Capsule())

                    if let notes = tool.notes, !notes.isEmpty {
                        Text(notes)
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

    private var ownershipLabel: String {
        switch tool.ownershipType {
        case "personal": return "Personal"
        case "shop": return "Shop"
        case "borrowed": return "Borrowed"
        default: return "Personal"
        }
    }

    private var ownershipColor: Color {
        switch tool.ownershipType {
        case "personal": return Color(red: 0.145, green: 0.388, blue: 0.922)
        case "shop": return Color(red: 0.392, green: 0.455, blue: 0.545)
        case "borrowed": return Color(red: 0.976, green: 0.451, blue: 0.086)
        default: return .blue
        }
    }
}

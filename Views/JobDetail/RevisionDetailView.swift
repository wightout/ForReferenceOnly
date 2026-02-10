import SwiftUI
import Foundation
import SwiftData

/// Displays a read-only view of a historical job revision snapshot.
/// The snapshot data is stored as JSON binary in the JobRevision entity.
struct RevisionDetailView: View {
    let revision: JobRevision

    /// Decoded snapshot dictionary
    private var snapshot: [String: Any] {
        guard let data = revision.snapshotData,
              let dict = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return [:]
        }
        return dict
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                // FRO Banner
                HStack {
                    Spacer()
                    Text("FOR REFERENCE ONLY")
                        .font(.caption)
                        .fontWeight(.bold)
                        .foregroundColor(Color(red: 0.976, green: 0.451, blue: 0.086))
                        .padding(.horizontal, 12)
                        .padding(.vertical, 4)
                        .background(Color(red: 0.976, green: 0.451, blue: 0.086).opacity(0.2))
                        .cornerRadius(4)
                    Spacer()
                }
                .padding(.top, 8)

                // Version badge
                HStack {
                    Text("Version \(revision.versionNumber)")
                        .font(.subheadline)
                        .fontWeight(.semibold)
                        .foregroundColor(.white)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                        .background(Color(red: 0.392, green: 0.455, blue: 0.545))
                        .cornerRadius(8)
                    Text("Historical Snapshot")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    Spacer()
                    Text(revision.editedAt, style: .date)
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                .padding(.horizontal)

                // Aircraft & Job Info
                VStack(alignment: .leading, spacing: 12) {
                    RevisionField(title: "Aircraft Type", value: snapshot["aircraftType"] as? String)

                    if let serial = snapshot["aircraftSerialNumber"] as? String, !serial.isEmpty {
                        RevisionField(title: "Serial Number", value: serial)
                    }

                    if let nNum = snapshot["nNumber"] as? String, !nNum.isEmpty {
                        RevisionField(title: "N-Number / Tail Number", value: nNum)
                    }

                    RevisionField(title: "System", value: snapshot["system"] as? String, color: Color(red: 0.145, green: 0.388, blue: 0.922))

                    if let comp = snapshot["component"] as? String, !comp.isEmpty {
                        RevisionField(title: "Component", value: comp)
                    }

                    if let dateStr = snapshot["jobDate"] as? String {
                        RevisionField(title: "Job Date", value: dateStr)
                    }
                }
                .padding(.horizontal)

                Divider().padding(.horizontal)

                // Task Description
                if let desc = snapshot["taskDescription"] as? String, !desc.isEmpty {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Task Description")
                            .font(.headline)
                            .foregroundColor(.secondary)
                        Text(desc)
                            .font(.body)
                    }
                    .padding(.horizontal)
                }

                // TM References
                if let tm = snapshot["tmReferences"] as? String, !tm.isEmpty {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("TM References")
                            .font(.headline)
                            .foregroundColor(.secondary)
                        Text(tm)
                            .font(.system(.body, design: .monospaced))
                    }
                    .padding(.horizontal)
                }

                // Tools Used
                if let tools = snapshot["tools"] as? [[String: String]], !tools.isEmpty {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Tools Used")
                            .font(.headline)
                            .foregroundColor(.secondary)
                            .padding(.horizontal)

                        ForEach(tools, id: \.self) { tool in
                            HStack {
                                Image(systemName: "wrench.fill")
                                    .foregroundColor(Color(red: 0.392, green: 0.455, blue: 0.545))
                                    .font(.caption)
                                VStack(alignment: .leading, spacing: 1) {
                                    Text(tool["name"] ?? "Unnamed Tool")
                                        .font(.body)
                                    if let ownership = tool["ownershipType"] {
                                        Text(ownershipLabel(ownership))
                                            .font(.caption)
                                            .foregroundColor(.secondary)
                                    }
                                }
                                Spacer()
                            }
                            .padding(.horizontal)
                            .padding(.vertical, 2)
                        }
                    }
                }

                // Consumables Used
                if let consumables = snapshot["consumables"] as? [[String: String]], !consumables.isEmpty {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Consumables Used")
                            .font(.headline)
                            .foregroundColor(.secondary)
                            .padding(.horizontal)

                        ForEach(consumables, id: \.self) { consumable in
                            HStack {
                                Image(systemName: "bolt.fill")
                                    .foregroundColor(Color(red: 0.392, green: 0.455, blue: 0.545))
                                    .font(.caption)
                                Text(consumable["name"] ?? "Unnamed")
                                    .font(.body)
                                Spacer()
                            }
                            .padding(.horizontal)
                            .padding(.vertical, 2)
                        }
                    }
                }

                // Chemicals Used
                if let chemicals = snapshot["chemicals"] as? [[String: String]], !chemicals.isEmpty {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Chemicals Used")
                            .font(.headline)
                            .foregroundColor(.secondary)
                            .padding(.horizontal)

                        ForEach(chemicals, id: \.self) { chemical in
                            HStack {
                                Image(systemName: "drop.fill")
                                    .foregroundColor(Color(red: 0.392, green: 0.455, blue: 0.545))
                                    .font(.caption)
                                Text(chemical["name"] ?? "Unnamed")
                                    .font(.body)
                                Spacer()
                            }
                            .padding(.horizontal)
                            .padding(.vertical, 2)
                        }
                    }
                }

                // Feature #141: Parts Used (from snapshot)
                if let parts = snapshot["parts"] as? [[String: Any]], !parts.isEmpty {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Parts Used")
                            .font(.headline)
                            .foregroundColor(.secondary)
                            .padding(.horizontal)

                        ForEach(Array(parts.enumerated()), id: \.offset) { _, part in
                            VStack(alignment: .leading, spacing: 2) {
                                HStack {
                                    Image(systemName: "gearshape.2.fill")
                                        .foregroundColor(Color(red: 0.392, green: 0.455, blue: 0.545))
                                        .font(.caption)
                                    Text(part["nomenclature"] as? String ?? "Unnamed")
                                        .font(.body)
                                    Spacer()
                                    if let qty = part["quantity"] as? Int, qty > 1 {
                                        Text("Qty: \(qty)")
                                            .font(.caption)
                                            .foregroundColor(.secondary)
                                    }
                                }
                                HStack(spacing: 12) {
                                    Text("P/N: \(part["partNumber"] as? String ?? "")")
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                    if let alt = part["alternatePartNumber"] as? String, !alt.isEmpty {
                                        Text("Alt: \(alt)")
                                            .font(.caption)
                                            .foregroundColor(.secondary)
                                    }
                                    if let nsn = part["nsn"] as? String, !nsn.isEmpty {
                                        Text("NSN: \(nsn)")
                                            .font(.caption)
                                            .foregroundColor(.secondary)
                                    }
                                }
                                .padding(.leading, 20)
                            }
                            .padding(.horizontal)
                            .padding(.vertical, 2)
                        }
                    }
                }

                // Notes (Feature #126 - display as numbered items)
                if let notesText = snapshot["notes"] as? String, !notesText.isEmpty {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Notes & Recommendations")
                            .font(.headline)
                            .foregroundColor(.secondary)
                            .accessibilityIdentifier("revisionNotesHeader")

                        // Split notes by line breaks and display as numbered list
                        let noteLines = notesText.components(separatedBy: .newlines).filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty }
                        if noteLines.count > 1 {
                            // Display as numbered list
                            VStack(alignment: .leading, spacing: 8) {
                                ForEach(Array(noteLines.enumerated()), id: \.offset) { index, line in
                                    HStack(alignment: .top, spacing: 10) {
                                        Text("\(index + 1).")
                                            .font(.body)
                                            .fontWeight(.semibold)
                                            .foregroundColor(Color(red: 0.145, green: 0.388, blue: 0.922)) // Industrial blue
                                            .frame(width: 24, alignment: .trailing)
                                        Text(line)
                                            .font(.body)
                                            .foregroundColor(.primary)
                                    }
                                    .accessibilityElement(children: .combine)
                                    .accessibilityLabel("Note \(index + 1): \(line)")
                                }
                            }
                            .accessibilityIdentifier("revisionNotesNumberedList")
                        } else {
                            // Single note - display as plain text
                            Text(notesText)
                                .font(.body)
                                .accessibilityIdentifier("revisionNotesSingleText")
                        }
                    }
                    .padding(.horizontal)
                    .accessibilityIdentifier("revisionNotesSection")
                }

                // Recommendations
                if let recs = snapshot["recommendations"] as? String, !recs.isEmpty {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Recommendations")
                            .font(.headline)
                            .foregroundColor(.secondary)
                        Text(recs)
                            .font(.body)
                    }
                    .padding(.horizontal)
                }

                // Edit notes (if any)
                if let editNotes = revision.editNotes, !editNotes.isEmpty {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Edit Notes")
                            .font(.headline)
                            .foregroundColor(.secondary)
                        Text(editNotes)
                            .font(.body)
                            .italic()
                    }
                    .padding(.horizontal)
                }

                Spacer(minLength: 20)
            }
        }
        .navigationTitle("v\(revision.versionNumber)")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func ownershipLabel(_ type: String) -> String {
        switch type {
        case "personal": return "Personal"
        case "shop": return "Shop"
        case "borrowed": return "Borrowed"
        case "imported": return "Imported"
        default: return "Personal"
        }
    }
}

/// A simple read-only field for revision detail display.
struct RevisionField: View {
    let title: String
    let value: String?
    var color: Color = .primary

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
                .font(.caption)
                .foregroundColor(.secondary)
                .textCase(.uppercase)
            Text(value ?? "Unknown")
                .font(.body)
                .foregroundColor(color)
        }
    }
}

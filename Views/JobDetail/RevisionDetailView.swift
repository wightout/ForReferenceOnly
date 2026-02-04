import SwiftUI
import CoreData

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
                        .background(Color(red: 0.976, green: 0.451, blue: 0.086).opacity(0.1))
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
                    if let editedAt = revision.editedAt {
                        Text(editedAt, style: .date)
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
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

                // Notes
                if let notesText = snapshot["notes"] as? String, !notesText.isEmpty {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Notes & Recommendations")
                            .font(.headline)
                            .foregroundColor(.secondary)
                        Text(notesText)
                            .font(.body)
                    }
                    .padding(.horizontal)
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

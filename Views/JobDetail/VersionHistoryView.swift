import SwiftUI
import CoreData

/// Displays a list of all versions (revisions) for a job record.
/// Users can tap any version to view the historical snapshot.
struct VersionHistoryView: View {
    @ObservedObject var job: JobRecord
    @Environment(\.managedObjectContext) private var viewContext

    /// All revisions for this job, sorted by version number descending (newest first)
    private var sortedRevisions: [JobRevision] {
        guard let revisionSet = job.revisions as? Set<JobRevision> else { return [] }
        return revisionSet.sorted { $0.versionNumber > $1.versionNumber }
    }

    var body: some View {
        List {
            // Current version (the live record)
            Section(header: Text("Current Version")) {
                HStack {
                    VStack(alignment: .leading, spacing: 4) {
                        HStack {
                            Text("v\(job.currentVersion)")
                                .font(.headline)
                                .foregroundColor(Color(red: 0.145, green: 0.388, blue: 0.922))
                            Text("(Current)")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                        if let updatedAt = job.updatedAt {
                            Text(updatedAt, style: .date)
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                        Text(job.aircraftType ?? "Unknown Aircraft")
                            .font(.subheadline)
                    }
                    Spacer()
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundColor(.green)
                }
                .padding(.vertical, 4)
            }

            // Historical versions
            if !sortedRevisions.isEmpty {
                Section(header: Text("Previous Versions")) {
                    ForEach(sortedRevisions, id: \.objectID) { revision in
                        NavigationLink(destination: RevisionDetailView(revision: revision)) {
                            HStack {
                                VStack(alignment: .leading, spacing: 4) {
                                    Text("v\(revision.versionNumber)")
                                        .font(.headline)
                                        .foregroundColor(Color(red: 0.392, green: 0.455, blue: 0.545))
                                    if let editedAt = revision.editedAt {
                                        Text(editedAt, style: .date)
                                            .font(.caption)
                                            .foregroundColor(.secondary)
                                    }
                                    if let snapshot = decodeSnapshot(revision.snapshotData) {
                                        Text(snapshot["aircraftType"] as? String ?? "Unknown Aircraft")
                                            .font(.subheadline)
                                            .foregroundColor(.secondary)
                                    }
                                }
                                Spacer()
                                Image(systemName: "clock.arrow.circlepath")
                                    .foregroundColor(.secondary)
                                    .font(.caption)
                            }
                            .padding(.vertical, 4)
                        }
                    }
                }
            } else {
                Section {
                    Text("No previous versions. Editing this job will create version history.")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                        .italic()
                }
            }
        }
        .navigationTitle("Version History")
        .navigationBarTitleDisplayMode(.inline)
    }

    /// Decodes the binary snapshot data into a dictionary
    private func decodeSnapshot(_ data: Data?) -> [String: Any]? {
        guard let data = data else { return nil }
        return try? JSONSerialization.jsonObject(with: data) as? [String: Any]
    }
}

import SwiftUI
import Foundation
import SwiftData

/// Review screen for staged import records with conflict resolution.
/// Shows all entities to be imported, highlights conflicts, and lets the user
/// choose per-conflict: skip, replace, or keep both.
struct ImportStagingReviewView: View {
    let sessionId: UUID
    let repository: FRORepository
    let onComplete: () -> Void
    let onCancel: () -> Void

    @State private var viewModel = ImportStagingViewModel()

    var body: some View {
        NavigationStack {
            Group {
                if viewModel.isLoading {
                    ProgressView("Loading import data...")
                } else if let error = viewModel.errorMessage {
                    ContentUnavailableView {
                        Label("Import Error", systemImage: "exclamationmark.triangle")
                    } description: {
                        Text(error)
                    }
                } else if viewModel.commitComplete {
                    ContentUnavailableView {
                        Label("Import Complete", systemImage: "checkmark.circle")
                    } description: {
                        Text("All items have been imported successfully.")
                    }
                    .onAppear {
                        Task {
                            try? await Task.sleep(for: .seconds(1))
                            onComplete()
                        }
                    }
                } else {
                    importReviewList
                }
            }
            .navigationTitle("Review Import")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        viewModel.cancelImport(repository: repository)
                        onCancel()
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Import") {
                        viewModel.commitImport(repository: repository)
                    }
                    .disabled(!viewModel.canCommit || viewModel.isCommitting)
                }
            }
        }
        .onAppear {
            viewModel.loadStagingRecords(sessionId: sessionId, repository: repository)
        }
    }

    private var importReviewList: some View {
        List {
            // Summary section
            Section {
                HStack {
                    Label("\(viewModel.totalCount) items", systemImage: "square.stack.3d.up")
                    Spacer()
                    if viewModel.conflictCount > 0 {
                        Text("\(viewModel.conflictCount) conflicts")
                            .foregroundStyle(.orange)
                    }
                }

                if viewModel.unresolvedCount > 0 {
                    HStack {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .foregroundStyle(.orange)
                        Text("\(viewModel.unresolvedCount) unresolved conflicts")
                        Spacer()
                    }
                }
            } header: {
                Text("Summary")
            }

            // Bulk actions for conflicts
            if viewModel.conflictCount > 0 {
                Section {
                    Button("Skip All Conflicts") {
                        viewModel.resolveAllConflicts(with: "skip")
                    }
                    Button("Replace All Existing") {
                        viewModel.resolveAllConflicts(with: "replace")
                    }
                    Button("Keep Both (All Conflicts)") {
                        viewModel.resolveAllConflicts(with: "keep_both")
                    }
                } header: {
                    Text("Bulk Actions")
                }
            }

            // Entity type groups
            ForEach(viewModel.groupedRecords, id: \.entityType) { group in
                Section {
                    ForEach(group.records, id: \.id) { record in
                        stagingRecordRow(record)
                    }
                } header: {
                    HStack {
                        Text(viewModel.displayEntityType(group.entityType))
                        Spacer()
                        Text("\(group.records.count)")
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
    }

    @ViewBuilder
    private func stagingRecordRow(_ record: FROImportStaging) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(viewModel.decodedName(for: record))
                .font(.body)

            if let conflictDesc = viewModel.conflictDescription(for: record) {
                HStack(spacing: 4) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .font(.caption)
                        .foregroundStyle(.orange)
                    Text(conflictDesc)
                        .font(.caption)
                        .foregroundStyle(.orange)
                }
            }

            if record.conflictType != nil {
                resolutionPicker(for: record)
            } else {
                Text("New — will be imported")
                    .font(.caption)
                    .foregroundStyle(.green)
            }
        }
        .padding(.vertical, 2)
    }

    @ViewBuilder
    private func resolutionPicker(for record: FROImportStaging) -> some View {
        Picker("Resolution", selection: Binding(
            get: { record.resolution ?? "" },
            set: { newValue in
                if !newValue.isEmpty {
                    viewModel.setResolution(newValue, for: record)
                }
            }
        )) {
            Text("Choose...").tag("")
            Text("Skip").tag("skip")
            Text("Replace Existing").tag("replace")
            Text("Keep Both").tag("keep_both")
        }
        .pickerStyle(.segmented)
        .font(.caption)
    }
}

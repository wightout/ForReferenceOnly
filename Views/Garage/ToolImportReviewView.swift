import SwiftUI
import Foundation
import SwiftData

/// Review screen for importing tools from a `.frotool` bundle.
/// Shows all tools found in the bundle with thumbnails, duplicate warnings,
/// and allows the user to deselect unwanted tools before importing.
/// Ownership defaults to "shop" since imported tools are typically shared inventory.
struct ToolImportReviewView: View {
    @Environment(\.modelContext) private var viewContext
    @Environment(\.dismiss) private var dismiss

    let parseResult: ToolImportService.ImportParseResult
    let onImportComplete: (Int) -> Void

    @State private var toolPreviews: [ToolImportService.ImportedToolPreview]
    @State private var defaultOwnership: String = "shop"
    @State private var isImporting = false
    @State private var showImportError = false
    @State private var importErrorMessage = ""

    private let industrialBlue = Color(red: 0.145, green: 0.388, blue: 0.922)
    private let safetyOrange = Color(red: 0.976, green: 0.451, blue: 0.086)
    private let steelGray = Color(red: 0.392, green: 0.455, blue: 0.545)

    init(parseResult: ToolImportService.ImportParseResult, onImportComplete: @escaping (Int) -> Void) {
        self.parseResult = parseResult
        self.onImportComplete = onImportComplete
        _toolPreviews = State(initialValue: parseResult.tools)
    }

    private var selectedCount: Int {
        toolPreviews.filter { $0.isSelected }.count
    }

    private var duplicateCount: Int {
        toolPreviews.filter { $0.isDuplicate }.count
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                // Summary header
                importSummaryHeader

                List {
                    // Ownership picker
                    Section {
                        Picker("Import as", selection: $defaultOwnership) {
                            Text("Shop").tag("shop")
                            Text("Personal").tag("personal")
                        }
                        .pickerStyle(.segmented)
                    } header: {
                        Text("Default Ownership")
                    } footer: {
                        Text("Imported tools will be assigned this ownership type.")
                    }

                    // Tool list
                    Section {
                        ForEach(toolPreviews.indices, id: \.self) { index in
                            importToolRow(at: index)
                        }
                    } header: {
                        HStack {
                            Text("Tools (\(toolPreviews.count))")
                            Spacer()
                            if duplicateCount > 0 {
                                Text("\(duplicateCount) duplicate\(duplicateCount == 1 ? "" : "s")")
                                    .foregroundColor(safetyOrange)
                            }
                        }
                    }
                }
                .listStyle(.insetGrouped)

                // Bottom import bar
                importActionBar
            }
            .navigationTitle("Import Tools")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cancel") {
                        // Clean up temp directory
                        try? FileManager.default.removeItem(at: parseResult.bundleURL)
                        dismiss()
                    }
                }

                ToolbarItem(placement: .navigationBarTrailing) {
                    Button {
                        toggleSelectAll()
                    } label: {
                        Text(selectedCount == toolPreviews.count ? "Deselect All" : "Select All")
                            .font(.subheadline)
                    }
                }
            }
            .alert("Import Error", isPresented: $showImportError) {
                Button("OK", role: .cancel) { }
            } message: {
                Text(importErrorMessage)
            }
        }
    }

    // MARK: - Summary Header

    private var importSummaryHeader: some View {
        HStack(spacing: 16) {
            // File icon
            Image(systemName: "doc.zipper")
                .font(.title)
                .foregroundColor(industrialBlue)

            VStack(alignment: .leading, spacing: 2) {
                Text("\(toolPreviews.count) tool\(toolPreviews.count == 1 ? "" : "s") found")
                    .font(.headline)
                Text("Exported \(parseResult.exportDate)")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            Spacer()

            // Selected count badge
            Text("\(selectedCount) selected")
                .font(.subheadline)
                .fontWeight(.medium)
                .padding(.horizontal, 10)
                .padding(.vertical, 4)
                .background(industrialBlue.opacity(0.15))
                .foregroundColor(industrialBlue)
                .clipShape(Capsule())
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(Color(.systemBackground))
    }

    // MARK: - Tool Row

    @ViewBuilder
    private func importToolRow(at index: Int) -> some View {
        let preview = toolPreviews[index]

        Button {
            toolPreviews[index].isSelected.toggle()
        } label: {
            HStack(spacing: 12) {
                // Checkbox
                Image(systemName: preview.isSelected ? "checkmark.circle.fill" : "circle")
                    .foregroundColor(preview.isSelected ? industrialBlue : .secondary)
                    .font(.title3)

                // Thumbnail
                if let thumb = preview.heroThumbnail {
                    Image(uiImage: thumb)
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                        .frame(width: 40, height: 40)
                        .clipped()
                        .cornerRadius(6)
                } else {
                    Image(systemName: "wrench.fill")
                        .foregroundColor(steelGray)
                        .font(.body)
                        .frame(width: 40, height: 40)
                        .background(steelGray.opacity(0.1))
                        .cornerRadius(6)
                }

                // Tool info
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 6) {
                        Text(preview.name)
                            .font(.headline)
                            .foregroundColor(.primary)

                        if preview.isDuplicate {
                            Text("Duplicate")
                                .font(.caption2)
                                .fontWeight(.medium)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(safetyOrange.opacity(0.15))
                                .foregroundColor(safetyOrange)
                                .clipShape(Capsule())
                        }
                    }

                    // Context: set/kit membership
                    HStack(spacing: 4) {
                        if let setName = preview.toolSetName {
                            Image(systemName: "square.grid.2x2.fill")
                                .font(.caption2)
                                .foregroundColor(.secondary)
                            Text(setName)
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }

                        if let kitNames = preview.toolKitNames, !kitNames.isEmpty {
                            if preview.toolSetName != nil {
                                Text("·")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                            Image(systemName: "bag.fill")
                                .font(.caption2)
                                .foregroundColor(.secondary)
                            Text(kitNames.joined(separator: ", "))
                                .font(.caption)
                                .foregroundColor(.secondary)
                                .lineLimit(1)
                        }
                    }

                    if let photoNames = preview.photoFileNames, !photoNames.isEmpty {
                        HStack(spacing: 4) {
                            Image(systemName: "camera.fill")
                                .font(.caption2)
                                .foregroundColor(.secondary)
                            Text("\(photoNames.count) photo\(photoNames.count == 1 ? "" : "s")")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                    }
                }

                Spacer()
            }
        }
        .buttonStyle(.plain)
        .opacity(preview.isSelected ? 1.0 : 0.5)
        .accessibilityIdentifier("importToolRow_\(index)")
    }

    // MARK: - Import Action Bar

    private var importActionBar: some View {
        HStack {
            Spacer()

            Button {
                performImport()
            } label: {
                HStack(spacing: 8) {
                    if isImporting {
                        ProgressView()
                            .progressViewStyle(CircularProgressViewStyle(tint: .white))
                            .scaleEffect(0.8)
                    } else {
                        Image(systemName: "square.and.arrow.down")
                    }
                    Text(isImporting ? "Importing..." : "Import \(selectedCount) Tool\(selectedCount == 1 ? "" : "s")")
                        .fontWeight(.semibold)
                }
                .font(.body)
                .foregroundColor(.white)
                .padding(.horizontal, 24)
                .padding(.vertical, 12)
                .background(selectedCount == 0 || isImporting ? Color.gray : industrialBlue)
                .cornerRadius(10)
            }
            .disabled(selectedCount == 0 || isImporting)
            .accessibilityIdentifier("importButton")

            Spacer()
        }
        .padding(.vertical, 12)
        .background(.ultraThinMaterial)
    }

    // MARK: - Actions

    private func toggleSelectAll() {
        let allSelected = selectedCount == toolPreviews.count
        for index in toolPreviews.indices {
            toolPreviews[index].isSelected = !allSelected
        }
    }

    private func performImport() {
        isImporting = true

        let selected = toolPreviews.filter { $0.isSelected }
        guard !selected.isEmpty else {
            isImporting = false
            return
        }

        do {
            let count = try ToolImportService.shared.importSelectedTools(
                selected,
                bundleDir: parseResult.bundleURL,
                defaultOwnership: defaultOwnership,
                context: viewContext
            )
            isImporting = false
            dismiss()
            onImportComplete(count)
        } catch {
            isImporting = false
            importErrorMessage = error.localizedDescription
            showImportError = true
        }
    }
}

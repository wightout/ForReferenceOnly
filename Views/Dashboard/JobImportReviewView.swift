import SwiftUI
import Foundation
import SwiftData

/// Review screen for importing a job from a `.frojob` bundle.
/// Shows the job summary, tools (with match status), parts, consumables, and chemicals.
/// The user can review all data before importing.
struct JobImportReviewView: View {
    @Environment(\.modelContext) private var viewContext
    @Environment(\.dismiss) private var dismiss

    let parseResult: JobImportService.JobImportParseResult
    var onImportComplete: ((JobRecord) -> Void)?

    // Colors
    private let industrialBlue = Color(red: 0.145, green: 0.388, blue: 0.922)
    private let safetyOrange = Color(red: 0.976, green: 0.451, blue: 0.086)
    private let steelGray = Color(red: 0.392, green: 0.455, blue: 0.545)
    private let importedPurple = Color(red: 0.608, green: 0.318, blue: 0.878)

    @State private var selectedToolIndices: Set<Int> = []
    @State private var selectedConsumableIndices: Set<Int> = []
    @State private var selectedChemicalIndices: Set<Int> = []
    @State private var isImporting = false
    @State private var showError = false
    @State private var errorMessage = ""

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {

                    // MARK: - Job Summary Card
                    jobSummaryCard

                    // MARK: - Tools Section
                    if !parseResult.tools.isEmpty {
                        toolsSection
                    }

                    // MARK: - Parts Section
                    if !parseResult.parts.isEmpty {
                        partsSection
                    }

                    // MARK: - Consumables Section
                    if !parseResult.consumables.isEmpty {
                        consumablesSection
                    }

                    // MARK: - Chemicals Section
                    if !parseResult.chemicals.isEmpty {
                        chemicalsSection
                    }

                    // MARK: - Import Button
                    importButton
                        .padding(.top, 8)
                }
                .padding()
            }
            .navigationTitle("Import Job")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cancel") { dismiss() }
                }
            }
            .onAppear {
                // Select all by default
                selectedToolIndices = Set(0..<parseResult.tools.count)
                selectedConsumableIndices = Set(0..<parseResult.consumables.count)
                selectedChemicalIndices = Set(0..<parseResult.chemicals.count)
            }
            .alert("Import Error", isPresented: $showError) {
                Button("OK", role: .cancel) { }
            } message: {
                Text(errorMessage)
            }
            .accessibilityIdentifier("jobImportReviewView")
        }
    }

    // MARK: - Job Summary Card

    private var jobSummaryCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            // Header
            HStack {
                Image(systemName: "doc.text.fill")
                    .foregroundColor(industrialBlue)
                Text("Job Summary")
                    .font(.headline)
                    .fontWeight(.bold)
                Spacer()

                // Export date
                Text("Exported: \(formattedExportDate)")
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }

            Divider()

            // Aircraft Type (title)
            Text(parseResult.job.aircraftType)
                .font(.title3)
                .fontWeight(.bold)
                .foregroundColor(.primary)

            // Metadata grid
            VStack(alignment: .leading, spacing: 6) {
                if let serial = parseResult.job.aircraftSerialNumber, !serial.isEmpty {
                    metadataRow("Serial Number", serial)
                }
                if let nNumber = parseResult.job.nNumber, !nNumber.isEmpty {
                    metadataRow("N-Number / Tail", nNumber)
                }
                if !parseResult.job.system.isEmpty {
                    metadataRow("System", parseResult.job.system)
                }
                if let component = parseResult.job.component, !component.isEmpty {
                    metadataRow("Component", component)
                }
                if let dateStr = parseResult.job.jobDate, !dateStr.isEmpty {
                    metadataRow("Job Date", dateStr)
                }
            }

            // Task Description preview
            if let desc = parseResult.job.taskDescription, !desc.isEmpty {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Task Description")
                        .font(.caption)
                        .fontWeight(.semibold)
                        .foregroundColor(steelGray)
                    Text(desc)
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .lineLimit(3)
                }
                .padding(.top, 4)
            }

            // Counts summary
            HStack(spacing: 12) {
                countBadge("\(parseResult.tools.count)", "Tools", industrialBlue)
                countBadge("\(parseResult.parts.count)", "Parts", steelGray)
                countBadge("\(parseResult.consumables.count)", "Consumables", safetyOrange)
                countBadge("\(parseResult.chemicals.count)", "Chemicals", importedPurple)
            }
            .padding(.top, 4)
        }
        .padding()
        .background(Color(UIColor.secondarySystemBackground))
        .cornerRadius(12)
        .accessibilityIdentifier("jobSummaryCard")
    }

    // MARK: - Tools Section

    private var toolsSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            sectionHeader("Tools", count: parseResult.tools.count, selectedCount: selectedToolIndices.count)

            ForEach(Array(parseResult.tools.enumerated()), id: \.offset) { index, preview in
                HStack(spacing: 10) {
                    // Selection checkbox
                    Button {
                        if selectedToolIndices.contains(index) {
                            selectedToolIndices.remove(index)
                        } else {
                            selectedToolIndices.insert(index)
                        }
                    } label: {
                        Image(systemName: selectedToolIndices.contains(index) ? "checkmark.circle.fill" : "circle")
                            .foregroundColor(selectedToolIndices.contains(index) ? industrialBlue : .secondary)
                    }

                    // Tool icon
                    Image(systemName: "wrench.fill")
                        .font(.caption)
                        .foregroundColor(preview.isNewTool ? importedPurple : industrialBlue)

                    // Tool name + match status
                    VStack(alignment: .leading, spacing: 2) {
                        Text(preview.displayName)
                            .font(.subheadline)
                            .fontWeight(.medium)

                        if let groupName = preview.exportedTool.groupName, !groupName.isEmpty {
                            Text("Set: \(groupName)")
                                .font(.caption2)
                                .foregroundColor(.secondary)
                        }
                    }

                    Spacer()

                    // Match status badge
                    if preview.isNewTool {
                        Text("NEW")
                            .font(.caption2)
                            .fontWeight(.bold)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(importedPurple.opacity(0.15))
                            .foregroundColor(importedPurple)
                            .clipShape(Capsule())
                    } else {
                        Text("MATCHED")
                            .font(.caption2)
                            .fontWeight(.bold)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Color.green.opacity(0.15))
                            .foregroundColor(.green)
                            .clipShape(Capsule())
                    }
                }
                .padding(.vertical, 4)
                .accessibilityIdentifier("importToolRow_\(index)")
            }
        }
        .padding()
        .background(Color(UIColor.secondarySystemBackground))
        .cornerRadius(12)
    }

    // MARK: - Parts Section

    private var partsSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Image(systemName: "shippingbox.fill")
                    .foregroundColor(steelGray)
                Text("Parts")
                    .font(.headline)
                    .fontWeight(.bold)
                Spacer()
                Text("\(parseResult.parts.count)")
                    .font(.caption)
                    .fontWeight(.bold)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 2)
                    .background(steelGray.opacity(0.15))
                    .foregroundColor(steelGray)
                    .clipShape(Capsule())
            }

            ForEach(Array(parseResult.parts.enumerated()), id: \.offset) { index, part in
                HStack(spacing: 10) {
                    Image(systemName: "gearshape.fill")
                        .font(.caption)
                        .foregroundColor(steelGray)

                    VStack(alignment: .leading, spacing: 2) {
                        Text(part.nomenclature ?? part.partNumber ?? "Unknown Part")
                            .font(.subheadline)
                            .fontWeight(.medium)

                        HStack(spacing: 8) {
                            if let pn = part.partNumber, !pn.isEmpty {
                                Text("P/N: \(pn)")
                                    .font(.caption2)
                                    .foregroundColor(.secondary)
                            }
                            if part.quantity > 1 {
                                Text("Qty: \(part.quantity)")
                                    .font(.caption2)
                                    .foregroundColor(.secondary)
                            }
                            if let nsn = part.nsn, !nsn.isEmpty {
                                Text("NSN: \(nsn)")
                                    .font(.caption2)
                                    .foregroundColor(.secondary)
                            }
                        }
                    }
                    Spacer()
                }
                .padding(.vertical, 2)
            }

            // Note that parts are always imported
            HStack(spacing: 6) {
                Image(systemName: "info.circle")
                    .font(.caption2)
                    .foregroundColor(.secondary)
                Text("All parts will be imported with this job.")
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }
        }
        .padding()
        .background(Color(UIColor.secondarySystemBackground))
        .cornerRadius(12)
    }

    // MARK: - Consumables Section

    private var consumablesSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            sectionHeader("Consumables", count: parseResult.consumables.count, selectedCount: selectedConsumableIndices.count)

            ForEach(Array(parseResult.consumables.enumerated()), id: \.offset) { index, preview in
                HStack(spacing: 10) {
                    Button {
                        if selectedConsumableIndices.contains(index) {
                            selectedConsumableIndices.remove(index)
                        } else {
                            selectedConsumableIndices.insert(index)
                        }
                    } label: {
                        Image(systemName: selectedConsumableIndices.contains(index) ? "checkmark.circle.fill" : "circle")
                            .foregroundColor(selectedConsumableIndices.contains(index) ? industrialBlue : .secondary)
                    }

                    Text(preview.displayName)
                        .font(.subheadline)

                    Spacer()

                    if preview.isNew {
                        Text("NEW")
                            .font(.caption2)
                            .fontWeight(.bold)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(importedPurple.opacity(0.15))
                            .foregroundColor(importedPurple)
                            .clipShape(Capsule())
                    } else {
                        Text("MATCHED")
                            .font(.caption2)
                            .fontWeight(.bold)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Color.green.opacity(0.15))
                            .foregroundColor(.green)
                            .clipShape(Capsule())
                    }
                }
                .padding(.vertical, 2)
            }
        }
        .padding()
        .background(Color(UIColor.secondarySystemBackground))
        .cornerRadius(12)
    }

    // MARK: - Chemicals Section

    private var chemicalsSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            sectionHeader("Chemicals", count: parseResult.chemicals.count, selectedCount: selectedChemicalIndices.count)

            ForEach(Array(parseResult.chemicals.enumerated()), id: \.offset) { index, preview in
                HStack(spacing: 10) {
                    Button {
                        if selectedChemicalIndices.contains(index) {
                            selectedChemicalIndices.remove(index)
                        } else {
                            selectedChemicalIndices.insert(index)
                        }
                    } label: {
                        Image(systemName: selectedChemicalIndices.contains(index) ? "checkmark.circle.fill" : "circle")
                            .foregroundColor(selectedChemicalIndices.contains(index) ? industrialBlue : .secondary)
                    }

                    Text(preview.displayName)
                        .font(.subheadline)

                    Spacer()

                    if preview.isNew {
                        Text("NEW")
                            .font(.caption2)
                            .fontWeight(.bold)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(importedPurple.opacity(0.15))
                            .foregroundColor(importedPurple)
                            .clipShape(Capsule())
                    } else {
                        Text("MATCHED")
                            .font(.caption2)
                            .fontWeight(.bold)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Color.green.opacity(0.15))
                            .foregroundColor(.green)
                            .clipShape(Capsule())
                    }
                }
                .padding(.vertical, 2)
            }
        }
        .padding()
        .background(Color(UIColor.secondarySystemBackground))
        .cornerRadius(12)
    }

    // MARK: - Import Button

    private var importButton: some View {
        Button {
            performImport()
        } label: {
            HStack {
                if isImporting {
                    ProgressView()
                        .tint(.white)
                } else {
                    Image(systemName: "square.and.arrow.down.fill")
                        .foregroundColor(.white)
                }
                Text(isImporting ? "Importing..." : "Import Job")
                    .fontWeight(.semibold)
                    .foregroundColor(.white)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 14)
            .background(isImporting ? steelGray : industrialBlue)
            .cornerRadius(12)
        }
        .disabled(isImporting)
        .accessibilityIdentifier("importJobButton")
    }

    // MARK: - Helpers

    private func metadataRow(_ label: String, _ value: String) -> some View {
        HStack(spacing: 8) {
            Text(label)
                .font(.caption)
                .fontWeight(.semibold)
                .foregroundColor(steelGray)
                .frame(width: 120, alignment: .leading)
            Text(value)
                .font(.caption)
                .foregroundColor(.primary)
        }
    }

    private func countBadge(_ count: String, _ label: String, _ color: Color) -> some View {
        VStack(spacing: 2) {
            Text(count)
                .font(.headline)
                .fontWeight(.bold)
                .foregroundColor(color)
            Text(label)
                .font(.caption2)
                .foregroundColor(.secondary)
        }
    }

    private func sectionHeader(_ title: String, count: Int, selectedCount: Int) -> some View {
        HStack {
            Image(systemName: "tray.full.fill")
                .foregroundColor(industrialBlue)
            Text(title)
                .font(.headline)
                .fontWeight(.bold)
            Spacer()
            Text("\(selectedCount)/\(count) selected")
                .font(.caption)
                .foregroundColor(.secondary)
        }
    }

    private var formattedExportDate: String {
        let isoFormatter = ISO8601DateFormatter()
        if let date = isoFormatter.date(from: parseResult.exportDate) {
            let displayFormatter = DateFormatter()
            displayFormatter.dateStyle = .medium
            displayFormatter.timeStyle = .short
            return displayFormatter.string(from: date)
        }
        return parseResult.exportDate
    }

    // MARK: - Import Action

    private func performImport() {
        guard !isImporting else { return }
        isImporting = true

        do {
            let jobRecord = try JobImportService.shared.importJob(
                from: parseResult,
                selectedToolIndices: selectedToolIndices,
                selectedConsumableIndices: selectedConsumableIndices,
                selectedChemicalIndices: selectedChemicalIndices,
                context: viewContext
            )
            onImportComplete?(jobRecord)
            dismiss()
        } catch {
            errorMessage = error.localizedDescription
            showError = true
            isImporting = false
        }
    }
}

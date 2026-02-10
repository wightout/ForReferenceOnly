import SwiftUI
import Foundation
import SwiftData

/// Full detail view for a saved job record.
/// Displays all metadata, linked tools, consumables, chemicals, notes, and TM references.
struct JobDetailView: View {
    @Bindable var job: JobRecord
    @Environment(\.modelContext) private var viewContext
    @Environment(\.dismiss) private var dismiss

    /// Controls the delete confirmation alert
    @State private var showDeleteConfirmation = false
    /// Prevents double-tap delete from causing issues - idempotency guard
    @State private var isDeleting = false
    /// Controls the edit sheet presentation
    @State private var showingEditSheet = false
    /// Controls the share sheet presentation for PDF export
    @State private var showingShareSheet = false
    /// URL to the generated PDF file for sharing
    @State private var pdfURL: URL?
    /// Controls the PDF generation error alert
    @State private var showPDFError = false
    // Note: PDF export from jobs is always read-only. Fillable forms are generated from Settings.
    /// Controls the share sheet for .frojob export
    @State private var showingJobShareSheet = false
    /// URL to the generated .frojob file for sharing
    @State private var frojobURL: URL?
    /// Controls the .frojob generation error alert
    @State private var showJobExportError = false

    /// Sorted list of tools linked to this job
    /// Sorted by size (smallest to largest), inch-standard before metric, tools without sizes at end
    private var linkedTools: [Tool] {
        guard let toolSet = job.tools else { return [] }
        return Array(toolSet).sortedBySize()
    }

    /// Feature #158: Groups tools by their Tool Set (tool.group) for display in Job Detail view
    /// Returns dictionary: Set name -> [Tool]
    private var toolsBySet: [String: [Tool]] {
        var result: [String: [Tool]] = [:]
        for tool in linkedTools {
            if let toolSet = tool.group, !toolSet.name.isEmpty {
                result[toolSet.name, default: []].append(tool)
            }
        }
        return result
    }

    /// Feature #158: Tool IDs that have been displayed in a Tool Set
    /// Used to avoid showing the same tool in multiple sections
    private var toolIDsInSets: Set<UUID> {
        var ids: Set<UUID> = []
        for tool in linkedTools {
            if let toolSet = tool.group, !toolSet.name.isEmpty {
                ids.insert(tool.id)
            }
        }
        return ids
    }

    /// Feature #159: Groups tools by their Tool Kit for display in Job Detail view
    /// Returns dictionary: Kit name -> [Tool]
    /// Tools can belong to multiple kits, but appear only once (in first kit alphabetically)
    /// Excludes tools already shown in Tool Sets (Feature #158)
    private var toolsByKit: [String: [Tool]] {
        var result: [String: [Tool]] = [:]
        var processedToolIDs: Set<UUID> = []

        for tool in linkedTools {
            let toolID = tool.id

            // Skip if already shown in a Tool Set (Feature #158)
            if toolIDsInSets.contains(toolID) { continue }

            // Skip if already processed
            if processedToolIDs.contains(toolID) { continue }

            // Check if tool belongs to any Tool Kit
            if let toolKits = tool.toolKits {
                let kitsWithNames = toolKits.compactMap { kit -> (String, ToolKit)? in
                    guard !kit.name.isEmpty else { return nil }
                    return (kit.name, kit)
                }

                if let firstKit = kitsWithNames.sorted(by: { $0.0 < $1.0 }).first {
                    // Add to the first kit alphabetically (tool appears only once)
                    result[firstKit.0, default: []].append(tool)
                    processedToolIDs.insert(toolID)
                }
            }
        }

        return result
    }

    /// Feature #159: Tools that don't belong to any Tool Kit or Tool Set
    /// Excludes tools already shown in Tool Sets (Feature #158)
    private var ungroupedTools: [Tool] {
        linkedTools.filter { tool in
            let toolID = tool.id

            // Exclude if shown in a Tool Set
            if toolIDsInSets.contains(toolID) { return false }

            // Exclude if belongs to any Tool Kit
            guard let toolKits = tool.toolKits else { return true }
            let kitsWithNames = toolKits.compactMap { kit -> String? in
                guard !kit.name.isEmpty else { return nil }
                return kit.name
            }
            return kitsWithNames.isEmpty
        }
    }

    /// Sorted list of consumables linked to this job
    private var linkedConsumables: [Consumable] {
        guard let set = job.consumables else { return [] }
        return set.sorted { ($0.name) < ($1.name) }
    }

    /// Sorted list of chemicals linked to this job
    private var linkedChemicals: [Chemical] {
        guard let set = job.chemicals else { return [] }
        return set.sorted { ($0.name) < ($1.name) }
    }

    /// Feature #141: Sorted list of parts linked to this job
    private var linkedParts: [Part] {
        guard let set = job.parts else { return [] }
        return set.sorted { $0.nomenclature < $1.nomenclature }
    }

    /// Total number of versions (current + historical revisions)
    private var revisionCount: Int {
        let historicalCount = job.revisions?.count ?? 0
        return historicalCount + 1 // +1 for current version
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                froBannerSection
                aircraftInfoSection
                Divider().padding(.horizontal)
                taskDescriptionSection
                tmReferencesSection
                toolsUsedSection
                consumablesSection
                chemicalsSection
                partsSection
                notesSection
                recommendationsSection
                shareButtonsSection
                versionInfoSection
                deleteSection
            }
        }
        .navigationTitle(job.aircraftType)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                toolbarButtons
            }
        }
        .sheet(isPresented: $showingEditSheet) {
            EditJobView(job: job)
        }
        .sheet(isPresented: $showingShareSheet) {
            if let url = pdfURL {
                ShareSheetView(activityItems: [url])
            }
        }
        .sheet(isPresented: $showingJobShareSheet) {
            if let url = frojobURL {
                ShareSheetView(activityItems: [url])
            }
        }
        .alert("PDF Error", isPresented: $showPDFError) {
            Button("OK", role: .cancel) { }
        } message: {
            Text("Failed to generate the PDF report. Please try again.")
        }
        .alert("Export Error", isPresented: $showJobExportError) {
            Button("OK", role: .cancel) { }
        } message: {
            Text("Failed to create the FRO Job export. Please try again.")
        }
        .alert("Delete Job Record", isPresented: $showDeleteConfirmation) {
            Button("Cancel", role: .cancel) { }
            Button("Delete", role: .destructive) {
                deleteJobRecord()
            }
        } message: {
            Text("Are you sure you want to delete this job record? This action cannot be undone.")
        }
    }

    // MARK: - Extracted Sub-Views

    @ViewBuilder
    private var froBannerSection: some View {
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
                .accessibilityLabel("For Reference Only disclaimer banner")
            Spacer()
        }
        .padding(.top, 8)
    }

    @ViewBuilder
    private var aircraftInfoSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            DetailSection(title: "Aircraft Type") {
                Text(job.aircraftType)
                    .font(.title3)
                    .fontWeight(.semibold)
            }

            if let serial = job.aircraftSerialNumber, !serial.isEmpty {
                DetailSection(title: "Serial Number") {
                    Text(serial)
                        .font(.body)
                }
            }

            if let nNum = job.nNumber, !nNum.isEmpty {
                DetailSection(title: "N-Number / Tail Number") {
                    Text(nNum)
                        .font(.body)
                }
            }

            DetailSection(title: "System") {
                Text(job.system)
                    .font(.body)
                    .foregroundColor(Color(red: 0.145, green: 0.388, blue: 0.922))
            }

            if let comp = job.component, !comp.isEmpty {
                DetailSection(title: "Component") {
                    Text(comp)
                        .font(.body)
                }
            }

            DetailSection(title: "Job Date") {
                Text(job.jobDate, style: .date)
                    .font(.body)
            }
        }
        .padding(.horizontal)
    }

    @ViewBuilder
    private var taskDescriptionSection: some View {
        if let desc = job.taskDescription, !desc.isEmpty {
            VStack(alignment: .leading, spacing: 6) {
                Text("Task Description")
                    .font(.headline)
                    .foregroundColor(.secondary)
                Text(desc)
                    .font(.body)
            }
            .padding(.horizontal)
        }
    }

    @ViewBuilder
    private var tmReferencesSection: some View {
        if let tm = job.tmReferences, !tm.isEmpty {
            VStack(alignment: .leading, spacing: 6) {
                Text("TM References")
                    .font(.headline)
                    .foregroundColor(.secondary)
                Text(tm)
                    .font(.system(.body, design: .monospaced))
            }
            .padding(.horizontal)
        }
    }

    @ViewBuilder
    private var toolsUsedSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Tools Used")
                .font(.headline)
                .foregroundColor(.secondary)
                .padding(.horizontal)
                .accessibilityIdentifier("toolsUsedHeader")

            if linkedTools.isEmpty {
                Text("No tools recorded")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                    .italic()
                    .padding(.horizontal)
                    .accessibilityIdentifier("noToolsMessage")
            } else {
                toolSetsSectionContent
                toolKitsSectionContent
                ungroupedToolsSectionContent
            }
        }
        .accessibilityIdentifier("toolsUsedSection")
    }

    @ViewBuilder
    private var toolSetsSectionContent: some View {
        let sortedSetNames = toolsBySet.keys.sorted()
        ForEach(sortedSetNames, id: \.self) { setName in
            if let setTools = toolsBySet[setName] {
                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 6) {
                        Image(systemName: "square.grid.2x2.fill")
                            .foregroundColor(Color(red: 0.145, green: 0.388, blue: 0.922))
                            .font(.caption)
                        Text(setName)
                            .font(.body)
                            .fontWeight(.bold)
                            .foregroundColor(Color(red: 0.145, green: 0.388, blue: 0.922))
                    }
                    .padding(.horizontal)
                    .padding(.top, 4)
                    .accessibilityIdentifier("toolSetHeader_\(setName)")

                    ForEach(setTools.sortedBySize(), id: \.id) { tool in
                        toolRow(tool: tool, identifier: "toolSetTool")
                    }
                }
                .padding(.bottom, 8)
            }
        }
    }

    @ViewBuilder
    private var toolKitsSectionContent: some View {
        let sortedKitNames = toolsByKit.keys.sorted()
        ForEach(sortedKitNames, id: \.self) { kitName in
            if let kitTools = toolsByKit[kitName] {
                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 6) {
                        Image(systemName: "bag.fill")
                            .foregroundColor(Color(red: 0.133, green: 0.545, blue: 0.133))
                            .font(.caption)
                        Text(kitName)
                            .font(.body)
                            .fontWeight(.bold)
                            .foregroundColor(Color(red: 0.133, green: 0.545, blue: 0.133))
                    }
                    .padding(.horizontal)
                    .padding(.top, 4)
                    .accessibilityIdentifier("toolKitHeader_\(kitName)")

                    ForEach(kitTools.sortedBySize(), id: \.id) { tool in
                        toolRow(tool: tool, identifier: "toolKitTool")
                    }
                }
                .padding(.bottom, 8)
            }
        }
    }

    @ViewBuilder
    private var ungroupedToolsSectionContent: some View {
        if !ungroupedTools.isEmpty {
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    Image(systemName: "wrench.fill")
                        .foregroundColor(Color(red: 0.392, green: 0.455, blue: 0.545))
                        .font(.caption)
                    Text("Individual Tools")
                        .font(.body)
                        .fontWeight(.bold)
                        .foregroundColor(Color(red: 0.392, green: 0.455, blue: 0.545))
                }
                .padding(.horizontal)
                .padding(.top, 4)
                .accessibilityIdentifier("individualToolsHeader")

                ForEach(ungroupedTools.sortedBySize(), id: \.id) { tool in
                    toolRow(tool: tool, identifier: "individualTool")
                }
            }
        }
    }

    @ViewBuilder
    private func toolRow(tool: Tool, identifier: String) -> some View {
        HStack(spacing: 6) {
            Spacer().frame(width: 16)
            Image(systemName: "wrench.fill")
                .foregroundColor(Color(red: 0.392, green: 0.455, blue: 0.545))
                .font(.caption)
            VStack(alignment: .leading, spacing: 1) {
                Text(tool.name)
                    .font(.body)
                Text(ownershipLabel(for: tool))
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            Spacer()
        }
        .padding(.horizontal)
        .padding(.vertical, 2)
        .accessibilityIdentifier("\(identifier)_\(tool.name)")
    }

    @ViewBuilder
    private var consumablesSection: some View {
        if !linkedConsumables.isEmpty {
            VStack(alignment: .leading, spacing: 8) {
                Text("Consumables Used")
                    .font(.headline)
                    .foregroundColor(.secondary)
                    .padding(.horizontal)

                ForEach(linkedConsumables, id: \.id) { consumable in
                    HStack {
                        Image(systemName: "bolt.fill")
                            .foregroundColor(Color(red: 0.392, green: 0.455, blue: 0.545))
                            .font(.caption)
                        Text(consumable.name)
                            .font(.body)
                        Spacer()
                    }
                    .padding(.horizontal)
                    .padding(.vertical, 2)
                }
            }
        }
    }

    @ViewBuilder
    private var chemicalsSection: some View {
        if !linkedChemicals.isEmpty {
            VStack(alignment: .leading, spacing: 8) {
                Text("Chemicals Used")
                    .font(.headline)
                    .foregroundColor(.secondary)
                    .padding(.horizontal)

                ForEach(linkedChemicals, id: \.id) { chemical in
                    HStack {
                        Image(systemName: "drop.fill")
                            .foregroundColor(Color(red: 0.392, green: 0.455, blue: 0.545))
                            .font(.caption)
                        Text(chemical.name)
                            .font(.body)
                        Spacer()
                    }
                    .padding(.horizontal)
                    .padding(.vertical, 2)
                }
            }
        }
    }

    @ViewBuilder
    private var partsSection: some View {
        if !linkedParts.isEmpty {
            VStack(alignment: .leading, spacing: 8) {
                Text("Parts Used")
                    .font(.headline)
                    .foregroundColor(.secondary)
                    .padding(.horizontal)

                ForEach(linkedParts, id: \.id) { part in
                    VStack(alignment: .leading, spacing: 2) {
                        HStack {
                            Image(systemName: "gearshape.2.fill")
                                .foregroundColor(Color(red: 0.392, green: 0.455, blue: 0.545))
                                .font(.caption)
                            Text(part.nomenclature)
                                .font(.body)
                            Spacer()
                            if part.quantity > 1 {
                                Text("Qty: \(part.quantity)")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                        }
                        HStack(spacing: 12) {
                            Text("P/N: \(part.partNumber)")
                                .font(.caption)
                                .foregroundColor(.secondary)
                            if let alt = part.alternatePartNumber, !alt.isEmpty {
                                Text("Alt: \(alt)")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                            if let nsn = part.nsn, !nsn.isEmpty {
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
    }

    @ViewBuilder
    private var notesSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Notes")
                .font(.headline)
                .foregroundColor(.secondary)
                .accessibilityIdentifier("notesHeader")

            if let notesText = job.notes, !notesText.isEmpty {
                let noteLines = notesText.components(separatedBy: .newlines).filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty }

                if noteLines.isEmpty {
                    notesEmptyState
                } else {
                    VStack(alignment: .leading, spacing: 8) {
                        ForEach(Array(noteLines.enumerated()), id: \.offset) { index, line in
                            HStack(alignment: .top, spacing: 10) {
                                Text("\(index + 1).")
                                    .font(.body)
                                    .fontWeight(.semibold)
                                    .foregroundColor(Color(red: 0.145, green: 0.388, blue: 0.922))
                                    .frame(width: 24, alignment: .trailing)
                                    .accessibilityHidden(true)
                                Text(line)
                                    .font(.body)
                                    .foregroundColor(.primary)
                                    .accessibilityIdentifier("noteItem\(index + 1)")
                            }
                            .accessibilityElement(children: .combine)
                            .accessibilityLabel("Note \(index + 1): \(line)")
                            .accessibilityIdentifier("noteRow\(index + 1)")
                        }
                    }
                    .accessibilityIdentifier("notesNumberedList")
                }
            } else {
                notesEmptyState
            }
        }
        .padding(.horizontal)
        .accessibilityIdentifier("notesSection")
    }

    @ViewBuilder
    private var notesEmptyState: some View {
        Text("No notes recorded")
            .font(.subheadline)
            .foregroundColor(.secondary)
            .italic()
            .accessibilityIdentifier("notesEmptyState")
    }

    @ViewBuilder
    private var recommendationsSection: some View {
        if let recs = job.recommendations, !recs.isEmpty {
            VStack(alignment: .leading, spacing: 6) {
                Text("Recommendations")
                    .font(.headline)
                    .foregroundColor(.secondary)
                Text(recs)
                    .font(.body)
            }
            .padding(.horizontal)
        }
    }

    @ViewBuilder
    private var shareButtonsSection: some View {
        // Share as PDF button — generates read-only PDF
        Button {
            generateAndSharePDF()
        } label: {
            HStack {
                Image(systemName: "doc.text.fill")
                    .foregroundColor(.white)
                Text("Share as PDF")
                    .fontWeight(.semibold)
                    .foregroundColor(.white)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 12)
            .background(Color(red: 0.145, green: 0.388, blue: 0.922))
            .cornerRadius(10)
        }
        .padding(.horizontal)
        .accessibilityIdentifier("shareAsPDFButton")
        .accessibilityLabel("Share as PDF")
        .accessibilityHint("Opens format selection for PDF export")

        // Share as FRO Job button — exports .frojob bundle for mechanic-to-mechanic sharing
        Button {
            generateAndShareFROJob()
        } label: {
            HStack {
                Image(systemName: "arrow.up.doc.fill")
                    .foregroundColor(Color(red: 0.145, green: 0.388, blue: 0.922))
                Text("Share as FRO Job")
                    .fontWeight(.semibold)
                    .foregroundColor(Color(red: 0.145, green: 0.388, blue: 0.922))
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 12)
            .background(Color(red: 0.145, green: 0.388, blue: 0.922).opacity(0.12))
            .cornerRadius(10)
            .overlay(
                RoundedRectangle(cornerRadius: 10)
                    .stroke(Color(red: 0.145, green: 0.388, blue: 0.922).opacity(0.3), lineWidth: 1)
            )
        }
        .padding(.horizontal)
        .accessibilityIdentifier("shareAsFROJobButton")
        .accessibilityLabel("Share as FRO Job")
        .accessibilityHint("Exports this job as an importable FRO Job bundle")
    }

    @ViewBuilder
    private var versionInfoSection: some View {
        VStack(spacing: 8) {
            HStack {
                Text("Version \(job.currentVersion)")
                    .font(.caption)
                    .foregroundColor(.secondary)
                Spacer()
                Text("Created: \(job.createdAt, style: .date)")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            NavigationLink(destination: VersionHistoryView(job: job)) {
                HStack {
                    Image(systemName: "clock.arrow.circlepath")
                        .foregroundColor(Color(red: 0.145, green: 0.388, blue: 0.922))
                    Text("Version History")
                        .foregroundColor(Color(red: 0.145, green: 0.388, blue: 0.922))
                    Spacer()
                    Text("\(revisionCount) version\(revisionCount == 1 ? "" : "s")")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    Image(systemName: "chevron.right")
                        .foregroundColor(.secondary)
                        .font(.caption)
                }
                .padding(.vertical, 8)
                .padding(.horizontal, 12)
                .background(Color(red: 0.145, green: 0.388, blue: 0.922).opacity(0.08))
                .cornerRadius(8)
            }
            .accessibilityIdentifier("versionHistoryButton")
            .accessibilityLabel("Version History")
            .accessibilityHint("View \(revisionCount) version\(revisionCount == 1 ? "" : "s") of this job record")
        }
        .padding(.horizontal)
    }

    @ViewBuilder
    private var deleteSection: some View {
        Divider()
            .padding(.horizontal)
            .padding(.top, 16)

        Button(role: .destructive) {
            showDeleteConfirmation = true
        } label: {
            HStack {
                Image(systemName: "trash.fill")
                Text("Delete Job Record")
                    .fontWeight(.semibold)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 14)
            .background(isDeleting ? Color.gray.opacity(0.3) : Color.red.opacity(0.1))
            .foregroundColor(isDeleting ? .gray : .red)
            .cornerRadius(10)
            .overlay(
                RoundedRectangle(cornerRadius: 10)
                    .stroke(isDeleting ? Color.gray : Color.red, lineWidth: 1)
            )
        }
        .disabled(isDeleting)
        .padding(.horizontal)
        .padding(.bottom, 40)
        .accessibilityIdentifier("deleteButton")
        .accessibilityLabel("Delete Job Record")
        .accessibilityHint("Permanently removes this job record")
    }

    @ViewBuilder
    private var toolbarButtons: some View {
        HStack(spacing: 16) {
            Button {
                generateAndSharePDF()
            } label: {
                Image(systemName: "square.and.arrow.up")
                    .foregroundColor(Color(red: 0.145, green: 0.388, blue: 0.922))
            }
            .accessibilityIdentifier("shareButton")
            .accessibilityLabel("Share Job as PDF")
            .accessibilityHint("Generates a read-only PDF to share")

            Button {
                showingEditSheet = true
            } label: {
                Image(systemName: "pencil")
                    .foregroundColor(Color(red: 0.145, green: 0.388, blue: 0.922))
            }
            .accessibilityIdentifier("editButton")
            .accessibilityLabel("Edit Job")
            .accessibilityHint("Opens form to edit this job record")
        }
    }

    // MARK: - Actions

    /// Deletes the job record and dismisses the view.
    /// This function is idempotent - calling it multiple times will only delete once.
    private func deleteJobRecord() {
        guard !isDeleting else {
            print("JobDetailView: Delete already in progress, ignoring duplicate call")
            return
        }
        isDeleting = true

        guard !job.isDeleted else {
            print("JobDetailView: Job already deleted or invalid, dismissing")
            dismiss()
            return
        }

        let aircraftType = job.aircraftType
        viewContext.delete(job)
        do {
            try viewContext.save()
            print("JobDetailView: Deleted job record for '\(aircraftType)' successfully")
        } catch {
            print("JobDetailView: Failed to delete job record, rolled back - \(error)")
            isDeleting = false
            return
        }
        dismiss()
    }

    /// Generates a .frojob bundle from the current job record and presents the share sheet.
    private func generateAndShareFROJob() {
        if let url = JobExportService.shared.exportJob(job) {
            frojobURL = url
            showingJobShareSheet = true
            print("JobDetailView: .frojob bundle generated at \(url.path)")
        } else {
            showJobExportError = true
            print("JobDetailView: Failed to generate .frojob bundle for job '\(job.aircraftType)'")
        }
    }

    /// Generates a read-only PDF from the current job record and presents the share sheet.
    private func generateAndSharePDF() {
        if let url = PDFService.generatePDFFile(for: job) {
            pdfURL = url
            showingShareSheet = true
            print("JobDetailView: PDF generated at \(url.path)")
        } else {
            showPDFError = true
            print("JobDetailView: Failed to generate PDF for job '\(job.aircraftType)'")
        }
    }

    private func ownershipLabel(for tool: Tool) -> String {
        switch tool.ownershipType {
        case "personal": return "Personal"
        case "shop": return "Shop"
        case "borrowed": return "Borrowed"
        case "imported": return "Imported"
        default: return "Personal"
        }
    }
}

/// UIKit wrapper for UIActivityViewController to share files via iOS share sheet.
struct ShareSheetView: UIViewControllerRepresentable {
    let activityItems: [Any]
    var applicationActivities: [UIActivity]? = nil

    func makeUIViewController(context: Context) -> UIActivityViewController {
        let controller = UIActivityViewController(
            activityItems: activityItems,
            applicationActivities: applicationActivities
        )
        return controller
    }

    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}

/// A simple detail section with a title label and content.
struct DetailSection<Content: View>: View {
    let title: String
    @ViewBuilder let content: () -> Content

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
                .font(.caption)
                .foregroundColor(.secondary)
                .textCase(.uppercase)
            content()
        }
    }
}

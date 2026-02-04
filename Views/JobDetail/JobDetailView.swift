import SwiftUI
import CoreData

/// Full detail view for a saved job record.
/// Displays all metadata, linked tools, consumables, chemicals, notes, and TM references.
struct JobDetailView: View {
    @ObservedObject var job: JobRecord
    @Environment(\.managedObjectContext) private var viewContext
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

    /// Sorted list of tools linked to this job
    private var linkedTools: [Tool] {
        guard let toolSet = job.tools as? Set<Tool> else { return [] }
        return toolSet.sorted { ($0.name ?? "") < ($1.name ?? "") }
    }

    /// Sorted list of consumables linked to this job
    private var linkedConsumables: [Consumable] {
        guard let set = job.consumables as? Set<Consumable> else { return [] }
        return set.sorted { ($0.name ?? "") < ($1.name ?? "") }
    }

    /// Sorted list of chemicals linked to this job
    private var linkedChemicals: [Chemical] {
        guard let set = job.chemicals as? Set<Chemical> else { return [] }
        return set.sorted { ($0.name ?? "") < ($1.name ?? "") }
    }

    /// Total number of versions (current + historical revisions)
    private var revisionCount: Int {
        let historicalCount = (job.revisions as? Set<JobRevision>)?.count ?? 0
        return historicalCount + 1 // +1 for current version
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
                        .accessibilityLabel("For Reference Only disclaimer banner")
                    Spacer()
                }
                .padding(.top, 8)

                // Aircraft & Job Info
                VStack(alignment: .leading, spacing: 12) {
                    DetailSection(title: "Aircraft Type") {
                        Text(job.aircraftType ?? "Unknown")
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
                        Text(job.system ?? "Unknown")
                            .font(.body)
                            .foregroundColor(Color(red: 0.145, green: 0.388, blue: 0.922))
                    }

                    if let comp = job.component, !comp.isEmpty {
                        DetailSection(title: "Component") {
                            Text(comp)
                                .font(.body)
                        }
                    }

                    if let date = job.jobDate {
                        DetailSection(title: "Job Date") {
                            Text(date, style: .date)
                                .font(.body)
                        }
                    }
                }
                .padding(.horizontal)

                Divider().padding(.horizontal)

                // Task Description
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

                // TM References
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

                // Tools Used
                VStack(alignment: .leading, spacing: 8) {
                    Text("Tools Used")
                        .font(.headline)
                        .foregroundColor(.secondary)
                        .padding(.horizontal)

                    if linkedTools.isEmpty {
                        Text("No tools recorded")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                            .italic()
                            .padding(.horizontal)
                    } else {
                        ForEach(linkedTools, id: \.objectID) { tool in
                            HStack {
                                Image(systemName: "wrench.fill")
                                    .foregroundColor(Color(red: 0.392, green: 0.455, blue: 0.545))
                                    .font(.caption)
                                VStack(alignment: .leading, spacing: 1) {
                                    Text(tool.name ?? "Unnamed Tool")
                                        .font(.body)
                                    Text(ownershipLabel(for: tool))
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                }
                                Spacer()
                            }
                            .padding(.horizontal)
                            .padding(.vertical, 4)
                        }
                    }
                }

                // Consumables Used
                if !linkedConsumables.isEmpty {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Consumables Used")
                            .font(.headline)
                            .foregroundColor(.secondary)
                            .padding(.horizontal)

                        ForEach(linkedConsumables, id: \.objectID) { consumable in
                            HStack {
                                Image(systemName: "bolt.fill")
                                    .foregroundColor(Color(red: 0.392, green: 0.455, blue: 0.545))
                                    .font(.caption)
                                Text(consumable.name ?? "Unnamed")
                                    .font(.body)
                                Spacer()
                            }
                            .padding(.horizontal)
                            .padding(.vertical, 2)
                        }
                    }
                }

                // Chemicals Used
                if !linkedChemicals.isEmpty {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Chemicals Used")
                            .font(.headline)
                            .foregroundColor(.secondary)
                            .padding(.horizontal)

                        ForEach(linkedChemicals, id: \.objectID) { chemical in
                            HStack {
                                Image(systemName: "drop.fill")
                                    .foregroundColor(Color(red: 0.392, green: 0.455, blue: 0.545))
                                    .font(.caption)
                                Text(chemical.name ?? "Unnamed")
                                    .font(.body)
                                Spacer()
                            }
                            .padding(.horizontal)
                            .padding(.vertical, 2)
                        }
                    }
                }

                // Notes
                if let notesText = job.notes, !notesText.isEmpty {
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

                // Share as PDF button
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
                .accessibilityHint("Generates a PDF report and opens the share sheet")

                // Version info & History
                VStack(spacing: 8) {
                    HStack {
                        Text("Version \(job.currentVersion)")
                            .font(.caption)
                            .foregroundColor(.secondary)
                        Spacer()
                        if let created = job.createdAt {
                            Text("Created: \(created, style: .date)")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                    }

                    NavigationLink(destination: VersionHistoryView(job: job).environment(\.managedObjectContext, viewContext)) {
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
                .padding(.bottom, 20)
            }
        }
        .navigationTitle(job.aircraftType ?? "Job Detail")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                HStack(spacing: 16) {
                    Button {
                        showingEditSheet = true
                    } label: {
                        Image(systemName: "pencil")
                            .foregroundColor(Color(red: 0.145, green: 0.388, blue: 0.922))
                    }
                    .accessibilityLabel("Edit Job")
                    .accessibilityHint("Opens form to edit this job record")

                    Button(role: .destructive) {
                        showDeleteConfirmation = true
                    } label: {
                        Image(systemName: "trash")
                            .foregroundColor(isDeleting ? .gray : .red)
                    }
                    .disabled(isDeleting)
                    .accessibilityLabel("Delete Job")
                    .accessibilityHint("Permanently removes this job record")
                }
            }
        }
        .sheet(isPresented: $showingEditSheet) {
            EditJobView(job: job)
                .environment(\.managedObjectContext, viewContext)
        }
        .sheet(isPresented: $showingShareSheet) {
            if let url = pdfURL {
                ShareSheetView(activityItems: [url])
            }
        }
        .alert("PDF Error", isPresented: $showPDFError) {
            Button("OK", role: .cancel) { }
        } message: {
            Text("Failed to generate the PDF report. Please try again.")
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

    /// Deletes the job record from Core Data and dismisses the view.
    /// This function is idempotent - calling it multiple times (e.g., from rapid double-tap)
    /// will only delete the job once and will not crash.
    private func deleteJobRecord() {
        // Guard against double-execution (e.g., rapid tapping of confirm button)
        guard !isDeleting else {
            print("JobDetailView: Delete already in progress, ignoring duplicate call")
            return
        }
        isDeleting = true

        // Check if the managed object is still valid and not already deleted
        guard !job.isDeleted && !job.isFault else {
            print("JobDetailView: Job already deleted or invalid, dismissing")
            dismiss()
            return
        }

        let aircraftType = job.aircraftType ?? "unknown"
        viewContext.delete(job)
        do {
            try viewContext.save()
            print("JobDetailView: Deleted job record for '\(aircraftType)' successfully")
        } catch {
            viewContext.rollback()
            print("JobDetailView: Failed to delete job record, rolled back - \(error)")
            // Reset flag on error so user can try again
            isDeleting = false
            return
        }
        dismiss()
    }

    /// Generates a PDF from the current job record and presents the share sheet.
    private func generateAndSharePDF() {
        if let url = PDFService.generatePDFFile(for: job) {
            pdfURL = url
            showingShareSheet = true
            print("JobDetailView: PDF generated at \(url.path)")
        } else {
            showPDFError = true
            print("JobDetailView: Failed to generate PDF for job '\(job.aircraftType ?? "unknown")'")
        }
    }

    private func ownershipLabel(for tool: Tool) -> String {
        switch tool.ownershipType {
        case "personal": return "Personal"
        case "shop": return "Shop"
        case "borrowed": return "Borrowed"
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

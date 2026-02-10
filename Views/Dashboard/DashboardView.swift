import SwiftUI
import Foundation
import SwiftData
import UniformTypeIdentifiers

/// Dashboard view showing recent jobs and quick stats.
struct DashboardView: View {
    @Environment(\.modelContext) private var viewContext

    /// Binding to the selected tab index so the empty state CTA can switch to New Job tab
    @Binding var selectedTab: Int

    /// Which type of file import the user triggered (nil = file picker not shown)
    enum ImportType { case pdf, frojob }
    @State private var activeImportType: ImportType?
    @State private var showingFileImporter = false

    // PDF import state
    @State private var showingImportReview = false
    @State private var importedData: ImportedJobData?
    @State private var showImportError = false
    @State private var importErrorMessage = ""

    // .frojob import state
    @State private var showingFrojobImportReview = false
    @State private var frojobParseResult: JobImportService.JobImportParseResult?
    @State private var showFrojobImportSuccess = false
    @State private var importedJobAircraftType = ""

    /// Fetch recent job records, most recent by job date first
    /// Feature #74: Sort by jobDate for correct date boundary sorting (Dec 31 before Jan 1)
    @Query(sort: \FROJob.jobDate, order: .reverse)
    private var jobRecords: [FROJob]

    @Query(sort: \FROTool.name, order: .forward)
    private var tools: [FROTool]

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 20) {
                    // FRO Banner
                    Text("FOR REFERENCE ONLY")
                        .font(.caption)
                        .fontWeight(.bold)
                        .foregroundColor(Color(red: 0.976, green: 0.451, blue: 0.086)) // Safety orange
                        .padding(.horizontal, 12)
                        .padding(.vertical, 4)
                        .background(Color(red: 0.976, green: 0.451, blue: 0.086).opacity(0.2))
                        .cornerRadius(4)
                        .padding(.top, 8)
                        .accessibilityLabel("For Reference Only disclaimer banner")

                    // Quick Stats
                    HStack(spacing: 16) {
                        StatCard(
                            title: "Jobs Logged",
                            value: "\(jobRecords.count)",
                            icon: "doc.text.fill",
                            color: Color(red: 0.145, green: 0.388, blue: 0.922)
                        )
                        StatCard(
                            title: "Tools",
                            value: "\(tools.count)",
                            icon: "wrench.fill",
                            color: Color(red: 0.392, green: 0.455, blue: 0.545)
                        )
                    }
                    .padding(.horizontal)

                    // Recent Jobs Section or Empty State
                    if jobRecords.isEmpty {
                        // Empty state
                        VStack(spacing: 16) {
                            Image(systemName: "airplane")
                                .font(.system(size: 60))
                                .foregroundColor(Color(red: 0.392, green: 0.455, blue: 0.545))
                            Text("Welcome to FRO")
                                .font(.title2)
                                .fontWeight(.bold)
                            Text("For Reference Only")
                                .font(.subheadline)
                                .foregroundColor(Color(red: 0.976, green: 0.451, blue: 0.086))
                            Text("Start logging your maintenance jobs\nto build your personal reference library.")
                                .font(.body)
                                .foregroundColor(.secondary)
                                .multilineTextAlignment(.center)

                            // Large tap target for gloved hands (60pt+ height)
                            Button(action: {
                                selectedTab = 1 // Switch to New Job tab
                            }) {
                                Text("Log Your First Job")
                                    .font(.title3)
                                    .fontWeight(.bold)
                                    .foregroundColor(.white)
                                    .padding(.horizontal, 32)
                                    .padding(.vertical, 16)
                                    .background(Color(red: 0.145, green: 0.388, blue: 0.922))
                                    .cornerRadius(12)
                            }
                            .frame(minHeight: 60)
                            .accessibilityLabel("Log Your First Job")
                            .accessibilityHint("Opens the New Job form to create your first maintenance record")
                            .padding(.top, 8)
                        }
                        .padding(.top, 40)
                    } else {
                        // Recent jobs list
                        VStack(alignment: .leading, spacing: 12) {
                            Text("Recent Jobs")
                                .font(.title3)
                                .fontWeight(.semibold)
                                .padding(.horizontal)

                            ForEach(jobRecords.prefix(10), id: \.id) { job in
                                NavigationLink(destination: JobDetailView(job: job)) {
                                    JobCardView(job: job)
                                }
                                .buttonStyle(.plain)
                                .padding(.horizontal)
                            }
                        }
                    }

                    Spacer(minLength: 20)
                }
            }
            .navigationTitle("Dashboard")
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Menu {
                        Button {
                            activeImportType = .pdf
                            showingFileImporter = true
                        } label: {
                            Label("Import from PDF", systemImage: "doc.richtext")
                        }
                        Button {
                            activeImportType = .frojob
                            showingFileImporter = true
                        } label: {
                            Label("Import FRO Job", systemImage: "doc.zipper")
                        }
                    } label: {
                        Image(systemName: "square.and.arrow.down")
                            .foregroundColor(Color(red: 0.145, green: 0.388, blue: 0.922))
                    }
                    .accessibilityIdentifier("importButton")
                    .accessibilityLabel("Import")
                    .accessibilityHint("Import a job from PDF or FRO Job file")
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    NavigationLink(destination: AboutView()) {
                        Image(systemName: "gearshape.fill")
                            .foregroundColor(Color(red: 0.392, green: 0.455, blue: 0.545)) // Steel gray
                            .accessibilityLabel("Settings")
                    }
                }
            }
            .fileImporter(
                isPresented: $showingFileImporter,
                allowedContentTypes: allowedContentTypes,
                allowsMultipleSelection: false
            ) { result in
                switch result {
                case .success(let urls):
                    guard let url = urls.first else { return }
                    handleImportedFile(url)
                case .failure(let error):
                    importErrorMessage = error.localizedDescription
                    showImportError = true
                }
            }
            .sheet(isPresented: $showingImportReview) {
                if let data = importedData {
                    ImportJobView(importedData: data)
                        
                }
            }
            .sheet(isPresented: $showingFrojobImportReview) {
                if let parseResult = frojobParseResult {
                    JobImportReviewView(
                        parseResult: parseResult,
                        onImportComplete: { jobRecord in
                            importedJobAircraftType = jobRecord.aircraftType
                            showFrojobImportSuccess = true
                        }
                    )
                    
                }
            }
            .alert("Import Error", isPresented: $showImportError) {
                Button("OK", role: .cancel) { }
            } message: {
                Text(importErrorMessage)
            }
            .alert("Job Imported!", isPresented: $showFrojobImportSuccess) {
                Button("OK") { }
            } message: {
                Text("'\(importedJobAircraftType)' job imported successfully.")
            }
        }
    }
    // MARK: - Import Helpers

    /// Returns the allowed UTTypes based on which import type the user selected.
    private var allowedContentTypes: [UTType] {
        switch activeImportType {
        case .pdf:
            return [.pdf]
        case .frojob:
            return [UTType(exportedAs: "com.forreference.frojob"), .data]
        case .none:
            return [.data]
        }
    }

    /// Handles a file URL returned from the file importer, routing to PDF or .frojob logic.
    private func handleImportedFile(_ url: URL) {
        switch activeImportType {
        case .pdf:
            do {
                importedData = try ImportService.importFromPDF(url: url)
                showingImportReview = true
            } catch {
                importErrorMessage = error.localizedDescription
                showImportError = true
            }
        case .frojob:
            do {
                frojobParseResult = try JobImportService.shared.parseFrojobBundle(
                    at: url,
                    context: viewContext
                )
                showingFrojobImportReview = true
            } catch {
                importErrorMessage = error.localizedDescription
                showImportError = true
            }
        case .none:
            break
        }
    }
}

/// Quick stat card for the dashboard
struct StatCard: View {
    let title: String
    let value: String
    let icon: String
    let color: Color

    var body: some View {
        VStack(spacing: 8) {
            Image(systemName: icon)
                .font(.title2)
                .foregroundColor(color)
                .accessibilityHidden(true)
            Text(value)
                .font(.title)
                .fontWeight(.bold)
                .accessibilityHidden(true)
            Text(title)
                .font(.caption)
                .foregroundColor(.secondary)
                .accessibilityHidden(true)
        }
        .frame(maxWidth: .infinity)
        .padding()
        .background(Color(.systemBackground))
        .cornerRadius(12)
        .shadow(color: .black.opacity(0.05), radius: 4, y: 2)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(value) \(title)")
    }
}

/// Simple job card for the dashboard recent jobs list
struct JobCardView: View {
    @Bindable var job: JobRecord

    private var accessibilityDescription: String {
        var parts: [String] = []
        if !job.aircraftType.isEmpty {
            parts.append(job.aircraftType)
        }
        if !job.system.isEmpty {
            parts.append(job.system)
        }
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        parts.append(formatter.string(from: job.jobDate))
        return parts.joined(separator: ", ")
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(job.aircraftType.isEmpty ? "Unknown Aircraft" : job.aircraftType)
                    .font(.headline)
                Spacer()
                Text(job.jobDate, style: .date)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            if !job.system.isEmpty {
                Text(job.system)
                    .font(.subheadline)
                    .foregroundColor(Color(red: 0.145, green: 0.388, blue: 0.922))
            }
            if let desc = job.taskDescription, !desc.isEmpty {
                Text(desc)
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .lineLimit(2)
            }
        }
        .padding()
        .background(Color(.systemBackground))
        .cornerRadius(10)
        .shadow(color: .black.opacity(0.05), radius: 3, y: 1)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Job record: \(accessibilityDescription)")
        .accessibilityHint("Double tap to view job details")
    }
}

#Preview {
    DashboardView(selectedTab: .constant(0))
        
}

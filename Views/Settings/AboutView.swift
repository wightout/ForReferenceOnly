import SwiftUI
import UniformTypeIdentifiers

/// About/Info screen displaying app information and the FRO disclaimer.
/// Accessed via the gear icon in the Dashboard navigation bar.
/// Also provides data management options including clearing all data and exporting data.
struct AboutView: View {
    @Environment(\.modelContext) private var viewContext

    /// App version retrieved from Info.plist (MARKETING_VERSION)
    private var appVersion: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "0.1.0"
    }

    /// Build number retrieved from Info.plist (CURRENT_PROJECT_VERSION)
    private var buildNumber: String {
        Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "1"
    }

    /// Controls whether the clear data confirmation alert is shown
    @State private var showClearDataConfirmation = false

    /// Controls whether the success/error alert is shown
    @State private var showResultAlert = false
    @State private var resultAlertTitle = ""
    @State private var resultAlertMessage = ""

    /// Thumbnail display toggle — syncs with GarageView row views via @AppStorage
    @AppStorage("showToolThumbnails") private var showToolThumbnails = true

    /// Controls the share sheet for exporting data
    @State private var showShareSheet = false
    @State private var exportFileURL: URL?

    /// Controls export in-progress state
    @State private var isExporting = false

    // Import state
    @State private var showingFileImporter = false
    @State private var showingImportReview = false
    @State private var importedData: ImportedJobData?
    @State private var showImportError = false
    @State private var importErrorMessage = ""

    var body: some View {
        ScrollView {
            VStack(spacing: 24) {
                // App Icon and Name
                VStack(spacing: 12) {
                    // App icon representation
                    ZStack {
                        RoundedRectangle(cornerRadius: 20)
                            .fill(
                                LinearGradient(
                                    colors: [
                                        Color(red: 0.145, green: 0.388, blue: 0.922), // Industrial blue
                                        Color(red: 0.1, green: 0.3, blue: 0.7)
                                    ],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                )
                            )
                            .frame(width: 100, height: 100)

                        Image(systemName: "wrench.and.screwdriver.fill")
                            .font(.system(size: 44))
                            .foregroundColor(.white)
                    }
                    .padding(.top, 20)

                    Text("For Reference Only")
                        .font(.title)
                        .fontWeight(.bold)
                        .foregroundColor(Color(red: 0.118, green: 0.161, blue: 0.231)) // Dark charcoal

                    Text("FRO")
                        .font(.title3)
                        .fontWeight(.medium)
                        .foregroundColor(Color(red: 0.392, green: 0.455, blue: 0.545)) // Steel gray
                }

                // Version Info
                VStack(spacing: 4) {
                    Text("Version \(appVersion)")
                        .font(.headline)
                        .foregroundColor(Color(red: 0.118, green: 0.161, blue: 0.231))

                    Text("Build \(buildNumber)")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                }
                .padding(.vertical, 8)

                // FRO Disclaimer - Prominent
                VStack(spacing: 12) {
                    Text("FOR REFERENCE ONLY")
                        .font(.headline)
                        .fontWeight(.bold)
                        .foregroundColor(Color(red: 0.976, green: 0.451, blue: 0.086)) // Safety orange

                    Text("This app is a personal reference tool for aircraft maintenance professionals. It captures practical tribal knowledge—tools used, consumables, workarounds, and execution notes—to help mechanics prepare for repeat tasks.")
                        .font(.body)
                        .multilineTextAlignment(.center)
                        .foregroundColor(Color(red: 0.118, green: 0.161, blue: 0.231))

                    Text("This is NOT authoritative maintenance data. Always refer to official Technical Manuals, Work Cards, and approved maintenance procedures for actual maintenance tasks.")
                        .font(.callout)
                        .fontWeight(.medium)
                        .multilineTextAlignment(.center)
                        .foregroundColor(Color(red: 0.976, green: 0.451, blue: 0.086))
                        .padding(.top, 4)
                }
                .padding()
                .background(Color(red: 0.976, green: 0.451, blue: 0.086).opacity(0.2))
                .cornerRadius(12)
                .padding(.horizontal)

                // Features Section
                VStack(alignment: .leading, spacing: 12) {
                    Text("Features")
                        .font(.headline)
                        .foregroundColor(Color(red: 0.118, green: 0.161, blue: 0.231))
                        .padding(.horizontal)

                    AboutFeatureRow(icon: "doc.text.fill", title: "Job Records", description: "Log and track maintenance jobs")
                    AboutFeatureRow(icon: "wrench.fill", title: "Garage", description: "Manage your personal tool inventory")
                    AboutFeatureRow(icon: "mic.fill", title: "Voice Capture", description: "Record post-task brain dumps")
                    AboutFeatureRow(icon: "magnifyingglass", title: "Search", description: "Find jobs by any field")
                    AboutFeatureRow(icon: "doc.richtext", title: "PDF Reports", description: "Share job summaries")
                }
                .padding(.vertical)

                // Preferences Section
                VStack(alignment: .leading, spacing: 12) {
                    Text("Preferences")
                        .font(.headline)
                        .foregroundColor(Color(red: 0.118, green: 0.161, blue: 0.231))
                        .padding(.horizontal)

                    // Tool Thumbnails Toggle
                    HStack {
                        Image(systemName: "photo.fill")
                            .font(.title3)
                            .foregroundColor(Color(red: 0.145, green: 0.388, blue: 0.922))
                            .frame(width: 30)

                        VStack(alignment: .leading, spacing: 2) {
                            Text("Tool Thumbnails")
                                .font(.subheadline)
                                .fontWeight(.medium)
                                .foregroundColor(Color(red: 0.118, green: 0.161, blue: 0.231))

                            Text("Show photo thumbnails when browsing tools in the Garage")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }

                        Spacer()

                        Toggle("", isOn: $showToolThumbnails)
                            .labelsHidden()
                            .accessibilityIdentifier("showToolThumbnailsToggle")
                    }
                    .padding(.horizontal)
                    .padding(.vertical, 8)
                }
                .padding(.vertical)
                .background(Color(.systemBackground))
                .cornerRadius(12)
                .padding(.horizontal)

                // Data Management Section
                VStack(alignment: .leading, spacing: 12) {
                    Text("Data Management")
                        .font(.headline)
                        .foregroundColor(Color(red: 0.118, green: 0.161, blue: 0.231))
                        .padding(.horizontal)

                    // Export Data Button - Feature #86
                    Button(action: {
                        exportData()
                    }) {
                        HStack {
                            if isExporting {
                                ProgressView()
                                    .frame(width: 30)
                            } else {
                                Image(systemName: "square.and.arrow.up.fill")
                                    .font(.title3)
                                    .foregroundColor(Color(red: 0.145, green: 0.388, blue: 0.922)) // Industrial blue
                                    .frame(width: 30)
                            }

                            VStack(alignment: .leading, spacing: 2) {
                                Text("Export Data for Backup")
                                    .font(.subheadline)
                                    .fontWeight(.medium)
                                    .foregroundColor(Color(red: 0.118, green: 0.161, blue: 0.231))

                                Text("Save all jobs, tools, consumables, and chemicals as JSON")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }

                            Spacer()

                            Image(systemName: "chevron.right")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                        .padding(.horizontal)
                        .padding(.vertical, 8)
                    }
                    .buttonStyle(.plain)
                    .disabled(isExporting)
                    .accessibilityIdentifier("exportDataButton")

                    Divider()
                        .padding(.horizontal)

                    // Import from PDF Button
                    Button(action: {
                        showingFileImporter = true
                    }) {
                        HStack {
                            Image(systemName: "square.and.arrow.down.fill")
                                .font(.title3)
                                .foregroundColor(Color(red: 0.145, green: 0.388, blue: 0.922))
                                .frame(width: 30)

                            VStack(alignment: .leading, spacing: 2) {
                                Text("Import from PDF")
                                    .font(.subheadline)
                                    .fontWeight(.medium)
                                    .foregroundColor(Color(red: 0.118, green: 0.161, blue: 0.231))

                                Text("Create a job record from an FRO PDF report")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }

                            Spacer()

                            Image(systemName: "chevron.right")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                        .padding(.horizontal)
                        .padding(.vertical, 8)
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("importFromPDFButton")

                    Divider()
                        .padding(.horizontal)

                    // Blank Fillable Form Button
                    Button(action: {
                        generateBlankTemplate()
                    }) {
                        HStack {
                            Image(systemName: "doc.badge.plus")
                                .font(.title3)
                                .foregroundColor(Color(red: 0.145, green: 0.388, blue: 0.922))
                                .frame(width: 30)

                            VStack(alignment: .leading, spacing: 2) {
                                Text("Blank Fillable Form")
                                    .font(.subheadline)
                                    .fontWeight(.medium)
                                    .foregroundColor(Color(red: 0.118, green: 0.161, blue: 0.231))

                                Text("Generate a blank FRO form to fill out on a computer")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }

                            Spacer()

                            Image(systemName: "chevron.right")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                        .padding(.horizontal)
                        .padding(.vertical, 8)
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("blankFillableFormButton")

                    Divider()
                        .padding(.horizontal)

                    Button(action: {
                        showClearDataConfirmation = true
                    }) {
                        HStack {
                            Image(systemName: "trash.fill")
                                .font(.title3)
                                .foregroundColor(.red)
                                .frame(width: 30)

                            VStack(alignment: .leading, spacing: 2) {
                                Text("Clear All Data")
                                    .font(.subheadline)
                                    .fontWeight(.medium)
                                    .foregroundColor(.red)

                                Text("Delete all jobs, tools, consumables, and chemicals")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }

                            Spacer()

                            Image(systemName: "chevron.right")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                        .padding(.horizontal)
                        .padding(.vertical, 8)
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("clearAllDataButton")
                }
                .padding(.vertical)
                .background(Color(.systemBackground))
                .cornerRadius(12)
                .padding(.horizontal)

                // Technology Stack
                VStack(spacing: 8) {
                    Text("Technology")
                        .font(.caption)
                        .foregroundColor(.secondary)

                    Text("Built with Swift & SwiftUI")
                        .font(.caption)
                        .foregroundColor(.secondary)

                    Text("Local-first • Offline capable")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                .padding(.bottom, 24)
            }
        }
        .background(Color(red: 0.973, green: 0.98, blue: 0.988)) // Light gray #F8FAFC
        .navigationTitle("About")
        .navigationBarTitleDisplayMode(.inline)
        .alert("Clear All Data?", isPresented: $showClearDataConfirmation) {
            Button("Cancel", role: .cancel) {
                // User cancelled - do nothing
            }
            Button("Clear All Data", role: .destructive) {
                clearAllData()
            }
        } message: {
            Text("This will permanently delete all your job records, tools, consumables, and chemicals. This action cannot be undone.")
        }
        .alert(resultAlertTitle, isPresented: $showResultAlert) {
            Button("OK", role: .cancel) { }
        } message: {
            Text(resultAlertMessage)
        }
        .sheet(isPresented: $showShareSheet) {
            if let fileURL = exportFileURL {
                ShareSheet(activityItems: [fileURL])
            }
        }
        .fileImporter(
            isPresented: $showingFileImporter,
            allowedContentTypes: [UTType.pdf],
            allowsMultipleSelection: false
        ) { result in
            switch result {
            case .success(let urls):
                guard let url = urls.first else { return }
                do {
                    importedData = try ImportService.importFromPDF(url: url)
                    showingImportReview = true
                } catch {
                    importErrorMessage = error.localizedDescription
                    showImportError = true
                }
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
        .alert("Import Error", isPresented: $showImportError) {
            Button("OK", role: .cancel) { }
        } message: {
            Text(importErrorMessage)
        }
    }

    /// Clears all data from the database
    private func clearAllData() {
        let result = SharedModelContainer.shared.clearAllData()
        if result.success {
            resultAlertTitle = "Data Cleared"
            resultAlertMessage = "All data has been successfully deleted."
        } else {
            resultAlertTitle = "Error"
            resultAlertMessage = result.error ?? "Failed to clear data. Please try again."
        }
        showResultAlert = true
    }

    /// Exports all data to JSON and presents the share sheet
    /// Feature #86: Export job record data for backup
    private func exportData() {
        isExporting = true
        Task {
            let result = ExportService.shared.exportAllData(context: viewContext)
            isExporting = false
            if result.success, let fileURL = result.fileURL {
                exportFileURL = fileURL
                showShareSheet = true
                if let counts = result.counts {
                    print("Export completed: \(counts.jobRecords) jobs, \(counts.tools) tools, \(counts.consumables) consumables, \(counts.chemicals) chemicals")
                }
            } else {
                resultAlertTitle = "Export Failed"
                resultAlertMessage = result.error ?? "Failed to export data. Please try again."
                showResultAlert = true
            }
        }
    }

    /// Generates a blank fillable PDF template and presents the share sheet.
    private func generateBlankTemplate() {
        if let url = PDFService.generateFillablePDFFile(for: nil) {
            exportFileURL = url
            showShareSheet = true
            print("AboutView: Blank fillable template generated at \(url.path)")
        } else {
            resultAlertTitle = "Error"
            resultAlertMessage = "Failed to generate blank fillable form. Please try again."
            showResultAlert = true
        }
    }
}

/// UIActivityViewController wrapper for SwiftUI share sheet
/// Used to share the exported backup file via iOS share sheet
struct ShareSheet: UIViewControllerRepresentable {
    let activityItems: [Any]
    var applicationActivities: [UIActivity]? = nil

    func makeUIViewController(context: Context) -> UIActivityViewController {
        let controller = UIActivityViewController(
            activityItems: activityItems,
            applicationActivities: applicationActivities
        )
        return controller
    }

    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {
        // No update needed
    }
}

/// Feature row for the About screen
struct AboutFeatureRow: View {
    let icon: String
    let title: String
    let description: String

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.title3)
                .foregroundColor(Color(red: 0.145, green: 0.388, blue: 0.922)) // Industrial blue
                .frame(width: 30)

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.subheadline)
                    .fontWeight(.medium)
                    .foregroundColor(Color(red: 0.118, green: 0.161, blue: 0.231))

                Text(description)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            Spacer()
        }
        .padding(.horizontal)
    }
}

#Preview {
    NavigationStack {
        AboutView()
    }
}

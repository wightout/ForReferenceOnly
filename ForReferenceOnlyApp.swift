import SwiftUI
import SwiftData

@main
struct ForReferenceOnlyApp: App {
    let container: ModelContainer

    /// Tracks whether the user has acknowledged the disclaimer this period.
    @AppStorage("hasCompletedOnboarding") private var hasCompletedOnboarding = false

    /// Stores the date when the user last acknowledged the disclaimer.
    @AppStorage("lastDisclaimerAcknowledgedDate") private var lastAcknowledgedTimestamp: Double = 0

    // MARK: - Deep Link Import State (Feature #142)
    @State private var showingDeepLinkImportReview = false
    @State private var deepLinkParseResult: ToolImportService.ImportParseResult?
    @State private var showDeepLinkImportError = false
    @State private var deepLinkImportErrorMessage = ""
    @State private var showDeepLinkImportSuccess = false
    @State private var deepLinkImportedToolCount = 0

    // MARK: - Deep Link Job Import State
    @State private var showingJobImportReview = false
    @State private var jobImportParseResult: JobImportService.JobImportParseResult?
    @State private var showJobImportSuccess = false
    @State private var importedJobAircraftType = ""

    /// Whether the disclaimer should be shown (first launch or monthly reset).
    private var shouldShowDisclaimer: Bool {
        if !hasCompletedOnboarding {
            return true
        }
        let lastDate = Date(timeIntervalSince1970: lastAcknowledgedTimestamp)
        let daysSince = Calendar.current.dateComponents([.day], from: lastDate, to: Date()).day ?? 0
        return daysSince >= 30
    }

    init() {
        do {
            let schema = Schema([
                FROTool.self,
                FROJob.self,
                FROToolGroup.self,
                FROToolKit.self,
                FROConsumable.self,
                FROChemical.self,
                FROPart.self,
                FROVoiceMemo.self,
                FROJobRevision.self,
                FROAttachment.self,
                FROImportStaging.self
            ])
            let config = ModelConfiguration(isStoredInMemoryOnly: false)
            container = try ModelContainer(for: schema, configurations: [config])
        } catch {
            fatalError("Failed to create ModelContainer: \(error)")
        }
    }

    var body: some Scene {
        WindowGroup {
            Group {
                if !shouldShowDisclaimer {
                    ContentView()
                } else {
                    WelcomeView(onContinue: {
                        withAnimation {
                            hasCompletedOnboarding = true
                            lastAcknowledgedTimestamp = Date().timeIntervalSince1970
                        }
                    })
                }
            }
            // MARK: - Deep Link: Open .frotool and .frojob files from Messages, AirDrop, Mail, Files
            .onOpenURL { url in
                let ext = url.pathExtension.lowercased()
                if ext == "frotool" {
                    handleIncomingFrotoolURL(url)
                } else if ext == "frojob" {
                    handleIncomingFrojobURL(url)
                }
            }
            .sheet(isPresented: $showingDeepLinkImportReview) {
                if let parseResult = deepLinkParseResult {
                    ToolImportReviewView(
                        parseResult: parseResult,
                        onImportComplete: { count in
                            deepLinkImportedToolCount = count
                            showDeepLinkImportSuccess = true
                        }
                    )
                }
            }
            .sheet(isPresented: $showingJobImportReview) {
                if let parseResult = jobImportParseResult {
                    JobImportReviewView(
                        parseResult: parseResult,
                        onImportComplete: { jobRecord in
                            importedJobAircraftType = jobRecord.aircraftType
                            showJobImportSuccess = true
                        }
                    )
                }
            }
            .alert("Import Error", isPresented: $showDeepLinkImportError) {
                Button("OK", role: .cancel) { }
            } message: {
                Text(deepLinkImportErrorMessage)
            }
            .alert("Tools Imported!", isPresented: $showDeepLinkImportSuccess) {
                Button("OK") { }
            } message: {
                Text("\(deepLinkImportedToolCount) tool\(deepLinkImportedToolCount == 1 ? "" : "s") imported successfully.")
            }
            .alert("Job Imported!", isPresented: $showJobImportSuccess) {
                Button("OK") { }
            } message: {
                Text("'\(importedJobAircraftType)' job imported successfully. You can find it in your Dashboard.")
            }
        }
        .modelContainer(container)
    }

    // MARK: - Deep Link Handler

    private func handleIncomingFrotoolURL(_ url: URL) {
        guard url.pathExtension.lowercased() == "frotool" else { return }

        let context = container.mainContext
        do {
            deepLinkParseResult = try ToolImportService.shared.parseFrotoolBundle(
                at: url,
                context: context
            )
            showingDeepLinkImportReview = true
            print("ForReferenceOnlyApp: Parsed .frotool bundle from deep link — \(deepLinkParseResult?.tools.count ?? 0) tool(s) found")
        } catch {
            deepLinkImportErrorMessage = "Could not open the tool export file: \(error.localizedDescription)"
            showDeepLinkImportError = true
            print("ForReferenceOnlyApp: Failed to parse .frotool bundle from deep link — \(error)")
        }
    }

    private func handleIncomingFrojobURL(_ url: URL) {
        let context = container.mainContext
        do {
            jobImportParseResult = try JobImportService.shared.parseFrojobBundle(
                at: url,
                context: context
            )
            showingJobImportReview = true
            print("ForReferenceOnlyApp: Parsed .frojob bundle from deep link — '\(jobImportParseResult?.job.aircraftType ?? "unknown")'")
        } catch {
            deepLinkImportErrorMessage = "Could not open the job export file: \(error.localizedDescription)"
            showDeepLinkImportError = true
            print("ForReferenceOnlyApp: Failed to parse .frojob bundle from deep link — \(error)")
        }
    }
}

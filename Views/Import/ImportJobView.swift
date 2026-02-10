import SwiftUI
import Foundation
import SwiftData

/// View for reviewing and saving data imported from a PDF.
/// Mirrors the NewJobView layout but pre-populated from ImportedJobData.
/// User can edit all fields before saving to Core Data.
struct ImportJobView: View {
    @Environment(\.modelContext) private var viewContext
    @Environment(\.dismiss) private var dismiss

    /// The imported data to review and save
    let importedData: ImportedJobData

    // MARK: - Form State (initialized from importedData)

    @State private var aircraftType: String
    @State private var aircraftSerialNumber: String
    @State private var nNumber: String
    @State private var selectedSystem: String
    @State private var component: String
    @State private var jobDate: Date
    @State private var taskDescription: String
    @State private var tmReferences: String
    @State private var notes: String
    @State private var recommendations: String

    // MARK: - UI State

    @State private var showingSaveSuccess = false
    @State private var showingError = false
    @State private var errorMessage = ""
    @State private var isSaving = false
    @State private var showAircraftTypeRequired = false
    @State private var showSystemRequired = false

    // Design system colors
    private let industrialBlue = Color(red: 0.145, green: 0.388, blue: 0.922)
    private let safetyOrange = Color(red: 0.976, green: 0.451, blue: 0.086)
    private let steelGray = Color(red: 0.392, green: 0.455, blue: 0.545)
    private let successGreen = Color(red: 0.133, green: 0.773, blue: 0.369)

    // MARK: - Init

    init(importedData: ImportedJobData) {
        self.importedData = importedData
        _aircraftType = State(initialValue: importedData.aircraftType)
        _aircraftSerialNumber = State(initialValue: importedData.aircraftSerialNumber ?? "")
        _nNumber = State(initialValue: importedData.nNumber ?? "")
        _selectedSystem = State(initialValue: importedData.system)
        _component = State(initialValue: importedData.component ?? "")
        _jobDate = State(initialValue: importedData.jobDate ?? Date())
        _taskDescription = State(initialValue: importedData.taskDescription ?? "")
        _tmReferences = State(initialValue: importedData.tmReferences ?? "")
        _notes = State(initialValue: importedData.combinedNotes)
        _recommendations = State(initialValue: importedData.recommendations ?? "")
    }

    // MARK: - Body

    var body: some View {
        NavigationStack {
            Form {
                // Import source badge
                Section {
                    HStack(spacing: 8) {
                        Image(systemName: "doc.badge.arrow.up")
                            .font(.body)
                            .foregroundColor(industrialBlue)
                        Text(importedData.source == .fillablePDF
                             ? "Imported from Fillable PDF"
                             : "Imported from PDF Report")
                            .font(.caption)
                            .fontWeight(.medium)
                            .foregroundColor(industrialBlue)
                        Spacer()
                    }
                    .padding(.vertical, 4)
                }

                // FRO Banner
                Section {
                    HStack {
                        Spacer()
                        Text("FOR REFERENCE ONLY")
                            .font(.caption)
                            .fontWeight(.bold)
                            .foregroundColor(safetyOrange)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 4)
                            .background(safetyOrange.opacity(0.2))
                            .cornerRadius(4)
                        Spacer()
                    }
                }

                // MARK: - Aircraft Information
                Section(header: Text("Aircraft Information")) {
                    VStack(alignment: .leading, spacing: 4) {
                        TextField("Aircraft Type (Required)", text: $aircraftType)
                            .font(.body)
                            .autocorrectionDisabled()
                        if showAircraftTypeRequired && aircraftType.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                            Text("Aircraft Type is required")
                                .font(.caption)
                                .foregroundColor(.red)
                        }
                    }

                    TextField("Aircraft Serial Number", text: $aircraftSerialNumber)
                        .font(.body)
                        .autocorrectionDisabled()

                    TextField("N-Number / Tail Number", text: $nNumber)
                        .font(.body)
                        .autocorrectionDisabled()
                }

                // MARK: - System & Component
                Section(header: Text("System & Component")) {
                    VStack(alignment: .leading, spacing: 4) {
                        TextField("System (Required)", text: $selectedSystem)
                            .font(.body)
                            .autocorrectionDisabled()
                        if showSystemRequired && selectedSystem.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                            Text("System is required")
                                .font(.caption)
                                .foregroundColor(.red)
                        }
                    }

                    TextField("Component", text: $component)
                        .font(.body)
                        .autocorrectionDisabled()
                }

                // MARK: - Job Date
                Section(header: Text("Job Date")) {
                    DatePicker("Date", selection: $jobDate, displayedComponents: .date)
                        .datePickerStyle(.graphical)
                }

                // MARK: - Task Description
                Section(header: Text("Task Description")) {
                    TextField("Describe the task performed...", text: $taskDescription, axis: .vertical)
                        .lineLimit(3...8)
                        .font(.body)
                }

                // MARK: - TM References
                Section(header: Text("TM References")) {
                    TextField("e.g., TM 1-1520-237-23, Fig 7-1", text: $tmReferences, axis: .vertical)
                        .lineLimit(2...4)
                        .font(.system(.body, design: .monospaced))
                }

                // MARK: - Notes & Materials
                Section(header: Text("Notes & Materials")) {
                    TextField("Notes, imported tools, consumables, chemicals...", text: $notes, axis: .vertical)
                        .lineLimit(3...10)
                        .font(.body)

                    if importedData.toolsText != nil || importedData.consumablesText != nil || importedData.chemicalsText != nil {
                        HStack(spacing: 6) {
                            Image(systemName: "info.circle")
                                .font(.caption)
                                .foregroundColor(steelGray)
                            Text("Tools, consumables, and chemicals from the PDF have been included as text in the notes above.")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                    }
                }

                // MARK: - Recommendations
                Section(header: Text("Recommendations")) {
                    TextField("Recommendations for next time...", text: $recommendations, axis: .vertical)
                        .lineLimit(3...6)
                        .font(.body)
                }

                // MARK: - Save Button
                Section {
                    Button {
                        saveImportedJob()
                    } label: {
                        HStack {
                            Spacer()
                            if isSaving {
                                ProgressView()
                                    .tint(.white)
                            } else {
                                Image(systemName: "square.and.arrow.down.fill")
                                    .font(.title3)
                                Text("Save Imported Job")
                                    .fontWeight(.bold)
                                    .font(.title3)
                            }
                            Spacer()
                        }
                        .foregroundColor(.white)
                        .padding(.vertical, 16)
                        .background(industrialBlue)
                        .cornerRadius(12)
                    }
                    .disabled(isSaving)
                    .listRowInsets(EdgeInsets())
                    .listRowBackground(Color.clear)
                }
            }
            .navigationTitle("Review Import")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cancel") {
                        dismiss()
                    }
                }
            }
            .alert("Job Imported!", isPresented: $showingSaveSuccess) {
                Button("OK") {
                    dismiss()
                }
            } message: {
                Text("Job record for '\(aircraftType)' has been imported successfully.")
            }
            .alert("Error", isPresented: $showingError) {
                Button("OK") { }
            } message: {
                Text(errorMessage)
            }
        }
    }

    // MARK: - Save

    private func saveImportedJob() {
        // Validate required fields
        let trimmedAircraftType = aircraftType.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedSystem = selectedSystem.trimmingCharacters(in: .whitespacesAndNewlines)

        if trimmedAircraftType.isEmpty {
            showAircraftTypeRequired = true
            errorMessage = "Aircraft Type is required."
            showingError = true
            return
        }

        if trimmedSystem.isEmpty {
            showSystemRequired = true
            errorMessage = "System is required."
            showingError = true
            return
        }

        // Prevent double-tap
        isSaving = true

        let record = FROJob(
            aircraftType: trimmedAircraftType,
            system: trimmedSystem,
            jobDate: jobDate
        )
        viewContext.insert(record)

        // Optional fields - only set if non-empty
        let trimmedSerial = aircraftSerialNumber.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmedSerial.isEmpty {
            record.aircraftSerialNumber = trimmedSerial
        }

        let trimmedNNumber = nNumber.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmedNNumber.isEmpty {
            record.nNumber = trimmedNNumber
        }

        let trimmedComponent = component.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmedComponent.isEmpty {
            record.component = trimmedComponent
        }

        let trimmedDescription = taskDescription.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmedDescription.isEmpty {
            record.taskDescription = trimmedDescription
        }

        let trimmedTM = tmReferences.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmedTM.isEmpty {
            record.tmReferences = trimmedTM
        }

        let trimmedNotes = notes.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmedNotes.isEmpty {
            record.notes = trimmedNotes
        }

        let trimmedRecommendations = recommendations.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmedRecommendations.isEmpty {
            record.recommendations = trimmedRecommendations
        }

        // Smart tool/consumable/chemical linking to Garage entities
        // Parse text into individual items, match against existing Garage, create new ones as "imported"
        linkImportedTools(to: record)
        linkImportedConsumables(to: record)
        linkImportedChemicals(to: record)

        do {
            try viewContext.save()
            print("ImportJobView: Saved imported job for '\(trimmedAircraftType)' - system: \(trimmedSystem), source: \(importedData.source == .fillablePDF ? "fillable PDF" : "read-only PDF")")
            showingSaveSuccess = true
        } catch {
            isSaving = false
            errorMessage = "Failed to save imported job: \(error.localizedDescription)"
            showingError = true
            print("ImportJobView: Save failed, rolled back - \(error)")
        }
    }

    // MARK: - Smart Linking Helpers

    /// Parses the tools text into individual tool names, then matches against existing Garage tools.
    /// Matched tools are linked directly; unmatched tools are created with "imported" ownership.
    private func linkImportedTools(to record: JobRecord) {
        guard let toolsText = importedData.toolsText, !toolsText.isEmpty else { return }

        let toolNames = parseItemList(toolsText)
        guard !toolNames.isEmpty else { return }

        // Fetch existing tools for matching
        let descriptor = FetchDescriptor<FROTool>()
        let existingTools = (try? viewContext.fetch(descriptor)) ?? []
        let existingToolsByName: [String: FROTool] = Dictionary(
            existingTools.map { tool -> (String, FROTool) in
                (tool.name.lowercased(), tool)
            },
            uniquingKeysWith: { first, _ in first }
        )

        var matchedCount = 0
        var createdCount = 0

        for name in toolNames {
            let cleanName = cleanToolName(name)
            guard !cleanName.isEmpty else { continue }

            if let existingTool = existingToolsByName[cleanName.lowercased()] {
                // Link to existing Garage tool
                if record.tools == nil { record.tools = [] }
                record.tools?.append(existingTool)
                matchedCount += 1
            } else {
                // Create new tool with "imported" ownership
                let newTool = FROTool(name: cleanName, ownershipType: "imported")
                viewContext.insert(newTool)
                if record.tools == nil { record.tools = [] }
                record.tools?.append(newTool)
                createdCount += 1
            }
        }

        if matchedCount > 0 || createdCount > 0 {
            print("ImportJobView: Linked \(matchedCount) existing tools, created \(createdCount) new imported tools")
        }
    }

    /// Parses consumables text and links/creates consumables for the job.
    private func linkImportedConsumables(to record: JobRecord) {
        guard let consumablesText = importedData.consumablesText, !consumablesText.isEmpty else { return }

        let itemNames = parseItemList(consumablesText)
        guard !itemNames.isEmpty else { return }

        let consumableDescriptor = FetchDescriptor<FROConsumable>()
        let existing = (try? viewContext.fetch(consumableDescriptor)) ?? []
        let existingByName: [String: FROConsumable] = Dictionary(
            existing.map { item -> (String, FROConsumable) in
                (item.name.lowercased(), item)
            },
            uniquingKeysWith: { first, _ in first }
        )

        for name in itemNames {
            let cleanName = name.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !cleanName.isEmpty else { continue }

            if let existingItem = existingByName[cleanName.lowercased()] {
                if record.consumables == nil { record.consumables = [] }
                record.consumables?.append(existingItem)
            } else {
                let newItem = FROConsumable(name: cleanName)
                viewContext.insert(newItem)
                if record.consumables == nil { record.consumables = [] }
                record.consumables?.append(newItem)
            }
        }
    }

    /// Parses chemicals text and links/creates chemicals for the job.
    private func linkImportedChemicals(to record: JobRecord) {
        guard let chemicalsText = importedData.chemicalsText, !chemicalsText.isEmpty else { return }

        let itemNames = parseItemList(chemicalsText)
        guard !itemNames.isEmpty else { return }

        let chemicalDescriptor = FetchDescriptor<FROChemical>()
        let existing = (try? viewContext.fetch(chemicalDescriptor)) ?? []
        let existingByName: [String: FROChemical] = Dictionary(
            existing.map { item -> (String, FROChemical) in
                (item.name.lowercased(), item)
            },
            uniquingKeysWith: { first, _ in first }
        )

        for name in itemNames {
            let cleanName = name.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !cleanName.isEmpty else { continue }

            if let existingItem = existingByName[cleanName.lowercased()] {
                if record.chemicals == nil { record.chemicals = [] }
                record.chemicals?.append(existingItem)
            } else {
                let newItem = FROChemical(name: cleanName)
                viewContext.insert(newItem)
                if record.chemicals == nil { record.chemicals = [] }
                record.chemicals?.append(newItem)
            }
        }
    }

    /// Parses a text block into individual item names.
    /// Handles newline-separated, comma-separated, and bullet-point formats.
    private func parseItemList(_ text: String) -> [String] {
        // First split by newlines
        var items = text.components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }

        // If only one line, try splitting by commas
        if items.count == 1 {
            items = items[0].components(separatedBy: ",")
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { !$0.isEmpty }
        }

        // Remove bullet points, dashes, numbers at the start
        items = items.map { item in
            var cleaned = item
            // Remove leading bullets: "• ", "- ", "* "
            if cleaned.hasPrefix("• ") || cleaned.hasPrefix("- ") || cleaned.hasPrefix("* ") {
                cleaned = String(cleaned.dropFirst(2))
            }
            // Remove leading numbers: "1. ", "2) "
            if let range = cleaned.range(of: #"^\d+[\.\)]\s*"#, options: .regularExpression) {
                cleaned = String(cleaned[range.upperBound...])
            }
            return cleaned.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        .filter { !$0.isEmpty }

        return items
    }

    /// Cleans a tool name by removing ownership annotations like "(personal)", "(borrowed from X)".
    private func cleanToolName(_ name: String) -> String {
        var cleaned = name
        // Remove trailing ownership annotations: " (personal)", " (shop)", " (borrowed)", " (borrowed from X)", " (imported)"
        if let range = cleaned.range(of: #"\s*\((personal|shop|borrowed(?:\s+from\s+[^)]*)?|imported)\)\s*$"#, options: [.regularExpression, .caseInsensitive]) {
            cleaned = String(cleaned[..<range.lowerBound])
        }
        return cleaned.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

#Preview {
    let sampleData = ImportedJobData(
        aircraftType: "Cessna 172",
        system: "Engine",
        aircraftSerialNumber: "17280001",
        nNumber: "N12345",
        component: "Magneto",
        jobDate: Date(),
        taskDescription: "Removed and inspected magneto points",
        tmReferences: "TM 1-1520-237-23",
        toolsText: "1/4\" socket, 3/8\" wrench",
        consumablesText: "Safety wire .032",
        chemicalsText: nil,
        partsText: nil,
        notes: "Check timing on reinstall",
        recommendations: "Replace points at next 500hr inspection",
        source: .readOnlyPDF
    )

    ImportJobView(importedData: sampleData)
        .modelContainer(for: [FROTool.self, FROJob.self, FROToolGroup.self, FROToolKit.self, FROConsumable.self, FROChemical.self, FROPart.self], inMemory: true)
}

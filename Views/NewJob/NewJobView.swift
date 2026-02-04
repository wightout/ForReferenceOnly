import SwiftUI
import CoreData

/// View for creating new job records with all metadata fields.
/// Saves directly to Core Data via the managed object context.
struct NewJobView: View {
    @Environment(\.managedObjectContext) private var viewContext

    // MARK: - Form State

    @State private var aircraftType: String = ""
    @State private var aircraftSerialNumber: String = ""
    @State private var nNumber: String = ""
    @State private var selectedSystem: String = ""
    @State private var component: String = ""
    @State private var jobDate: Date = Date()
    @State private var taskDescription: String = ""
    @State private var tmReferences: String = ""
    @State private var notes: String = ""

    // MARK: - Tool Selection State

    /// Set of selected tool object IDs from Garage picker
    @State private var selectedToolIDs: Set<NSManagedObjectID> = []
    @State private var showingToolPicker = false

    // MARK: - Consumable Selection State

    /// Set of selected consumable object IDs from Garage picker
    @State private var selectedConsumableIDs: Set<NSManagedObjectID> = []
    @State private var showingConsumablePicker = false

    // MARK: - Chemical Selection State

    /// Set of selected chemical object IDs from Garage picker
    @State private var selectedChemicalIDs: Set<NSManagedObjectID> = []
    @State private var showingChemicalPicker = false

    // MARK: - UI State

    @State private var showingSaveSuccess = false
    @State private var showingError = false
    @State private var errorMessage = ""
    @State private var savedJobAircraftType = ""
    @State private var showAircraftTypeRequired = false
    @State private var showSystemRequired = false
    @State private var showingVoiceCapture = false
    /// Flag to prevent double-tap creating duplicate job records
    @State private var isSaving = false

    // MARK: - System Options

    private let systemOptions = [
        "Hydraulics",
        "Flight Controls",
        "Electrical",
        "Powerplant",
        "Fuel System",
        "Landing Gear",
        "Rotor System",
        "Drive Train",
        "Airframe",
        "Avionics",
        "Environmental Control",
        "Weapons System",
        "Other"
    ]

    /// Whether the form has the minimum required fields filled
    private var canSave: Bool {
        !aircraftType.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
        !selectedSystem.isEmpty
    }

    /// Resolve selected tool object IDs to Tool managed objects
    private var selectedTools: [Tool] {
        selectedToolIDs.compactMap { objectID in
            try? viewContext.existingObject(with: objectID) as? Tool
        }.sorted { ($0.name ?? "") < ($1.name ?? "") }
    }

    /// Resolve selected consumable object IDs to Consumable managed objects
    private var selectedConsumables: [Consumable] {
        selectedConsumableIDs.compactMap { objectID in
            try? viewContext.existingObject(with: objectID) as? Consumable
        }.sorted { ($0.name ?? "") < ($1.name ?? "") }
    }

    /// Resolve selected chemical object IDs to Chemical managed objects
    private var selectedChemicals: [Chemical] {
        selectedChemicalIDs.compactMap { objectID in
            try? viewContext.existingObject(with: objectID) as? Chemical
        }.sorted { ($0.name ?? "") < ($1.name ?? "") }
    }

    var body: some View {
        NavigationStack {
            Form {
                // MARK: - FRO Banner
                Section {
                    HStack {
                        Spacer()
                        Text("FOR REFERENCE ONLY")
                            .font(.caption)
                            .fontWeight(.bold)
                            .foregroundColor(Color(red: 0.976, green: 0.451, blue: 0.086))
                            .accessibilityLabel("For Reference Only disclaimer banner")
                        Spacer()
                    }
                }

                // MARK: - Voice Capture
                Section(header: Text("Voice Capture")) {
                    Button(action: {
                        showingVoiceCapture = true
                    }) {
                        HStack(spacing: 12) {
                            Image(systemName: "mic.circle.fill")
                                .font(.title2)
                                .foregroundColor(Color(red: 0.145, green: 0.388, blue: 0.922))
                            VStack(alignment: .leading, spacing: 2) {
                                Text("Record Voice Memo")
                                    .font(.body)
                                    .fontWeight(.medium)
                                    .foregroundColor(.primary)
                                Text("Speak about your task — auto-transcribes")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                            Spacer()
                            Image(systemName: "chevron.right")
                                .foregroundColor(.secondary)
                                .font(.caption)
                        }
                        .padding(.vertical, 4)
                    }
                    .accessibilityIdentifier("voiceCaptureButton")
                    .accessibilityLabel("Record Voice Memo")
                    .accessibilityHint("Opens voice capture to record and transcribe your task description")
                }

                // MARK: - Aircraft Information
                Section(header: Text("Aircraft Information")) {
                    TextField("Aircraft Type (required)", text: $aircraftType)
                        .font(.body)
                        .autocorrectionDisabled()
                        .accessibilityIdentifier("aircraftTypeField")
                        .accessibilityLabel("Aircraft Type, required field")
                        .onChange(of: aircraftType) { _, newValue in
                            if !newValue.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                                showAircraftTypeRequired = false
                            }
                        }

                    if showAircraftTypeRequired {
                        Text("Aircraft type is required")
                            .font(.caption)
                            .foregroundColor(.red)
                            .accessibilityIdentifier("aircraftTypeRequiredLabel")
                    }

                    TextField("Serial Number", text: $aircraftSerialNumber)
                        .font(.body)
                        .autocorrectionDisabled()
                        .accessibilityIdentifier("serialNumberField")
                        .accessibilityLabel("Aircraft Serial Number")

                    TextField("N-Number / Tail Number", text: $nNumber)
                        .font(.body)
                        .autocorrectionDisabled()
                        .accessibilityIdentifier("nNumberField")
                        .accessibilityLabel("N-Number or Tail Number")
                }

                // MARK: - System & Component
                Section(header: Text("System & Component")) {
                    Picker("System (required)", selection: $selectedSystem) {
                        Text("Select a system").tag("")
                        ForEach(systemOptions, id: \.self) { system in
                            Text(system).tag(system)
                        }
                    }
                    .accessibilityIdentifier("systemPicker")
                    .accessibilityLabel("Aircraft System, required field")
                    .accessibilityHint("Select the system being worked on")
                    .onChange(of: selectedSystem) { _, newValue in
                        if !newValue.isEmpty {
                            showSystemRequired = false
                        }
                    }

                    if showSystemRequired {
                        Text("System is required")
                            .font(.caption)
                            .foregroundColor(.red)
                            .accessibilityIdentifier("systemRequiredLabel")
                    }

                    TextField("Component", text: $component)
                        .font(.body)
                        .autocorrectionDisabled()
                        .accessibilityIdentifier("componentField")
                        .accessibilityLabel("Component")
                }

                // MARK: - Job Date
                Section(header: Text("Job Date")) {
                    DatePicker("Date", selection: $jobDate, displayedComponents: .date)
                        .datePickerStyle(.graphical)
                        .accessibilityIdentifier("jobDatePicker")
                        .accessibilityLabel("Job Date")
                }

                // MARK: - Task Description
                Section(header: Text("Task Description")) {
                    TextField("Describe the task performed", text: $taskDescription, axis: .vertical)
                        .lineLimit(3...8)
                        .font(.body)
                        .accessibilityIdentifier("taskDescriptionField")
                        .accessibilityLabel("Task Description")
                }

                // MARK: - TM References
                Section(header: Text("TM References")) {
                    TextField("e.g., TM 1-1520-237-23, Fig 7-1", text: $tmReferences, axis: .vertical)
                        .lineLimit(2...5)
                        .font(.system(.body, design: .monospaced))
                        .autocorrectionDisabled()
                        .accessibilityIdentifier("tmReferencesField")
                        .accessibilityLabel("Technical Manual References")
                }

                // MARK: - Notes
                Section(header: Text("Notes & Recommendations")) {
                    TextField("Additional notes, tips, or observations", text: $notes, axis: .vertical)
                        .lineLimit(3...8)
                        .font(.body)
                        .accessibilityIdentifier("notesField")
                        .accessibilityLabel("Notes and Recommendations")
                }

                // MARK: - Tools Used
                Section("Tools Used") {
                    if selectedTools.isEmpty {
                        Button(action: { showingToolPicker = true }) {
                            HStack {
                                Image(systemName: "wrench.and.screwdriver")
                                    .foregroundColor(Color(red: 0.145, green: 0.388, blue: 0.922))
                                Text("Add from Garage")
                                    .foregroundColor(Color(red: 0.145, green: 0.388, blue: 0.922))
                                Spacer()
                                Image(systemName: "chevron.right")
                                    .foregroundColor(.secondary)
                                    .font(.caption)
                            }
                        }
                        .accessibilityIdentifier("addToolsFromGarageButton")
                        .accessibilityLabel("Add Tools from Garage")
                        .accessibilityHint("Opens picker to select tools from your Garage")
                    } else {
                        // Show selected tools
                        ForEach(selectedTools, id: \.objectID) { tool in
                            HStack {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(tool.name ?? "Unnamed Tool")
                                        .font(.body)
                                    Text(ownershipLabel(for: tool))
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                }
                                Spacer()
                                // Large tap target for gloved hands (44x44pt minimum)
                                Button(action: {
                                    selectedToolIDs.remove(tool.objectID)
                                }) {
                                    Image(systemName: "xmark.circle.fill")
                                        .font(.title2)
                                        .foregroundColor(.secondary)
                                        .frame(width: 44, height: 44)
                                        .contentShape(Rectangle())
                                }
                                .buttonStyle(.plain)
                                .accessibilityLabel("Remove \(tool.name ?? "tool")")
                            }
                        }

                        // Button to add more tools - large tap target
                        Button(action: { showingToolPicker = true }) {
                            HStack {
                                Image(systemName: "plus.circle")
                                    .font(.title3)
                                    .foregroundColor(Color(red: 0.145, green: 0.388, blue: 0.922))
                                Text("Add More Tools")
                                    .foregroundColor(Color(red: 0.145, green: 0.388, blue: 0.922))
                            }
                            .frame(minHeight: 44)
                        }
                        .accessibilityIdentifier("addMoreToolsButton")
                        .accessibilityLabel("Add More Tools")
                    }
                }

                // MARK: - Consumables Used
                Section("Consumables Used") {
                    if selectedConsumables.isEmpty {
                        Button(action: { showingConsumablePicker = true }) {
                            HStack {
                                Image(systemName: "bolt.fill")
                                    .foregroundColor(Color(red: 0.145, green: 0.388, blue: 0.922))
                                Text("Add from Garage")
                                    .foregroundColor(Color(red: 0.145, green: 0.388, blue: 0.922))
                                Spacer()
                                Image(systemName: "chevron.right")
                                    .foregroundColor(.secondary)
                                    .font(.caption)
                            }
                        }
                        .accessibilityIdentifier("addConsumablesFromGarageButton")
                        .accessibilityLabel("Add Consumables from Garage")
                        .accessibilityHint("Opens picker to select consumables from your Garage")
                    } else {
                        ForEach(selectedConsumables, id: \.objectID) { consumable in
                            HStack {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(consumable.name ?? "Unnamed Consumable")
                                        .font(.body)
                                    Text(consumableCategoryLabel(for: consumable))
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                }
                                Spacer()
                                // Large tap target for gloved hands (44x44pt minimum)
                                Button(action: {
                                    selectedConsumableIDs.remove(consumable.objectID)
                                }) {
                                    Image(systemName: "xmark.circle.fill")
                                        .font(.title2)
                                        .foregroundColor(.secondary)
                                        .frame(width: 44, height: 44)
                                        .contentShape(Rectangle())
                                }
                                .buttonStyle(.plain)
                                .accessibilityLabel("Remove \(consumable.name ?? "consumable")")
                            }
                        }

                        // Large tap target for Add More button
                        Button(action: { showingConsumablePicker = true }) {
                            HStack {
                                Image(systemName: "plus.circle")
                                    .font(.title3)
                                    .foregroundColor(Color(red: 0.145, green: 0.388, blue: 0.922))
                                Text("Add More Consumables")
                                    .foregroundColor(Color(red: 0.145, green: 0.388, blue: 0.922))
                            }
                            .frame(minHeight: 44)
                        }
                        .accessibilityIdentifier("addMoreConsumablesButton")
                        .accessibilityLabel("Add More Consumables")
                    }
                }

                // MARK: - Chemicals Used
                Section("Chemicals Used") {
                    if selectedChemicals.isEmpty {
                        Button(action: { showingChemicalPicker = true }) {
                            HStack {
                                Image(systemName: "drop.fill")
                                    .foregroundColor(Color(red: 0.145, green: 0.388, blue: 0.922))
                                Text("Add from Garage")
                                    .foregroundColor(Color(red: 0.145, green: 0.388, blue: 0.922))
                                Spacer()
                                Image(systemName: "chevron.right")
                                    .foregroundColor(.secondary)
                                    .font(.caption)
                            }
                        }
                        .accessibilityIdentifier("addChemicalsFromGarageButton")
                        .accessibilityLabel("Add Chemicals from Garage")
                        .accessibilityHint("Opens picker to select chemicals from your Garage")
                    } else {
                        ForEach(selectedChemicals, id: \.objectID) { chemical in
                            HStack {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(chemical.name ?? "Unnamed Chemical")
                                        .font(.body)
                                    Text(chemicalCategoryLabel(for: chemical))
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                }
                                Spacer()
                                // Large tap target for gloved hands (44x44pt minimum)
                                Button(action: {
                                    selectedChemicalIDs.remove(chemical.objectID)
                                }) {
                                    Image(systemName: "xmark.circle.fill")
                                        .font(.title2)
                                        .foregroundColor(.secondary)
                                        .frame(width: 44, height: 44)
                                        .contentShape(Rectangle())
                                }
                                .buttonStyle(.plain)
                                .accessibilityLabel("Remove \(chemical.name ?? "chemical")")
                            }
                        }

                        // Large tap target for Add More button
                        Button(action: { showingChemicalPicker = true }) {
                            HStack {
                                Image(systemName: "plus.circle")
                                    .font(.title3)
                                    .foregroundColor(Color(red: 0.145, green: 0.388, blue: 0.922))
                                Text("Add More Chemicals")
                                    .foregroundColor(Color(red: 0.145, green: 0.388, blue: 0.922))
                            }
                            .frame(minHeight: 44)
                        }
                        .accessibilityIdentifier("addMoreChemicalsButton")
                        .accessibilityLabel("Add More Chemicals")
                    }
                }

                // MARK: - Save Button
                // Prominent save button with large tap target for gloved/greasy hands (60pt+ height)
                // Disabled during save to prevent double-tap creating duplicates (Feature #69)
                Section {
                    if isSaving {
                        // Show saving indicator - button is disabled during processing
                        HStack {
                            Spacer()
                            ProgressView()
                                .progressViewStyle(CircularProgressViewStyle())
                                .scaleEffect(1.2)
                                .accessibilityIdentifier("saveProgressIndicator")
                            Text("Saving...")
                                .fontWeight(.bold)
                                .font(.title2)
                                .foregroundColor(.gray)
                                .padding(.leading, 8)
                            Spacer()
                        }
                        .padding(.vertical, 16)
                        .frame(minHeight: 60)
                        .accessibilityLabel("Saving job record in progress")
                    } else if !canSave {
                        // Show tappable area that triggers validation message when form is incomplete
                        Button(action: {
                            // Show validation errors for any missing required fields
                            if aircraftType.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                                showAircraftTypeRequired = true
                            }
                            if selectedSystem.isEmpty {
                                showSystemRequired = true
                            }
                        }) {
                            HStack {
                                Spacer()
                                Image(systemName: "checkmark.circle.fill")
                                    .font(.title2)
                                Text("Save Job Record")
                                    .fontWeight(.bold)
                                    .font(.title2)
                                Spacer()
                            }
                            .padding(.vertical, 16)
                            .foregroundColor(.gray)
                        }
                        .frame(minHeight: 60)
                        .accessibilityIdentifier("saveJobButton")
                        .accessibilityLabel("Save Job Record, disabled")
                        .accessibilityHint("Fill in required fields to enable saving")
                    } else {
                        Button(action: saveJobRecord) {
                            HStack {
                                Spacer()
                                Image(systemName: "checkmark.circle.fill")
                                    .font(.title2)
                                Text("Save Job Record")
                                    .fontWeight(.bold)
                                    .font(.title2)
                                Spacer()
                            }
                            .padding(.vertical, 16)
                            .foregroundColor(Color(red: 0.145, green: 0.388, blue: 0.922))
                        }
                        .disabled(isSaving)
                        .frame(minHeight: 60)
                        .accessibilityIdentifier("saveJobButton")
                        .accessibilityLabel("Save Job Record")
                        .accessibilityHint("Saves this job record to your reference library")
                    }
                }
            }
            .navigationTitle("New Job")
            .navigationBarTitleDisplayMode(.large)
            .sheet(isPresented: $showingToolPicker) {
                GarageToolPickerView(selectedToolIDs: $selectedToolIDs)
                    .environment(\.managedObjectContext, viewContext)
            }
            .sheet(isPresented: $showingConsumablePicker) {
                GarageConsumablePickerView(selectedConsumableIDs: $selectedConsumableIDs)
                    .environment(\.managedObjectContext, viewContext)
            }
            .sheet(isPresented: $showingChemicalPicker) {
                GarageChemicalPickerView(selectedChemicalIDs: $selectedChemicalIDs)
                    .environment(\.managedObjectContext, viewContext)
            }
            .sheet(isPresented: $showingVoiceCapture) {
                VoiceCaptureView(
                    onTranscriptionWithCandidates: { toolIDs, consumableIDs, chemicalIDs, transcribedText in
                        // Append transcribed text to the task description
                        if taskDescription.isEmpty {
                            taskDescription = transcribedText
                        } else {
                            taskDescription += "\n\n[Voice Memo]\n" + transcribedText
                        }

                        // Merge candidate tool selections with any existing selections
                        selectedToolIDs = selectedToolIDs.union(toolIDs)

                        // Merge candidate consumable selections
                        selectedConsumableIDs = selectedConsumableIDs.union(consumableIDs)

                        // Merge candidate chemical selections
                        selectedChemicalIDs = selectedChemicalIDs.union(chemicalIDs)

                        print("NewJobView: Voice transcription added - tools: \(toolIDs.count), consumables: \(consumableIDs.count), chemicals: \(chemicalIDs.count)")
                    },
                    onTranscriptionComplete: { transcribedText in
                        // Fallback: Append transcribed text to the task description only
                        if taskDescription.isEmpty {
                            taskDescription = transcribedText
                        } else {
                            taskDescription += "\n\n[Voice Memo]\n" + transcribedText
                        }
                        print("NewJobView: Voice transcription added to task description (text only)")
                    },
                    isPresented: $showingVoiceCapture
                )
                .environment(\.managedObjectContext, viewContext)
            }
            .alert("Job Saved!", isPresented: $showingSaveSuccess) {
                Button("OK") { }
            } message: {
                Text("Job record for \(savedJobAircraftType) has been saved successfully.")
            }
            .alert("Error", isPresented: $showingError) {
                Button("OK") { }
            } message: {
                Text(errorMessage)
            }
        }
    }

    // MARK: - Helpers

    private func ownershipLabel(for tool: Tool) -> String {
        switch tool.ownershipType {
        case "personal": return "Personal"
        case "shop": return "Shop"
        case "borrowed": return "Borrowed"
        default: return "Personal"
        }
    }

    private func consumableCategoryLabel(for consumable: Consumable) -> String {
        switch consumable.category {
        case "safety_wire": return "Safety Wire"
        case "cotter_pin": return "Cotter Pin"
        case "o_ring": return "O-Ring"
        case "seal": return "Seal"
        case "other": return "Other"
        default: return "Other"
        }
    }

    private func chemicalCategoryLabel(for chemical: Chemical) -> String {
        switch chemical.category {
        case "fluid": return "Fluid"
        case "lubricant": return "Lubricant"
        case "cleaner": return "Cleaner"
        case "sealant": return "Sealant"
        case "other": return "Other"
        default: return "Other"
        }
    }

    // MARK: - Save Logic

    /// Saves the job record atomically to Core Data.
    /// If save fails or is interrupted by navigation, the context is rolled back
    /// to prevent partial/corrupted records from lingering in the store.
    /// Uses isSaving flag to prevent double-tap creating duplicate records (Feature #69).
    private func saveJobRecord() {
        // Prevent double-tap creating duplicates - exit early if already saving
        guard !isSaving else {
            print("NewJobView: Save already in progress, ignoring duplicate tap")
            return
        }

        let trimmedAircraftType = aircraftType.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedAircraftType.isEmpty else {
            errorMessage = "Aircraft type is required."
            showAircraftTypeRequired = true
            showingError = true
            return
        }

        // Validate system field is not empty (required field)
        guard !selectedSystem.isEmpty else {
            errorMessage = "System is required."
            showSystemRequired = true
            showingError = true
            return
        }

        // Set saving flag to disable button and prevent duplicate saves
        isSaving = true

        // Capture current pending changes count to detect corruption
        let pendingInsertsBefore = viewContext.insertedObjects.count

        let record = JobRecord(context: viewContext)
        record.id = UUID()
        record.aircraftType = trimmedAircraftType
        record.system = selectedSystem
        record.jobDate = jobDate
        record.createdAt = Date()
        record.updatedAt = Date()
        record.currentVersion = 1

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

        // Link selected tools from Garage to the job record
        for toolID in selectedToolIDs {
            if let tool = try? viewContext.existingObject(with: toolID) as? Tool {
                record.addToTools(tool)
                print("NewJobView: Linked tool '\(tool.name ?? "unknown")' to job record")
            }
        }

        // Link selected consumables from Garage to the job record
        for consumableID in selectedConsumableIDs {
            if let consumable = try? viewContext.existingObject(with: consumableID) as? Consumable {
                record.addToConsumables(consumable)
                print("NewJobView: Linked consumable '\(consumable.name ?? "unknown")' to job record")
            }
        }

        // Link selected chemicals from Garage to the job record
        for chemicalID in selectedChemicalIDs {
            if let chemical = try? viewContext.existingObject(with: chemicalID) as? Chemical {
                record.addToChemicals(chemical)
                print("NewJobView: Linked chemical '\(chemical.name ?? "unknown")' to job record")
            }
        }

        do {
            try viewContext.save()
            print("NewJobView: Saved job record for '\(trimmedAircraftType)' - system: \(selectedSystem), tools: \(selectedToolIDs.count)")
            savedJobAircraftType = trimmedAircraftType
            isSaving = false  // Reset saving flag on success
            showingSaveSuccess = true
            resetForm()
        } catch {
            // CRITICAL: Rollback the context on failure to prevent partial/corrupted
            // records from lingering. Without rollback, the unsaved JobRecord object
            // stays in the context and could be inadvertently saved later or cause
            // corruption if the user navigates away and another save occurs.
            viewContext.rollback()
            print("NewJobView: Save failed, context rolled back - \(error)")
            isSaving = false  // Reset saving flag on error
            errorMessage = "Failed to save job record: \(error.localizedDescription)"
            showingError = true
        }

        // Safety check: verify no orphaned pending inserts remain after save attempt
        let pendingInsertsAfter = viewContext.insertedObjects.count
        if pendingInsertsAfter > pendingInsertsBefore {
            // Something went wrong — clean up stale objects
            viewContext.rollback()
            print("NewJobView: Safety rollback - detected orphaned pending inserts (\(pendingInsertsAfter) vs \(pendingInsertsBefore))")
        }
    }

    // MARK: - Reset Form

    private func resetForm() {
        aircraftType = ""
        aircraftSerialNumber = ""
        nNumber = ""
        selectedSystem = ""
        component = ""
        jobDate = Date()
        taskDescription = ""
        tmReferences = ""
        notes = ""
        selectedToolIDs = []
        selectedConsumableIDs = []
        selectedChemicalIDs = []
    }
}

#Preview {
    NewJobView()
        .environment(\.managedObjectContext, PersistenceController.preview.container.viewContext)
}

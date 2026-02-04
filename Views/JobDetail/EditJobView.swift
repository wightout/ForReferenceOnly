import SwiftUI
import CoreData

/// View for editing an existing job record.
/// Pre-populates all fields from the existing record and saves changes back to Core Data.
struct EditJobView: View {
    @ObservedObject var job: JobRecord
    @Environment(\.managedObjectContext) private var viewContext
    @Environment(\.dismiss) private var dismiss

    // MARK: - Form State (initialized from job)

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

    // MARK: - Tool Selection State

    @State private var selectedToolIDs: Set<NSManagedObjectID>
    @State private var showingToolPicker = false

    // MARK: - Consumable Selection State

    @State private var selectedConsumableIDs: Set<NSManagedObjectID>
    @State private var showingConsumablePicker = false

    // MARK: - Chemical Selection State

    @State private var selectedChemicalIDs: Set<NSManagedObjectID>
    @State private var showingChemicalPicker = false

    // MARK: - UI State

    @State private var showingSaveSuccess = false
    @State private var showingError = false
    @State private var errorMessage = ""
    @State private var showAircraftTypeRequired = false

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

    // MARK: - Init

    init(job: JobRecord) {
        self.job = job
        // Pre-populate all fields from the existing job record
        _aircraftType = State(initialValue: job.aircraftType ?? "")
        _aircraftSerialNumber = State(initialValue: job.aircraftSerialNumber ?? "")
        _nNumber = State(initialValue: job.nNumber ?? "")
        _selectedSystem = State(initialValue: job.system ?? "Hydraulics")
        _component = State(initialValue: job.component ?? "")
        _jobDate = State(initialValue: job.jobDate ?? Date())
        _taskDescription = State(initialValue: job.taskDescription ?? "")
        _tmReferences = State(initialValue: job.tmReferences ?? "")
        _notes = State(initialValue: job.notes ?? "")
        _recommendations = State(initialValue: job.recommendations ?? "")

        // Pre-populate linked tools
        if let toolSet = job.tools as? Set<Tool> {
            _selectedToolIDs = State(initialValue: Set(toolSet.map { $0.objectID }))
        } else {
            _selectedToolIDs = State(initialValue: [])
        }

        // Pre-populate linked consumables
        if let consumableSet = job.consumables as? Set<Consumable> {
            _selectedConsumableIDs = State(initialValue: Set(consumableSet.map { $0.objectID }))
        } else {
            _selectedConsumableIDs = State(initialValue: [])
        }

        // Pre-populate linked chemicals
        if let chemicalSet = job.chemicals as? Set<Chemical> {
            _selectedChemicalIDs = State(initialValue: Set(chemicalSet.map { $0.objectID }))
        } else {
            _selectedChemicalIDs = State(initialValue: [])
        }
    }

    /// Whether the form has the minimum required fields filled
    private var canSave: Bool {
        !aircraftType.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
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
                        Spacer()
                    }
                }

                // MARK: - Aircraft Information
                Section(header: Text("Aircraft Information")) {
                    TextField("Aircraft Type (required)", text: $aircraftType)
                        .font(.body)
                        .autocorrectionDisabled()
                        .accessibilityIdentifier("editAircraftTypeField")
                        .onChange(of: aircraftType) { _, newValue in
                            if !newValue.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                                showAircraftTypeRequired = false
                            }
                        }

                    if showAircraftTypeRequired {
                        Text("Aircraft type is required")
                            .font(.caption)
                            .foregroundColor(.red)
                            .accessibilityIdentifier("editAircraftTypeRequiredLabel")
                    }

                    TextField("Serial Number", text: $aircraftSerialNumber)
                        .font(.body)
                        .autocorrectionDisabled()
                        .accessibilityIdentifier("editSerialNumberField")

                    TextField("N-Number / Tail Number", text: $nNumber)
                        .font(.body)
                        .autocorrectionDisabled()
                        .accessibilityIdentifier("editNNumberField")
                }

                // MARK: - System & Component
                Section(header: Text("System & Component")) {
                    Picker("System", selection: $selectedSystem) {
                        ForEach(systemOptions, id: \.self) { system in
                            Text(system).tag(system)
                        }
                    }
                    .accessibilityIdentifier("editSystemPicker")

                    TextField("Component", text: $component)
                        .font(.body)
                        .autocorrectionDisabled()
                        .accessibilityIdentifier("editComponentField")
                }

                // MARK: - Job Date
                Section(header: Text("Job Date")) {
                    DatePicker("Date", selection: $jobDate, displayedComponents: .date)
                        .datePickerStyle(.graphical)
                        .accessibilityIdentifier("editJobDatePicker")
                }

                // MARK: - Task Description
                Section(header: Text("Task Description")) {
                    TextField("Describe the task performed", text: $taskDescription, axis: .vertical)
                        .lineLimit(3...8)
                        .font(.body)
                        .accessibilityIdentifier("editTaskDescriptionField")
                }

                // MARK: - TM References
                Section(header: Text("TM References")) {
                    TextField("e.g., TM 1-1520-237-23, Fig 7-1", text: $tmReferences, axis: .vertical)
                        .lineLimit(2...5)
                        .font(.system(.body, design: .monospaced))
                        .autocorrectionDisabled()
                        .accessibilityIdentifier("editTmReferencesField")
                }

                // MARK: - Notes & Recommendations
                Section(header: Text("Notes & Recommendations")) {
                    TextField("Additional notes, tips, or observations", text: $notes, axis: .vertical)
                        .lineLimit(3...8)
                        .font(.body)
                        .accessibilityIdentifier("editNotesField")
                }

                // MARK: - Recommendations
                Section(header: Text("Recommendations")) {
                    TextField("Recommendations for next time", text: $recommendations, axis: .vertical)
                        .lineLimit(2...5)
                        .font(.body)
                        .accessibilityIdentifier("editRecommendationsField")
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
                        .accessibilityIdentifier("editAddToolsFromGarageButton")
                    } else {
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
                                Button(action: {
                                    selectedToolIDs.remove(tool.objectID)
                                }) {
                                    Image(systemName: "xmark.circle.fill")
                                        .foregroundColor(.secondary)
                                }
                                .buttonStyle(.plain)
                            }
                        }

                        Button(action: { showingToolPicker = true }) {
                            HStack {
                                Image(systemName: "plus.circle")
                                    .foregroundColor(Color(red: 0.145, green: 0.388, blue: 0.922))
                                Text("Add More Tools")
                                    .foregroundColor(Color(red: 0.145, green: 0.388, blue: 0.922))
                            }
                        }
                        .accessibilityIdentifier("editAddMoreToolsButton")
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
                        .accessibilityIdentifier("editAddConsumablesFromGarageButton")
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
                                Button(action: {
                                    selectedConsumableIDs.remove(consumable.objectID)
                                }) {
                                    Image(systemName: "xmark.circle.fill")
                                        .foregroundColor(.secondary)
                                }
                                .buttonStyle(.plain)
                            }
                        }

                        Button(action: { showingConsumablePicker = true }) {
                            HStack {
                                Image(systemName: "plus.circle")
                                    .foregroundColor(Color(red: 0.145, green: 0.388, blue: 0.922))
                                Text("Add More Consumables")
                                    .foregroundColor(Color(red: 0.145, green: 0.388, blue: 0.922))
                            }
                        }
                        .accessibilityIdentifier("editAddMoreConsumablesButton")
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
                        .accessibilityIdentifier("editAddChemicalsFromGarageButton")
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
                                Button(action: {
                                    selectedChemicalIDs.remove(chemical.objectID)
                                }) {
                                    Image(systemName: "xmark.circle.fill")
                                        .foregroundColor(.secondary)
                                }
                                .buttonStyle(.plain)
                            }
                        }

                        Button(action: { showingChemicalPicker = true }) {
                            HStack {
                                Image(systemName: "plus.circle")
                                    .foregroundColor(Color(red: 0.145, green: 0.388, blue: 0.922))
                                Text("Add More Chemicals")
                                    .foregroundColor(Color(red: 0.145, green: 0.388, blue: 0.922))
                            }
                        }
                        .accessibilityIdentifier("editAddMoreChemicalsButton")
                    }
                }

                // MARK: - Save Button
                Section {
                    if !canSave {
                        Button(action: {
                            showAircraftTypeRequired = true
                        }) {
                            HStack {
                                Spacer()
                                Image(systemName: "checkmark.circle.fill")
                                    .font(.title3)
                                Text("Save Changes")
                                    .fontWeight(.semibold)
                                    .font(.title3)
                                Spacer()
                            }
                            .padding(.vertical, 8)
                            .foregroundColor(.gray)
                        }
                        .accessibilityIdentifier("editSaveButton")
                    } else {
                        Button(action: saveChanges) {
                            HStack {
                                Spacer()
                                Image(systemName: "checkmark.circle.fill")
                                    .font(.title3)
                                Text("Save Changes")
                                    .fontWeight(.semibold)
                                    .font(.title3)
                                Spacer()
                            }
                            .padding(.vertical, 8)
                            .foregroundColor(Color(red: 0.145, green: 0.388, blue: 0.922))
                        }
                        .accessibilityIdentifier("editSaveButton")
                    }
                }
            }
            .navigationTitle("Edit Job")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cancel") {
                        dismiss()
                    }
                }
            }
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
            .alert("Changes Saved!", isPresented: $showingSaveSuccess) {
                Button("OK") {
                    dismiss()
                }
            } message: {
                Text("Job record for \(job.aircraftType ?? "unknown") has been updated.")
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

    // MARK: - Revision Snapshot

    /// Creates a JSON snapshot of the current job record state before editing.
    /// This snapshot is stored as binary data in a JobRevision entity.
    private func createRevisionSnapshot() -> Data? {
        var snapshot: [String: Any] = [:]
        snapshot["aircraftType"] = job.aircraftType ?? ""
        snapshot["aircraftSerialNumber"] = job.aircraftSerialNumber ?? ""
        snapshot["nNumber"] = job.nNumber ?? ""
        snapshot["system"] = job.system ?? ""
        snapshot["component"] = job.component ?? ""
        snapshot["taskDescription"] = job.taskDescription ?? ""
        snapshot["tmReferences"] = job.tmReferences ?? ""
        snapshot["notes"] = job.notes ?? ""
        snapshot["recommendations"] = job.recommendations ?? ""

        // Format job date as ISO string for JSON serialization
        if let jobDate = job.jobDate {
            let formatter = DateFormatter()
            formatter.dateStyle = .long
            formatter.timeStyle = .none
            snapshot["jobDate"] = formatter.string(from: jobDate)
        }

        // Snapshot linked tools
        if let toolSet = job.tools as? Set<Tool> {
            let toolsArray = toolSet.map { tool -> [String: String] in
                ["name": tool.name ?? "Unknown", "ownershipType": tool.ownershipType ?? "personal"]
            }
            snapshot["tools"] = toolsArray
        }

        // Snapshot linked consumables
        if let consumableSet = job.consumables as? Set<Consumable> {
            let consumablesArray = consumableSet.map { c -> [String: String] in
                ["name": c.name ?? "Unknown", "category": c.category ?? "other"]
            }
            snapshot["consumables"] = consumablesArray
        }

        // Snapshot linked chemicals
        if let chemicalSet = job.chemicals as? Set<Chemical> {
            let chemicalsArray = chemicalSet.map { c -> [String: String] in
                ["name": c.name ?? "Unknown", "category": c.category ?? "other"]
            }
            snapshot["chemicals"] = chemicalsArray
        }

        return try? JSONSerialization.data(withJSONObject: snapshot, options: [.sortedKeys])
    }

    /// Creates a JobRevision entity preserving the current state before the edit is applied.
    private func createRevision() {
        let revision = JobRevision(context: viewContext)
        revision.id = UUID()
        revision.versionNumber = job.currentVersion
        revision.editedAt = Date()
        revision.snapshotData = createRevisionSnapshot()
        revision.jobRecord = job
        job.addToRevisions(revision)
        print("EditJobView: Created revision v\(job.currentVersion) for job '\(job.aircraftType ?? "unknown")'")
    }

    // MARK: - Save Logic

    /// Saves changes to the existing job record in Core Data.
    /// Creates a revision snapshot of the current state, then updates all fields.
    private func saveChanges() {
        let trimmedAircraftType = aircraftType.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedAircraftType.isEmpty else {
            errorMessage = "Aircraft type is required."
            showingError = true
            return
        }

        // Create a revision snapshot of the CURRENT state before applying edits
        createRevision()

        // Increment the version number
        job.currentVersion += 1

        // Update all fields on the existing job record
        job.aircraftType = trimmedAircraftType
        job.system = selectedSystem
        job.jobDate = jobDate
        job.updatedAt = Date()

        // Optional fields
        let trimmedSerial = aircraftSerialNumber.trimmingCharacters(in: .whitespacesAndNewlines)
        job.aircraftSerialNumber = trimmedSerial.isEmpty ? nil : trimmedSerial

        let trimmedNNumber = nNumber.trimmingCharacters(in: .whitespacesAndNewlines)
        job.nNumber = trimmedNNumber.isEmpty ? nil : trimmedNNumber

        let trimmedComponent = component.trimmingCharacters(in: .whitespacesAndNewlines)
        job.component = trimmedComponent.isEmpty ? nil : trimmedComponent

        let trimmedDescription = taskDescription.trimmingCharacters(in: .whitespacesAndNewlines)
        job.taskDescription = trimmedDescription.isEmpty ? nil : trimmedDescription

        let trimmedTM = tmReferences.trimmingCharacters(in: .whitespacesAndNewlines)
        job.tmReferences = trimmedTM.isEmpty ? nil : trimmedTM

        let trimmedNotes = notes.trimmingCharacters(in: .whitespacesAndNewlines)
        job.notes = trimmedNotes.isEmpty ? nil : trimmedNotes

        let trimmedRecs = recommendations.trimmingCharacters(in: .whitespacesAndNewlines)
        job.recommendations = trimmedRecs.isEmpty ? nil : trimmedRecs

        // Update tool links: remove old, add new
        if let existingTools = job.tools as? Set<Tool> {
            for tool in existingTools {
                job.removeFromTools(tool)
            }
        }
        for toolID in selectedToolIDs {
            if let tool = try? viewContext.existingObject(with: toolID) as? Tool {
                job.addToTools(tool)
            }
        }

        // Update consumable links: remove old, add new
        if let existingConsumables = job.consumables as? Set<Consumable> {
            for consumable in existingConsumables {
                job.removeFromConsumables(consumable)
            }
        }
        for consumableID in selectedConsumableIDs {
            if let consumable = try? viewContext.existingObject(with: consumableID) as? Consumable {
                job.addToConsumables(consumable)
            }
        }

        // Update chemical links: remove old, add new
        if let existingChemicals = job.chemicals as? Set<Chemical> {
            for chemical in existingChemicals {
                job.removeFromChemicals(chemical)
            }
        }
        for chemicalID in selectedChemicalIDs {
            if let chemical = try? viewContext.existingObject(with: chemicalID) as? Chemical {
                job.addToChemicals(chemical)
            }
        }

        do {
            try viewContext.save()
            print("EditJobView: Updated job record for '\(trimmedAircraftType)' successfully")
            showingSaveSuccess = true
        } catch {
            viewContext.rollback()
            print("EditJobView: Save failed, context rolled back - \(error)")
            errorMessage = "Failed to save changes: \(error.localizedDescription)"
            showingError = true
        }
    }
}

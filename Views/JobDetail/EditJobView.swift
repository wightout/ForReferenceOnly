import SwiftUI
import Foundation
import SwiftData

/// Identifies which sheet is currently presented from EditJobView.
enum EditJobSheet: Identifiable {
    case toolPicker
    case consumablePicker
    case chemicalPicker
    case partEntry
    case addToGaragePrompt

    var id: String {
        switch self {
        case .toolPicker: return "toolPicker"
        case .consumablePicker: return "consumablePicker"
        case .chemicalPicker: return "chemicalPicker"
        case .partEntry: return "partEntry"
        case .addToGaragePrompt: return "addToGaragePrompt"
        }
    }
}

/// View for editing an existing job record.
/// Pre-populates all fields from the existing record and saves changes back to Core Data.
struct EditJobView: View {
    @Bindable var job: JobRecord
    @Environment(\.modelContext) private var viewContext
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

    @State private var selectedToolIDs: Set<UUID>

    // MARK: - Consumable Selection State

    @State private var selectedConsumableIDs: Set<UUID>

    // MARK: - Chemical Selection State

    @State private var selectedChemicalIDs: Set<UUID>

    // MARK: - Part Selection State (Feature #141)

    @State private var selectedPartIDs: Set<UUID>

    // MARK: - Sheet Management
    /// Single active sheet to avoid SwiftUI's multiple .sheet modifier bug.
    @State private var activeSheet: EditJobSheet?

    // MARK: - UI State

    @State private var showingSaveSuccess = false
    @State private var showingError = false
    @State private var errorMessage = ""
    @State private var showAircraftTypeRequired = false
    /// On-the-fly tools (isInGarage = false) that were added to the job
    @State private var onTheFlyTools: [Tool] = []
    /// On-the-fly consumables (isInGarage = false) that were added to the job
    @State private var onTheFlyConsumables: [Consumable] = []
    /// On-the-fly chemicals (isInGarage = false) that were added to the job
    @State private var onTheFlyChemicals: [Chemical] = []

    // MARK: - System Options (now handled by SystemAutocompleteField - Feature #102)

    // MARK: - Init

    init(job: JobRecord) {
        self.job = job
        // Pre-populate all fields from the existing job record
        _aircraftType = State(initialValue: job.aircraftType)
        _aircraftSerialNumber = State(initialValue: job.aircraftSerialNumber ?? "")
        _nNumber = State(initialValue: job.nNumber ?? "")
        _selectedSystem = State(initialValue: job.system)
        _component = State(initialValue: job.component ?? "")
        _jobDate = State(initialValue: job.jobDate)
        _taskDescription = State(initialValue: job.taskDescription ?? "")
        _tmReferences = State(initialValue: job.tmReferences ?? "")
        _notes = State(initialValue: job.notes ?? "")
        _recommendations = State(initialValue: job.recommendations ?? "")

        // Pre-populate linked tools
        if let toolSet = job.tools {
            _selectedToolIDs = State(initialValue: Set(toolSet.map { $0.id }))
        } else {
            _selectedToolIDs = State(initialValue: [])
        }

        // Pre-populate linked consumables
        if let consumableSet = job.consumables {
            _selectedConsumableIDs = State(initialValue: Set(consumableSet.map { $0.id }))
        } else {
            _selectedConsumableIDs = State(initialValue: [])
        }

        // Pre-populate linked chemicals
        if let chemicalSet = job.chemicals {
            _selectedChemicalIDs = State(initialValue: Set(chemicalSet.map { $0.id }))
        } else {
            _selectedChemicalIDs = State(initialValue: [])
        }

        // Feature #141: Pre-populate linked parts
        if let partSet = job.parts {
            _selectedPartIDs = State(initialValue: Set(partSet.map { $0.id }))
        } else {
            _selectedPartIDs = State(initialValue: [])
        }
    }

    /// Whether the form has the minimum required fields filled
    private var canSave: Bool {
        !aircraftType.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
        !selectedSystem.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    /// Resolve selected tool object IDs to Tool managed objects, sorted by size then name
    private var selectedTools: [Tool] {
        selectedToolIDs.compactMap { objectID in
            fetchByPersistentID(Tool.self, id: objectID, context: viewContext)
        }.sortedBySize()
    }

    /// Resolve selected consumable object IDs to Consumable managed objects
    private var selectedConsumables: [Consumable] {
        selectedConsumableIDs.compactMap { objectID in
            fetchByPersistentID(Consumable.self, id: objectID, context: viewContext)
        }.sorted { $0.name < $1.name }
    }

    /// Resolve selected chemical object IDs to Chemical managed objects
    private var selectedChemicals: [Chemical] {
        selectedChemicalIDs.compactMap { objectID in
            fetchByPersistentID(Chemical.self, id: objectID, context: viewContext)
        }.sorted { $0.name < $1.name }
    }

    /// Feature #141: Resolve selected part object IDs to Part managed objects
    private var selectedParts: [Part] {
        selectedPartIDs.compactMap { objectID in
            fetchByPersistentID(Part.self, id: objectID, context: viewContext)
        }.sorted { $0.nomenclature < $1.nomenclature }
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
                    // Feature #99: Aircraft type autocomplete from previous entries
                    AircraftTypeAutocompleteView(
                        aircraftType: $aircraftType,
                        placeholder: "Aircraft Type (required)",
                        accessibilityPrefix: "edit"
                    )
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

                    // Feature #100: Serial number autocomplete from previous entries
                    SerialNumberAutocompleteField(
                        text: $aircraftSerialNumber,
                        placeholder: "Serial Number",
                        accessibilityId: "editSerialNumberField"
                    )

                    // Feature #101: N-number autocomplete from previous entries
                    NNumberAutocompleteField(
                        text: $nNumber,
                        placeholder: "N-Number / Tail Number",
                        accessibilityId: "editNNumberField"
                    )
                }

                // MARK: - System & Component
                Section(header: Text("System & Component")) {
                    // Feature #102: System field autocomplete from previous entries
                    SystemAutocompleteField(
                        text: $selectedSystem,
                        placeholder: "System (required)",
                        accessibilityId: "editSystemField"
                    )

                    // Feature #103: Component field autocomplete from previous entries
                    ComponentAutocompleteField(
                        text: $component,
                        placeholder: "Component",
                        accessibilityId: "editComponentField"
                    )
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

                // MARK: - Notes & Recommendations (Feature #126)
                Section(header: Text("Notes & Recommendations")) {
                    VStack(alignment: .leading, spacing: 8) {
                        TextField("Enter a note, press return for new item", text: $notes, axis: .vertical)
                            .lineLimit(3...10)
                            .font(.body)
                            .accessibilityIdentifier("editNotesField")
                            .accessibilityLabel("Notes and Recommendations")
                            .accessibilityHint("Enter notes separated by line breaks. Each line becomes a numbered item.")

                        // Display notes as numbered list preview when there are multiple lines
                        if !notes.isEmpty {
                            let noteLines = notes.components(separatedBy: .newlines).filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty }
                            if noteLines.count > 1 {
                                Divider()
                                VStack(alignment: .leading, spacing: 4) {
                                    Text("Preview (\(noteLines.count) items)")
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                        .accessibilityIdentifier("editNotesPreviewHeader")
                                    ForEach(Array(noteLines.enumerated()), id: \.offset) { index, line in
                                        HStack(alignment: .top, spacing: 8) {
                                            Text("\(index + 1).")
                                                .font(.caption)
                                                .foregroundColor(Color(red: 0.145, green: 0.388, blue: 0.922)) // Industrial blue
                                                .frame(width: 20, alignment: .trailing)
                                            Text(line)
                                                .font(.caption)
                                                .foregroundColor(.primary)
                                        }
                                        .accessibilityElement(children: .combine)
                                        .accessibilityLabel("Note \(index + 1): \(line)")
                                    }
                                }
                                .padding(.vertical, 4)
                                .accessibilityIdentifier("editNotesPreviewList")
                            }
                        }

                        // Hint text
                        Text("Press return to add multiple notes")
                            .font(.caption2)
                            .foregroundColor(.secondary)
                            .accessibilityIdentifier("editNotesHintText")
                    }
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
                        Button(action: { activeSheet = .toolPicker }) {
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
                        ForEach(selectedTools, id: \.id) { tool in
                            HStack {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(tool.name)
                                        .font(.body)
                                    Text(ownershipLabel(for: tool))
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                }
                                Spacer()
                                Button(action: {
                                    selectedToolIDs.remove(tool.id)
                                }) {
                                    Image(systemName: "xmark.circle.fill")
                                        .foregroundColor(.secondary)
                                }
                                .buttonStyle(.plain)
                            }
                        }

                        Button(action: { activeSheet = .toolPicker }) {
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
                        Button(action: { activeSheet = .consumablePicker }) {
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
                        ForEach(selectedConsumables, id: \.id) { consumable in
                            HStack {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(consumable.name)
                                        .font(.body)
                                    Text(consumableCategoryLabel(for: consumable))
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                }
                                Spacer()
                                Button(action: {
                                    selectedConsumableIDs.remove(consumable.id)
                                }) {
                                    Image(systemName: "xmark.circle.fill")
                                        .foregroundColor(.secondary)
                                }
                                .buttonStyle(.plain)
                            }
                        }

                        Button(action: { activeSheet = .consumablePicker }) {
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
                        Button(action: { activeSheet = .chemicalPicker }) {
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
                        ForEach(selectedChemicals, id: \.id) { chemical in
                            HStack {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(chemical.name)
                                        .font(.body)
                                    Text(chemicalCategoryLabel(for: chemical))
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                }
                                Spacer()
                                Button(action: {
                                    selectedChemicalIDs.remove(chemical.id)
                                }) {
                                    Image(systemName: "xmark.circle.fill")
                                        .foregroundColor(.secondary)
                                }
                                .buttonStyle(.plain)
                            }
                        }

                        Button(action: { activeSheet = .chemicalPicker }) {
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

                // MARK: - Parts Used (Feature #141)
                Section("Parts Used") {
                    if selectedParts.isEmpty {
                        Button(action: { activeSheet = .partEntry }) {
                            HStack {
                                Image(systemName: "gearshape.2.fill")
                                    .foregroundColor(Color(red: 0.145, green: 0.388, blue: 0.922))
                                Text("Add Part")
                                    .foregroundColor(Color(red: 0.145, green: 0.388, blue: 0.922))
                                Spacer()
                                Image(systemName: "chevron.right")
                                    .foregroundColor(.secondary)
                                    .font(.caption)
                            }
                        }
                        .accessibilityIdentifier("editAddPartButton")
                    } else {
                        ForEach(selectedParts, id: \.id) { part in
                            HStack {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(part.nomenclature)
                                        .font(.body)
                                    HStack(spacing: 8) {
                                        Text("P/N: \(part.partNumber)")
                                            .font(.caption)
                                            .foregroundColor(.secondary)
                                        if part.quantity > 1 {
                                            Text("Qty: \(part.quantity)")
                                                .font(.caption)
                                                .foregroundColor(.secondary)
                                        }
                                    }
                                }
                                Spacer()
                                Button(action: {
                                    selectedPartIDs.remove(part.id)
                                }) {
                                    Image(systemName: "xmark.circle.fill")
                                        .foregroundColor(.secondary)
                                }
                                .buttonStyle(.plain)
                                .accessibilityLabel("Remove \(part.nomenclature)")
                            }
                        }

                        Button(action: { activeSheet = .partEntry }) {
                            HStack {
                                Image(systemName: "plus.circle")
                                    .foregroundColor(Color(red: 0.145, green: 0.388, blue: 0.922))
                                Text("Add More Parts")
                                    .foregroundColor(Color(red: 0.145, green: 0.388, blue: 0.922))
                            }
                        }
                        .accessibilityIdentifier("editAddMorePartsButton")
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
            // Single .sheet(item:) to avoid SwiftUI's multiple-sheet binding bug
            .sheet(item: $activeSheet) { sheet in
                switch sheet {
                case .toolPicker:
                    GarageToolPickerView(selectedToolIDs: $selectedToolIDs)
                        
                case .consumablePicker:
                    GarageConsumablePickerView(selectedConsumableIDs: $selectedConsumableIDs)
                        
                case .chemicalPicker:
                    GarageChemicalPickerView(selectedChemicalIDs: $selectedChemicalIDs)
                        
                case .partEntry:
                    PartEntryView(selectedPartIDs: $selectedPartIDs)
                        
                case .addToGaragePrompt:
                    AddToGaragePromptView(
                        tools: onTheFlyTools,
                        consumables: onTheFlyConsumables,
                        chemicals: onTheFlyChemicals,
                        onDismiss: {
                            onTheFlyTools = []
                            onTheFlyConsumables = []
                            onTheFlyChemicals = []
                            showingSaveSuccess = true
                        }
                    )
                    
                }
            }
            .alert("Changes Saved!", isPresented: $showingSaveSuccess) {
                Button("OK") {
                    dismiss()
                }
            } message: {
                Text("Job record for \(job.aircraftType) has been updated.")
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
        case "imported": return "Imported"
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
        snapshot["aircraftType"] = job.aircraftType
        snapshot["aircraftSerialNumber"] = job.aircraftSerialNumber ?? ""
        snapshot["nNumber"] = job.nNumber ?? ""
        snapshot["system"] = job.system
        snapshot["component"] = job.component ?? ""
        snapshot["taskDescription"] = job.taskDescription ?? ""
        snapshot["tmReferences"] = job.tmReferences ?? ""
        snapshot["notes"] = job.notes ?? ""
        snapshot["recommendations"] = job.recommendations ?? ""

        // Format job date as ISO string for JSON serialization
        let formatter = DateFormatter()
        formatter.dateStyle = .long
        formatter.timeStyle = .none
        snapshot["jobDate"] = formatter.string(from: job.jobDate)

        // Snapshot linked tools
        if let toolSet = job.tools {
            let toolsArray = toolSet.map { tool -> [String: String] in
                ["name": tool.name, "ownershipType": tool.ownershipType]
            }
            snapshot["tools"] = toolsArray
        }

        // Snapshot linked consumables
        if let consumableSet = job.consumables {
            let consumablesArray = consumableSet.map { c -> [String: String] in
                ["name": c.name, "category": c.category]
            }
            snapshot["consumables"] = consumablesArray
        }

        // Snapshot linked chemicals
        if let chemicalSet = job.chemicals {
            let chemicalsArray = chemicalSet.map { c -> [String: String] in
                ["name": c.name, "category": c.category]
            }
            snapshot["chemicals"] = chemicalsArray
        }

        // Feature #141: Snapshot linked parts
        if let partSet = job.parts {
            let partsArray = partSet.map { p -> [String: Any] in
                var dict: [String: Any] = [
                    "nomenclature": p.nomenclature,
                    "partNumber": p.partNumber,
                    "quantity": Int(p.quantity)
                ]
                if let alt = p.alternatePartNumber, !alt.isEmpty { dict["alternatePartNumber"] = alt }
                if let nsn = p.nsn, !nsn.isEmpty { dict["nsn"] = nsn }
                if let uom = p.unitOfMeasure, !uom.isEmpty { dict["unitOfMeasure"] = uom }
                if let notes = p.notes, !notes.isEmpty { dict["notes"] = notes }
                return dict
            }
            snapshot["parts"] = partsArray
        }

        return try? JSONSerialization.data(withJSONObject: snapshot, options: [.sortedKeys])
    }

    /// Creates a JobRevision entity preserving the current state before the edit is applied.
    private func createRevision() {
        let revision = FROJobRevision(
            versionNumber: job.currentVersion,
            snapshotData: createRevisionSnapshot()
        )
        revision.jobRecord = job
        viewContext.insert(revision)
        if job.revisions == nil { job.revisions = [] }
        job.revisions?.append(revision)
        print("EditJobView: Created revision v\(job.currentVersion) for job '\(job.aircraftType)'")
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
        job.system = selectedSystem.trimmingCharacters(in: .whitespacesAndNewlines)
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

        // Feature #96: Track on-the-fly items (isInGarage = false) for post-save prompt
        var newOnTheFlyTools: [FROTool] = []
        var newOnTheFlyConsumables: [FROConsumable] = []
        var newOnTheFlyChemicals: [FROChemical] = []

        // Update tool links: replace with new selection
        var updatedTools: [FROTool] = []
        for toolID in selectedToolIDs {
            if let tool = fetchByPersistentID(FROTool.self, id: toolID, context: viewContext) {
                updatedTools.append(tool)
                if !tool.isInGarage {
                    newOnTheFlyTools.append(tool)
                    print("EditJobView: Detected on-the-fly tool '\(tool.name)'")
                }
            }
        }
        job.tools = updatedTools

        // Update consumable links: replace with new selection
        var updatedConsumables: [FROConsumable] = []
        for consumableID in selectedConsumableIDs {
            if let consumable = fetchByPersistentID(FROConsumable.self, id: consumableID, context: viewContext) {
                updatedConsumables.append(consumable)
                if !consumable.isInGarage {
                    newOnTheFlyConsumables.append(consumable)
                    print("EditJobView: Detected on-the-fly consumable '\(consumable.name)'")
                }
            }
        }
        job.consumables = updatedConsumables

        // Update chemical links: replace with new selection
        var updatedChemicals: [FROChemical] = []
        for chemicalID in selectedChemicalIDs {
            if let chemical = fetchByPersistentID(FROChemical.self, id: chemicalID, context: viewContext) {
                updatedChemicals.append(chemical)
                if !chemical.isInGarage {
                    newOnTheFlyChemicals.append(chemical)
                    print("EditJobView: Detected on-the-fly chemical '\(chemical.name)'")
                }
            }
        }
        job.chemicals = updatedChemicals

        // Feature #141: Update part links: replace with new selection
        var updatedParts: [FROPart] = []
        for partID in selectedPartIDs {
            if let part = fetchByPersistentID(FROPart.self, id: partID, context: viewContext) {
                updatedParts.append(part)
                print("EditJobView: Linked part '\(part.nomenclature)' P/N: \(part.partNumber)")
            }
        }
        job.parts = updatedParts

        do {
            try viewContext.save()
            print("EditJobView: Updated job record for '\(trimmedAircraftType)' successfully")

            // Feature #96: Check if there are on-the-fly items to prompt about
            let hasOnTheFlyItems = !newOnTheFlyTools.isEmpty || !newOnTheFlyConsumables.isEmpty || !newOnTheFlyChemicals.isEmpty

            if hasOnTheFlyItems {
                // Store on-the-fly items and show the prompt
                onTheFlyTools = newOnTheFlyTools
                onTheFlyConsumables = newOnTheFlyConsumables
                onTheFlyChemicals = newOnTheFlyChemicals
                print("EditJobView: Showing Add to Garage prompt for \(newOnTheFlyTools.count) tools, \(newOnTheFlyConsumables.count) consumables, \(newOnTheFlyChemicals.count) chemicals")
                activeSheet = .addToGaragePrompt
            } else {
                // No on-the-fly items, show regular success alert
                showingSaveSuccess = true
            }
        } catch {
            print("EditJobView: Save failed, context rolled back - \(error)")
            errorMessage = "Failed to save changes: \(error.localizedDescription)"
            showingError = true
        }
    }
}

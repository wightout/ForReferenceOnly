import SwiftUI
import Foundation
import SwiftData

/// Identifies which sheet is currently presented from NewJobView.
/// Using a single .sheet(item:) avoids SwiftUI's stale-binding bug
/// that occurs when multiple .sheet(isPresented:) modifiers are chained.
enum NewJobSheet: Identifiable {
    case toolPicker
    case consumablePicker
    case chemicalPicker
    case partEntry
    case voiceCapture
    case addToGaragePrompt

    var id: String {
        switch self {
        case .toolPicker: return "toolPicker"
        case .consumablePicker: return "consumablePicker"
        case .chemicalPicker: return "chemicalPicker"
        case .partEntry: return "partEntry"
        case .voiceCapture: return "voiceCapture"
        case .addToGaragePrompt: return "addToGaragePrompt"
        }
    }
}

/// View for creating new job records with all metadata fields.
/// Saves directly to Core Data via the managed object context.
struct NewJobView: View {
    @Environment(\.modelContext) private var viewContext

    // MARK: - Navigation (Feature #118)

    /// Binding to the selected tab index for navigating to Dashboard on cancel
    @Binding var selectedTab: Int

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
    @State private var selectedToolIDs: Set<UUID> = []

    // MARK: - Consumable Selection State

    /// Set of selected consumable object IDs from Garage picker
    @State private var selectedConsumableIDs: Set<UUID> = []

    // MARK: - Chemical Selection State

    /// Set of selected chemical object IDs from Garage picker
    @State private var selectedChemicalIDs: Set<UUID> = []

    // MARK: - Part Selection State (Feature #141)

    /// Set of selected part object IDs for this job
    @State private var selectedPartIDs: Set<UUID> = []

    // MARK: - Sheet Management
    /// Single active sheet to avoid SwiftUI's multiple .sheet modifier bug.
    /// Only one sheet can be presented at a time.
    @State private var activeSheet: NewJobSheet?

    // MARK: - UI State

    @State private var showingSaveSuccess = false
    @State private var showingError = false
    @State private var errorMessage = ""
    @State private var savedJobAircraftType = ""
    @State private var showAircraftTypeRequired = false
    @State private var showSystemRequired = false
    // showingVoiceCapture removed — managed via activeSheet enum
    /// Flag to prevent double-tap creating duplicate job records
    @State private var isSaving = false

    // MARK: - Feature #118: Cancel Button State

    /// Shows confirmation dialog when user taps Cancel with unsaved data
    @State private var showingCancelConfirmation = false

    // MARK: - Feature #96: On-the-fly items prompt state

    /// Shows the "Add to Garage" prompt for on-the-fly items after saving
    // showingAddToGaragePrompt removed — managed via activeSheet enum
    /// On-the-fly tools (isInGarage = false) that were added to the job
    @State private var onTheFlyTools: [Tool] = []
    /// On-the-fly consumables (isInGarage = false) that were added to the job
    @State private var onTheFlyConsumables: [Consumable] = []
    /// On-the-fly chemicals (isInGarage = false) that were added to the job
    @State private var onTheFlyChemicals: [Chemical] = []

    // MARK: - System Options (now handled by SystemAutocompleteField - Feature #102)

    /// Whether the form has the minimum required fields filled
    private var canSave: Bool {
        !aircraftType.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
        !selectedSystem.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    /// Feature #118: Whether the form has any unsaved data (user has entered something)
    /// Used to determine if we should show a confirmation dialog when canceling
    private var hasUnsavedData: Bool {
        !aircraftType.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ||
        !aircraftSerialNumber.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ||
        !nNumber.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ||
        !selectedSystem.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ||
        !component.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ||
        !taskDescription.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ||
        !tmReferences.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ||
        !notes.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ||
        !selectedToolIDs.isEmpty ||
        !selectedConsumableIDs.isEmpty ||
        !selectedChemicalIDs.isEmpty ||
        !selectedPartIDs.isEmpty
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
                            .accessibilityLabel("For Reference Only disclaimer banner")
                        Spacer()
                    }
                }

                // MARK: - Voice Capture
                Section(header: Text("Voice Capture")) {
                    Button(action: {
                        activeSheet = .voiceCapture
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
                    // Feature #99: Aircraft type autocomplete from previous entries
                    AircraftTypeAutocompleteView(
                        aircraftType: $aircraftType,
                        placeholder: "Aircraft Type (required)",
                        accessibilityPrefix: ""
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
                            .accessibilityIdentifier("aircraftTypeRequiredLabel")
                    }

                    // Feature #100: Serial number autocomplete from previous entries
                    SerialNumberAutocompleteField(
                        text: $aircraftSerialNumber,
                        placeholder: "Serial Number",
                        accessibilityId: "serialNumberField"
                    )

                    // Feature #101: N-number autocomplete from previous entries
                    NNumberAutocompleteField(
                        text: $nNumber,
                        placeholder: "N-Number / Tail Number",
                        accessibilityId: "nNumberField"
                    )
                }

                // MARK: - System & Component
                Section(header: Text("System & Component")) {
                    // Feature #102: System field autocomplete from previous entries
                    SystemAutocompleteField(
                        text: $selectedSystem,
                        placeholder: "System (required)",
                        accessibilityId: "systemField"
                    )
                    .onChange(of: selectedSystem) { _, newValue in
                        if !newValue.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                            showSystemRequired = false
                        }
                    }

                    if showSystemRequired {
                        Text("System is required")
                            .font(.caption)
                            .foregroundColor(.red)
                            .accessibilityIdentifier("systemRequiredLabel")
                    }

                    // Feature #103: Component field autocomplete from previous entries
                    ComponentAutocompleteField(
                        text: $component,
                        placeholder: "Component",
                        accessibilityId: "componentField"
                    )
                }

                // MARK: - Job Date
                Section(header: Text("Job Date")) {
                    DatePicker("Date", selection: $jobDate, displayedComponents: .date)
                        .datePickerStyle(.compact)
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

                // MARK: - Notes (Feature #126)
                Section(header: Text("Notes & Recommendations")) {
                    VStack(alignment: .leading, spacing: 8) {
                        TextField("Enter a note, press return for new item", text: $notes, axis: .vertical)
                            .lineLimit(3...10)
                            .font(.body)
                            .accessibilityIdentifier("notesField")
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
                                        .accessibilityIdentifier("notesPreviewHeader")
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
                                .accessibilityIdentifier("notesPreviewList")
                            }
                        }

                        // Hint text
                        Text("Press return to add multiple notes")
                            .font(.caption2)
                            .foregroundColor(.secondary)
                            .accessibilityIdentifier("notesHintText")
                    }
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
                        .accessibilityIdentifier("addToolsFromGarageButton")
                        .accessibilityLabel("Add Tools from Garage")
                        .accessibilityHint("Opens picker to select tools from your Garage")
                    } else {
                        // Show selected tools
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
                                // Large tap target for gloved hands (44x44pt minimum)
                                Button(action: {
                                    selectedToolIDs.remove(tool.id)
                                }) {
                                    Image(systemName: "xmark.circle.fill")
                                        .font(.title2)
                                        .foregroundColor(.secondary)
                                        .frame(width: 44, height: 44)
                                        .contentShape(Rectangle())
                                }
                                .buttonStyle(.plain)
                                .accessibilityLabel("Remove \(tool.name)")
                            }
                        }

                        // Button to add more tools - large tap target
                        Button(action: { activeSheet = .toolPicker }) {
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
                        .accessibilityIdentifier("addConsumablesFromGarageButton")
                        .accessibilityLabel("Add Consumables from Garage")
                        .accessibilityHint("Opens picker to select consumables from your Garage")
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
                                // Large tap target for gloved hands (44x44pt minimum)
                                Button(action: {
                                    selectedConsumableIDs.remove(consumable.id)
                                }) {
                                    Image(systemName: "xmark.circle.fill")
                                        .font(.title2)
                                        .foregroundColor(.secondary)
                                        .frame(width: 44, height: 44)
                                        .contentShape(Rectangle())
                                }
                                .buttonStyle(.plain)
                                .accessibilityLabel("Remove \(consumable.name)")
                            }
                        }

                        // Large tap target for Add More button
                        Button(action: { activeSheet = .consumablePicker }) {
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
                        .accessibilityIdentifier("addChemicalsFromGarageButton")
                        .accessibilityLabel("Add Chemicals from Garage")
                        .accessibilityHint("Opens picker to select chemicals from your Garage")
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
                                // Large tap target for gloved hands (44x44pt minimum)
                                Button(action: {
                                    selectedChemicalIDs.remove(chemical.id)
                                }) {
                                    Image(systemName: "xmark.circle.fill")
                                        .font(.title2)
                                        .foregroundColor(.secondary)
                                        .frame(width: 44, height: 44)
                                        .contentShape(Rectangle())
                                }
                                .buttonStyle(.plain)
                                .accessibilityLabel("Remove \(chemical.name)")
                            }
                        }

                        // Large tap target for Add More button
                        Button(action: { activeSheet = .chemicalPicker }) {
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
                        .accessibilityIdentifier("addPartButton")
                        .accessibilityLabel("Add Part")
                        .accessibilityHint("Opens form to add a part used on this job")
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
                                        .font(.title2)
                                        .foregroundColor(.secondary)
                                        .frame(width: 44, height: 44)
                                        .contentShape(Rectangle())
                                }
                                .buttonStyle(.plain)
                                .accessibilityLabel("Remove \(part.nomenclature)")
                            }
                        }

                        Button(action: { activeSheet = .partEntry }) {
                            HStack {
                                Image(systemName: "plus.circle")
                                    .font(.title3)
                                    .foregroundColor(Color(red: 0.145, green: 0.388, blue: 0.922))
                                Text("Add More Parts")
                                    .foregroundColor(Color(red: 0.145, green: 0.388, blue: 0.922))
                            }
                            .frame(minHeight: 44)
                        }
                        .accessibilityIdentifier("addMorePartsButton")
                        .accessibilityLabel("Add More Parts")
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
            // Feature #117: Tap outside text fields dismisses keyboard
            // When the keyboard is visible, tapping on non-interactive areas of the form
            // (section headers, background, etc.) or scrolling the form will dismiss the keyboard.
            // This makes the tab bar accessible again for navigation.
            .scrollDismissesKeyboard(.interactively)
            .navigationTitle("New Job")
            .navigationBarTitleDisplayMode(.large)
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
                        
                case .voiceCapture:
                    VoiceCaptureView(
                        onTranscriptionWithCandidates: { toolIDs, consumableIDs, chemicalIDs, transcribedText in
                            if taskDescription.isEmpty {
                                taskDescription = transcribedText
                            } else {
                                taskDescription += "\n\n[Voice Memo]\n" + transcribedText
                            }
                            selectedToolIDs = selectedToolIDs.union(toolIDs)
                            selectedConsumableIDs = selectedConsumableIDs.union(consumableIDs)
                            selectedChemicalIDs = selectedChemicalIDs.union(chemicalIDs)
                            print("NewJobView: Voice transcription added - tools: \(toolIDs.count), consumables: \(consumableIDs.count), chemicals: \(chemicalIDs.count)")
                        },
                        onTranscriptionComplete: { transcribedText in
                            if taskDescription.isEmpty {
                                taskDescription = transcribedText
                            } else {
                                taskDescription += "\n\n[Voice Memo]\n" + transcribedText
                            }
                            print("NewJobView: Voice transcription added to task description (text only)")
                        },
                        isPresented: Binding(
                            get: { activeSheet == .voiceCapture },
                            set: { if !$0 { activeSheet = nil } }
                        )
                    )
                    
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
            // MARK: - Feature #116: Keyboard Dismiss Button
            // Adds a "Done" button above the keyboard to allow users to dismiss it
            // and reveal the tab bar for navigation to other sections
            .toolbar {
                ToolbarItemGroup(placement: .keyboard) {
                    Spacer()
                    Button("Done") {
                        // Dismiss the keyboard by resigning first responder
                        UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
                    }
                    .accessibilityIdentifier("keyboardDoneButton")
                    .accessibilityLabel("Done")
                    .accessibilityHint("Dismisses the keyboard to reveal the tab bar")
                }

                // MARK: - Feature #118: Cancel Button in Navigation Bar
                // Provides a clear escape path when users need to leave the New Job screen
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cancel") {
                        // Dismiss keyboard first
                        UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)

                        if hasUnsavedData {
                            // Show confirmation dialog if form has data
                            showingCancelConfirmation = true
                        } else {
                            // Navigate directly to Dashboard if form is empty
                            navigateToDashboard()
                        }
                    }
                    .accessibilityIdentifier("cancelButton")
                    .accessibilityLabel("Cancel")
                    .accessibilityHint(hasUnsavedData ? "Shows confirmation to discard changes" : "Returns to Dashboard")
                }
            }
            // MARK: - Feature #118: Cancel Confirmation Dialog
            .alert("Discard Changes?", isPresented: $showingCancelConfirmation) {
                Button("Keep Editing", role: .cancel) {
                    // Do nothing, stay on form
                }
                Button("Discard", role: .destructive) {
                    // Reset form and navigate to Dashboard
                    resetForm()
                    navigateToDashboard()
                }
            } message: {
                Text("You have unsaved changes. Are you sure you want to discard them?")
            }
        }
    }

    // MARK: - Feature #118: Navigation Helper

    /// Navigates to the Dashboard tab (tab index 0)
    private func navigateToDashboard() {
        selectedTab = 0
        print("NewJobView: Navigated to Dashboard via Cancel button")
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
        let trimmedSystem = selectedSystem.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedSystem.isEmpty else {
            errorMessage = "System is required."
            showSystemRequired = true
            showingError = true
            return
        }

        // Set saving flag to disable button and prevent duplicate saves
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

        // Feature #96: Track on-the-fly items (isInGarage = false) for post-save prompt
        var newOnTheFlyTools: [FROTool] = []
        var newOnTheFlyConsumables: [FROConsumable] = []
        var newOnTheFlyChemicals: [FROChemical] = []

        // Link selected tools from Garage to the job record
        for toolID in selectedToolIDs {
            if let tool = fetchByPersistentID(FROTool.self, id: toolID, context: viewContext) {
                if record.tools == nil { record.tools = [] }
                record.tools?.append(tool)
                print("NewJobView: Linked tool '\(tool.name)' to job record")
                // Track if this is an on-the-fly item (not yet in Garage)
                if !tool.isInGarage {
                    newOnTheFlyTools.append(tool)
                    print("NewJobView: Detected on-the-fly tool '\(tool.name)'")
                }
            }
        }

        // Link selected consumables from Garage to the job record
        for consumableID in selectedConsumableIDs {
            if let consumable = fetchByPersistentID(FROConsumable.self, id: consumableID, context: viewContext) {
                if record.consumables == nil { record.consumables = [] }
                record.consumables?.append(consumable)
                print("NewJobView: Linked consumable '\(consumable.name)' to job record")
                // Track if this is an on-the-fly item (not yet in Garage)
                if !consumable.isInGarage {
                    newOnTheFlyConsumables.append(consumable)
                    print("NewJobView: Detected on-the-fly consumable '\(consumable.name)'")
                }
            }
        }

        // Link selected chemicals from Garage to the job record
        for chemicalID in selectedChemicalIDs {
            if let chemical = fetchByPersistentID(FROChemical.self, id: chemicalID, context: viewContext) {
                if record.chemicals == nil { record.chemicals = [] }
                record.chemicals?.append(chemical)
                print("NewJobView: Linked chemical '\(chemical.name)' to job record")
                // Track if this is an on-the-fly item (not yet in Garage)
                if !chemical.isInGarage {
                    newOnTheFlyChemicals.append(chemical)
                    print("NewJobView: Detected on-the-fly chemical '\(chemical.name)'")
                }
            }
        }

        // Feature #141: Link selected parts to the job record
        for partID in selectedPartIDs {
            if let part = fetchByPersistentID(FROPart.self, id: partID, context: viewContext) {
                if record.parts == nil { record.parts = [] }
                record.parts?.append(part)
                print("NewJobView: Linked part '\(part.nomenclature)' P/N: \(part.partNumber)")
            }
        }

        do {
            try viewContext.save()
            print("NewJobView: Saved job record for '\(trimmedAircraftType)' - system: \(trimmedSystem), tools: \(selectedToolIDs.count)")
            savedJobAircraftType = trimmedAircraftType
            isSaving = false  // Reset saving flag on success

            // Feature #96: Check if there are on-the-fly items to prompt about
            let hasOnTheFlyItems = !newOnTheFlyTools.isEmpty || !newOnTheFlyConsumables.isEmpty || !newOnTheFlyChemicals.isEmpty

            if hasOnTheFlyItems {
                // Store on-the-fly items and show the prompt
                onTheFlyTools = newOnTheFlyTools
                onTheFlyConsumables = newOnTheFlyConsumables
                onTheFlyChemicals = newOnTheFlyChemicals
                print("NewJobView: Showing Add to Garage prompt for \(newOnTheFlyTools.count) tools, \(newOnTheFlyConsumables.count) consumables, \(newOnTheFlyChemicals.count) chemicals")
                activeSheet = .addToGaragePrompt
            } else {
                // No on-the-fly items, show regular success alert
                showingSaveSuccess = true
            }
            resetForm()
        } catch {
            // CRITICAL: Rollback the context on failure to prevent partial/corrupted
            // records from lingering. Without rollback, the unsaved JobRecord object
            // stays in the context and could be inadvertently saved later or cause
            // corruption if the user navigates away and another save occurs.
            print("NewJobView: Save failed, context rolled back - \(error)")
            isSaving = false  // Reset saving flag on error
            errorMessage = "Failed to save job record: \(error.localizedDescription)"
            showingError = true
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
        selectedPartIDs = []
    }
}

#Preview {
    NewJobView(selectedTab: .constant(1))
        
}

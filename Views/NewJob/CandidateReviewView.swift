import SwiftUI
import CoreData

/// View displayed after voice transcription completes, showing identified candidate
/// tools, consumables, and chemicals from the transcription text.
/// Users can confirm, remove, or add items before applying to the job record.
struct CandidateReviewView: View {
    let candidates: [TranscriptionCandidate]

    /// Callback with selected tool IDs, consumable IDs, chemical IDs, and the (possibly edited) transcribed text
    var onConfirm: (Set<NSManagedObjectID>, Set<NSManagedObjectID>, Set<NSManagedObjectID>, String) -> Void

    @Binding var isPresented: Bool

    @Environment(\.managedObjectContext) private var viewContext

    // Editable transcription text
    @State private var editableText: String
    @State private var isEditingText: Bool = false

    // Track which candidates are selected (all selected by default for high/medium confidence)
    @State private var selectedCandidateIDs: Set<UUID> = []

    // Manually added items from Garage (not from transcription matching)
    @State private var manuallyAddedToolIDs: Set<NSManagedObjectID> = []
    @State private var manuallyAddedConsumableIDs: Set<NSManagedObjectID> = []
    @State private var manuallyAddedChemicalIDs: Set<NSManagedObjectID> = []

    // Garage picker sheets
    @State private var showingToolPicker = false
    @State private var showingConsumablePicker = false
    @State private var showingChemicalPicker = false

    init(transcribedText: String, candidates: [TranscriptionCandidate],
         onConfirm: @escaping (Set<NSManagedObjectID>, Set<NSManagedObjectID>, Set<NSManagedObjectID>, String) -> Void,
         isPresented: Binding<Bool>) {
        self.candidates = candidates
        self.onConfirm = onConfirm
        self._isPresented = isPresented
        self._editableText = State(initialValue: transcribedText)
    }

    // Categorized candidates
    private var toolCandidates: [TranscriptionCandidate] {
        candidates.filter { $0.type == .tool }
    }

    private var consumableCandidates: [TranscriptionCandidate] {
        candidates.filter { $0.type == .consumable }
    }

    private var chemicalCandidates: [TranscriptionCandidate] {
        candidates.filter { $0.type == .chemical }
    }

    private var uncertainCandidates: [TranscriptionCandidate] {
        candidates.filter { $0.confidence == .low }
    }

    // Resolve manually added items to display names
    private var manuallyAddedTools: [Tool] {
        manuallyAddedToolIDs.compactMap { id in
            try? viewContext.existingObject(with: id) as? Tool
        }.sorted { ($0.name ?? "") < ($1.name ?? "") }
    }

    private var manuallyAddedConsumables: [Consumable] {
        manuallyAddedConsumableIDs.compactMap { id in
            try? viewContext.existingObject(with: id) as? Consumable
        }.sorted { ($0.name ?? "") < ($1.name ?? "") }
    }

    private var manuallyAddedChemicals: [Chemical] {
        manuallyAddedChemicalIDs.compactMap { id in
            try? viewContext.existingObject(with: id) as? Chemical
        }.sorted { ($0.name ?? "") < ($1.name ?? "") }
    }

    /// Total number of selected items (auto-detected + manually added)
    private var totalSelectedCount: Int {
        selectedCandidateIDs.count + manuallyAddedToolIDs.count + manuallyAddedConsumableIDs.count + manuallyAddedChemicalIDs.count
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 20) {
                    // MARK: - Transcription Summary (Editable)
                    transcriptionSummary

                    // MARK: - Identified Tools
                    if !toolCandidates.isEmpty {
                        candidateSection(
                            title: "Candidate Tools",
                            icon: "wrench.and.screwdriver",
                            color: Color(red: 0.145, green: 0.388, blue: 0.922),
                            items: toolCandidates
                        )
                    }

                    // MARK: - Identified Consumables
                    if !consumableCandidates.isEmpty {
                        candidateSection(
                            title: "Candidate Consumables",
                            icon: "bolt.fill",
                            color: Color(red: 0.976, green: 0.451, blue: 0.086),
                            items: consumableCandidates
                        )
                    }

                    // MARK: - Identified Chemicals
                    if !chemicalCandidates.isEmpty {
                        candidateSection(
                            title: "Candidate Chemicals",
                            icon: "drop.fill",
                            color: Color(red: 0.306, green: 0.694, blue: 0.482),
                            items: chemicalCandidates
                        )
                    }

                    // MARK: - Uncertain Items Warning
                    if !uncertainCandidates.isEmpty {
                        uncertainItemsSection
                    }

                    // MARK: - Manually Added Items
                    if !manuallyAddedTools.isEmpty || !manuallyAddedConsumables.isEmpty || !manuallyAddedChemicals.isEmpty {
                        manuallyAddedSection
                    }

                    // MARK: - Add Missing Items
                    addFromGarageSection

                    // MARK: - No Candidates Found
                    if candidates.isEmpty && manuallyAddedToolIDs.isEmpty && manuallyAddedConsumableIDs.isEmpty && manuallyAddedChemicalIDs.isEmpty {
                        noCandidatesView
                    }

                    // MARK: - Action Buttons
                    actionButtons
                }
                .padding()
            }
            .navigationTitle("Review Candidates")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cancel") {
                        isPresented = false
                    }
                }
            }
            .onAppear {
                // Pre-select high and medium confidence candidates
                selectedCandidateIDs = Set(
                    candidates
                        .filter { $0.confidence == .high || $0.confidence == .medium }
                        .map { $0.id }
                )
            }
            .sheet(isPresented: $showingToolPicker) {
                GarageToolPickerView(selectedToolIDs: $manuallyAddedToolIDs)
                    .environment(\.managedObjectContext, viewContext)
            }
            .sheet(isPresented: $showingConsumablePicker) {
                GarageConsumablePickerView(selectedConsumableIDs: $manuallyAddedConsumableIDs)
                    .environment(\.managedObjectContext, viewContext)
            }
            .sheet(isPresented: $showingChemicalPicker) {
                GarageChemicalPickerView(selectedChemicalIDs: $manuallyAddedChemicalIDs)
                    .environment(\.managedObjectContext, viewContext)
            }
        }
    }

    // MARK: - Transcription Summary (Editable)

    private var transcriptionSummary: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Image(systemName: "text.bubble.fill")
                    .foregroundColor(Color(red: 0.145, green: 0.388, blue: 0.922))
                Text("Transcription")
                    .font(.subheadline)
                    .fontWeight(.semibold)

                Spacer()

                Button(action: {
                    isEditingText.toggle()
                }) {
                    HStack(spacing: 4) {
                        Image(systemName: isEditingText ? "checkmark.circle.fill" : "pencil.circle")
                            .foregroundColor(Color(red: 0.145, green: 0.388, blue: 0.922))
                        Text(isEditingText ? "Done" : "Edit")
                            .font(.caption)
                            .fontWeight(.medium)
                            .foregroundColor(Color(red: 0.145, green: 0.388, blue: 0.922))
                    }
                }
                .accessibilityIdentifier("editTranscriptionButton")
            }

            if isEditingText {
                TextEditor(text: $editableText)
                    .font(.body)
                    .frame(minHeight: 100, maxHeight: 200)
                    .padding(8)
                    .background(Color(.systemBackground))
                    .cornerRadius(10)
                    .overlay(
                        RoundedRectangle(cornerRadius: 10)
                            .stroke(Color(red: 0.145, green: 0.388, blue: 0.922), lineWidth: 1.5)
                    )
                    .accessibilityIdentifier("editableTranscriptionField")

                Text("Edit the transcription text before finalizing.")
                    .font(.caption2)
                    .foregroundColor(.secondary)
            } else {
                Text(editableText)
                    .font(.body)
                    .foregroundColor(.primary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding()
                    .background(Color(.systemGray6))
                    .cornerRadius(10)
                    .accessibilityIdentifier("candidateTranscriptionText")
            }
        }
    }

    // MARK: - Candidate Section

    private func candidateSection(title: String, icon: String, color: Color, items: [TranscriptionCandidate]) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Image(systemName: icon)
                    .foregroundColor(color)
                Text(title)
                    .font(.subheadline)
                    .fontWeight(.semibold)
                Text("(\(items.count))")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            .accessibilityIdentifier("\(title.replacingOccurrences(of: " ", with: ""))Header")

            VStack(spacing: 4) {
                ForEach(items) { candidate in
                    candidateRow(candidate: candidate, accentColor: color)
                }
            }
        }
    }

    private func candidateRow(candidate: TranscriptionCandidate, accentColor: Color) -> some View {
        let isSelected = selectedCandidateIDs.contains(candidate.id)

        return HStack(spacing: 12) {
            // Selection toggle
            Button(action: {
                if isSelected {
                    selectedCandidateIDs.remove(candidate.id)
                } else {
                    selectedCandidateIDs.insert(candidate.id)
                }
            }) {
                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .foregroundColor(isSelected ? accentColor : .secondary)
                    .font(.title3)
            }
            .buttonStyle(.plain)

            // Item info
            VStack(alignment: .leading, spacing: 2) {
                Text(candidate.name)
                    .font(.body)
                    .fontWeight(.medium)
                    .foregroundColor(.primary)

                HStack(spacing: 6) {
                    // Type badge
                    Text(candidate.type.rawValue)
                        .font(.caption2)
                        .fontWeight(.semibold)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(accentColor.opacity(0.15))
                        .foregroundColor(accentColor)
                        .cornerRadius(4)

                    // Confidence badge
                    confidenceBadge(candidate.confidence)

                    // Matched phrase
                    if candidate.confidence != .high || candidate.matchedPhrase.lowercased() != candidate.name.lowercased() {
                        Text("matched: \"\(candidate.matchedPhrase)\"")
                            .font(.caption2)
                            .foregroundColor(.secondary)
                            .italic()
                    }
                }
            }

            Spacer()

            // Remove button - deselects and visually removes
            if isSelected {
                Button(action: {
                    selectedCandidateIDs.remove(candidate.id)
                }) {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundColor(.secondary)
                        .font(.body)
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("remove_\(candidate.name.replacingOccurrences(of: " ", with: "_"))")
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(isSelected ? accentColor.opacity(0.05) : Color(.systemGray6))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(isSelected ? accentColor.opacity(0.3) : Color.clear, lineWidth: 1)
        )
        .accessibilityIdentifier("candidate_\(candidate.name.replacingOccurrences(of: " ", with: "_"))")
    }

    private func confidenceBadge(_ confidence: TranscriptionCandidate.MatchConfidence) -> some View {
        let (text, color): (String, Color) = {
            switch confidence {
            case .high: return ("High", .green)
            case .medium: return ("Medium", .orange)
            case .low: return ("Uncertain", .red)
            }
        }()

        return Text(text)
            .font(.caption2)
            .fontWeight(.medium)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(color.opacity(0.15))
            .foregroundColor(color)
            .cornerRadius(4)
            .accessibilityIdentifier("confidence_\(confidence.rawValue)")
    }

    // MARK: - Uncertain Items Section

    private var uncertainItemsSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundColor(.orange)
                Text("Uncertain Matches")
                    .font(.subheadline)
                    .fontWeight(.semibold)
                Text("- Manual confirmation recommended")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            .accessibilityIdentifier("uncertainMatchesHeader")

            Text("These items had low-confidence matches. Tap to select or deselect them.")
                .font(.caption)
                .foregroundColor(.secondary)
        }
    }

    // MARK: - Manually Added Items Section

    private var manuallyAddedSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Image(systemName: "plus.circle.fill")
                    .foregroundColor(Color(red: 0.145, green: 0.388, blue: 0.922))
                Text("Manually Added Items")
                    .font(.subheadline)
                    .fontWeight(.semibold)
            }
            .accessibilityIdentifier("manuallyAddedHeader")

            // Manually added tools
            ForEach(manuallyAddedTools, id: \.objectID) { tool in
                manuallyAddedRow(
                    name: tool.name ?? "Unnamed Tool",
                    typeBadge: "Tool",
                    color: Color(red: 0.145, green: 0.388, blue: 0.922),
                    onRemove: { manuallyAddedToolIDs.remove(tool.objectID) }
                )
            }

            // Manually added consumables
            ForEach(manuallyAddedConsumables, id: \.objectID) { consumable in
                manuallyAddedRow(
                    name: consumable.name ?? "Unnamed Consumable",
                    typeBadge: "Consumable",
                    color: Color(red: 0.976, green: 0.451, blue: 0.086),
                    onRemove: { manuallyAddedConsumableIDs.remove(consumable.objectID) }
                )
            }

            // Manually added chemicals
            ForEach(manuallyAddedChemicals, id: \.objectID) { chemical in
                manuallyAddedRow(
                    name: chemical.name ?? "Unnamed Chemical",
                    typeBadge: "Chemical",
                    color: Color(red: 0.306, green: 0.694, blue: 0.482),
                    onRemove: { manuallyAddedChemicalIDs.remove(chemical.objectID) }
                )
            }
        }
    }

    private func manuallyAddedRow(name: String, typeBadge: String, color: Color, onRemove: @escaping () -> Void) -> some View {
        HStack(spacing: 12) {
            Image(systemName: "checkmark.circle.fill")
                .foregroundColor(color)
                .font(.title3)

            VStack(alignment: .leading, spacing: 2) {
                Text(name)
                    .font(.body)
                    .fontWeight(.medium)
                    .foregroundColor(.primary)

                HStack(spacing: 6) {
                    Text(typeBadge)
                        .font(.caption2)
                        .fontWeight(.semibold)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(color.opacity(0.15))
                        .foregroundColor(color)
                        .cornerRadius(4)

                    Text("Manually Added")
                        .font(.caption2)
                        .fontWeight(.medium)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Color.purple.opacity(0.15))
                        .foregroundColor(.purple)
                        .cornerRadius(4)
                }
            }

            Spacer()

            Button(action: onRemove) {
                Image(systemName: "xmark.circle.fill")
                    .foregroundColor(.secondary)
                    .font(.body)
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("removeManual_\(name.replacingOccurrences(of: " ", with: "_"))")
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(color.opacity(0.05))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(color.opacity(0.3), lineWidth: 1)
        )
    }

    // MARK: - Add From Garage Section

    private var addFromGarageSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Image(systemName: "tray.and.arrow.down")
                    .foregroundColor(.secondary)
                Text("Add Missed Items")
                    .font(.subheadline)
                    .fontWeight(.semibold)
                    .foregroundColor(.secondary)
            }

            Text("Didn't find something? Add items from your Garage manually.")
                .font(.caption)
                .foregroundColor(.secondary)

            HStack(spacing: 12) {
                // Add Tool
                Button(action: { showingToolPicker = true }) {
                    VStack(spacing: 4) {
                        Image(systemName: "wrench.and.screwdriver")
                            .font(.title3)
                        Text("Tool")
                            .font(.caption2)
                            .fontWeight(.medium)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
                    .background(Color(red: 0.145, green: 0.388, blue: 0.922).opacity(0.1))
                    .foregroundColor(Color(red: 0.145, green: 0.388, blue: 0.922))
                    .cornerRadius(10)
                }
                .accessibilityIdentifier("addToolFromGarageButton")

                // Add Consumable
                Button(action: { showingConsumablePicker = true }) {
                    VStack(spacing: 4) {
                        Image(systemName: "bolt.fill")
                            .font(.title3)
                        Text("Consumable")
                            .font(.caption2)
                            .fontWeight(.medium)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
                    .background(Color(red: 0.976, green: 0.451, blue: 0.086).opacity(0.1))
                    .foregroundColor(Color(red: 0.976, green: 0.451, blue: 0.086))
                    .cornerRadius(10)
                }
                .accessibilityIdentifier("addConsumableFromGarageButton")

                // Add Chemical
                Button(action: { showingChemicalPicker = true }) {
                    VStack(spacing: 4) {
                        Image(systemName: "drop.fill")
                            .font(.title3)
                        Text("Chemical")
                            .font(.caption2)
                            .fontWeight(.medium)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
                    .background(Color(red: 0.306, green: 0.694, blue: 0.482).opacity(0.1))
                    .foregroundColor(Color(red: 0.306, green: 0.694, blue: 0.482))
                    .cornerRadius(10)
                }
                .accessibilityIdentifier("addChemicalFromGarageButton")
            }
        }
    }

    // MARK: - No Candidates View

    private var noCandidatesView: some View {
        VStack(spacing: 12) {
            Image(systemName: "magnifyingglass")
                .font(.largeTitle)
                .foregroundColor(.secondary)

            Text("No Garage Items Identified")
                .font(.headline)
                .foregroundColor(.primary)

            Text("The transcription didn't match any tools, consumables, or chemicals in your Garage. Use the buttons above to add items manually.")
                .font(.body)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
        }
        .padding(.vertical, 30)
        .accessibilityIdentifier("noCandidatesMessage")
    }

    // MARK: - Action Buttons

    private var actionButtons: some View {
        VStack(spacing: 12) {
            // Confirm button
            Button(action: {
                let selectedSet = selectedCandidateIDs
                var toolIDs = Set<NSManagedObjectID>()
                var consumableIDs = Set<NSManagedObjectID>()
                var chemicalIDs = Set<NSManagedObjectID>()

                // Add auto-detected selected candidates
                for candidate in candidates where selectedSet.contains(candidate.id) {
                    switch candidate.type {
                    case .tool: toolIDs.insert(candidate.objectID)
                    case .consumable: consumableIDs.insert(candidate.objectID)
                    case .chemical: chemicalIDs.insert(candidate.objectID)
                    }
                }

                // Merge manually added items
                toolIDs = toolIDs.union(manuallyAddedToolIDs)
                consumableIDs = consumableIDs.union(manuallyAddedConsumableIDs)
                chemicalIDs = chemicalIDs.union(manuallyAddedChemicalIDs)

                onConfirm(toolIDs, consumableIDs, chemicalIDs, editableText)
                isPresented = false
            }) {
                HStack {
                    Image(systemName: "checkmark.circle.fill")
                    Text(totalSelectedCount == 0 ? "Use Transcription Only" : "Confirm \(totalSelectedCount) Item\(totalSelectedCount == 1 ? "" : "s")")
                        .fontWeight(.semibold)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 14)
                .background(Color(red: 0.145, green: 0.388, blue: 0.922))
                .foregroundColor(.white)
                .cornerRadius(12)
            }
            .accessibilityIdentifier("confirmCandidatesButton")

            // Skip and use text only
            Button(action: {
                onConfirm([], [], [], editableText)
                isPresented = false
            }) {
                HStack {
                    Image(systemName: "text.badge.checkmark")
                    Text("Skip Items — Use Text Only")
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 14)
                .background(Color(.systemGray5))
                .foregroundColor(.primary)
                .cornerRadius(12)
            }
            .accessibilityIdentifier("skipCandidatesButton")
        }
    }
}

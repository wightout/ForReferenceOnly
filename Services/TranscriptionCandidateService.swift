import CoreData

/// Represents a matched item from the Garage identified in transcribed text.
/// Includes the entity type, confidence level, and the matched text span.
struct TranscriptionCandidate: Identifiable {
    let id = UUID()
    let name: String
    let objectID: NSManagedObjectID
    let type: CandidateType
    let confidence: MatchConfidence
    let matchedPhrase: String

    enum CandidateType: String {
        case tool = "Tool"
        case consumable = "Consumable"
        case chemical = "Chemical"
    }

    enum MatchConfidence: String {
        case high = "High"      // Exact or near-exact match
        case medium = "Medium"  // Partial match (word boundary)
        case low = "Low"        // Fuzzy/uncertain match
    }
}

/// TranscriptionCandidateService identifies tools, consumables, and chemicals
/// from transcribed voice text by matching against the user's Garage inventory.
/// Uses Core Data fetch requests against the real SQLite database.
class TranscriptionCandidateService {

    // MARK: - Properties

    private let persistenceController: PersistenceController

    var viewContext: NSManagedObjectContext {
        persistenceController.viewContext
    }

    // MARK: - Initialization

    init(persistenceController: PersistenceController = .shared) {
        self.persistenceController = persistenceController
    }

    // MARK: - Main Identification

    /// Identifies candidate tools, consumables, and chemicals from transcribed text.
    /// Fetches all Garage items from Core Data and matches them against the transcription.
    /// - Parameter transcription: The transcribed voice text
    /// - Returns: Array of TranscriptionCandidate objects sorted by confidence
    func identifyCandidates(from transcription: String) -> [TranscriptionCandidate] {
        let normalizedText = transcription.lowercased()
        var candidates: [TranscriptionCandidate] = []

        // Fetch all tools from Garage
        let toolCandidates = matchTools(against: normalizedText)
        candidates.append(contentsOf: toolCandidates)

        // Fetch all consumables from Garage
        let consumableCandidates = matchConsumables(against: normalizedText)
        candidates.append(contentsOf: consumableCandidates)

        // Fetch all chemicals from Garage
        let chemicalCandidates = matchChemicals(against: normalizedText)
        candidates.append(contentsOf: chemicalCandidates)

        // Sort by confidence (high first), then by name
        candidates.sort { lhs, rhs in
            let lhsOrder = confidenceOrder(lhs.confidence)
            let rhsOrder = confidenceOrder(rhs.confidence)
            if lhsOrder != rhsOrder { return lhsOrder < rhsOrder }
            return lhs.name < rhs.name
        }

        print("TranscriptionCandidateService: Identified \(candidates.count) candidates from transcription")
        return candidates
    }

    // MARK: - Tool Matching

    private func matchTools(against normalizedText: String) -> [TranscriptionCandidate] {
        let request = NSFetchRequest<Tool>(entityName: "Tool")
        request.sortDescriptors = [NSSortDescriptor(key: "name", ascending: true)]

        do {
            let tools = try viewContext.fetch(request)
            var candidates: [TranscriptionCandidate] = []

            for tool in tools {
                guard let toolName = tool.name, !toolName.isEmpty else { continue }

                if let match = findMatch(itemName: toolName, aliases: tool.aliases as? [String], in: normalizedText) {
                    candidates.append(TranscriptionCandidate(
                        name: toolName,
                        objectID: tool.objectID,
                        type: .tool,
                        confidence: match.confidence,
                        matchedPhrase: match.phrase
                    ))
                }
            }

            print("TranscriptionCandidateService: Matched \(candidates.count) tools")
            return candidates
        } catch {
            print("TranscriptionCandidateService: Failed to fetch tools - \(error)")
            return []
        }
    }

    // MARK: - Consumable Matching

    private func matchConsumables(against normalizedText: String) -> [TranscriptionCandidate] {
        let request = NSFetchRequest<Consumable>(entityName: "Consumable")
        request.sortDescriptors = [NSSortDescriptor(key: "name", ascending: true)]

        do {
            let consumables = try viewContext.fetch(request)
            var candidates: [TranscriptionCandidate] = []

            for consumable in consumables {
                guard let name = consumable.name, !name.isEmpty else { continue }

                if let match = findMatch(itemName: name, aliases: nil, in: normalizedText) {
                    candidates.append(TranscriptionCandidate(
                        name: name,
                        objectID: consumable.objectID,
                        type: .consumable,
                        confidence: match.confidence,
                        matchedPhrase: match.phrase
                    ))
                }
            }

            print("TranscriptionCandidateService: Matched \(candidates.count) consumables")
            return candidates
        } catch {
            print("TranscriptionCandidateService: Failed to fetch consumables - \(error)")
            return []
        }
    }

    // MARK: - Chemical Matching

    private func matchChemicals(against normalizedText: String) -> [TranscriptionCandidate] {
        let request = NSFetchRequest<Chemical>(entityName: "Chemical")
        request.sortDescriptors = [NSSortDescriptor(key: "name", ascending: true)]

        do {
            let chemicals = try viewContext.fetch(request)
            var candidates: [TranscriptionCandidate] = []

            for chemical in chemicals {
                guard let name = chemical.name, !name.isEmpty else { continue }

                if let match = findMatch(itemName: name, aliases: nil, in: normalizedText) {
                    candidates.append(TranscriptionCandidate(
                        name: name,
                        objectID: chemical.objectID,
                        type: .chemical,
                        confidence: match.confidence,
                        matchedPhrase: match.phrase
                    ))
                }
            }

            print("TranscriptionCandidateService: Matched \(chemicals.count) chemicals checked, \(candidates.count) matched")
            return candidates
        } catch {
            print("TranscriptionCandidateService: Failed to fetch chemicals - \(error)")
            return []
        }
    }

    // MARK: - Matching Algorithm

    struct MatchResult {
        let confidence: TranscriptionCandidate.MatchConfidence
        let phrase: String
    }

    /// Attempts to match an item name (and optional aliases) against normalized transcription text.
    /// Uses a multi-tier matching strategy:
    /// 1. Exact full name match (case-insensitive) → High confidence
    /// 2. All significant words present → High confidence
    /// 3. Alias match → High confidence
    /// 4. Most significant words present (>=50%) → Medium confidence
    /// 5. Any significant word match (length >= 4) → Low confidence
    private func findMatch(itemName: String, aliases: [String]?, in normalizedText: String) -> MatchResult? {
        let normalizedName = itemName.lowercased()

        // Tier 1: Exact full name match (case-insensitive)
        if normalizedText.contains(normalizedName) {
            return MatchResult(confidence: .high, phrase: itemName)
        }

        // Tier 2: Check aliases for exact match
        if let aliases = aliases {
            for alias in aliases {
                let normalizedAlias = alias.lowercased()
                if normalizedText.contains(normalizedAlias) {
                    return MatchResult(confidence: .high, phrase: alias)
                }
            }
        }

        // Tier 3: Word-level matching
        let significantWords = extractSignificantWords(from: normalizedName)
        guard !significantWords.isEmpty else { return nil }

        let matchedWords = significantWords.filter { word in
            normalizedText.contains(word)
        }

        let matchRatio = Double(matchedWords.count) / Double(significantWords.count)

        if matchRatio >= 1.0 {
            // All significant words present → High
            return MatchResult(confidence: .high, phrase: matchedWords.joined(separator: " "))
        } else if matchRatio >= 0.5 && significantWords.count >= 2 {
            // At least half the significant words → Medium
            return MatchResult(confidence: .medium, phrase: matchedWords.joined(separator: " "))
        } else if matchedWords.contains(where: { $0.count >= 4 }) {
            // At least one significant word (4+ chars) matched → Low
            let longMatches = matchedWords.filter { $0.count >= 4 }
            if !longMatches.isEmpty {
                return MatchResult(confidence: .low, phrase: longMatches.joined(separator: " "))
            }
        }

        return nil
    }

    /// Extracts significant words from a name, filtering out common short words
    /// that would cause false positives (e.g., "a", "the", "in", "of")
    private func extractSignificantWords(from name: String) -> [String] {
        let stopWords: Set<String> = [
            "a", "an", "the", "in", "on", "of", "for", "to", "and", "or",
            "with", "by", "at", "from", "is", "it", "no", "not", "as"
        ]

        return name
            .components(separatedBy: CharacterSet.alphanumerics.inverted)
            .filter { word in
                let trimmed = word.trimmingCharacters(in: .whitespaces)
                return !trimmed.isEmpty && !stopWords.contains(trimmed) && trimmed.count >= 2
            }
    }

    private func confidenceOrder(_ confidence: TranscriptionCandidate.MatchConfidence) -> Int {
        switch confidence {
        case .high: return 0
        case .medium: return 1
        case .low: return 2
        }
    }
}

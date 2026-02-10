import Foundation
import SwiftData

/// SearchService provides universal and filtered search across all SwiftData entities.
/// Includes fuzzy/typo-tolerant matching using Levenshtein distance.
@MainActor
class SearchService {

    // MARK: - Properties

    private var modelContext: ModelContext {
        SharedModelContainer.shared.mainContext
    }

    /// Maximum Levenshtein distance for fuzzy matching (based on query length)
    /// Shorter queries need tighter matching; longer queries can tolerate more errors
    private func maxFuzzyDistance(for query: String) -> Int {
        let length = query.count
        if length <= 3 { return 1 }         // Short words: 1 typo max
        if length <= 6 { return 2 }         // Medium words: 2 typos max
        return 3                             // Long words: 3 typos max
    }

    // MARK: - Fuzzy Matching Utilities

    /// Calculates the Levenshtein edit distance between two strings.
    /// This measures the minimum number of single-character edits (insertions, deletions, substitutions)
    /// required to transform one string into another.
    /// - Parameters:
    ///   - s1: First string
    ///   - s2: Second string
    /// - Returns: The edit distance between the two strings
    func levenshteinDistance(_ s1: String, _ s2: String) -> Int {
        let str1 = Array(s1.lowercased())
        let str2 = Array(s2.lowercased())

        let m = str1.count
        let n = str2.count

        // Edge cases
        if m == 0 { return n }
        if n == 0 { return m }

        // Create distance matrix
        var dp = [[Int]](repeating: [Int](repeating: 0, count: n + 1), count: m + 1)

        // Initialize first row and column
        for i in 0...m { dp[i][0] = i }
        for j in 0...n { dp[0][j] = j }

        // Fill in the rest of the matrix
        for i in 1...m {
            for j in 1...n {
                if str1[i - 1] == str2[j - 1] {
                    dp[i][j] = dp[i - 1][j - 1]
                } else {
                    dp[i][j] = min(
                        dp[i - 1][j] + 1,      // deletion
                        dp[i][j - 1] + 1,      // insertion
                        dp[i - 1][j - 1] + 1   // substitution
                    )
                }
            }
        }

        return dp[m][n]
    }

    /// Normalizes a string for comparison by removing spaces, dashes, and lowercasing.
    /// This helps match "UH-60M Black Hawk" with "UH60M" or "blackhawk".
    /// - Parameter text: The text to normalize
    /// - Returns: Normalized text without spaces, dashes, or other special characters
    func normalizeForComparison(_ text: String) -> String {
        return text.lowercased()
            .replacingOccurrences(of: " ", with: "")
            .replacingOccurrences(of: "-", with: "")
            .replacingOccurrences(of: "_", with: "")
    }

    /// Checks if a query fuzzy-matches any part of the target text.
    /// Uses multiple matching strategies:
    /// 1. Exact contains match (case-insensitive)
    /// 2. Normalized match (ignoring spaces/dashes)
    /// 3. Word-by-word fuzzy match using Levenshtein distance
    /// - Parameters:
    ///   - query: The search query
    ///   - target: The target text to search in
    /// - Returns: true if the query fuzzy-matches the target
    func fuzzyMatches(query: String, target: String) -> Bool {
        let queryLower = query.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
        let targetLower = target.lowercased()

        // Strategy 1: Exact contains match (fast path)
        if targetLower.contains(queryLower) {
            return true
        }

        // Strategy 2: Normalized match (handles "UH60M" vs "UH-60M", "blackhawk" vs "Black Hawk")
        let normalizedQuery = normalizeForComparison(query)
        let normalizedTarget = normalizeForComparison(target)
        if normalizedTarget.contains(normalizedQuery) {
            return true
        }

        // Strategy 3: Word-by-word fuzzy matching (handles typos like "Black Hwak")
        let queryWords = queryLower.components(separatedBy: .whitespaces).filter { !$0.isEmpty }
        let targetWords = targetLower.components(separatedBy: .whitespaces).filter { !$0.isEmpty }

        // Each query word should fuzzy-match at least one target word
        for queryWord in queryWords {
            let maxDist = maxFuzzyDistance(for: queryWord)
            var foundMatch = false

            for targetWord in targetWords {
                // Check if target word contains query word (partial match)
                if targetWord.contains(queryWord) {
                    foundMatch = true
                    break
                }

                // Check Levenshtein distance for fuzzy match
                let distance = levenshteinDistance(queryWord, targetWord)
                if distance <= maxDist {
                    foundMatch = true
                    break
                }

                // Check if normalized versions match
                if normalizeForComparison(targetWord).contains(normalizeForComparison(queryWord)) {
                    foundMatch = true
                    break
                }
            }

            if !foundMatch {
                // Also check if the query word fuzzy-matches the entire normalized target
                // This handles cases like "blackhawk" matching "Black Hawk"
                if normalizeForComparison(target).contains(normalizeForComparison(queryWord)) {
                    continue
                }
                return false
            }
        }

        return true
    }

    // MARK: - Universal Search

    /// Searches across all job record fields for the given query string.
    /// Fetches all records and filters in-memory for multi-field OR matching.
    /// - Parameter query: The search text
    /// - Returns: Array of matching JobRecord objects sorted by jobDate descending
    func searchJobRecords(query: String) -> [FROJob] {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return [] }

        let descriptor = FetchDescriptor<FROJob>(
            sortBy: [SortDescriptor(\.jobDate, order: .reverse)]
        )

        do {
            let allRecords = try modelContext.fetch(descriptor)
            let lowerQuery = trimmed.lowercased()

            let results = allRecords.filter { record in
                record.aircraftType.localizedCaseInsensitiveContains(lowerQuery) ||
                (record.aircraftSerialNumber?.localizedCaseInsensitiveContains(lowerQuery) ?? false) ||
                (record.nNumber?.localizedCaseInsensitiveContains(lowerQuery) ?? false) ||
                record.system.localizedCaseInsensitiveContains(lowerQuery) ||
                (record.component?.localizedCaseInsensitiveContains(lowerQuery) ?? false) ||
                (record.taskDescription?.localizedCaseInsensitiveContains(lowerQuery) ?? false) ||
                (record.tmReferences?.localizedCaseInsensitiveContains(lowerQuery) ?? false) ||
                (record.notes?.localizedCaseInsensitiveContains(lowerQuery) ?? false) ||
                (record.recommendations?.localizedCaseInsensitiveContains(lowerQuery) ?? false)
            }

            print("SearchService: Found \(results.count) job records for query '\(trimmed)'")
            return results
        } catch {
            print("SearchService: Failed to search job records - \(error)")
            return []
        }
    }

    // MARK: - Filtered Search

    /// Searches job records filtered by aircraft type.
    /// - Parameter aircraftType: The aircraft type to filter by
    /// - Returns: Array of matching JobRecord objects
    func searchByAircraftType(_ aircraftType: String) -> [FROJob] {
        let searchTerm = aircraftType
        let descriptor = FetchDescriptor<FROJob>(
            sortBy: [SortDescriptor(\.jobDate, order: .reverse)]
        )

        do {
            let all = try modelContext.fetch(descriptor)
            return all.filter { $0.aircraftType.localizedCaseInsensitiveContains(searchTerm) }
        } catch {
            print("SearchService: Failed to search by aircraft type - \(error)")
            return []
        }
    }

    /// Searches job records filtered by system.
    /// - Parameter system: The system to filter by
    /// - Returns: Array of matching JobRecord objects
    func searchBySystem(_ system: String) -> [FROJob] {
        let searchTerm = system
        let descriptor = FetchDescriptor<FROJob>(
            sortBy: [SortDescriptor(\.jobDate, order: .reverse)]
        )

        do {
            let all = try modelContext.fetch(descriptor)
            return all.filter { $0.system.localizedCaseInsensitiveContains(searchTerm) }
        } catch {
            print("SearchService: Failed to search by system - \(error)")
            return []
        }
    }

    /// Searches job records filtered by TM reference.
    /// - Parameter tmReference: The TM reference to search for
    /// - Returns: Array of matching JobRecord objects
    func searchByTMReference(_ tmReference: String) -> [FROJob] {
        let searchTerm = tmReference
        let descriptor = FetchDescriptor<FROJob>(
            sortBy: [SortDescriptor(\.jobDate, order: .reverse)]
        )

        do {
            let all = try modelContext.fetch(descriptor)
            return all.filter { $0.tmReferences?.localizedCaseInsensitiveContains(searchTerm) ?? false }
        } catch {
            print("SearchService: Failed to search by TM reference - \(error)")
            return []
        }
    }

    // MARK: - Tool Search

    /// Searches tools by name or alias (case-insensitive, contains match).
    /// - Parameter query: The search text
    /// - Returns: Array of matching Tool objects (deduplicated, sorted by name)
    func searchTools(query: String) -> [FROTool] {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return [] }

        let descriptor = FetchDescriptor<FROTool>(
            sortBy: [SortDescriptor(\.name)]
        )

        do {
            let allTools = try modelContext.fetch(descriptor)
            let lowerQuery = trimmed.lowercased()

            let results = allTools.filter { tool in
                // Check name match
                if tool.name.localizedCaseInsensitiveContains(lowerQuery) {
                    return true
                }
                // Check alias match
                if let aliases = tool.aliases {
                    return aliases.contains { $0.lowercased().contains(lowerQuery) }
                }
                return false
            }

            print("SearchService: Found \(results.count) tools for query '\(trimmed)'")
            return results
        } catch {
            print("SearchService: Failed to search tools - \(error)")
            return []
        }
    }

    // MARK: - Consumable Search

    /// Searches consumables by name (case-insensitive, contains match).
    /// - Parameter query: The search text
    /// - Returns: Array of matching Consumable objects
    func searchConsumables(query: String) -> [FROConsumable] {
        let searchTerm = query
        let descriptor = FetchDescriptor<FROConsumable>(
            sortBy: [SortDescriptor(\.name)]
        )

        do {
            let all = try modelContext.fetch(descriptor)
            return all.filter { $0.name.localizedCaseInsensitiveContains(searchTerm) }
        } catch {
            print("SearchService: Failed to search consumables - \(error)")
            return []
        }
    }

    // MARK: - Chemical Search

    /// Searches chemicals by name (case-insensitive, contains match).
    /// - Parameter query: The search text
    /// - Returns: Array of matching Chemical objects
    func searchChemicals(query: String) -> [FROChemical] {
        let searchTerm = query
        let descriptor = FetchDescriptor<FROChemical>(
            sortBy: [SortDescriptor(\.name)]
        )

        do {
            let all = try modelContext.fetch(descriptor)
            return all.filter { $0.name.localizedCaseInsensitiveContains(searchTerm) }
        } catch {
            print("SearchService: Failed to search chemicals - \(error)")
            return []
        }
    }
}

import SwiftUI
import Foundation
import SwiftData

/// A TextField with autocomplete suggestions for N-numbers (tail numbers).
/// Queries JobRecord entities to show previously entered N-numbers.
/// Feature #101: N-number field autocompletes from previous entries.
struct NNumberAutocompleteField: View {
    @Environment(\.modelContext) private var viewContext

    /// Binding to the N-number text value
    @Binding var text: String

    /// Placeholder text for the field
    let placeholder: String

    /// Accessibility identifier for the text field
    let accessibilityId: String

    /// Minimum characters to trigger suggestions
    private let minCharsForSuggestions = 1

    /// Maximum number of suggestions to display
    private let maxSuggestions = 5

    /// State for showing suggestions
    @State private var showSuggestions = false

    /// Fetches all job records and extracts unique N-numbers matching input
    private var allMatchingNNumbers: [String] {
        guard text.count >= minCharsForSuggestions else { return [] }

        let descriptor = FetchDescriptor<FROJob>(
            sortBy: [SortDescriptor(\.jobDate, order: .reverse)]
        )

        do {
            let results = try viewContext.fetch(descriptor)
            let lowerText = text.lowercased()
            var seen = Set<String>()
            var unique: [String] = []
            for record in results {
                if let nNum = record.nNumber?.trimmingCharacters(in: .whitespacesAndNewlines),
                   !nNum.isEmpty,
                   nNum.lowercased().contains(lowerText) {
                    let lowercased = nNum.lowercased()
                    if !seen.contains(lowercased) {
                        seen.insert(lowercased)
                        unique.append(nNum)
                    }
                }
            }
            return unique
        } catch {
            print("NNumberAutocompleteField: Failed to fetch N-numbers - \(error)")
            return []
        }
    }

    /// Computed property for matching N-numbers (limited to maxSuggestions)
    private var matchingNNumbers: [String] {
        Array(allMatchingNNumbers.prefix(maxSuggestions))
    }

    /// Count of total matches (for "X more" indicator)
    private var totalMatchCount: Int {
        allMatchingNNumbers.count
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            // The text field
            TextField(placeholder, text: $text)
                .font(.body)
                .autocorrectionDisabled()
                .textInputAutocapitalization(.characters)  // N-numbers are typically uppercase
                .accessibilityIdentifier(accessibilityId)
                .accessibilityLabel("N-Number or Tail Number")
                .onChange(of: text) { _, newValue in
                    // Show suggestions when there's text
                    showSuggestions = newValue.count >= minCharsForSuggestions && !matchingNNumbers.isEmpty
                }

            // Suggestions dropdown
            if showSuggestions && !matchingNNumbers.isEmpty {
                VStack(alignment: .leading, spacing: 0) {
                    // Header
                    HStack(spacing: 4) {
                        Image(systemName: "clock.arrow.circlepath")
                            .font(.caption)
                            .foregroundColor(.secondary)
                        Text("Previous entries:")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .accessibilityIdentifier("nNumberSuggestionsHeader")

                    Divider()

                    // Suggestion list
                    ForEach(matchingNNumbers, id: \.self) { nNum in
                        Button(action: {
                            selectSuggestion(nNum)
                        }) {
                            HStack {
                                // Highlight matching text
                                highlightedText(nNum, searchText: text)
                                    .font(.body)
                                Spacer()
                                Image(systemName: "arrow.turn.down.left")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                            .padding(.horizontal, 12)
                            .padding(.vertical, 10)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .accessibilityIdentifier("nNumberSuggestion_\(nNum)")
                        .accessibilityLabel("Select \(nNum)")
                        .accessibilityHint("Tap to use this N-number")

                        if nNum != matchingNNumbers.last {
                            Divider()
                                .padding(.leading, 12)
                        }
                    }

                    // Show "X more" if there are additional matches
                    if totalMatchCount > maxSuggestions {
                        Divider()
                        HStack {
                            Spacer()
                            Text("+\(totalMatchCount - maxSuggestions) more matches")
                                .font(.caption)
                                .foregroundColor(.secondary)
                            Spacer()
                        }
                        .padding(.vertical, 6)
                        .accessibilityIdentifier("moreNNumberMatchesLabel")
                    }
                }
                .background(Color(UIColor.secondarySystemBackground))
                .cornerRadius(8)
                .accessibilityIdentifier("nNumberSuggestionsContainer")
            }
        }
    }

    /// Selects a suggestion and updates the text field
    private func selectSuggestion(_ nNum: String) {
        withAnimation(.easeInOut(duration: 0.15)) {
            text = nNum
            showSuggestions = false
        }
        print("NNumberAutocompleteField: Selected suggestion '\(nNum)'")
    }

    /// Creates attributed text with highlighted matching portion
    @ViewBuilder
    private func highlightedText(_ fullText: String, searchText: String) -> some View {
        let lowercasedFull = fullText.lowercased()
        let lowercasedSearch = searchText.lowercased()

        if let range = lowercasedFull.range(of: lowercasedSearch) {
            let startIndex = fullText.index(fullText.startIndex, offsetBy: lowercasedFull.distance(from: lowercasedFull.startIndex, to: range.lowerBound))
            let endIndex = fullText.index(fullText.startIndex, offsetBy: lowercasedFull.distance(from: lowercasedFull.startIndex, to: range.upperBound))

            let before = String(fullText[..<startIndex])
            let match = String(fullText[startIndex..<endIndex])
            let after = String(fullText[endIndex...])

            HStack(spacing: 0) {
                Text(before)
                    .foregroundColor(.primary)
                Text(match)
                    .foregroundColor(Color(red: 0.145, green: 0.388, blue: 0.922))
                    .fontWeight(.semibold)
                Text(after)
                    .foregroundColor(.primary)
            }
        } else {
            Text(fullText)
                .foregroundColor(.primary)
        }
    }
}

#Preview {
    struct PreviewWrapper: View {
        @State private var nNumber = ""

        var body: some View {
            Form {
                Section(header: Text("Aircraft Information")) {
                    NNumberAutocompleteField(
                        text: $nNumber,
                        placeholder: "N-Number / Tail Number",
                        accessibilityId: "nNumberField"
                    )
                }
            }
            
        }
    }

    return PreviewWrapper()
}

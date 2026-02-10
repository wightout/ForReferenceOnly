import SwiftUI
import SwiftUI
import Foundation
import SwiftData

/// A TextField with autocomplete suggestions for aircraft serial numbers.
/// Queries JobRecord entities to show previously entered serial numbers.
/// Feature #100: Serial number field autocompletes from previous entries.
struct SerialNumberAutocompleteField: View {
    @Environment(\.modelContext) private var viewContext

    /// Binding to the serial number text value
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

    /// Computed property for matching serial numbers from existing JobRecords
    private var matchingSerialNumbers: [String] {
        guard text.count >= minCharsForSuggestions else { return [] }

        // Fetch all unique serial numbers that match the current input
        let searchText = text
        let descriptor = FetchDescriptor<FROJob>(
            predicate: #Predicate { $0.aircraftSerialNumber != nil },
            sortBy: [SortDescriptor(\FROJob.jobDate, order: .reverse)]
        )

        do {
            let results = try viewContext.fetch(descriptor).filter {
                $0.aircraftSerialNumber?.localizedCaseInsensitiveContains(searchText) == true
            }
            // Get unique serial numbers, case-insensitive deduplication
            var seen = Set<String>()
            var unique: [String] = []
            for record in results {
                if let serial = record.aircraftSerialNumber?.trimmingCharacters(in: .whitespacesAndNewlines),
                   !serial.isEmpty {
                    let lowercased = serial.lowercased()
                    if !seen.contains(lowercased) {
                        seen.insert(lowercased)
                        unique.append(serial)
                        if unique.count >= maxSuggestions {
                            break
                        }
                    }
                }
            }
            return unique
        } catch {
            print("SerialNumberAutocompleteField: Failed to fetch serial numbers - \(error)")
            return []
        }
    }

    /// Count of total matches (for "X more" indicator)
    private var totalMatchCount: Int {
        guard text.count >= minCharsForSuggestions else { return 0 }

        let searchText2 = text
        let countDescriptor = FetchDescriptor<FROJob>(
            predicate: #Predicate { $0.aircraftSerialNumber != nil }
        )

        do {
            let results = try viewContext.fetch(countDescriptor).filter {
                $0.aircraftSerialNumber?.localizedCaseInsensitiveContains(searchText2) == true
            }
            // Count unique serial numbers
            var seen = Set<String>()
            for record in results {
                if let serial = record.aircraftSerialNumber?.lowercased() {
                    seen.insert(serial)
                }
            }
            return seen.count
        } catch {
            return 0
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            // The text field
            TextField(placeholder, text: $text)
                .font(.body)
                .autocorrectionDisabled()
                .textInputAutocapitalization(.characters)  // Serial numbers are typically uppercase
                .accessibilityIdentifier(accessibilityId)
                .accessibilityLabel("Aircraft Serial Number")
                .onChange(of: text) { _, newValue in
                    // Show suggestions when there's text
                    showSuggestions = newValue.count >= minCharsForSuggestions && !matchingSerialNumbers.isEmpty
                }

            // Suggestions dropdown
            if showSuggestions && !matchingSerialNumbers.isEmpty {
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
                    .accessibilityIdentifier("serialNumberSuggestionsHeader")

                    Divider()

                    // Suggestion list
                    ForEach(matchingSerialNumbers, id: \.self) { serial in
                        Button(action: {
                            selectSuggestion(serial)
                        }) {
                            HStack {
                                // Highlight matching text
                                highlightedText(serial, searchText: text)
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
                        .accessibilityIdentifier("serialSuggestion_\(serial)")
                        .accessibilityLabel("Select \(serial)")
                        .accessibilityHint("Tap to use this serial number")

                        if serial != matchingSerialNumbers.last {
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
                        .accessibilityIdentifier("moreSerialMatchesLabel")
                    }
                }
                .background(Color(UIColor.secondarySystemBackground))
                .cornerRadius(8)
                .accessibilityIdentifier("serialNumberSuggestionsContainer")
            }
        }
    }

    /// Selects a suggestion and updates the text field
    private func selectSuggestion(_ serial: String) {
        withAnimation(.easeInOut(duration: 0.15)) {
            text = serial
            showSuggestions = false
        }
        print("SerialNumberAutocompleteField: Selected suggestion '\(serial)'")
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
        @State private var serialNumber = ""

        var body: some View {
            Form {
                Section(header: Text("Aircraft Information")) {
                    SerialNumberAutocompleteField(
                        text: $serialNumber,
                        placeholder: "Serial Number",
                        accessibilityId: "serialNumberField"
                    )
                }
            }
            .modelContainer(for: [FROTool.self, FROJob.self, FROToolGroup.self, FROToolKit.self, FROConsumable.self, FROChemical.self, FROPart.self], inMemory: true)
        }
    }

    return PreviewWrapper()
}

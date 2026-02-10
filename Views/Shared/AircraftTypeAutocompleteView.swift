import SwiftUI
import Foundation
import SwiftData

/// A reusable autocomplete text field for aircraft type entry.
/// Shows suggestions based on previously entered aircraft types from job records.
/// Helps maintain consistency (e.g., always 'UH-60' not sometimes 'UH60').
///
/// Feature #99: Aircraft type field autocompletes from previous entries
struct AircraftTypeAutocompleteView: View {
    @Environment(\.modelContext) private var viewContext

    /// Binding to the aircraft type text field value
    @Binding var aircraftType: String

    /// Placeholder text for the field
    var placeholder: String = "Aircraft Type (required)"

    /// Accessibility identifier prefix (used to differentiate new job vs edit job)
    var accessibilityPrefix: String = ""

    /// Fetch all job records to extract unique aircraft types
    @Query(sort: \FROJob.aircraftType, order: .forward)
    private var allJobs: [FROJob]

    /// Computed property returning all unique aircraft types from existing job records
    private var allAircraftTypes: [String] {
        let types = allJobs.compactMap { $0.aircraftType }.filter { !$0.isEmpty }
        let uniqueTypes = Set(types)
        return uniqueTypes.sorted { $0.localizedCaseInsensitiveCompare($1) == .orderedAscending }
    }

    /// Build accessibility identifier with optional prefix
    private func accessibilityId(_ suffix: String) -> String {
        if accessibilityPrefix.isEmpty {
            return suffix
        } else {
            return "\(accessibilityPrefix)\(suffix)"
        }
    }

    /// Computed property returning matching aircraft types based on user input.
    /// Uses case-insensitive prefix matching for better UX.
    private var matchingAircraftTypes: [String] {
        let trimmedInput = aircraftType.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmedInput.count >= 1 else { return [] }

        let lowercasedInput = trimmedInput.lowercased()
        return allAircraftTypes.filter { type in
            type.lowercased().contains(lowercasedInput)
        }
    }

    /// Whether to show the suggestions dropdown
    private var showSuggestions: Bool {
        let trimmedInput = aircraftType.trimmingCharacters(in: .whitespacesAndNewlines)
        // Show suggestions when:
        // 1. Input has at least 1 character
        // 2. There are matching suggestions
        // 3. The current value is not an exact match (so user isn't just viewing what they already selected)
        guard trimmedInput.count >= 1 else { return false }
        guard !matchingAircraftTypes.isEmpty else { return false }

        // Don't show suggestions if the only match is exactly what the user typed
        if matchingAircraftTypes.count == 1 && matchingAircraftTypes[0].lowercased() == trimmedInput.lowercased() {
            return false
        }

        return true
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            // Aircraft Type TextField
            TextField(placeholder, text: $aircraftType)
                .font(.body)
                .autocorrectionDisabled()
                .textInputAutocapitalization(.characters) // Aircraft types are typically uppercase
                .accessibilityIdentifier(accessibilityId("AircraftTypeField"))
                .accessibilityLabel("Aircraft Type, required field")

            // MARK: - Autocomplete Suggestions
            if showSuggestions {
                VStack(alignment: .leading, spacing: 0) {
                    // Suggestions header
                    HStack(spacing: 6) {
                        Image(systemName: "airplane")
                            .font(.caption)
                            .foregroundColor(Color(red: 0.145, green: 0.388, blue: 0.922))
                        Text("Previous aircraft types:")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    .padding(.horizontal, 12)
                    .padding(.top, 8)
                    .padding(.bottom, 4)
                    .accessibilityIdentifier(accessibilityId("AircraftTypeSuggestionsHeader"))

                    // Suggestion rows (limit to 5)
                    ForEach(matchingAircraftTypes.prefix(5), id: \.self) { suggestion in
                        Button(action: {
                            selectSuggestion(suggestion)
                        }) {
                            HStack(spacing: 10) {
                                Text(suggestion)
                                    .font(.subheadline)
                                    .fontWeight(.medium)
                                    .foregroundColor(.primary)

                                Spacer()

                                // Tap indicator
                                Image(systemName: "arrow.up.left")
                                    .font(.caption)
                                    .foregroundColor(Color(red: 0.145, green: 0.388, blue: 0.922))
                            }
                            .padding(.horizontal, 12)
                            .padding(.vertical, 10)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .accessibilityIdentifier(accessibilityId("AircraftTypeSuggestion_\(suggestion)"))
                        .accessibilityLabel("Select \(suggestion)")
                        .accessibilityHint("Fills the aircraft type field with \(suggestion)")

                        // Divider between suggestions
                        if suggestion != matchingAircraftTypes.prefix(5).last {
                            Divider()
                                .padding(.leading, 12)
                        }
                    }

                    // Show count if there are more matches
                    if matchingAircraftTypes.count > 5 {
                        Text("+ \(matchingAircraftTypes.count - 5) more")
                            .font(.caption2)
                            .foregroundColor(.secondary)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 6)
                            .accessibilityIdentifier(accessibilityId("AircraftTypeMoreMatchesLabel"))
                    }
                }
                .background(Color(UIColor.secondarySystemBackground))
                .cornerRadius(8)
                .accessibilityIdentifier(accessibilityId("AircraftTypeSuggestionsContainer"))
            }
        }
    }

    // MARK: - Actions

    /// Selects a suggestion and populates the text field
    private func selectSuggestion(_ suggestion: String) {
        withAnimation(.easeInOut(duration: 0.15)) {
            aircraftType = suggestion
        }
        print("AircraftTypeAutocomplete: Selected '\(suggestion)' from suggestions")
    }
}

#Preview {
    struct PreviewWrapper: View {
        @State private var aircraftType = ""

        var body: some View {
            Form {
                Section(header: Text("Aircraft Information")) {
                    AircraftTypeAutocompleteView(
                        aircraftType: $aircraftType,
                        placeholder: "Aircraft Type (required)"
                    )
                }
            }
        }
    }

    return PreviewWrapper()
        
}

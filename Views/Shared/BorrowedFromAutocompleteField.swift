import SwiftUI
import Foundation
import SwiftData

/// A reusable autocomplete text field for the "borrowed from" field.
/// Shows suggestions based on previously entered names from borrowed tools.
/// Helps maintain consistency in tracking who tools are borrowed from.
///
/// Feature #104: Borrowed from field autocompletes from previous entries
struct BorrowedFromAutocompleteField: View {
    @Environment(\.modelContext) private var viewContext

    /// Binding to the borrowed from text field value
    @Binding var borrowedFrom: String

    /// Placeholder text for the field
    var placeholder: String = "Borrowed from..."

    /// Accessibility identifier prefix (used to differentiate different usages)
    var accessibilityPrefix: String = ""

    /// Fetch all tools that have borrowedFrom values to extract unique names
    @Query(filter: #Predicate<FROTool> { $0.borrowedFrom != nil }, sort: \FROTool.borrowedFrom, order: .forward)
    private var borrowedTools: [FROTool]

    /// Computed property returning all unique borrowedFrom values from existing tools
    private var allBorrowedFromNames: [String] {
        let names = borrowedTools.compactMap { $0.borrowedFrom }
        let uniqueNames = Set(names)
        return uniqueNames.sorted { $0.localizedCaseInsensitiveCompare($1) == .orderedAscending }
    }

    /// Computed property returning matching names based on user input.
    /// Uses case-insensitive contains matching for better UX.
    private var matchingNames: [String] {
        let trimmedInput = borrowedFrom.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmedInput.count >= 1 else { return [] }

        let lowercasedInput = trimmedInput.lowercased()
        return allBorrowedFromNames.filter { name in
            name.lowercased().contains(lowercasedInput)
        }
    }

    /// Whether to show the suggestions dropdown
    private var showSuggestions: Bool {
        let trimmedInput = borrowedFrom.trimmingCharacters(in: .whitespacesAndNewlines)
        // Show suggestions when:
        // 1. Input has at least 1 character
        // 2. There are matching suggestions
        // 3. The current value is not an exact match (so user isn't just viewing what they already selected)
        guard trimmedInput.count >= 1 else { return false }
        guard !matchingNames.isEmpty else { return false }

        // Don't show suggestions if the only match is exactly what the user typed
        if matchingNames.count == 1 && matchingNames[0].lowercased() == trimmedInput.lowercased() {
            return false
        }

        return true
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            // Borrowed From TextField
            TextField(placeholder, text: $borrowedFrom)
                .font(.body)
                .autocorrectionDisabled()
                .accessibilityIdentifier("\(accessibilityPrefix)borrowedFromField")
                .accessibilityLabel("Borrowed from")
                .accessibilityHint("Enter the name of the person or place you borrowed this tool from")

            // MARK: - Autocomplete Suggestions
            if showSuggestions {
                VStack(alignment: .leading, spacing: 0) {
                    // Suggestions header
                    HStack(spacing: 6) {
                        Image(systemName: "person.2.fill")
                            .font(.caption)
                            .foregroundColor(Color(red: 0.976, green: 0.451, blue: 0.086)) // Safety orange for borrowed
                        Text("Previous sources:")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    .padding(.horizontal, 12)
                    .padding(.top, 8)
                    .padding(.bottom, 4)
                    .accessibilityIdentifier("\(accessibilityPrefix)borrowedFromSuggestionsHeader")

                    // Suggestion rows (limit to 5)
                    ForEach(matchingNames.prefix(5), id: \.self) { suggestion in
                        Button(action: {
                            selectSuggestion(suggestion)
                        }) {
                            HStack(spacing: 10) {
                                Image(systemName: "person.fill")
                                    .font(.caption)
                                    .foregroundColor(.secondary)

                                Text(suggestion)
                                    .font(.subheadline)
                                    .fontWeight(.medium)
                                    .foregroundColor(.primary)

                                Spacer()

                                // Tap indicator
                                Image(systemName: "arrow.up.left")
                                    .font(.caption)
                                    .foregroundColor(Color(red: 0.976, green: 0.451, blue: 0.086))
                            }
                            .padding(.horizontal, 12)
                            .padding(.vertical, 10)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .accessibilityIdentifier("\(accessibilityPrefix)borrowedFromSuggestion_\(suggestion)")
                        .accessibilityLabel("Select \(suggestion)")
                        .accessibilityHint("Fills the borrowed from field with \(suggestion)")

                        // Divider between suggestions
                        if suggestion != matchingNames.prefix(5).last {
                            Divider()
                                .padding(.leading, 12)
                        }
                    }

                    // Show count if there are more matches
                    if matchingNames.count > 5 {
                        Text("+ \(matchingNames.count - 5) more")
                            .font(.caption2)
                            .foregroundColor(.secondary)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 6)
                            .accessibilityIdentifier("\(accessibilityPrefix)borrowedFromMoreMatchesLabel")
                    }
                }
                .background(Color(UIColor.secondarySystemBackground))
                .cornerRadius(8)
                .accessibilityIdentifier("\(accessibilityPrefix)borrowedFromSuggestionsContainer")
            }
        }
    }

    // MARK: - Actions

    /// Selects a suggestion and populates the text field
    private func selectSuggestion(_ suggestion: String) {
        withAnimation(.easeInOut(duration: 0.15)) {
            borrowedFrom = suggestion
        }
        print("BorrowedFromAutocomplete: Selected '\(suggestion)' from suggestions")
    }
}

#Preview {
    struct PreviewWrapper: View {
        @State private var borrowedFrom = ""

        var body: some View {
            Form {
                Section(header: Text("Ownership")) {
                    Picker("Type", selection: .constant("borrowed")) {
                        Text("Personal").tag("personal")
                        Text("Shop").tag("shop")
                        Text("Borrowed").tag("borrowed")
                    }
                    .pickerStyle(.segmented)

                    BorrowedFromAutocompleteField(
                        borrowedFrom: $borrowedFrom,
                        placeholder: "Borrowed from..."
                    )
                }
            }
        }
    }

    return PreviewWrapper()
        .modelContainer(for: [FROTool.self, FROJob.self, FROToolGroup.self, FROToolKit.self, FROConsumable.self, FROChemical.self, FROPart.self], inMemory: true)
}

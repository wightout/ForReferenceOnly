import SwiftUI
import Foundation
import SwiftData

/// A reusable autocomplete text field for component entry.
/// Shows suggestions based on previously entered components from job records.
/// Helps maintain consistency and speeds up entry for repeat work on the same components.
///
/// Feature #103: Component field autocompletes from previous entries
struct ComponentAutocompleteField: View {
    @Environment(\.modelContext) private var viewContext

    /// Binding to the component text field value
    @Binding var text: String

    /// Placeholder text for the field
    var placeholder: String = "Component"

    /// Accessibility identifier for the text field
    var accessibilityId: String = "componentField"

    /// Fetch all job records to extract unique components
    @Query(sort: \FROJob.component, order: .forward)
    private var allJobs: [FROJob]

    /// Computed property returning all unique components from existing job records
    private var allComponents: [String] {
        let components = allJobs.compactMap { $0.component }.filter { !$0.isEmpty }
        let uniqueComponents = Set(components)
        return uniqueComponents.sorted { $0.localizedCaseInsensitiveCompare($1) == .orderedAscending }
    }

    /// Computed property returning matching components based on user input.
    /// Uses case-insensitive contains matching for better UX.
    private var matchingComponents: [String] {
        let trimmedInput = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmedInput.count >= 1 else { return [] }

        let lowercasedInput = trimmedInput.lowercased()
        return allComponents.filter { component in
            component.lowercased().contains(lowercasedInput)
        }
    }

    /// Whether to show the suggestions dropdown
    private var showSuggestions: Bool {
        let trimmedInput = text.trimmingCharacters(in: .whitespacesAndNewlines)
        // Show suggestions when:
        // 1. Input has at least 1 character
        // 2. There are matching suggestions
        // 3. The current value is not an exact match (so user isn't just viewing what they already selected)
        guard trimmedInput.count >= 1 else { return false }
        guard !matchingComponents.isEmpty else { return false }

        // Don't show suggestions if the only match is exactly what the user typed
        if matchingComponents.count == 1 && matchingComponents[0].lowercased() == trimmedInput.lowercased() {
            return false
        }

        return true
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            // Component TextField
            TextField(placeholder, text: $text)
                .font(.body)
                .autocorrectionDisabled()
                .accessibilityIdentifier(accessibilityId)
                .accessibilityLabel("Component")

            // MARK: - Autocomplete Suggestions
            if showSuggestions {
                VStack(alignment: .leading, spacing: 0) {
                    // Suggestions header
                    HStack(spacing: 6) {
                        Image(systemName: "gearshape.2")
                            .font(.caption)
                            .foregroundColor(Color(red: 0.145, green: 0.388, blue: 0.922))
                        Text("Previous components:")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    .padding(.horizontal, 12)
                    .padding(.top, 8)
                    .padding(.bottom, 4)
                    .accessibilityIdentifier("\(accessibilityId)SuggestionsHeader")

                    // Suggestion rows (limit to 5)
                    ForEach(matchingComponents.prefix(5), id: \.self) { suggestion in
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
                        .accessibilityIdentifier("\(accessibilityId)Suggestion_\(suggestion)")
                        .accessibilityLabel("Select \(suggestion)")
                        .accessibilityHint("Fills the component field with \(suggestion)")

                        // Divider between suggestions
                        if suggestion != matchingComponents.prefix(5).last {
                            Divider()
                                .padding(.leading, 12)
                        }
                    }

                    // Show count if there are more matches
                    if matchingComponents.count > 5 {
                        Text("+ \(matchingComponents.count - 5) more")
                            .font(.caption2)
                            .foregroundColor(.secondary)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 6)
                            .accessibilityIdentifier("\(accessibilityId)MoreMatchesLabel")
                    }
                }
                .background(Color(UIColor.secondarySystemBackground))
                .cornerRadius(8)
                .accessibilityIdentifier("\(accessibilityId)SuggestionsContainer")
            }
        }
    }

    // MARK: - Actions

    /// Selects a suggestion and populates the text field
    private func selectSuggestion(_ suggestion: String) {
        withAnimation(.easeInOut(duration: 0.15)) {
            text = suggestion
        }
        print("ComponentAutocomplete: Selected '\(suggestion)' from suggestions")
    }
}

private struct ComponentAutocompleteFieldPreview: View {
    @State private var component = ""

    var body: some View {
        Form {
            Section(header: Text("System & Component")) {
                ComponentAutocompleteField(
                    text: $component,
                    placeholder: "Component"
                )
            }
        }
        
    }
}

#Preview {
    ComponentAutocompleteFieldPreview()
}

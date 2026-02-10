import SwiftUI
import Foundation
import SwiftData

/// A reusable autocomplete text field for toolkit name entry.
/// Shows suggestions based on existing toolkit names to help avoid duplicates
/// and maintain naming consistency.
///
/// Feature #106: Toolkit name field autocompletes from existing toolkits
struct ToolKitNameAutocompleteField: View {
    @Environment(\.modelContext) private var viewContext

    /// Binding to the toolkit name text field value
    @Binding var text: String

    /// Placeholder text for the field
    var placeholder: String = "e.g., Hydraulic Pump R&R Kit"

    /// Accessibility identifier for the text field
    var accessibilityId: String = "toolKitNameField"

    /// Fetch all tool kits to extract existing names
    @Query(sort: \FROToolKit.name, order: .forward)
    private var allToolKits: [FROToolKit]

    /// Design system colors
    private let kitColor = Color(red: 0.133, green: 0.545, blue: 0.133) // Green (matches ToolKit styling)
    private let warningOrange = Color(red: 0.976, green: 0.451, blue: 0.086) // Safety orange

    /// Computed property returning all existing toolkit names
    private var existingToolKitNames: [String] {
        let names = allToolKits.compactMap { $0.name }.filter { !$0.isEmpty }
        return names.sorted { $0.localizedCaseInsensitiveCompare($1) == .orderedAscending }
    }

    /// Computed property returning matching toolkit names based on user input.
    /// Uses case-insensitive contains matching for better UX.
    private var matchingNames: [String] {
        let trimmedInput = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmedInput.count >= 1 else { return [] }

        let lowercasedInput = trimmedInput.lowercased()
        return existingToolKitNames.filter { name in
            name.lowercased().contains(lowercasedInput)
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
        guard !matchingNames.isEmpty else { return false }

        // Don't show suggestions if the only match is exactly what the user typed
        if matchingNames.count == 1 && matchingNames[0].lowercased() == trimmedInput.lowercased() {
            return false
        }

        return true
    }

    /// Check if the current input is an exact match to an existing toolkit name
    private var isExactMatch: Bool {
        let trimmedInput = text.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return existingToolKitNames.contains { $0.lowercased() == trimmedInput }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            // ToolKit Name TextField
            TextField(placeholder, text: $text)
                .font(.body)
                .autocorrectionDisabled()
                .accessibilityIdentifier(accessibilityId)
                .accessibilityLabel("Toolkit name")

            // MARK: - Exact match warning
            if isExactMatch {
                HStack(spacing: 6) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .font(.caption)
                        .foregroundColor(warningOrange)
                    Text("A toolkit with this exact name already exists")
                        .font(.caption)
                        .foregroundColor(warningOrange)
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(warningOrange.opacity(0.1))
                .cornerRadius(6)
                .accessibilityIdentifier("\(accessibilityId)ExactMatchWarning")
            }

            // MARK: - Autocomplete Suggestions
            if showSuggestions {
                VStack(alignment: .leading, spacing: 0) {
                    // Suggestions header with warning tone
                    HStack(spacing: 6) {
                        Image(systemName: "exclamationmark.circle")
                            .font(.caption)
                            .foregroundColor(warningOrange)
                        Text("Similar toolkits exist:")
                            .font(.caption)
                            .foregroundColor(warningOrange)
                    }
                    .padding(.horizontal, 12)
                    .padding(.top, 8)
                    .padding(.bottom, 4)
                    .accessibilityIdentifier("\(accessibilityId)SuggestionsHeader")

                    // Suggestion rows (limit to 5)
                    ForEach(matchingNames.prefix(5), id: \.self) { suggestion in
                        Button(action: {
                            selectSuggestion(suggestion)
                        }) {
                            HStack(spacing: 10) {
                                Image(systemName: "bag.fill")
                                    .font(.caption)
                                    .foregroundColor(kitColor)

                                Text(suggestion)
                                    .font(.subheadline)
                                    .fontWeight(.medium)
                                    .foregroundColor(.primary)

                                Spacer()

                                // Tap indicator - copy to field
                                Image(systemName: "arrow.up.left")
                                    .font(.caption)
                                    .foregroundColor(kitColor)
                            }
                            .padding(.horizontal, 12)
                            .padding(.vertical, 10)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .accessibilityIdentifier("\(accessibilityId)Suggestion_\(suggestion.replacingOccurrences(of: " ", with: "_"))")
                        .accessibilityLabel("Existing toolkit: \(suggestion)")
                        .accessibilityHint("Tap to use this name")

                        // Divider between suggestions
                        if suggestion != matchingNames.prefix(5).last {
                            Divider()
                                .padding(.leading, 12)
                        }
                    }

                    // Show count if there are more matches
                    if matchingNames.count > 5 {
                        Text("+ \(matchingNames.count - 5) more similar kits")
                            .font(.caption2)
                            .foregroundColor(.secondary)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 6)
                            .accessibilityIdentifier("\(accessibilityId)MoreMatchesLabel")
                    }

                    // Helpful tip
                    HStack(spacing: 6) {
                        Image(systemName: "lightbulb.fill")
                            .font(.caption2)
                            .foregroundColor(.secondary)
                        Text("Tip: Use a unique name to avoid confusion")
                            .font(.caption2)
                            .foregroundColor(.secondary)
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .accessibilityIdentifier("\(accessibilityId)Tip")
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
        print("ToolKitNameAutocomplete: Selected '\(suggestion)' from suggestions")
    }
}

#Preview {
    struct PreviewWrapper: View {
        @State private var kitName = ""

        var body: some View {
            NavigationStack {
                Form {
                    Section(header: Text("Kit Name")) {
                        ToolKitNameAutocompleteField(
                            text: $kitName,
                            placeholder: "e.g., Hydraulic Pump R&R Kit"
                        )
                    }
                }
                .navigationTitle("Create Tool Kit")
            }
        }
    }

    return PreviewWrapper()
        .modelContainer(for: [FROTool.self, FROJob.self, FROToolGroup.self, FROToolKit.self, FROConsumable.self, FROChemical.self, FROPart.self], inMemory: true)
}

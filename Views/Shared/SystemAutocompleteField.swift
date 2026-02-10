import SwiftUI
import Foundation
import SwiftData

/// A reusable autocomplete text field for system entry.
/// Shows suggestions based on:
/// 1. Previously entered systems from job records (user's history)
/// 2. Common system options as defaults
/// Helps maintain consistency (e.g., always 'Hydraulics' not sometimes 'Hydraulic System').
///
/// Feature #102: System field autocompletes from previous entries
struct SystemAutocompleteField: View {
    @Environment(\.modelContext) private var viewContext

    /// Binding to the system text field value
    @Binding var text: String

    /// Placeholder text for the field
    var placeholder: String = "System (required)"

    /// Accessibility identifier for the text field
    var accessibilityId: String = "systemField"

    /// ATA 100 chapter codes — standardized aircraft maintenance documentation numbering.
    /// Triple-checked against Jet Parts Engineering, Aviation Maintenance Jobs, and SKYbrary sources.
    /// Format: "ATA XX — Name" so mechanics can search by number OR name.
    private let defaultSystems = [
        // General / Administrative (ATA 00–19)
        "ATA 05 — Time Limits/Maintenance Checks",
        "ATA 06 — Dimensions and Areas",
        "ATA 07 — Lifting and Shoring",
        "ATA 08 — Leveling and Weighing",
        "ATA 09 — Towing and Taxiing",
        "ATA 10 — Parking, Mooring, Storage, and Return to Service",
        "ATA 11 — Placards and Markings",
        "ATA 12 — Servicing",
        "ATA 18 — Vibration and Noise Analysis (Helicopter)",
        // Aircraft Systems (ATA 20–49)
        "ATA 20 — Standard Practices - Airframe",
        "ATA 21 — Air Conditioning and Pressurization",
        "ATA 22 — Auto Flight",
        "ATA 23 — Communications",
        "ATA 24 — Electrical Power",
        "ATA 25 — Equipment/Furnishings",
        "ATA 26 — Fire Protection",
        "ATA 27 — Flight Controls",
        "ATA 28 — Fuel",
        "ATA 29 — Hydraulic Power",
        "ATA 30 — Ice and Rain Protection",
        "ATA 31 — Indicating/Recording System",
        "ATA 32 — Landing Gear",
        "ATA 33 — Lights",
        "ATA 34 — Navigation",
        "ATA 35 — Oxygen",
        "ATA 36 — Pneumatic",
        "ATA 37 — Vacuum",
        "ATA 38 — Water/Waste",
        "ATA 39 — Electrical - Electronic Panels and Multipurpose Components",
        "ATA 40 — Multisystem",
        "ATA 41 — Water Ballast",
        "ATA 42 — Integrated Modular Avionics",
        "ATA 44 — Cabin Systems",
        "ATA 45 — Central Maintenance System (CMS)",
        "ATA 46 — Information Systems",
        "ATA 47 — Inert Gas System",
        "ATA 49 — Airborne Auxiliary Power Unit",
        "ATA 50 — Cargo and Accessory Compartments",
        // Structures (ATA 51–57)
        "ATA 51 — Standard Practices and Structures - General",
        "ATA 52 — Doors",
        "ATA 53 — Fuselage",
        "ATA 54 — Nacelles/Pylons",
        "ATA 55 — Stabilizers",
        "ATA 56 — Windows",
        "ATA 57 — Wings",
        // Propeller/Rotor (ATA 60–67)
        "ATA 60 — Standard Practices - Propeller/Rotor",
        "ATA 61 — Propellers/Propulsors",
        "ATA 62 — Main Rotor(s)",
        "ATA 63 — Main Rotor Drive(s)",
        "ATA 64 — Tail Rotor",
        "ATA 65 — Tail Rotor Drive",
        "ATA 66 — Folding Blades/Pylon",
        "ATA 67 — Rotors and Flight Controls",
        // Power Plant (ATA 70–85)
        "ATA 70 — Standard Practices - Engine",
        "ATA 71 — Power Plant",
        "ATA 72 — Engine",
        "ATA 73 — Engine Fuel and Control",
        "ATA 74 — Ignition",
        "ATA 75 — Bleed Air",
        "ATA 76 — Engine Controls",
        "ATA 77 — Engine Indicating",
        "ATA 78 — Exhaust",
        "ATA 79 — Oil",
        "ATA 80 — Starting",
        "ATA 81 — Turbines",
        "ATA 82 — Water Injection",
        "ATA 83 — Accessory Gearboxes",
        "ATA 84 — Propulsion Augmentation",
        "ATA 85 — Fuel Cell Systems"
    ]

    /// Fetch all job records to extract unique systems
    @Query(sort: \FROJob.system, order: .forward)
    private var allJobs: [FROJob]

    /// Computed property returning all unique systems from existing job records,
    /// merged with default options and sorted alphabetically.
    private var allSystems: [String] {
        // Get unique systems from job history
        let historySystems = allJobs.compactMap { $0.system }.filter { !$0.isEmpty }

        // Merge with defaults and get unique values
        var allUniqueSystems = Set(historySystems)
        allUniqueSystems.formUnion(defaultSystems)

        return allUniqueSystems.sorted { $0.localizedCaseInsensitiveCompare($1) == .orderedAscending }
    }

    /// Computed property returning matching systems based on user input.
    /// Uses case-insensitive contains matching for better UX.
    private var matchingSystems: [String] {
        let trimmedInput = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmedInput.count >= 1 else { return [] }

        let lowercasedInput = trimmedInput.lowercased()
        return allSystems.filter { system in
            system.lowercased().contains(lowercasedInput)
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
        guard !matchingSystems.isEmpty else { return false }

        // Don't show suggestions if the only match is exactly what the user typed
        if matchingSystems.count == 1 && matchingSystems[0].lowercased() == trimmedInput.lowercased() {
            return false
        }

        return true
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            // System TextField
            TextField(placeholder, text: $text)
                .font(.body)
                .autocorrectionDisabled()
                .accessibilityIdentifier(accessibilityId)
                .accessibilityLabel("System, required field")
                .accessibilityHint("Enter the aircraft system being worked on")

            // MARK: - Autocomplete Suggestions
            if showSuggestions {
                VStack(alignment: .leading, spacing: 0) {
                    // Suggestions header
                    HStack(spacing: 6) {
                        Image(systemName: "gearshape.fill")
                            .font(.caption)
                            .foregroundColor(Color(red: 0.145, green: 0.388, blue: 0.922))
                        Text("Previous systems:")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    .padding(.horizontal, 12)
                    .padding(.top, 8)
                    .padding(.bottom, 4)
                    .accessibilityIdentifier("\(accessibilityId)SuggestionsHeader")

                    // Suggestion rows (limit to 5)
                    ForEach(matchingSystems.prefix(5), id: \.self) { suggestion in
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
                        .accessibilityHint("Fills the system field with \(suggestion)")

                        // Divider between suggestions
                        if suggestion != matchingSystems.prefix(5).last {
                            Divider()
                                .padding(.leading, 12)
                        }
                    }

                    // Show count if there are more matches
                    if matchingSystems.count > 5 {
                        Text("+ \(matchingSystems.count - 5) more")
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
        print("SystemAutocomplete: Selected '\(suggestion)' from suggestions")
    }
}

private struct SystemAutocompleteFieldPreview: View {
    @State private var system = ""

    var body: some View {
        Form {
            Section(header: Text("System & Component")) {
                SystemAutocompleteField(
                    text: $system,
                    placeholder: "System (required)"
                )
            }
        }
        
    }
}

#Preview {
    SystemAutocompleteFieldPreview()
}

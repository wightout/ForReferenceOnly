import SwiftUI
import Foundation
import SwiftData

/// Universal search view with search bar, filter area, and fuzzy/typo-tolerant matching.
struct SearchView: View {
    @Environment(\.modelContext) private var viewContext

    @State private var searchText: String = ""
    @State private var selectedFilter: SearchFilter = .all
    @State private var selectedAircraftType: String? = nil
    @State private var showingAircraftPicker: Bool = false

    /// SearchService instance for fuzzy matching utilities
    private let searchService = SearchService()

    enum SearchFilter: String, CaseIterable {
        case all = "All"
        case aircraftType = "Aircraft"
        case system = "System"
        case component = "Component"
        case tool = "Tool"
        case consumable = "Consumable"
        case tmReference = "TM Ref"
    }

    /// Fetch job records for search results
    /// Feature #74: Sort by jobDate for correct date boundary sorting
    @Query(sort: \FROJob.jobDate, order: .reverse)
    private var allJobRecords: [FROJob]

    /// Fetch all tools for tool/alias search
    @Query(sort: \FROTool.name, order: .forward)
    private var allTools: [FROTool]

    /// Unique aircraft types from all job records (for filter dropdown)
    private var availableAircraftTypes: [String] {
        let types = allJobRecords.map { $0.aircraftType }
        return Array(Set(types)).sorted()
    }

    /// Tools matching the search query (by name or alias) with fuzzy matching
    /// Feature #90: Results sorted by size (smallest first, inch before metric, no-size last)
    private var filteredTools: [Tool] {
        guard !searchText.isEmpty else { return [] }
        return allTools.filter { tool in
            // Fuzzy match by name
            if searchService.fuzzyMatches(query: searchText, target: tool.name) {
                return true
            }
            // Fuzzy match by alias
            if let aliases = tool.aliases {
                if aliases.contains(where: { searchService.fuzzyMatches(query: searchText, target: $0) }) {
                    return true
                }
            }
            return false
        }.sortedBySize()
    }

    /// Jobs filtered by aircraft type selection (independent of search text)
    private var aircraftFilteredRecords: [JobRecord] {
        guard let aircraftType = selectedAircraftType else {
            return Array(allJobRecords)
        }
        return allJobRecords.filter { job in
            job.aircraftType.lowercased() == aircraftType.lowercased()
        }
    }

    private var filteredRecords: [JobRecord] {
        // If search text is empty but aircraft filter is active, show aircraft-filtered results
        if searchText.isEmpty {
            if selectedAircraftType != nil {
                return aircraftFilteredRecords
            }
            return []
        }

        // Start with aircraft-filtered records (or all records if no aircraft filter)
        let baseRecords = selectedAircraftType != nil ? aircraftFilteredRecords : Array(allJobRecords)

        return baseRecords.filter { job in
            switch selectedFilter {
            case .all:
                return fuzzyMatchesAny(job: job, query: searchText)
            case .aircraftType:
                return searchService.fuzzyMatches(query: searchText, target: job.aircraftType)
            case .system:
                return searchService.fuzzyMatches(query: searchText, target: job.system)
            case .component:
                return searchService.fuzzyMatches(query: searchText, target: job.component ?? "")
            case .tool:
                // Fuzzy search by linked tools (name or alias) in this job record
                return jobContainsToolFuzzy(job: job, query: searchText)
            case .consumable:
                // Fuzzy search by linked consumables in this job record
                return jobContainsConsumableFuzzy(job: job, query: searchText)
            case .tmReference:
                return searchService.fuzzyMatches(query: searchText, target: job.tmReferences ?? "")
            }
        }
    }

    /// Check if job has a linked tool matching the query (by name or alias) with fuzzy matching
    private func jobContainsToolFuzzy(job: JobRecord, query: String) -> Bool {
        guard let tools = job.tools else { return false }
        return tools.contains { tool in
            // Fuzzy match by name
            if searchService.fuzzyMatches(query: query, target: tool.name) {
                return true
            }
            // Fuzzy match by alias
            if let aliases = tool.aliases {
                if aliases.contains(where: { searchService.fuzzyMatches(query: query, target: $0) }) {
                    return true
                }
            }
            return false
        }
    }

    /// Check if job has a linked consumable matching the query (by name) with fuzzy matching
    private func jobContainsConsumableFuzzy(job: JobRecord, query: String) -> Bool {
        guard let consumables = job.consumables else { return false }
        return consumables.contains { consumable in
            searchService.fuzzyMatches(query: query, target: consumable.name)
        }
    }

    /// Check if results should be shown (either search text or aircraft filter active)
    private var hasActiveFilter: Bool {
        !searchText.isEmpty || selectedAircraftType != nil
    }

    /// Fuzzy match across all job record fields
    private func fuzzyMatchesAny(job: JobRecord, query: String) -> Bool {
        let fields = [
            job.aircraftType,
            job.aircraftSerialNumber,
            job.nNumber,
            job.system,
            job.component,
            job.taskDescription,
            job.tmReferences,
            job.notes,
            job.recommendations
        ]
        return fields.compactMap { $0 }.contains { searchService.fuzzyMatches(query: query, target: $0) }
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                // FRO Banner
                Text("FOR REFERENCE ONLY")
                    .font(.caption2)
                    .fontWeight(.bold)
                    .foregroundColor(Color(red: 0.976, green: 0.451, blue: 0.086))
                    .padding(.top, 4)
                    .accessibilityLabel("For Reference Only disclaimer banner")

                // Aircraft Type Filter Section
                if !availableAircraftTypes.isEmpty {
                    VStack(alignment: .leading, spacing: 4) {
                        HStack {
                            Text("Filter by Aircraft Type:")
                                .font(.subheadline)
                                .foregroundColor(.secondary)
                            Spacer()
                            if selectedAircraftType != nil {
                                Button(action: { selectedAircraftType = nil }) {
                                    HStack(spacing: 4) {
                                        Image(systemName: "xmark.circle.fill")
                                            .font(.caption)
                                        Text("Clear")
                                            .font(.caption)
                                    }
                                    .foregroundColor(Color(red: 0.976, green: 0.451, blue: 0.086))
                                }
                                .accessibilityIdentifier("clearAircraftFilter")
                                .accessibilityLabel("Clear aircraft filter")
                            }
                        }
                        .padding(.horizontal)

                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: 8) {
                                ForEach(availableAircraftTypes, id: \.self) { aircraftType in
                                    AircraftTypeChip(
                                        title: aircraftType,
                                        isSelected: selectedAircraftType == aircraftType,
                                        action: {
                                            if selectedAircraftType == aircraftType {
                                                selectedAircraftType = nil
                                            } else {
                                                selectedAircraftType = aircraftType
                                            }
                                        }
                                    )
                                    .accessibilityIdentifier("aircraftFilter_\(aircraftType)")
                                }
                            }
                            .padding(.horizontal)
                        }
                    }
                    .padding(.vertical, 8)
                    .background(Color(.systemGray6))
                }

                // Search category filter chips
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(SearchFilter.allCases, id: \.self) { filter in
                            FilterChip(
                                title: filter.rawValue,
                                isSelected: selectedFilter == filter,
                                action: { selectedFilter = filter }
                            )
                        }
                    }
                    .padding(.horizontal)
                    .padding(.vertical, 8)
                }

                // Search results
                if !hasActiveFilter {
                    // Empty state - no search text and no aircraft filter
                    VStack(spacing: 16) {
                        Spacer()
                        Image(systemName: "magnifyingglass")
                            .font(.system(size: 60))
                            .foregroundColor(Color(red: 0.392, green: 0.455, blue: 0.545))
                        Text("Search Your Records")
                            .font(.title2)
                            .fontWeight(.semibold)
                        Text("Search across all job records by aircraft,\nsystem, tools, consumables, and more.")
                            .font(.body)
                            .foregroundColor(.secondary)
                            .multilineTextAlignment(.center)
                        if !availableAircraftTypes.isEmpty {
                            Text("Or use the aircraft type filter above.")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                        Spacer()
                    }
                    .padding()
                } else if filteredRecords.isEmpty && filteredTools.isEmpty {
                    VStack(spacing: 16) {
                        Spacer()
                        Image(systemName: "doc.text.magnifyingglass")
                            .font(.system(size: 50))
                            .foregroundColor(.secondary)
                        Text("No Results")
                            .font(.title3)
                            .fontWeight(.semibold)
                        Text("Try a different search term or filter.")
                            .font(.body)
                            .foregroundColor(.secondary)
                        Spacer()
                    }
                    .padding()
                } else {
                    List {
                        // Show tool results for Tool filter or All filter
                        if (selectedFilter == .tool || selectedFilter == .all) && !filteredTools.isEmpty {
                            Section(header: Text("Tools")) {
                                ForEach(filteredTools, id: \.id) { tool in
                                    NavigationLink(destination: ToolDetailView(tool: tool).modelContainer(for: [FROTool.self, FROJob.self, FROToolGroup.self, FROToolKit.self, FROConsumable.self, FROChemical.self, FROPart.self], inMemory: true)) {
                                        VStack(alignment: .leading, spacing: 4) {
                                            HStack(spacing: 8) {
                                                Image(systemName: "wrench.and.screwdriver.fill")
                                                    .foregroundColor(Color(red: 0.392, green: 0.455, blue: 0.545))
                                                    .font(.body)
                                                Text(tool.name)
                                                    .font(.headline)
                                            }
                                            if let aliases = tool.aliases, !aliases.isEmpty {
                                                Text("aka: \(aliases.joined(separator: ", "))")
                                                    .font(.caption)
                                                    .foregroundColor(.secondary)
                                                    .italic()
                                            }
                                            Text(tool.ownershipType.capitalized)
                                                    .font(.caption2)
                                                    .fontWeight(.medium)
                                                    .padding(.horizontal, 6)
                                                    .padding(.vertical, 2)
                                                    .background(Color(red: 0.145, green: 0.388, blue: 0.922).opacity(0.15))
                                                    .foregroundColor(Color(red: 0.145, green: 0.388, blue: 0.922))
                                                    .cornerRadius(4)
                                        }
                                        .padding(.vertical, 4)
                                    }
                                }
                            }
                        }

                        // Show job record results as navigable cards
                        // Feature #81: Search results display as job record cards with key info
                        if !filteredRecords.isEmpty {
                            Section(header: Text("Job Records")) {
                                ForEach(filteredRecords, id: \.id) { job in
                                    NavigationLink(destination: JobDetailView(job: job).modelContainer(for: [FROTool.self, FROJob.self, FROToolGroup.self, FROToolKit.self, FROConsumable.self, FROChemical.self, FROPart.self], inMemory: true)) {
                                        SearchResultCardView(job: job)
                                    }
                                    .buttonStyle(.plain)
                                }
                            }
                        }
                    }
                    .listStyle(.insetGrouped)
                }
            }
            .navigationTitle("Search")
            .searchable(text: $searchText, prompt: "Search jobs, tools, parts...")
        }
    }
}

/// Filter chip button - sized for gloved/greasy hands (44pt minimum tap target)
struct FilterChip: View {
    let title: String
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.subheadline)
                .fontWeight(isSelected ? .semibold : .regular)
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
                .background(isSelected ? Color(red: 0.145, green: 0.388, blue: 0.922) : Color(.systemGray5))
                .foregroundColor(isSelected ? .white : .primary)
                .cornerRadius(20)
        }
        .frame(minHeight: 44)
        .accessibilityLabel("\(title) filter\(isSelected ? ", selected" : "")")
        .accessibilityHint("Double tap to \(isSelected ? "deselect" : "select") this search filter")
    }
}

/// Aircraft type filter chip - green color scheme for aircraft-specific filtering
/// Sized for gloved/greasy hands (44pt minimum tap target)
struct AircraftTypeChip: View {
    let title: String
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                Image(systemName: "airplane")
                    .font(.caption)
                    .accessibilityHidden(true)
                Text(title)
                    .font(.subheadline)
                    .fontWeight(isSelected ? .semibold : .regular)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .background(isSelected ? Color(red: 0.133, green: 0.545, blue: 0.133) : Color(.systemGray5))
            .foregroundColor(isSelected ? .white : .primary)
            .cornerRadius(20)
        }
        .frame(minHeight: 44)
        .accessibilityLabel("Aircraft type \(title)\(isSelected ? ", selected" : "")")
        .accessibilityHint("Double tap to \(isSelected ? "clear" : "filter by") this aircraft type")
    }
}

/// Search result card for job records in search results.
/// Feature #81: Displays aircraft type, date, and system at minimum.
/// Tapping opens the full job detail view via NavigationLink.
struct SearchResultCardView: View {
    @Bindable var job: JobRecord

    /// Accessibility description combining key job info
    private var accessibilityDescription: String {
        var parts: [String] = []
        parts.append(job.aircraftType)
        if !job.system.isEmpty {
            parts.append(job.system)
        }
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        parts.append(formatter.string(from: job.jobDate))
        return parts.joined(separator: ", ")
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            // Top row: Aircraft type and date
            HStack {
                Text(job.aircraftType.isEmpty ? "Unknown Aircraft" : job.aircraftType)
                    .font(.headline)
                    .foregroundColor(.primary)
                Spacer()
                Text(job.jobDate, style: .date)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            // System (required field per app_spec.txt)
            if !job.system.isEmpty {
                Text(job.system)
                    .font(.subheadline)
                    .foregroundColor(Color(red: 0.145, green: 0.388, blue: 0.922))
            }

            // Task description preview (optional, 2-line limit)
            if let desc = job.taskDescription, !desc.isEmpty {
                Text(desc)
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .lineLimit(2)
            }
        }
        .padding(.vertical, 8)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Job record: \(accessibilityDescription)")
        .accessibilityHint("Double tap to view job details")
    }
}

#Preview {
    SearchView()
        .modelContainer(for: [FROTool.self, FROJob.self, FROToolGroup.self, FROToolKit.self, FROConsumable.self, FROChemical.self, FROPart.self], inMemory: true)
}

import Foundation
import SwiftData

/// ToolGroupService handles all CRUD operations for FROToolGroup entities in SwiftData.
/// Supports nested group hierarchies (groups within groups) for organizing tools.
@MainActor
class ToolGroupService {

    // MARK: - Properties

    private var modelContext: ModelContext {
        SharedModelContainer.shared.mainContext
    }

    // MARK: - Create

    /// Creates a new ToolGroup in SwiftData and saves immediately.
    /// - Parameters:
    ///   - name: The group name (required)
    ///   - parentGroup: Optional parent group for nesting
    /// - Returns: The created ToolGroup object
    @discardableResult
    func createGroup(
        name: String,
        parentGroup: FROToolGroup? = nil
    ) -> FROToolGroup {
        // Set sort order to be after existing siblings
        let siblings: Int
        if let parent = parentGroup {
            siblings = parent.childGroups?.count ?? 0
        } else {
            siblings = fetchTopLevelGroups().count
        }

        let group = FROToolGroup(
            name: name,
            sortOrder: siblings
        )
        group.parentGroup = parentGroup
        modelContext.insert(group)

        do {
            try modelContext.save()
            print("ToolGroupService: Created group '\(name)' successfully")
        } catch {
            print("ToolGroupService: Failed to create group - \(error)")
        }

        return group
    }

    // MARK: - Read

    /// Fetches all top-level groups (no parent), sorted by sortOrder then name.
    /// - Returns: Array of ToolGroup objects
    func fetchTopLevelGroups() -> [FROToolGroup] {
        // #Predicate cannot test optional relationship == nil reliably,
        // so fetch all and filter in-memory
        let descriptor = FetchDescriptor<FROToolGroup>(
            sortBy: [SortDescriptor(\.sortOrder), SortDescriptor(\.name)]
        )

        do {
            let all = try modelContext.fetch(descriptor)
            return all.filter { $0.parentGroup == nil }
        } catch {
            print("ToolGroupService: Failed to fetch top-level groups - \(error)")
            return []
        }
    }

    /// Fetches all groups, sorted by name.
    /// - Returns: Array of all ToolGroup objects
    func fetchAllGroups() -> [FROToolGroup] {
        let descriptor = FetchDescriptor<FROToolGroup>(
            sortBy: [SortDescriptor(\.name)]
        )

        do {
            return try modelContext.fetch(descriptor)
        } catch {
            print("ToolGroupService: Failed to fetch all groups - \(error)")
            return []
        }
    }

    /// Fetches a single group by its UUID.
    /// - Parameter id: The group's UUID
    /// - Returns: The ToolGroup if found, nil otherwise
    func fetchGroup(byId id: UUID) -> FROToolGroup? {
        var descriptor = FetchDescriptor<FROToolGroup>(
            predicate: #Predicate { $0.id == id }
        )
        descriptor.fetchLimit = 1

        do {
            return try modelContext.fetch(descriptor).first
        } catch {
            print("ToolGroupService: Failed to fetch group by ID - \(error)")
            return nil
        }
    }

    /// Gets child groups of a given parent, sorted by sortOrder then name.
    /// - Parameter parent: The parent ToolGroup
    /// - Returns: Sorted array of child ToolGroup objects
    func fetchChildGroups(of parent: FROToolGroup) -> [FROToolGroup] {
        guard let children = parent.childGroups else { return [] }
        return children.sorted { g1, g2 in
            if g1.sortOrder != g2.sortOrder {
                return g1.sortOrder < g2.sortOrder
            }
            return g1.name < g2.name
        }
    }

    /// Gets tools directly in a given group, sorted by size then name.
    /// - Parameter group: The ToolGroup
    /// - Returns: Sorted array of Tool objects in this group
    func fetchTools(in group: FROToolGroup) -> [FROTool] {
        guard let tools = group.tools else { return [] }
        return Array(tools).sortedBySize()
    }

    // MARK: - Update

    /// Updates a group's name and saves.
    /// - Parameters:
    ///   - group: The ToolGroup object to update
    ///   - name: New name (optional, keeps current if nil)
    func updateGroup(
        _ group: FROToolGroup,
        name: String? = nil
    ) {
        if let name = name { group.name = name }

        do {
            try modelContext.save()
            print("ToolGroupService: Updated group '\(group.name)' successfully")
        } catch {
            print("ToolGroupService: Failed to update group - \(error)")
        }
    }

    /// Assigns a tool to a group.
    /// - Parameters:
    ///   - tool: The tool to assign
    ///   - group: The group to assign it to (nil to unassign)
    func assignTool(_ tool: FROTool, to group: FROToolGroup?) {
        tool.group = group

        do {
            try modelContext.save()
            print("ToolGroupService: Assigned tool '\(tool.name)' to group '\(group?.name ?? "none")'")
        } catch {
            print("ToolGroupService: Failed to assign tool to group - \(error)")
        }
    }

    // MARK: - Delete

    /// Deletes a group from SwiftData. Child groups are cascade-deleted.
    /// Tools in the group are unassigned (nullified), not deleted.
    /// - Parameter group: The ToolGroup object to delete
    func deleteGroup(_ group: FROToolGroup) {
        let name = group.name
        modelContext.delete(group)

        do {
            try modelContext.save()
            print("ToolGroupService: Deleted group '\(name)' successfully")
        } catch {
            print("ToolGroupService: Failed to delete group - \(error)")
        }
    }
}

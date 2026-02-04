import CoreData

/// ToolGroupService handles all CRUD operations for ToolGroup entities in Core Data.
/// Supports nested group hierarchies (groups within groups) for organizing tools.
class ToolGroupService {

    // MARK: - Properties

    private let persistenceController: PersistenceController

    /// The managed object context used for all operations
    var viewContext: NSManagedObjectContext {
        persistenceController.viewContext
    }

    // MARK: - Initialization

    /// Initialize with a persistence controller (defaults to shared singleton)
    init(persistenceController: PersistenceController = .shared) {
        self.persistenceController = persistenceController
    }

    // MARK: - Create

    /// Creates a new ToolGroup in Core Data and saves immediately.
    /// - Parameters:
    ///   - name: The group name (required)
    ///   - parentGroup: Optional parent group for nesting
    /// - Returns: The created ToolGroup managed object
    @discardableResult
    func createGroup(
        name: String,
        parentGroup: ToolGroup? = nil
    ) -> ToolGroup {
        let context = viewContext
        let group = ToolGroup(context: context)
        group.id = UUID()
        group.name = name
        group.parentGroup = parentGroup

        // Set sort order to be after existing siblings
        let siblings: Int
        if let parent = parentGroup {
            siblings = (parent.childGroups as? Set<ToolGroup>)?.count ?? 0
        } else {
            siblings = fetchTopLevelGroups().count
        }
        group.sortOrder = Int32(siblings)

        do {
            try context.save()
            print("ToolGroupService: Created group '\(name)' successfully")
        } catch {
            context.rollback()
            print("ToolGroupService: Failed to create group, rolled back - \(error)")
        }

        return group
    }

    // MARK: - Read

    /// Fetches all top-level groups (no parent), sorted by sortOrder then name.
    /// - Returns: Array of ToolGroup managed objects
    func fetchTopLevelGroups() -> [ToolGroup] {
        let request = NSFetchRequest<ToolGroup>(entityName: "ToolGroup")
        request.predicate = NSPredicate(format: "parentGroup == nil")
        request.sortDescriptors = [
            NSSortDescriptor(key: "sortOrder", ascending: true),
            NSSortDescriptor(key: "name", ascending: true)
        ]

        do {
            return try viewContext.fetch(request)
        } catch {
            print("ToolGroupService: Failed to fetch top-level groups - \(error)")
            return []
        }
    }

    /// Fetches all groups, sorted by name.
    /// - Returns: Array of all ToolGroup managed objects
    func fetchAllGroups() -> [ToolGroup] {
        let request = NSFetchRequest<ToolGroup>(entityName: "ToolGroup")
        request.sortDescriptors = [NSSortDescriptor(key: "name", ascending: true)]

        do {
            return try viewContext.fetch(request)
        } catch {
            print("ToolGroupService: Failed to fetch all groups - \(error)")
            return []
        }
    }

    /// Fetches a single group by its UUID.
    /// - Parameter id: The group's UUID
    /// - Returns: The ToolGroup if found, nil otherwise
    func fetchGroup(byId id: UUID) -> ToolGroup? {
        let request = NSFetchRequest<ToolGroup>(entityName: "ToolGroup")
        request.predicate = NSPredicate(format: "id == %@", id as CVarArg)
        request.fetchLimit = 1

        do {
            return try viewContext.fetch(request).first
        } catch {
            print("ToolGroupService: Failed to fetch group by ID - \(error)")
            return nil
        }
    }

    /// Gets child groups of a given parent, sorted by sortOrder then name.
    /// - Parameter parent: The parent ToolGroup
    /// - Returns: Sorted array of child ToolGroup objects
    func fetchChildGroups(of parent: ToolGroup) -> [ToolGroup] {
        guard let children = parent.childGroups as? Set<ToolGroup> else { return [] }
        return children.sorted { g1, g2 in
            if g1.sortOrder != g2.sortOrder {
                return g1.sortOrder < g2.sortOrder
            }
            return (g1.name ?? "") < (g2.name ?? "")
        }
    }

    /// Gets tools directly in a given group, sorted by name.
    /// - Parameter group: The ToolGroup
    /// - Returns: Sorted array of Tool objects in this group
    func fetchTools(in group: ToolGroup) -> [Tool] {
        guard let tools = group.tools as? Set<Tool> else { return [] }
        return tools.sorted { ($0.name ?? "") < ($1.name ?? "") }
    }

    // MARK: - Update

    /// Updates a group's name and saves.
    /// - Parameters:
    ///   - group: The ToolGroup managed object to update
    ///   - name: New name (optional, keeps current if nil)
    func updateGroup(
        _ group: ToolGroup,
        name: String? = nil
    ) {
        if let name = name { group.name = name }

        do {
            try viewContext.save()
            print("ToolGroupService: Updated group '\(group.name ?? "unknown")' successfully")
        } catch {
            viewContext.rollback()
            print("ToolGroupService: Failed to update group, rolled back - \(error)")
        }
    }

    /// Assigns a tool to a group.
    /// - Parameters:
    ///   - tool: The tool to assign
    ///   - group: The group to assign it to (nil to unassign)
    func assignTool(_ tool: Tool, to group: ToolGroup?) {
        tool.group = group

        do {
            try viewContext.save()
            print("ToolGroupService: Assigned tool '\(tool.name ?? "")' to group '\(group?.name ?? "none")'")
        } catch {
            viewContext.rollback()
            print("ToolGroupService: Failed to assign tool to group, rolled back - \(error)")
        }
    }

    // MARK: - Delete

    /// Deletes a group from Core Data. Child groups are cascade-deleted.
    /// Tools in the group are unassigned (nullified), not deleted.
    /// - Parameter group: The ToolGroup managed object to delete
    func deleteGroup(_ group: ToolGroup) {
        let name = group.name ?? "unknown"
        viewContext.delete(group)

        do {
            try viewContext.save()
            print("ToolGroupService: Deleted group '\(name)' successfully")
        } catch {
            viewContext.rollback()
            print("ToolGroupService: Failed to delete group, rolled back - \(error)")
        }
    }
}

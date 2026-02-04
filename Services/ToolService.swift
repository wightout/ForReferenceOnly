import CoreData

/// ToolService handles all CRUD operations for Tool entities in Core Data.
/// Uses the real SQLite-backed persistent store for all operations.
class ToolService {

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

    /// Creates a new Tool in Core Data and saves immediately.
    /// - Parameters:
    ///   - name: The tool name (required)
    ///   - ownershipType: Ownership category: "personal", "shop", or "borrowed"
    ///   - borrowedFrom: Source name if borrowed (optional)
    ///   - notes: Additional notes (optional)
    ///   - aliases: Array of alias names (optional)
    /// - Returns: The created Tool managed object
    @discardableResult
    func createTool(
        name: String,
        ownershipType: String = "personal",
        borrowedFrom: String? = nil,
        notes: String? = nil,
        aliases: [String]? = nil
    ) -> Tool {
        let context = viewContext
        let tool = Tool(context: context)
        tool.id = UUID()
        tool.name = name
        tool.ownershipType = ownershipType
        tool.borrowedFrom = borrowedFrom
        tool.notes = notes
        tool.aliases = aliases as NSArray?
        tool.createdAt = Date()

        do {
            try context.save()
            print("ToolService: Created tool '\(name)' successfully")
        } catch {
            context.rollback()
            print("ToolService: Failed to create tool, rolled back - \(error)")
        }

        return tool
    }

    // MARK: - Read

    /// Fetches all tools, sorted by name ascending.
    /// - Returns: Array of Tool managed objects
    func fetchAllTools() -> [Tool] {
        let request = NSFetchRequest<Tool>(entityName: "Tool")
        request.sortDescriptors = [NSSortDescriptor(key: "name", ascending: true)]

        do {
            let tools = try viewContext.fetch(request)
            return tools
        } catch {
            print("ToolService: Failed to fetch tools - \(error)")
            return []
        }
    }

    /// Fetches a single tool by its UUID.
    /// - Parameter id: The tool's UUID
    /// - Returns: The Tool if found, nil otherwise
    func fetchTool(byId id: UUID) -> Tool? {
        let request = NSFetchRequest<Tool>(entityName: "Tool")
        request.predicate = NSPredicate(format: "id == %@", id as CVarArg)
        request.fetchLimit = 1

        do {
            return try viewContext.fetch(request).first
        } catch {
            print("ToolService: Failed to fetch tool by ID - \(error)")
            return nil
        }
    }

    /// Fetches tools matching a name (exact match).
    /// - Parameter name: The tool name to search for
    /// - Returns: Array of matching Tool objects
    func fetchTools(byName name: String) -> [Tool] {
        let request = NSFetchRequest<Tool>(entityName: "Tool")
        request.predicate = NSPredicate(format: "name == %@", name)

        do {
            return try viewContext.fetch(request)
        } catch {
            print("ToolService: Failed to fetch tools by name - \(error)")
            return []
        }
    }

    // MARK: - Update

    /// Updates a tool's properties and saves.
    /// - Parameters:
    ///   - tool: The Tool managed object to update
    ///   - name: New name (optional, keeps current if nil)
    ///   - ownershipType: New ownership type (optional)
    ///   - borrowedFrom: New borrowed source (optional)
    ///   - notes: New notes (optional)
    func updateTool(
        _ tool: Tool,
        name: String? = nil,
        ownershipType: String? = nil,
        borrowedFrom: String? = nil,
        notes: String? = nil,
        aliases: [String]? = nil
    ) {
        if let name = name { tool.name = name }
        if let ownershipType = ownershipType { tool.ownershipType = ownershipType }
        if let borrowedFrom = borrowedFrom { tool.borrowedFrom = borrowedFrom }
        if let notes = notes { tool.notes = notes }
        if let aliases = aliases { tool.aliases = aliases.isEmpty ? nil : aliases as NSArray }

        do {
            try viewContext.save()
            print("ToolService: Updated tool '\(tool.name ?? "unknown")' successfully")
        } catch {
            viewContext.rollback()
            print("ToolService: Failed to update tool, rolled back - \(error)")
        }
    }

    // MARK: - Delete

    /// Deletes a tool from Core Data and saves.
    /// - Parameter tool: The Tool managed object to delete
    func deleteTool(_ tool: Tool) {
        let name = tool.name ?? "unknown"
        viewContext.delete(tool)

        do {
            try viewContext.save()
            print("ToolService: Deleted tool '\(name)' successfully")
        } catch {
            viewContext.rollback()
            print("ToolService: Failed to delete tool, rolled back - \(error)")
        }
    }

    /// Deletes all tools matching a given name.
    /// - Parameter name: The tool name to delete
    /// - Returns: Number of tools deleted
    @discardableResult
    func deleteTools(byName name: String) -> Int {
        let tools = fetchTools(byName: name)
        var count = 0
        for tool in tools {
            viewContext.delete(tool)
            count += 1
        }

        if count > 0 {
            do {
                try viewContext.save()
                print("ToolService: Deleted \(count) tool(s) named '\(name)'")
            } catch {
                viewContext.rollback()
            print("ToolService: Failed to delete tools, rolled back - \(error)")
            }
        }

        return count
    }
}

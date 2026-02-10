import Foundation
import SwiftData

/// Result of a smart tool deletion — either hard-deleted or converted to borrowed.
/// Used by `ToolService.smartDeleteTool(_:)` to communicate the outcome to the caller.
enum ToolDeletionResult {
    /// Tool had no job references and was permanently deleted
    case deleted
    /// Tool had job references and was converted to borrowed instead of deleted
    case convertedToBorrowed(newName: String)
}

/// ToolService handles all CRUD operations for FROTool entities in SwiftData.
/// Uses the real SQLite-backed persistent store for all operations.
@MainActor
class ToolService {

    // MARK: - Properties

    private var modelContext: ModelContext {
        SharedModelContainer.shared.mainContext
    }

    // MARK: - Create

    /// Creates a new Tool in SwiftData and saves immediately.
    /// - Parameters:
    ///   - name: The tool name (required)
    ///   - ownershipType: Ownership category: "personal", "shop", or "borrowed"
    ///   - borrowedFrom: Source name if borrowed (optional)
    ///   - notes: Additional notes (optional)
    ///   - aliases: Array of alias names (optional)
    /// - Returns: The created Tool object
    @discardableResult
    func createTool(
        name: String,
        ownershipType: String = "personal",
        borrowedFrom: String? = nil,
        notes: String? = nil,
        aliases: [String]? = nil
    ) -> FROTool {
        let tool = FROTool(
            name: name,
            aliases: aliases,
            ownershipType: ownershipType,
            borrowedFrom: borrowedFrom,
            notes: notes
        )
        modelContext.insert(tool)

        do {
            try modelContext.save()
            print("ToolService: Created tool '\(name)' successfully")
        } catch {
            print("ToolService: Failed to create tool - \(error)")
        }

        return tool
    }

    // MARK: - Read

    /// Fetches all tools, sorted by name ascending.
    /// - Returns: Array of Tool objects
    func fetchAllTools() -> [FROTool] {
        let descriptor = FetchDescriptor<FROTool>(
            sortBy: [SortDescriptor(\.name)]
        )

        do {
            return try modelContext.fetch(descriptor)
        } catch {
            print("ToolService: Failed to fetch tools - \(error)")
            return []
        }
    }

    /// Fetches a single tool by its UUID.
    /// - Parameter id: The tool's UUID
    /// - Returns: The Tool if found, nil otherwise
    func fetchTool(byId id: UUID) -> FROTool? {
        var descriptor = FetchDescriptor<FROTool>(
            predicate: #Predicate { $0.id == id }
        )
        descriptor.fetchLimit = 1

        do {
            return try modelContext.fetch(descriptor).first
        } catch {
            print("ToolService: Failed to fetch tool by ID - \(error)")
            return nil
        }
    }

    /// Fetches tools matching a name (exact match).
    /// - Parameter name: The tool name to search for
    /// - Returns: Array of matching Tool objects
    func fetchTools(byName name: String) -> [FROTool] {
        let descriptor = FetchDescriptor<FROTool>(
            predicate: #Predicate { $0.name == name }
        )

        do {
            return try modelContext.fetch(descriptor)
        } catch {
            print("ToolService: Failed to fetch tools by name - \(error)")
            return []
        }
    }

    // MARK: - Update

    /// Updates a tool's properties and saves.
    /// - Parameters:
    ///   - tool: The Tool object to update
    ///   - name: New name (optional, keeps current if nil)
    ///   - ownershipType: New ownership type (optional)
    ///   - borrowedFrom: New borrowed source (optional)
    ///   - notes: New notes (optional)
    func updateTool(
        _ tool: FROTool,
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
        if let aliases = aliases { tool.aliases = aliases.isEmpty ? nil : aliases }

        do {
            try modelContext.save()
            print("ToolService: Updated tool '\(tool.name)' successfully")
        } catch {
            print("ToolService: Failed to update tool - \(error)")
        }
    }

    // MARK: - Delete

    /// Deletes a tool from SwiftData and saves.
    /// - Parameter tool: The Tool object to delete
    func deleteTool(_ tool: FROTool) {
        let name = tool.name
        modelContext.delete(tool)

        do {
            try modelContext.save()
            print("ToolService: Deleted tool '\(name)' successfully")
        } catch {
            print("ToolService: Failed to delete tool - \(error)")
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
            modelContext.delete(tool)
            count += 1
        }

        if count > 0 {
            do {
                try modelContext.save()
                print("ToolService: Deleted \(count) tool(s) named '\(name)'")
            } catch {
                print("ToolService: Failed to delete tools - \(error)")
            }
        }

        return count
    }

    // MARK: - Purchase Conversion

    /// Converts a borrowed tool to personal (marks as purchased).
    /// The tool entity stays the same, so all job references automatically update.
    /// - Parameter tool: The borrowed Tool to convert to personal
    func markAsPurchased(_ tool: FROTool) {
        let name = tool.name
        tool.ownershipType = "personal"
        tool.borrowedFrom = nil

        do {
            try modelContext.save()
            print("ToolService: Marked tool '\(name)' as purchased (borrowed -> personal)")
        } catch {
            print("ToolService: Failed to mark tool as purchased - \(error)")
        }
    }

    // MARK: - Smart Delete

    /// Intelligently deletes a tool: hard-deletes if no job references,
    /// or converts to borrowed with context name if jobs reference it.
    /// This preserves job record accuracy when a tool is lost/broken.
    /// - Parameter tool: The Tool to delete or convert
    /// - Returns: The deletion result indicating what action was taken
    @discardableResult
    func smartDeleteTool(_ tool: FROTool) -> ToolDeletionResult {
        let originalName = tool.name
        let jobCount = tool.jobRecords?.count ?? 0

        // No job references — safe to hard-delete
        if jobCount == 0 {
            modelContext.delete(tool)
            do {
                try modelContext.save()
                print("ToolService: Hard-deleted tool '\(originalName)' (no job references)")
            } catch {
                print("ToolService: Failed to delete tool '\(originalName)' - \(error)")
            }
            return .deleted
        }

        // Tool has job references — convert to borrowed instead of deleting
        // Build a standalone name using toolType (e.g., "3/8"" -> "3/8" Socket")
        // Falls back to appending the full set/kit name if no toolType is set
        var updatedName = originalName

        if let group = tool.group, let type = group.toolType, !type.isEmpty {
            updatedName = "\(originalName) \(type)"
        } else if let kits = tool.toolKits, let firstKit = kits.first,
                  let type = firstKit.toolType, !type.isEmpty {
            updatedName = "\(originalName) \(type)"
        } else if let group = tool.group, !group.name.isEmpty {
            updatedName = "\(originalName) — \(group.name)"
        } else if let kits = tool.toolKits, let firstKit = kits.first,
                  !firstKit.name.isEmpty {
            updatedName = "\(originalName) — \(firstKit.name)"
        }

        // Convert to borrowed
        tool.ownershipType = "borrowed"
        tool.borrowedFrom = nil
        tool.name = updatedName

        // Remove from group (borrowed tools can't be in sets)
        if tool.group != nil {
            let groupName = tool.group?.name ?? "unknown"
            tool.group = nil
            print("ToolService: Removed tool from group '\(groupName)' during smart-delete")
        }

        // Remove from all kits (borrowed tools can't be in kits)
        if let kits = tool.toolKits, !kits.isEmpty {
            let kitNames = kits.map { $0.name }.joined(separator: ", ")
            tool.toolKits = []
            print("ToolService: Removed tool from \(kits.count) kit(s): [\(kitNames)] during smart-delete")
        }

        do {
            try modelContext.save()
            print("ToolService: Smart-deleted tool '\(originalName)' -> converted to borrowed as '\(updatedName)' (\(jobCount) job references preserved)")
        } catch {
            print("ToolService: Failed to smart-delete tool '\(originalName)' - \(error)")
        }

        return .convertedToBorrowed(newName: updatedName)
    }
}

import CoreData

/// PersistenceController manages the Core Data stack for the FRO app.
/// It initializes a SQLite-backed persistent container and provides
/// the managed object context for all data operations.
struct PersistenceController {

    // MARK: - Shared Instance

    /// Shared singleton instance for production use
    static let shared = PersistenceController()

    // MARK: - Properties

    /// The Core Data persistent container with SQLite backing store
    let container: NSPersistentContainer

    /// Convenience accessor for the main view context
    var viewContext: NSManagedObjectContext {
        container.viewContext
    }

    // MARK: - Initialization

    /// Initializes the Core Data stack.
    /// - Parameter inMemory: If true, uses an in-memory store (for previews/testing only).
    ///   Production always uses SQLite on disk.
    init(inMemory: Bool = false) {
        // Load the Core Data model from the bundle
        container = NSPersistentContainer(name: "ForReferenceOnly")

        if inMemory {
            // In-memory store for SwiftUI previews only
            container.persistentStoreDescriptions.first?.url = URL(fileURLWithPath: "/dev/null")
        }

        // Configure SQLite store options for performance
        if let description = container.persistentStoreDescriptions.first {
            // Enable lightweight migration
            description.setOption(true as NSNumber, forKey: NSMigratePersistentStoresAutomaticallyOption)
            description.setOption(true as NSNumber, forKey: NSInferMappingModelAutomaticallyOption)

            // Enable WAL journal mode for better concurrent access
            description.setOption(["journal_mode": "WAL"] as NSDictionary, forKey: NSSQLitePragmasOption)
        }

        // Load persistent stores
        container.loadPersistentStores { storeDescription, error in
            if let error = error as NSError? {
                print("Core Data failed to load: \(error), \(error.userInfo)")
                fatalError("Core Data stack initialization failed: \(error.localizedDescription)")
            }

            print("Core Data stack initialized successfully")
            print("   Store type: \(storeDescription.type)")
            if let url = storeDescription.url {
                print("   Store URL: \(url.absoluteString)")
            }
        }

        // Configure view context for UI usage
        container.viewContext.automaticallyMergesChangesFromParent = true
        container.viewContext.mergePolicy = NSMergeByPropertyObjectTrumpMergePolicy
    }

    // MARK: - Save Support

    /// Saves the view context if there are unsaved changes.
    func save() {
        let context = viewContext
        if context.hasChanges {
            do {
                try context.save()
                print("Core Data context saved successfully")
            } catch {
                let nsError = error as NSError
                print("Core Data save failed: \(nsError), \(nsError.userInfo)")
            }
        }
    }

    // MARK: - Data Management

    /// Clears all data from the database.
    /// Deletes all entities: JobRecord, JobRevision, Tool, ToolGroup, ToolKit, Consumable, Chemical, VoiceMemo.
    /// - Returns: A tuple with success flag and optional error message
    func clearAllData() -> (success: Bool, error: String?) {
        let context = viewContext
        let entityNames = [
            "JobRevision", // Delete revisions first (references JobRecord)
            "VoiceMemo",   // Delete voice memos (may reference JobRecord)
            "JobRecord",   // Delete job records (has relationships to tools, consumables, chemicals)
            "Tool",        // Delete tools (may be in groups or kits)
            "ToolGroup",   // Delete tool groups
            "ToolKit",     // Delete tool kits
            "Consumable",  // Delete consumables
            "Chemical"     // Delete chemicals
        ]

        do {
            for entityName in entityNames {
                let fetchRequest = NSFetchRequest<NSFetchRequestResult>(entityName: entityName)
                let deleteRequest = NSBatchDeleteRequest(fetchRequest: fetchRequest)
                deleteRequest.resultType = .resultTypeObjectIDs

                // Execute batch delete
                let result = try context.execute(deleteRequest) as? NSBatchDeleteResult
                let objectIDArray = result?.result as? [NSManagedObjectID] ?? []

                // Merge changes into context so UI updates
                NSManagedObjectContext.mergeChanges(
                    fromRemoteContextSave: [NSDeletedObjectsKey: objectIDArray],
                    into: [context]
                )

                print("Cleared \(objectIDArray.count) \(entityName) records")
            }

            // Reset the context to ensure clean state
            context.reset()
            print("All data cleared successfully")
            return (true, nil)
        } catch {
            let nsError = error as NSError
            print("Failed to clear data: \(nsError), \(nsError.userInfo)")
            return (false, nsError.localizedDescription)
        }
    }

    // MARK: - Preview Support

    /// Preview instance with in-memory store for SwiftUI previews
    static var preview: PersistenceController = {
        let controller = PersistenceController(inMemory: true)
        return controller
    }()
}

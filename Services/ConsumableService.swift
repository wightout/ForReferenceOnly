import CoreData

/// ConsumableService handles all CRUD operations for Consumable entities in Core Data.
/// Uses the real SQLite-backed persistent store for all operations.
class ConsumableService {

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

    /// Creates a new Consumable in Core Data and saves immediately.
    /// - Parameters:
    ///   - name: The consumable name (required)
    ///   - category: Category (safety_wire, cotter_pin, o_ring, seal, other)
    ///   - size: Size specification (optional)
    ///   - spec: Spec/part number (optional)
    ///   - notes: Additional notes (optional)
    /// - Returns: The created Consumable managed object
    @discardableResult
    func createConsumable(
        name: String,
        category: String = "other",
        size: String? = nil,
        spec: String? = nil,
        notes: String? = nil
    ) -> Consumable {
        let context = viewContext
        let consumable = Consumable(context: context)
        consumable.id = UUID()
        consumable.name = name
        consumable.category = category
        consumable.size = size
        consumable.spec = spec
        consumable.notes = notes
        consumable.createdAt = Date()

        do {
            try context.save()
            print("ConsumableService: Created consumable '\(name)' successfully")
        } catch {
            context.rollback()
            print("ConsumableService: Failed to create consumable, rolled back - \(error)")
        }

        return consumable
    }

    // MARK: - Read

    /// Fetches all consumables, sorted by name ascending.
    /// - Returns: Array of Consumable managed objects
    func fetchAllConsumables() -> [Consumable] {
        let request = NSFetchRequest<Consumable>(entityName: "Consumable")
        request.sortDescriptors = [NSSortDescriptor(key: "name", ascending: true)]

        do {
            let consumables = try viewContext.fetch(request)
            return consumables
        } catch {
            print("ConsumableService: Failed to fetch consumables - \(error)")
            return []
        }
    }

    /// Fetches a single consumable by its UUID.
    /// - Parameter id: The consumable's UUID
    /// - Returns: The Consumable if found, nil otherwise
    func fetchConsumable(byId id: UUID) -> Consumable? {
        let request = NSFetchRequest<Consumable>(entityName: "Consumable")
        request.predicate = NSPredicate(format: "id == %@", id as CVarArg)
        request.fetchLimit = 1

        do {
            return try viewContext.fetch(request).first
        } catch {
            print("ConsumableService: Failed to fetch consumable by ID - \(error)")
            return nil
        }
    }

    /// Fetches consumables matching a category.
    /// - Parameter category: The category to filter by
    /// - Returns: Array of matching Consumable objects
    func fetchConsumables(byCategory category: String) -> [Consumable] {
        let request = NSFetchRequest<Consumable>(entityName: "Consumable")
        request.predicate = NSPredicate(format: "category == %@", category)
        request.sortDescriptors = [NSSortDescriptor(key: "name", ascending: true)]

        do {
            return try viewContext.fetch(request)
        } catch {
            print("ConsumableService: Failed to fetch consumables by category - \(error)")
            return []
        }
    }

    /// Fetches consumables matching a name (exact match).
    /// - Parameter name: The consumable name to search for
    /// - Returns: Array of matching Consumable objects
    func fetchConsumables(byName name: String) -> [Consumable] {
        let request = NSFetchRequest<Consumable>(entityName: "Consumable")
        request.predicate = NSPredicate(format: "name == %@", name)

        do {
            return try viewContext.fetch(request)
        } catch {
            print("ConsumableService: Failed to fetch consumables by name - \(error)")
            return []
        }
    }

    // MARK: - Update

    /// Updates a consumable's properties and saves.
    /// - Parameters:
    ///   - consumable: The Consumable managed object to update
    ///   - name: New name (optional, keeps current if nil)
    ///   - category: New category (optional)
    ///   - size: New size (optional)
    ///   - spec: New spec (optional)
    ///   - notes: New notes (optional)
    func updateConsumable(
        _ consumable: Consumable,
        name: String? = nil,
        category: String? = nil,
        size: String? = nil,
        spec: String? = nil,
        notes: String? = nil
    ) {
        if let name = name { consumable.name = name }
        if let category = category { consumable.category = category }
        if let size = size { consumable.size = size }
        if let spec = spec { consumable.spec = spec }
        if let notes = notes { consumable.notes = notes }

        do {
            try viewContext.save()
            print("ConsumableService: Updated consumable '\(consumable.name ?? "unknown")' successfully")
        } catch {
            viewContext.rollback()
            print("ConsumableService: Failed to update consumable, rolled back - \(error)")
        }
    }

    // MARK: - Delete

    /// Deletes a consumable from Core Data and saves.
    /// - Parameter consumable: The Consumable managed object to delete
    func deleteConsumable(_ consumable: Consumable) {
        let name = consumable.name ?? "unknown"
        viewContext.delete(consumable)

        do {
            try viewContext.save()
            print("ConsumableService: Deleted consumable '\(name)' successfully")
        } catch {
            viewContext.rollback()
            print("ConsumableService: Failed to delete consumable, rolled back - \(error)")
        }
    }

    /// Deletes all consumables matching a given name.
    /// - Parameter name: The consumable name to delete
    /// - Returns: Number of consumables deleted
    @discardableResult
    func deleteConsumables(byName name: String) -> Int {
        let consumables = fetchConsumables(byName: name)
        var count = 0
        for consumable in consumables {
            viewContext.delete(consumable)
            count += 1
        }

        if count > 0 {
            do {
                try viewContext.save()
                print("ConsumableService: Deleted \(count) consumable(s) named '\(name)'")
            } catch {
                viewContext.rollback()
            print("ConsumableService: Failed to delete consumables, rolled back - \(error)")
            }
        }

        return count
    }
}

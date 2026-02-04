import CoreData

/// ChemicalService handles all CRUD operations for Chemical entities in Core Data.
/// Uses the real SQLite-backed persistent store for all operations.
class ChemicalService {

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

    /// Creates a new Chemical in Core Data and saves immediately.
    /// - Parameters:
    ///   - name: The chemical name (required)
    ///   - category: Category (fluid, lubricant, cleaner, sealant, other)
    ///   - size: Size specification (optional)
    ///   - spec: Spec/part number (optional)
    ///   - notes: Additional notes (optional)
    /// - Returns: The created Chemical managed object
    @discardableResult
    func createChemical(
        name: String,
        category: String = "other",
        size: String? = nil,
        spec: String? = nil,
        notes: String? = nil
    ) -> Chemical {
        let context = viewContext
        let chemical = Chemical(context: context)
        chemical.id = UUID()
        chemical.name = name
        chemical.category = category
        chemical.size = size
        chemical.spec = spec
        chemical.notes = notes
        chemical.createdAt = Date()

        do {
            try context.save()
            print("ChemicalService: Created chemical '\(name)' successfully")
        } catch {
            context.rollback()
            print("ChemicalService: Failed to create chemical, rolled back - \(error)")
        }

        return chemical
    }

    // MARK: - Read

    /// Fetches all chemicals, sorted by name ascending.
    /// - Returns: Array of Chemical managed objects
    func fetchAllChemicals() -> [Chemical] {
        let request = NSFetchRequest<Chemical>(entityName: "Chemical")
        request.sortDescriptors = [NSSortDescriptor(key: "name", ascending: true)]

        do {
            let chemicals = try viewContext.fetch(request)
            return chemicals
        } catch {
            print("ChemicalService: Failed to fetch chemicals - \(error)")
            return []
        }
    }

    /// Fetches a single chemical by its UUID.
    /// - Parameter id: The chemical's UUID
    /// - Returns: The Chemical if found, nil otherwise
    func fetchChemical(byId id: UUID) -> Chemical? {
        let request = NSFetchRequest<Chemical>(entityName: "Chemical")
        request.predicate = NSPredicate(format: "id == %@", id as CVarArg)
        request.fetchLimit = 1

        do {
            return try viewContext.fetch(request).first
        } catch {
            print("ChemicalService: Failed to fetch chemical by ID - \(error)")
            return nil
        }
    }

    /// Fetches chemicals matching a category.
    /// - Parameter category: The category to filter by
    /// - Returns: Array of matching Chemical objects
    func fetchChemicals(byCategory category: String) -> [Chemical] {
        let request = NSFetchRequest<Chemical>(entityName: "Chemical")
        request.predicate = NSPredicate(format: "category == %@", category)
        request.sortDescriptors = [NSSortDescriptor(key: "name", ascending: true)]

        do {
            return try viewContext.fetch(request)
        } catch {
            print("ChemicalService: Failed to fetch chemicals by category - \(error)")
            return []
        }
    }

    /// Fetches chemicals matching a name (exact match).
    /// - Parameter name: The chemical name to search for
    /// - Returns: Array of matching Chemical objects
    func fetchChemicals(byName name: String) -> [Chemical] {
        let request = NSFetchRequest<Chemical>(entityName: "Chemical")
        request.predicate = NSPredicate(format: "name == %@", name)

        do {
            return try viewContext.fetch(request)
        } catch {
            print("ChemicalService: Failed to fetch chemicals by name - \(error)")
            return []
        }
    }

    // MARK: - Update

    /// Updates a chemical's properties and saves.
    /// - Parameters:
    ///   - chemical: The Chemical managed object to update
    ///   - name: New name (optional, keeps current if nil)
    ///   - category: New category (optional)
    ///   - size: New size (optional)
    ///   - spec: New spec (optional)
    ///   - notes: New notes (optional)
    func updateChemical(
        _ chemical: Chemical,
        name: String? = nil,
        category: String? = nil,
        size: String? = nil,
        spec: String? = nil,
        notes: String? = nil
    ) {
        if let name = name { chemical.name = name }
        if let category = category { chemical.category = category }
        if let size = size { chemical.size = size }
        if let spec = spec { chemical.spec = spec }
        if let notes = notes { chemical.notes = notes }

        do {
            try viewContext.save()
            print("ChemicalService: Updated chemical '\(chemical.name ?? "unknown")' successfully")
        } catch {
            viewContext.rollback()
            print("ChemicalService: Failed to update chemical, rolled back - \(error)")
        }
    }

    // MARK: - Delete

    /// Deletes a chemical from Core Data and saves.
    /// - Parameter chemical: The Chemical managed object to delete
    func deleteChemical(_ chemical: Chemical) {
        let name = chemical.name ?? "unknown"
        viewContext.delete(chemical)

        do {
            try viewContext.save()
            print("ChemicalService: Deleted chemical '\(name)' successfully")
        } catch {
            viewContext.rollback()
            print("ChemicalService: Failed to delete chemical, rolled back - \(error)")
        }
    }

    /// Deletes all chemicals matching a given name.
    /// - Parameter name: The chemical name to delete
    /// - Returns: Number of chemicals deleted
    @discardableResult
    func deleteChemicals(byName name: String) -> Int {
        let chemicals = fetchChemicals(byName: name)
        var count = 0
        for chemical in chemicals {
            viewContext.delete(chemical)
            count += 1
        }

        if count > 0 {
            do {
                try viewContext.save()
                print("ChemicalService: Deleted \(count) chemical(s) named '\(name)'")
            } catch {
                viewContext.rollback()
            print("ChemicalService: Failed to delete chemicals, rolled back - \(error)")
            }
        }

        return count
    }
}

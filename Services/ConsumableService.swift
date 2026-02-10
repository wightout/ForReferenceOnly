import Foundation
import SwiftData

/// ConsumableService handles all CRUD operations for FROConsumable entities in SwiftData.
/// Uses the real SQLite-backed persistent store for all operations.
@MainActor
class ConsumableService {

    // MARK: - Properties

    private var modelContext: ModelContext {
        SharedModelContainer.shared.mainContext
    }

    // MARK: - Create

    /// Creates a new Consumable in SwiftData and saves immediately.
    /// - Parameters:
    ///   - name: The consumable name (required)
    ///   - category: Category (safety_wire, cotter_pin, o_ring, seal, other)
    ///   - size: Size specification (optional)
    ///   - spec: Spec/part number (optional)
    ///   - notes: Additional notes (optional)
    /// - Returns: The created Consumable object
    @discardableResult
    func createConsumable(
        name: String,
        category: String = "other",
        size: String? = nil,
        spec: String? = nil,
        notes: String? = nil
    ) -> FROConsumable {
        let consumable = FROConsumable(
            name: name,
            category: category,
            size: size,
            spec: spec,
            notes: notes
        )
        modelContext.insert(consumable)

        do {
            try modelContext.save()
            print("ConsumableService: Created consumable '\(name)' successfully")
        } catch {
            print("ConsumableService: Failed to create consumable - \(error)")
        }

        return consumable
    }

    // MARK: - Read

    /// Fetches all consumables, sorted by name ascending.
    /// - Returns: Array of Consumable objects
    func fetchAllConsumables() -> [FROConsumable] {
        let descriptor = FetchDescriptor<FROConsumable>(
            sortBy: [SortDescriptor(\.name)]
        )

        do {
            return try modelContext.fetch(descriptor)
        } catch {
            print("ConsumableService: Failed to fetch consumables - \(error)")
            return []
        }
    }

    /// Fetches a single consumable by its UUID.
    /// - Parameter id: The consumable's UUID
    /// - Returns: The Consumable if found, nil otherwise
    func fetchConsumable(byId id: UUID) -> FROConsumable? {
        var descriptor = FetchDescriptor<FROConsumable>(
            predicate: #Predicate { $0.id == id }
        )
        descriptor.fetchLimit = 1

        do {
            return try modelContext.fetch(descriptor).first
        } catch {
            print("ConsumableService: Failed to fetch consumable by ID - \(error)")
            return nil
        }
    }

    /// Fetches consumables matching a category.
    /// - Parameter category: The category to filter by
    /// - Returns: Array of matching Consumable objects
    func fetchConsumables(byCategory category: String) -> [FROConsumable] {
        let descriptor = FetchDescriptor<FROConsumable>(
            predicate: #Predicate { $0.category == category },
            sortBy: [SortDescriptor(\.name)]
        )

        do {
            return try modelContext.fetch(descriptor)
        } catch {
            print("ConsumableService: Failed to fetch consumables by category - \(error)")
            return []
        }
    }

    /// Fetches consumables matching a name (exact match).
    /// - Parameter name: The consumable name to search for
    /// - Returns: Array of matching Consumable objects
    func fetchConsumables(byName name: String) -> [FROConsumable] {
        let descriptor = FetchDescriptor<FROConsumable>(
            predicate: #Predicate { $0.name == name }
        )

        do {
            return try modelContext.fetch(descriptor)
        } catch {
            print("ConsumableService: Failed to fetch consumables by name - \(error)")
            return []
        }
    }

    // MARK: - Update

    /// Updates a consumable's properties and saves.
    /// - Parameters:
    ///   - consumable: The Consumable object to update
    ///   - name: New name (optional, keeps current if nil)
    ///   - category: New category (optional)
    ///   - size: New size (optional)
    ///   - spec: New spec (optional)
    ///   - notes: New notes (optional)
    func updateConsumable(
        _ consumable: FROConsumable,
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
            try modelContext.save()
            print("ConsumableService: Updated consumable '\(consumable.name)' successfully")
        } catch {
            print("ConsumableService: Failed to update consumable - \(error)")
        }
    }

    // MARK: - Delete

    /// Deletes a consumable from SwiftData and saves.
    /// - Parameter consumable: The Consumable object to delete
    func deleteConsumable(_ consumable: FROConsumable) {
        let name = consumable.name
        modelContext.delete(consumable)

        do {
            try modelContext.save()
            print("ConsumableService: Deleted consumable '\(name)' successfully")
        } catch {
            print("ConsumableService: Failed to delete consumable - \(error)")
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
            modelContext.delete(consumable)
            count += 1
        }

        if count > 0 {
            do {
                try modelContext.save()
                print("ConsumableService: Deleted \(count) consumable(s) named '\(name)'")
            } catch {
                print("ConsumableService: Failed to delete consumables - \(error)")
            }
        }

        return count
    }
}

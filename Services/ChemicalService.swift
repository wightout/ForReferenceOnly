import Foundation
import SwiftData

/// ChemicalService handles all CRUD operations for FROChemical entities in SwiftData.
/// Uses the real SQLite-backed persistent store for all operations.
@MainActor
class ChemicalService {

    // MARK: - Properties

    private var modelContext: ModelContext {
        SharedModelContainer.shared.mainContext
    }

    // MARK: - Create

    /// Creates a new Chemical in SwiftData and saves immediately.
    /// - Parameters:
    ///   - name: The chemical name (required)
    ///   - category: Category (fluid, lubricant, cleaner, sealant, other)
    ///   - size: Size specification (optional)
    ///   - spec: Spec/part number (optional)
    ///   - notes: Additional notes (optional)
    /// - Returns: The created Chemical object
    @discardableResult
    func createChemical(
        name: String,
        category: String = "other",
        size: String? = nil,
        spec: String? = nil,
        notes: String? = nil
    ) -> FROChemical {
        let chemical = FROChemical(
            name: name,
            category: category,
            size: size,
            spec: spec,
            notes: notes
        )
        modelContext.insert(chemical)

        do {
            try modelContext.save()
            print("ChemicalService: Created chemical '\(name)' successfully")
        } catch {
            print("ChemicalService: Failed to create chemical - \(error)")
        }

        return chemical
    }

    // MARK: - Read

    /// Fetches all chemicals, sorted by name ascending.
    /// - Returns: Array of Chemical objects
    func fetchAllChemicals() -> [FROChemical] {
        let descriptor = FetchDescriptor<FROChemical>(
            sortBy: [SortDescriptor(\.name)]
        )

        do {
            return try modelContext.fetch(descriptor)
        } catch {
            print("ChemicalService: Failed to fetch chemicals - \(error)")
            return []
        }
    }

    /// Fetches a single chemical by its UUID.
    /// - Parameter id: The chemical's UUID
    /// - Returns: The Chemical if found, nil otherwise
    func fetchChemical(byId id: UUID) -> FROChemical? {
        var descriptor = FetchDescriptor<FROChemical>(
            predicate: #Predicate { $0.id == id }
        )
        descriptor.fetchLimit = 1

        do {
            return try modelContext.fetch(descriptor).first
        } catch {
            print("ChemicalService: Failed to fetch chemical by ID - \(error)")
            return nil
        }
    }

    /// Fetches chemicals matching a category.
    /// - Parameter category: The category to filter by
    /// - Returns: Array of matching Chemical objects
    func fetchChemicals(byCategory category: String) -> [FROChemical] {
        let descriptor = FetchDescriptor<FROChemical>(
            predicate: #Predicate { $0.category == category },
            sortBy: [SortDescriptor(\.name)]
        )

        do {
            return try modelContext.fetch(descriptor)
        } catch {
            print("ChemicalService: Failed to fetch chemicals by category - \(error)")
            return []
        }
    }

    /// Fetches chemicals matching a name (exact match).
    /// - Parameter name: The chemical name to search for
    /// - Returns: Array of matching Chemical objects
    func fetchChemicals(byName name: String) -> [FROChemical] {
        let descriptor = FetchDescriptor<FROChemical>(
            predicate: #Predicate { $0.name == name }
        )

        do {
            return try modelContext.fetch(descriptor)
        } catch {
            print("ChemicalService: Failed to fetch chemicals by name - \(error)")
            return []
        }
    }

    // MARK: - Update

    /// Updates a chemical's properties and saves.
    /// - Parameters:
    ///   - chemical: The Chemical object to update
    ///   - name: New name (optional, keeps current if nil)
    ///   - category: New category (optional)
    ///   - size: New size (optional)
    ///   - spec: New spec (optional)
    ///   - notes: New notes (optional)
    func updateChemical(
        _ chemical: FROChemical,
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
            try modelContext.save()
            print("ChemicalService: Updated chemical '\(chemical.name)' successfully")
        } catch {
            print("ChemicalService: Failed to update chemical - \(error)")
        }
    }

    // MARK: - Delete

    /// Deletes a chemical from SwiftData and saves.
    /// - Parameter chemical: The Chemical object to delete
    func deleteChemical(_ chemical: FROChemical) {
        let name = chemical.name
        modelContext.delete(chemical)

        do {
            try modelContext.save()
            print("ChemicalService: Deleted chemical '\(name)' successfully")
        } catch {
            print("ChemicalService: Failed to delete chemical - \(error)")
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
            modelContext.delete(chemical)
            count += 1
        }

        if count > 0 {
            do {
                try modelContext.save()
                print("ChemicalService: Deleted \(count) chemical(s) named '\(name)'")
            } catch {
                print("ChemicalService: Failed to delete chemicals - \(error)")
            }
        }

        return count
    }
}

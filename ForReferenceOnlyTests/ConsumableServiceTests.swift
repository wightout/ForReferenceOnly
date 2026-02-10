import XCTest
import Foundation
import SwiftData
@testable import ForReferenceOnly

/// Tests for ConsumableService CRUD operations.
/// Tests operate on ModelContext directly since the service uses a non-injectable singleton.
@MainActor
final class ConsumableServiceTests: XCTestCase {

    private var container: ModelContainer!
    private var context: ModelContext!

    override func setUp() async throws {
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        container = try ModelContainer(
            for: FROJob.self, FROJobRevision.self, FROTool.self, FROToolGroup.self,
            FROToolKit.self, FROConsumable.self, FROChemical.self, FROPart.self,
            FROVoiceMemo.self, FROAttachment.self, FROImportStaging.self,
            configurations: config
        )
        context = container.mainContext
    }

    override func tearDown() async throws {
        container = nil
        context = nil
    }

    // MARK: - Create

    func testCreateConsumableDefaults() throws {
        let consumable = FROConsumable(name: "Safety Wire")
        context.insert(consumable)
        try context.save()

        XCTAssertEqual(consumable.name, "Safety Wire")
        XCTAssertEqual(consumable.category, "other")
        XCTAssertNil(consumable.size)
        XCTAssertNil(consumable.spec)
        XCTAssertNil(consumable.notes)
        XCTAssertTrue(consumable.isInGarage)
    }

    func testCreateConsumableAllFields() throws {
        let consumable = FROConsumable(
            name: "Cotter Pin",
            category: "cotter_pin",
            size: "3/32 x 1\"",
            spec: "AN381-3-16",
            notes: "Stock level: 50"
        )
        context.insert(consumable)
        try context.save()

        XCTAssertEqual(consumable.name, "Cotter Pin")
        XCTAssertEqual(consumable.category, "cotter_pin")
        XCTAssertEqual(consumable.size, "3/32 x 1\"")
        XCTAssertEqual(consumable.spec, "AN381-3-16")
        XCTAssertEqual(consumable.notes, "Stock level: 50")
    }

    // MARK: - Read: Fetch All Sorted

    func testFetchAllConsumablesSorted() throws {
        let c1 = FROConsumable(name: "Wire")
        let c2 = FROConsumable(name: "Cotter Pin")
        let c3 = FROConsumable(name: "O-Ring")
        [c1, c2, c3].forEach { context.insert($0) }
        try context.save()

        let descriptor = FetchDescriptor<FROConsumable>(sortBy: [SortDescriptor(\.name)])
        let all = try context.fetch(descriptor)
        XCTAssertEqual(all.count, 3)
        XCTAssertEqual(all[0].name, "Cotter Pin")
        XCTAssertEqual(all[1].name, "O-Ring")
        XCTAssertEqual(all[2].name, "Wire")
    }

    // MARK: - Read: By ID

    func testFetchConsumableById() throws {
        let id = UUID()
        let consumable = FROConsumable(id: id, name: "Safety Wire")
        context.insert(consumable)
        try context.save()

        var descriptor = FetchDescriptor<FROConsumable>(predicate: #Predicate { $0.id == id })
        descriptor.fetchLimit = 1
        let found = try context.fetch(descriptor).first
        XCTAssertNotNil(found)
        XCTAssertEqual(found?.name, "Safety Wire")
    }

    func testFetchConsumableByIdNotFound() throws {
        let consumable = FROConsumable(name: "Wire")
        context.insert(consumable)
        try context.save()

        let missingId = UUID()
        var descriptor = FetchDescriptor<FROConsumable>(predicate: #Predicate { $0.id == missingId })
        descriptor.fetchLimit = 1
        let found = try context.fetch(descriptor).first
        XCTAssertNil(found)
    }

    // MARK: - Read: By Category

    func testFetchConsumablesByCategory() throws {
        let c1 = FROConsumable(name: "Safety Wire", category: "safety_wire")
        let c2 = FROConsumable(name: "Lock Wire", category: "safety_wire")
        let c3 = FROConsumable(name: "O-Ring", category: "o_ring")
        [c1, c2, c3].forEach { context.insert($0) }
        try context.save()

        let cat = "safety_wire"
        let descriptor = FetchDescriptor<FROConsumable>(
            predicate: #Predicate { $0.category == cat },
            sortBy: [SortDescriptor(\.name)]
        )
        let found = try context.fetch(descriptor)
        XCTAssertEqual(found.count, 2)
    }

    // MARK: - Read: By Name

    func testFetchConsumablesByName() throws {
        let c1 = FROConsumable(name: "Safety Wire")
        let c2 = FROConsumable(name: "Safety Wire")
        let c3 = FROConsumable(name: "O-Ring")
        [c1, c2, c3].forEach { context.insert($0) }
        try context.save()

        let name = "Safety Wire"
        let descriptor = FetchDescriptor<FROConsumable>(predicate: #Predicate { $0.name == name })
        let found = try context.fetch(descriptor)
        XCTAssertEqual(found.count, 2)
    }

    // MARK: - Update

    func testUpdateConsumable() throws {
        let consumable = FROConsumable(name: "Wire", category: "other")
        context.insert(consumable)
        try context.save()

        consumable.name = "Safety Wire"
        consumable.category = "safety_wire"
        consumable.size = "0.032\""
        consumable.spec = "MS20995-C32"
        consumable.notes = "Updated notes"
        try context.save()

        XCTAssertEqual(consumable.name, "Safety Wire")
        XCTAssertEqual(consumable.category, "safety_wire")
        XCTAssertEqual(consumable.size, "0.032\"")
        XCTAssertEqual(consumable.spec, "MS20995-C32")
        XCTAssertEqual(consumable.notes, "Updated notes")
    }

    // MARK: - Delete

    func testDeleteConsumable() throws {
        let consumable = FROConsumable(name: "Wire")
        context.insert(consumable)
        try context.save()

        context.delete(consumable)
        try context.save()

        let descriptor = FetchDescriptor<FROConsumable>()
        let remaining = try context.fetch(descriptor)
        XCTAssertTrue(remaining.isEmpty)
    }

    func testDeleteConsumablesByName() throws {
        let c1 = FROConsumable(name: "Wire")
        let c2 = FROConsumable(name: "Wire")
        let c3 = FROConsumable(name: "O-Ring")
        [c1, c2, c3].forEach { context.insert($0) }
        try context.save()

        let name = "Wire"
        let nameDescriptor = FetchDescriptor<FROConsumable>(predicate: #Predicate { $0.name == name })
        let toDelete = try context.fetch(nameDescriptor)
        XCTAssertEqual(toDelete.count, 2)

        toDelete.forEach { context.delete($0) }
        try context.save()

        let allDescriptor = FetchDescriptor<FROConsumable>()
        let remaining = try context.fetch(allDescriptor)
        XCTAssertEqual(remaining.count, 1)
        XCTAssertEqual(remaining.first?.name, "O-Ring")
    }
}

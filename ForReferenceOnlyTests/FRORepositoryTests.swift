import XCTest
import Foundation
import SwiftData
@testable import ForReferenceOnly

@MainActor
final class FRORepositoryTests: XCTestCase {

    private var container: ModelContainer!
    private var repository: SwiftDataRepository!

    override func setUp() async throws {
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        container = try ModelContainer(
            for: FROJob.self, FROJobRevision.self, FROTool.self, FROToolGroup.self,
            FROToolKit.self, FROConsumable.self, FROChemical.self, FROPart.self,
            FROVoiceMemo.self, FROAttachment.self, FROImportStaging.self,
            configurations: config
        )
        repository = SwiftDataRepository(modelContext: container.mainContext)
    }

    override func tearDown() async throws {
        repository = nil
        container = nil
    }

    // MARK: - Insert + Fetch

    func testInsertAndFetch() throws {
        let tool = FROTool(name: "Screwdriver")
        repository.insert(tool)
        try repository.save()

        let tools = try repository.fetchAll(FROTool.self)
        XCTAssertEqual(tools.count, 1)
        XCTAssertEqual(tools.first?.name, "Screwdriver")
    }

    func testFetchWithSortDescriptor() throws {
        let tool1 = FROTool(name: "Wrench")
        let tool2 = FROTool(name: "Allen Key")
        repository.insert(tool1)
        repository.insert(tool2)
        try repository.save()

        let tools = try repository.fetchAll(FROTool.self, sortBy: [SortDescriptor(\.name)])
        XCTAssertEqual(tools.count, 2)
        XCTAssertEqual(tools[0].name, "Allen Key")
        XCTAssertEqual(tools[1].name, "Wrench")
    }

    // MARK: - Delete

    func testDelete() throws {
        let tool = FROTool(name: "Hammer")
        repository.insert(tool)
        try repository.save()

        repository.delete(tool)
        try repository.save()

        let tools = try repository.fetchAll(FROTool.self)
        XCTAssertTrue(tools.isEmpty)
    }

    // MARK: - FetchById

    func testFetchById() throws {
        let id = UUID()
        let tool = FROTool(id: id, name: "Pliers")
        repository.insert(tool)
        try repository.save()

        let found = try repository.fetchById(FROTool.self, id: id)
        XCTAssertNotNil(found)
        XCTAssertEqual(found?.name, "Pliers")
    }

    func testFetchByIdReturnsNilForMissingId() throws {
        let tool = FROTool(name: "Tape Measure")
        repository.insert(tool)
        try repository.save()

        let found = try repository.fetchById(FROTool.self, id: UUID())
        XCTAssertNil(found)
    }

    // MARK: - Predicate-based Fetch

    func testFetchWithPredicate() throws {
        let tool1 = FROTool(name: "Socket", ownershipType: "personal")
        let tool2 = FROTool(name: "Drill", ownershipType: "borrowed")
        repository.insert(tool1)
        repository.insert(tool2)
        try repository.save()

        let predicate = #Predicate<FROTool> { $0.ownershipType == "borrowed" }
        let borrowed = try repository.fetch(FROTool.self, predicate: predicate, sortBy: [])
        XCTAssertEqual(borrowed.count, 1)
        XCTAssertEqual(borrowed.first?.name, "Drill")
    }

    // MARK: - Multiple Entity Types

    func testMultipleEntityTypes() throws {
        let tool = FROTool(name: "Wrench")
        let consumable = FROConsumable(name: "Safety Wire")
        let chemical = FROChemical(name: "CRC")
        repository.insert(tool)
        repository.insert(consumable)
        repository.insert(chemical)
        try repository.save()

        let tools = try repository.fetchAll(FROTool.self)
        let consumables = try repository.fetchAll(FROConsumable.self)
        let chemicals = try repository.fetchAll(FROChemical.self)

        XCTAssertEqual(tools.count, 1)
        XCTAssertEqual(consumables.count, 1)
        XCTAssertEqual(chemicals.count, 1)
    }
}

import XCTest
import Foundation
import SwiftData
@testable import ForReferenceOnly

/// Tests for ToolService CRUD operations.
/// Since ToolService uses SharedModelContainer.shared.mainContext (singleton, not injectable),
/// tests operate on ModelContext directly, replicating service logic against in-memory containers.
@MainActor
final class ToolServiceTests: XCTestCase {

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

    func testCreateToolDefaults() throws {
        let tool = FROTool(name: "Screwdriver")
        context.insert(tool)
        try context.save()

        XCTAssertEqual(tool.name, "Screwdriver")
        XCTAssertEqual(tool.ownershipType, "personal")
        XCTAssertNil(tool.borrowedFrom)
        XCTAssertNil(tool.notes)
        XCTAssertNil(tool.aliases)
        XCTAssertTrue(tool.isInGarage)
    }

    func testCreateToolAllFields() throws {
        let tool = FROTool(
            name: "Torque Wrench",
            aliases: ["TW-1", "Big Torque"],
            ownershipType: "borrowed",
            borrowedFrom: "Shop A",
            notes: "Calibrated 2024"
        )
        context.insert(tool)
        try context.save()

        XCTAssertEqual(tool.name, "Torque Wrench")
        XCTAssertEqual(tool.aliases, ["TW-1", "Big Torque"])
        XCTAssertEqual(tool.ownershipType, "borrowed")
        XCTAssertEqual(tool.borrowedFrom, "Shop A")
        XCTAssertEqual(tool.notes, "Calibrated 2024")
    }

    func testCreateToolPersists() throws {
        let tool = FROTool(name: "Hammer")
        context.insert(tool)
        try context.save()

        let descriptor = FetchDescriptor<FROTool>()
        let fetched = try context.fetch(descriptor)
        XCTAssertEqual(fetched.count, 1)
        XCTAssertEqual(fetched.first?.name, "Hammer")
    }

    // MARK: - Read: Sorted Fetch

    func testFetchAllToolsSortedByName() throws {
        let t1 = FROTool(name: "Wrench")
        let t2 = FROTool(name: "Allen Key")
        let t3 = FROTool(name: "Socket")
        [t1, t2, t3].forEach { context.insert($0) }
        try context.save()

        let descriptor = FetchDescriptor<FROTool>(sortBy: [SortDescriptor(\.name)])
        let tools = try context.fetch(descriptor)
        XCTAssertEqual(tools.count, 3)
        XCTAssertEqual(tools[0].name, "Allen Key")
        XCTAssertEqual(tools[1].name, "Socket")
        XCTAssertEqual(tools[2].name, "Wrench")
    }

    // MARK: - Read: By ID

    func testFetchToolByIdFound() throws {
        let id = UUID()
        let tool = FROTool(id: id, name: "Pliers")
        context.insert(tool)
        try context.save()

        var descriptor = FetchDescriptor<FROTool>(predicate: #Predicate { $0.id == id })
        descriptor.fetchLimit = 1
        let found = try context.fetch(descriptor).first
        XCTAssertNotNil(found)
        XCTAssertEqual(found?.name, "Pliers")
    }

    func testFetchToolByIdNotFound() throws {
        let tool = FROTool(name: "Pliers")
        context.insert(tool)
        try context.save()

        let missingId = UUID()
        var descriptor = FetchDescriptor<FROTool>(predicate: #Predicate { $0.id == missingId })
        descriptor.fetchLimit = 1
        let found = try context.fetch(descriptor).first
        XCTAssertNil(found)
    }

    // MARK: - Read: By Name

    func testFetchToolsByNameMatch() throws {
        let t1 = FROTool(name: "Socket")
        let t2 = FROTool(name: "Socket")
        let t3 = FROTool(name: "Wrench")
        [t1, t2, t3].forEach { context.insert($0) }
        try context.save()

        let name = "Socket"
        let descriptor = FetchDescriptor<FROTool>(predicate: #Predicate { $0.name == name })
        let found = try context.fetch(descriptor)
        XCTAssertEqual(found.count, 2)
    }

    func testFetchToolsByNameNoMatch() throws {
        let tool = FROTool(name: "Hammer")
        context.insert(tool)
        try context.save()

        let name = "Socket"
        let descriptor = FetchDescriptor<FROTool>(predicate: #Predicate { $0.name == name })
        let found = try context.fetch(descriptor)
        XCTAssertTrue(found.isEmpty)
    }

    // MARK: - Update

    func testUpdateToolName() throws {
        let tool = FROTool(name: "Old Name")
        context.insert(tool)
        try context.save()

        tool.name = "New Name"
        try context.save()

        let descriptor = FetchDescriptor<FROTool>()
        let fetched = try context.fetch(descriptor)
        XCTAssertEqual(fetched.first?.name, "New Name")
    }

    func testUpdateToolOwnershipType() throws {
        let tool = FROTool(name: "Socket", ownershipType: "personal")
        context.insert(tool)
        try context.save()

        tool.ownershipType = "borrowed"
        tool.borrowedFrom = "Shop B"
        try context.save()

        XCTAssertEqual(tool.ownershipType, "borrowed")
        XCTAssertEqual(tool.borrowedFrom, "Shop B")
    }

    func testUpdateToolAliases() throws {
        let tool = FROTool(name: "Socket")
        context.insert(tool)
        try context.save()

        tool.aliases = ["10mm Deep Socket", "Deep Socket"]
        try context.save()

        XCTAssertEqual(tool.aliases?.count, 2)
        XCTAssertEqual(tool.aliases?[0], "10mm Deep Socket")
    }

    // MARK: - Delete

    func testDeleteSingleTool() throws {
        let tool = FROTool(name: "Hammer")
        context.insert(tool)
        try context.save()

        context.delete(tool)
        try context.save()

        let descriptor = FetchDescriptor<FROTool>()
        let remaining = try context.fetch(descriptor)
        XCTAssertTrue(remaining.isEmpty)
    }

    func testDeleteToolsByNameWithCount() throws {
        let t1 = FROTool(name: "Socket")
        let t2 = FROTool(name: "Socket")
        let t3 = FROTool(name: "Wrench")
        [t1, t2, t3].forEach { context.insert($0) }
        try context.save()

        let name = "Socket"
        let nameDescriptor = FetchDescriptor<FROTool>(predicate: #Predicate { $0.name == name })
        let toDelete = try context.fetch(nameDescriptor)
        XCTAssertEqual(toDelete.count, 2)

        toDelete.forEach { context.delete($0) }
        try context.save()

        let allDescriptor = FetchDescriptor<FROTool>()
        let remaining = try context.fetch(allDescriptor)
        XCTAssertEqual(remaining.count, 1)
        XCTAssertEqual(remaining.first?.name, "Wrench")
    }

    // MARK: - Mark As Purchased

    func testMarkAsPurchasedConvertsBorrowedToPersonal() throws {
        let tool = FROTool(name: "Torque Wrench", ownershipType: "borrowed", borrowedFrom: "Shop A")
        context.insert(tool)
        try context.save()

        tool.ownershipType = "personal"
        tool.borrowedFrom = nil
        try context.save()

        XCTAssertEqual(tool.ownershipType, "personal")
        XCTAssertNil(tool.borrowedFrom)
    }

    // MARK: - Smart Delete Logic

    func testSmartDeleteNoJobRefsHardDeletes() throws {
        let tool = FROTool(name: "Socket")
        context.insert(tool)
        try context.save()

        // No job references — should be safe to hard delete
        let jobCount = tool.jobRecords?.count ?? 0
        XCTAssertEqual(jobCount, 0)

        context.delete(tool)
        try context.save()

        let descriptor = FetchDescriptor<FROTool>()
        let remaining = try context.fetch(descriptor)
        XCTAssertTrue(remaining.isEmpty)
    }

    func testSmartDeleteWithJobRefsConvertsToBorrowed() throws {
        let tool = FROTool(name: "3/8\"", ownershipType: "personal")
        context.insert(tool)

        let group = FROToolGroup(name: "Sockets", toolType: "Socket")
        context.insert(group)
        tool.group = group

        let job = FROJob(aircraftType: "CH-47", system: "Hydraulic")
        context.insert(job)
        if job.tools == nil { job.tools = [] }
        job.tools?.append(tool)

        try context.save()

        // Should have job references
        let jobCount = tool.jobRecords?.count ?? 0
        XCTAssertGreaterThan(jobCount, 0)

        // Replicate smartDeleteTool logic: convert to borrowed
        let originalName = tool.name
        var updatedName = originalName
        if let grp = tool.group, let type = grp.toolType, !type.isEmpty {
            updatedName = "\(originalName) \(type)"
        }

        tool.ownershipType = "borrowed"
        tool.borrowedFrom = nil
        tool.name = updatedName
        tool.group = nil
        try context.save()

        XCTAssertEqual(tool.ownershipType, "borrowed")
        XCTAssertEqual(tool.name, "3/8\" Socket")
        XCTAssertNil(tool.group)
    }

    func testSmartDeleteNameFromGroupToolType() throws {
        let tool = FROTool(name: "10mm")
        context.insert(tool)

        let group = FROToolGroup(name: "Wrenches", toolType: "Wrench")
        context.insert(group)
        tool.group = group

        try context.save()

        // Build name using group's toolType
        var updatedName = tool.name
        if let grp = tool.group, let type = grp.toolType, !type.isEmpty {
            updatedName = "\(tool.name) \(type)"
        }

        XCTAssertEqual(updatedName, "10mm Wrench")
    }

    func testSmartDeleteRemovesFromKits() throws {
        let tool = FROTool(name: "10mm Socket")
        context.insert(tool)

        let kit = FROToolKit(name: "Metric Kit", toolType: "Socket")
        context.insert(kit)
        if kit.tools == nil { kit.tools = [] }
        kit.tools?.append(tool)

        try context.save()

        XCTAssertEqual(tool.toolKits?.count ?? 0, 1)

        // Replicate: remove from kits
        tool.toolKits = []
        try context.save()

        XCTAssertEqual(tool.toolKits?.count ?? 0, 0)
    }
}

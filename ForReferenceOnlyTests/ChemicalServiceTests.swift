import XCTest
import Foundation
import SwiftData
@testable import ForReferenceOnly

/// Tests for ChemicalService CRUD operations.
/// Tests operate on ModelContext directly since the service uses a non-injectable singleton.
@MainActor
final class ChemicalServiceTests: XCTestCase {

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

    func testCreateChemicalDefaults() throws {
        let chemical = FROChemical(name: "CRC")
        context.insert(chemical)
        try context.save()

        XCTAssertEqual(chemical.name, "CRC")
        XCTAssertEqual(chemical.category, "other")
        XCTAssertNil(chemical.size)
        XCTAssertNil(chemical.spec)
        XCTAssertNil(chemical.notes)
        XCTAssertTrue(chemical.isInGarage)
    }

    func testCreateChemicalAllFields() throws {
        let chemical = FROChemical(
            name: "Hydraulic Fluid",
            category: "fluid",
            size: "1 Quart",
            spec: "MIL-PRF-83282",
            notes: "Store at room temp"
        )
        context.insert(chemical)
        try context.save()

        XCTAssertEqual(chemical.name, "Hydraulic Fluid")
        XCTAssertEqual(chemical.category, "fluid")
        XCTAssertEqual(chemical.size, "1 Quart")
        XCTAssertEqual(chemical.spec, "MIL-PRF-83282")
        XCTAssertEqual(chemical.notes, "Store at room temp")
    }

    func testCreateChemicalFluidCategory() throws {
        let chemical = FROChemical(name: "Engine Oil", category: "fluid")
        context.insert(chemical)
        try context.save()
        XCTAssertEqual(chemical.category, "fluid")
    }

    func testCreateChemicalLubricantCategory() throws {
        let chemical = FROChemical(name: "Grease", category: "lubricant")
        context.insert(chemical)
        try context.save()
        XCTAssertEqual(chemical.category, "lubricant")
    }

    func testCreateChemicalCleanerCategory() throws {
        let chemical = FROChemical(name: "MEK", category: "cleaner")
        context.insert(chemical)
        try context.save()
        XCTAssertEqual(chemical.category, "cleaner")
    }

    func testCreateChemicalSealantCategory() throws {
        let chemical = FROChemical(name: "PR-1422", category: "sealant")
        context.insert(chemical)
        try context.save()
        XCTAssertEqual(chemical.category, "sealant")
    }

    // MARK: - Read: Fetch All Sorted

    func testFetchAllChemicalsSorted() throws {
        let c1 = FROChemical(name: "WD-40")
        let c2 = FROChemical(name: "CRC")
        let c3 = FROChemical(name: "Hydraulic Fluid")
        [c1, c2, c3].forEach { context.insert($0) }
        try context.save()

        let descriptor = FetchDescriptor<FROChemical>(sortBy: [SortDescriptor(\.name)])
        let all = try context.fetch(descriptor)
        XCTAssertEqual(all.count, 3)
        XCTAssertEqual(all[0].name, "CRC")
        XCTAssertEqual(all[1].name, "Hydraulic Fluid")
        XCTAssertEqual(all[2].name, "WD-40")
    }

    // MARK: - Read: By ID

    func testFetchChemicalById() throws {
        let id = UUID()
        let chemical = FROChemical(id: id, name: "CRC")
        context.insert(chemical)
        try context.save()

        var descriptor = FetchDescriptor<FROChemical>(predicate: #Predicate { $0.id == id })
        descriptor.fetchLimit = 1
        let found = try context.fetch(descriptor).first
        XCTAssertNotNil(found)
        XCTAssertEqual(found?.name, "CRC")
    }

    // MARK: - Read: By Category

    func testFetchChemicalsByCategory() throws {
        let c1 = FROChemical(name: "Hydraulic Fluid", category: "fluid")
        let c2 = FROChemical(name: "Engine Oil", category: "fluid")
        let c3 = FROChemical(name: "CRC", category: "cleaner")
        [c1, c2, c3].forEach { context.insert($0) }
        try context.save()

        let cat = "fluid"
        let descriptor = FetchDescriptor<FROChemical>(
            predicate: #Predicate { $0.category == cat },
            sortBy: [SortDescriptor(\.name)]
        )
        let found = try context.fetch(descriptor)
        XCTAssertEqual(found.count, 2)
        XCTAssertEqual(found[0].name, "Engine Oil")
        XCTAssertEqual(found[1].name, "Hydraulic Fluid")
    }

    // MARK: - Read: By Name

    func testFetchChemicalsByName() throws {
        let c1 = FROChemical(name: "CRC")
        let c2 = FROChemical(name: "CRC")
        let c3 = FROChemical(name: "WD-40")
        [c1, c2, c3].forEach { context.insert($0) }
        try context.save()

        let name = "CRC"
        let descriptor = FetchDescriptor<FROChemical>(predicate: #Predicate { $0.name == name })
        let found = try context.fetch(descriptor)
        XCTAssertEqual(found.count, 2)
    }

    // MARK: - Update

    func testUpdateChemical() throws {
        let chemical = FROChemical(name: "CRC", category: "other")
        context.insert(chemical)
        try context.save()

        chemical.name = "CRC 5-56"
        chemical.category = "lubricant"
        chemical.size = "16oz"
        chemical.spec = "CRC-5005"
        chemical.notes = "Multi-purpose"
        try context.save()

        XCTAssertEqual(chemical.name, "CRC 5-56")
        XCTAssertEqual(chemical.category, "lubricant")
        XCTAssertEqual(chemical.size, "16oz")
        XCTAssertEqual(chemical.spec, "CRC-5005")
        XCTAssertEqual(chemical.notes, "Multi-purpose")
    }

    // MARK: - Delete

    func testDeleteChemical() throws {
        let chemical = FROChemical(name: "CRC")
        context.insert(chemical)
        try context.save()

        context.delete(chemical)
        try context.save()

        let descriptor = FetchDescriptor<FROChemical>()
        let remaining = try context.fetch(descriptor)
        XCTAssertTrue(remaining.isEmpty)
    }

    func testDeleteChemicalsByName() throws {
        let c1 = FROChemical(name: "CRC")
        let c2 = FROChemical(name: "CRC")
        let c3 = FROChemical(name: "WD-40")
        [c1, c2, c3].forEach { context.insert($0) }
        try context.save()

        let name = "CRC"
        let nameDescriptor = FetchDescriptor<FROChemical>(predicate: #Predicate { $0.name == name })
        let toDelete = try context.fetch(nameDescriptor)
        XCTAssertEqual(toDelete.count, 2)

        toDelete.forEach { context.delete($0) }
        try context.save()

        let allDescriptor = FetchDescriptor<FROChemical>()
        let remaining = try context.fetch(allDescriptor)
        XCTAssertEqual(remaining.count, 1)
        XCTAssertEqual(remaining.first?.name, "WD-40")
    }
}

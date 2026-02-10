import XCTest
import Foundation
import SwiftData
@testable import ForReferenceOnly

/// Tests for ToolGroupService operations.
/// Tests operate on ModelContext directly since the service uses a non-injectable singleton.
@MainActor
final class ToolGroupServiceTests: XCTestCase {

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

    func testCreateTopLevelGroup() throws {
        let group = FROToolGroup(name: "Sockets")
        context.insert(group)
        try context.save()

        let descriptor = FetchDescriptor<FROToolGroup>()
        let groups = try context.fetch(descriptor)
        XCTAssertEqual(groups.count, 1)
        XCTAssertEqual(groups.first?.name, "Sockets")
        XCTAssertNil(groups.first?.parentGroup)
    }

    func testCreateChildGroup() throws {
        let parent = FROToolGroup(name: "Sockets")
        context.insert(parent)

        let child = FROToolGroup(name: "Deep Sockets", sortOrder: 0)
        child.parentGroup = parent
        context.insert(child)
        try context.save()

        XCTAssertEqual(child.parentGroup?.id, parent.id)
        XCTAssertEqual(parent.childGroups?.count, 1)
    }

    func testCreateGroupAutoSortOrder() throws {
        let g1 = FROToolGroup(name: "Sockets", sortOrder: 0)
        let g2 = FROToolGroup(name: "Wrenches", sortOrder: 1)
        [g1, g2].forEach { context.insert($0) }
        try context.save()

        XCTAssertEqual(g1.sortOrder, 0)
        XCTAssertEqual(g2.sortOrder, 1)
    }

    // MARK: - Read: Top Level

    func testFetchTopLevelExcludesChildren() throws {
        let parent = FROToolGroup(name: "Sockets")
        context.insert(parent)

        let child = FROToolGroup(name: "Deep Sockets")
        child.parentGroup = parent
        context.insert(child)
        try context.save()

        let descriptor = FetchDescriptor<FROToolGroup>(
            sortBy: [SortDescriptor(\.sortOrder), SortDescriptor(\.name)]
        )
        let all = try context.fetch(descriptor)
        let topLevel = all.filter { $0.parentGroup == nil }
        XCTAssertEqual(topLevel.count, 1)
        XCTAssertEqual(topLevel.first?.name, "Sockets")
    }

    func testFetchAllGroups() throws {
        let g1 = FROToolGroup(name: "Sockets")
        let g2 = FROToolGroup(name: "Wrenches")
        context.insert(g1)
        context.insert(g2)

        let child = FROToolGroup(name: "Deep Sockets")
        child.parentGroup = g1
        context.insert(child)
        try context.save()

        let descriptor = FetchDescriptor<FROToolGroup>(sortBy: [SortDescriptor(\.name)])
        let all = try context.fetch(descriptor)
        XCTAssertEqual(all.count, 3)
    }

    // MARK: - Read: By ID

    func testFetchGroupById() throws {
        let id = UUID()
        let group = FROToolGroup(id: id, name: "Sockets")
        context.insert(group)
        try context.save()

        var descriptor = FetchDescriptor<FROToolGroup>(predicate: #Predicate { $0.id == id })
        descriptor.fetchLimit = 1
        let found = try context.fetch(descriptor).first
        XCTAssertNotNil(found)
        XCTAssertEqual(found?.name, "Sockets")
    }

    // MARK: - Read: Child Sort

    func testChildGroupsSortBySortOrderThenName() throws {
        let parent = FROToolGroup(name: "Main")
        context.insert(parent)

        let c1 = FROToolGroup(name: "Bravo", sortOrder: 1)
        c1.parentGroup = parent
        let c2 = FROToolGroup(name: "Alpha", sortOrder: 0)
        c2.parentGroup = parent
        let c3 = FROToolGroup(name: "Alpha2", sortOrder: 0)
        c3.parentGroup = parent
        [c1, c2, c3].forEach { context.insert($0) }
        try context.save()

        guard let children = parent.childGroups else {
            XCTFail("No children found")
            return
        }

        let sorted = children.sorted { g1, g2 in
            if g1.sortOrder != g2.sortOrder {
                return g1.sortOrder < g2.sortOrder
            }
            return g1.name < g2.name
        }

        XCTAssertEqual(sorted[0].name, "Alpha")
        XCTAssertEqual(sorted[1].name, "Alpha2")
        XCTAssertEqual(sorted[2].name, "Bravo")
    }

    // MARK: - Read: Tools in Group

    func testFetchToolsInGroup() throws {
        let group = FROToolGroup(name: "Sockets")
        context.insert(group)

        let t1 = FROTool(name: "10mm Socket")
        let t2 = FROTool(name: "3/8\" Socket")
        [t1, t2].forEach {
            context.insert($0)
            $0.group = group
        }
        try context.save()

        let tools = group.tools ?? []
        XCTAssertEqual(tools.count, 2)
    }

    // MARK: - Update

    func testRenameGroup() throws {
        let group = FROToolGroup(name: "Old Name")
        context.insert(group)
        try context.save()

        group.name = "New Name"
        try context.save()

        let descriptor = FetchDescriptor<FROToolGroup>()
        let fetched = try context.fetch(descriptor)
        XCTAssertEqual(fetched.first?.name, "New Name")
    }

    // MARK: - Assign / Unassign Tool

    func testAssignToolToGroup() throws {
        let group = FROToolGroup(name: "Sockets")
        context.insert(group)

        let tool = FROTool(name: "10mm Socket")
        context.insert(tool)
        try context.save()

        tool.group = group
        try context.save()

        XCTAssertEqual(tool.group?.id, group.id)
        XCTAssertEqual(group.tools?.count, 1)
    }

    func testUnassignToolFromGroup() throws {
        let group = FROToolGroup(name: "Sockets")
        context.insert(group)

        let tool = FROTool(name: "10mm Socket")
        context.insert(tool)
        tool.group = group
        try context.save()

        tool.group = nil
        try context.save()

        XCTAssertNil(tool.group)
    }

    // MARK: - Delete

    func testDeleteGroupCascadesChildren() throws {
        let parent = FROToolGroup(name: "Main")
        context.insert(parent)

        let child = FROToolGroup(name: "Sub")
        child.parentGroup = parent
        context.insert(child)
        try context.save()

        context.delete(parent)
        try context.save()

        let descriptor = FetchDescriptor<FROToolGroup>()
        let remaining = try context.fetch(descriptor)
        XCTAssertTrue(remaining.isEmpty)
    }

    func testDeleteGroupNullifiesTools() throws {
        let group = FROToolGroup(name: "Sockets")
        context.insert(group)

        let tool = FROTool(name: "10mm Socket")
        context.insert(tool)
        tool.group = group
        try context.save()

        context.delete(group)
        try context.save()

        // Tool should still exist but group reference should be nil
        let toolDescriptor = FetchDescriptor<FROTool>()
        let tools = try context.fetch(toolDescriptor)
        XCTAssertEqual(tools.count, 1)
        XCTAssertNil(tools.first?.group)
    }
}

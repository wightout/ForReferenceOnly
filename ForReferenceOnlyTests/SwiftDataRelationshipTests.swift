import XCTest
import Foundation
import SwiftData
@testable import ForReferenceOnly

@MainActor
final class SwiftDataRelationshipTests: XCTestCase {

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

    // MARK: - Tool <-> ToolGroup

    func testToolGroupAssignment() throws {
        let group = FROToolGroup(name: "Wrenches")
        let tool = FROTool(name: "10mm Wrench")
        context.insert(group)
        context.insert(tool)
        tool.group = group
        try context.save()

        XCTAssertEqual(tool.group?.id, group.id)
        XCTAssertTrue(group.tools?.contains(where: { $0.id == tool.id }) ?? false)
    }

    func testDeletingToolGroupDoesNotDeleteTools() throws {
        let group = FROToolGroup(name: "Sockets")
        let tool = FROTool(name: "12mm Socket")
        context.insert(group)
        context.insert(tool)
        tool.group = group
        try context.save()

        let toolId = tool.id

        // Delete the group
        context.delete(group)
        try context.save()

        // Tool should still exist with group nullified
        let descriptor = FetchDescriptor<FROTool>()
        let tools = try context.fetch(descriptor)
        let survivingTool = tools.first { $0.id == toolId }
        XCTAssertNotNil(survivingTool, "Tool should survive group deletion")
        XCTAssertNil(survivingTool?.group, "Tool's group reference should be nil")
    }

    // MARK: - Tool <-> ToolKit (many-to-many)

    func testToolKitManyToMany() throws {
        let kit = FROToolKit(name: "Engine Kit")
        let tool1 = FROTool(name: "Torque Wrench")
        let tool2 = FROTool(name: "Socket Set")
        context.insert(kit)
        context.insert(tool1)
        context.insert(tool2)
        kit.tools = [tool1, tool2]
        try context.save()

        XCTAssertEqual(kit.tools?.count, 2)
        XCTAssertTrue(tool1.toolKits?.contains(where: { $0.id == kit.id }) ?? false)
        XCTAssertTrue(tool2.toolKits?.contains(where: { $0.id == kit.id }) ?? false)
    }

    // MARK: - ToolGroup -> childGroups (cascade)

    func testToolGroupChildGroupsCascadeDelete() throws {
        let parent = FROToolGroup(name: "SAE Wrenches")
        let child = FROToolGroup(name: "Standard")
        context.insert(parent)
        context.insert(child)
        child.parentGroup = parent
        try context.save()

        let childId = child.id

        // Delete parent - child should cascade
        context.delete(parent)
        try context.save()

        let descriptor = FetchDescriptor<FROToolGroup>()
        let groups = try context.fetch(descriptor)
        let survivingChild = groups.first { $0.id == childId }
        XCTAssertNil(survivingChild, "Child group should be cascade-deleted with parent")
    }

    // MARK: - Job -> Revisions (cascade)

    func testJobRevisionsCascadeDelete() throws {
        let job = FROJob(aircraftType: "CH-47", system: "Hydraulic")
        let revision = FROJobRevision(versionNumber: 1, editNotes: "Initial")
        context.insert(job)
        context.insert(revision)
        revision.jobRecord = job
        try context.save()

        let revisionId = revision.id

        context.delete(job)
        try context.save()

        let descriptor = FetchDescriptor<FROJobRevision>()
        let revisions = try context.fetch(descriptor)
        let survivingRevision = revisions.first { $0.id == revisionId }
        XCTAssertNil(survivingRevision, "Revision should be cascade-deleted with job")
    }

    // MARK: - Job -> VoiceMemo (cascade)

    func testJobVoiceMemoCascadeDelete() throws {
        let job = FROJob(aircraftType: "UH-60", system: "Electrical")
        let memo = FROVoiceMemo(transcriptionText: "Replace relay", transcriptionStatus: "completed")
        context.insert(job)
        context.insert(memo)
        job.voiceMemo = memo
        try context.save()

        let memoId = memo.id

        context.delete(job)
        try context.save()

        let descriptor = FetchDescriptor<FROVoiceMemo>()
        let memos = try context.fetch(descriptor)
        let survivingMemo = memos.first { $0.id == memoId }
        XCTAssertNil(survivingMemo, "Voice memo should be cascade-deleted with job")
    }

    // MARK: - Job -> Tools (nullify)

    func testJobToolsNullifyOnDelete() throws {
        let job = FROJob(aircraftType: "C-130", system: "Engines")
        let tool = FROTool(name: "Borescope")
        context.insert(job)
        context.insert(tool)
        job.tools = [tool]
        try context.save()

        let toolId = tool.id

        context.delete(job)
        try context.save()

        let descriptor = FetchDescriptor<FROTool>()
        let tools = try context.fetch(descriptor)
        let survivingTool = tools.first { $0.id == toolId }
        XCTAssertNotNil(survivingTool, "Tool should survive job deletion")
    }

    // MARK: - Job -> Consumables (nullify)

    func testJobConsumablesNullifyOnDelete() throws {
        let job = FROJob(aircraftType: "F-16", system: "Avionics")
        let consumable = FROConsumable(name: "Wire Ties")
        context.insert(job)
        context.insert(consumable)
        job.consumables = [consumable]
        try context.save()

        let consumableId = consumable.id

        context.delete(job)
        try context.save()

        let descriptor = FetchDescriptor<FROConsumable>()
        let consumables = try context.fetch(descriptor)
        let surviving = consumables.first { $0.id == consumableId }
        XCTAssertNotNil(surviving, "Consumable should survive job deletion")
    }

    // MARK: - Job -> Chemicals (nullify)

    func testJobChemicalsNullifyOnDelete() throws {
        let job = FROJob(aircraftType: "AH-64", system: "Weapons")
        let chemical = FROChemical(name: "MIL-PRF-81309")
        context.insert(job)
        context.insert(chemical)
        job.chemicals = [chemical]
        try context.save()

        let chemicalId = chemical.id

        context.delete(job)
        try context.save()

        let descriptor = FetchDescriptor<FROChemical>()
        let chemicals = try context.fetch(descriptor)
        let surviving = chemicals.first { $0.id == chemicalId }
        XCTAssertNotNil(surviving, "Chemical should survive job deletion")
    }

    // MARK: - Job -> Parts (nullify)

    func testJobPartsNullifyOnDelete() throws {
        let job = FROJob(aircraftType: "V-22", system: "Flight Controls")
        let part = FROPart(partNumber: "PN-001", nomenclature: "Actuator")
        context.insert(job)
        context.insert(part)
        job.parts = [part]
        try context.save()

        let partId = part.id

        context.delete(job)
        try context.save()

        let descriptor = FetchDescriptor<FROPart>()
        let parts = try context.fetch(descriptor)
        let surviving = parts.first { $0.id == partId }
        XCTAssertNotNil(surviving, "Part should survive job deletion")
    }
}

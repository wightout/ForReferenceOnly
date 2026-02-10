import XCTest
import Foundation
import SwiftData
@testable import ForReferenceOnly

/// Tests round-trip fidelity for ImportExportService:
/// export all data -> import to a fresh database -> verify everything matches.
@MainActor
final class ImportExportRoundTripTests: XCTestCase {

    private var sourceContainer: ModelContainer!
    private var sourceRepo: SwiftDataRepository!

    private var destContainer: ModelContainer!
    private var destRepo: SwiftDataRepository!

    private let service = ImportExportService.shared

    override func setUp() async throws {
        let config1 = ModelConfiguration(isStoredInMemoryOnly: true)
        sourceContainer = try ModelContainer(
            for: FROJob.self, FROJobRevision.self, FROTool.self, FROToolGroup.self,
            FROToolKit.self, FROConsumable.self, FROChemical.self, FROPart.self,
            FROVoiceMemo.self, FROAttachment.self, FROImportStaging.self,
            configurations: config1
        )
        sourceRepo = SwiftDataRepository(modelContext: sourceContainer.mainContext)

        let config2 = ModelConfiguration(isStoredInMemoryOnly: true)
        destContainer = try ModelContainer(
            for: FROJob.self, FROJobRevision.self, FROTool.self, FROToolGroup.self,
            FROToolKit.self, FROConsumable.self, FROChemical.self, FROPart.self,
            FROVoiceMemo.self, FROAttachment.self, FROImportStaging.self,
            configurations: config2
        )
        destRepo = SwiftDataRepository(modelContext: destContainer.mainContext)
    }

    override func tearDown() async throws {
        sourceRepo = nil
        sourceContainer = nil
        destRepo = nil
        destContainer = nil
    }

    // MARK: - Helpers

    /// Seeds the source database with a set of interconnected entities.
    /// Returns the UUIDs of all created entities for verification.
    private func seedSourceData() throws -> SeedData {
        // Create tool groups with hierarchy: parentGroup -> childGroup
        let parentGroup = FROToolGroup(
            name: "Wrenches",
            sortOrder: 0,
            ownershipType: "personal",
            toolType: "wrench",
            measurementType: "sae"
        )
        sourceRepo.insert(parentGroup)

        let childGroup = FROToolGroup(
            name: "Combination Wrenches",
            sortOrder: 1,
            ownershipType: "personal",
            toolType: "wrench",
            measurementType: "sae"
        )
        childGroup.parentGroup = parentGroup
        sourceRepo.insert(childGroup)

        // Create a tool kit
        let kit = FROToolKit(
            name: "Engine Kit",
            descriptionText: "Tools for engine work",
            ownershipType: "personal",
            toolType: "mixed"
        )
        sourceRepo.insert(kit)

        // Create tools — one in the child group and kit, one standalone
        let tool1 = FROTool(
            name: "1/2\" Combination Wrench",
            aliases: ["half-inch wrench"],
            ownershipType: "personal",
            notes: "SAE standard",
            isInGarage: true,
            photoFileNames: ["photo_0.jpg"]
        )
        tool1.group = childGroup
        tool1.toolKits = [kit]
        sourceRepo.insert(tool1)

        let tool2 = FROTool(
            name: "Torque Wrench",
            ownershipType: "borrowed",
            borrowedFrom: "Shop A",
            isInGarage: true
        )
        sourceRepo.insert(tool2)

        // Create consumables
        let consumable = FROConsumable(
            name: "Safety Wire",
            category: "hardware",
            size: "0.032",
            spec: "MS20995C32",
            notes: "Stainless steel"
        )
        sourceRepo.insert(consumable)

        // Create chemicals
        let chemical = FROChemical(
            name: "CRC 5-56",
            category: "lubricant",
            spec: "MIL-PRF-3150"
        )
        sourceRepo.insert(chemical)

        // Create parts
        let part = FROPart(
            partNumber: "MS24665-132",
            nomenclature: "Cotter Pin",
            nsn: "5315-00-007-0532",
            quantity: 10,
            unitOfMeasure: "EA"
        )
        sourceRepo.insert(part)

        // Create a job with relationships
        let job = FROJob(
            aircraftType: "UH-60L",
            aircraftSerialNumber: "85-24389",
            nNumber: nil,
            system: "Main Rotor",
            component: "Blade Grips",
            taskDescription: "Inspect and lubricate blade grip bearings",
            tmReferences: "TM 1-1520-237-23",
            notes: "All bearings serviceable"
        )
        job.tools = [tool1, tool2]
        job.consumables = [consumable]
        job.chemicals = [chemical]
        job.parts = [part]
        sourceRepo.insert(job)

        // Create a revision for the job
        let revision = FROJobRevision(
            versionNumber: 1,
            editNotes: "Initial entry"
        )
        revision.jobRecord = job
        sourceRepo.insert(revision)

        try sourceRepo.save()

        return SeedData(
            parentGroupId: parentGroup.id,
            childGroupId: childGroup.id,
            kitId: kit.id,
            tool1Id: tool1.id,
            tool2Id: tool2.id,
            consumableId: consumable.id,
            chemicalId: chemical.id,
            partId: part.id,
            jobId: job.id,
            revisionId: revision.id
        )
    }

    struct SeedData {
        let parentGroupId: UUID
        let childGroupId: UUID
        let kitId: UUID
        let tool1Id: UUID
        let tool2Id: UUID
        let consumableId: UUID
        let chemicalId: UUID
        let partId: UUID
        let jobId: UUID
        let revisionId: UUID
    }

    /// Exports from sourceRepo, imports to destRepo, commits the import.
    private func performRoundTrip() throws -> SeedData {
        let seed = try seedSourceData()

        // Export
        guard let exportURL = service.exportBackup(repository: sourceRepo) else {
            XCTFail("Export returned nil")
            return seed
        }

        // Import to dest
        let sessionId = try service.parseBackup(at: exportURL, repository: destRepo)

        // Commit (no conflicts since dest is empty)
        try service.commitImport(sessionId: sessionId, repository: destRepo)

        // Clean up temp file
        try? FileManager.default.removeItem(at: exportURL)

        return seed
    }

    // MARK: - Round-Trip Entity Count Tests

    func testRoundTripPreservesEntityCounts() throws {
        _ = try performRoundTrip()

        let tools = try destRepo.fetchAll(FROTool.self)
        let groups = try destRepo.fetchAll(FROToolGroup.self)
        let kits = try destRepo.fetchAll(FROToolKit.self)
        let consumables = try destRepo.fetchAll(FROConsumable.self)
        let chemicals = try destRepo.fetchAll(FROChemical.self)
        let parts = try destRepo.fetchAll(FROPart.self)
        let jobs = try destRepo.fetchAll(FROJob.self)
        let revisions = try destRepo.fetchAll(FROJobRevision.self)

        XCTAssertEqual(tools.count, 2, "Should have 2 tools")
        XCTAssertEqual(groups.count, 2, "Should have 2 tool groups")
        XCTAssertEqual(kits.count, 1, "Should have 1 tool kit")
        XCTAssertEqual(consumables.count, 1, "Should have 1 consumable")
        XCTAssertEqual(chemicals.count, 1, "Should have 1 chemical")
        XCTAssertEqual(parts.count, 1, "Should have 1 part")
        XCTAssertEqual(jobs.count, 1, "Should have 1 job")
        XCTAssertEqual(revisions.count, 1, "Should have 1 revision")
    }

    // MARK: - UUID Preservation Tests

    func testRoundTripPreservesToolUUIDs() throws {
        let seed = try performRoundTrip()

        let tool1 = try destRepo.fetchById(FROTool.self, id: seed.tool1Id)
        let tool2 = try destRepo.fetchById(FROTool.self, id: seed.tool2Id)

        XCTAssertNotNil(tool1, "Tool 1 should be found by original UUID")
        XCTAssertNotNil(tool2, "Tool 2 should be found by original UUID")
        XCTAssertEqual(tool1?.name, "1/2\" Combination Wrench")
        XCTAssertEqual(tool2?.name, "Torque Wrench")
    }

    func testRoundTripPreservesGroupUUIDs() throws {
        let seed = try performRoundTrip()

        let parent = try destRepo.fetchById(FROToolGroup.self, id: seed.parentGroupId)
        let child = try destRepo.fetchById(FROToolGroup.self, id: seed.childGroupId)

        XCTAssertNotNil(parent, "Parent group should be found by original UUID")
        XCTAssertNotNil(child, "Child group should be found by original UUID")
        XCTAssertEqual(parent?.name, "Wrenches")
        XCTAssertEqual(child?.name, "Combination Wrenches")
    }

    func testRoundTripPreservesKitUUIDs() throws {
        let seed = try performRoundTrip()

        let kit = try destRepo.fetchById(FROToolKit.self, id: seed.kitId)
        XCTAssertNotNil(kit, "Kit should be found by original UUID")
        XCTAssertEqual(kit?.name, "Engine Kit")
    }

    func testRoundTripPreservesJobUUIDs() throws {
        let seed = try performRoundTrip()

        let job = try destRepo.fetchById(FROJob.self, id: seed.jobId)
        XCTAssertNotNil(job, "Job should be found by original UUID")
        XCTAssertEqual(job?.aircraftType, "UH-60L")
        XCTAssertEqual(job?.system, "Main Rotor")
    }

    // MARK: - Relationship Preservation Tests

    func testRoundTripPreservesToolGroupMembership() throws {
        let seed = try performRoundTrip()

        let tool1 = try destRepo.fetchById(FROTool.self, id: seed.tool1Id)
        XCTAssertNotNil(tool1?.group, "Tool should be in a group")
        XCTAssertEqual(tool1?.group?.id, seed.childGroupId, "Tool should be in the correct child group")
    }

    func testRoundTripPreservesToolKitMembership() throws {
        let seed = try performRoundTrip()

        let tool1 = try destRepo.fetchById(FROTool.self, id: seed.tool1Id)
        XCTAssertNotNil(tool1?.toolKits, "Tool should have kit memberships")
        XCTAssertEqual(tool1?.toolKits?.count, 1, "Tool should be in 1 kit")
        XCTAssertEqual(tool1?.toolKits?.first?.id, seed.kitId, "Tool should be in the correct kit")
    }

    func testRoundTripPreservesToolGroupHierarchy() throws {
        let seed = try performRoundTrip()

        let child = try destRepo.fetchById(FROToolGroup.self, id: seed.childGroupId)
        XCTAssertNotNil(child?.parentGroup, "Child group should have a parent")
        XCTAssertEqual(child?.parentGroup?.id, seed.parentGroupId, "Child should reference correct parent")

        let parent = try destRepo.fetchById(FROToolGroup.self, id: seed.parentGroupId)
        XCTAssertNil(parent?.parentGroup, "Parent group should have no parent")
        XCTAssertNotNil(parent?.childGroups, "Parent should have children")
        XCTAssertEqual(parent?.childGroups?.count, 1, "Parent should have 1 child")
    }

    func testRoundTripPreservesJobRelationships() throws {
        let seed = try performRoundTrip()

        let job = try destRepo.fetchById(FROJob.self, id: seed.jobId)
        XCTAssertNotNil(job)

        XCTAssertEqual(job?.tools?.count, 2, "Job should have 2 tools")
        XCTAssertEqual(job?.consumables?.count, 1, "Job should have 1 consumable")
        XCTAssertEqual(job?.chemicals?.count, 1, "Job should have 1 chemical")
        XCTAssertEqual(job?.parts?.count, 1, "Job should have 1 part")

        // Verify the tools are the correct ones
        let toolIds = Set(job?.tools?.map { $0.id } ?? [])
        XCTAssertTrue(toolIds.contains(seed.tool1Id), "Job should contain tool 1")
        XCTAssertTrue(toolIds.contains(seed.tool2Id), "Job should contain tool 2")
    }

    func testRoundTripPreservesJobRevision() throws {
        let seed = try performRoundTrip()

        let revision = try destRepo.fetchById(FROJobRevision.self, id: seed.revisionId)
        XCTAssertNotNil(revision, "Revision should be found by original UUID")
        XCTAssertEqual(revision?.versionNumber, 1)
        XCTAssertEqual(revision?.editNotes, "Initial entry")
        XCTAssertEqual(revision?.jobRecord?.id, seed.jobId, "Revision should link to correct job")
    }

    // MARK: - Field Value Preservation Tests

    func testRoundTripPreservesToolFields() throws {
        let seed = try performRoundTrip()

        let tool1 = try destRepo.fetchById(FROTool.self, id: seed.tool1Id)
        XCTAssertEqual(tool1?.name, "1/2\" Combination Wrench")
        XCTAssertEqual(tool1?.aliases, ["half-inch wrench"])
        XCTAssertEqual(tool1?.ownershipType, "personal")
        XCTAssertEqual(tool1?.notes, "SAE standard")
        XCTAssertEqual(tool1?.isInGarage, true)
        XCTAssertEqual(tool1?.photoFileNames, ["photo_0.jpg"])

        let tool2 = try destRepo.fetchById(FROTool.self, id: seed.tool2Id)
        XCTAssertEqual(tool2?.ownershipType, "borrowed")
        XCTAssertEqual(tool2?.borrowedFrom, "Shop A")
    }

    func testRoundTripPreservesConsumableFields() throws {
        let seed = try performRoundTrip()

        let consumable = try destRepo.fetchById(FROConsumable.self, id: seed.consumableId)
        XCTAssertNotNil(consumable)
        XCTAssertEqual(consumable?.name, "Safety Wire")
        XCTAssertEqual(consumable?.category, "hardware")
        XCTAssertEqual(consumable?.size, "0.032")
        XCTAssertEqual(consumable?.spec, "MS20995C32")
        XCTAssertEqual(consumable?.notes, "Stainless steel")
    }

    func testRoundTripPreservesChemicalFields() throws {
        let seed = try performRoundTrip()

        let chemical = try destRepo.fetchById(FROChemical.self, id: seed.chemicalId)
        XCTAssertNotNil(chemical)
        XCTAssertEqual(chemical?.name, "CRC 5-56")
        XCTAssertEqual(chemical?.category, "lubricant")
        XCTAssertEqual(chemical?.spec, "MIL-PRF-3150")
    }

    func testRoundTripPreservesPartFields() throws {
        let seed = try performRoundTrip()

        let part = try destRepo.fetchById(FROPart.self, id: seed.partId)
        XCTAssertNotNil(part)
        XCTAssertEqual(part?.partNumber, "MS24665-132")
        XCTAssertEqual(part?.nomenclature, "Cotter Pin")
        XCTAssertEqual(part?.nsn, "5315-00-007-0532")
        XCTAssertEqual(part?.quantity, 10)
        XCTAssertEqual(part?.unitOfMeasure, "EA")
    }

    func testRoundTripPreservesJobFields() throws {
        let seed = try performRoundTrip()

        let job = try destRepo.fetchById(FROJob.self, id: seed.jobId)
        XCTAssertNotNil(job)
        XCTAssertEqual(job?.aircraftType, "UH-60L")
        XCTAssertEqual(job?.aircraftSerialNumber, "85-24389")
        XCTAssertEqual(job?.system, "Main Rotor")
        XCTAssertEqual(job?.component, "Blade Grips")
        XCTAssertEqual(job?.taskDescription, "Inspect and lubricate blade grip bearings")
        XCTAssertEqual(job?.tmReferences, "TM 1-1520-237-23")
        XCTAssertEqual(job?.notes, "All bearings serviceable")
    }

    // MARK: - Nested Hierarchy Tests

    func testThreeLevelGroupHierarchySurvivesRoundTrip() throws {
        // Create 3-level deep hierarchy: Wrenches -> Combination -> SAE
        let level1 = FROToolGroup(name: "Wrenches", sortOrder: 0)
        sourceRepo.insert(level1)

        let level2 = FROToolGroup(name: "Combination", sortOrder: 0)
        level2.parentGroup = level1
        sourceRepo.insert(level2)

        let level3 = FROToolGroup(name: "SAE", sortOrder: 0)
        level3.parentGroup = level2
        sourceRepo.insert(level3)

        let tool = FROTool(name: "1/2 inch combo")
        tool.group = level3
        sourceRepo.insert(tool)

        try sourceRepo.save()

        // Export
        guard let exportURL = service.exportBackup(repository: sourceRepo) else {
            XCTFail("Export returned nil")
            return
        }

        // Import to dest
        let sessionId = try service.parseBackup(at: exportURL, repository: destRepo)
        try service.commitImport(sessionId: sessionId, repository: destRepo)
        try? FileManager.default.removeItem(at: exportURL)

        // Verify hierarchy
        let destLevel3 = try destRepo.fetchById(FROToolGroup.self, id: level3.id)
        XCTAssertNotNil(destLevel3)
        XCTAssertEqual(destLevel3?.name, "SAE")
        XCTAssertEqual(destLevel3?.parentGroup?.name, "Combination")
        XCTAssertEqual(destLevel3?.parentGroup?.parentGroup?.name, "Wrenches")
        XCTAssertNil(destLevel3?.parentGroup?.parentGroup?.parentGroup, "Top level has no parent")

        // Verify tool is in the deepest group
        let destTool = try destRepo.fetchById(FROTool.self, id: tool.id)
        XCTAssertEqual(destTool?.group?.id, level3.id)
    }

    // MARK: - Conflict Detection Tests

    func testUUIDMatchDetectedAsConflict() throws {
        let toolId = UUID()

        // Insert tool in source
        let sourceTool = FROTool(id: toolId, name: "Wrench")
        sourceRepo.insert(sourceTool)
        try sourceRepo.save()

        // Insert same UUID tool in dest
        let destTool = FROTool(id: toolId, name: "Old Wrench")
        destRepo.insert(destTool)
        try destRepo.save()

        // Export from source
        guard let exportURL = service.exportBackup(repository: sourceRepo) else {
            XCTFail("Export returned nil")
            return
        }

        // Parse into dest (should detect conflict)
        let sessionId = try service.parseBackup(at: exportURL, repository: destRepo)
        try? FileManager.default.removeItem(at: exportURL)

        let staging = try destRepo.fetchAll(FROImportStaging.self)
        let toolStaging = staging.filter { $0.entityType == "tool" }
        XCTAssertEqual(toolStaging.count, 1)
        XCTAssertEqual(toolStaging.first?.conflictType, "uuid_match")
        XCTAssertEqual(toolStaging.first?.matchedEntityId, toolId)

        // Clean up
        try service.cancelImport(sessionId: sessionId, repository: destRepo)
    }

    func testNameMatchDetectedAsConflict() throws {
        // Insert tool in source with one UUID
        let sourceTool = FROTool(name: "Wrench")
        sourceRepo.insert(sourceTool)
        try sourceRepo.save()

        // Insert tool in dest with different UUID but same name
        let destTool = FROTool(name: "wrench") // lowercase — should still match
        destRepo.insert(destTool)
        try destRepo.save()

        // Export from source
        guard let exportURL = service.exportBackup(repository: sourceRepo) else {
            XCTFail("Export returned nil")
            return
        }

        // Parse into dest
        let sessionId = try service.parseBackup(at: exportURL, repository: destRepo)
        try? FileManager.default.removeItem(at: exportURL)

        let staging = try destRepo.fetchAll(FROImportStaging.self)
        let toolStaging = staging.filter { $0.entityType == "tool" }
        XCTAssertEqual(toolStaging.count, 1)
        XCTAssertEqual(toolStaging.first?.conflictType, "name_match", "Case-insensitive name match should be detected")

        try service.cancelImport(sessionId: sessionId, repository: destRepo)
    }

    func testSkipResolutionDoesNotCreate() throws {
        let toolId = UUID()

        let sourceTool = FROTool(id: toolId, name: "Wrench")
        sourceRepo.insert(sourceTool)
        try sourceRepo.save()

        let destTool = FROTool(id: toolId, name: "Old Wrench")
        destRepo.insert(destTool)
        try destRepo.save()

        guard let exportURL = service.exportBackup(repository: sourceRepo) else {
            XCTFail("Export returned nil")
            return
        }

        let sessionId = try service.parseBackup(at: exportURL, repository: destRepo)
        try? FileManager.default.removeItem(at: exportURL)

        // Set resolution to skip
        let staging = try destRepo.fetchAll(FROImportStaging.self)
        for record in staging where record.conflictType != nil {
            record.resolution = "skip"
            record.status = "resolved"
        }
        try destRepo.save()

        try service.commitImport(sessionId: sessionId, repository: destRepo)

        // Dest should still have only the original tool
        let tools = try destRepo.fetchAll(FROTool.self)
        XCTAssertEqual(tools.count, 1)
        XCTAssertEqual(tools.first?.name, "Old Wrench", "Skip should not modify existing")
    }

    func testCancelDeletesStagingRecords() throws {
        let sourceTool = FROTool(name: "Wrench")
        sourceRepo.insert(sourceTool)
        try sourceRepo.save()

        guard let exportURL = service.exportBackup(repository: sourceRepo) else {
            XCTFail("Export returned nil")
            return
        }

        let sessionId = try service.parseBackup(at: exportURL, repository: destRepo)
        try? FileManager.default.removeItem(at: exportURL)

        // Verify staging records exist
        let beforeCancel = try destRepo.fetchAll(FROImportStaging.self)
        XCTAssertFalse(beforeCancel.isEmpty, "Should have staging records before cancel")

        // Cancel
        try service.cancelImport(sessionId: sessionId, repository: destRepo)

        // Verify staging records are gone
        let afterCancel = try destRepo.fetchAll(FROImportStaging.self)
        XCTAssertTrue(afterCancel.isEmpty, "Cancel should delete all staging records")

        // Verify no tools were created
        let tools = try destRepo.fetchAll(FROTool.self)
        XCTAssertTrue(tools.isEmpty, "Cancel should not create any entities")
    }

    // MARK: - JSON Schema Tests

    func testExportProducesValidV2JSON() throws {
        _ = try seedSourceData()

        guard let exportURL = service.exportBackup(repository: sourceRepo) else {
            XCTFail("Export returned nil")
            return
        }

        let jsonData = try Data(contentsOf: exportURL)
        let payload = try JSONDecoder().decode(ImportExportService.BackupPayload.self, from: jsonData)

        XCTAssertEqual(payload.version, 2)
        XCTAssertFalse(payload.exportedAt.isEmpty)
        XCTAssertEqual(payload.entities.tools.count, 2)
        XCTAssertEqual(payload.entities.toolGroups.count, 2)
        XCTAssertEqual(payload.entities.toolKits.count, 1)
        XCTAssertEqual(payload.entities.jobs.count, 1)
        XCTAssertEqual(payload.entities.consumables.count, 1)
        XCTAssertEqual(payload.entities.chemicals.count, 1)
        XCTAssertEqual(payload.entities.parts.count, 1)

        // Verify UUIDs are present
        for tool in payload.entities.tools {
            XCTAssertFalse(tool.id.isEmpty, "Tool should have UUID")
            XCTAssertNotNil(UUID(uuidString: tool.id), "Tool ID should be valid UUID")
        }

        // Verify hierarchy references
        let childGroup = payload.entities.toolGroups.first { $0.parentGroupId != nil }
        XCTAssertNotNil(childGroup, "Should have a child group with parentGroupId")
        XCTAssertNotNil(UUID(uuidString: childGroup!.parentGroupId!), "parentGroupId should be valid UUID")

        try? FileManager.default.removeItem(at: exportURL)
    }
}

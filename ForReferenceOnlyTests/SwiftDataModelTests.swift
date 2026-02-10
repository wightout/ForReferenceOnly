import XCTest
import Foundation
import SwiftData
@testable import ForReferenceOnly

@MainActor
final class SwiftDataModelTests: XCTestCase {

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

    // MARK: - FROJob

    func testFROJobDefaultValues() throws {
        let job = FROJob()
        XCTAssertNotNil(job.id)
        XCTAssertEqual(job.aircraftType, "")
        XCTAssertEqual(job.system, "")
        XCTAssertEqual(job.currentVersion, 1)
        XCTAssertNil(job.aircraftSerialNumber)
        XCTAssertNil(job.nNumber)
        XCTAssertNil(job.component)
        XCTAssertNil(job.taskDescription)
        XCTAssertNil(job.tmReferences)
        XCTAssertNil(job.notes)
        XCTAssertNil(job.recommendations)
    }

    func testFROJobPropertyAssignment() throws {
        let job = FROJob(
            aircraftType: "CH-47",
            aircraftSerialNumber: "SN-123",
            nNumber: "N12345",
            system: "Hydraulic",
            component: "Pump",
            taskDescription: "Replace pump seals",
            currentVersion: 2
        )
        context.insert(job)
        try context.save()

        XCTAssertEqual(job.aircraftType, "CH-47")
        XCTAssertEqual(job.aircraftSerialNumber, "SN-123")
        XCTAssertEqual(job.nNumber, "N12345")
        XCTAssertEqual(job.system, "Hydraulic")
        XCTAssertEqual(job.component, "Pump")
        XCTAssertEqual(job.taskDescription, "Replace pump seals")
        XCTAssertEqual(job.currentVersion, 2)
    }

    // MARK: - FROJobRevision

    func testFROJobRevisionDefaultValues() throws {
        let rev = FROJobRevision()
        XCTAssertNotNil(rev.id)
        XCTAssertEqual(rev.versionNumber, 0)
        XCTAssertNil(rev.snapshotData)
        XCTAssertNil(rev.editNotes)
    }

    // MARK: - FROTool

    func testFROToolDefaultValues() throws {
        let tool = FROTool()
        XCTAssertNotNil(tool.id)
        XCTAssertEqual(tool.name, "")
        XCTAssertEqual(tool.ownershipType, "personal")
        XCTAssertTrue(tool.isInGarage)
        XCTAssertNil(tool.aliases)
        XCTAssertNil(tool.borrowedFrom)
        XCTAssertNil(tool.notes)
        XCTAssertNil(tool.photoFileNames)
    }

    func testFROToolWithAliases() throws {
        let tool = FROTool(name: "Socket", aliases: ["10mm Socket", "Deep Socket"])
        context.insert(tool)
        try context.save()

        XCTAssertEqual(tool.aliases?.count, 2)
        XCTAssertEqual(tool.aliases?[0], "10mm Socket")
    }

    // MARK: - FROToolGroup

    func testFROToolGroupDefaultValues() throws {
        let group = FROToolGroup()
        XCTAssertNotNil(group.id)
        XCTAssertEqual(group.name, "")
        XCTAssertEqual(group.sortOrder, 0)
        XCTAssertEqual(group.ownershipType, "personal")
        XCTAssertEqual(group.measurementType, "sae")
        XCTAssertNil(group.toolType)
    }

    // MARK: - FROToolKit

    func testFROToolKitDefaultValues() throws {
        let kit = FROToolKit()
        XCTAssertNotNil(kit.id)
        XCTAssertEqual(kit.name, "")
        XCTAssertEqual(kit.ownershipType, "personal")
        XCTAssertNil(kit.descriptionText)
        XCTAssertNil(kit.toolType)
    }

    // MARK: - FROConsumable

    func testFROConsumableDefaultValues() throws {
        let item = FROConsumable()
        XCTAssertNotNil(item.id)
        XCTAssertEqual(item.name, "")
        XCTAssertEqual(item.category, "other")
        XCTAssertTrue(item.isInGarage)
    }

    // MARK: - FROChemical

    func testFROChemicalDefaultValues() throws {
        let item = FROChemical()
        XCTAssertNotNil(item.id)
        XCTAssertEqual(item.name, "")
        XCTAssertEqual(item.category, "other")
        XCTAssertTrue(item.isInGarage)
    }

    // MARK: - FROPart

    func testFROPartDefaultValues() throws {
        let part = FROPart()
        XCTAssertNotNil(part.id)
        XCTAssertEqual(part.partNumber, "")
        XCTAssertEqual(part.nomenclature, "")
        XCTAssertEqual(part.quantity, 1)
    }

    // MARK: - FROVoiceMemo

    func testFROVoiceMemoDefaultValues() throws {
        let memo = FROVoiceMemo()
        XCTAssertNotNil(memo.id)
        XCTAssertEqual(memo.transcriptionStatus, "pending")
        XCTAssertNil(memo.audioFilePath)
        XCTAssertNil(memo.transcriptionText)
        XCTAssertNil(memo.identifiedTools)
    }

    // MARK: - FROAttachment

    func testFROAttachmentDefaultValues() throws {
        let attachment = FROAttachment()
        XCTAssertNotNil(attachment.id)
        XCTAssertEqual(attachment.fileName, "")
        XCTAssertEqual(attachment.fileType, "photo")
        XCTAssertNil(attachment.notes)
    }

    // MARK: - FROImportStaging

    func testFROImportStagingDefaultValues() throws {
        let staging = FROImportStaging()
        XCTAssertNotNil(staging.id)
        XCTAssertNotNil(staging.importSessionId)
        XCTAssertEqual(staging.entityType, "")
        XCTAssertEqual(staging.status, "pending")
        XCTAssertNil(staging.conflictType)
        XCTAssertNil(staging.matchedEntityId)
        XCTAssertNil(staging.resolution)
    }

    func testFROImportStagingRequiredFields() throws {
        let sessionId = UUID()
        let entityId = UUID()
        let jsonData = "{\"name\":\"test\"}".data(using: .utf8)!
        let staging = FROImportStaging(
            importSessionId: sessionId,
            entityType: "tool",
            entityId: entityId,
            jsonData: jsonData,
            status: "conflict",
            conflictType: "name_match",
            matchedEntityId: UUID()
        )
        context.insert(staging)
        try context.save()

        XCTAssertEqual(staging.importSessionId, sessionId)
        XCTAssertEqual(staging.entityType, "tool")
        XCTAssertEqual(staging.entityId, entityId)
        XCTAssertEqual(staging.status, "conflict")
        XCTAssertEqual(staging.conflictType, "name_match")
        XCTAssertNotNil(staging.matchedEntityId)
    }

    // MARK: - UUID Stability

    func testUUIDStability() throws {
        let id = UUID()
        let tool = FROTool(id: id, name: "Test Tool")
        context.insert(tool)
        try context.save()

        XCTAssertEqual(tool.id, id)
    }
}

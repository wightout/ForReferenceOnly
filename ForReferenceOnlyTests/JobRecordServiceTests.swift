import XCTest
import Foundation
import SwiftData
@testable import ForReferenceOnly

/// Tests for JobRecordService CRUD operations.
/// Tests operate on ModelContext directly since the service uses a non-injectable singleton.
@MainActor
final class JobRecordServiceTests: XCTestCase {

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

    func testCreateJobRecordRequiredFields() throws {
        let job = FROJob(aircraftType: "CH-47", system: "Hydraulic")
        context.insert(job)
        try context.save()

        XCTAssertEqual(job.aircraftType, "CH-47")
        XCTAssertEqual(job.system, "Hydraulic")
        XCTAssertEqual(job.currentVersion, 1)
        XCTAssertNotNil(job.jobDate)
    }

    func testCreateJobRecordAllFields() throws {
        let date = Date()
        let job = FROJob(
            aircraftType: "UH-60M",
            aircraftSerialNumber: "SN-456",
            nNumber: "N98765",
            system: "Avionics",
            component: "Radio",
            jobDate: date,
            taskDescription: "Replace radio panel",
            tmReferences: "TM 1-1520-237-23",
            notes: "Waiting for parts",
            recommendations: "Check wiring harness"
        )
        context.insert(job)
        try context.save()

        XCTAssertEqual(job.aircraftType, "UH-60M")
        XCTAssertEqual(job.aircraftSerialNumber, "SN-456")
        XCTAssertEqual(job.nNumber, "N98765")
        XCTAssertEqual(job.system, "Avionics")
        XCTAssertEqual(job.component, "Radio")
        XCTAssertEqual(job.taskDescription, "Replace radio panel")
        XCTAssertEqual(job.tmReferences, "TM 1-1520-237-23")
        XCTAssertEqual(job.notes, "Waiting for parts")
        XCTAssertEqual(job.recommendations, "Check wiring harness")
    }

    func testCreateJobRecordDefaultDate() throws {
        let before = Date()
        let job = FROJob(aircraftType: "AH-64", system: "Engine")
        context.insert(job)
        try context.save()
        let after = Date()

        XCTAssertGreaterThanOrEqual(job.jobDate, before)
        XCTAssertLessThanOrEqual(job.jobDate, after)
    }

    // MARK: - Read: Sorted by Date

    func testFetchAllJobRecordsSortedByDateDesc() throws {
        let oldDate = Calendar.current.date(byAdding: .day, value: -10, to: Date())!
        let newDate = Date()

        let j1 = FROJob(aircraftType: "CH-47", system: "Hydraulic", jobDate: oldDate)
        let j2 = FROJob(aircraftType: "UH-60M", system: "Avionics", jobDate: newDate)
        [j1, j2].forEach { context.insert($0) }
        try context.save()

        let descriptor = FetchDescriptor<FROJob>(
            sortBy: [SortDescriptor(\.jobDate, order: .reverse)]
        )
        let jobs = try context.fetch(descriptor)
        XCTAssertEqual(jobs.count, 2)
        XCTAssertEqual(jobs[0].aircraftType, "UH-60M") // newer first
        XCTAssertEqual(jobs[1].aircraftType, "CH-47")
    }

    // MARK: - Read: By ID

    func testFetchJobRecordById() throws {
        let id = UUID()
        let job = FROJob(id: id, aircraftType: "AH-64", system: "Engine")
        context.insert(job)
        try context.save()

        var descriptor = FetchDescriptor<FROJob>(predicate: #Predicate { $0.id == id })
        descriptor.fetchLimit = 1
        let found = try context.fetch(descriptor).first
        XCTAssertNotNil(found)
        XCTAssertEqual(found?.aircraftType, "AH-64")
    }

    // MARK: - Read: By Aircraft Type

    func testFetchJobRecordsByAircraftType() throws {
        let j1 = FROJob(aircraftType: "CH-47", system: "Hydraulic")
        let j2 = FROJob(aircraftType: "CH-47", system: "Engine")
        let j3 = FROJob(aircraftType: "UH-60M", system: "Avionics")
        [j1, j2, j3].forEach { context.insert($0) }
        try context.save()

        let type = "CH-47"
        let descriptor = FetchDescriptor<FROJob>(
            predicate: #Predicate { $0.aircraftType == type },
            sortBy: [SortDescriptor(\.jobDate, order: .reverse)]
        )
        let found = try context.fetch(descriptor)
        XCTAssertEqual(found.count, 2)
    }

    // MARK: - Read: By System

    func testFetchJobRecordsBySystem() throws {
        let j1 = FROJob(aircraftType: "CH-47", system: "Hydraulic")
        let j2 = FROJob(aircraftType: "UH-60M", system: "Hydraulic")
        let j3 = FROJob(aircraftType: "AH-64", system: "Avionics")
        [j1, j2, j3].forEach { context.insert($0) }
        try context.save()

        let sys = "Hydraulic"
        let descriptor = FetchDescriptor<FROJob>(
            predicate: #Predicate { $0.system == sys },
            sortBy: [SortDescriptor(\.jobDate, order: .reverse)]
        )
        let found = try context.fetch(descriptor)
        XCTAssertEqual(found.count, 2)
    }

    // MARK: - Read: Count

    func testCountJobRecords() throws {
        let j1 = FROJob(aircraftType: "CH-47", system: "Hydraulic")
        let j2 = FROJob(aircraftType: "UH-60M", system: "Avionics")
        [j1, j2].forEach { context.insert($0) }
        try context.save()

        let descriptor = FetchDescriptor<FROJob>()
        let count = try context.fetchCount(descriptor)
        XCTAssertEqual(count, 2)
    }

    // MARK: - Update

    func testUpdateJobRecordFields() throws {
        let job = FROJob(aircraftType: "CH-47", system: "Hydraulic")
        context.insert(job)
        try context.save()

        let originalUpdatedAt = job.updatedAt

        // Slight delay to ensure updatedAt differs
        job.aircraftType = "UH-60M"
        job.system = "Avionics"
        job.taskDescription = "New task"
        job.notes = "Updated notes"
        job.recommendations = "New rec"
        job.updatedAt = Date()
        try context.save()

        XCTAssertEqual(job.aircraftType, "UH-60M")
        XCTAssertEqual(job.system, "Avionics")
        XCTAssertEqual(job.taskDescription, "New task")
        XCTAssertEqual(job.notes, "Updated notes")
        XCTAssertEqual(job.recommendations, "New rec")
        XCTAssertGreaterThanOrEqual(job.updatedAt, originalUpdatedAt)
    }

    // MARK: - Delete

    func testDeleteJobRecord() throws {
        let job = FROJob(aircraftType: "CH-47", system: "Hydraulic")
        context.insert(job)
        try context.save()

        context.delete(job)
        try context.save()

        let descriptor = FetchDescriptor<FROJob>()
        let remaining = try context.fetch(descriptor)
        XCTAssertTrue(remaining.isEmpty)
    }
}

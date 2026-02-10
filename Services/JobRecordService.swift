import Foundation
import SwiftData

/// JobRecordService handles all CRUD operations for FROJob entities in SwiftData.
/// Uses the real SQLite-backed persistent store for all operations.
@MainActor
class JobRecordService {

    // MARK: - Properties

    private var modelContext: ModelContext {
        SharedModelContainer.shared.mainContext
    }

    // MARK: - Create

    /// Creates a new JobRecord in SwiftData and saves immediately.
    /// - Parameters:
    ///   - aircraftType: The aircraft type (required)
    ///   - system: The system worked on (required)
    ///   - aircraftSerialNumber: Aircraft serial number (optional)
    ///   - nNumber: N-number / tail number (optional)
    ///   - component: Component name (optional)
    ///   - jobDate: Date of the job (defaults to now)
    ///   - taskDescription: Description of the task (optional)
    ///   - tmReferences: Technical manual references (optional)
    ///   - notes: Additional notes (optional)
    ///   - recommendations: Recommendations (optional)
    /// - Returns: The created JobRecord object
    @discardableResult
    func createJobRecord(
        aircraftType: String,
        system: String,
        aircraftSerialNumber: String? = nil,
        nNumber: String? = nil,
        component: String? = nil,
        jobDate: Date = Date(),
        taskDescription: String? = nil,
        tmReferences: String? = nil,
        notes: String? = nil,
        recommendations: String? = nil
    ) -> FROJob {
        let record = FROJob(
            aircraftType: aircraftType,
            aircraftSerialNumber: aircraftSerialNumber,
            nNumber: nNumber,
            system: system,
            component: component,
            jobDate: jobDate,
            taskDescription: taskDescription,
            tmReferences: tmReferences,
            notes: notes,
            recommendations: recommendations
        )
        modelContext.insert(record)

        do {
            try modelContext.save()
            print("JobRecordService: Created job record for '\(aircraftType)' successfully")
        } catch {
            print("JobRecordService: Failed to create job record - \(error)")
        }

        return record
    }

    // MARK: - Read

    /// Fetches all job records, sorted by job date descending (most recent first).
    /// - Returns: Array of JobRecord objects
    func fetchAllJobRecords() -> [FROJob] {
        let descriptor = FetchDescriptor<FROJob>(
            sortBy: [SortDescriptor(\.jobDate, order: .reverse)]
        )

        do {
            return try modelContext.fetch(descriptor)
        } catch {
            print("JobRecordService: Failed to fetch job records - \(error)")
            return []
        }
    }

    /// Fetches a single job record by its UUID.
    /// - Parameter id: The job record's UUID
    /// - Returns: The JobRecord if found, nil otherwise
    func fetchJobRecord(byId id: UUID) -> FROJob? {
        var descriptor = FetchDescriptor<FROJob>(
            predicate: #Predicate { $0.id == id }
        )
        descriptor.fetchLimit = 1

        do {
            return try modelContext.fetch(descriptor).first
        } catch {
            print("JobRecordService: Failed to fetch job record by ID - \(error)")
            return nil
        }
    }

    /// Fetches job records matching an aircraft type.
    /// - Parameter aircraftType: The aircraft type to filter by
    /// - Returns: Array of matching JobRecord objects
    func fetchJobRecords(byAircraftType aircraftType: String) -> [FROJob] {
        let descriptor = FetchDescriptor<FROJob>(
            predicate: #Predicate { $0.aircraftType == aircraftType },
            sortBy: [SortDescriptor(\.jobDate, order: .reverse)]
        )

        do {
            return try modelContext.fetch(descriptor)
        } catch {
            print("JobRecordService: Failed to fetch job records by aircraft type - \(error)")
            return []
        }
    }

    /// Fetches job records matching a system.
    /// - Parameter system: The system to filter by
    /// - Returns: Array of matching JobRecord objects
    func fetchJobRecords(bySystem system: String) -> [FROJob] {
        let descriptor = FetchDescriptor<FROJob>(
            predicate: #Predicate { $0.system == system },
            sortBy: [SortDescriptor(\.jobDate, order: .reverse)]
        )

        do {
            return try modelContext.fetch(descriptor)
        } catch {
            print("JobRecordService: Failed to fetch job records by system - \(error)")
            return []
        }
    }

    /// Returns the total count of job records.
    func countJobRecords() -> Int {
        let descriptor = FetchDescriptor<FROJob>()
        do {
            return try modelContext.fetchCount(descriptor)
        } catch {
            print("JobRecordService: Failed to count job records - \(error)")
            return 0
        }
    }

    // MARK: - Update

    /// Updates a job record's properties and saves.
    /// - Parameters:
    ///   - record: The JobRecord object to update
    ///   - aircraftType: New aircraft type (optional, keeps current if nil)
    ///   - system: New system (optional)
    ///   - taskDescription: New task description (optional)
    ///   - notes: New notes (optional)
    ///   - recommendations: New recommendations (optional)
    func updateJobRecord(
        _ record: FROJob,
        aircraftType: String? = nil,
        system: String? = nil,
        taskDescription: String? = nil,
        notes: String? = nil,
        recommendations: String? = nil
    ) {
        if let aircraftType = aircraftType { record.aircraftType = aircraftType }
        if let system = system { record.system = system }
        if let taskDescription = taskDescription { record.taskDescription = taskDescription }
        if let notes = notes { record.notes = notes }
        if let recommendations = recommendations { record.recommendations = recommendations }
        record.updatedAt = Date()

        do {
            try modelContext.save()
            print("JobRecordService: Updated job record '\(record.aircraftType)' successfully")
        } catch {
            print("JobRecordService: Failed to update job record - \(error)")
        }
    }

    // MARK: - Delete

    /// Deletes a job record from SwiftData and saves.
    /// - Parameter record: The JobRecord object to delete
    func deleteJobRecord(_ record: FROJob) {
        let aircraftType = record.aircraftType
        modelContext.delete(record)

        do {
            try modelContext.save()
            print("JobRecordService: Deleted job record for '\(aircraftType)' successfully")
        } catch {
            print("JobRecordService: Failed to delete job record - \(error)")
        }
    }
}

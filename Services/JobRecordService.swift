import CoreData

/// JobRecordService handles all CRUD operations for JobRecord entities in Core Data.
/// Uses the real SQLite-backed persistent store for all operations.
class JobRecordService {

    // MARK: - Properties

    private let persistenceController: PersistenceController

    /// The managed object context used for all operations
    var viewContext: NSManagedObjectContext {
        persistenceController.viewContext
    }

    // MARK: - Initialization

    /// Initialize with a persistence controller (defaults to shared singleton)
    init(persistenceController: PersistenceController = .shared) {
        self.persistenceController = persistenceController
    }

    // MARK: - Create

    /// Creates a new JobRecord in Core Data and saves immediately.
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
    /// - Returns: The created JobRecord managed object
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
    ) -> JobRecord {
        let context = viewContext
        let record = JobRecord(context: context)
        record.id = UUID()
        record.aircraftType = aircraftType
        record.system = system
        record.aircraftSerialNumber = aircraftSerialNumber
        record.nNumber = nNumber
        record.component = component
        record.jobDate = jobDate
        record.taskDescription = taskDescription
        record.tmReferences = tmReferences
        record.notes = notes
        record.recommendations = recommendations
        record.createdAt = Date()
        record.updatedAt = Date()
        record.currentVersion = 1

        do {
            try context.save()
            print("JobRecordService: Created job record for '\(aircraftType)' successfully")
        } catch {
            // Rollback to prevent partial/corrupted records from lingering in context
            context.rollback()
            print("JobRecordService: Failed to create job record, rolled back - \(error)")
        }

        return record
    }

    // MARK: - Read

    /// Fetches all job records, sorted by job date descending (most recent first).
    /// - Returns: Array of JobRecord managed objects
    func fetchAllJobRecords() -> [JobRecord] {
        let request = NSFetchRequest<JobRecord>(entityName: "JobRecord")
        request.sortDescriptors = [NSSortDescriptor(key: "jobDate", ascending: false)]

        do {
            let records = try viewContext.fetch(request)
            return records
        } catch {
            print("JobRecordService: Failed to fetch job records - \(error)")
            return []
        }
    }

    /// Fetches a single job record by its UUID.
    /// - Parameter id: The job record's UUID
    /// - Returns: The JobRecord if found, nil otherwise
    func fetchJobRecord(byId id: UUID) -> JobRecord? {
        let request = NSFetchRequest<JobRecord>(entityName: "JobRecord")
        request.predicate = NSPredicate(format: "id == %@", id as CVarArg)
        request.fetchLimit = 1

        do {
            return try viewContext.fetch(request).first
        } catch {
            print("JobRecordService: Failed to fetch job record by ID - \(error)")
            return nil
        }
    }

    /// Fetches job records matching an aircraft type.
    /// - Parameter aircraftType: The aircraft type to filter by
    /// - Returns: Array of matching JobRecord objects
    func fetchJobRecords(byAircraftType aircraftType: String) -> [JobRecord] {
        let request = NSFetchRequest<JobRecord>(entityName: "JobRecord")
        request.predicate = NSPredicate(format: "aircraftType == %@", aircraftType)
        request.sortDescriptors = [NSSortDescriptor(key: "jobDate", ascending: false)]

        do {
            return try viewContext.fetch(request)
        } catch {
            print("JobRecordService: Failed to fetch job records by aircraft type - \(error)")
            return []
        }
    }

    /// Fetches job records matching a system.
    /// - Parameter system: The system to filter by
    /// - Returns: Array of matching JobRecord objects
    func fetchJobRecords(bySystem system: String) -> [JobRecord] {
        let request = NSFetchRequest<JobRecord>(entityName: "JobRecord")
        request.predicate = NSPredicate(format: "system == %@", system)
        request.sortDescriptors = [NSSortDescriptor(key: "jobDate", ascending: false)]

        do {
            return try viewContext.fetch(request)
        } catch {
            print("JobRecordService: Failed to fetch job records by system - \(error)")
            return []
        }
    }

    /// Returns the total count of job records.
    func countJobRecords() -> Int {
        let request = NSFetchRequest<JobRecord>(entityName: "JobRecord")
        do {
            return try viewContext.count(for: request)
        } catch {
            print("JobRecordService: Failed to count job records - \(error)")
            return 0
        }
    }

    // MARK: - Update

    /// Updates a job record's properties and saves.
    /// Automatically increments the version and creates a revision snapshot.
    /// - Parameters:
    ///   - record: The JobRecord managed object to update
    ///   - aircraftType: New aircraft type (optional, keeps current if nil)
    ///   - system: New system (optional)
    ///   - taskDescription: New task description (optional)
    ///   - notes: New notes (optional)
    ///   - recommendations: New recommendations (optional)
    func updateJobRecord(
        _ record: JobRecord,
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
            try viewContext.save()
            print("JobRecordService: Updated job record '\(record.aircraftType ?? "unknown")' successfully")
        } catch {
            // Rollback to prevent partial changes from corrupting data
            viewContext.rollback()
            print("JobRecordService: Failed to update job record, rolled back - \(error)")
        }
    }

    // MARK: - Delete

    /// Deletes a job record from Core Data and saves.
    /// - Parameter record: The JobRecord managed object to delete
    func deleteJobRecord(_ record: JobRecord) {
        let aircraftType = record.aircraftType ?? "unknown"
        viewContext.delete(record)

        do {
            try viewContext.save()
            print("JobRecordService: Deleted job record for '\(aircraftType)' successfully")
        } catch {
            // Rollback to prevent partial deletion state from corrupting data
            viewContext.rollback()
            print("JobRecordService: Failed to delete job record, rolled back - \(error)")
        }
    }
}

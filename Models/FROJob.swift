import Foundation
import SwiftData

@Model
final class FROJob: FROIdentifiable {
    var id: UUID
    var aircraftType: String
    var aircraftSerialNumber: String?
    var nNumber: String?
    var system: String
    var component: String?
    var jobDate: Date
    var taskDescription: String?
    var tmReferences: String?
    var notes: String?
    var recommendations: String?
    var createdAt: Date
    var updatedAt: Date
    var currentVersion: Int

    @Relationship(deleteRule: .nullify, inverse: \FROTool.jobRecords)
    var tools: [FROTool]?

    @Relationship(deleteRule: .nullify, inverse: \FROConsumable.jobRecords)
    var consumables: [FROConsumable]?

    @Relationship(deleteRule: .nullify, inverse: \FROChemical.jobRecords)
    var chemicals: [FROChemical]?

    @Relationship(deleteRule: .nullify, inverse: \FROPart.jobRecords)
    var parts: [FROPart]?

    @Relationship(deleteRule: .cascade, inverse: \FROJobRevision.jobRecord)
    var revisions: [FROJobRevision]?

    @Relationship(deleteRule: .cascade, inverse: \FROVoiceMemo.jobRecord)
    var voiceMemo: FROVoiceMemo?

    init(
        id: UUID = UUID(),
        aircraftType: String = "",
        aircraftSerialNumber: String? = nil,
        nNumber: String? = nil,
        system: String = "",
        component: String? = nil,
        jobDate: Date = Date(),
        taskDescription: String? = nil,
        tmReferences: String? = nil,
        notes: String? = nil,
        recommendations: String? = nil,
        createdAt: Date = Date(),
        updatedAt: Date = Date(),
        currentVersion: Int = 1
    ) {
        self.id = id
        self.aircraftType = aircraftType
        self.aircraftSerialNumber = aircraftSerialNumber
        self.nNumber = nNumber
        self.system = system
        self.component = component
        self.jobDate = jobDate
        self.taskDescription = taskDescription
        self.tmReferences = tmReferences
        self.notes = notes
        self.recommendations = recommendations
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.currentVersion = currentVersion
    }
}

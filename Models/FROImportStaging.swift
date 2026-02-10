import Foundation
import SwiftData

@Model
final class FROImportStaging: FROIdentifiable {
    var id: UUID
    var importSessionId: UUID
    var entityType: String
    var entityId: UUID
    var jsonData: Data
    var status: String
    var conflictType: String?
    var matchedEntityId: UUID?
    var resolution: String?
    var createdAt: Date

    init(
        id: UUID = UUID(),
        importSessionId: UUID = UUID(),
        entityType: String = "",
        entityId: UUID = UUID(),
        jsonData: Data = Data(),
        status: String = "pending",
        conflictType: String? = nil,
        matchedEntityId: UUID? = nil,
        resolution: String? = nil,
        createdAt: Date = Date()
    ) {
        self.id = id
        self.importSessionId = importSessionId
        self.entityType = entityType
        self.entityId = entityId
        self.jsonData = jsonData
        self.status = status
        self.conflictType = conflictType
        self.matchedEntityId = matchedEntityId
        self.resolution = resolution
        self.createdAt = createdAt
    }
}

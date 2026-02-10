import Foundation
import SwiftData

@Model
final class FROToolKit: FROIdentifiable {
    var id: UUID
    var name: String
    var descriptionText: String?
    var ownershipType: String
    var toolType: String?
    var createdAt: Date
    var photoFileNames: [String]?

    @Relationship(deleteRule: .nullify, inverse: \FROTool.toolKits)
    var tools: [FROTool]?

    init(
        id: UUID = UUID(),
        name: String = "",
        descriptionText: String? = nil,
        ownershipType: String = "personal",
        toolType: String? = nil,
        createdAt: Date = Date(),
        photoFileNames: [String]? = nil
    ) {
        self.id = id
        self.name = name
        self.descriptionText = descriptionText
        self.ownershipType = ownershipType
        self.toolType = toolType
        self.createdAt = createdAt
        self.photoFileNames = photoFileNames
    }
}

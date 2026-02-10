import Foundation
import SwiftData

@Model
final class FROToolGroup: FROIdentifiable {
    var id: UUID
    var name: String
    var sortOrder: Int
    var ownershipType: String
    var toolType: String?
    var measurementType: String?
    var photoFileNames: [String]?

    @Relationship(deleteRule: .cascade, inverse: \FROToolGroup.parentGroup)
    var childGroups: [FROToolGroup]?

    var parentGroup: FROToolGroup?

    @Relationship(deleteRule: .nullify, inverse: \FROTool.group)
    var tools: [FROTool]?

    init(
        id: UUID = UUID(),
        name: String = "",
        sortOrder: Int = 0,
        ownershipType: String = "personal",
        toolType: String? = nil,
        measurementType: String? = "sae",
        photoFileNames: [String]? = nil
    ) {
        self.id = id
        self.name = name
        self.sortOrder = sortOrder
        self.ownershipType = ownershipType
        self.toolType = toolType
        self.measurementType = measurementType
        self.photoFileNames = photoFileNames
    }
}

import Foundation
import SwiftData

@Model
final class FROTool: FROIdentifiable {
    var id: UUID
    var name: String
    var aliases: [String]?
    var ownershipType: String
    var borrowedFrom: String?
    var notes: String?
    var createdAt: Date
    var isInGarage: Bool
    var photoFileNames: [String]?

    var group: FROToolGroup?
    var jobRecords: [FROJob]?
    var toolKits: [FROToolKit]?

    init(
        id: UUID = UUID(),
        name: String = "",
        aliases: [String]? = nil,
        ownershipType: String = "personal",
        borrowedFrom: String? = nil,
        notes: String? = nil,
        createdAt: Date = Date(),
        isInGarage: Bool = true,
        photoFileNames: [String]? = nil
    ) {
        self.id = id
        self.name = name
        self.aliases = aliases
        self.ownershipType = ownershipType
        self.borrowedFrom = borrowedFrom
        self.notes = notes
        self.createdAt = createdAt
        self.isInGarage = isInGarage
        self.photoFileNames = photoFileNames
    }
}

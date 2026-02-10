import Foundation
import SwiftData

@Model
final class FROChemical: FROIdentifiable {
    var id: UUID
    var name: String
    var category: String
    var size: String?
    var spec: String?
    var notes: String?
    var createdAt: Date
    var isInGarage: Bool

    var jobRecords: [FROJob]?

    init(
        id: UUID = UUID(),
        name: String = "",
        category: String = "other",
        size: String? = nil,
        spec: String? = nil,
        notes: String? = nil,
        createdAt: Date = Date(),
        isInGarage: Bool = true
    ) {
        self.id = id
        self.name = name
        self.category = category
        self.size = size
        self.spec = spec
        self.notes = notes
        self.createdAt = createdAt
        self.isInGarage = isInGarage
    }
}

import Foundation
import SwiftData

@Model
final class FROPart: FROIdentifiable {
    var id: UUID
    var partNumber: String
    var alternatePartNumber: String?
    var nomenclature: String
    var nsn: String?
    var quantity: Int
    var unitOfMeasure: String?
    var notes: String?

    var jobRecords: [FROJob]?

    init(
        id: UUID = UUID(),
        partNumber: String = "",
        alternatePartNumber: String? = nil,
        nomenclature: String = "",
        nsn: String? = nil,
        quantity: Int = 1,
        unitOfMeasure: String? = nil,
        notes: String? = nil
    ) {
        self.id = id
        self.partNumber = partNumber
        self.alternatePartNumber = alternatePartNumber
        self.nomenclature = nomenclature
        self.nsn = nsn
        self.quantity = quantity
        self.unitOfMeasure = unitOfMeasure
        self.notes = notes
    }
}

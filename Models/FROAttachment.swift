import Foundation
import SwiftData

@Model
final class FROAttachment: FROIdentifiable {
    var id: UUID
    var fileName: String
    var fileType: String
    var createdAt: Date
    var notes: String?

    init(
        id: UUID = UUID(),
        fileName: String = "",
        fileType: String = "photo",
        createdAt: Date = Date(),
        notes: String? = nil
    ) {
        self.id = id
        self.fileName = fileName
        self.fileType = fileType
        self.createdAt = createdAt
        self.notes = notes
    }
}

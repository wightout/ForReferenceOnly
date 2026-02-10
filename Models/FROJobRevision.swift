import Foundation
import SwiftData

@Model
final class FROJobRevision: FROIdentifiable {
    var id: UUID
    var versionNumber: Int
    var snapshotData: Data?
    var editedAt: Date
    var editNotes: String?

    var jobRecord: FROJob?

    init(
        id: UUID = UUID(),
        versionNumber: Int = 0,
        snapshotData: Data? = nil,
        editedAt: Date = Date(),
        editNotes: String? = nil
    ) {
        self.id = id
        self.versionNumber = versionNumber
        self.snapshotData = snapshotData
        self.editedAt = editedAt
        self.editNotes = editNotes
    }
}

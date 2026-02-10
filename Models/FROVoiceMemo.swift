import Foundation
import SwiftData

@Model
final class FROVoiceMemo: FROIdentifiable {
    var id: UUID
    var audioFilePath: String?
    var transcriptionText: String?
    var transcriptionStatus: String
    var identifiedTools: [String]?
    var identifiedConsumables: [String]?
    var identifiedChemicals: [String]?
    var createdAt: Date

    var jobRecord: FROJob?

    init(
        id: UUID = UUID(),
        audioFilePath: String? = nil,
        transcriptionText: String? = nil,
        transcriptionStatus: String = "pending",
        identifiedTools: [String]? = nil,
        identifiedConsumables: [String]? = nil,
        identifiedChemicals: [String]? = nil,
        createdAt: Date = Date()
    ) {
        self.id = id
        self.audioFilePath = audioFilePath
        self.transcriptionText = transcriptionText
        self.transcriptionStatus = transcriptionStatus
        self.identifiedTools = identifiedTools
        self.identifiedConsumables = identifiedConsumables
        self.identifiedChemicals = identifiedChemicals
        self.createdAt = createdAt
    }
}

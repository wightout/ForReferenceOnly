import Foundation
import SwiftData
import Combine

/// ViewModel for the import staging review screen.
/// Drives the conflict resolution UI without exposing persistence logic to the View.
@MainActor
@Observable
final class ImportStagingViewModel {

    // MARK: - Published State

    var stagingRecords: [FROImportStaging] = []
    var isLoading = false
    var errorMessage: String?
    var isCommitting = false
    var commitComplete = false

    // MARK: - Computed Properties

    var sessionId: UUID?

    var totalCount: Int { stagingRecords.count }

    var conflictCount: Int {
        stagingRecords.filter { $0.conflictType != nil }.count
    }

    var unresolvedCount: Int {
        stagingRecords.filter { $0.conflictType != nil && $0.resolution == nil }.count
    }

    var canCommit: Bool {
        unresolvedCount == 0 && !stagingRecords.isEmpty
    }

    /// Records grouped by entity type for display
    var groupedRecords: [(entityType: String, records: [FROImportStaging])] {
        let grouped = Dictionary(grouping: stagingRecords) { $0.entityType }
        let order = ["toolGroup", "toolKit", "tool", "consumable", "chemical", "part", "job", "jobRevision", "voiceMemo"]
        return order.compactMap { type in
            guard let records = grouped[type], !records.isEmpty else { return nil }
            return (entityType: type, records: records)
        }
    }

    // MARK: - Decode Helpers

    private let decoder = JSONDecoder()

    func decodedName(for record: FROImportStaging) -> String {
        struct NameOnly: Decodable { let name: String? }
        struct PartName: Decodable { let partNumber: String?; let nomenclature: String? }
        struct JobName: Decodable { let aircraftType: String?; let system: String? }

        switch record.entityType {
        case "tool", "toolGroup", "toolKit", "consumable", "chemical":
            if let payload = try? decoder.decode(NameOnly.self, from: record.jsonData) {
                return payload.name ?? "Unknown"
            }
        case "part":
            if let payload = try? decoder.decode(PartName.self, from: record.jsonData) {
                return payload.nomenclature ?? payload.partNumber ?? "Unknown Part"
            }
        case "job":
            if let payload = try? decoder.decode(JobName.self, from: record.jsonData) {
                return [payload.aircraftType, payload.system].compactMap { $0 }.joined(separator: " — ")
            }
        default:
            break
        }
        return record.entityType
    }

    func displayEntityType(_ type: String) -> String {
        switch type {
        case "toolGroup": return "Tool Sets"
        case "toolKit": return "Tool Kits"
        case "tool": return "Tools"
        case "consumable": return "Consumables"
        case "chemical": return "Chemicals"
        case "part": return "Parts"
        case "job": return "Jobs"
        case "jobRevision": return "Job Revisions"
        case "voiceMemo": return "Voice Memos"
        default: return type.capitalized
        }
    }

    func conflictDescription(for record: FROImportStaging) -> String? {
        switch record.conflictType {
        case "uuid_match":
            return "Same item exists (UUID match)"
        case "name_match":
            return "Similar item exists (name match)"
        default:
            return nil
        }
    }

    // MARK: - Actions

    func loadStagingRecords(sessionId: UUID, repository: FRORepository) {
        self.sessionId = sessionId
        isLoading = true
        errorMessage = nil

        do {
            let all = try repository.fetchAll(FROImportStaging.self, sortBy: [SortDescriptor(\.createdAt)])
            stagingRecords = all.filter { $0.importSessionId == sessionId }
            isLoading = false
        } catch {
            errorMessage = error.localizedDescription
            isLoading = false
        }
    }

    func setResolution(_ resolution: String, for record: FROImportStaging) {
        record.resolution = resolution
        record.status = "resolved"
    }

    func resolveAllConflicts(with resolution: String) {
        for record in stagingRecords where record.conflictType != nil && record.resolution == nil {
            record.resolution = resolution
            record.status = "resolved"
        }
    }

    func commitImport(repository: FRORepository) {
        guard let sessionId = sessionId, canCommit else { return }
        isCommitting = true
        errorMessage = nil

        do {
            try ImportExportService.shared.commitImport(sessionId: sessionId, repository: repository)
            commitComplete = true
            isCommitting = false
        } catch {
            errorMessage = error.localizedDescription
            isCommitting = false
        }
    }

    func cancelImport(repository: FRORepository) {
        guard let sessionId = sessionId else { return }
        do {
            try ImportExportService.shared.cancelImport(sessionId: sessionId, repository: repository)
        } catch {
            print("ImportStagingViewModel: Cancel failed — \(error)")
        }
    }
}

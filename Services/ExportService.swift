import Foundation
import SwiftData

/// ExportService handles exporting all app data to JSON format for backup purposes.
/// Exports job records, tools, consumables, chemicals, tool groups, and tool kits.
/// Feature #86: Export job record data for backup
class ExportService {

    // MARK: - Singleton

    nonisolated(unsafe) static let shared = ExportService()

    private init() {}

    // MARK: - Export Data Structures

    /// Root structure for the exported backup file
    struct FROBackup: Codable {
        let version: String
        let exportedAt: Date
        let appVersion: String
        let jobRecords: [JobRecordExport]
        let tools: [ToolExport]
        let toolGroups: [ToolGroupExport]
        let toolKits: [ToolKitExport]
        let consumables: [ConsumableExport]
        let chemicals: [ChemicalExport]
        let parts: [PartExport]
    }

    struct JobRecordExport: Codable {
        let id: String
        let aircraftType: String
        let aircraftSerialNumber: String?
        let nNumber: String?
        let system: String
        let component: String?
        let jobDate: Date?
        let taskDescription: String?
        let tmReferences: String?
        let notes: String?
        let recommendations: String?
        let currentVersion: Int
        let createdAt: Date?
        let updatedAt: Date?
        let toolIds: [String]
        let consumableIds: [String]
        let chemicalIds: [String]
        let partIds: [String]
    }

    struct ToolExport: Codable {
        let id: String
        let name: String
        let aliases: [String]?
        let ownershipType: String?
        let borrowedFrom: String?
        let notes: String?
        let createdAt: Date?
        let groupId: String?
    }

    struct ToolGroupExport: Codable {
        let id: String
        let name: String
        let sortOrder: Int
        let parentGroupId: String?
        let ownershipType: String?
        let toolType: String?
        let measurementType: String?
    }

    struct ToolKitExport: Codable {
        let id: String
        let name: String
        let descriptionText: String?
        let ownershipType: String?
        let toolType: String?
        let createdAt: Date?
        let toolIds: [String]
    }

    struct ConsumableExport: Codable {
        let id: String
        let name: String
        let category: String?
        let size: String?
        let spec: String?
        let notes: String?
        let createdAt: Date?
    }

    struct ChemicalExport: Codable {
        let id: String
        let name: String
        let category: String?
        let size: String?
        let spec: String?
        let notes: String?
        let createdAt: Date?
    }

    struct PartExport: Codable {
        let id: String
        let partNumber: String?
        let alternatePartNumber: String?
        let nomenclature: String?
        let nsn: String?
        let quantity: Int
        let unitOfMeasure: String?
        let notes: String?
    }

    // MARK: - Export Result

    struct ExportResult {
        let success: Bool
        let fileURL: URL?
        let error: String?
        let counts: ExportCounts?
    }

    struct ExportCounts {
        let jobRecords: Int
        let tools: Int
        let toolGroups: Int
        let toolKits: Int
        let consumables: Int
        let chemicals: Int
        let parts: Int

        var total: Int {
            jobRecords + tools + toolGroups + toolKits + consumables + chemicals + parts
        }
    }

    // MARK: - Export Functions

    /// Exports all data from Core Data to a JSON file
    /// - Parameter context: The managed object context to fetch data from
    /// - Returns: ExportResult with file URL on success or error message on failure
    func exportAllData(context: ModelContext) -> ExportResult {
        do {
            // Fetch all entities
            let jobRecords = try fetchJobRecords(context: context)
            let tools = try fetchTools(context: context)
            let toolGroups = try fetchToolGroups(context: context)
            let toolKits = try fetchToolKits(context: context)
            let consumables = try fetchConsumables(context: context)
            let chemicals = try fetchChemicals(context: context)
            let parts = try fetchParts(context: context)

            // Get app version
            let appVersion = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "0.1.0"

            // Create backup structure
            let backup = FROBackup(
                version: "1.0",
                exportedAt: Date(),
                appVersion: appVersion,
                jobRecords: jobRecords,
                tools: tools,
                toolGroups: toolGroups,
                toolKits: toolKits,
                consumables: consumables,
                chemicals: chemicals,
                parts: parts
            )

            // Encode to JSON
            let encoder = JSONEncoder()
            encoder.dateEncodingStrategy = .iso8601
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            let jsonData = try encoder.encode(backup)

            // Generate filename with timestamp
            let dateFormatter = DateFormatter()
            dateFormatter.dateFormat = "yyyy-MM-dd_HHmmss"
            let timestamp = dateFormatter.string(from: Date())
            let filename = "FRO_Backup_\(timestamp).json"

            // Write to temp directory for sharing
            let tempDir = FileManager.default.temporaryDirectory
            let fileURL = tempDir.appendingPathComponent(filename)
            try jsonData.write(to: fileURL)

            let counts = ExportCounts(
                jobRecords: jobRecords.count,
                tools: tools.count,
                toolGroups: toolGroups.count,
                toolKits: toolKits.count,
                consumables: consumables.count,
                chemicals: chemicals.count,
                parts: parts.count
            )

            print("Export completed: \(counts.total) items exported to \(fileURL.path)")

            return ExportResult(success: true, fileURL: fileURL, error: nil, counts: counts)

        } catch {
            print("Export failed: \(error.localizedDescription)")
            return ExportResult(success: false, fileURL: nil, error: error.localizedDescription, counts: nil)
        }
    }

    // MARK: - Fetch Helpers

    private func fetchJobRecords(context: ModelContext) throws -> [JobRecordExport] {
        let descriptor = FetchDescriptor<FROJob>(sortBy: [SortDescriptor(\FROJob.createdAt, order: .reverse)])
        let records = try context.fetch(descriptor)

        return records.map { record in
            let toolIds: [String] = record.tools?.map { $0.id.uuidString } ?? []
            let consumableIds: [String] = record.consumables?.map { $0.id.uuidString } ?? []
            let chemicalIds: [String] = record.chemicals?.map { $0.id.uuidString } ?? []
            let partIds: [String] = record.parts?.map { $0.id.uuidString } ?? []

            return JobRecordExport(
                id: record.id.uuidString,
                aircraftType: record.aircraftType,
                aircraftSerialNumber: record.aircraftSerialNumber,
                nNumber: record.nNumber,
                system: record.system,
                component: record.component,
                jobDate: record.jobDate,
                taskDescription: record.taskDescription,
                tmReferences: record.tmReferences,
                notes: record.notes,
                recommendations: record.recommendations,
                currentVersion: record.currentVersion,
                createdAt: record.createdAt,
                updatedAt: record.updatedAt,
                toolIds: toolIds,
                consumableIds: consumableIds,
                chemicalIds: chemicalIds,
                partIds: partIds
            )
        }
    }

    private func fetchTools(context: ModelContext) throws -> [ToolExport] {
        let descriptor = FetchDescriptor<FROTool>(sortBy: [SortDescriptor(\FROTool.name)])
        let tools = try context.fetch(descriptor)

        return tools.map { tool in
            ToolExport(
                id: tool.id.uuidString,
                name: tool.name,
                aliases: tool.aliases,
                ownershipType: tool.ownershipType,
                borrowedFrom: tool.borrowedFrom,
                notes: tool.notes,
                createdAt: tool.createdAt,
                groupId: tool.group?.id.uuidString
            )
        }
    }

    private func fetchToolGroups(context: ModelContext) throws -> [ToolGroupExport] {
        let descriptor = FetchDescriptor<FROToolGroup>(sortBy: [SortDescriptor(\FROToolGroup.sortOrder)])
        let groups = try context.fetch(descriptor)

        return groups.map { group in
            ToolGroupExport(
                id: group.id.uuidString,
                name: group.name,
                sortOrder: group.sortOrder,
                parentGroupId: group.parentGroup?.id.uuidString,
                ownershipType: group.ownershipType,
                toolType: group.toolType,
                measurementType: group.measurementType
            )
        }
    }

    private func fetchToolKits(context: ModelContext) throws -> [ToolKitExport] {
        let descriptor = FetchDescriptor<FROToolKit>(sortBy: [SortDescriptor(\FROToolKit.name)])
        let kits = try context.fetch(descriptor)

        return kits.map { kit in
            let toolIds: [String] = kit.tools?.map { $0.id.uuidString } ?? []

            return ToolKitExport(
                id: kit.id.uuidString,
                name: kit.name,
                descriptionText: kit.descriptionText,
                ownershipType: kit.ownershipType,
                toolType: kit.toolType,
                createdAt: kit.createdAt,
                toolIds: toolIds
            )
        }
    }

    private func fetchConsumables(context: ModelContext) throws -> [ConsumableExport] {
        let descriptor = FetchDescriptor<FROConsumable>(sortBy: [SortDescriptor(\FROConsumable.name)])
        let consumables = try context.fetch(descriptor)

        return consumables.map { consumable in
            ConsumableExport(
                id: consumable.id.uuidString,
                name: consumable.name,
                category: consumable.category,
                size: consumable.size,
                spec: consumable.spec,
                notes: consumable.notes,
                createdAt: consumable.createdAt
            )
        }
    }

    private func fetchChemicals(context: ModelContext) throws -> [ChemicalExport] {
        let descriptor = FetchDescriptor<FROChemical>(sortBy: [SortDescriptor(\FROChemical.name)])
        let chemicals = try context.fetch(descriptor)

        return chemicals.map { chemical in
            ChemicalExport(
                id: chemical.id.uuidString,
                name: chemical.name,
                category: chemical.category,
                size: chemical.size,
                spec: chemical.spec,
                notes: chemical.notes,
                createdAt: chemical.createdAt
            )
        }
    }

    private func fetchParts(context: ModelContext) throws -> [PartExport] {
        let descriptor = FetchDescriptor<FROPart>(sortBy: [SortDescriptor(\FROPart.nomenclature)])
        let parts = try context.fetch(descriptor)

        return parts.map { part in
            PartExport(
                id: part.id.uuidString,
                partNumber: part.partNumber,
                alternatePartNumber: part.alternatePartNumber,
                nomenclature: part.nomenclature,
                nsn: part.nsn,
                quantity: part.quantity,
                unitOfMeasure: part.unitOfMeasure,
                notes: part.notes
            )
        }
    }
}

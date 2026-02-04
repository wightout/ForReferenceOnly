import Foundation
import CoreData

/// ExportService handles exporting all app data to JSON format for backup purposes.
/// Exports job records, tools, consumables, chemicals, tool groups, and tool kits.
/// Feature #86: Export job record data for backup
class ExportService {

    // MARK: - Singleton

    static let shared = ExportService()

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
    }

    struct ToolKitExport: Codable {
        let id: String
        let name: String
        let descriptionText: String?
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

        var total: Int {
            jobRecords + tools + toolGroups + toolKits + consumables + chemicals
        }
    }

    // MARK: - Export Functions

    /// Exports all data from Core Data to a JSON file
    /// - Parameter context: The managed object context to fetch data from
    /// - Returns: ExportResult with file URL on success or error message on failure
    func exportAllData(context: NSManagedObjectContext) -> ExportResult {
        do {
            // Fetch all entities
            let jobRecords = try fetchJobRecords(context: context)
            let tools = try fetchTools(context: context)
            let toolGroups = try fetchToolGroups(context: context)
            let toolKits = try fetchToolKits(context: context)
            let consumables = try fetchConsumables(context: context)
            let chemicals = try fetchChemicals(context: context)

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
                chemicals: chemicals
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
                chemicals: chemicals.count
            )

            print("Export completed: \(counts.total) items exported to \(fileURL.path)")

            return ExportResult(success: true, fileURL: fileURL, error: nil, counts: counts)

        } catch {
            print("Export failed: \(error.localizedDescription)")
            return ExportResult(success: false, fileURL: nil, error: error.localizedDescription, counts: nil)
        }
    }

    // MARK: - Fetch Helpers

    private func fetchJobRecords(context: NSManagedObjectContext) throws -> [JobRecordExport] {
        let request: NSFetchRequest<JobRecord> = JobRecord.fetchRequest()
        request.sortDescriptors = [NSSortDescriptor(keyPath: \JobRecord.createdAt, ascending: false)]

        let records = try context.fetch(request)

        return records.map { record in
            // Get related tool IDs
            let toolIds: [String] = (record.tools as? Set<Tool>)?
                .compactMap { $0.id?.uuidString } ?? []

            // Get related consumable IDs
            let consumableIds: [String] = (record.consumables as? Set<Consumable>)?
                .compactMap { $0.id?.uuidString } ?? []

            // Get related chemical IDs
            let chemicalIds: [String] = (record.chemicals as? Set<Chemical>)?
                .compactMap { $0.id?.uuidString } ?? []

            return JobRecordExport(
                id: record.id?.uuidString ?? UUID().uuidString,
                aircraftType: record.aircraftType ?? "",
                aircraftSerialNumber: record.aircraftSerialNumber,
                nNumber: record.nNumber,
                system: record.system ?? "",
                component: record.component,
                jobDate: record.jobDate,
                taskDescription: record.taskDescription,
                tmReferences: record.tmReferences,
                notes: record.notes,
                recommendations: record.recommendations,
                currentVersion: Int(record.currentVersion),
                createdAt: record.createdAt,
                updatedAt: record.updatedAt,
                toolIds: toolIds,
                consumableIds: consumableIds,
                chemicalIds: chemicalIds
            )
        }
    }

    private func fetchTools(context: NSManagedObjectContext) throws -> [ToolExport] {
        let request: NSFetchRequest<Tool> = Tool.fetchRequest()
        request.sortDescriptors = [NSSortDescriptor(keyPath: \Tool.name, ascending: true)]

        let tools = try context.fetch(request)

        return tools.map { tool in
            // Convert aliases from NSObject to [String]
            let aliasArray: [String]?
            if let aliasData = tool.aliases as? [String] {
                aliasArray = aliasData
            } else if let aliasData = tool.aliases as? NSArray {
                aliasArray = aliasData.compactMap { $0 as? String }
            } else {
                aliasArray = nil
            }

            return ToolExport(
                id: tool.id?.uuidString ?? UUID().uuidString,
                name: tool.name ?? "",
                aliases: aliasArray,
                ownershipType: tool.ownershipType,
                borrowedFrom: tool.borrowedFrom,
                notes: tool.notes,
                createdAt: tool.createdAt,
                groupId: tool.group?.id?.uuidString
            )
        }
    }

    private func fetchToolGroups(context: NSManagedObjectContext) throws -> [ToolGroupExport] {
        let request: NSFetchRequest<ToolGroup> = ToolGroup.fetchRequest()
        request.sortDescriptors = [NSSortDescriptor(keyPath: \ToolGroup.sortOrder, ascending: true)]

        let groups = try context.fetch(request)

        return groups.map { group in
            ToolGroupExport(
                id: group.id?.uuidString ?? UUID().uuidString,
                name: group.name ?? "",
                sortOrder: Int(group.sortOrder),
                parentGroupId: group.parentGroup?.id?.uuidString
            )
        }
    }

    private func fetchToolKits(context: NSManagedObjectContext) throws -> [ToolKitExport] {
        let request: NSFetchRequest<ToolKit> = ToolKit.fetchRequest()
        request.sortDescriptors = [NSSortDescriptor(keyPath: \ToolKit.name, ascending: true)]

        let kits = try context.fetch(request)

        return kits.map { kit in
            let toolIds: [String] = (kit.tools as? Set<Tool>)?
                .compactMap { $0.id?.uuidString } ?? []

            return ToolKitExport(
                id: kit.id?.uuidString ?? UUID().uuidString,
                name: kit.name ?? "",
                descriptionText: kit.descriptionText,
                createdAt: kit.createdAt,
                toolIds: toolIds
            )
        }
    }

    private func fetchConsumables(context: NSManagedObjectContext) throws -> [ConsumableExport] {
        let request: NSFetchRequest<Consumable> = Consumable.fetchRequest()
        request.sortDescriptors = [NSSortDescriptor(keyPath: \Consumable.name, ascending: true)]

        let consumables = try context.fetch(request)

        return consumables.map { consumable in
            ConsumableExport(
                id: consumable.id?.uuidString ?? UUID().uuidString,
                name: consumable.name ?? "",
                category: consumable.category,
                size: consumable.size,
                spec: consumable.spec,
                notes: consumable.notes,
                createdAt: consumable.createdAt
            )
        }
    }

    private func fetchChemicals(context: NSManagedObjectContext) throws -> [ChemicalExport] {
        let request: NSFetchRequest<Chemical> = Chemical.fetchRequest()
        request.sortDescriptors = [NSSortDescriptor(keyPath: \Chemical.name, ascending: true)]

        let chemicals = try context.fetch(request)

        return chemicals.map { chemical in
            ChemicalExport(
                id: chemical.id?.uuidString ?? UUID().uuidString,
                name: chemical.name ?? "",
                category: chemical.category,
                size: chemical.size,
                spec: chemical.spec,
                notes: chemical.notes,
                createdAt: chemical.createdAt
            )
        }
    }
}

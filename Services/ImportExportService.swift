import Foundation
import SwiftData

/// Unified import/export service for all FRO data operations.
/// Per CLAUDE.md: "Import/Export — Isolated in ImportExportService."
/// Uses FRORepository for all data access — no direct ModelContext queries.
final class ImportExportService {

    static let shared = ImportExportService()

    /// File extension for full backup archives
    static let backupExtension = "frobackup"

    private init() {}

    // MARK: - v2 JSON Schema

    struct BackupPayload: Codable {
        let version: Int
        let exportedAt: String
        let appVersion: String
        let entities: EntityPayload
    }

    struct EntityPayload: Codable {
        var tools: [ToolPayload]
        var toolGroups: [ToolGroupPayload]
        var toolKits: [ToolKitPayload]
        var jobs: [JobPayload]
        var jobRevisions: [JobRevisionPayload]
        var consumables: [ConsumablePayload]
        var chemicals: [ChemicalPayload]
        var parts: [PartPayload]
        var voiceMemos: [VoiceMemoPayload]
        var attachments: [AttachmentPayload]
    }

    struct ToolPayload: Codable {
        let id: String
        let name: String
        let aliases: [String]?
        let ownershipType: String
        let borrowedFrom: String?
        let notes: String?
        let createdAt: String
        let isInGarage: Bool
        let photoFileNames: [String]?
        let groupId: String?
        let toolKitIds: [String]?
    }

    struct ToolGroupPayload: Codable {
        let id: String
        let name: String
        let sortOrder: Int
        let ownershipType: String
        let toolType: String?
        let measurementType: String?
        let photoFileNames: [String]?
        let parentGroupId: String?
    }

    struct ToolKitPayload: Codable {
        let id: String
        let name: String
        let descriptionText: String?
        let ownershipType: String
        let toolType: String?
        let createdAt: String
        let photoFileNames: [String]?
        let toolIds: [String]?
    }

    struct JobPayload: Codable {
        let id: String
        let aircraftType: String
        let aircraftSerialNumber: String?
        let nNumber: String?
        let system: String
        let component: String?
        let jobDate: String
        let taskDescription: String?
        let tmReferences: String?
        let notes: String?
        let recommendations: String?
        let createdAt: String
        let updatedAt: String
        let currentVersion: Int
        let toolIds: [String]?
        let consumableIds: [String]?
        let chemicalIds: [String]?
        let partIds: [String]?
    }

    struct JobRevisionPayload: Codable {
        let id: String
        let versionNumber: Int
        let snapshotData: String?  // Base64-encoded
        let editedAt: String
        let editNotes: String?
        let jobId: String?
    }

    struct ConsumablePayload: Codable {
        let id: String
        let name: String
        let category: String
        let size: String?
        let spec: String?
        let notes: String?
        let createdAt: String
        let isInGarage: Bool
    }

    struct ChemicalPayload: Codable {
        let id: String
        let name: String
        let category: String
        let size: String?
        let spec: String?
        let notes: String?
        let createdAt: String
        let isInGarage: Bool
    }

    struct PartPayload: Codable {
        let id: String
        let partNumber: String
        let alternatePartNumber: String?
        let nomenclature: String
        let nsn: String?
        let quantity: Int
        let unitOfMeasure: String?
        let notes: String?
    }

    struct VoiceMemoPayload: Codable {
        let id: String
        let audioFilePath: String?
        let transcriptionText: String?
        let transcriptionStatus: String
        let identifiedTools: [String]?
        let identifiedConsumables: [String]?
        let identifiedChemicals: [String]?
        let createdAt: String
        let jobId: String?
    }

    struct AttachmentPayload: Codable {
        let id: String
        let fileName: String
        let fileType: String
        let createdAt: String
        let notes: String?
        let entityId: String?
        let entityType: String?
        let relativePath: String?
    }

    // MARK: - Date Formatting

    private static let isoFormatter: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f
    }()

    private static func formatDate(_ date: Date) -> String {
        isoFormatter.string(from: date)
    }

    private static func parseDate(_ string: String) -> Date {
        if let date = isoFormatter.date(from: string) { return date }
        // Try without fractional seconds
        let basic = ISO8601DateFormatter()
        if let date = basic.date(from: string) { return date }
        // Try date-only format
        let dateOnly = DateFormatter()
        dateOnly.dateFormat = "yyyy-MM-dd"
        dateOnly.locale = Locale(identifier: "en_US_POSIX")
        if let date = dateOnly.date(from: string) { return date }
        return Date()
    }

    // MARK: - Export Backup (JSON only)

    /// Exports all data to a v2 JSON backup file.
    /// - Parameter repository: FRORepository for data access
    /// - Returns: URL to the exported JSON file, or nil on failure
    func exportBackup(repository: FRORepository) -> URL? {
        do {
            let payload = try buildBackupPayload(repository: repository)

            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            let jsonData = try encoder.encode(payload)

            let dateFormatter = DateFormatter()
            dateFormatter.dateFormat = "yyyy-MM-dd_HHmmss"
            let timestamp = dateFormatter.string(from: Date())
            let filename = "FRO_Backup_\(timestamp).json"

            let tempDir = FileManager.default.temporaryDirectory
            let fileURL = tempDir.appendingPathComponent(filename)
            try jsonData.write(to: fileURL)

            print("ImportExportService: Exported backup to \(fileURL.lastPathComponent)")
            return fileURL
        } catch {
            print("ImportExportService: Export backup failed — \(error)")
            return nil
        }
    }

    // MARK: - Export Archive (.frobackup)

    /// Exports all data as a .frobackup archive (JSON + photos ZIP).
    /// - Parameter repository: FRORepository for data access
    /// - Returns: URL to the .frobackup file, or nil on failure
    func exportArchive(repository: FRORepository) -> URL? {
        do {
            let payload = try buildBackupPayload(repository: repository)

            let workDir = FileManager.default.temporaryDirectory
                .appendingPathComponent("frobackup_\(UUID().uuidString)", isDirectory: true)
            let attachmentsDir = workDir.appendingPathComponent("attachments", isDirectory: true)
            try FileManager.default.createDirectory(at: workDir, withIntermediateDirectories: true)
            try FileManager.default.createDirectory(at: attachmentsDir, withIntermediateDirectories: true)

            // Write export.json
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            let jsonData = try encoder.encode(payload)
            try jsonData.write(to: workDir.appendingPathComponent("export.json"))

            // Copy photos for tools, toolGroups, toolKits
            let photoService = ToolPhotoService.shared
            let allToolIds = payload.entities.tools.map { $0.id }
            let allGroupIds = payload.entities.toolGroups.map { $0.id }
            let allKitIds = payload.entities.toolKits.map { $0.id }

            for entityId in allToolIds + allGroupIds + allKitIds {
                guard let uuid = UUID(uuidString: entityId) else { continue }
                let entityPhotosDir = photoService.photoDirectory(for: uuid)
                guard FileManager.default.fileExists(atPath: entityPhotosDir.path) else { continue }

                let destDir = attachmentsDir.appendingPathComponent(entityId, isDirectory: true)
                try? FileManager.default.copyItem(at: entityPhotosDir, to: destDir)
            }

            // Create .frobackup archive
            let dateFormatter = DateFormatter()
            dateFormatter.dateFormat = "yyyy-MM-dd_HHmmss"
            let timestamp = dateFormatter.string(from: Date())
            let archiveURL = FileManager.default.temporaryDirectory
                .appendingPathComponent("FRO_Backup_\(timestamp).\(Self.backupExtension)")
            try? FileManager.default.removeItem(at: archiveURL)

            guard ZipUtility.createArchive(from: workDir, to: archiveURL) else {
                try? FileManager.default.removeItem(at: workDir)
                return nil
            }

            try? FileManager.default.removeItem(at: workDir)
            print("ImportExportService: Exported archive to \(archiveURL.lastPathComponent)")
            return archiveURL
        } catch {
            print("ImportExportService: Export archive failed — \(error)")
            return nil
        }
    }

    // MARK: - Export Tools (.frotool)

    /// Exports tools as a .frotool bundle (v2 format with UUIDs).
    /// - Parameters:
    ///   - tools: Array of FROTool objects to export
    ///   - repository: FRORepository for data access
    /// - Returns: URL to the .frotool file, or nil on failure
    func exportTools(_ tools: [FROTool], repository: FRORepository) -> URL? {
        guard !tools.isEmpty else { return nil }

        do {
            let toolPayloads = tools.map { buildToolPayload($0) }

            // Collect groups and kits referenced by these tools
            var groupPayloads: [ToolGroupPayload] = []
            var kitPayloads: [ToolKitPayload] = []
            var seenGroupIds = Set<UUID>()
            var seenKitIds = Set<UUID>()

            for tool in tools {
                if let group = tool.group, !seenGroupIds.contains(group.id) {
                    seenGroupIds.insert(group.id)
                    groupPayloads.append(buildToolGroupPayload(group))
                    // Include parent chain
                    var parent = group.parentGroup
                    while let p = parent, !seenGroupIds.contains(p.id) {
                        seenGroupIds.insert(p.id)
                        groupPayloads.append(buildToolGroupPayload(p))
                        parent = p.parentGroup
                    }
                }
                if let kits = tool.toolKits {
                    for kit in kits where !seenKitIds.contains(kit.id) {
                        seenKitIds.insert(kit.id)
                        kitPayloads.append(buildToolKitPayload(kit))
                    }
                }
            }

            let payload = BackupPayload(
                version: 2,
                exportedAt: Self.formatDate(Date()),
                appVersion: Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "0.2.0",
                entities: EntityPayload(
                    tools: toolPayloads,
                    toolGroups: groupPayloads,
                    toolKits: kitPayloads,
                    jobs: [],
                    jobRevisions: [],
                    consumables: [],
                    chemicals: [],
                    parts: [],
                    voiceMemos: [],
                    attachments: []
                )
            )

            let workDir = FileManager.default.temporaryDirectory
                .appendingPathComponent("frotool_export_\(UUID().uuidString)", isDirectory: true)
            let photosDir = workDir.appendingPathComponent("photos", isDirectory: true)
            try FileManager.default.createDirectory(at: workDir, withIntermediateDirectories: true)
            try FileManager.default.createDirectory(at: photosDir, withIntermediateDirectories: true)

            // Write export.json
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            let jsonData = try encoder.encode(payload)
            try jsonData.write(to: workDir.appendingPathComponent("export.json"))

            // Copy photos
            let photoService = ToolPhotoService.shared
            for tool in tools {
                let toolPhotosDir = photoService.photoDirectory(for: tool.id)
                guard FileManager.default.fileExists(atPath: toolPhotosDir.path) else { continue }
                let destDir = photosDir.appendingPathComponent(tool.id.uuidString, isDirectory: true)
                try? FileManager.default.copyItem(at: toolPhotosDir, to: destDir)
            }

            // Create .frotool bundle
            let bundleName = generateToolBundleName(for: tools)
            let frotoolURL = FileManager.default.temporaryDirectory
                .appendingPathComponent("\(bundleName).frotool")
            try? FileManager.default.removeItem(at: frotoolURL)

            guard ZipUtility.createArchive(from: workDir, to: frotoolURL) else {
                try? FileManager.default.removeItem(at: workDir)
                return nil
            }

            try? FileManager.default.removeItem(at: workDir)
            print("ImportExportService: Exported \(tools.count) tool(s) to \(frotoolURL.lastPathComponent)")
            return frotoolURL
        } catch {
            print("ImportExportService: Tool export failed — \(error)")
            return nil
        }
    }

    // MARK: - Export Job (.frojob)

    /// Exports a single job as a .frojob bundle (v2 format with UUIDs).
    /// - Parameters:
    ///   - job: The FROJob to export
    ///   - repository: FRORepository for data access
    /// - Returns: URL to the .frojob file, or nil on failure
    func exportJob(_ job: FROJob, repository: FRORepository) -> URL? {
        do {
            let jobPayload = buildJobPayload(job)

            let toolPayloads = (job.tools ?? []).map { buildToolPayload($0) }
            let consumablePayloads = (job.consumables ?? []).map { buildConsumablePayload($0) }
            let chemicalPayloads = (job.chemicals ?? []).map { buildChemicalPayload($0) }
            let partPayloads = (job.parts ?? []).map { buildPartPayload($0) }
            let revisionPayloads = (job.revisions ?? []).map { buildJobRevisionPayload($0, jobId: job.id) }

            let payload = BackupPayload(
                version: 2,
                exportedAt: Self.formatDate(Date()),
                appVersion: Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "0.2.0",
                entities: EntityPayload(
                    tools: toolPayloads,
                    toolGroups: [],
                    toolKits: [],
                    jobs: [jobPayload],
                    jobRevisions: revisionPayloads,
                    consumables: consumablePayloads,
                    chemicals: chemicalPayloads,
                    parts: partPayloads,
                    voiceMemos: [],
                    attachments: []
                )
            )

            let workDir = FileManager.default.temporaryDirectory
                .appendingPathComponent("frojob_\(UUID().uuidString)", isDirectory: true)
            try FileManager.default.createDirectory(at: workDir, withIntermediateDirectories: true)

            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            let jsonData = try encoder.encode(payload)
            try jsonData.write(to: workDir.appendingPathComponent("export.json"))

            let bundleName = generateJobBundleName(for: job)
            let frojobURL = FileManager.default.temporaryDirectory
                .appendingPathComponent("\(bundleName).frojob")
            try? FileManager.default.removeItem(at: frojobURL)

            guard ZipUtility.createArchive(from: workDir, to: frojobURL) else {
                try? FileManager.default.removeItem(at: workDir)
                return nil
            }

            try? FileManager.default.removeItem(at: workDir)
            print("ImportExportService: Exported job '\(job.aircraftType)' to \(frojobURL.lastPathComponent)")
            return frojobURL
        } catch {
            print("ImportExportService: Job export failed — \(error)")
            return nil
        }
    }

    // MARK: - Parse Backup / Archive for Staging

    /// Parses a v2 JSON backup or .frobackup archive and creates FROImportStaging records.
    /// - Parameters:
    ///   - url: URL to the file (JSON or .frobackup)
    ///   - repository: FRORepository for conflict detection and staging insertion
    /// - Returns: Import session UUID
    func parseBackup(at url: URL, repository: FRORepository) throws -> UUID {
        let accessing = url.startAccessingSecurityScopedResource()
        defer { if accessing { url.stopAccessingSecurityScopedResource() } }

        let payload: BackupPayload
        var attachmentsDir: URL?

        if url.pathExtension == Self.backupExtension {
            // Archive — extract ZIP
            let tempDir = FileManager.default.temporaryDirectory
                .appendingPathComponent("frobackup_import_\(UUID().uuidString)", isDirectory: true)
            try ZipUtility.extractArchive(at: url, to: tempDir)
            guard ZipUtility.locateAndFlatten(jsonFile: "export.json", in: tempDir) else {
                throw ImportExportError.missingJSON("export.json")
            }
            let jsonData = try Data(contentsOf: tempDir.appendingPathComponent("export.json"))
            payload = try JSONDecoder().decode(BackupPayload.self, from: jsonData)
            let attDir = tempDir.appendingPathComponent("attachments", isDirectory: true)
            if FileManager.default.fileExists(atPath: attDir.path) {
                attachmentsDir = attDir
            }
        } else {
            // Plain JSON
            let jsonData = try Data(contentsOf: url)
            payload = try JSONDecoder().decode(BackupPayload.self, from: jsonData)
        }

        let sessionId = UUID()
        try createStagingRecords(from: payload, sessionId: sessionId, repository: repository)

        // If archive had attachments, restore photos
        if let attDir = attachmentsDir {
            restorePhotos(from: attDir)
        }

        return sessionId
    }

    /// Parses a .frotool bundle and creates staging records.
    func parseToolBundle(at url: URL, repository: FRORepository) throws -> UUID {
        let accessing = url.startAccessingSecurityScopedResource()
        defer { if accessing { url.stopAccessingSecurityScopedResource() } }

        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("frotool_import_\(UUID().uuidString)", isDirectory: true)

        try ZipUtility.extractArchive(at: url, to: tempDir)
        guard ZipUtility.locateAndFlatten(jsonFile: "export.json", in: tempDir) else {
            throw ImportExportError.missingJSON("export.json")
        }

        let jsonData = try Data(contentsOf: tempDir.appendingPathComponent("export.json"))
        let payload = try JSONDecoder().decode(BackupPayload.self, from: jsonData)

        let sessionId = UUID()
        try createStagingRecords(from: payload, sessionId: sessionId, repository: repository)

        // Copy photos from bundle
        let photosDir = tempDir.appendingPathComponent("photos", isDirectory: true)
        if FileManager.default.fileExists(atPath: photosDir.path) {
            restorePhotos(from: photosDir)
        }

        try? FileManager.default.removeItem(at: tempDir)
        return sessionId
    }

    /// Parses a .frojob bundle and creates staging records.
    func parseJobBundle(at url: URL, repository: FRORepository) throws -> UUID {
        let accessing = url.startAccessingSecurityScopedResource()
        defer { if accessing { url.stopAccessingSecurityScopedResource() } }

        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("frojob_import_\(UUID().uuidString)", isDirectory: true)

        try ZipUtility.extractArchive(at: url, to: tempDir)

        // Try export.json first (v2), then job.json (v1 compatibility)
        let jsonFileName: String
        if ZipUtility.locateAndFlatten(jsonFile: "export.json", in: tempDir) {
            jsonFileName = "export.json"
        } else if ZipUtility.locateAndFlatten(jsonFile: "job.json", in: tempDir) {
            jsonFileName = "job.json"
        } else {
            throw ImportExportError.missingJSON("export.json or job.json")
        }

        let jsonData = try Data(contentsOf: tempDir.appendingPathComponent(jsonFileName))

        let payload: BackupPayload
        if jsonFileName == "export.json" {
            payload = try JSONDecoder().decode(BackupPayload.self, from: jsonData)
        } else {
            // v1 job.json — convert to v2 payload
            let v1Bundle = try JSONDecoder().decode(JobExportService.JobExportBundle.self, from: jsonData)
            payload = convertV1JobBundle(v1Bundle)
        }

        let sessionId = UUID()
        try createStagingRecords(from: payload, sessionId: sessionId, repository: repository)

        try? FileManager.default.removeItem(at: tempDir)
        return sessionId
    }

    // MARK: - Commit Import

    /// Commits all staging records for a session, creating/updating SwiftData entities.
    /// - Parameters:
    ///   - sessionId: The import session to commit
    ///   - repository: FRORepository for entity creation and staging cleanup
    func commitImport(sessionId: UUID, repository: FRORepository) throws {
        let allStaging = try repository.fetchAll(FROImportStaging.self, sortBy: [SortDescriptor(\.createdAt)])
        let sessionRecords = allStaging.filter { $0.importSessionId == sessionId }

        let decoder = JSONDecoder()

        // Process entity types in dependency order:
        // 1. toolGroups (may have parent references)
        // 2. toolKits
        // 3. tools (reference groups and kits)
        // 4. consumables, chemicals, parts
        // 5. jobs (reference tools, consumables, chemicals, parts)
        // 6. jobRevisions (reference jobs)
        // 7. voiceMemos (reference jobs)

        let grouped = Dictionary(grouping: sessionRecords) { $0.entityType }

        // Tool Groups — process in hierarchy order (parents first)
        try commitToolGroups(grouped["toolGroup"] ?? [], decoder: decoder, repository: repository)

        // Tool Kits
        try commitToolKits(grouped["toolKit"] ?? [], decoder: decoder, repository: repository)

        // Tools
        try commitTools(grouped["tool"] ?? [], decoder: decoder, repository: repository)

        // Consumables
        try commitConsumables(grouped["consumable"] ?? [], decoder: decoder, repository: repository)

        // Chemicals
        try commitChemicals(grouped["chemical"] ?? [], decoder: decoder, repository: repository)

        // Parts
        try commitParts(grouped["part"] ?? [], decoder: decoder, repository: repository)

        // Jobs
        try commitJobs(grouped["job"] ?? [], decoder: decoder, repository: repository)

        // Job Revisions
        try commitJobRevisions(grouped["jobRevision"] ?? [], decoder: decoder, repository: repository)

        // Voice Memos
        try commitVoiceMemos(grouped["voiceMemo"] ?? [], decoder: decoder, repository: repository)

        // Clean up staging records
        for record in sessionRecords {
            repository.delete(record)
        }

        try repository.save()
        print("ImportExportService: Committed import session \(sessionId.uuidString)")
    }

    // MARK: - Cancel Import

    /// Cancels an import session by deleting all staging records.
    func cancelImport(sessionId: UUID, repository: FRORepository) throws {
        let allStaging = try repository.fetchAll(FROImportStaging.self, sortBy: [SortDescriptor(\.createdAt)])
        let sessionRecords = allStaging.filter { $0.importSessionId == sessionId }
        for record in sessionRecords {
            repository.delete(record)
        }
        try repository.save()
        print("ImportExportService: Cancelled import session \(sessionId.uuidString)")
    }

    // MARK: - Build Payload Helpers

    private func buildBackupPayload(repository: FRORepository) throws -> BackupPayload {
        let tools = try repository.fetchAll(FROTool.self, sortBy: [SortDescriptor(\.name)])
        let groups = try repository.fetchAll(FROToolGroup.self, sortBy: [SortDescriptor(\.sortOrder)])
        let kits = try repository.fetchAll(FROToolKit.self, sortBy: [SortDescriptor(\.name)])
        let jobs = try repository.fetchAll(FROJob.self, sortBy: [SortDescriptor(\.createdAt, order: .reverse)])
        let revisions = try repository.fetchAll(FROJobRevision.self, sortBy: [SortDescriptor(\.editedAt)])
        let consumables = try repository.fetchAll(FROConsumable.self, sortBy: [SortDescriptor(\.name)])
        let chemicals = try repository.fetchAll(FROChemical.self, sortBy: [SortDescriptor(\.name)])
        let parts = try repository.fetchAll(FROPart.self, sortBy: [SortDescriptor(\.nomenclature)])
        let voiceMemos = try repository.fetchAll(FROVoiceMemo.self, sortBy: [SortDescriptor(\.createdAt)])
        let attachments = try repository.fetchAll(FROAttachment.self, sortBy: [SortDescriptor(\.createdAt)])

        return BackupPayload(
            version: 2,
            exportedAt: Self.formatDate(Date()),
            appVersion: Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "0.2.0",
            entities: EntityPayload(
                tools: tools.map { buildToolPayload($0) },
                toolGroups: groups.map { buildToolGroupPayload($0) },
                toolKits: kits.map { buildToolKitPayload($0) },
                jobs: jobs.map { buildJobPayload($0) },
                jobRevisions: revisions.map { rev in
                    buildJobRevisionPayload(rev, jobId: rev.jobRecord?.id ?? UUID())
                },
                consumables: consumables.map { buildConsumablePayload($0) },
                chemicals: chemicals.map { buildChemicalPayload($0) },
                parts: parts.map { buildPartPayload($0) },
                voiceMemos: voiceMemos.map { memo in
                    buildVoiceMemoPayload(memo, jobId: memo.jobRecord?.id)
                },
                attachments: attachments.map { buildAttachmentPayload($0) }
            )
        )
    }

    private func buildToolPayload(_ tool: FROTool) -> ToolPayload {
        ToolPayload(
            id: tool.id.uuidString,
            name: tool.name,
            aliases: tool.aliases,
            ownershipType: tool.ownershipType,
            borrowedFrom: tool.borrowedFrom,
            notes: tool.notes,
            createdAt: Self.formatDate(tool.createdAt),
            isInGarage: tool.isInGarage,
            photoFileNames: tool.photoFileNames,
            groupId: tool.group?.id.uuidString,
            toolKitIds: tool.toolKits?.map { $0.id.uuidString }
        )
    }

    private func buildToolGroupPayload(_ group: FROToolGroup) -> ToolGroupPayload {
        ToolGroupPayload(
            id: group.id.uuidString,
            name: group.name,
            sortOrder: group.sortOrder,
            ownershipType: group.ownershipType,
            toolType: group.toolType,
            measurementType: group.measurementType,
            photoFileNames: group.photoFileNames,
            parentGroupId: group.parentGroup?.id.uuidString
        )
    }

    private func buildToolKitPayload(_ kit: FROToolKit) -> ToolKitPayload {
        ToolKitPayload(
            id: kit.id.uuidString,
            name: kit.name,
            descriptionText: kit.descriptionText,
            ownershipType: kit.ownershipType,
            toolType: kit.toolType,
            createdAt: Self.formatDate(kit.createdAt),
            photoFileNames: kit.photoFileNames,
            toolIds: kit.tools?.map { $0.id.uuidString }
        )
    }

    private func buildJobPayload(_ job: FROJob) -> JobPayload {
        JobPayload(
            id: job.id.uuidString,
            aircraftType: job.aircraftType,
            aircraftSerialNumber: job.aircraftSerialNumber,
            nNumber: job.nNumber,
            system: job.system,
            component: job.component,
            jobDate: Self.formatDate(job.jobDate),
            taskDescription: job.taskDescription,
            tmReferences: job.tmReferences,
            notes: job.notes,
            recommendations: job.recommendations,
            createdAt: Self.formatDate(job.createdAt),
            updatedAt: Self.formatDate(job.updatedAt),
            currentVersion: job.currentVersion,
            toolIds: job.tools?.map { $0.id.uuidString },
            consumableIds: job.consumables?.map { $0.id.uuidString },
            chemicalIds: job.chemicals?.map { $0.id.uuidString },
            partIds: job.parts?.map { $0.id.uuidString }
        )
    }

    private func buildJobRevisionPayload(_ rev: FROJobRevision, jobId: UUID) -> JobRevisionPayload {
        JobRevisionPayload(
            id: rev.id.uuidString,
            versionNumber: rev.versionNumber,
            snapshotData: rev.snapshotData?.base64EncodedString(),
            editedAt: Self.formatDate(rev.editedAt),
            editNotes: rev.editNotes,
            jobId: jobId.uuidString
        )
    }

    private func buildConsumablePayload(_ c: FROConsumable) -> ConsumablePayload {
        ConsumablePayload(
            id: c.id.uuidString,
            name: c.name,
            category: c.category,
            size: c.size,
            spec: c.spec,
            notes: c.notes,
            createdAt: Self.formatDate(c.createdAt),
            isInGarage: c.isInGarage
        )
    }

    private func buildChemicalPayload(_ ch: FROChemical) -> ChemicalPayload {
        ChemicalPayload(
            id: ch.id.uuidString,
            name: ch.name,
            category: ch.category,
            size: ch.size,
            spec: ch.spec,
            notes: ch.notes,
            createdAt: Self.formatDate(ch.createdAt),
            isInGarage: ch.isInGarage
        )
    }

    private func buildPartPayload(_ p: FROPart) -> PartPayload {
        PartPayload(
            id: p.id.uuidString,
            partNumber: p.partNumber,
            alternatePartNumber: p.alternatePartNumber,
            nomenclature: p.nomenclature,
            nsn: p.nsn,
            quantity: p.quantity,
            unitOfMeasure: p.unitOfMeasure,
            notes: p.notes
        )
    }

    private func buildVoiceMemoPayload(_ m: FROVoiceMemo, jobId: UUID?) -> VoiceMemoPayload {
        VoiceMemoPayload(
            id: m.id.uuidString,
            audioFilePath: m.audioFilePath,
            transcriptionText: m.transcriptionText,
            transcriptionStatus: m.transcriptionStatus,
            identifiedTools: m.identifiedTools,
            identifiedConsumables: m.identifiedConsumables,
            identifiedChemicals: m.identifiedChemicals,
            createdAt: Self.formatDate(m.createdAt),
            jobId: jobId?.uuidString
        )
    }

    private func buildAttachmentPayload(_ a: FROAttachment) -> AttachmentPayload {
        AttachmentPayload(
            id: a.id.uuidString,
            fileName: a.fileName,
            fileType: a.fileType,
            createdAt: Self.formatDate(a.createdAt),
            notes: a.notes,
            entityId: nil,
            entityType: nil,
            relativePath: nil
        )
    }

    // MARK: - Staging Record Creation

    private func createStagingRecords(
        from payload: BackupPayload,
        sessionId: UUID,
        repository: FRORepository
    ) throws {
        let encoder = JSONEncoder()

        // Fetch existing entities for conflict detection
        let existingTools = try repository.fetchAll(FROTool.self, sortBy: [])
        let existingGroups = try repository.fetchAll(FROToolGroup.self, sortBy: [])
        let existingKits = try repository.fetchAll(FROToolKit.self, sortBy: [])
        let existingJobs = try repository.fetchAll(FROJob.self, sortBy: [])
        let existingConsumables = try repository.fetchAll(FROConsumable.self, sortBy: [])
        let existingChemicals = try repository.fetchAll(FROChemical.self, sortBy: [])
        let existingParts = try repository.fetchAll(FROPart.self, sortBy: [])

        // Build lookup maps
        let toolIdMap = Dictionary(uniqueKeysWithValues: existingTools.map { ($0.id, $0) })
        let toolNameMap = Dictionary(existingTools.map { ($0.name.lowercased(), $0) }, uniquingKeysWith: { first, _ in first })
        let groupIdMap = Dictionary(uniqueKeysWithValues: existingGroups.map { ($0.id, $0) })
        let groupNameMap = Dictionary(existingGroups.map { ($0.name.lowercased(), $0) }, uniquingKeysWith: { first, _ in first })
        let kitIdMap = Dictionary(uniqueKeysWithValues: existingKits.map { ($0.id, $0) })
        let kitNameMap = Dictionary(existingKits.map { ($0.name.lowercased(), $0) }, uniquingKeysWith: { first, _ in first })
        let jobIdMap = Dictionary(uniqueKeysWithValues: existingJobs.map { ($0.id, $0) })
        let consumableIdMap = Dictionary(uniqueKeysWithValues: existingConsumables.map { ($0.id, $0) })
        let consumableNameMap = Dictionary(existingConsumables.map { ($0.name.lowercased(), $0) }, uniquingKeysWith: { first, _ in first })
        let chemicalIdMap = Dictionary(uniqueKeysWithValues: existingChemicals.map { ($0.id, $0) })
        let chemicalNameMap = Dictionary(existingChemicals.map { ($0.name.lowercased(), $0) }, uniquingKeysWith: { first, _ in first })
        let partIdMap = Dictionary(uniqueKeysWithValues: existingParts.map { ($0.id, $0) })

        // Stage tool groups
        for groupPayload in payload.entities.toolGroups {
            guard let entityId = UUID(uuidString: groupPayload.id) else { continue }
            let jsonData = try encoder.encode(groupPayload)
            let (conflictType, matchedId) = detectConflict(
                entityId: entityId, name: groupPayload.name,
                idMap: groupIdMap, nameMap: groupNameMap
            )
            let staging = FROImportStaging(
                importSessionId: sessionId,
                entityType: "toolGroup",
                entityId: entityId,
                jsonData: jsonData,
                status: conflictType == nil ? "auto" : "pending",
                conflictType: conflictType,
                matchedEntityId: matchedId
            )
            repository.insert(staging)
        }

        // Stage tool kits
        for kitPayload in payload.entities.toolKits {
            guard let entityId = UUID(uuidString: kitPayload.id) else { continue }
            let jsonData = try encoder.encode(kitPayload)
            let (conflictType, matchedId) = detectConflict(
                entityId: entityId, name: kitPayload.name,
                idMap: kitIdMap, nameMap: kitNameMap
            )
            let staging = FROImportStaging(
                importSessionId: sessionId,
                entityType: "toolKit",
                entityId: entityId,
                jsonData: jsonData,
                status: conflictType == nil ? "auto" : "pending",
                conflictType: conflictType,
                matchedEntityId: matchedId
            )
            repository.insert(staging)
        }

        // Stage tools
        for toolPayload in payload.entities.tools {
            guard let entityId = UUID(uuidString: toolPayload.id) else { continue }
            let jsonData = try encoder.encode(toolPayload)
            let (conflictType, matchedId) = detectConflict(
                entityId: entityId, name: toolPayload.name,
                idMap: toolIdMap, nameMap: toolNameMap
            )
            let staging = FROImportStaging(
                importSessionId: sessionId,
                entityType: "tool",
                entityId: entityId,
                jsonData: jsonData,
                status: conflictType == nil ? "auto" : "pending",
                conflictType: conflictType,
                matchedEntityId: matchedId
            )
            repository.insert(staging)
        }

        // Stage consumables
        for cPayload in payload.entities.consumables {
            guard let entityId = UUID(uuidString: cPayload.id) else { continue }
            let jsonData = try encoder.encode(cPayload)
            let (conflictType, matchedId) = detectConflict(
                entityId: entityId, name: cPayload.name,
                idMap: consumableIdMap, nameMap: consumableNameMap
            )
            let staging = FROImportStaging(
                importSessionId: sessionId,
                entityType: "consumable",
                entityId: entityId,
                jsonData: jsonData,
                status: conflictType == nil ? "auto" : "pending",
                conflictType: conflictType,
                matchedEntityId: matchedId
            )
            repository.insert(staging)
        }

        // Stage chemicals
        for chPayload in payload.entities.chemicals {
            guard let entityId = UUID(uuidString: chPayload.id) else { continue }
            let jsonData = try encoder.encode(chPayload)
            let (conflictType, matchedId) = detectConflict(
                entityId: entityId, name: chPayload.name,
                idMap: chemicalIdMap, nameMap: chemicalNameMap
            )
            let staging = FROImportStaging(
                importSessionId: sessionId,
                entityType: "chemical",
                entityId: entityId,
                jsonData: jsonData,
                status: conflictType == nil ? "auto" : "pending",
                conflictType: conflictType,
                matchedEntityId: matchedId
            )
            repository.insert(staging)
        }

        // Stage parts (conflict by UUID only, no name matching)
        for pPayload in payload.entities.parts {
            guard let entityId = UUID(uuidString: pPayload.id) else { continue }
            let jsonData = try encoder.encode(pPayload)
            var conflictType: String?
            var matchedId: UUID?
            if partIdMap[entityId] != nil {
                conflictType = "uuid_match"
                matchedId = entityId
            }
            let staging = FROImportStaging(
                importSessionId: sessionId,
                entityType: "part",
                entityId: entityId,
                jsonData: jsonData,
                status: conflictType == nil ? "auto" : "pending",
                conflictType: conflictType,
                matchedEntityId: matchedId
            )
            repository.insert(staging)
        }

        // Stage jobs
        for jobPayload in payload.entities.jobs {
            guard let entityId = UUID(uuidString: jobPayload.id) else { continue }
            let jsonData = try encoder.encode(jobPayload)
            var conflictType: String?
            var matchedId: UUID?
            if jobIdMap[entityId] != nil {
                conflictType = "uuid_match"
                matchedId = entityId
            }
            let staging = FROImportStaging(
                importSessionId: sessionId,
                entityType: "job",
                entityId: entityId,
                jsonData: jsonData,
                status: conflictType == nil ? "auto" : "pending",
                conflictType: conflictType,
                matchedEntityId: matchedId
            )
            repository.insert(staging)
        }

        // Stage job revisions (no conflict detection — always import)
        for revPayload in payload.entities.jobRevisions {
            guard let entityId = UUID(uuidString: revPayload.id) else { continue }
            let jsonData = try encoder.encode(revPayload)
            let staging = FROImportStaging(
                importSessionId: sessionId,
                entityType: "jobRevision",
                entityId: entityId,
                jsonData: jsonData,
                status: "auto"
            )
            repository.insert(staging)
        }

        // Stage voice memos (no conflict detection — always import)
        for memoPayload in payload.entities.voiceMemos {
            guard let entityId = UUID(uuidString: memoPayload.id) else { continue }
            let jsonData = try encoder.encode(memoPayload)
            let staging = FROImportStaging(
                importSessionId: sessionId,
                entityType: "voiceMemo",
                entityId: entityId,
                jsonData: jsonData,
                status: "auto"
            )
            repository.insert(staging)
        }

        try repository.save()
        print("ImportExportService: Created staging records for session \(sessionId.uuidString)")
    }

    // MARK: - Conflict Detection

    private func detectConflict<T: FROIdentifiable>(
        entityId: UUID,
        name: String,
        idMap: [UUID: T],
        nameMap: [String: T]
    ) -> (conflictType: String?, matchedEntityId: UUID?) {
        if let existing = idMap[entityId] {
            return ("uuid_match", existing.id)
        }
        if let existing = nameMap[name.lowercased()] {
            return ("name_match", existing.id)
        }
        return (nil, nil)
    }

    // MARK: - Commit Helpers

    private func commitToolGroups(
        _ records: [FROImportStaging],
        decoder: JSONDecoder,
        repository: FRORepository
    ) throws {
        // Sort so parents come before children
        let payloads = records.compactMap { record -> (FROImportStaging, ToolGroupPayload)? in
            guard shouldCommit(record) else { return nil }
            guard let payload = try? decoder.decode(ToolGroupPayload.self, from: record.jsonData) else { return nil }
            return (record, payload)
        }

        // Build a depth map: groups without parentGroupId come first
        let sortedPayloads = payloads.sorted { a, b in
            let aDepth = a.1.parentGroupId == nil ? 0 : 1
            let bDepth = b.1.parentGroupId == nil ? 0 : 1
            return aDepth < bDepth
        }

        for (record, payload) in sortedPayloads {
            guard let entityId = UUID(uuidString: payload.id) else { continue }

            if record.resolution == "replace", let matchedId = record.matchedEntityId,
               let existing = try repository.fetchById(FROToolGroup.self, id: matchedId) {
                existing.name = payload.name
                existing.sortOrder = payload.sortOrder
                existing.ownershipType = payload.ownershipType
                existing.toolType = payload.toolType
                existing.measurementType = payload.measurementType
                existing.photoFileNames = payload.photoFileNames
                if let parentIdStr = payload.parentGroupId, let parentId = UUID(uuidString: parentIdStr) {
                    existing.parentGroup = try repository.fetchById(FROToolGroup.self, id: parentId)
                }
            } else if record.resolution == "keep_both" {
                let newGroup = FROToolGroup(
                    id: UUID(), // New UUID for "keep both"
                    name: payload.name,
                    sortOrder: payload.sortOrder,
                    ownershipType: payload.ownershipType,
                    toolType: payload.toolType,
                    measurementType: payload.measurementType,
                    photoFileNames: payload.photoFileNames
                )
                if let parentIdStr = payload.parentGroupId, let parentId = UUID(uuidString: parentIdStr) {
                    newGroup.parentGroup = try repository.fetchById(FROToolGroup.self, id: parentId)
                }
                repository.insert(newGroup)
            } else if record.resolution != "skip" {
                // New record (auto or no conflict)
                let newGroup = FROToolGroup(
                    id: entityId,
                    name: payload.name,
                    sortOrder: payload.sortOrder,
                    ownershipType: payload.ownershipType,
                    toolType: payload.toolType,
                    measurementType: payload.measurementType,
                    photoFileNames: payload.photoFileNames
                )
                if let parentIdStr = payload.parentGroupId, let parentId = UUID(uuidString: parentIdStr) {
                    newGroup.parentGroup = try repository.fetchById(FROToolGroup.self, id: parentId)
                }
                repository.insert(newGroup)
            }
        }
    }

    private func commitToolKits(
        _ records: [FROImportStaging],
        decoder: JSONDecoder,
        repository: FRORepository
    ) throws {
        for record in records {
            guard shouldCommit(record) else { continue }
            guard let payload = try? decoder.decode(ToolKitPayload.self, from: record.jsonData) else { continue }
            guard let entityId = UUID(uuidString: payload.id) else { continue }

            if record.resolution == "replace", let matchedId = record.matchedEntityId,
               let existing = try repository.fetchById(FROToolKit.self, id: matchedId) {
                existing.name = payload.name
                existing.descriptionText = payload.descriptionText
                existing.ownershipType = payload.ownershipType
                existing.toolType = payload.toolType
                existing.photoFileNames = payload.photoFileNames
            } else if record.resolution == "keep_both" {
                let newKit = FROToolKit(
                    id: UUID(),
                    name: payload.name,
                    descriptionText: payload.descriptionText,
                    ownershipType: payload.ownershipType,
                    toolType: payload.toolType,
                    photoFileNames: payload.photoFileNames
                )
                repository.insert(newKit)
            } else if record.resolution != "skip" {
                let newKit = FROToolKit(
                    id: entityId,
                    name: payload.name,
                    descriptionText: payload.descriptionText,
                    ownershipType: payload.ownershipType,
                    toolType: payload.toolType,
                    photoFileNames: payload.photoFileNames
                )
                repository.insert(newKit)
            }
        }
    }

    private func commitTools(
        _ records: [FROImportStaging],
        decoder: JSONDecoder,
        repository: FRORepository
    ) throws {
        for record in records {
            guard shouldCommit(record) else { continue }
            guard let payload = try? decoder.decode(ToolPayload.self, from: record.jsonData) else { continue }
            guard let entityId = UUID(uuidString: payload.id) else { continue }

            if record.resolution == "replace", let matchedId = record.matchedEntityId,
               let existing = try repository.fetchById(FROTool.self, id: matchedId) {
                existing.name = payload.name
                existing.aliases = payload.aliases
                existing.ownershipType = payload.ownershipType
                existing.borrowedFrom = payload.borrowedFrom
                existing.notes = payload.notes
                existing.isInGarage = payload.isInGarage
                existing.photoFileNames = payload.photoFileNames
                if let groupIdStr = payload.groupId, let groupId = UUID(uuidString: groupIdStr) {
                    existing.group = try repository.fetchById(FROToolGroup.self, id: groupId)
                }
                linkToolToKits(existing, kitIds: payload.toolKitIds, repository: repository)
            } else if record.resolution == "keep_both" {
                let newTool = FROTool(
                    id: UUID(),
                    name: payload.name,
                    aliases: payload.aliases,
                    ownershipType: payload.ownershipType,
                    borrowedFrom: payload.borrowedFrom,
                    notes: payload.notes,
                    createdAt: Self.parseDate(payload.createdAt),
                    isInGarage: payload.isInGarage,
                    photoFileNames: payload.photoFileNames
                )
                if let groupIdStr = payload.groupId, let groupId = UUID(uuidString: groupIdStr) {
                    newTool.group = try repository.fetchById(FROToolGroup.self, id: groupId)
                }
                repository.insert(newTool)
                linkToolToKits(newTool, kitIds: payload.toolKitIds, repository: repository)
            } else if record.resolution != "skip" {
                let newTool = FROTool(
                    id: entityId,
                    name: payload.name,
                    aliases: payload.aliases,
                    ownershipType: payload.ownershipType,
                    borrowedFrom: payload.borrowedFrom,
                    notes: payload.notes,
                    createdAt: Self.parseDate(payload.createdAt),
                    isInGarage: payload.isInGarage,
                    photoFileNames: payload.photoFileNames
                )
                if let groupIdStr = payload.groupId, let groupId = UUID(uuidString: groupIdStr) {
                    newTool.group = try repository.fetchById(FROToolGroup.self, id: groupId)
                }
                repository.insert(newTool)
                linkToolToKits(newTool, kitIds: payload.toolKitIds, repository: repository)
            }
        }
    }

    private func linkToolToKits(_ tool: FROTool, kitIds: [String]?, repository: FRORepository) {
        guard let kitIds = kitIds else { return }
        for kitIdStr in kitIds {
            guard let kitId = UUID(uuidString: kitIdStr),
                  let kit = try? repository.fetchById(FROToolKit.self, id: kitId) else { continue }
            if tool.toolKits == nil {
                tool.toolKits = [kit]
            } else {
                tool.toolKits?.append(kit)
            }
        }
    }

    private func commitConsumables(
        _ records: [FROImportStaging],
        decoder: JSONDecoder,
        repository: FRORepository
    ) throws {
        for record in records {
            guard shouldCommit(record) else { continue }
            guard let payload = try? decoder.decode(ConsumablePayload.self, from: record.jsonData) else { continue }
            guard let entityId = UUID(uuidString: payload.id) else { continue }

            if record.resolution == "replace", let matchedId = record.matchedEntityId,
               let existing = try repository.fetchById(FROConsumable.self, id: matchedId) {
                existing.name = payload.name
                existing.category = payload.category
                existing.size = payload.size
                existing.spec = payload.spec
                existing.notes = payload.notes
                existing.isInGarage = payload.isInGarage
            } else if record.resolution == "keep_both" {
                let newItem = FROConsumable(
                    id: UUID(),
                    name: payload.name,
                    category: payload.category,
                    size: payload.size,
                    spec: payload.spec,
                    notes: payload.notes,
                    createdAt: Self.parseDate(payload.createdAt),
                    isInGarage: payload.isInGarage
                )
                repository.insert(newItem)
            } else if record.resolution != "skip" {
                let newItem = FROConsumable(
                    id: entityId,
                    name: payload.name,
                    category: payload.category,
                    size: payload.size,
                    spec: payload.spec,
                    notes: payload.notes,
                    createdAt: Self.parseDate(payload.createdAt),
                    isInGarage: payload.isInGarage
                )
                repository.insert(newItem)
            }
        }
    }

    private func commitChemicals(
        _ records: [FROImportStaging],
        decoder: JSONDecoder,
        repository: FRORepository
    ) throws {
        for record in records {
            guard shouldCommit(record) else { continue }
            guard let payload = try? decoder.decode(ChemicalPayload.self, from: record.jsonData) else { continue }
            guard let entityId = UUID(uuidString: payload.id) else { continue }

            if record.resolution == "replace", let matchedId = record.matchedEntityId,
               let existing = try repository.fetchById(FROChemical.self, id: matchedId) {
                existing.name = payload.name
                existing.category = payload.category
                existing.size = payload.size
                existing.spec = payload.spec
                existing.notes = payload.notes
                existing.isInGarage = payload.isInGarage
            } else if record.resolution == "keep_both" {
                let newItem = FROChemical(
                    id: UUID(),
                    name: payload.name,
                    category: payload.category,
                    size: payload.size,
                    spec: payload.spec,
                    notes: payload.notes,
                    createdAt: Self.parseDate(payload.createdAt),
                    isInGarage: payload.isInGarage
                )
                repository.insert(newItem)
            } else if record.resolution != "skip" {
                let newItem = FROChemical(
                    id: entityId,
                    name: payload.name,
                    category: payload.category,
                    size: payload.size,
                    spec: payload.spec,
                    notes: payload.notes,
                    createdAt: Self.parseDate(payload.createdAt),
                    isInGarage: payload.isInGarage
                )
                repository.insert(newItem)
            }
        }
    }

    private func commitParts(
        _ records: [FROImportStaging],
        decoder: JSONDecoder,
        repository: FRORepository
    ) throws {
        for record in records {
            guard shouldCommit(record) else { continue }
            guard let payload = try? decoder.decode(PartPayload.self, from: record.jsonData) else { continue }
            guard let entityId = UUID(uuidString: payload.id) else { continue }

            if record.resolution == "replace", let matchedId = record.matchedEntityId,
               let existing = try repository.fetchById(FROPart.self, id: matchedId) {
                existing.partNumber = payload.partNumber
                existing.alternatePartNumber = payload.alternatePartNumber
                existing.nomenclature = payload.nomenclature
                existing.nsn = payload.nsn
                existing.quantity = payload.quantity
                existing.unitOfMeasure = payload.unitOfMeasure
                existing.notes = payload.notes
            } else if record.resolution == "keep_both" {
                let newItem = FROPart(
                    id: UUID(),
                    partNumber: payload.partNumber,
                    alternatePartNumber: payload.alternatePartNumber,
                    nomenclature: payload.nomenclature,
                    nsn: payload.nsn,
                    quantity: payload.quantity,
                    unitOfMeasure: payload.unitOfMeasure,
                    notes: payload.notes
                )
                repository.insert(newItem)
            } else if record.resolution != "skip" {
                let newItem = FROPart(
                    id: entityId,
                    partNumber: payload.partNumber,
                    alternatePartNumber: payload.alternatePartNumber,
                    nomenclature: payload.nomenclature,
                    nsn: payload.nsn,
                    quantity: payload.quantity,
                    unitOfMeasure: payload.unitOfMeasure,
                    notes: payload.notes
                )
                repository.insert(newItem)
            }
        }
    }

    private func commitJobs(
        _ records: [FROImportStaging],
        decoder: JSONDecoder,
        repository: FRORepository
    ) throws {
        for record in records {
            guard shouldCommit(record) else { continue }
            guard let payload = try? decoder.decode(JobPayload.self, from: record.jsonData) else { continue }
            guard let entityId = UUID(uuidString: payload.id) else { continue }

            if record.resolution == "replace", let matchedId = record.matchedEntityId,
               let existing = try repository.fetchById(FROJob.self, id: matchedId) {
                existing.aircraftType = payload.aircraftType
                existing.aircraftSerialNumber = payload.aircraftSerialNumber
                existing.nNumber = payload.nNumber
                existing.system = payload.system
                existing.component = payload.component
                existing.jobDate = Self.parseDate(payload.jobDate)
                existing.taskDescription = payload.taskDescription
                existing.tmReferences = payload.tmReferences
                existing.notes = payload.notes
                existing.recommendations = payload.recommendations
                existing.updatedAt = Date()
                existing.currentVersion = payload.currentVersion
                linkJobToEntities(existing, payload: payload, repository: repository)
            } else if record.resolution == "keep_both" {
                let newJob = createJob(id: UUID(), payload: payload)
                repository.insert(newJob)
                linkJobToEntities(newJob, payload: payload, repository: repository)
            } else if record.resolution != "skip" {
                let newJob = createJob(id: entityId, payload: payload)
                repository.insert(newJob)
                linkJobToEntities(newJob, payload: payload, repository: repository)
            }
        }
    }

    private func createJob(id: UUID, payload: JobPayload) -> FROJob {
        FROJob(
            id: id,
            aircraftType: payload.aircraftType,
            aircraftSerialNumber: payload.aircraftSerialNumber,
            nNumber: payload.nNumber,
            system: payload.system,
            component: payload.component,
            jobDate: Self.parseDate(payload.jobDate),
            taskDescription: payload.taskDescription,
            tmReferences: payload.tmReferences,
            notes: payload.notes,
            recommendations: payload.recommendations,
            createdAt: Self.parseDate(payload.createdAt),
            updatedAt: Self.parseDate(payload.updatedAt),
            currentVersion: payload.currentVersion
        )
    }

    private func linkJobToEntities(_ job: FROJob, payload: JobPayload, repository: FRORepository) {
        if let toolIds = payload.toolIds {
            for idStr in toolIds {
                guard let id = UUID(uuidString: idStr),
                      let tool = try? repository.fetchById(FROTool.self, id: id) else { continue }
                if job.tools == nil { job.tools = [] }
                job.tools?.append(tool)
            }
        }
        if let consumableIds = payload.consumableIds {
            for idStr in consumableIds {
                guard let id = UUID(uuidString: idStr),
                      let item = try? repository.fetchById(FROConsumable.self, id: id) else { continue }
                if job.consumables == nil { job.consumables = [] }
                job.consumables?.append(item)
            }
        }
        if let chemicalIds = payload.chemicalIds {
            for idStr in chemicalIds {
                guard let id = UUID(uuidString: idStr),
                      let item = try? repository.fetchById(FROChemical.self, id: id) else { continue }
                if job.chemicals == nil { job.chemicals = [] }
                job.chemicals?.append(item)
            }
        }
        if let partIds = payload.partIds {
            for idStr in partIds {
                guard let id = UUID(uuidString: idStr),
                      let item = try? repository.fetchById(FROPart.self, id: id) else { continue }
                if job.parts == nil { job.parts = [] }
                job.parts?.append(item)
            }
        }
    }

    private func commitJobRevisions(
        _ records: [FROImportStaging],
        decoder: JSONDecoder,
        repository: FRORepository
    ) throws {
        for record in records {
            guard shouldCommit(record) else { continue }
            guard let payload = try? decoder.decode(JobRevisionPayload.self, from: record.jsonData) else { continue }
            guard let entityId = UUID(uuidString: payload.id) else { continue }

            let revision = FROJobRevision(
                id: entityId,
                versionNumber: payload.versionNumber,
                snapshotData: payload.snapshotData.flatMap { Data(base64Encoded: $0) },
                editedAt: Self.parseDate(payload.editedAt),
                editNotes: payload.editNotes
            )
            if let jobIdStr = payload.jobId, let jobId = UUID(uuidString: jobIdStr) {
                revision.jobRecord = try repository.fetchById(FROJob.self, id: jobId)
            }
            repository.insert(revision)
        }
    }

    private func commitVoiceMemos(
        _ records: [FROImportStaging],
        decoder: JSONDecoder,
        repository: FRORepository
    ) throws {
        for record in records {
            guard shouldCommit(record) else { continue }
            guard let payload = try? decoder.decode(VoiceMemoPayload.self, from: record.jsonData) else { continue }
            guard let entityId = UUID(uuidString: payload.id) else { continue }

            let memo = FROVoiceMemo(
                id: entityId,
                audioFilePath: payload.audioFilePath,
                transcriptionText: payload.transcriptionText,
                transcriptionStatus: payload.transcriptionStatus,
                identifiedTools: payload.identifiedTools,
                identifiedConsumables: payload.identifiedConsumables,
                identifiedChemicals: payload.identifiedChemicals,
                createdAt: Self.parseDate(payload.createdAt)
            )
            if let jobIdStr = payload.jobId, let jobId = UUID(uuidString: jobIdStr) {
                memo.jobRecord = try repository.fetchById(FROJob.self, id: jobId)
            }
            repository.insert(memo)
        }
    }

    private func shouldCommit(_ record: FROImportStaging) -> Bool {
        record.resolution != "skip" && record.status != "skipped"
    }

    // MARK: - Photo Restoration

    private func restorePhotos(from attachmentsDir: URL) {
        let fm = FileManager.default
        guard let entityDirs = try? fm.contentsOfDirectory(
            at: attachmentsDir,
            includingPropertiesForKeys: [.isDirectoryKey]
        ) else { return }

        let photoService = ToolPhotoService.shared

        for entityDir in entityDirs {
            var isDir: ObjCBool = false
            fm.fileExists(atPath: entityDir.path, isDirectory: &isDir)
            guard isDir.boolValue else { continue }

            let entityIdStr = entityDir.lastPathComponent
            guard let entityId = UUID(uuidString: entityIdStr) else { continue }

            let destDir = photoService.photoDirectory(for: entityId)
            if fm.fileExists(atPath: destDir.path) {
                // Photos already exist — don't overwrite
                continue
            }
            try? fm.copyItem(at: entityDir, to: destDir)
        }
    }

    // MARK: - v1 Backward Compatibility

    private func convertV1JobBundle(_ v1: JobExportService.JobExportBundle) -> BackupPayload {
        let toolPayloads = v1.tools.map { tool in
            ToolPayload(
                id: UUID().uuidString,
                name: tool.name,
                aliases: tool.aliases,
                ownershipType: tool.ownershipType ?? "imported",
                borrowedFrom: tool.borrowedFrom,
                notes: tool.notes,
                createdAt: Self.formatDate(Date()),
                isInGarage: true,
                photoFileNames: nil,
                groupId: nil,
                toolKitIds: nil
            )
        }

        let consumablePayloads = v1.consumables.map { c in
            ConsumablePayload(
                id: UUID().uuidString,
                name: c.name,
                category: c.category ?? "other",
                size: c.size,
                spec: c.spec,
                notes: c.notes,
                createdAt: Self.formatDate(Date()),
                isInGarage: true
            )
        }

        let chemicalPayloads = v1.chemicals.map { ch in
            ChemicalPayload(
                id: UUID().uuidString,
                name: ch.name,
                category: ch.category ?? "other",
                size: ch.size,
                spec: ch.spec,
                notes: ch.notes,
                createdAt: Self.formatDate(Date()),
                isInGarage: true
            )
        }

        let partPayloads = v1.parts.map { p in
            PartPayload(
                id: UUID().uuidString,
                partNumber: p.partNumber ?? "",
                alternatePartNumber: p.alternatePartNumber,
                nomenclature: p.nomenclature ?? "",
                nsn: p.nsn,
                quantity: p.quantity,
                unitOfMeasure: p.unitOfMeasure,
                notes: p.notes
            )
        }

        let jobId = UUID().uuidString
        let jobPayload = JobPayload(
            id: jobId,
            aircraftType: v1.job.aircraftType,
            aircraftSerialNumber: v1.job.aircraftSerialNumber,
            nNumber: v1.job.nNumber,
            system: v1.job.system,
            component: v1.job.component,
            jobDate: v1.job.jobDate ?? Self.formatDate(Date()),
            taskDescription: v1.job.taskDescription,
            tmReferences: v1.job.tmReferences,
            notes: v1.job.notes,
            recommendations: v1.job.recommendations,
            createdAt: Self.formatDate(Date()),
            updatedAt: Self.formatDate(Date()),
            currentVersion: 1,
            toolIds: toolPayloads.map { $0.id },
            consumableIds: consumablePayloads.map { $0.id },
            chemicalIds: chemicalPayloads.map { $0.id },
            partIds: partPayloads.map { $0.id }
        )

        return BackupPayload(
            version: 2,
            exportedAt: v1.exportDate,
            appVersion: v1.appVersion,
            entities: EntityPayload(
                tools: toolPayloads,
                toolGroups: [],
                toolKits: [],
                jobs: [jobPayload],
                jobRevisions: [],
                consumables: consumablePayloads,
                chemicals: chemicalPayloads,
                parts: partPayloads,
                voiceMemos: [],
                attachments: []
            )
        )
    }

    // MARK: - File Naming

    private func generateToolBundleName(for tools: [FROTool]) -> String {
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyyy-MM-dd"
        let dateStr = dateFormatter.string(from: Date())

        if tools.count == 1 {
            let safeName = tools[0].name
                .replacingOccurrences(of: "/", with: "-")
                .replacingOccurrences(of: "\"", with: "")
                .replacingOccurrences(of: ":", with: "-")
                .trimmingCharacters(in: .whitespacesAndNewlines)
            return "FRO-Tool-\(safeName)-\(dateStr)"
        } else {
            return "FRO-Tools-\(tools.count)-\(dateStr)"
        }
    }

    private func generateJobBundleName(for job: FROJob) -> String {
        func sanitize(_ text: String) -> String {
            let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { return "" }
            var result = trimmed.replacingOccurrences(of: " ", with: "_")
            let invalidChars = CharacterSet(charactersIn: "/\\:*?\"<>|")
            result = result.components(separatedBy: invalidChars).joined()
            return String(result.prefix(30))
        }

        var components = ["FRO", "Job"]
        let aircraft = sanitize(job.aircraftType)
        if !aircraft.isEmpty { components.append(aircraft) }
        let system = sanitize(job.system)
        if !system.isEmpty { components.append(system) }

        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyyyMMdd"
        components.append(dateFormatter.string(from: job.jobDate))

        return components.joined(separator: "_")
    }
}

// MARK: - Errors

enum ImportExportError: LocalizedError {
    case missingJSON(String)
    case invalidFormat(String)

    var errorDescription: String? {
        switch self {
        case .missingJSON(let name):
            return "The file does not contain \(name)."
        case .invalidFormat(let details):
            return "Invalid format: \(details)"
        }
    }
}

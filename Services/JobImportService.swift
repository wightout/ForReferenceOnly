import Foundation
import SwiftData

/// Service for importing job records from `.frojob` bundles.
/// Two-phase approach: parse first (returns preview), then import after user review.
/// When importing, tools are matched against existing Garage tools (case-insensitive name match).
/// Matched tools link to existing entities; unmatched tools are created with "imported" ownership.
class JobImportService {

    // MARK: - Singleton

    nonisolated(unsafe) static let shared = JobImportService()
    private init() {}

    // MARK: - Parse Result

    /// Result of parsing a `.frojob` bundle, ready for user review.
    struct JobImportParseResult {
        let job: JobExportService.ExportedJob
        let tools: [ToolImportPreview]
        let consumables: [ConsumableImportPreview]
        let chemicals: [ChemicalImportPreview]
        let parts: [JobExportService.ExportedJobPart]
        let exportDate: String
        let appVersion: String
        let bundleURL: URL
    }

    /// Preview of a tool that will be imported, with match status.
    struct ToolImportPreview {
        let exportedTool: JobExportService.ExportedJobTool
        let matchedTool: FROTool?          // existing Garage tool, if found
        var isSelected: Bool = true

        var isNewTool: Bool { matchedTool == nil }
        var displayName: String { exportedTool.name }
    }

    /// Preview of a consumable that will be imported.
    struct ConsumableImportPreview {
        let exportedConsumable: JobExportService.ExportedJobConsumable
        let matchedConsumable: FROConsumable?
        var isSelected: Bool = true

        var isNew: Bool { matchedConsumable == nil }
        var displayName: String { exportedConsumable.name }
    }

    /// Preview of a chemical that will be imported.
    struct ChemicalImportPreview {
        let exportedChemical: JobExportService.ExportedJobChemical
        let matchedChemical: FROChemical?
        var isSelected: Bool = true

        var isNew: Bool { matchedChemical == nil }
        var displayName: String { exportedChemical.name }
    }

    // MARK: - Errors

    enum JobImportError: LocalizedError {
        case invalidBundle(details: String)
        case decodingFailed(details: String)
        case versionMismatch(version: Int)
        case importFailed(details: String)

        var errorDescription: String? {
            switch self {
            case .invalidBundle(let details):
                return "Invalid .frojob file: \(details)"
            case .decodingFailed(let details):
                return "Could not read job data: \(details)"
            case .versionMismatch(let version):
                return "This file requires a newer version of FRO (format version \(version))."
            case .importFailed(let details):
                return "Import failed: \(details)"
            }
        }
    }

    // MARK: - Phase 1: Parse

    /// Parses a `.frojob` bundle and returns a preview for user review.
    /// - Parameters:
    ///   - url: URL to the `.frojob` file (may be security-scoped)
    ///   - context: Model context for matching existing entities
    /// - Returns: Parsed result ready for review
    func parseFrojobBundle(at url: URL, context: ModelContext) throws -> JobImportParseResult {
        let didStartAccessing = url.startAccessingSecurityScopedResource()
        defer {
            if didStartAccessing {
                url.stopAccessingSecurityScopedResource()
            }
        }

        // Extract the ZIP contents
        let extractedDir = try unzipBundle(at: url)
        defer {
            try? FileManager.default.removeItem(at: extractedDir)
        }

        // Read job.json
        let jsonURL = extractedDir.appendingPathComponent("job.json")
        guard FileManager.default.fileExists(atPath: jsonURL.path) else {
            throw JobImportError.invalidBundle(details: "Missing job.json in bundle.")
        }

        let jsonData = try Data(contentsOf: jsonURL)
        let decoder = JSONDecoder()

        let bundle: JobExportService.JobExportBundle
        do {
            bundle = try decoder.decode(JobExportService.JobExportBundle.self, from: jsonData)
        } catch {
            throw JobImportError.decodingFailed(details: error.localizedDescription)
        }

        // Version check
        guard bundle.version <= 1 else {
            throw JobImportError.versionMismatch(version: bundle.version)
        }

        // Fetch existing entities for matching
        let existingTools = try fetchExistingToolNames(context: context)
        let existingConsumables = try fetchExistingConsumableNames(context: context)
        let existingChemicals = try fetchExistingChemicalNames(context: context)

        // Build tool previews with match status
        let toolPreviews = bundle.tools.map { exportedTool -> ToolImportPreview in
            let match = existingTools[exportedTool.name.lowercased()]
            return ToolImportPreview(
                exportedTool: exportedTool,
                matchedTool: match
            )
        }

        // Build consumable previews
        let consumablePreviews = bundle.consumables.map { exportedConsumable -> ConsumableImportPreview in
            let match = existingConsumables[exportedConsumable.name.lowercased()]
            return ConsumableImportPreview(
                exportedConsumable: exportedConsumable,
                matchedConsumable: match
            )
        }

        // Build chemical previews
        let chemicalPreviews = bundle.chemicals.map { exportedChemical -> ChemicalImportPreview in
            let match = existingChemicals[exportedChemical.name.lowercased()]
            return ChemicalImportPreview(
                exportedChemical: exportedChemical,
                matchedChemical: match
            )
        }

        print("JobImportService: Parsed .frojob — \(toolPreviews.count) tools (\(toolPreviews.filter { !$0.isNewTool }.count) matched), \(bundle.parts.count) parts, \(consumablePreviews.count) consumables, \(chemicalPreviews.count) chemicals")

        return JobImportParseResult(
            job: bundle.job,
            tools: toolPreviews,
            consumables: consumablePreviews,
            chemicals: chemicalPreviews,
            parts: bundle.parts,
            exportDate: bundle.exportDate,
            appVersion: bundle.appVersion,
            bundleURL: url
        )
    }

    // MARK: - Phase 2: Import

    /// Imports a job from a parsed result into SwiftData.
    /// - Parameters:
    ///   - parseResult: The parsed bundle data
    ///   - selectedToolIndices: Indices of tools the user selected to import
    ///   - context: Model context to create entities in
    /// - Returns: The newly created JobRecord
    func importJob(
        from parseResult: JobImportParseResult,
        selectedToolIndices: Set<Int>,
        selectedConsumableIndices: Set<Int>,
        selectedChemicalIndices: Set<Int>,
        context: ModelContext
    ) throws -> FROJob {
        let exportedJob = parseResult.job

        // Create the JobRecord
        let jobRecord = FROJob(
            aircraftType: exportedJob.aircraftType,
            aircraftSerialNumber: exportedJob.aircraftSerialNumber,
            nNumber: exportedJob.nNumber,
            system: exportedJob.system,
            component: exportedJob.component,
            taskDescription: exportedJob.taskDescription,
            tmReferences: exportedJob.tmReferences,
            notes: exportedJob.notes,
            recommendations: exportedJob.recommendations
        )
        context.insert(jobRecord)

        // Parse job date
        if let dateString = exportedJob.jobDate {
            if let parsedDate = parseDate(dateString) {
                jobRecord.jobDate = parsedDate
            }
        }

        // Initialize relationship arrays
        if jobRecord.tools == nil { jobRecord.tools = [] }
        if jobRecord.consumables == nil { jobRecord.consumables = [] }
        if jobRecord.chemicals == nil { jobRecord.chemicals = [] }
        if jobRecord.parts == nil { jobRecord.parts = [] }

        // Link/create tools
        for index in selectedToolIndices {
            guard index < parseResult.tools.count else { continue }
            let preview = parseResult.tools[index]

            if let existingTool = preview.matchedTool {
                // Link to existing Garage tool
                jobRecord.tools?.append(existingTool)
            } else {
                // Create new tool with "imported" ownership
                let newTool = FROTool(
                    name: preview.exportedTool.name,
                    aliases: preview.exportedTool.aliases,
                    ownershipType: "imported",
                    borrowedFrom: preview.exportedTool.borrowedFrom,
                    notes: preview.exportedTool.notes
                )
                context.insert(newTool)
                jobRecord.tools?.append(newTool)
            }
        }

        // Link/create consumables
        for index in selectedConsumableIndices {
            guard index < parseResult.consumables.count else { continue }
            let preview = parseResult.consumables[index]

            if let existingConsumable = preview.matchedConsumable {
                jobRecord.consumables?.append(existingConsumable)
            } else {
                let newConsumable = FROConsumable(
                    name: preview.exportedConsumable.name,
                    category: preview.exportedConsumable.category ?? "other",
                    size: preview.exportedConsumable.size,
                    spec: preview.exportedConsumable.spec,
                    notes: preview.exportedConsumable.notes
                )
                context.insert(newConsumable)
                jobRecord.consumables?.append(newConsumable)
            }
        }

        // Link/create chemicals
        for index in selectedChemicalIndices {
            guard index < parseResult.chemicals.count else { continue }
            let preview = parseResult.chemicals[index]

            if let existingChemical = preview.matchedChemical {
                jobRecord.chemicals?.append(existingChemical)
            } else {
                let newChemical = FROChemical(
                    name: preview.exportedChemical.name,
                    category: preview.exportedChemical.category ?? "other",
                    size: preview.exportedChemical.size,
                    spec: preview.exportedChemical.spec,
                    notes: preview.exportedChemical.notes
                )
                context.insert(newChemical)
                jobRecord.chemicals?.append(newChemical)
            }
        }

        // Create all parts (parts are per-job, always created fresh)
        for exportedPart in parseResult.parts {
            let part = FROPart(
                partNumber: exportedPart.partNumber ?? "",
                alternatePartNumber: exportedPart.alternatePartNumber,
                nomenclature: exportedPart.nomenclature ?? "",
                nsn: exportedPart.nsn,
                quantity: exportedPart.quantity,
                unitOfMeasure: exportedPart.unitOfMeasure,
                notes: exportedPart.notes
            )
            context.insert(part)
            jobRecord.parts?.append(part)
        }

        // Save
        do {
            try context.save()
            print("JobImportService: Imported job '\(exportedJob.aircraftType)' with \(selectedToolIndices.count) tools, \(parseResult.parts.count) parts")
            return jobRecord
        } catch {
            throw JobImportError.importFailed(details: error.localizedDescription)
        }
    }

    // MARK: - Matching Helpers

    /// Fetches all existing tool names as a lowercase-keyed dictionary for fast matching.
    private func fetchExistingToolNames(context: ModelContext) throws -> [String: FROTool] {
        let descriptor = FetchDescriptor<FROTool>()
        let tools = try context.fetch(descriptor)

        var dict: [String: FROTool] = [:]
        for tool in tools {
            dict[tool.name.lowercased()] = tool
        }
        return dict
    }

    /// Fetches all existing consumable names as a lowercase-keyed dictionary.
    private func fetchExistingConsumableNames(context: ModelContext) throws -> [String: FROConsumable] {
        let descriptor = FetchDescriptor<FROConsumable>()
        let items = try context.fetch(descriptor)

        var dict: [String: FROConsumable] = [:]
        for item in items {
            dict[item.name.lowercased()] = item
        }
        return dict
    }

    /// Fetches all existing chemical names as a lowercase-keyed dictionary.
    private func fetchExistingChemicalNames(context: ModelContext) throws -> [String: FROChemical] {
        let descriptor = FetchDescriptor<FROChemical>()
        let items = try context.fetch(descriptor)

        var dict: [String: FROChemical] = [:]
        for item in items {
            dict[item.name.lowercased()] = item
        }
        return dict
    }

    // MARK: - ZIP Extraction

    /// Extracts a `.frojob` ZIP file to a temporary directory.
    /// Copies to a .zip extension first so the system recognizes the format.
    private func unzipBundle(at url: URL) throws -> URL {
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("frojob_import_\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)

        // Copy to .zip extension so the system recognizes it
        let tempZip = tempDir.deletingLastPathComponent()
            .appendingPathComponent(UUID().uuidString + ".zip")
        try FileManager.default.copyItem(at: url, to: tempZip)
        defer { try? FileManager.default.removeItem(at: tempZip) }

        // Read and extract manually
        let data = try Data(contentsOf: tempZip)

        // Verify ZIP signature
        guard data.count > 4,
              data[0] == 0x50, data[1] == 0x4B,
              data[2] == 0x03, data[3] == 0x04 else {
            throw JobImportError.invalidBundle(details: "Not a valid ZIP file")
        }

        let success = extractZipManually(data, to: tempDir)
        guard success else {
            throw JobImportError.invalidBundle(details: "Failed to extract ZIP contents")
        }

        return tempDir
    }

    /// Manual zip extraction that handles both standard ZIP and data descriptor (bit 3) formats.
    /// NSFileCoordinator .forUploading creates ZIPs with bit 3 set, meaning sizes are zero in the
    /// local file header and the actual sizes follow the data in a data descriptor record.
    private func extractZipManually(_ data: Data, to destDir: URL) -> Bool {
        var offset = 0
        let count = data.count

        while offset + 30 <= count {
            // Read local file header signature
            let sig = data[offset..<offset+4]
            guard sig.elementsEqual([0x50, 0x4B, 0x03, 0x04]) else {
                break // No more local file headers
            }

            // Parse header fields
            let bitFlag = UInt16(data[offset+6]) | (UInt16(data[offset+7]) << 8)
            let hasDataDescriptor = (bitFlag & 0x0008) != 0
            let compressionMethod = UInt16(data[offset+8]) | (UInt16(data[offset+9]) << 8)
            var compressedSize = Int(UInt32(data[offset+18]) | (UInt32(data[offset+19]) << 8) |
                                     (UInt32(data[offset+20]) << 16) | (UInt32(data[offset+21]) << 24))
            var uncompressedSize = Int(UInt32(data[offset+22]) | (UInt32(data[offset+23]) << 8) |
                                       (UInt32(data[offset+24]) << 16) | (UInt32(data[offset+25]) << 24))
            let fileNameLen = Int(UInt16(data[offset+26]) | (UInt16(data[offset+27]) << 8))
            let extraFieldLen = Int(UInt16(data[offset+28]) | (UInt16(data[offset+29]) << 8))

            guard offset + 30 + fileNameLen <= count else { break }

            let fileNameData = data[(offset+30)..<(offset+30+fileNameLen)]
            guard let fileName = String(data: fileNameData, encoding: .utf8) else {
                offset += 30 + fileNameLen + extraFieldLen + max(compressedSize, 1)
                continue
            }

            let dataStart = offset + 30 + fileNameLen + extraFieldLen

            // Handle data descriptor: sizes in header are 0, real sizes follow the data
            if hasDataDescriptor && compressedSize == 0 {
                // Scan forward for next PK signature or end of data
                var scanPos = dataStart
                while scanPos + 4 <= count {
                    if data[scanPos] == 0x50 && data[scanPos+1] == 0x4B {
                        let marker = data[scanPos+2]
                        let marker2 = data[scanPos+3]
                        // Next local file header or central directory
                        if (marker == 0x03 && marker2 == 0x04) || (marker == 0x01 && marker2 == 0x02) {
                            break
                        }
                    }
                    scanPos += 1
                }

                // Data descriptor is between the data and the next PK signature
                // Try 16-byte descriptor with signature (PK\x07\x08 + CRC + compSize + uncompSize)
                var descriptorSize = 0
                if scanPos - dataStart >= 16 {
                    let descStart = scanPos - 16
                    if data[descStart] == 0x50 && data[descStart+1] == 0x4B &&
                       data[descStart+2] == 0x07 && data[descStart+3] == 0x08 {
                        compressedSize = Int(UInt32(data[descStart+8]) | (UInt32(data[descStart+9]) << 8) |
                                             (UInt32(data[descStart+10]) << 16) | (UInt32(data[descStart+11]) << 24))
                        uncompressedSize = Int(UInt32(data[descStart+12]) | (UInt32(data[descStart+13]) << 8) |
                                               (UInt32(data[descStart+14]) << 16) | (UInt32(data[descStart+15]) << 24))
                        descriptorSize = 16
                    }
                }
                // Try 12-byte descriptor without signature (CRC + compSize + uncompSize)
                if descriptorSize == 0 && scanPos - dataStart >= 12 {
                    let descStart = scanPos - 12
                    compressedSize = Int(UInt32(data[descStart+4]) | (UInt32(data[descStart+5]) << 8) |
                                         (UInt32(data[descStart+6]) << 16) | (UInt32(data[descStart+7]) << 24))
                    uncompressedSize = Int(UInt32(data[descStart+8]) | (UInt32(data[descStart+9]) << 8) |
                                           (UInt32(data[descStart+10]) << 16) | (UInt32(data[descStart+11]) << 24))
                    descriptorSize = 12
                }
            }

            let dataEnd = dataStart + compressedSize
            guard dataEnd <= count else { break }

            let fileURL = destDir.appendingPathComponent(fileName)

            if fileName.hasSuffix("/") {
                // Directory entry
                try? FileManager.default.createDirectory(at: fileURL, withIntermediateDirectories: true)
            } else {
                // File entry
                let parentDir = fileURL.deletingLastPathComponent()
                try? FileManager.default.createDirectory(at: parentDir, withIntermediateDirectories: true)

                if compressionMethod == 0 {
                    // Stored (no compression)
                    let fileData = data[dataStart..<dataEnd]
                    try? fileData.write(to: fileURL)
                } else if compressionMethod == 8 {
                    // Deflated — use Foundation's decompression
                    let compressedData = data[dataStart..<dataEnd]
                    if let decompressed = decompressDeflate(Data(compressedData), expectedSize: uncompressedSize) {
                        try? decompressed.write(to: fileURL)
                    }
                }
            }

            // Advance past file data (and data descriptor if present)
            offset = dataEnd
            if hasDataDescriptor {
                // Skip past the data descriptor
                if offset + 4 <= count && data[offset] == 0x50 && data[offset+1] == 0x4B &&
                   data[offset+2] == 0x07 && data[offset+3] == 0x08 {
                    offset += 16 // 16-byte descriptor with signature
                } else {
                    offset += 12 // 12-byte descriptor without signature
                }
            }
        }

        // Verify job.json was extracted — check root first, then subdirectories
        // (NSFileCoordinator .forUploading wraps directory contents in a subdirectory)
        let jsonURL = destDir.appendingPathComponent("job.json")
        if FileManager.default.fileExists(atPath: jsonURL.path) {
            return true
        }

        // Search one level deep for job.json (NSFileCoordinator wrapping)
        if let subdirs = try? FileManager.default.contentsOfDirectory(at: destDir, includingPropertiesForKeys: nil) {
            for subdir in subdirs {
                var isDir: ObjCBool = false
                FileManager.default.fileExists(atPath: subdir.path, isDirectory: &isDir)
                guard isDir.boolValue else { continue }

                let nestedJSON = subdir.appendingPathComponent("job.json")
                if FileManager.default.fileExists(atPath: nestedJSON.path) {
                    // Move all contents from subdirectory up to destDir
                    if let contents = try? FileManager.default.contentsOfDirectory(at: subdir, includingPropertiesForKeys: nil) {
                        for item in contents {
                            let target = destDir.appendingPathComponent(item.lastPathComponent)
                            try? FileManager.default.moveItem(at: item, to: target)
                        }
                    }
                    try? FileManager.default.removeItem(at: subdir)
                    return true
                }
            }
        }
        return false
    }

    /// Decompresses deflate-compressed data using Foundation.
    private func decompressDeflate(_ data: Data, expectedSize: Int) -> Data? {
        // Try raw deflate first (add zlib header for NSData.decompressed)
        var zlibData = Data([0x78, 0x01])
        zlibData.append(data)
        if let result = try? (zlibData as NSData).decompressed(using: .zlib) as Data {
            return result
        }
        // Fallback: try the data as-is (may already have zlib wrapper)
        return try? (data as NSData).decompressed(using: .zlib) as Data
    }

    // MARK: - Date Parsing

    private func parseDate(_ string: String) -> Date? {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")

        // Try ISO format first: "2026-02-07"
        formatter.dateFormat = "yyyy-MM-dd"
        if let date = formatter.date(from: string) { return date }

        // Try ISO 8601 full: "2026-02-07T12:00:00Z"
        let isoFormatter = ISO8601DateFormatter()
        if let date = isoFormatter.date(from: string) { return date }

        return nil
    }
}

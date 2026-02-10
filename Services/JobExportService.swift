import Foundation
import SwiftData

/// Service for exporting individual job records as `.frojob` bundles.
/// A `.frojob` file is a renamed ZIP containing `job.json` with the job
/// and all related entities (tools, consumables, chemicals, parts).
/// This enables mechanic-to-mechanic job sharing.
class JobExportService {

    // MARK: - Singleton

    nonisolated(unsafe) static let shared = JobExportService()
    private init() {}

    // MARK: - Export Data Structures

    /// Root structure for the `.frojob` bundle JSON
    struct JobExportBundle: Codable {
        let version: Int               // Schema version (1)
        let exportDate: String          // ISO 8601 timestamp
        let appVersion: String
        let job: ExportedJob
        let tools: [ExportedJobTool]
        let consumables: [ExportedJobConsumable]
        let chemicals: [ExportedJobChemical]
        let parts: [ExportedJobPart]
    }

    struct ExportedJob: Codable {
        let aircraftType: String
        let aircraftSerialNumber: String?
        let nNumber: String?
        let system: String
        let component: String?
        let jobDate: String?            // ISO 8601 formatted date
        let taskDescription: String?
        let tmReferences: String?
        let notes: String?
        let recommendations: String?
    }

    struct ExportedJobTool: Codable {
        let name: String
        let ownershipType: String?
        let borrowedFrom: String?
        let notes: String?
        let aliases: [String]?
        let groupName: String?          // Tool Set name for context
    }

    struct ExportedJobConsumable: Codable {
        let name: String
        let category: String?
        let size: String?
        let spec: String?
        let notes: String?
    }

    struct ExportedJobChemical: Codable {
        let name: String
        let category: String?
        let size: String?
        let spec: String?
        let notes: String?
    }

    struct ExportedJobPart: Codable {
        let partNumber: String?
        let alternatePartNumber: String?
        let nomenclature: String?
        let nsn: String?
        let quantity: Int
        let unitOfMeasure: String?
        let notes: String?
    }

    // MARK: - Export

    /// Exports a single job record as a `.frojob` bundle.
    /// - Parameter job: The JobRecord to export
    /// - Returns: URL to the temporary `.frojob` file, or nil on failure
    func exportJob(_ job: JobRecord) -> URL? {
        // Build exported data
        let exportedJob = ExportedJob(
            aircraftType: job.aircraftType,
            aircraftSerialNumber: job.aircraftSerialNumber,
            nNumber: job.nNumber,
            system: job.system,
            component: job.component,
            jobDate: formatDate(job.jobDate),
            taskDescription: job.taskDescription,
            tmReferences: job.tmReferences,
            notes: job.notes,
            recommendations: job.recommendations
        )

        // Export tools
        let tools: [ExportedJobTool]
        if let toolSet = job.tools {
            tools = Array(toolSet).sortedBySize().compactMap { tool in
                let name = tool.name
                guard !name.isEmpty else { return nil }
                return ExportedJobTool(
                    name: name,
                    ownershipType: tool.ownershipType,
                    borrowedFrom: tool.borrowedFrom,
                    notes: tool.notes,
                    aliases: tool.aliases,
                    groupName: tool.group?.name
                )
            }
        } else {
            tools = []
        }

        // Export consumables
        let consumables: [ExportedJobConsumable]
        if let consumableSet = job.consumables {
            consumables = consumableSet.sorted { $0.name < $1.name }.compactMap { item in
                let name = item.name
                guard !name.isEmpty else { return nil }
                return ExportedJobConsumable(
                    name: name,
                    category: item.category,
                    size: item.size,
                    spec: item.spec,
                    notes: item.notes
                )
            }
        } else {
            consumables = []
        }

        // Export chemicals
        let chemicals: [ExportedJobChemical]
        if let chemicalSet = job.chemicals {
            chemicals = chemicalSet.sorted { $0.name < $1.name }.compactMap { item in
                let name = item.name
                guard !name.isEmpty else { return nil }
                return ExportedJobChemical(
                    name: name,
                    category: item.category,
                    size: item.size,
                    spec: item.spec,
                    notes: item.notes
                )
            }
        } else {
            chemicals = []
        }

        // Export parts
        let parts: [ExportedJobPart]
        if let partSet = job.parts {
            parts = partSet.sorted { $0.nomenclature < $1.nomenclature }.map { part in
                ExportedJobPart(
                    partNumber: part.partNumber,
                    alternatePartNumber: part.alternatePartNumber,
                    nomenclature: part.nomenclature,
                    nsn: part.nsn,
                    quantity: Int(part.quantity),
                    unitOfMeasure: part.unitOfMeasure,
                    notes: part.notes
                )
            }
        } else {
            parts = []
        }

        let appVersion = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "0.1.0"

        let bundle = JobExportBundle(
            version: 1,
            exportDate: ISO8601DateFormatter().string(from: Date()),
            appVersion: appVersion,
            job: exportedJob,
            tools: tools,
            consumables: consumables,
            chemicals: chemicals,
            parts: parts
        )

        // Encode to JSON
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]

        guard let jsonData = try? encoder.encode(bundle) else {
            print("JobExportService: Failed to encode job bundle to JSON")
            return nil
        }

        // Create temp directory for the bundle
        let tempDir = FileManager.default.temporaryDirectory
        let bundleDir = tempDir.appendingPathComponent("frojob_\(UUID().uuidString)")

        do {
            try FileManager.default.createDirectory(at: bundleDir, withIntermediateDirectories: true)

            // Write job.json
            let jsonURL = bundleDir.appendingPathComponent("job.json")
            try jsonData.write(to: jsonURL)

            // Generate filename
            let fileName = generateFilename(for: job)
            let frojobURL = tempDir.appendingPathComponent(fileName)

            // Remove existing file if any
            try? FileManager.default.removeItem(at: frojobURL)

            // Create ZIP archive using manual ZIP writer (avoids NSFileCoordinator
            // data descriptor flag issue that breaks our manual ZIP parser on import)
            guard createZipArchive(from: bundleDir, to: frojobURL) else {
                print("JobExportService: Failed to create ZIP archive")
                try? FileManager.default.removeItem(at: bundleDir)
                return nil
            }

            // Clean up temp directory
            try? FileManager.default.removeItem(at: bundleDir)

            print("JobExportService: Exported job '\(job.aircraftType)' — \(tools.count) tools, \(parts.count) parts, \(consumables.count) consumables, \(chemicals.count) chemicals")
            return frojobURL

        } catch {
            print("JobExportService: Export failed — \(error)")
            try? FileManager.default.removeItem(at: bundleDir)
            return nil
        }
    }

    // MARK: - Helpers

    /// Generates a descriptive filename for the .frojob bundle.
    /// Format: FRO_Job_[AircraftType]_[System]_[YYYYMMDD].frojob
    private func generateFilename(for job: JobRecord) -> String {
        func sanitize(_ text: String?) -> String {
            guard let text = text?.trimmingCharacters(in: .whitespacesAndNewlines),
                  !text.isEmpty else { return "" }
            var result = text.replacingOccurrences(of: " ", with: "_")
            let invalidChars = CharacterSet(charactersIn: "/\\:*?\"<>|")
            result = result.components(separatedBy: invalidChars).joined()
            return String(result.prefix(30))
        }

        var components = ["FRO", "Job"]

        let aircraft = sanitize(job.aircraftType)
        if !aircraft.isEmpty { components.append(aircraft) }

        let system = sanitize(job.system)
        if !system.isEmpty { components.append(system) }

        // Add date
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyyyMMdd"
        components.append(dateFormatter.string(from: job.jobDate))

        return components.joined(separator: "_") + ".frojob"
    }

    /// Formats a date to ISO 8601 string, or returns nil.
    private func formatDate(_ date: Date?) -> String? {
        guard let date = date else { return nil }
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        formatter.locale = Locale(identifier: "en_US_POSIX")
        return formatter.string(from: date)
    }

    // MARK: - ZIP Archive

    /// Creates a ZIP archive from a directory using manual ZIP format writing.
    /// Uses stored (no compression) method with no data descriptor flag,
    /// ensuring full compatibility with our manual ZIP parser on import.
    private func createZipArchive(from sourceDir: URL, to destURL: URL) -> Bool {
        let fm = FileManager.default

        guard let enumerator = fm.enumerator(
            at: sourceDir,
            includingPropertiesForKeys: [.isRegularFileKey],
            options: [.skipsHiddenFiles]
        ) else { return false }

        var files: [(relativePath: String, url: URL)] = []
        while let fileURL = enumerator.nextObject() as? URL {
            guard let resourceValues = try? fileURL.resourceValues(forKeys: [.isRegularFileKey]),
                  resourceValues.isRegularFile == true else { continue }
            let fullPath = fileURL.path
            let basePath = sourceDir.path.hasSuffix("/") ? sourceDir.path : sourceDir.path + "/"
            guard fullPath.hasPrefix(basePath) else { continue }
            let relativePath = String(fullPath.dropFirst(basePath.count))
            files.append((relativePath: relativePath, url: fileURL))
        }

        var zipData = Data()
        var centralDirectory = Data()
        var centralEntryCount: UInt16 = 0

        for file in files {
            guard let fileData = try? Data(contentsOf: file.url) else { continue }
            let fileNameData = Data(file.relativePath.utf8)
            let crc = crc32(fileData)
            let fileSize = UInt32(fileData.count)
            let localHeaderOffset = UInt32(zipData.count)

            // Local file header
            var localHeader = Data()
            localHeader.appendUInt32(0x04034B50) // PK\x03\x04
            localHeader.appendUInt16(20)          // version needed (2.0)
            localHeader.appendUInt16(0)           // general purpose bit flag (NO data descriptor)
            localHeader.appendUInt16(0)           // compression method (stored)
            localHeader.appendUInt16(0)           // last mod time
            localHeader.appendUInt16(0)           // last mod date
            localHeader.appendUInt32(crc)         // CRC-32
            localHeader.appendUInt32(fileSize)    // compressed size
            localHeader.appendUInt32(fileSize)    // uncompressed size
            localHeader.appendUInt16(UInt16(fileNameData.count)) // file name length
            localHeader.appendUInt16(0)           // extra field length

            zipData.append(localHeader)
            zipData.append(fileNameData)
            zipData.append(fileData)

            // Central directory entry
            var cdEntry = Data()
            cdEntry.appendUInt32(0x02014B50)  // PK\x01\x02
            cdEntry.appendUInt16(20)           // version made by
            cdEntry.appendUInt16(20)           // version needed
            cdEntry.appendUInt16(0)            // general purpose bit flag
            cdEntry.appendUInt16(0)            // compression method (stored)
            cdEntry.appendUInt16(0)            // last mod time
            cdEntry.appendUInt16(0)            // last mod date
            cdEntry.appendUInt32(crc)          // CRC-32
            cdEntry.appendUInt32(fileSize)     // compressed size
            cdEntry.appendUInt32(fileSize)     // uncompressed size
            cdEntry.appendUInt16(UInt16(fileNameData.count)) // file name length
            cdEntry.appendUInt16(0)            // extra field length
            cdEntry.appendUInt16(0)            // file comment length
            cdEntry.appendUInt16(0)            // disk number start
            cdEntry.appendUInt16(0)            // internal file attributes
            cdEntry.appendUInt32(0)            // external file attributes
            cdEntry.appendUInt32(localHeaderOffset) // offset of local header

            cdEntry.append(fileNameData)
            centralDirectory.append(cdEntry)
            centralEntryCount += 1
        }

        let cdOffset = UInt32(zipData.count)
        zipData.append(centralDirectory)
        let cdSize = UInt32(centralDirectory.count)

        // End of central directory record
        var eocd = Data()
        eocd.appendUInt32(0x06054B50)  // PK\x05\x06
        eocd.appendUInt16(0)            // disk number
        eocd.appendUInt16(0)            // disk where CD starts
        eocd.appendUInt16(centralEntryCount)  // entries on this disk
        eocd.appendUInt16(centralEntryCount)  // total entries
        eocd.appendUInt32(cdSize)       // size of central directory
        eocd.appendUInt32(cdOffset)     // offset of central directory
        eocd.appendUInt16(0)            // comment length
        zipData.append(eocd)

        do {
            try zipData.write(to: destURL)
            return true
        } catch {
            print("JobExportService: Failed to write ZIP — \(error)")
            return false
        }
    }

    /// Computes CRC-32 for the given data.
    private func crc32(_ data: Data) -> UInt32 {
        var crc: UInt32 = 0xFFFFFFFF
        for byte in data {
            let index = Int((crc ^ UInt32(byte)) & 0xFF)
            crc = Self.crc32Table[index] ^ (crc >> 8)
        }
        return crc ^ 0xFFFFFFFF
    }

    /// CRC-32 lookup table (standard polynomial 0xEDB88320)
    private static let crc32Table: [UInt32] = {
        (0..<256).map { i -> UInt32 in
            var crc = UInt32(i)
            for _ in 0..<8 {
                if crc & 1 != 0 {
                    crc = (crc >> 1) ^ 0xEDB88320
                } else {
                    crc >>= 1
                }
            }
            return crc
        }
    }()
}

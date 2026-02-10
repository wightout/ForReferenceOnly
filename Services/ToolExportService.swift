import Foundation
import UIKit
import SwiftData

/// Service for exporting tools as `.frotool` bundles (renamed .zip files).
/// A `.frotool` bundle contains:
///   - `export.json`: Metadata for all tools, including Set/Kit context
///   - `photos/`: Directory containing all tool photos, organized by tool ID
///
/// Supports multi-tool export in a single bundle for shop inventory sharing.
final class ToolExportService {

    nonisolated(unsafe) static let shared = ToolExportService()

    /// File extension for tool export bundles
    static let fileExtension = "frotool"

    private init() {}

    // MARK: - Export Data Models

    /// JSON-serializable representation of a tool for export
    struct ExportedTool: Codable {
        let name: String
        let ownershipType: String
        let borrowedFrom: String?
        let notes: String?
        let aliases: [String]?
        let photoFileNames: [String]?
        let toolSet: ExportedToolSet?
        let toolKits: [ExportedToolKit]?
    }

    /// JSON-serializable representation of a Tool Set (ToolGroup) for export
    struct ExportedToolSet: Codable {
        let name: String
        let ownershipType: String
        let toolType: String?
        let measurementType: String?
    }

    /// JSON-serializable representation of a Tool Kit for export
    struct ExportedToolKit: Codable {
        let name: String
        let ownershipType: String
        let toolType: String?
        let descriptionText: String?
    }

    /// Top-level export container
    struct ExportBundle: Codable {
        let version: Int
        let exportDate: String
        let toolCount: Int
        let tools: [ExportedTool]
    }

    // MARK: - Export

    /// Exports an array of tools into a `.frotool` bundle file.
    /// Returns the URL to the created bundle file, or nil on failure.
    /// - Parameters:
    ///   - tools: Array of Tool Core Data objects to export
    ///   - context: Managed object context for reading relationships
    /// - Returns: URL to the created `.frotool` file
    func exportTools(_ tools: [Tool], context: ModelContext) -> URL? {
        guard !tools.isEmpty else {
            print("ToolExportService: No tools to export")
            return nil
        }

        let tempDir = FileManager.default.temporaryDirectory
        let bundleName = generateBundleName(for: tools)
        let workDir = tempDir.appendingPathComponent("frotool_export_\(UUID().uuidString)", isDirectory: true)
        let photosDir = workDir.appendingPathComponent("photos", isDirectory: true)

        do {
            // Create working directories
            try FileManager.default.createDirectory(at: workDir, withIntermediateDirectories: true)
            try FileManager.default.createDirectory(at: photosDir, withIntermediateDirectories: true)

            // Build export data
            var exportedTools: [ExportedTool] = []

            for tool in tools {
                let exported = buildExportedTool(tool)
                exportedTools.append(exported)

                // Copy photos if they exist
                copyPhotos(for: tool.id, photoFileNames: tool.photoFileNames, to: photosDir)
            }

            // Create export.json
            let exportBundle = ExportBundle(
                version: 1,
                exportDate: ISO8601DateFormatter().string(from: Date()),
                toolCount: exportedTools.count,
                tools: exportedTools
            )

            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            let jsonData = try encoder.encode(exportBundle)
            let jsonURL = workDir.appendingPathComponent("export.json")
            try jsonData.write(to: jsonURL)

            // Create .frotool archive directly (ZIP format with custom extension)
            let frotoolURL = tempDir.appendingPathComponent("\(bundleName).\(ToolExportService.fileExtension)")
            try? FileManager.default.removeItem(at: frotoolURL)

            guard createZipArchive(from: workDir, to: frotoolURL) else {
                print("ToolExportService: Failed to create ZIP archive")
                try? FileManager.default.removeItem(at: workDir)
                return nil
            }

            // Clean up working directory
            try? FileManager.default.removeItem(at: workDir)

            // Verify the file was created
            let fileSize = (try? FileManager.default.attributesOfItem(atPath: frotoolURL.path)[.size] as? Int) ?? 0
            print("ToolExportService: Exported \(tools.count) tool(s) to \(frotoolURL.lastPathComponent) (\(fileSize) bytes)")
            return frotoolURL

        } catch {
            print("ToolExportService: Export failed - \(error)")
            try? FileManager.default.removeItem(at: workDir)
            return nil
        }
    }

    // MARK: - Build Export Data

    private func buildExportedTool(_ tool: Tool) -> ExportedTool {
        // Get Tool Set context
        var exportedSet: ExportedToolSet?
        if let group = tool.group {
            exportedSet = ExportedToolSet(
                name: group.name,
                ownershipType: group.ownershipType,
                toolType: group.toolType,
                measurementType: group.measurementType
            )
        }

        // Get Tool Kit contexts
        var exportedKits: [ExportedToolKit]?
        if let kits = tool.toolKits, !kits.isEmpty {
            exportedKits = kits.sorted(by: { $0.name < $1.name }).map { kit in
                ExportedToolKit(
                    name: kit.name,
                    ownershipType: kit.ownershipType,
                    toolType: kit.toolType,
                    descriptionText: kit.descriptionText
                )
            }
        }

        return ExportedTool(
            name: tool.name,
            ownershipType: tool.ownershipType,
            borrowedFrom: tool.borrowedFrom,
            notes: tool.notes,
            aliases: tool.aliases,
            photoFileNames: tool.photoFileNames,
            toolSet: exportedSet,
            toolKits: exportedKits
        )
    }

    // MARK: - Photo Copy

    private func copyPhotos(for toolID: UUID, photoFileNames: [String]?, to photosDir: URL) {
        guard let fileNames = photoFileNames, !fileNames.isEmpty else { return }

        let toolPhotosDir = photosDir.appendingPathComponent(toolID.uuidString, isDirectory: true)
        try? FileManager.default.createDirectory(at: toolPhotosDir, withIntermediateDirectories: true)

        let photoService = ToolPhotoService.shared
        for (index, fileName) in fileNames.enumerated() {
            guard !fileName.isEmpty else { continue }
            let sourceURL = photoService.photoURL(for: toolID, at: index)
            if FileManager.default.fileExists(atPath: sourceURL.path) {
                let destURL = toolPhotosDir.appendingPathComponent(fileName)
                try? FileManager.default.copyItem(at: sourceURL, to: destURL)
            }
        }
    }

    // MARK: - Zip Archive

    /// Creates a ZIP archive from a directory using manual ZIP format writing.
    /// Uses stored (no compression) method with no data descriptor flag,
    /// ensuring full compatibility with our manual ZIP parser on import.
    private func createZipArchive(from sourceDir: URL, to destURL: URL) -> Bool {
        let fm = FileManager.default

        // Enumerate all files in the source directory
        guard let enumerator = fm.enumerator(
            at: sourceDir,
            includingPropertiesForKeys: [.isRegularFileKey],
            options: [.skipsHiddenFiles]
        ) else { return false }

        var files: [(relativePath: String, url: URL)] = []
        while let fileURL = enumerator.nextObject() as? URL {
            guard let resourceValues = try? fileURL.resourceValues(forKeys: [.isRegularFileKey]),
                  resourceValues.isRegularFile == true else { continue }
            // Get path relative to sourceDir
            let fullPath = fileURL.path
            let basePath = sourceDir.path.hasSuffix("/") ? sourceDir.path : sourceDir.path + "/"
            guard fullPath.hasPrefix(basePath) else { continue }
            let relativePath = String(fullPath.dropFirst(basePath.count))
            files.append((relativePath: relativePath, url: fileURL))
        }

        print("ToolExportService: ZIP — \(files.count) file(s) to archive: \(files.map { $0.relativePath })")

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
            print("ToolExportService: Failed to write ZIP — \(error)")
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

    // MARK: - Bundle Naming

    /// Generates a descriptive file name for the export bundle
    private func generateBundleName(for tools: [Tool]) -> String {
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyyy-MM-dd"
        let dateStr = dateFormatter.string(from: Date())

        if tools.count == 1, let name = tools.first?.name {
            let safeName = name.replacingOccurrences(of: "/", with: "-")
                .replacingOccurrences(of: "\"", with: "")
                .replacingOccurrences(of: ":", with: "-")
                .trimmingCharacters(in: .whitespacesAndNewlines)
            return "FRO-Tool-\(safeName)-\(dateStr)"
        } else {
            return "FRO-Tools-\(tools.count)-\(dateStr)"
        }
    }
}

// MARK: - Data Extension for ZIP Writing

/// Helpers for writing little-endian integers to Data, used by manual ZIP writer.
extension Data {
    mutating func appendUInt16(_ value: UInt16) {
        var v = value.littleEndian
        append(Data(bytes: &v, count: 2))
    }

    mutating func appendUInt32(_ value: UInt32) {
        var v = value.littleEndian
        append(Data(bytes: &v, count: 4))
    }
}

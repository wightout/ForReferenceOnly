import Foundation
import UIKit
import SwiftData

/// Service for importing tools from `.frotool` bundles.
/// Parses the bundle, detects duplicates, and creates tools + photos + Sets/Kits.
final class ToolImportService {

    nonisolated(unsafe) static let shared = ToolImportService()

    private init() {}

    // MARK: - Import Result Models

    /// Represents a tool parsed from an import bundle, ready for review
    struct ImportedToolPreview {
        let name: String
        let ownershipType: String
        let borrowedFrom: String?
        let notes: String?
        let aliases: [String]?
        let photoFileNames: [String]?
        let toolSetName: String?
        let toolSetOwnership: String?
        let toolSetToolType: String?
        let toolSetMeasurementType: String?
        let toolKitNames: [String]?
        let toolKitOwnerships: [String]?
        let toolKitToolTypes: [String]?
        let toolKitDescriptions: [String]?
        let heroThumbnail: UIImage?
        let isDuplicate: Bool
        var isSelected: Bool
    }

    /// Result of parsing an import bundle
    struct ImportParseResult {
        let tools: [ImportedToolPreview]
        let bundleURL: URL
        let exportDate: String
        let version: Int
    }

    // MARK: - Parse Bundle

    /// Parses a `.frotool` bundle file and returns preview data for the review screen.
    /// Does NOT create any SwiftData objects yet — that happens in `importSelectedTools`.
    /// - Parameters:
    ///   - url: URL to the `.frotool` file
    ///   - context: Model context for duplicate detection
    /// - Returns: ParseResult with tool previews
    func parseFrotoolBundle(at url: URL, context: ModelContext) throws -> ImportParseResult {
        // Start accessing the security-scoped resource
        let accessing = url.startAccessingSecurityScopedResource()
        defer {
            if accessing {
                url.stopAccessingSecurityScopedResource()
            }
        }

        // Unzip to temp directory
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("frotool_import_\(UUID().uuidString)", isDirectory: true)

        try unzipBundle(from: url, to: tempDir)

        // Read export.json
        let jsonURL = tempDir.appendingPathComponent("export.json")
        guard FileManager.default.fileExists(atPath: jsonURL.path) else {
            throw ToolImportError.missingExportJSON
        }

        let jsonData = try Data(contentsOf: jsonURL)
        let decoder = JSONDecoder()
        let exportBundle = try decoder.decode(ToolExportService.ExportBundle.self, from: jsonData)

        // Fetch existing tool names for duplicate detection
        let existingNames = fetchExistingToolNames(context: context)

        // Build preview tools
        let photosDir = tempDir.appendingPathComponent("photos", isDirectory: true)
        var previews: [ImportedToolPreview] = []

        for (_, exportedTool) in exportBundle.tools.enumerated() {
            let isDuplicate = existingNames.contains(exportedTool.name.lowercased())

            // Try to load hero thumbnail from the bundle photos
            var heroThumb: UIImage?
            if let fileNames = exportedTool.photoFileNames, !fileNames.isEmpty {
                // Look for photos in the photos directory
                // They could be organized by tool ID or just by index
                let toolPhotoDirs = try? FileManager.default.contentsOfDirectory(
                    at: photosDir,
                    includingPropertiesForKeys: nil
                )
                // Find matching directory (we don't have tool IDs in the export, so we use the order)
                if let dirs = toolPhotoDirs {
                    for dir in dirs {
                        let heroURL = dir.appendingPathComponent(fileNames[0])
                        if FileManager.default.fileExists(atPath: heroURL.path) {
                            heroThumb = UIImage(contentsOfFile: heroURL.path)
                            break
                        }
                    }
                }
            }

            // Extract kit info arrays
            var kitNames: [String]?
            var kitOwnerships: [String]?
            var kitToolTypes: [String]?
            var kitDescriptions: [String]?

            if let kits = exportedTool.toolKits {
                kitNames = kits.map { $0.name }
                kitOwnerships = kits.map { $0.ownershipType }
                kitToolTypes = kits.map { $0.toolType ?? "" }
                kitDescriptions = kits.map { $0.descriptionText ?? "" }
            }

            let preview = ImportedToolPreview(
                name: exportedTool.name,
                ownershipType: exportedTool.ownershipType,
                borrowedFrom: exportedTool.borrowedFrom,
                notes: exportedTool.notes,
                aliases: exportedTool.aliases,
                photoFileNames: exportedTool.photoFileNames,
                toolSetName: exportedTool.toolSet?.name,
                toolSetOwnership: exportedTool.toolSet?.ownershipType,
                toolSetToolType: exportedTool.toolSet?.toolType,
                toolSetMeasurementType: exportedTool.toolSet?.measurementType,
                toolKitNames: kitNames,
                toolKitOwnerships: kitOwnerships,
                toolKitToolTypes: kitToolTypes,
                toolKitDescriptions: kitDescriptions,
                heroThumbnail: heroThumb,
                isDuplicate: isDuplicate,
                isSelected: !isDuplicate // Pre-deselect duplicates
            )
            previews.append(preview)
        }

        print("ToolImportService: Parsed \(previews.count) tools (\(previews.filter { $0.isDuplicate }.count) duplicates)")

        return ImportParseResult(
            tools: previews,
            bundleURL: tempDir,
            exportDate: exportBundle.exportDate,
            version: exportBundle.version
        )
    }

    // MARK: - Import Selected Tools

    /// Creates SwiftData objects for the selected tools from an import preview.
    /// Also copies photos and auto-creates Tool Sets/Kits as needed.
    /// - Parameters:
    ///   - previews: The selected tool previews to import
    ///   - bundleDir: The unzipped bundle temp directory
    ///   - defaultOwnership: Default ownership type for imported tools (usually "shop")
    ///   - context: Model context
    /// - Returns: Number of tools successfully imported
    func importSelectedTools(
        _ previews: [ImportedToolPreview],
        bundleDir: URL,
        defaultOwnership: String,
        context: ModelContext
    ) throws -> Int {
        let photosDir = bundleDir.appendingPathComponent("photos", isDirectory: true)
        var importCount = 0

        // Cache for created Tool Sets and Kits to avoid duplicates
        var createdSets: [String: FROToolGroup] = [:]
        var createdKits: [String: FROToolKit] = [:]

        // Pre-fetch existing sets and kits
        let existingSets = fetchExistingToolSets(context: context)
        let existingKits = fetchExistingToolKits(context: context)

        for set in existingSets {
            createdSets[set.name] = set
        }
        for kit in existingKits {
            createdKits[kit.name] = kit
        }

        for preview in previews where preview.isSelected {
            let tool = FROTool(
                name: preview.name,
                aliases: preview.aliases,
                ownershipType: defaultOwnership,
                borrowedFrom: preview.borrowedFrom,
                notes: preview.notes
            )
            context.insert(tool)

            // Handle Tool Set assignment
            if let setName = preview.toolSetName, !setName.isEmpty {
                if let existingSet = createdSets[setName] {
                    tool.group = existingSet
                } else {
                    // Create new Tool Set
                    let newSet = FROToolGroup(
                        name: setName,
                        ownershipType: defaultOwnership,
                        toolType: preview.toolSetToolType,
                        measurementType: preview.toolSetMeasurementType ?? "sae"
                    )
                    context.insert(newSet)
                    createdSets[setName] = newSet
                    tool.group = newSet
                    print("ToolImportService: Created new Tool Set '\(setName)'")
                }
            }

            // Handle Tool Kit assignments
            if let kitNames = preview.toolKitNames {
                for (index, kitName) in kitNames.enumerated() where !kitName.isEmpty {
                    if let existingKit = createdKits[kitName] {
                        if tool.toolKits == nil { tool.toolKits = [] }
                        tool.toolKits?.append(existingKit)
                    } else {
                        // Create new Tool Kit
                        let newKit = FROToolKit(
                            name: kitName,
                            ownershipType: defaultOwnership,
                            toolType: preview.toolKitToolTypes?[safe: index]?.isEmpty == false ? preview.toolKitToolTypes?[index] : nil
                        )
                        if let desc = preview.toolKitDescriptions?[safe: index], !desc.isEmpty {
                            newKit.descriptionText = desc
                        }
                        context.insert(newKit)
                        createdKits[kitName] = newKit
                        if tool.toolKits == nil { tool.toolKits = [] }
                        tool.toolKits?.append(newKit)
                        print("ToolImportService: Created new Tool Kit '\(kitName)'")
                    }
                }
            }

            // Copy photos from bundle to tool's photo directory
            let toolID = tool.id
            importPhotos(
                for: toolID,
                photoFileNames: preview.photoFileNames,
                from: photosDir,
                tool: tool
            )

            importCount += 1
        }

        try context.save()

        // Clean up temp directory
        try? FileManager.default.removeItem(at: bundleDir)

        print("ToolImportService: Successfully imported \(importCount) tools")
        return importCount
    }

    // MARK: - Photo Import

    private func importPhotos(for toolID: UUID, photoFileNames: [String]?, from photosDir: URL, tool: FROTool) {
        guard let fileNames = photoFileNames, !fileNames.isEmpty else { return }

        let photoService = ToolPhotoService.shared

        // Ensure destination directory exists
        let destDir = photoService.photoDirectory(for: toolID)
        try? FileManager.default.createDirectory(at: destDir, withIntermediateDirectories: true)

        // Find the photos in the bundle
        guard let toolDirs = try? FileManager.default.contentsOfDirectory(
            at: photosDir,
            includingPropertiesForKeys: nil
        ) else { return }

        var copiedNames: [String] = []

        for (index, fileName) in fileNames.enumerated() {
            guard !fileName.isEmpty else { continue }

            // Search through all tool directories in the bundle for matching photos
            for dir in toolDirs {
                let sourceURL = dir.appendingPathComponent(fileName)
                if FileManager.default.fileExists(atPath: sourceURL.path) {
                    let destURL = photoService.photoURL(for: toolID, at: index)
                    try? FileManager.default.copyItem(at: sourceURL, to: destURL)
                    copiedNames.append(ToolPhotoService.fileName(at: index))
                    break
                }
            }
        }

        if !copiedNames.isEmpty {
            tool.photoFileNames = copiedNames
        }
    }

    // MARK: - Duplicate Detection

    private func fetchExistingToolNames(context: ModelContext) -> Set<String> {
        let descriptor = FetchDescriptor<FROTool>(
            predicate: #Predicate { $0.isInGarage == true }
        )
        guard let tools = try? context.fetch(descriptor) else { return [] }
        return Set(tools.map { $0.name.lowercased() })
    }

    private func fetchExistingToolSets(context: ModelContext) -> [FROToolGroup] {
        let descriptor = FetchDescriptor<FROToolGroup>()
        return (try? context.fetch(descriptor)) ?? []
    }

    private func fetchExistingToolKits(context: ModelContext) -> [FROToolKit] {
        let descriptor = FetchDescriptor<FROToolKit>()
        return (try? context.fetch(descriptor)) ?? []
    }

    // MARK: - Unzip

    /// Extracts a .frotool (zip) bundle to a destination directory.
    /// Reads the ZIP data directly and extracts using our manual parser.
    private func unzipBundle(from sourceURL: URL, to destDir: URL) throws {
        try FileManager.default.createDirectory(at: destDir, withIntermediateDirectories: true)

        // Copy to temp location to avoid security-scoped resource issues
        let tempZip = destDir.deletingLastPathComponent()
            .appendingPathComponent(UUID().uuidString + ".zip")
        try FileManager.default.copyItem(at: sourceURL, to: tempZip)
        defer { try? FileManager.default.removeItem(at: tempZip) }

        // Read ZIP data and extract manually
        let data = try Data(contentsOf: tempZip)

        // Verify ZIP signature (PK\x03\x04)
        guard data.count > 4,
              data[0] == 0x50, data[1] == 0x4B,
              data[2] == 0x03, data[3] == 0x04 else {
            print("ToolImportService: Not a valid ZIP file (\(data.count) bytes)")
            throw ToolImportError.unzipFailed
        }

        print("ToolImportService: Extracting ZIP (\(data.count) bytes)")
        let success = extractZipManually(data, to: destDir)

        if !success {
            throw ToolImportError.unzipFailed
        }
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
                    print("ToolImportService: Extracted '\(fileName)' (\(fileData.count) bytes, stored)")
                } else if compressionMethod == 8 {
                    // Deflated — use Foundation's decompression
                    let compressedData = data[dataStart..<dataEnd]
                    if let decompressed = decompressDeflate(Data(compressedData), expectedSize: uncompressedSize) {
                        try? decompressed.write(to: fileURL)
                        print("ToolImportService: Extracted '\(fileName)' (\(decompressed.count) bytes, deflated)")
                    } else {
                        print("ToolImportService: Failed to decompress '\(fileName)'")
                    }
                } else {
                    print("ToolImportService: Unsupported compression method \(compressionMethod) for '\(fileName)'")
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

        // Verify export.json was extracted — check root first, then subdirectories
        // (older exports may wrap directory contents in a subdirectory)
        let jsonURL = destDir.appendingPathComponent("export.json")
        if FileManager.default.fileExists(atPath: jsonURL.path) {
            print("ToolImportService: Found export.json at root")
            return true
        }

        print("ToolImportService: export.json not at root, searching subdirectories...")
        // Search one level deep for export.json (older export format wrapping)
        if let subdirs = try? FileManager.default.contentsOfDirectory(at: destDir, includingPropertiesForKeys: nil) {
            for subdir in subdirs {
                var isDir: ObjCBool = false
                FileManager.default.fileExists(atPath: subdir.path, isDirectory: &isDir)
                guard isDir.boolValue else { continue }

                let nestedJSON = subdir.appendingPathComponent("export.json")
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
        print("ToolImportService: export.json not found — extraction failed")
        return false
    }

    /// Decompresses deflate-compressed data using Foundation.
    private func decompressDeflate(_ data: Data, expectedSize: Int) -> Data? {
        // Add zlib header (0x78 0x01) for raw deflate decompression
        var zlibData = Data([0x78, 0x01])
        zlibData.append(data)

        return try? (zlibData as NSData).decompressed(using: .zlib) as Data
    }
}

// MARK: - Safe Array Subscript

private extension Array {
    subscript(safe index: Int) -> Element? {
        return indices.contains(index) ? self[index] : nil
    }
}

// MARK: - Errors

enum ToolImportError: LocalizedError {
    case missingExportJSON
    case invalidFormat
    case unzipFailed

    var errorDescription: String? {
        switch self {
        case .missingExportJSON:
            return "The file does not contain valid tool export data."
        case .invalidFormat:
            return "The file format is not recognized."
        case .unzipFailed:
            return "Failed to extract the tool bundle."
        }
    }
}

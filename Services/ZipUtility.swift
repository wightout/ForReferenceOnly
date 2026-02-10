import Foundation

/// Shared ZIP archive creation and extraction utility.
/// Consolidates the manual ZIP read/write code previously duplicated across
/// ToolExportService, ToolImportService, JobExportService, and JobImportService.
enum ZipUtility {

    // MARK: - Create Archive

    /// Creates a ZIP archive from a directory using stored (no compression) method.
    /// Uses no data descriptor flag, ensuring compatibility with our manual parser.
    /// - Parameters:
    ///   - sourceDir: Directory containing files to archive
    ///   - destURL: Output URL for the ZIP file
    /// - Returns: true if the archive was created successfully
    @discardableResult
    static func createArchive(from sourceDir: URL, to destURL: URL) -> Bool {
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
            localHeader.appendUInt32(0x04034B50)
            localHeader.appendUInt16(20)
            localHeader.appendUInt16(0)
            localHeader.appendUInt16(0)
            localHeader.appendUInt16(0)
            localHeader.appendUInt16(0)
            localHeader.appendUInt32(crc)
            localHeader.appendUInt32(fileSize)
            localHeader.appendUInt32(fileSize)
            localHeader.appendUInt16(UInt16(fileNameData.count))
            localHeader.appendUInt16(0)

            zipData.append(localHeader)
            zipData.append(fileNameData)
            zipData.append(fileData)

            // Central directory entry
            var cdEntry = Data()
            cdEntry.appendUInt32(0x02014B50)
            cdEntry.appendUInt16(20)
            cdEntry.appendUInt16(20)
            cdEntry.appendUInt16(0)
            cdEntry.appendUInt16(0)
            cdEntry.appendUInt16(0)
            cdEntry.appendUInt16(0)
            cdEntry.appendUInt32(crc)
            cdEntry.appendUInt32(fileSize)
            cdEntry.appendUInt32(fileSize)
            cdEntry.appendUInt16(UInt16(fileNameData.count))
            cdEntry.appendUInt16(0)
            cdEntry.appendUInt16(0)
            cdEntry.appendUInt16(0)
            cdEntry.appendUInt16(0)
            cdEntry.appendUInt32(0)
            cdEntry.appendUInt32(localHeaderOffset)

            cdEntry.append(fileNameData)
            centralDirectory.append(cdEntry)
            centralEntryCount += 1
        }

        let cdOffset = UInt32(zipData.count)
        zipData.append(centralDirectory)
        let cdSize = UInt32(centralDirectory.count)

        // End of central directory record
        var eocd = Data()
        eocd.appendUInt32(0x06054B50)
        eocd.appendUInt16(0)
        eocd.appendUInt16(0)
        eocd.appendUInt16(centralEntryCount)
        eocd.appendUInt16(centralEntryCount)
        eocd.appendUInt32(cdSize)
        eocd.appendUInt32(cdOffset)
        eocd.appendUInt16(0)
        zipData.append(eocd)

        do {
            try zipData.write(to: destURL)
            return true
        } catch {
            print("ZipUtility: Failed to write ZIP — \(error)")
            return false
        }
    }

    // MARK: - Extract Archive

    /// Extracts a ZIP archive to a destination directory.
    /// Handles both standard ZIP and data descriptor (bit 3) formats.
    /// - Parameters:
    ///   - data: Raw ZIP data
    ///   - destDir: Directory to extract files into
    /// - Returns: true if extraction succeeded
    @discardableResult
    static func extractArchive(_ data: Data, to destDir: URL) -> Bool {
        var offset = 0
        let count = data.count

        while offset + 30 <= count {
            let sig = data[offset..<offset+4]
            guard sig.elementsEqual([0x50, 0x4B, 0x03, 0x04]) else {
                break
            }

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

            if hasDataDescriptor && compressedSize == 0 {
                var scanPos = dataStart
                while scanPos + 4 <= count {
                    if data[scanPos] == 0x50 && data[scanPos+1] == 0x4B {
                        let marker = data[scanPos+2]
                        let marker2 = data[scanPos+3]
                        if (marker == 0x03 && marker2 == 0x04) || (marker == 0x01 && marker2 == 0x02) {
                            break
                        }
                    }
                    scanPos += 1
                }

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
                if descriptorSize == 0 && scanPos - dataStart >= 12 {
                    let descStart = scanPos - 12
                    compressedSize = Int(UInt32(data[descStart+4]) | (UInt32(data[descStart+5]) << 8) |
                                         (UInt32(data[descStart+6]) << 16) | (UInt32(data[descStart+7]) << 24))
                    uncompressedSize = Int(UInt32(data[descStart+8]) | (UInt32(data[descStart+9]) << 8) |
                                           (UInt32(data[descStart+10]) << 16) | (UInt32(data[descStart+11]) << 24))
                    _ = descriptorSize // suppress warning
                }
            }

            let dataEnd = dataStart + compressedSize
            guard dataEnd <= count else { break }

            let fileURL = destDir.appendingPathComponent(fileName)

            if fileName.hasSuffix("/") {
                try? FileManager.default.createDirectory(at: fileURL, withIntermediateDirectories: true)
            } else {
                let parentDir = fileURL.deletingLastPathComponent()
                try? FileManager.default.createDirectory(at: parentDir, withIntermediateDirectories: true)

                if compressionMethod == 0 {
                    let fileData = data[dataStart..<dataEnd]
                    try? fileData.write(to: fileURL)
                } else if compressionMethod == 8 {
                    let compressedData = data[dataStart..<dataEnd]
                    if let decompressed = decompressDeflate(Data(compressedData), expectedSize: uncompressedSize) {
                        try? decompressed.write(to: fileURL)
                    }
                }
            }

            offset = dataEnd
            if hasDataDescriptor {
                if offset + 4 <= count && data[offset] == 0x50 && data[offset+1] == 0x4B &&
                   data[offset+2] == 0x07 && data[offset+3] == 0x08 {
                    offset += 16
                } else {
                    offset += 12
                }
            }
        }

        return true
    }

    /// Extracts a ZIP file at a URL to a destination directory.
    /// Handles security-scoped resource access and copies to a temp file first.
    /// - Parameters:
    ///   - sourceURL: URL to the ZIP file (may be security-scoped)
    ///   - destDir: Directory to extract files into
    /// - Throws: ZipError if extraction fails
    static func extractArchive(at sourceURL: URL, to destDir: URL) throws {
        try FileManager.default.createDirectory(at: destDir, withIntermediateDirectories: true)

        let tempZip = destDir.deletingLastPathComponent()
            .appendingPathComponent(UUID().uuidString + ".zip")
        try FileManager.default.copyItem(at: sourceURL, to: tempZip)
        defer { try? FileManager.default.removeItem(at: tempZip) }

        let data = try Data(contentsOf: tempZip)

        guard data.count > 4,
              data[0] == 0x50, data[1] == 0x4B,
              data[2] == 0x03, data[3] == 0x04 else {
            throw ZipError.invalidSignature
        }

        guard extractArchive(data, to: destDir) else {
            throw ZipError.extractionFailed
        }
    }

    /// Searches for a specific JSON file in the extracted directory.
    /// Checks root first, then one level of subdirectories (for NSFileCoordinator wrapping).
    /// If found in a subdirectory, moves all contents up to destDir.
    /// - Parameters:
    ///   - fileName: The JSON file to look for (e.g. "export.json", "job.json")
    ///   - destDir: The extraction directory
    /// - Returns: true if the file was found
    static func locateAndFlatten(jsonFile fileName: String, in destDir: URL) -> Bool {
        let jsonURL = destDir.appendingPathComponent(fileName)
        if FileManager.default.fileExists(atPath: jsonURL.path) {
            return true
        }

        if let subdirs = try? FileManager.default.contentsOfDirectory(at: destDir, includingPropertiesForKeys: nil) {
            for subdir in subdirs {
                var isDir: ObjCBool = false
                FileManager.default.fileExists(atPath: subdir.path, isDirectory: &isDir)
                guard isDir.boolValue else { continue }

                let nestedJSON = subdir.appendingPathComponent(fileName)
                if FileManager.default.fileExists(atPath: nestedJSON.path) {
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

    // MARK: - CRC-32

    static func crc32(_ data: Data) -> UInt32 {
        var crc: UInt32 = 0xFFFFFFFF
        for byte in data {
            let index = Int((crc ^ UInt32(byte)) & 0xFF)
            crc = crc32Table[index] ^ (crc >> 8)
        }
        return crc ^ 0xFFFFFFFF
    }

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

    // MARK: - Decompression

    private static func decompressDeflate(_ data: Data, expectedSize: Int) -> Data? {
        var zlibData = Data([0x78, 0x01])
        zlibData.append(data)
        if let result = try? (zlibData as NSData).decompressed(using: .zlib) as Data {
            return result
        }
        return try? (data as NSData).decompressed(using: .zlib) as Data
    }
}

// MARK: - Errors

enum ZipError: LocalizedError {
    case invalidSignature
    case extractionFailed

    var errorDescription: String? {
        switch self {
        case .invalidSignature:
            return "Not a valid ZIP file."
        case .extractionFailed:
            return "Failed to extract ZIP contents."
        }
    }
}

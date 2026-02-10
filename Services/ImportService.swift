import Foundation
import PDFKit

// MARK: - Import Data Model

/// Intermediate representation of data extracted from an imported PDF.
/// This is a plain Swift struct (not Core Data) used to review data before saving.
struct ImportedJobData {
    var aircraftType: String
    var system: String
    var aircraftSerialNumber: String?
    var nNumber: String?
    var component: String?
    var jobDate: Date?
    var taskDescription: String?
    var tmReferences: String?
    var toolsText: String?          // tools as plain text (not linked to Garage)
    var consumablesText: String?    // consumables as plain text
    var chemicalsText: String?      // chemicals as plain text
    var partsText: String?          // parts as plain text
    var notes: String?
    var recommendations: String?
    var source: ImportSource

    /// Combined notes including tools/consumables/chemicals as text.
    /// Used when saving the imported job since these aren't linked to Garage entities.
    var combinedNotes: String {
        var parts: [String] = []

        if let notes = notes, !notes.isEmpty {
            parts.append(notes)
        }

        if let tools = toolsText, !tools.isEmpty {
            parts.append("[Imported Tools]\n\(tools)")
        }

        if let consumables = consumablesText, !consumables.isEmpty {
            parts.append("[Imported Consumables]\n\(consumables)")
        }

        if let chemicals = chemicalsText, !chemicals.isEmpty {
            parts.append("[Imported Chemicals]\n\(chemicals)")
        }

        if let partsData = partsText, !partsData.isEmpty {
            parts.append("[Imported Parts]\n\(partsData)")
        }

        return parts.joined(separator: "\n\n")
    }
}

/// How the import data was parsed
enum ImportSource {
    case fillablePDF    // parsed from AcroForm widget annotations
    case readOnlyPDF    // parsed from text extraction
}

/// Errors that can occur during PDF import
enum ImportError: LocalizedError {
    case fileAccessDenied
    case invalidPDF
    case missingRequiredFields(details: String)
    case parsingFailed(details: String)

    var errorDescription: String? {
        switch self {
        case .fileAccessDenied:
            return "Unable to access the selected file. Please try again."
        case .invalidPDF:
            return "The selected file is not a valid PDF or could not be opened."
        case .missingRequiredFields(let details):
            return "Required fields are missing: \(details)"
        case .parsingFailed(let details):
            return details
        }
    }
}

// MARK: - Import Service

/// Service for importing job data from PDF files.
/// Supports both fillable PDFs (AcroForm fields) and read-only FRO PDF reports.
class ImportService {

    // MARK: - Public API

    /// Attempts to import job data from a PDF file URL.
    /// First tries to read AcroForm fields (fillable PDF).
    /// Falls back to text extraction (read-only PDF) if no form fields found.
    /// - Parameter url: URL to the PDF file (may be security-scoped)
    /// - Returns: ImportedJobData with extracted values
    /// - Throws: ImportError if the PDF cannot be parsed
    static func importFromPDF(url: URL) throws -> ImportedJobData {
        // Start accessing security-scoped resource (required for files from .fileImporter)
        let didStartAccessing = url.startAccessingSecurityScopedResource()
        defer {
            if didStartAccessing {
                url.stopAccessingSecurityScopedResource()
            }
        }

        guard let document = PDFDocument(url: url) else {
            throw ImportError.invalidPDF
        }

        // Try fillable PDF first (AcroForm fields with fro_ prefix)
        if let formData = parseFromFormFields(document: document) {
            print("ImportService: Successfully parsed fillable PDF with form fields")
            return formData
        }

        // Fall back to text extraction for read-only PDFs
        let textData = try parseFromTextContent(document: document)
        print("ImportService: Successfully parsed read-only PDF via text extraction")
        return textData
    }

    // MARK: - Fillable PDF Parsing

    /// Extracts data from AcroForm widget annotations.
    /// Returns nil if no FRO form fields (fro_ prefix) are found.
    private static func parseFromFormFields(document: PDFDocument) -> ImportedJobData? {
        var fieldValues: [String: String] = [:]

        // Iterate all pages and collect annotation values
        for pageIndex in 0..<document.pageCount {
            guard let page = document.page(at: pageIndex) else { continue }
            for annotation in page.annotations {
                guard let fieldName = annotation.fieldName,
                      fieldName.hasPrefix("fro_"),
                      let value = annotation.widgetStringValue,
                      !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { continue }
                fieldValues[fieldName] = value.trimmingCharacters(in: .whitespacesAndNewlines)
            }
        }

        // Must have at least one fro_ field to be recognized as a fillable FRO form
        guard !fieldValues.isEmpty else { return nil }

        // Must have aircraftType to be valid
        guard let aircraftType = fieldValues["fro_aircraftType"],
              !aircraftType.isEmpty else { return nil }

        return ImportedJobData(
            aircraftType: aircraftType,
            system: fieldValues["fro_system"] ?? "",
            aircraftSerialNumber: fieldValues["fro_aircraftSerialNumber"],
            nNumber: fieldValues["fro_nNumber"],
            component: fieldValues["fro_component"],
            jobDate: parseDate(fieldValues["fro_jobDate"]),
            taskDescription: fieldValues["fro_taskDescription"],
            tmReferences: fieldValues["fro_tmReferences"],
            toolsText: fieldValues["fro_toolsUsed"],
            consumablesText: fieldValues["fro_consumablesUsed"],
            chemicalsText: fieldValues["fro_chemicalsUsed"],
            partsText: fieldValues["fro_partsUsed"],
            notes: fieldValues["fro_notes"],
            recommendations: fieldValues["fro_recommendations"],
            source: .fillablePDF
        )
    }

    // MARK: - Read-Only PDF Parsing

    /// Extracts data by parsing the text content of the PDF.
    /// Uses section headers as delimiters (TASK DESCRIPTION, TM REFERENCES, etc.).
    private static func parseFromTextContent(document: PDFDocument) throws -> ImportedJobData {
        let fullText = extractFullText(from: document)

        // Verify this looks like an FRO PDF
        guard fullText.contains("FOR REFERENCE ONLY") else {
            throw ImportError.parsingFailed(
                details: "This PDF does not appear to be a ForReferenceOnly job report. The 'FOR REFERENCE ONLY' marker was not found."
            )
        }

        // Extract the title (aircraft type) — appears after the FRO disclaimer
        let aircraftType = extractAircraftType(from: fullText) ?? ""

        // Extract metadata key-value pairs
        let metadata = extractMetadata(from: fullText)

        // Parse sections by headers
        let sections = parseSections(from: fullText)

        let data = ImportedJobData(
            aircraftType: aircraftType,
            system: metadata["System"] ?? "",
            aircraftSerialNumber: metadata["Serial Number"],
            nNumber: metadata["N-Number / Tail"],
            component: metadata["Component"],
            jobDate: parseDate(metadata["Job Date"]),
            taskDescription: sections["TASK DESCRIPTION"],
            tmReferences: sections["TM REFERENCES"],
            toolsText: sections["TOOLS USED"],
            consumablesText: sections["CONSUMABLES"],
            chemicalsText: sections["CHEMICALS"],
            partsText: sections["PARTS USED"],
            notes: sections["NOTES"],
            recommendations: sections["RECOMMENDATIONS"],
            source: .readOnlyPDF
        )

        // Validate at least aircraft type was found
        guard !data.aircraftType.isEmpty else {
            throw ImportError.missingRequiredFields(
                details: "Could not extract Aircraft Type from the PDF."
            )
        }

        return data
    }

    // MARK: - Text Extraction Helpers

    /// Extracts the full text from all pages of a PDFDocument.
    private static func extractFullText(from document: PDFDocument) -> String {
        var text = ""
        for pageIndex in 0..<document.pageCount {
            if let page = document.page(at: pageIndex),
               let pageText = page.string {
                text += pageText + "\n"
            }
        }
        return text
    }

    /// Extracts the aircraft type from the title area of the PDF text.
    /// The title appears after "FOR REFERENCE ONLY" and the subtitle, before the metadata section.
    private static func extractAircraftType(from text: String) -> String? {
        // The FRO disclaimer line is followed by a subtitle, then the aircraft type title
        // Look for content between the FRO marker and the first metadata label
        let lines = text.components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }

        // Find the line after "FOR REFERENCE ONLY" and its subtitle
        var foundFRO = false
        var foundSubtitle = false

        for line in lines {
            if line.contains("FOR REFERENCE ONLY") {
                foundFRO = true
                continue
            }

            if foundFRO && !foundSubtitle {
                // This is the subtitle line — skip it
                if line.contains("not authoritative") || line.contains("personal reference") {
                    foundSubtitle = true
                    continue
                }
                // If no subtitle text, this might be the title already
                foundSubtitle = true
            }

            if foundFRO && foundSubtitle {
                // This should be the aircraft type title
                // Stop if it looks like a metadata label
                if line.contains(":") && (line.hasPrefix("Serial") || line.hasPrefix("N-Number") ||
                    line.hasPrefix("System") || line.hasPrefix("Component") || line.hasPrefix("Job Date")) {
                    break
                }
                // Skip if it's the FRO footer
                if line.contains("Not authoritative maintenance data") { continue }
                // Return the first real content line as the title
                if !line.isEmpty {
                    return line
                }
            }
        }

        return nil
    }

    /// Extracts metadata key-value pairs from the metadata section.
    /// Looks for patterns like "Serial Number: value", "System: value", etc.
    private static func extractMetadata(from text: String) -> [String: String] {
        var metadata: [String: String] = [:]

        let metadataPatterns: [(key: String, pattern: String)] = [
            ("Serial Number", "Serial Number:"),
            ("N-Number / Tail", "N-Number / Tail:"),
            ("N-Number / Tail", "N-Number:"),  // Alternate format
            ("System", "System:"),
            ("Component", "Component:"),
            ("Job Date", "Job Date:")
        ]

        let lines = text.components(separatedBy: .newlines)

        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
            for (key, pattern) in metadataPatterns {
                if trimmed.hasPrefix(pattern) || trimmed.contains(pattern) {
                    // Extract the value after the pattern
                    if let range = trimmed.range(of: pattern) {
                        let value = String(trimmed[range.upperBound...])
                            .trimmingCharacters(in: .whitespacesAndNewlines)
                        if !value.isEmpty && metadata[key] == nil {
                            metadata[key] = value
                        }
                    }
                }
            }
        }

        return metadata
    }

    /// Parses section-delimited text into a dictionary of section name → content.
    /// Uses the PDF's section headers as delimiters.
    private static func parseSections(from text: String) -> [String: String] {
        let sectionHeaders = [
            "TASK DESCRIPTION",
            "TM REFERENCES",
            "TOOLS USED",
            "CONSUMABLES",
            "CHEMICALS",
            "PARTS USED",
            "NOTES",
            "RECOMMENDATIONS"
        ]

        var sections: [String: String] = [:]

        for (index, header) in sectionHeaders.enumerated() {
            guard let headerRange = text.range(of: header) else { continue }

            let contentStart = headerRange.upperBound

            // Find the next section header or end of text
            var contentEnd = text.endIndex
            for nextHeader in sectionHeaders.suffix(from: index + 1) {
                if let nextRange = text.range(of: nextHeader, range: contentStart..<text.endIndex) {
                    contentEnd = nextRange.lowerBound
                    break
                }
            }

            // Also stop at footer markers
            if let footerRange = text.range(of: "FOR REFERENCE ONLY - Not authoritative",
                                            range: contentStart..<contentEnd) {
                contentEnd = footerRange.lowerBound
            }
            // Also stop at the small FRO banner on continuation pages
            if let bannerRange = text.range(of: "FOR REFERENCE ONLY\n",
                                            range: contentStart..<contentEnd) {
                contentEnd = bannerRange.lowerBound
            }

            let content = String(text[contentStart..<contentEnd])
                .trimmingCharacters(in: .whitespacesAndNewlines)

            if !content.isEmpty {
                sections[header] = content
            }
        }

        return sections
    }

    // MARK: - Date Parsing

    /// Attempts to parse a date string in various formats.
    /// Supports: long ("February 7, 2026"), ISO ("2026-02-07"), US ("02/07/2026"), medium ("Feb 7, 2026")
    private static func parseDate(_ string: String?) -> Date? {
        guard let string = string, !string.isEmpty else { return nil }

        let trimmed = string.trimmingCharacters(in: .whitespacesAndNewlines)

        // Try long format: "February 7, 2026"
        let longFormatter = DateFormatter()
        longFormatter.dateStyle = .long
        longFormatter.locale = Locale(identifier: "en_US")
        if let date = longFormatter.date(from: trimmed) { return date }

        // Try medium format: "Feb 7, 2026"
        let mediumFormatter = DateFormatter()
        mediumFormatter.dateStyle = .medium
        mediumFormatter.locale = Locale(identifier: "en_US")
        if let date = mediumFormatter.date(from: trimmed) { return date }

        // Try ISO format: "2026-02-07"
        let isoFormatter = DateFormatter()
        isoFormatter.dateFormat = "yyyy-MM-dd"
        isoFormatter.locale = Locale(identifier: "en_US_POSIX")
        if let date = isoFormatter.date(from: trimmed) { return date }

        // Try US format: "02/07/2026"
        let usFormatter = DateFormatter()
        usFormatter.dateFormat = "MM/dd/yyyy"
        usFormatter.locale = Locale(identifier: "en_US_POSIX")
        if let date = usFormatter.date(from: trimmed) { return date }

        // Try short format: "2/7/26"
        let shortFormatter = DateFormatter()
        shortFormatter.dateFormat = "M/d/yy"
        shortFormatter.locale = Locale(identifier: "en_US_POSIX")
        if let date = shortFormatter.date(from: trimmed) { return date }

        print("ImportService: Could not parse date string '\(trimmed)'")
        return nil
    }
}

import Foundation
import PDFKit
import UIKit

/// Service for generating PDF job reports from job records.
/// Uses UIKit PDF rendering (UIGraphicsPDFRenderer) to create professional
/// job reports with all sections and the mandatory FRO disclaimer.
class PDFService {

    // MARK: - Constants

    private static let pageWidth: CGFloat = 612   // US Letter width in points
    private static let pageHeight: CGFloat = 792  // US Letter height in points
    private static let margin: CGFloat = 50
    private static let contentWidth: CGFloat = pageWidth - 2 * margin

    // Colors
    private static let primaryBlue = UIColor(red: 0.145, green: 0.388, blue: 0.922, alpha: 1.0)
    private static let safetyOrange = UIColor(red: 0.976, green: 0.451, blue: 0.086, alpha: 1.0)
    private static let steelGray = UIColor(red: 0.392, green: 0.455, blue: 0.545, alpha: 1.0)
    private static let darkCharcoal = UIColor(red: 0.118, green: 0.161, blue: 0.231, alpha: 1.0)

    // MARK: - Public API

    /// Generates a PDF data blob for a job record.
    /// - Parameter job: The JobRecord to generate a PDF for
    /// - Returns: PDF data, or nil if generation fails
    static func generatePDF(for job: JobRecord) -> Data? {
        let pageRect = CGRect(x: 0, y: 0, width: pageWidth, height: pageHeight)
        let renderer = UIGraphicsPDFRenderer(bounds: pageRect)

        let data = renderer.pdfData { context in
            var currentY: CGFloat = 0

            // Start first page
            context.beginPage()
            currentY = margin

            // === HEADER: Bold FRO Disclaimer ===
            currentY = drawFRODisclaimer(at: currentY, in: context)
            currentY += 20

            // === TITLE: Aircraft Type ===
            currentY = drawTitle(job.aircraftType, at: currentY, in: context)
            currentY += 8

            // === Metadata Section ===
            currentY = drawMetadataSection(for: job, at: currentY, in: context)
            currentY += 16

            // === Task Description ===
            if let desc = job.taskDescription, !desc.isEmpty {
                currentY = checkPageBreak(currentY: currentY, neededHeight: 80, context: context)
                currentY = drawSectionHeader("TASK DESCRIPTION", at: currentY, in: context)
                currentY = drawBodyText(desc, at: currentY, in: context)
                currentY += 12
            }

            // === TM References ===
            if let tm = job.tmReferences, !tm.isEmpty {
                currentY = checkPageBreak(currentY: currentY, neededHeight: 60, context: context)
                currentY = drawSectionHeader("TM REFERENCES", at: currentY, in: context)
                currentY = drawMonoText(tm, at: currentY, in: context)
                currentY += 12
            }

            // === Tools Used ===
            let tools = sortedTools(from: job)
            if !tools.isEmpty {
                currentY = checkPageBreak(currentY: currentY, neededHeight: 60, context: context)
                currentY = drawSectionHeader("TOOLS USED", at: currentY, in: context)
                currentY = drawToolsList(tools, at: currentY, in: context)
                currentY += 12
            }

            // === Consumables ===
            let consumables = sortedConsumables(from: job)
            if !consumables.isEmpty {
                currentY = checkPageBreak(currentY: currentY, neededHeight: 60, context: context)
                currentY = drawSectionHeader("CONSUMABLES", at: currentY, in: context)
                currentY = drawConsumablesList(consumables, at: currentY, in: context)
                currentY += 12
            }

            // === Chemicals ===
            let chemicals = sortedChemicals(from: job)
            if !chemicals.isEmpty {
                currentY = checkPageBreak(currentY: currentY, neededHeight: 60, context: context)
                currentY = drawSectionHeader("CHEMICALS", at: currentY, in: context)
                currentY = drawChemicalsList(chemicals, at: currentY, in: context)
                currentY += 12
            }

            // === Parts (Feature #141) ===
            let parts = sortedParts(from: job)
            if !parts.isEmpty {
                currentY = checkPageBreak(currentY: currentY, neededHeight: 60, context: context)
                currentY = drawSectionHeader("PARTS USED", at: currentY, in: context)
                currentY = drawPartsList(parts, at: currentY, in: context)
                currentY += 12
            }

            // === Notes (Feature #129 - display as numbered line items in PDF) ===
            if let notes = job.notes, !notes.isEmpty {
                currentY = checkPageBreak(currentY: currentY, neededHeight: 60, context: context)
                currentY = drawSectionHeader("NOTES", at: currentY, in: context)
                currentY = drawNumberedNotes(notes, at: currentY, in: context)
                currentY += 12
            }

            // === Recommendations ===
            if let recs = job.recommendations, !recs.isEmpty {
                currentY = checkPageBreak(currentY: currentY, neededHeight: 60, context: context)
                currentY = drawSectionHeader("RECOMMENDATIONS", at: currentY, in: context)
                currentY = drawBodyText(recs, at: currentY, in: context)
                currentY += 12
            }

            // === Footer disclaimer on every page is handled by drawFooter in checkPageBreak ===
            drawFooter(in: context)
        }

        return data
    }

    /// Generates a PDF and returns a temporary file URL for sharing.
    /// - Parameter job: The JobRecord to generate a PDF for
    /// - Returns: URL to the temporary PDF file, or nil if generation fails
    /// Feature #174: PDF filename format is FRO_[AircraftType]_[System]_[Component]_[YYYYMMDD].pdf
    static func generatePDFFile(for job: JobRecord) -> URL? {
        guard let data = generatePDF(for: job) else { return nil }

        // Feature #174: Build descriptive filename with all job metadata
        // Format: FRO_[AircraftType]_[System]_[Component]_[YYYYMMDD].pdf
        let fileName = generateDescriptiveFilename(for: job)

        let tempDir = FileManager.default.temporaryDirectory
        let fileURL = tempDir.appendingPathComponent(fileName)

        do {
            try data.write(to: fileURL)
            return fileURL
        } catch {
            print("PDFService: Failed to write PDF file - \(error)")
            return nil
        }
    }

    /// Feature #174: Generates a descriptive PDF filename from job metadata.
    /// Format: FRO_[AircraftType]_[System]_[Component]_[YYYYMMDD].pdf
    /// All parts are separated by underscores, spaces replaced with underscores.
    /// Special characters that are invalid in filenames are removed.
    /// Feature #177: Long field values are truncated to keep filenames reasonable.
    private static func generateDescriptiveFilename(for job: JobRecord) -> String {
        // Feature #177: Maximum character lengths for each field segment
        // These limits keep total filename length reasonable across all platforms
        // (macOS: 255 chars, iOS: 255 chars, Windows: 260 chars including path)
        let maxAircraftTypeLength = 30
        let maxSystemLength = 25
        let maxComponentLength = 30

        // Sanitize each component: replace spaces with underscores, remove invalid filename characters
        // Feature #176: Gracefully handle empty and whitespace-only fields
        func sanitize(_ text: String?) -> String {
            guard let text = text else { return "" }
            // Feature #176: Trim whitespace first to treat whitespace-only fields as empty
            let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { return "" }
            // Replace spaces with underscores
            var result = trimmed.replacingOccurrences(of: " ", with: "_")
            // Feature #175: Remove characters that are invalid in filenames: / \ : * ? " < > |
            // This ensures generated filenames are valid for all common filesystems
            let invalidChars = CharacterSet(charactersIn: "/\\:*?\"<>|")
            result = result.components(separatedBy: invalidChars).joined()
            // Feature #176: After removing invalid chars, check again for empty result
            // This handles cases like a field containing only invalid characters
            return result.isEmpty ? "" : result
        }

        // Feature #177: Truncate text to max length, preferring word boundaries
        // If possible, truncates at the last underscore (word boundary) before maxLength
        // Falls back to hard truncation if no word boundary exists
        func truncate(_ text: String, maxLength: Int) -> String {
            guard text.count > maxLength else { return text }

            // Try to find a word boundary (underscore) to truncate at
            let truncatedRange = text.prefix(maxLength)
            if let lastUnderscoreIndex = truncatedRange.lastIndex(of: "_") {
                // Only use word boundary if it's not too early (at least 60% of max length)
                let boundaryPosition = truncatedRange.distance(from: truncatedRange.startIndex, to: lastUnderscoreIndex)
                if boundaryPosition >= maxLength * 60 / 100 {
                    return String(truncatedRange[..<lastUnderscoreIndex])
                }
            }

            // Hard truncate if no good word boundary found
            return String(truncatedRange)
        }

        // Build filename components
        var components: [String] = ["FRO"]

        // Add AircraftType (required field, but use "Job" as fallback)
        // Feature #177: Truncate to maxAircraftTypeLength
        let aircraftType = truncate(sanitize(job.aircraftType), maxLength: maxAircraftTypeLength)
        components.append(aircraftType.isEmpty ? "Job" : aircraftType)

        // Add System (required field, use "Unknown" as fallback)
        // Feature #177: Truncate to maxSystemLength
        let system = truncate(sanitize(job.system), maxLength: maxSystemLength)
        if !system.isEmpty {
            components.append(system)
        }

        // Add Component (optional field, include if present)
        // Feature #177: Truncate to maxComponentLength
        let component = truncate(sanitize(job.component), maxLength: maxComponentLength)
        if !component.isEmpty {
            components.append(component)
        }

        // Add date in YYYYMMDD format (no dashes or slashes)
        // Feature #177: Date is never truncated - always 8 characters
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyyyMMdd"
        let dateStr = dateFormatter.string(from: job.jobDate)
        components.append(dateStr)

        // Join with underscores and add .pdf extension
        return components.joined(separator: "_") + ".pdf"
    }

    // MARK: - Fillable PDF Generation

    /// Describes where a form field should be placed in the PDF.
    /// Uses UIKit coordinates (top-left origin) — converted to PDF coordinates when adding annotations.
    private struct FieldPosition {
        let fieldName: String        // e.g., "fro_aircraftType"
        let pageIndex: Int           // which page (0-based)
        let rect: CGRect             // position in UIKit coordinates (top-left origin)
        let isMultiline: Bool        // single-line vs multiline text widget
        let fontSize: CGFloat        // font size for the field
    }

    /// Generates a fillable PDF with AcroForm text fields for all job record sections.
    /// When `job` is provided, pre-fills the fields with existing data.
    /// When `job` is nil, generates a blank fillable template.
    /// - Parameter job: Optional JobRecord to pre-fill fields from
    /// - Returns: PDF data with AcroForm annotations, or nil if generation fails
    static func generateFillablePDF(for job: JobRecord? = nil) -> Data? {
        let pageRect = CGRect(x: 0, y: 0, width: pageWidth, height: pageHeight)
        let renderer = UIGraphicsPDFRenderer(bounds: pageRect)

        // Track field positions while drawing the layout
        var fieldPositions: [FieldPosition] = []
        var currentPageIndex = 0

        let baseData = renderer.pdfData { context in
            var currentY: CGFloat = 0

            // === PAGE 1 ===
            context.beginPage()
            currentPageIndex = 0
            currentY = margin

            // FRO Disclaimer (same as read-only)
            currentY = drawFRODisclaimer(at: currentY, in: context)
            currentY += 4

            // Fillable form instruction
            let instructionAttrs: [NSAttributedString.Key: Any] = [
                .font: UIFont.italicSystemFont(ofSize: 9),
                .foregroundColor: steelGray
            ]
            let instructionText = job == nil
                ? "Fillable Form — Open in Adobe Acrobat or Preview to type in the fields below, then import into FRO app."
                : "Fillable Form — Open in Adobe Acrobat or Preview to edit the fields below."
            let instructionSize = instructionText.size(withAttributes: instructionAttrs)
            let instructionX = margin + (contentWidth - instructionSize.width) / 2
            instructionText.draw(at: CGPoint(x: max(instructionX, margin), y: currentY), withAttributes: instructionAttrs)
            currentY += 18

            // Title label + field
            let titleLabelAttrs: [NSAttributedString.Key: Any] = [
                .font: UIFont.boldSystemFont(ofSize: 12),
                .foregroundColor: primaryBlue
            ]
            "AIRCRAFT TYPE".draw(at: CGPoint(x: margin, y: currentY), withAttributes: titleLabelAttrs)
            currentY += 18
            let titleFieldRect = CGRect(x: margin, y: currentY, width: contentWidth, height: 28)
            drawFieldBox(titleFieldRect, in: context)
            fieldPositions.append(FieldPosition(fieldName: "fro_aircraftType", pageIndex: currentPageIndex, rect: titleFieldRect, isMultiline: false, fontSize: 16))
            currentY += 36

            // === Metadata Section ===
            let metadataLabelWidth: CGFloat = 130
            let metadataFieldWidth: CGFloat = contentWidth - metadataLabelWidth - 10
            let metadataRowHeight: CGFloat = 24
            let metadataFieldHeight: CGFloat = 20

            let labelAttrs: [NSAttributedString.Key: Any] = [
                .font: UIFont.boldSystemFont(ofSize: 10),
                .foregroundColor: steelGray
            ]

            // Draw light background box for metadata
            let metadataBoxHeight: CGFloat = 5 * metadataRowHeight + 16
            let metadataBoxRect = CGRect(x: margin, y: currentY, width: contentWidth, height: metadataBoxHeight)
            UIColor(red: 0.973, green: 0.98, blue: 0.988, alpha: 1.0).setFill()
            UIBezierPath(roundedRect: metadataBoxRect, cornerRadius: 4).fill()

            currentY += 8

            let metadataFields: [(label: String, fieldName: String)] = [
                ("Serial Number:", "fro_aircraftSerialNumber"),
                ("N-Number / Tail:", "fro_nNumber"),
                ("System:", "fro_system"),
                ("Component:", "fro_component"),
                ("Job Date:", "fro_jobDate")
            ]

            for (label, fieldName) in metadataFields {
                label.draw(at: CGPoint(x: margin + 10, y: currentY + 2), withAttributes: labelAttrs)
                let fieldRect = CGRect(x: margin + metadataLabelWidth, y: currentY, width: metadataFieldWidth, height: metadataFieldHeight)
                drawFieldBox(fieldRect, in: context)
                fieldPositions.append(FieldPosition(fieldName: fieldName, pageIndex: currentPageIndex, rect: fieldRect, isMultiline: false, fontSize: 11))
                currentY += metadataRowHeight
            }
            currentY += 16

            // === Section fields ===
            let sections: [(header: String, fieldName: String, height: CGFloat)] = [
                ("TASK DESCRIPTION", "fro_taskDescription", 100),
                ("TM REFERENCES", "fro_tmReferences", 60),
                ("TOOLS USED", "fro_toolsUsed", 70),
                ("CONSUMABLES", "fro_consumablesUsed", 50),
                ("CHEMICALS", "fro_chemicalsUsed", 50),
                ("PARTS USED", "fro_partsUsed", 70),
            ]

            for (header, fieldName, fieldHeight) in sections {
                // Check if we need a new page
                if currentY + fieldHeight + 24 > pageHeight - margin - 30 {
                    drawFooter(in: context)
                    context.beginPage()
                    currentPageIndex += 1
                    currentY = margin
                    let bannerY = drawFROBannerSmall(at: currentY, in: context)
                    currentY = bannerY + 10
                }

                currentY = drawSectionHeader(header, at: currentY, in: context)
                let fieldRect = CGRect(x: margin, y: currentY, width: contentWidth, height: fieldHeight)
                drawFieldBox(fieldRect, in: context)
                fieldPositions.append(FieldPosition(fieldName: fieldName, pageIndex: currentPageIndex, rect: fieldRect, isMultiline: true, fontSize: 10))
                currentY += fieldHeight + 10
            }

            // Notes and Recommendations on page 2 if needed
            let remainingSections: [(header: String, fieldName: String, height: CGFloat)] = [
                ("NOTES", "fro_notes", 80),
                ("RECOMMENDATIONS", "fro_recommendations", 70),
            ]

            for (header, fieldName, fieldHeight) in remainingSections {
                if currentY + fieldHeight + 24 > pageHeight - margin - 30 {
                    drawFooter(in: context)
                    context.beginPage()
                    currentPageIndex += 1
                    currentY = margin
                    let bannerY = drawFROBannerSmall(at: currentY, in: context)
                    currentY = bannerY + 10
                }

                currentY = drawSectionHeader(header, at: currentY, in: context)
                let fieldRect = CGRect(x: margin, y: currentY, width: contentWidth, height: fieldHeight)
                drawFieldBox(fieldRect, in: context)
                fieldPositions.append(FieldPosition(fieldName: fieldName, pageIndex: currentPageIndex, rect: fieldRect, isMultiline: true, fontSize: 10))
                currentY += fieldHeight + 10
            }

            drawFooter(in: context)
        }

        // Load the rendered PDF into PDFDocument and add form field annotations
        guard let document = PDFDocument(data: baseData) else {
            print("PDFService: Failed to create PDFDocument from rendered fillable layout")
            return nil
        }

        addFormFieldAnnotations(to: document, positions: fieldPositions, prefillFrom: job)

        guard let finalData = document.dataRepresentation() else {
            print("PDFService: Failed to extract data from annotated PDFDocument")
            return nil
        }

        return finalData
    }

    /// Generates a fillable PDF and returns a temporary file URL for sharing.
    /// - Parameter job: Optional JobRecord to pre-fill fields from (nil = blank template)
    /// - Returns: URL to the temporary PDF file, or nil if generation fails
    static func generateFillablePDFFile(for job: JobRecord? = nil) -> URL? {
        guard let data = generateFillablePDF(for: job) else { return nil }

        let fileName: String
        if let job = job {
            fileName = "FRO_Fillable_\(generateDescriptiveFilename(for: job))"
        } else {
            fileName = "FRO_Blank_Template.pdf"
        }

        let tempDir = FileManager.default.temporaryDirectory
        let fileURL = tempDir.appendingPathComponent(fileName)

        do {
            try data.write(to: fileURL)
            return fileURL
        } catch {
            print("PDFService: Failed to write fillable PDF file - \(error)")
            return nil
        }
    }

    // MARK: - Fillable PDF Helpers

    /// Draws a light-bordered field box placeholder for form fields.
    /// These are drawn in the base PDF layer (not as annotations) so they remain
    /// visible even in PDF viewers that don't render AcroForm annotations.
    private static func drawFieldBox(_ rect: CGRect, in context: UIGraphicsPDFRendererContext) {
        // Light blue-tinted background to visually indicate fillable areas
        UIColor(red: 0.95, green: 0.97, blue: 1.0, alpha: 1.0).setFill()
        UIBezierPath(roundedRect: rect, cornerRadius: 2).fill()

        // Subtle border
        UIColor(red: 0.75, green: 0.8, blue: 0.85, alpha: 1.0).setStroke()
        let borderPath = UIBezierPath(roundedRect: rect, cornerRadius: 2)
        borderPath.lineWidth = 0.5
        borderPath.stroke()
    }

    /// Adds PDFAnnotation widgets to a PDFDocument at the specified positions.
    private static func addFormFieldAnnotations(
        to document: PDFDocument,
        positions: [FieldPosition],
        prefillFrom job: JobRecord?
    ) {
        for position in positions {
            guard position.pageIndex < document.pageCount,
                  let page = document.page(at: position.pageIndex) else { continue }

            // Convert from UIKit (top-left origin) to PDF (bottom-left origin) coordinates
            let flippedY = pageHeight - position.rect.origin.y - position.rect.height
            let pdfRect = CGRect(
                x: position.rect.origin.x,
                y: flippedY,
                width: position.rect.width,
                height: position.rect.height
            )

            let annotation = PDFAnnotation(bounds: pdfRect, forType: .widget, withProperties: nil)
            annotation.widgetFieldType = .text
            annotation.fieldName = position.fieldName
            annotation.isMultiline = position.isMultiline
            annotation.font = UIFont.systemFont(ofSize: position.fontSize)
            annotation.fontColor = darkCharcoal
            // Use clear background to avoid iOS PDFKit rendering bug where
            // opaque annotation backgrounds cover the underlying PDF content,
            // causing a blank/white screen appearance in Quick Look and Files.app.
            // The field boxes are already drawn in the base PDF by drawFieldBox().
            annotation.backgroundColor = UIColor.clear

            // Thin border so the field boundary is still visible when editing
            let border = PDFBorder()
            border.lineWidth = 0.5
            annotation.border = border

            // Pre-fill from job if available
            if let job = job, let value = fillableFieldValue(for: position.fieldName, from: job) {
                annotation.widgetStringValue = value
            }

            page.addAnnotation(annotation)
        }
    }

    /// Returns the value for a fillable form field from a JobRecord.
    private static func fillableFieldValue(for fieldName: String, from job: JobRecord) -> String? {
        switch fieldName {
        case "fro_aircraftType":
            return job.aircraftType
        case "fro_aircraftSerialNumber":
            return job.aircraftSerialNumber
        case "fro_nNumber":
            return job.nNumber
        case "fro_system":
            return job.system
        case "fro_component":
            return job.component
        case "fro_jobDate":
            let formatter = DateFormatter()
            formatter.dateStyle = .long
            return formatter.string(from: job.jobDate)
        case "fro_taskDescription":
            return job.taskDescription
        case "fro_tmReferences":
            return job.tmReferences
        case "fro_toolsUsed":
            // Convert tools to text representation
            guard let toolSet = job.tools, !toolSet.isEmpty else { return nil }
            return Array(toolSet)
                .sortedBySize()
                .map { tool -> String in
                    let name = tool.name
                    let ownership = tool.ownershipType
                    if ownership == "borrowed", let from = tool.borrowedFrom, !from.isEmpty {
                        return "\(name) (borrowed from \(from))"
                    }
                    return "\(name) (\(ownership))"
                }
                .joined(separator: "\n")
        case "fro_consumablesUsed":
            guard let set = job.consumables, !set.isEmpty else { return nil }
            return set.sorted { $0.name < $1.name }
                .map { item -> String in
                    let name = item.name
                    var details: [String] = []
                    if !item.category.isEmpty { details.append(item.category) }
                    if let size = item.size, !size.isEmpty { details.append(size) }
                    return details.isEmpty ? name : "\(name) (\(details.joined(separator: ", ")))"
                }
                .joined(separator: "\n")
        case "fro_chemicalsUsed":
            guard let set = job.chemicals, !set.isEmpty else { return nil }
            return set.sorted { $0.name < $1.name }
                .map { item -> String in
                    let name = item.name
                    var details: [String] = []
                    if !item.category.isEmpty { details.append(item.category) }
                    if let size = item.size, !size.isEmpty { details.append(size) }
                    return details.isEmpty ? name : "\(name) (\(details.joined(separator: ", ")))"
                }
                .joined(separator: "\n")
        case "fro_partsUsed":
            guard let set = job.parts, !set.isEmpty else { return nil }
            return set.sorted { $0.nomenclature < $1.nomenclature }
                .map { part -> String in
                    let name = part.nomenclature
                    var details: [String] = []
                    if !part.partNumber.isEmpty { details.append("P/N: \(part.partNumber)") }
                    if part.quantity > 1 { details.append("Qty: \(part.quantity)") }
                    if let nsn = part.nsn, !nsn.isEmpty { details.append("NSN: \(nsn)") }
                    return details.isEmpty ? name : "\(name) (\(details.joined(separator: ", ")))"
                }
                .joined(separator: "\n")
        case "fro_notes":
            return job.notes
        case "fro_recommendations":
            return job.recommendations
        default:
            return nil
        }
    }

    // MARK: - Drawing Helpers

    /// Draws the bold "FOR REFERENCE ONLY" disclaimer at the top of the page
    private static func drawFRODisclaimer(at y: CGFloat, in context: UIGraphicsPDFRendererContext) -> CGFloat {
        let disclaimerText = "FOR REFERENCE ONLY"
        let subtitleText = "This document is not authoritative maintenance data. It is a personal reference only."

        // Draw orange background box
        let boxRect = CGRect(x: margin, y: y, width: contentWidth, height: 52)
        let bgColor = safetyOrange.withAlphaComponent(0.12)
        bgColor.setFill()
        UIBezierPath(roundedRect: boxRect, cornerRadius: 6).fill()

        // Draw orange border
        safetyOrange.setStroke()
        let borderPath = UIBezierPath(roundedRect: boxRect, cornerRadius: 6)
        borderPath.lineWidth = 2
        borderPath.stroke()

        // Draw bold disclaimer text
        let disclaimerAttrs: [NSAttributedString.Key: Any] = [
            .font: UIFont.boldSystemFont(ofSize: 18),
            .foregroundColor: safetyOrange
        ]
        let disclaimerSize = disclaimerText.size(withAttributes: disclaimerAttrs)
        let disclaimerX = margin + (contentWidth - disclaimerSize.width) / 2
        disclaimerText.draw(at: CGPoint(x: disclaimerX, y: y + 6), withAttributes: disclaimerAttrs)

        // Draw subtitle
        let subtitleAttrs: [NSAttributedString.Key: Any] = [
            .font: UIFont.systemFont(ofSize: 9),
            .foregroundColor: steelGray
        ]
        let subtitleSize = subtitleText.size(withAttributes: subtitleAttrs)
        let subtitleX = margin + (contentWidth - subtitleSize.width) / 2
        subtitleText.draw(at: CGPoint(x: subtitleX, y: y + 30), withAttributes: subtitleAttrs)

        return y + 52
    }

    /// Draws the main title (aircraft type)
    private static func drawTitle(_ text: String, at y: CGFloat, in context: UIGraphicsPDFRendererContext) -> CGFloat {
        let attrs: [NSAttributedString.Key: Any] = [
            .font: UIFont.boldSystemFont(ofSize: 22),
            .foregroundColor: darkCharcoal
        ]
        let rect = CGRect(x: margin, y: y, width: contentWidth, height: 200)
        let boundingRect = text.boundingRect(with: CGSize(width: contentWidth, height: 200),
                                              options: .usesLineFragmentOrigin,
                                              attributes: attrs,
                                              context: nil)
        text.draw(in: rect, withAttributes: attrs)
        return y + boundingRect.height
    }

    /// Draws the metadata section (serial, N-number, system, component, date)
    private static func drawMetadataSection(for job: JobRecord, at y: CGFloat, in context: UIGraphicsPDFRendererContext) -> CGFloat {
        var currentY = y

        // Draw a light gray background box
        var metadataItems: [(String, String)] = []

        if let serial = job.aircraftSerialNumber, !serial.isEmpty {
            metadataItems.append(("Serial Number", serial))
        }
        if let nNum = job.nNumber, !nNum.isEmpty {
            metadataItems.append(("N-Number / Tail", nNum))
        }
        if !job.system.isEmpty {
            metadataItems.append(("System", job.system))
        }
        if let comp = job.component, !comp.isEmpty {
            metadataItems.append(("Component", comp))
        }
        do {
            let formatter = DateFormatter()
            formatter.dateStyle = .long
            metadataItems.append(("Job Date", formatter.string(from: job.jobDate)))
        }

        if metadataItems.isEmpty { return currentY }

        let rowHeight: CGFloat = 18
        let boxHeight = CGFloat(metadataItems.count) * rowHeight + 16
        let boxRect = CGRect(x: margin, y: currentY, width: contentWidth, height: boxHeight)
        UIColor(red: 0.973, green: 0.98, blue: 0.988, alpha: 1.0).setFill()
        UIBezierPath(roundedRect: boxRect, cornerRadius: 4).fill()

        currentY += 8
        let labelAttrs: [NSAttributedString.Key: Any] = [
            .font: UIFont.boldSystemFont(ofSize: 10),
            .foregroundColor: steelGray
        ]
        let valueAttrs: [NSAttributedString.Key: Any] = [
            .font: UIFont.systemFont(ofSize: 11),
            .foregroundColor: darkCharcoal
        ]

        for (label, value) in metadataItems {
            "\(label):".draw(at: CGPoint(x: margin + 10, y: currentY), withAttributes: labelAttrs)
            value.draw(at: CGPoint(x: margin + 130, y: currentY), withAttributes: valueAttrs)
            currentY += rowHeight
        }

        return currentY + 8
    }

    /// Draws a section header with underline
    private static func drawSectionHeader(_ text: String, at y: CGFloat, in context: UIGraphicsPDFRendererContext) -> CGFloat {
        let attrs: [NSAttributedString.Key: Any] = [
            .font: UIFont.boldSystemFont(ofSize: 12),
            .foregroundColor: primaryBlue
        ]
        text.draw(at: CGPoint(x: margin, y: y), withAttributes: attrs)

        // Underline
        let lineY = y + 16
        primaryBlue.withAlphaComponent(0.3).setStroke()
        let path = UIBezierPath()
        path.move(to: CGPoint(x: margin, y: lineY))
        path.addLine(to: CGPoint(x: margin + contentWidth, y: lineY))
        path.lineWidth = 0.5
        path.stroke()

        return lineY + 6
    }

    /// Draws body text with word wrapping
    private static func drawBodyText(_ text: String, at y: CGFloat, in context: UIGraphicsPDFRendererContext) -> CGFloat {
        let attrs: [NSAttributedString.Key: Any] = [
            .font: UIFont.systemFont(ofSize: 11),
            .foregroundColor: darkCharcoal
        ]
        let maxHeight: CGFloat = pageHeight - margin - 40 // Leave room for footer
        let availableHeight = maxHeight - y
        let rect = CGRect(x: margin, y: y, width: contentWidth, height: max(availableHeight, 100))
        let boundingRect = text.boundingRect(with: CGSize(width: contentWidth, height: 2000),
                                              options: .usesLineFragmentOrigin,
                                              attributes: attrs,
                                              context: nil)
        text.draw(in: rect, withAttributes: attrs)
        return y + min(boundingRect.height, availableHeight)
    }

    /// Draws monospaced text (for TM references)
    private static func drawMonoText(_ text: String, at y: CGFloat, in context: UIGraphicsPDFRendererContext) -> CGFloat {
        let attrs: [NSAttributedString.Key: Any] = [
            .font: UIFont.monospacedSystemFont(ofSize: 10, weight: .regular),
            .foregroundColor: darkCharcoal
        ]
        let rect = CGRect(x: margin, y: y, width: contentWidth, height: 500)
        let boundingRect = text.boundingRect(with: CGSize(width: contentWidth, height: 500),
                                              options: .usesLineFragmentOrigin,
                                              attributes: attrs,
                                              context: nil)
        text.draw(in: rect, withAttributes: attrs)
        return y + boundingRect.height
    }

    /// Draws notes as numbered line items (Feature #129)
    /// Each line break in the notes field creates a new numbered item.
    /// Empty lines are filtered out for cleaner formatting.
    private static func drawNumberedNotes(_ text: String, at y: CGFloat, in context: UIGraphicsPDFRendererContext) -> CGFloat {
        var currentY = y

        // Split by newlines and filter out empty/whitespace-only lines
        let lines = text.components(separatedBy: .newlines)
            .filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty }

        // If no valid lines after filtering, draw a simple message
        if lines.isEmpty {
            let emptyAttrs: [NSAttributedString.Key: Any] = [
                .font: UIFont.italicSystemFont(ofSize: 11),
                .foregroundColor: steelGray
            ]
            "No notes recorded".draw(at: CGPoint(x: margin, y: currentY), withAttributes: emptyAttrs)
            return currentY + 16
        }

        // Number attributes - bold blue numbers for visual hierarchy
        let numberAttrs: [NSAttributedString.Key: Any] = [
            .font: UIFont.boldSystemFont(ofSize: 11),
            .foregroundColor: primaryBlue
        ]

        // Text attributes
        let textAttrs: [NSAttributedString.Key: Any] = [
            .font: UIFont.systemFont(ofSize: 11),
            .foregroundColor: darkCharcoal
        ]

        // Width for number column (e.g., "1. ", "10. ", etc.)
        let numberWidth: CGFloat = 24
        let textIndent: CGFloat = margin + numberWidth + 6
        let textContentWidth: CGFloat = contentWidth - numberWidth - 6

        for (index, line) in lines.enumerated() {
            // Check for page break before each item
            currentY = checkPageBreak(currentY: currentY, neededHeight: 20, context: context)

            // Draw the number
            let numberStr = "\(index + 1)."
            numberStr.draw(at: CGPoint(x: margin, y: currentY), withAttributes: numberAttrs)

            // Calculate text height for multi-line wrapping
            let textRect = CGRect(x: textIndent, y: currentY, width: textContentWidth, height: 500)
            let boundingRect = line.boundingRect(
                with: CGSize(width: textContentWidth, height: 500),
                options: .usesLineFragmentOrigin,
                attributes: textAttrs,
                context: nil
            )

            // Draw the note text
            line.draw(in: textRect, withAttributes: textAttrs)

            // Move Y position down by the height of this item plus spacing
            currentY += max(boundingRect.height, 16) + 6
        }

        return currentY
    }

    /// Draws the tools list grouped by ownership, with Tool Sets grouped together (Feature #152)
    private static func drawToolsList(_ tools: [Tool], at y: CGFloat, in context: UIGraphicsPDFRendererContext) -> CGFloat {
        var currentY = y

        let personalTools = tools.filter { $0.ownershipType == "personal" }
        let shopTools = tools.filter { $0.ownershipType == "shop" }
        let borrowedTools = tools.filter { $0.ownershipType == "borrowed" }
        let importedTools = tools.filter { $0.ownershipType == "imported" }

        if !personalTools.isEmpty {
            currentY = drawToolGroupWithSets("Personal Tools", tools: personalTools, at: currentY, in: context)
        }
        if !shopTools.isEmpty {
            currentY = drawToolGroupWithSets("Shop Tools", tools: shopTools, at: currentY, in: context)
        }
        if !borrowedTools.isEmpty {
            currentY = drawToolGroupWithSets("Borrowed Tools", tools: borrowedTools, at: currentY, in: context)
        }
        if !importedTools.isEmpty {
            currentY = drawToolGroupWithSets("Imported Tools", tools: importedTools, at: currentY, in: context)
        }

        return currentY
    }

    /// Draws a tool ownership group with Tool Sets and Tool Kits nested (Feature #152, #153)
    /// Groups tools by their Tool Set, then by Tool Kit, showing names as headers with tools indented below.
    /// Tools not in any set or kit are shown as "Individual Tools".
    private static func drawToolGroupWithSets(_ groupName: String, tools: [Tool], at y: CGFloat, in context: UIGraphicsPDFRendererContext) -> CGFloat {
        var currentY = y

        // Draw ownership header (e.g., "Personal Tools")
        let groupAttrs: [NSAttributedString.Key: Any] = [
            .font: UIFont.boldSystemFont(ofSize: 10),
            .foregroundColor: steelGray
        ]
        groupName.draw(at: CGPoint(x: margin + 10, y: currentY), withAttributes: groupAttrs)
        currentY += 16

        // Track which tools have been displayed (to avoid duplicates)
        var displayedToolIDs: Set<UUID> = []

        // Group tools by their Tool Set
        var toolsBySet: [String: [Tool]] = [:]  // Set name -> tools

        for tool in tools {
            if let toolSet = tool.group, !toolSet.name.isEmpty {
                toolsBySet[toolSet.name, default: []].append(tool)
            }
        }

        // Draw tools organized by Tool Set (Feature #152)
        let sortedSetNames = toolsBySet.keys.sorted()
        for setName in sortedSetNames {
            guard let setTools = toolsBySet[setName] else { continue }
            currentY = drawToolSetSection(setName, tools: setTools.sortedBySize(), at: currentY, in: context)
            // Mark these tools as displayed
            for tool in setTools {
                displayedToolIDs.insert(tool.id)
            }
        }

        // Feature #153: Group remaining tools by their Tool Kit
        var toolsByKit: [String: [Tool]] = [:]  // Kit name -> tools
        var ungroupedTools: [Tool] = []

        for tool in tools {
            // Skip tools already shown in a Tool Set
            if displayedToolIDs.contains(tool.id) { continue }

            // Check if tool belongs to any Tool Kit
            if let toolKits = tool.toolKits, !toolKits.isEmpty {
                let kitsWithNames = toolKits.filter { !$0.name.isEmpty }
                    .map { ($0.name, $0) }

                if let firstKit = kitsWithNames.sorted(by: { $0.0 < $1.0 }).first {
                    // Add to the first kit alphabetically (tool can only appear once)
                    toolsByKit[firstKit.0, default: []].append(tool)
                } else {
                    ungroupedTools.append(tool)
                }
            } else {
                ungroupedTools.append(tool)
            }
        }

        // Draw tools organized by Tool Kit (Feature #153)
        let sortedKitNames = toolsByKit.keys.sorted()
        for kitName in sortedKitNames {
            guard let kitTools = toolsByKit[kitName] else { continue }
            currentY = drawToolKitSection(kitName, tools: kitTools.sortedBySize(), at: currentY, in: context)
        }

        // Draw ungrouped tools at the end (not in any Set or Kit)
        if !ungroupedTools.isEmpty {
            currentY = drawUngroupedTools(ungroupedTools.sortedBySize(), at: currentY, in: context)
        }

        return currentY
    }

    /// Draws a Tool Set section with header and indented tools (Feature #152)
    private static func drawToolSetSection(_ setName: String, tools: [Tool], at y: CGFloat, in context: UIGraphicsPDFRendererContext) -> CGFloat {
        var currentY = y

        // Check for page break before drawing set header
        currentY = checkPageBreak(currentY: currentY, neededHeight: 36, context: context)

        // Draw Tool Set header - indented and styled distinctly
        // Feature #155: Headers use larger font (11pt) than tool items (10pt) for clear visual hierarchy
        let setHeaderAttrs: [NSAttributedString.Key: Any] = [
            .font: UIFont.boldSystemFont(ofSize: 11),
            .foregroundColor: primaryBlue
        ]
        let setHeader = "▸ \(setName)"
        setHeader.draw(at: CGPoint(x: margin + 20, y: currentY), withAttributes: setHeaderAttrs)
        currentY += 14

        // Draw tools within the set - further indented
        let bulletAttrs: [NSAttributedString.Key: Any] = [
            .font: UIFont.systemFont(ofSize: 10),
            .foregroundColor: darkCharcoal
        ]
        let detailAttrs: [NSAttributedString.Key: Any] = [
            .font: UIFont.italicSystemFont(ofSize: 9),
            .foregroundColor: steelGray
        ]

        for tool in tools {
            currentY = checkPageBreak(currentY: currentY, neededHeight: 20, context: context)
            let displayName = toolDisplayName(for: tool)
            let bullet = "  \u{2022}  \(displayName)"
            bullet.draw(at: CGPoint(x: margin + 30, y: currentY), withAttributes: bulletAttrs)

            // Show borrowed info if applicable
            if tool.ownershipType == "borrowed", let from = tool.borrowedFrom, !from.isEmpty {
                let trailingX = margin + 30 + bullet.size(withAttributes: bulletAttrs).width
                let detail = "  (from: \(from))"
                detail.draw(at: CGPoint(x: trailingX, y: currentY + 1), withAttributes: detailAttrs)
            }

            currentY += 14
        }

        return currentY + 2  // Small spacing after set
    }

    /// Draws a Tool Kit section with header and indented tools (Feature #153)
    /// Tool Kits use forest green color to distinguish from Tool Sets (which use blue).
    private static func drawToolKitSection(_ kitName: String, tools: [Tool], at y: CGFloat, in context: UIGraphicsPDFRendererContext) -> CGFloat {
        var currentY = y

        // Check for page break before drawing kit header
        currentY = checkPageBreak(currentY: currentY, neededHeight: 36, context: context)

        // Tool Kit green color (matches UI styling)
        let toolKitGreen = UIColor(red: 0.133, green: 0.545, blue: 0.133, alpha: 1.0)

        // Draw Tool Kit header - indented and styled distinctly with green color
        // Feature #155: Headers use larger font (11pt) than tool items (10pt) for clear visual hierarchy
        let kitHeaderAttrs: [NSAttributedString.Key: Any] = [
            .font: UIFont.boldSystemFont(ofSize: 11),
            .foregroundColor: toolKitGreen
        ]
        let kitHeader = "◆ \(kitName)"  // Diamond symbol to distinguish from Tool Sets (which use ▸)
        kitHeader.draw(at: CGPoint(x: margin + 20, y: currentY), withAttributes: kitHeaderAttrs)
        currentY += 14

        // Draw tools within the kit - further indented
        let bulletAttrs: [NSAttributedString.Key: Any] = [
            .font: UIFont.systemFont(ofSize: 10),
            .foregroundColor: darkCharcoal
        ]
        let detailAttrs: [NSAttributedString.Key: Any] = [
            .font: UIFont.italicSystemFont(ofSize: 9),
            .foregroundColor: steelGray
        ]

        for tool in tools {
            currentY = checkPageBreak(currentY: currentY, neededHeight: 20, context: context)
            let displayName = toolDisplayName(for: tool)
            let bullet = "  \u{2022}  \(displayName)"
            bullet.draw(at: CGPoint(x: margin + 30, y: currentY), withAttributes: bulletAttrs)

            // Show borrowed info if applicable
            if tool.ownershipType == "borrowed", let from = tool.borrowedFrom, !from.isEmpty {
                let trailingX = margin + 30 + bullet.size(withAttributes: bulletAttrs).width
                let detail = "  (from: \(from))"
                detail.draw(at: CGPoint(x: trailingX, y: currentY + 1), withAttributes: detailAttrs)
            }

            currentY += 14
        }

        return currentY + 2  // Small spacing after kit
    }

    /// Draws ungrouped tools (not in any Tool Set or Tool Kit) - Feature #154
    /// Tools that are not part of any Tool Set or Tool Kit appear in a separate section
    /// in the PDF, clearly distinguished from grouped tools with "Individual Tools" header.
    private static func drawUngroupedTools(_ tools: [Tool], at y: CGFloat, in context: UIGraphicsPDFRendererContext) -> CGFloat {
        var currentY = y

        // Feature #154: Show clear "Individual Tools" section header
        currentY = checkPageBreak(currentY: currentY, neededHeight: 36, context: context)

        let headerAttrs: [NSAttributedString.Key: Any] = [
            .font: UIFont.boldSystemFont(ofSize: 10),
            .foregroundColor: steelGray
        ]
        "Individual Tools".draw(at: CGPoint(x: margin + 20, y: currentY), withAttributes: headerAttrs)
        currentY += 14

        let bulletAttrs: [NSAttributedString.Key: Any] = [
            .font: UIFont.systemFont(ofSize: 10),
            .foregroundColor: darkCharcoal
        ]
        let detailAttrs: [NSAttributedString.Key: Any] = [
            .font: UIFont.italicSystemFont(ofSize: 9),
            .foregroundColor: steelGray
        ]

        for tool in tools {
            currentY = checkPageBreak(currentY: currentY, neededHeight: 20, context: context)
            let displayName = toolDisplayName(for: tool)
            let bullet = "  \u{2022}  \(displayName)"
            bullet.draw(at: CGPoint(x: margin + 20, y: currentY), withAttributes: bulletAttrs)

            // Show borrowed info if applicable
            if tool.ownershipType == "borrowed", let from = tool.borrowedFrom, !from.isEmpty {
                let trailingX = margin + 20 + bullet.size(withAttributes: bulletAttrs).width
                let detail = "  (from: \(from))"
                detail.draw(at: CGPoint(x: trailingX, y: currentY + 1), withAttributes: detailAttrs)
            }

            currentY += 14
        }

        return currentY
    }

    /// Draws a tool group (e.g., "Personal Tools")
    private static func drawToolGroup(_ groupName: String, tools: [Tool], at y: CGFloat, in context: UIGraphicsPDFRendererContext) -> CGFloat {
        var currentY = y

        let groupAttrs: [NSAttributedString.Key: Any] = [
            .font: UIFont.boldSystemFont(ofSize: 10),
            .foregroundColor: steelGray
        ]
        groupName.draw(at: CGPoint(x: margin + 10, y: currentY), withAttributes: groupAttrs)
        currentY += 16

        let bulletAttrs: [NSAttributedString.Key: Any] = [
            .font: UIFont.systemFont(ofSize: 10),
            .foregroundColor: darkCharcoal
        ]
        let detailAttrs: [NSAttributedString.Key: Any] = [
            .font: UIFont.italicSystemFont(ofSize: 9),
            .foregroundColor: steelGray
        ]

        for tool in tools {
            currentY = checkPageBreak(currentY: currentY, neededHeight: 20, context: context)
            let name = tool.name
            let bullet = "  \u{2022}  \(name)"
            bullet.draw(at: CGPoint(x: margin + 10, y: currentY), withAttributes: bulletAttrs)

            // Show borrowed from if applicable
            if tool.ownershipType == "borrowed", let from = tool.borrowedFrom, !from.isEmpty {
                let detail = "  (from: \(from))"
                let nameSize = bullet.size(withAttributes: bulletAttrs)
                detail.draw(at: CGPoint(x: margin + 10 + nameSize.width, y: currentY + 1), withAttributes: detailAttrs)
            }

            currentY += 16
        }

        return currentY
    }

    /// Draws the consumables list
    private static func drawConsumablesList(_ consumables: [Consumable], at y: CGFloat, in context: UIGraphicsPDFRendererContext) -> CGFloat {
        var currentY = y
        let bulletAttrs: [NSAttributedString.Key: Any] = [
            .font: UIFont.systemFont(ofSize: 10),
            .foregroundColor: darkCharcoal
        ]
        let detailAttrs: [NSAttributedString.Key: Any] = [
            .font: UIFont.italicSystemFont(ofSize: 9),
            .foregroundColor: steelGray
        ]

        for item in consumables {
            currentY = checkPageBreak(currentY: currentY, neededHeight: 20, context: context)
            let name = item.name
            let bullet = "  \u{2022}  \(name)"
            bullet.draw(at: CGPoint(x: margin + 10, y: currentY), withAttributes: bulletAttrs)

            var details: [String] = []
            if !item.category.isEmpty { details.append(categoryLabel(item.category)) }
            if let size = item.size, !size.isEmpty { details.append(size) }
            if let spec = item.spec, !spec.isEmpty { details.append(spec) }

            if !details.isEmpty {
                let detailStr = "  (\(details.joined(separator: ", ")))"
                let nameSize = bullet.size(withAttributes: bulletAttrs)
                detailStr.draw(at: CGPoint(x: margin + 10 + nameSize.width, y: currentY + 1), withAttributes: detailAttrs)
            }

            currentY += 16
        }

        return currentY
    }

    /// Draws the chemicals list
    private static func drawChemicalsList(_ chemicals: [Chemical], at y: CGFloat, in context: UIGraphicsPDFRendererContext) -> CGFloat {
        var currentY = y
        let bulletAttrs: [NSAttributedString.Key: Any] = [
            .font: UIFont.systemFont(ofSize: 10),
            .foregroundColor: darkCharcoal
        ]
        let detailAttrs: [NSAttributedString.Key: Any] = [
            .font: UIFont.italicSystemFont(ofSize: 9),
            .foregroundColor: steelGray
        ]

        for item in chemicals {
            currentY = checkPageBreak(currentY: currentY, neededHeight: 20, context: context)
            let name = item.name
            let bullet = "  \u{2022}  \(name)"
            bullet.draw(at: CGPoint(x: margin + 10, y: currentY), withAttributes: bulletAttrs)

            var details: [String] = []
            if !item.category.isEmpty { details.append(categoryLabel(item.category)) }
            if let size = item.size, !size.isEmpty { details.append(size) }
            if let spec = item.spec, !spec.isEmpty { details.append(spec) }

            if !details.isEmpty {
                let detailStr = "  (\(details.joined(separator: ", ")))"
                let nameSize = bullet.size(withAttributes: bulletAttrs)
                detailStr.draw(at: CGPoint(x: margin + 10 + nameSize.width, y: currentY + 1), withAttributes: detailAttrs)
            }

            currentY += 16
        }

        return currentY
    }

    /// Feature #141: Draws the parts list in PDF
    private static func drawPartsList(_ parts: [Part], at y: CGFloat, in context: UIGraphicsPDFRendererContext) -> CGFloat {
        var currentY = y
        let bulletAttrs: [NSAttributedString.Key: Any] = [
            .font: UIFont.systemFont(ofSize: 10),
            .foregroundColor: darkCharcoal
        ]
        let detailAttrs: [NSAttributedString.Key: Any] = [
            .font: UIFont.italicSystemFont(ofSize: 9),
            .foregroundColor: steelGray
        ]

        for item in parts {
            currentY = checkPageBreak(currentY: currentY, neededHeight: 32, context: context)
            let name = item.nomenclature
            let bullet = "  \u{2022}  \(name)"
            bullet.draw(at: CGPoint(x: margin + 10, y: currentY), withAttributes: bulletAttrs)

            if item.quantity > 1 {
                let qtyStr = "  (Qty: \(item.quantity))"
                let nameSize = bullet.size(withAttributes: bulletAttrs)
                qtyStr.draw(at: CGPoint(x: margin + 10 + nameSize.width, y: currentY + 1), withAttributes: detailAttrs)
            }

            currentY += 14

            // Detail line: P/N, Alt P/N, NSN
            var details: [String] = []
            if !item.partNumber.isEmpty { details.append("P/N: \(item.partNumber)") }
            if let alt = item.alternatePartNumber, !alt.isEmpty { details.append("Alt: \(alt)") }
            if let nsn = item.nsn, !nsn.isEmpty { details.append("NSN: \(nsn)") }

            if !details.isEmpty {
                let detailStr = "     \(details.joined(separator: "  |  "))"
                detailStr.draw(at: CGPoint(x: margin + 10, y: currentY), withAttributes: detailAttrs)
                currentY += 14
            }

            currentY += 2
        }

        return currentY
    }

    /// Checks if a page break is needed and starts a new page if so
    private static func checkPageBreak(currentY: CGFloat, neededHeight: CGFloat, context: UIGraphicsPDFRendererContext) -> CGFloat {
        let maxY = pageHeight - margin - 30 // Leave room for footer
        if currentY + neededHeight > maxY {
            drawFooter(in: context)
            context.beginPage()
            // Draw FRO banner on continuation pages too
            let bannerY = drawFROBannerSmall(at: margin, in: context)
            return bannerY + 10
        }
        return currentY
    }

    /// Draws a smaller FRO banner for continuation pages
    private static func drawFROBannerSmall(at y: CGFloat, in context: UIGraphicsPDFRendererContext) -> CGFloat {
        let text = "FOR REFERENCE ONLY"
        let attrs: [NSAttributedString.Key: Any] = [
            .font: UIFont.boldSystemFont(ofSize: 10),
            .foregroundColor: safetyOrange
        ]
        let size = text.size(withAttributes: attrs)
        let x = margin + (contentWidth - size.width) / 2
        text.draw(at: CGPoint(x: x, y: y), withAttributes: attrs)

        // Separator line
        safetyOrange.withAlphaComponent(0.3).setStroke()
        let path = UIBezierPath()
        path.move(to: CGPoint(x: margin, y: y + size.height + 4))
        path.addLine(to: CGPoint(x: margin + contentWidth, y: y + size.height + 4))
        path.lineWidth = 0.5
        path.stroke()

        return y + size.height + 8
    }

    /// Draws the footer on the current page
    private static func drawFooter(in context: UIGraphicsPDFRendererContext) {
        let footerY = pageHeight - margin + 10
        let footerText = "FOR REFERENCE ONLY - Not authoritative maintenance data"
        let attrs: [NSAttributedString.Key: Any] = [
            .font: UIFont.boldSystemFont(ofSize: 8),
            .foregroundColor: safetyOrange.withAlphaComponent(0.7)
        ]
        let size = footerText.size(withAttributes: attrs)
        let x = margin + (contentWidth - size.width) / 2
        footerText.draw(at: CGPoint(x: x, y: footerY), withAttributes: attrs)
    }

    // MARK: - Data Helpers

    /// Returns the tool's display name with its toolType appended if available.
    /// e.g., tool.name = "3/8"" + parent toolType = "Socket" → "3/8\" Socket"
    /// If no toolType is set on the parent set/kit, returns the raw tool name.
    private static func toolDisplayName(for tool: Tool) -> String {
        let name = tool.name
        let type = toolTypeLabel(for: tool)
        if type.isEmpty {
            return name
        }
        return "\(name) \(type)"
    }

    /// Returns the toolType from the tool's parent Tool Set or Tool Kit.
    /// Checks Tool Set first, then falls back to Tool Kit.
    /// Returns empty string if no parent has a toolType set.
    private static func toolTypeLabel(for tool: Tool) -> String {
        // Check Tool Set first (group relationship)
        if let group = tool.group, let type = group.toolType, !type.isEmpty {
            return type
        }
        // Check Tool Kits (many-to-many)
        if let toolKits = tool.toolKits {
            for kit in toolKits.sorted(by: { $0.name < $1.name }) {
                if let type = kit.toolType, !type.isEmpty {
                    return type
                }
            }
        }
        return ""
    }

    private static func sortedTools(from job: JobRecord) -> [Tool] {
        guard let toolSet = job.tools else { return [] }
        return Array(toolSet).sortedBySize()
    }

    private static func sortedConsumables(from job: JobRecord) -> [Consumable] {
        guard let set = job.consumables else { return [] }
        return set.sorted { $0.name < $1.name }
    }

    private static func sortedChemicals(from job: JobRecord) -> [Chemical] {
        guard let set = job.chemicals else { return [] }
        return set.sorted { $0.name < $1.name }
    }

    /// Feature #141: Sorted parts from job
    private static func sortedParts(from job: JobRecord) -> [Part] {
        guard let set = job.parts else { return [] }
        return set.sorted { $0.nomenclature < $1.nomenclature }
    }

    private static func categoryLabel(_ raw: String) -> String {
        switch raw {
        case "safety_wire": return "Safety Wire"
        case "cotter_pin": return "Cotter Pin"
        case "o_ring": return "O-Ring"
        case "seal": return "Seal"
        case "fluid": return "Fluid"
        case "lubricant": return "Lubricant"
        case "cleaner": return "Cleaner"
        case "sealant": return "Sealant"
        default: return raw.capitalized
        }
    }
}

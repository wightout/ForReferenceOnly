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
            currentY = drawTitle(job.aircraftType ?? "Job Report", at: currentY, in: context)
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

            // === Notes ===
            if let notes = job.notes, !notes.isEmpty {
                currentY = checkPageBreak(currentY: currentY, neededHeight: 60, context: context)
                currentY = drawSectionHeader("NOTES", at: currentY, in: context)
                currentY = drawBodyText(notes, at: currentY, in: context)
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
    static func generatePDFFile(for job: JobRecord) -> URL? {
        guard let data = generatePDF(for: job) else { return nil }

        let aircraftType = (job.aircraftType ?? "Job").replacingOccurrences(of: " ", with: "_")
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyyy-MM-dd"
        let dateStr = dateFormatter.string(from: job.jobDate ?? Date())
        let fileName = "FRO_\(aircraftType)_\(dateStr).pdf"

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
        if let system = job.system, !system.isEmpty {
            metadataItems.append(("System", system))
        }
        if let comp = job.component, !comp.isEmpty {
            metadataItems.append(("Component", comp))
        }
        if let date = job.jobDate {
            let formatter = DateFormatter()
            formatter.dateStyle = .long
            metadataItems.append(("Job Date", formatter.string(from: date)))
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

    /// Draws the tools list grouped by ownership
    private static func drawToolsList(_ tools: [Tool], at y: CGFloat, in context: UIGraphicsPDFRendererContext) -> CGFloat {
        var currentY = y

        let personalTools = tools.filter { $0.ownershipType == "personal" || $0.ownershipType == nil }
        let shopTools = tools.filter { $0.ownershipType == "shop" }
        let borrowedTools = tools.filter { $0.ownershipType == "borrowed" }

        if !personalTools.isEmpty {
            currentY = drawToolGroup("Personal Tools", tools: personalTools, at: currentY, in: context)
        }
        if !shopTools.isEmpty {
            currentY = drawToolGroup("Shop Tools", tools: shopTools, at: currentY, in: context)
        }
        if !borrowedTools.isEmpty {
            currentY = drawToolGroup("Borrowed Tools", tools: borrowedTools, at: currentY, in: context)
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
            let name = tool.name ?? "Unnamed"
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
            let name = item.name ?? "Unnamed"
            let bullet = "  \u{2022}  \(name)"
            bullet.draw(at: CGPoint(x: margin + 10, y: currentY), withAttributes: bulletAttrs)

            var details: [String] = []
            if let cat = item.category, !cat.isEmpty { details.append(categoryLabel(cat)) }
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
            let name = item.name ?? "Unnamed"
            let bullet = "  \u{2022}  \(name)"
            bullet.draw(at: CGPoint(x: margin + 10, y: currentY), withAttributes: bulletAttrs)

            var details: [String] = []
            if let cat = item.category, !cat.isEmpty { details.append(categoryLabel(cat)) }
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

    private static func sortedTools(from job: JobRecord) -> [Tool] {
        guard let toolSet = job.tools as? Set<Tool> else { return [] }
        return toolSet.sorted { ($0.name ?? "") < ($1.name ?? "") }
    }

    private static func sortedConsumables(from job: JobRecord) -> [Consumable] {
        guard let set = job.consumables as? Set<Consumable> else { return [] }
        return set.sorted { ($0.name ?? "") < ($1.name ?? "") }
    }

    private static func sortedChemicals(from job: JobRecord) -> [Chemical] {
        guard let set = job.chemicals as? Set<Chemical> else { return [] }
        return set.sorted { ($0.name ?? "") < ($1.name ?? "") }
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

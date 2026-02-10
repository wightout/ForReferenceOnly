import Foundation

/// Service for parsing and sorting tools by size.
/// Handles fractional inches, metric sizes, and standard sizes.
/// Sorting order: smallest to largest, inch-standard before metric, tools without sizes at end.
struct ToolSizeSortingService {

    /// Represents a parsed tool size with type information for sorting
    struct ParsedSize: Comparable {
        enum SizeType: Int, Comparable {
            case inch = 0        // Fractional inches (1/4", 3/8", etc.)
            case inchDecimal = 1 // Decimal inches (0.5", etc.)
            case metric = 2      // Metric (10mm, 13mm, etc.)
            case other = 3       // Other numeric sizes (8in, 12in, etc.)
            case none = 4        // No size found

            static func < (lhs: SizeType, rhs: SizeType) -> Bool {
                lhs.rawValue < rhs.rawValue
            }
        }

        let value: Double      // Numeric value in consistent units (inches for inch, mm for metric)
        let type: SizeType     // Size type for grouping
        let original: String   // Original size string extracted

        static func < (lhs: ParsedSize, rhs: ParsedSize) -> Bool {
            // First sort by type (inch before metric, etc.)
            if lhs.type != rhs.type {
                return lhs.type < rhs.type
            }
            // Then by value within same type
            return lhs.value < rhs.value
        }

        static func noSize() -> ParsedSize {
            ParsedSize(value: Double.infinity, type: .none, original: "")
        }
    }

    /// Common fractional inch values for pattern matching
    private static let fractionPatterns: [(pattern: String, value: Double)] = [
        // Common fractions sorted by size
        ("1/16", 1.0/16.0),
        ("1/8", 1.0/8.0),
        ("5/32", 5.0/32.0),
        ("3/16", 3.0/16.0),
        ("7/32", 7.0/32.0),
        ("1/4", 1.0/4.0),
        ("9/32", 9.0/32.0),
        ("5/16", 5.0/16.0),
        ("11/32", 11.0/32.0),
        ("3/8", 3.0/8.0),
        ("13/32", 13.0/32.0),
        ("7/16", 7.0/16.0),
        ("15/32", 15.0/32.0),
        ("1/2", 1.0/2.0),
        ("17/32", 17.0/32.0),
        ("9/16", 9.0/16.0),
        ("19/32", 19.0/32.0),
        ("5/8", 5.0/8.0),
        ("21/32", 21.0/32.0),
        ("11/16", 11.0/16.0),
        ("23/32", 23.0/32.0),
        ("3/4", 3.0/4.0),
        ("25/32", 25.0/32.0),
        ("13/16", 13.0/16.0),
        ("27/32", 27.0/32.0),
        ("7/8", 7.0/8.0),
        ("29/32", 29.0/32.0),
        ("15/16", 15.0/16.0),
        ("31/32", 31.0/32.0),
        ("1", 1.0),
        ("1-1/16", 1.0 + 1.0/16.0),
        ("1-1/8", 1.0 + 1.0/8.0),
        ("1-1/4", 1.0 + 1.0/4.0),
        ("1-3/8", 1.0 + 3.0/8.0),
        ("1-1/2", 1.0 + 1.0/2.0),
        ("1-5/8", 1.0 + 5.0/8.0),
        ("1-3/4", 1.0 + 3.0/4.0),
        ("2", 2.0),
    ]

    /// Parse a size from a tool name string
    /// - Parameter toolName: The full tool name (e.g., "3/8\" Torque Wrench")
    /// - Returns: A ParsedSize struct with the extracted size information
    static func parseSize(from toolName: String) -> ParsedSize {
        let name = toolName.lowercased()

        // 1. Check for other inch sizes (8in, 12in, etc.) FIRST to avoid false positives
        // Match patterns like "8in", "8 in", "8-inch", "8 inch", "12 inch"
        // Must check this before fractional inches to avoid "12 inch" matching as "2" inch
        if let inchRegex = try? NSRegularExpression(pattern: "(\\d+)\\s*-?\\s*in(?:ch)?\\b", options: []),
           let match = inchRegex.firstMatch(in: name, options: [], range: NSRange(name.startIndex..., in: name)) {
            if let valueRange = Range(match.range(at: 1), in: name),
               let value = Double(name[valueRange]) {
                return ParsedSize(value: value, type: .other, original: "\(Int(value))in")
            }
        }

        // 2. Check for metric sizes (mm) - before fractions to avoid false positives
        // Match patterns like "10mm", "13 mm", "10-mm"
        if let metricRegex = try? NSRegularExpression(pattern: "(\\d+\\.?\\d*)\\s*-?\\s*mm\\b", options: []),
           let match = metricRegex.firstMatch(in: name, options: [], range: NSRange(name.startIndex..., in: name)) {
            if let valueRange = Range(match.range(at: 1), in: name),
               let value = Double(name[valueRange]) {
                return ParsedSize(value: value, type: .metric, original: "\(Int(value))mm")
            }
        }

        // 3. Check for fractional inch sizes
        // Match patterns like "3/8"", "3/8 inch", "3/8-inch", "3/8 drive"
        for (fraction, value) in fractionPatterns.sorted(by: { $0.pattern.count > $1.pattern.count }) {
            // Look for fraction followed by " or drive or at word boundary
            let fractionPattern = fraction.replacingOccurrences(of: "/", with: "\\/")
            let patterns = [
                "\(fractionPattern)\"",           // 3/8"
                "\(fractionPattern)'",            // 3/8' (less common)
                "\(fractionPattern)\\s*drive",    // 3/8 drive
                "\(fractionPattern)\\s+",         // 3/8 followed by space
                "\\b\(fractionPattern)\\b",       // 3/8 as standalone word
            ]

            for pattern in patterns {
                if let regex = try? NSRegularExpression(pattern: pattern, options: []),
                   regex.firstMatch(in: name, options: [], range: NSRange(name.startIndex..., in: name)) != nil {
                    return ParsedSize(value: value, type: .inch, original: fraction)
                }
            }
        }

        // 4. Check for decimal inch sizes
        // Match patterns like "0.5"", ".5 inch", "0.375"
        if let decimalRegex = try? NSRegularExpression(pattern: "(\\d*\\.\\d+)\\s*(?:\"|in)?", options: []),
           let match = decimalRegex.firstMatch(in: name, options: [], range: NSRange(name.startIndex..., in: name)) {
            if let valueRange = Range(match.range(at: 1), in: name),
               let value = Double(name[valueRange]) {
                // Only treat as decimal inch if value is reasonable (less than 10")
                if value < 10 {
                    return ParsedSize(value: value, type: .inchDecimal, original: String(format: "%.3f\"", value))
                }
            }
        }

        // 5. Check for simple numeric prefix (e.g., "#2 Phillips")
        if let numericRegex = try? NSRegularExpression(pattern: "^#?(\\d+)\\s+", options: []),
           let match = numericRegex.firstMatch(in: name, options: [], range: NSRange(name.startIndex..., in: name)) {
            if let valueRange = Range(match.range(at: 1), in: name),
               let value = Double(name[valueRange]) {
                return ParsedSize(value: value, type: .other, original: "#\(Int(value))")
            }
        }

        // No size found
        return ParsedSize.noSize()
    }

    /// Sort an array of Tool objects by size, then alphabetically
    /// - Parameter tools: Array of Tool objects to sort
    /// - Returns: Sorted array with tools ordered by: size (smallest first), inch before metric, tools without sizes last
    static func sortBySize(_ tools: [Tool]) -> [Tool] {
        return tools.sorted { tool1, tool2 in
            let name1 = tool1.name
            let name2 = tool2.name

            let size1 = parseSize(from: name1)
            let size2 = parseSize(from: name2)

            // If both have sizes, compare sizes
            if size1.type != .none && size2.type != .none {
                if size1 != size2 {
                    return size1 < size2
                }
                // Same size, sort alphabetically
                return name1.localizedCaseInsensitiveCompare(name2) == .orderedAscending
            }

            // Tools with sizes come before tools without
            if size1.type != .none && size2.type == .none {
                return true
            }
            if size1.type == .none && size2.type != .none {
                return false
            }

            // Both have no size, sort alphabetically
            return name1.localizedCaseInsensitiveCompare(name2) == .orderedAscending
        }
    }
}

// MARK: - Tool Extension for Convenient Sorting
extension Array where Element == Tool {
    /// Returns the array sorted by tool size (smallest first, inch before metric, no-size last)
    func sortedBySize() -> [Tool] {
        return ToolSizeSortingService.sortBySize(self)
    }
}

// MARK: - Display Size Extension for Tools
extension ToolSizeSortingService {
    /// Extract a display-friendly size string from a tool name.
    /// Returns the size with appropriate indicator (e.g., '3/8"', '10mm').
    /// If no size is found, returns nil.
    /// - Parameters:
    ///   - toolName: The full tool name
    ///   - measurementType: The measurement type of the parent group ("sae" or "metric")
    /// - Returns: A display string like "3/8\"" or "10mm", or nil if no size detected
    static func displaySize(from toolName: String, measurementType: String?) -> String? {
        let parsed = parseSize(from: toolName)

        guard parsed.type != .none else {
            return nil
        }

        switch parsed.type {
        case .inch:
            // Return the fraction with inch indicator
            return parsed.original + "\""
        case .inchDecimal:
            // Return decimal with inch indicator
            let value = parsed.value
            // Try to show as fraction if it's a common one
            if let fraction = decimalToFraction(value) {
                return fraction + "\""
            }
            return String(format: "%.3f", value).trimmingCharacters(in: CharacterSet(charactersIn: "0")).trimmingCharacters(in: CharacterSet(charactersIn: ".")) + "\""
        case .metric:
            // Return with mm indicator
            return parsed.original
        case .other:
            // Return the original size (e.g., "8in", "#2")
            return parsed.original
        case .none:
            return nil
        }
    }

    /// Try to convert a decimal inch value to a common fraction string
    private static func decimalToFraction(_ value: Double) -> String? {
        // Check common fractions with small tolerance
        let tolerance = 0.001
        for (fraction, fracValue) in fractionPatterns {
            if abs(value - fracValue) < tolerance {
                return fraction
            }
        }
        return nil
    }

    /// Format a size for display within a tool group context.
    /// Uses the group's measurement type to determine the indicator.
    /// - Parameters:
    ///   - toolName: The full tool name
    ///   - groupMeasurementType: The measurement type of the parent group ("sae" or "metric")
    /// - Returns: A clean display string with indicator, or the original name if no size found
    static func formatSizeForGroup(toolName: String, groupMeasurementType: String?) -> String {
        if let sizeDisplay = displaySize(from: toolName, measurementType: groupMeasurementType) {
            return sizeDisplay
        }
        // Fall back to original name if no size detected
        return toolName
    }
}

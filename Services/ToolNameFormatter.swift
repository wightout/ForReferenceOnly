import Foundation

/// Shared utility for formatting tool names based on measurement type and parsing tool size input.
/// Extracted for reuse across AddToolGroupView, EditToolGroupView, AddToolKitView, and EditToolKitView.
struct ToolNameFormatter {

    /// Formats a tool name from a raw size string, adding unit suffix based on measurement type.
    /// - For SAE: adds `"` suffix to numeric/fraction patterns (e.g., "1/4" → "1/4\"")
    /// - For Metric: adds `mm` suffix if not already present (e.g., "10" → "10mm")
    /// - Parameters:
    ///   - size: Raw size string (e.g., "1/4", "10")
    ///   - measurementType: The measurement system (SAE or Metric)
    /// - Returns: Formatted tool name with appropriate suffix
    static func formatToolName(_ size: String, measurementType: MeasurementType) -> String {
        let trimmed = size.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return trimmed }

        // For metric, add "mm" if not already present
        if measurementType == .metric {
            if trimmed.lowercased().hasSuffix("mm") {
                return trimmed
            } else {
                return "\(trimmed)mm"
            }
        }

        // For SAE, add inch symbol if not present (and if it looks like a fraction or number)
        if measurementType == .sae {
            if trimmed.hasSuffix("\"") || trimmed.hasSuffix("inch") || trimmed.hasSuffix("in") {
                return trimmed
            }
            // Check if it's a number or fraction pattern
            let fractionPattern = #"^[\d/\.\-]+$"#
            if trimmed.range(of: fractionPattern, options: .regularExpression) != nil {
                return "\(trimmed)\""
            }
        }

        return trimmed
    }

    /// Parses a multi-line text input into individual tool sizes.
    /// Each non-empty line becomes one tool entry.
    /// - Parameter text: Multi-line text input (one size per line)
    /// - Returns: Array of trimmed, non-empty size strings
    static func parseLineSeparatedSizes(_ text: String) -> [String] {
        text
            .components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
    }
}

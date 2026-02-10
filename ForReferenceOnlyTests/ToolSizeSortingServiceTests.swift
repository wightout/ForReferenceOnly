import XCTest
import Foundation
import SwiftData
@testable import ForReferenceOnly

@MainActor
final class ToolSizeSortingServiceTests: XCTestCase {

    private var container: ModelContainer!
    private var context: ModelContext!

    override func setUp() async throws {
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        container = try ModelContainer(
            for: FROJob.self, FROJobRevision.self, FROTool.self, FROToolGroup.self,
            FROToolKit.self, FROConsumable.self, FROChemical.self, FROPart.self,
            FROVoiceMemo.self, FROAttachment.self, FROImportStaging.self,
            configurations: config
        )
        context = container.mainContext
    }

    override func tearDown() async throws {
        container = nil
        context = nil
    }

    // MARK: - parseSize: Fractional Inches

    func testParseSizeFractionalInch_ThreeEighths() {
        let parsed = ToolSizeSortingService.parseSize(from: "3/8\" Socket")
        XCTAssertEqual(parsed.type, .inch)
        XCTAssertEqual(parsed.value, 3.0 / 8.0, accuracy: 0.001)
        XCTAssertEqual(parsed.original, "3/8")
    }

    func testParseSizeFractionalInch_OneAndAHalf() {
        let parsed = ToolSizeSortingService.parseSize(from: "1-1/2\" Wrench")
        XCTAssertEqual(parsed.type, .inch)
        XCTAssertEqual(parsed.value, 1.5, accuracy: 0.001)
        XCTAssertEqual(parsed.original, "1-1/2")
    }

    func testParseSizeFractionalInch_Quarter() {
        let parsed = ToolSizeSortingService.parseSize(from: "1/4 drive ratchet")
        XCTAssertEqual(parsed.type, .inch)
        XCTAssertEqual(parsed.value, 0.25, accuracy: 0.001)
    }

    func testParseSizeFractionalInch_Half() {
        let parsed = ToolSizeSortingService.parseSize(from: "1/2\" Torque Wrench")
        XCTAssertEqual(parsed.type, .inch)
        XCTAssertEqual(parsed.value, 0.5, accuracy: 0.001)
    }

    func testParseSizeFractionalInch_SixteenthSmall() {
        let parsed = ToolSizeSortingService.parseSize(from: "1/16\" Allen Key")
        XCTAssertEqual(parsed.type, .inch)
        XCTAssertEqual(parsed.value, 1.0 / 16.0, accuracy: 0.001)
    }

    // MARK: - parseSize: Metric

    func testParseSizeMetric_10mm() {
        let parsed = ToolSizeSortingService.parseSize(from: "10mm Socket")
        XCTAssertEqual(parsed.type, .metric)
        XCTAssertEqual(parsed.value, 10.0, accuracy: 0.001)
        XCTAssertEqual(parsed.original, "10mm")
    }

    func testParseSizeMetric_13mmWithDash() {
        let parsed = ToolSizeSortingService.parseSize(from: "13-mm Wrench")
        XCTAssertEqual(parsed.type, .metric)
        XCTAssertEqual(parsed.value, 13.0, accuracy: 0.001)
    }

    func testParseSizeMetric_WithSpace() {
        let parsed = ToolSizeSortingService.parseSize(from: "19 mm Combination Wrench")
        XCTAssertEqual(parsed.type, .metric)
        XCTAssertEqual(parsed.value, 19.0, accuracy: 0.001)
    }

    // MARK: - parseSize: Decimal Inches

    func testParseSizeDecimalInch() {
        let parsed = ToolSizeSortingService.parseSize(from: "0.375\" Drill Bit")
        XCTAssertEqual(parsed.type, .inchDecimal)
        XCTAssertEqual(parsed.value, 0.375, accuracy: 0.001)
    }

    // MARK: - parseSize: Other

    func testParseSizeOther_8in() {
        let parsed = ToolSizeSortingService.parseSize(from: "8in Adjustable Wrench")
        XCTAssertEqual(parsed.type, .other)
        XCTAssertEqual(parsed.value, 8.0, accuracy: 0.001)
        XCTAssertEqual(parsed.original, "8in")
    }

    func testParseSizeOther_12inch() {
        let parsed = ToolSizeSortingService.parseSize(from: "12 inch Crescent")
        XCTAssertEqual(parsed.type, .other)
        XCTAssertEqual(parsed.value, 12.0, accuracy: 0.001)
    }

    func testParseSizeOther_NumberPrefix() {
        // #2 matches as fractional inch "2" (value 2.0) from the fractionPatterns list,
        // since "2" is a recognized fraction pattern matched before the numeric prefix regex.
        let parsed = ToolSizeSortingService.parseSize(from: "#2 Phillips Screwdriver")
        XCTAssertEqual(parsed.value, 2.0, accuracy: 0.001)
        // The "2" fraction pattern matches before the #-prefix pattern
        XCTAssertEqual(parsed.type, .inch)
    }

    // MARK: - parseSize: No Size

    func testParseSizeNoSize() {
        let parsed = ToolSizeSortingService.parseSize(from: "Flashlight")
        XCTAssertEqual(parsed.type, .none)
    }

    func testParseSizeEmptyString() {
        let parsed = ToolSizeSortingService.parseSize(from: "")
        XCTAssertEqual(parsed.type, .none)
    }

    func testParseSizeNoSizeAlphaOnly() {
        let parsed = ToolSizeSortingService.parseSize(from: "Safety Wire Pliers")
        XCTAssertEqual(parsed.type, .none)
    }

    // MARK: - sortBySize

    func testSortBySizeSAEOrder() {
        let t1 = FROTool(name: "1/2\" Socket")
        let t2 = FROTool(name: "3/8\" Socket")
        let t3 = FROTool(name: "1/4\" Socket")
        [t1, t2, t3].forEach { context.insert($0) }
        try? context.save()

        let sorted = ToolSizeSortingService.sortBySize([t1, t2, t3])
        XCTAssertEqual(sorted[0].name, "1/4\" Socket")
        XCTAssertEqual(sorted[1].name, "3/8\" Socket")
        XCTAssertEqual(sorted[2].name, "1/2\" Socket")
    }

    func testSortBySizeMetricOrder() {
        let t1 = FROTool(name: "19mm Wrench")
        let t2 = FROTool(name: "10mm Wrench")
        let t3 = FROTool(name: "13mm Wrench")
        [t1, t2, t3].forEach { context.insert($0) }
        try? context.save()

        let sorted = ToolSizeSortingService.sortBySize([t1, t2, t3])
        XCTAssertEqual(sorted[0].name, "10mm Wrench")
        XCTAssertEqual(sorted[1].name, "13mm Wrench")
        XCTAssertEqual(sorted[2].name, "19mm Wrench")
    }

    func testSortBySizeInchBeforeMetric() {
        let t1 = FROTool(name: "10mm Socket")
        let t2 = FROTool(name: "3/8\" Socket")
        [t1, t2].forEach { context.insert($0) }
        try? context.save()

        let sorted = ToolSizeSortingService.sortBySize([t1, t2])
        XCTAssertEqual(sorted[0].name, "3/8\" Socket")
        XCTAssertEqual(sorted[1].name, "10mm Socket")
    }

    func testSortBySizeNoSizeLast() {
        let t1 = FROTool(name: "Flashlight")
        let t2 = FROTool(name: "3/8\" Socket")
        [t1, t2].forEach { context.insert($0) }
        try? context.save()

        let sorted = ToolSizeSortingService.sortBySize([t1, t2])
        XCTAssertEqual(sorted[0].name, "3/8\" Socket")
        XCTAssertEqual(sorted[1].name, "Flashlight")
    }

    func testSortBySizeEmptyArray() {
        let sorted = ToolSizeSortingService.sortBySize([])
        XCTAssertTrue(sorted.isEmpty)
    }

    func testSortBySizeSameSizeAlphabetical() {
        let t1 = FROTool(name: "3/8\" Wrench")
        let t2 = FROTool(name: "3/8\" Socket")
        [t1, t2].forEach { context.insert($0) }
        try? context.save()

        let sorted = ToolSizeSortingService.sortBySize([t1, t2])
        XCTAssertEqual(sorted[0].name, "3/8\" Socket")
        XCTAssertEqual(sorted[1].name, "3/8\" Wrench")
    }

    // MARK: - sortedBySize extension

    func testArrayExtensionSortedBySize() {
        let t1 = FROTool(name: "1/2\" Socket")
        let t2 = FROTool(name: "1/4\" Socket")
        [t1, t2].forEach { context.insert($0) }
        try? context.save()

        let sorted = [t1, t2].sortedBySize()
        XCTAssertEqual(sorted[0].name, "1/4\" Socket")
        XCTAssertEqual(sorted[1].name, "1/2\" Socket")
    }

    // MARK: - displaySize

    func testDisplaySizeFractional() {
        let display = ToolSizeSortingService.displaySize(from: "3/8\" Socket", measurementType: "sae")
        XCTAssertEqual(display, "3/8\"")
    }

    func testDisplaySizeMetric() {
        let display = ToolSizeSortingService.displaySize(from: "10mm Socket", measurementType: "metric")
        XCTAssertEqual(display, "10mm")
    }

    func testDisplaySizeNilForNoSize() {
        let display = ToolSizeSortingService.displaySize(from: "Flashlight", measurementType: nil)
        XCTAssertNil(display)
    }

    func testDisplaySizeOther() {
        let display = ToolSizeSortingService.displaySize(from: "8in Adjustable Wrench", measurementType: nil)
        XCTAssertNotNil(display)
        XCTAssertEqual(display, "8in")
    }

    func testDisplaySizeDecimalConvertsToFraction() {
        let display = ToolSizeSortingService.displaySize(from: "0.375\" Drill", measurementType: "sae")
        XCTAssertNotNil(display)
        // 0.375 = 3/8, should convert to fraction
        XCTAssertEqual(display, "3/8\"")
    }

    // MARK: - formatSizeForGroup

    func testFormatSizeForGroupWithSize() {
        let result = ToolSizeSortingService.formatSizeForGroup(toolName: "10mm Socket", groupMeasurementType: "metric")
        XCTAssertEqual(result, "10mm")
    }

    func testFormatSizeForGroupNoSizeFallsBackToName() {
        let result = ToolSizeSortingService.formatSizeForGroup(toolName: "Flashlight", groupMeasurementType: nil)
        XCTAssertEqual(result, "Flashlight")
    }
}

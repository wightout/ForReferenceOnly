import XCTest
import Foundation
import SwiftData
@testable import ForReferenceOnly

@MainActor
final class MigrationSmokeTest: XCTestCase {

    func testModelContainerInitializes() throws {
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        let container = try ModelContainer(
            for: FROJob.self, FROJobRevision.self, FROTool.self, FROToolGroup.self,
            FROToolKit.self, FROConsumable.self, FROChemical.self, FROPart.self,
            FROVoiceMemo.self, FROAttachment.self, FROImportStaging.self,
            configurations: config
        )
        XCTAssertNotNil(container)
    }

    func testAllModelTypesInSchema() throws {
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        let container = try ModelContainer(
            for: FROJob.self, FROJobRevision.self, FROTool.self, FROToolGroup.self,
            FROToolKit.self, FROConsumable.self, FROChemical.self, FROPart.self,
            FROVoiceMemo.self, FROAttachment.self, FROImportStaging.self,
            configurations: config
        )

        let context = container.mainContext

        // Insert one of each to verify all 11 types work
        context.insert(FROJob())
        context.insert(FROJobRevision())
        context.insert(FROTool())
        context.insert(FROToolGroup())
        context.insert(FROToolKit())
        context.insert(FROConsumable())
        context.insert(FROChemical())
        context.insert(FROPart())
        context.insert(FROVoiceMemo())
        context.insert(FROAttachment())
        context.insert(FROImportStaging())

        try context.save()

        XCTAssertEqual(try context.fetch(FetchDescriptor<FROJob>()).count, 1)
        XCTAssertEqual(try context.fetch(FetchDescriptor<FROJobRevision>()).count, 1)
        XCTAssertEqual(try context.fetch(FetchDescriptor<FROTool>()).count, 1)
        XCTAssertEqual(try context.fetch(FetchDescriptor<FROToolGroup>()).count, 1)
        XCTAssertEqual(try context.fetch(FetchDescriptor<FROToolKit>()).count, 1)
        XCTAssertEqual(try context.fetch(FetchDescriptor<FROConsumable>()).count, 1)
        XCTAssertEqual(try context.fetch(FetchDescriptor<FROChemical>()).count, 1)
        XCTAssertEqual(try context.fetch(FetchDescriptor<FROPart>()).count, 1)
        XCTAssertEqual(try context.fetch(FetchDescriptor<FROVoiceMemo>()).count, 1)
        XCTAssertEqual(try context.fetch(FetchDescriptor<FROAttachment>()).count, 1)
        XCTAssertEqual(try context.fetch(FetchDescriptor<FROImportStaging>()).count, 1)
    }
}

import XCTest

final class ForReferenceOnlyTests: XCTestCase {
    func testAppLaunches() throws {
        // Smoke test - verifies the test target is correctly configured
        XCTAssertTrue(true, "Test target is working")
    }
    
    func testBundleIdentifierExists() throws {
        // Verify the test bundle loaded correctly
        let bundle = Bundle(for: type(of: self))
        XCTAssertNotNil(bundle.bundleIdentifier, "Test bundle should have an identifier")
    }
}

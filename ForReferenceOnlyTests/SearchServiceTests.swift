import XCTest
import Foundation
@testable import ForReferenceOnly

@MainActor
final class SearchServiceTests: XCTestCase {

    private var searchService: SearchService!

    override func setUp() async throws {
        searchService = SearchService()
    }

    override func tearDown() async throws {
        searchService = nil
    }

    // MARK: - levenshteinDistance

    func testLevenshteinDistanceIdenticalStrings() {
        let distance = searchService.levenshteinDistance("hello", "hello")
        XCTAssertEqual(distance, 0)
    }

    func testLevenshteinDistanceEmptyFirst() {
        let distance = searchService.levenshteinDistance("", "abc")
        XCTAssertEqual(distance, 3)
    }

    func testLevenshteinDistanceEmptySecond() {
        let distance = searchService.levenshteinDistance("abc", "")
        XCTAssertEqual(distance, 3)
    }

    func testLevenshteinDistanceBothEmpty() {
        let distance = searchService.levenshteinDistance("", "")
        XCTAssertEqual(distance, 0)
    }

    func testLevenshteinDistanceSingleInsertion() {
        let distance = searchService.levenshteinDistance("cat", "cats")
        XCTAssertEqual(distance, 1)
    }

    func testLevenshteinDistanceSingleDeletion() {
        let distance = searchService.levenshteinDistance("cats", "cat")
        XCTAssertEqual(distance, 1)
    }

    func testLevenshteinDistanceSingleSubstitution() {
        let distance = searchService.levenshteinDistance("cat", "bat")
        XCTAssertEqual(distance, 1)
    }

    func testLevenshteinDistanceMultipleEdits() {
        let distance = searchService.levenshteinDistance("kitten", "sitting")
        XCTAssertEqual(distance, 3)
    }

    func testLevenshteinDistanceCaseInsensitive() {
        let distance = searchService.levenshteinDistance("Hello", "hello")
        XCTAssertEqual(distance, 0)
    }

    func testLevenshteinDistanceRealisticTypo() {
        let distance = searchService.levenshteinDistance("wrench", "wrnech")
        XCTAssertLessThanOrEqual(distance, 2)
    }

    func testLevenshteinDistanceRealisticTypoBlackHawk() {
        let distance = searchService.levenshteinDistance("hawk", "hwak")
        XCTAssertEqual(distance, 2)
    }

    // MARK: - normalizeForComparison

    func testNormalizeForComparisonLowercase() {
        let result = searchService.normalizeForComparison("HELLO")
        XCTAssertEqual(result, "hello")
    }

    func testNormalizeForComparisonRemovesSpaces() {
        let result = searchService.normalizeForComparison("Black Hawk")
        XCTAssertEqual(result, "blackhawk")
    }

    func testNormalizeForComparisonRemovesDashes() {
        let result = searchService.normalizeForComparison("UH-60M")
        XCTAssertEqual(result, "uh60m")
    }

    func testNormalizeForComparisonRemovesUnderscores() {
        let result = searchService.normalizeForComparison("tool_name")
        XCTAssertEqual(result, "toolname")
    }

    func testNormalizeForComparisonCombined() {
        let result = searchService.normalizeForComparison("UH-60M Black Hawk")
        XCTAssertEqual(result, "uh60mblackhawk")
    }

    // MARK: - fuzzyMatches

    func testFuzzyMatchesExactContains() {
        let result = searchService.fuzzyMatches(query: "socket", target: "3/8\" Socket Set")
        XCTAssertTrue(result)
    }

    func testFuzzyMatchesNormalizedMatch() {
        let result = searchService.fuzzyMatches(query: "UH60M", target: "UH-60M Black Hawk")
        XCTAssertTrue(result)
    }

    func testFuzzyMatchesNormalizedMatchBlackHawk() {
        let result = searchService.fuzzyMatches(query: "blackhawk", target: "Black Hawk")
        XCTAssertTrue(result)
    }

    func testFuzzyMatchesWordByWordTypo() {
        let result = searchService.fuzzyMatches(query: "Black Hwak", target: "Black Hawk")
        XCTAssertTrue(result)
    }

    func testFuzzyMatchesNoMatch() {
        let result = searchService.fuzzyMatches(query: "airplane", target: "3/8\" Socket")
        XCTAssertFalse(result)
    }

    func testFuzzyMatchesMultiWordAllMatch() {
        let result = searchService.fuzzyMatches(query: "torque wrench", target: "1/2\" Torque Wrench")
        XCTAssertTrue(result)
    }

    func testFuzzyMatchesCaseInsensitive() {
        let result = searchService.fuzzyMatches(query: "SOCKET", target: "10mm Socket")
        XCTAssertTrue(result)
    }

    func testFuzzyMatchesTrimsWhitespace() {
        let result = searchService.fuzzyMatches(query: "  socket  ", target: "10mm Socket")
        XCTAssertTrue(result)
    }

    func testFuzzyMatchesCompletelyDifferent() {
        let result = searchService.fuzzyMatches(query: "zzzzzzz", target: "10mm Socket")
        XCTAssertFalse(result)
    }
}

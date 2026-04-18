import XCTest
@testable import SeshatAppKit

final class BuildInfoTests: XCTestCase {
    func testPackagedBundleRendersVersionAndShortSHA() {
        let info = BuildInfo(infoDictionary: [
            "CFBundleShortVersionString": "0.1.0",
            "SeshatGitSHA": "abcdef1234567890fedcba",
        ])

        XCTAssertEqual(info.version, "0.1.0")
        XCTAssertEqual(info.shortSHA, "abcdef1")
        XCTAssertEqual(info.displayString, "Seshat 0.1.0 · abcdef1")
    }

    func testMissingBundleEntriesFallBackToDevAndUnknown() {
        let info = BuildInfo(infoDictionary: [:])

        XCTAssertEqual(info.version, "dev")
        XCTAssertEqual(info.shortSHA, "unknown")
        XCTAssertEqual(info.displayString, "Seshat dev · unknown")
    }

    func testEmptyShaStringFallsBackToUnknown() {
        let info = BuildInfo(infoDictionary: [
            "CFBundleShortVersionString": "0.2.0",
            "SeshatGitSHA": "",
        ])

        XCTAssertEqual(info.version, "0.2.0")
        XCTAssertEqual(info.shortSHA, "unknown")
    }

    func testShaShorterThanSevenCharsUsedInFull() {
        let info = BuildInfo(infoDictionary: [
            "SeshatGitSHA": "abc",
        ])

        XCTAssertEqual(info.shortSHA, "abc")
    }
}

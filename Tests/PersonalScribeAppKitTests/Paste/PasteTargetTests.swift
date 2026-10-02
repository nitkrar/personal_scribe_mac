import XCTest
@testable import PersonalScribeAppKit

/// Paste rule shared by batch paste and live cursor output: Cmd+V goes to
/// the frontmost app, so paste unless that app is Ninimma itself.
final class PasteTargetTests: XCTestCase {
    private let selfBundle = "com.nitkrar.personal_scribe"

    func testPastesIntoAnyOtherFrontmostApp() {
        // Includes Electron apps like Slack, whose AX focus isn't readable —
        // the rule doesn't depend on AX.
        let target = PasteTarget.frontmost(bundleID: "com.tinyspeck.slackmacgap", pid: 42)
        XCTAssertTrue(target.permitsPaste(selfBundleID: selfBundle))
    }

    func testDoesNotPasteWhenNinimmaIsFrontmost() {
        let target = PasteTarget.frontmost(bundleID: selfBundle, pid: 7)
        XCTAssertFalse(target.permitsPaste(selfBundleID: selfBundle))
    }

    func testDoesNotPasteWithNoFrontmostApp() {
        XCTAssertFalse(PasteTarget.noFrontmostApp.permitsPaste(selfBundleID: selfBundle))
    }

    func testLogDescriptionNamesTheFrontmostApp() {
        XCTAssertEqual(
            PasteTarget.frontmost(bundleID: "com.tinyspeck.slackmacgap", pid: 42).logDescription,
            "frontmost=com.tinyspeck.slackmacgap pid=42"
        )
        XCTAssertEqual(PasteTarget.noFrontmostApp.logDescription, "frontmost=none")
    }
}

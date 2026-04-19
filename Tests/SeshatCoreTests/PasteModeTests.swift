import XCTest
@testable import SeshatCore

final class PasteModeTests: XCTestCase {
    private let suiteName = "SeshatTestsPasteMode"

    private func isolatedDefaults() -> UserDefaults {
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        return defaults
    }

    func testDefaultIsPasteAtCursor() {
        XCTAssertEqual(PasteMode.default, .pasteAtCursor)
    }

    func testResolveReturnsDefaultWhenKeyAbsent() {
        let defaults = isolatedDefaults()

        XCTAssertEqual(PasteMode.resolve(from: defaults), .pasteAtCursor)
    }

    func testPreferenceRoundTripsClipboardOnly() {
        let defaults = isolatedDefaults()
        let preference = PasteMode.preference(defaults: defaults)

        preference.persist(.clipboardOnly)

        XCTAssertEqual(
            defaults.string(forKey: PasteMode.userDefaultsKey),
            "clipboard-only"
        )
        XCTAssertEqual(preference.resolve(), .clipboardOnly)
        XCTAssertEqual(PasteMode.resolve(from: defaults), .clipboardOnly)
    }

    func testResolveReturnsDefaultForUnrecognizedValue() {
        let defaults = isolatedDefaults()
        defaults.set("legacy-value", forKey: PasteMode.userDefaultsKey)

        XCTAssertEqual(PasteMode.resolve(from: defaults), .pasteAtCursor)
    }

    func testUserDefaultsKeyDropsSeshatPrefix() {
        XCTAssertEqual(PasteMode.userDefaultsKey, "PasteMode")
    }
}

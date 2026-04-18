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
        XCTAssertEqual(SeshatPasteMode.default, .pasteAtCursor)
    }

    func testResolveReturnsDefaultWhenKeyAbsent() {
        let defaults = isolatedDefaults()

        XCTAssertEqual(SeshatPasteMode.resolve(from: defaults), .pasteAtCursor)
    }

    func testPersistRoundTripClipboardOnly() {
        let defaults = isolatedDefaults()

        SeshatPasteMode.clipboardOnly.persist(to: defaults)

        XCTAssertEqual(
            defaults.string(forKey: SeshatPasteMode.userDefaultsKey),
            "clipboard-only"
        )
        XCTAssertEqual(SeshatPasteMode.resolve(from: defaults), .clipboardOnly)
    }

    func testResolveReturnsDefaultForUnrecognizedValue() {
        let defaults = isolatedDefaults()
        defaults.set("legacy-value", forKey: SeshatPasteMode.userDefaultsKey)

        XCTAssertEqual(SeshatPasteMode.resolve(from: defaults), .pasteAtCursor)
    }
}

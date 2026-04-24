import XCTest
@testable import PersonalScribeAppKit

final class ClipboardRestoreEnabledPreferenceTests: XCTestCase {
    private let suiteName = "PersonalScribeTestsClipboardRestoreEnabled"

    private func isolatedDefaults() -> UserDefaults {
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        return defaults
    }

    func testDefaultIsFalse() {
        // #072: fresh installs default to "transcript stays on clipboard
        // indefinitely" so the reported silent-drop-into-cursorless-surface
        // symptom is structurally impossible. Users who want the pre-#072
        // auto-restore convenience opt in.
        XCTAssertFalse(ClipboardRestoreEnabledPreference.default)
    }

    func testResolveReturnsDefaultWhenKeyAbsent() {
        let defaults = isolatedDefaults()

        XCTAssertFalse(ClipboardRestoreEnabledPreference.resolve(from: defaults))
    }

    func testResolveReadsPersistedTrueDistinctFromUnset() {
        let defaults = isolatedDefaults()
        ClipboardRestoreEnabledPreference.persist(true, to: defaults)

        XCTAssertTrue(ClipboardRestoreEnabledPreference.resolve(from: defaults))
    }

    func testPersistRoundTrip() {
        let defaults = isolatedDefaults()
        ClipboardRestoreEnabledPreference.persist(true, to: defaults)
        XCTAssertTrue(ClipboardRestoreEnabledPreference.resolve(from: defaults))

        ClipboardRestoreEnabledPreference.persist(false, to: defaults)
        XCTAssertFalse(ClipboardRestoreEnabledPreference.resolve(from: defaults))
    }

    func testUserDefaultsKey() {
        XCTAssertEqual(ClipboardRestoreEnabledPreference.userDefaultsKey, "ClipboardRestoreEnabled")
    }
}

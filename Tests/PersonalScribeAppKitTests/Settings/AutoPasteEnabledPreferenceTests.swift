import XCTest
@testable import PersonalScribeAppKit

final class AutoPasteEnabledPreferenceTests: XCTestCase {
    private let suiteName = "PersonalScribeTestsAutoPasteEnabled"

    private func isolatedDefaults() -> UserDefaults {
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        return defaults
    }

    func testDefaultIsTrue() {
        XCTAssertTrue(AutoPasteEnabledPreference.default)
    }

    func testResolveReturnsDefaultWhenKeyAbsent() {
        let defaults = isolatedDefaults()

        XCTAssertTrue(AutoPasteEnabledPreference.resolve(from: defaults))
    }

    func testResolveReadsPersistedFalseDistinctFromUnset() {
        let defaults = isolatedDefaults()
        AutoPasteEnabledPreference.persist(false, to: defaults)

        XCTAssertFalse(
            AutoPasteEnabledPreference.resolve(from: defaults),
            "Explicit false must not fall through to the `true` default"
        )
    }

    func testPersistRoundTrip() {
        let defaults = isolatedDefaults()
        AutoPasteEnabledPreference.persist(false, to: defaults)
        XCTAssertFalse(AutoPasteEnabledPreference.resolve(from: defaults))

        AutoPasteEnabledPreference.persist(true, to: defaults)
        XCTAssertTrue(AutoPasteEnabledPreference.resolve(from: defaults))
    }

    func testUserDefaultsKey() {
        XCTAssertEqual(AutoPasteEnabledPreference.userDefaultsKey, "AutoPasteEnabled")
    }
}

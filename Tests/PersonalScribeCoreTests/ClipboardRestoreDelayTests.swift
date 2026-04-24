import XCTest
@testable import PersonalScribeCore

final class ClipboardRestoreDelayTests: XCTestCase {
    private let suiteName = "PersonalScribeTestsClipboardRestoreDelay"

    private func isolatedDefaults() -> UserDefaults {
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        return defaults
    }

    func testDefaultIsThreeSeconds() {
        XCTAssertEqual(ClipboardRestoreDelay.default.seconds, 3.0, accuracy: 0.0001)
    }

    func testResolveReturnsDefaultWhenKeyAbsent() {
        let defaults = isolatedDefaults()

        XCTAssertEqual(ClipboardRestoreDelay.resolve(from: defaults).seconds, 3.0, accuracy: 0.0001)
    }

    func testStoredSecondsPreferenceRoundTrip() {
        let defaults = isolatedDefaults()
        let storedSeconds = ClipboardRestoreDelay.storedSeconds(defaults: defaults)

        storedSeconds.persist(1.7)

        XCTAssertEqual(
            defaults.double(forKey: ClipboardRestoreDelay.userDefaultsKey),
            1.7,
            accuracy: 0.0001
        )
        XCTAssertEqual(storedSeconds.resolve(), 1.7, accuracy: 0.0001)
        XCTAssertEqual(ClipboardRestoreDelay.resolve(from: defaults).seconds, 1.7, accuracy: 0.0001)
    }

    func testResolveClampsOutOfRangeValuesToNearestBound() {
        let defaults = isolatedDefaults()
        defaults.set(0.05, forKey: ClipboardRestoreDelay.userDefaultsKey)

        XCTAssertEqual(ClipboardRestoreDelay.resolve(from: defaults).seconds, 0.1, accuracy: 0.0001)

        // Range bumped to 10.0s (#072). 11.0 clamps to the new max.
        defaults.set(11.0, forKey: ClipboardRestoreDelay.userDefaultsKey)

        XCTAssertEqual(ClipboardRestoreDelay.resolve(from: defaults).seconds, 10.0, accuracy: 0.0001)
    }

    func testResolveReturnsDefaultForInvalidType() {
        let defaults = isolatedDefaults()
        defaults.set("soon", forKey: ClipboardRestoreDelay.userDefaultsKey)

        XCTAssertEqual(ClipboardRestoreDelay.resolve(from: defaults).seconds, 3.0, accuracy: 0.0001)
    }

    func testUserDefaultsKeyPreservesMigrationFromPre072() {
        // Key name intentionally kept as the pre-#072 `PasteRestoreDelaySeconds`
        // so users who persisted a slider value before the rename don't reset
        // to the new default.
        XCTAssertEqual(ClipboardRestoreDelay.userDefaultsKey, "PasteRestoreDelaySeconds")
    }

    func testRangeBoundsExposed() {
        XCTAssertEqual(ClipboardRestoreDelay.minimumSeconds, 0.1, accuracy: 0.0001)
        XCTAssertEqual(ClipboardRestoreDelay.maximumSeconds, 10.0, accuracy: 0.0001)
    }
}

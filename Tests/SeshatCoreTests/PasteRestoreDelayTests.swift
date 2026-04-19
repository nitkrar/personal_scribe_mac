import XCTest
@testable import SeshatCore

final class PasteRestoreDelayTests: XCTestCase {
    private let suiteName = "SeshatTestsPasteRestoreDelay"

    private func isolatedDefaults() -> UserDefaults {
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        return defaults
    }

    func testDefaultIsHalfSecond() {
        XCTAssertEqual(PasteRestoreDelay.default.seconds, 0.5, accuracy: 0.0001)
    }

    func testResolveReturnsDefaultWhenKeyAbsent() {
        let defaults = isolatedDefaults()

        XCTAssertEqual(PasteRestoreDelay.resolve(from: defaults).seconds, 0.5, accuracy: 0.0001)
    }

    func testStoredSecondsPreferenceRoundTrip() {
        let defaults = isolatedDefaults()
        let storedSeconds = PasteRestoreDelay.storedSeconds(defaults: defaults)

        storedSeconds.persist(1.7)

        XCTAssertEqual(
            defaults.double(forKey: PasteRestoreDelay.userDefaultsKey),
            1.7,
            accuracy: 0.0001
        )
        XCTAssertEqual(storedSeconds.resolve(), 1.7, accuracy: 0.0001)
        XCTAssertEqual(PasteRestoreDelay.resolve(from: defaults).seconds, 1.7, accuracy: 0.0001)
    }

    func testResolveClampsOutOfRangeValuesToNearestBound() {
        let defaults = isolatedDefaults()
        defaults.set(0.05, forKey: PasteRestoreDelay.userDefaultsKey)

        XCTAssertEqual(PasteRestoreDelay.resolve(from: defaults).seconds, 0.1, accuracy: 0.0001)

        defaults.set(10.0, forKey: PasteRestoreDelay.userDefaultsKey)

        XCTAssertEqual(PasteRestoreDelay.resolve(from: defaults).seconds, 5.0, accuracy: 0.0001)
    }

    func testResolveReturnsDefaultForInvalidType() {
        let defaults = isolatedDefaults()
        defaults.set("soon", forKey: PasteRestoreDelay.userDefaultsKey)

        XCTAssertEqual(PasteRestoreDelay.resolve(from: defaults).seconds, 0.5, accuracy: 0.0001)
    }

    func testUserDefaultsKeyDropsSeshatPrefix() {
        XCTAssertEqual(PasteRestoreDelay.userDefaultsKey, "PasteRestoreDelaySeconds")
    }
}

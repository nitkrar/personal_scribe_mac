import XCTest
@testable import PersonalScribeCore

final class PausedRecordingTimeoutTests: XCTestCase {
    func testDefaultIsFiveMinutesAndUsesCanonicalKey() {
        XCTAssertEqual(PausedRecordingTimeout.default.minutes, 5)
        XCTAssertEqual(PausedRecordingTimeout.userDefaultsKey, "PausedRecordingTimeout")
    }

    func testResolveClampsToOneThroughThirtyMinutes() {
        let defaults = UserDefaults(suiteName: #function)!
        defaults.removePersistentDomain(forName: #function)

        defaults.set(0, forKey: PausedRecordingTimeout.userDefaultsKey)
        XCTAssertEqual(PausedRecordingTimeout.resolve(from: defaults).minutes, 1)

        defaults.set(99, forKey: PausedRecordingTimeout.userDefaultsKey)
        XCTAssertEqual(PausedRecordingTimeout.resolve(from: defaults).minutes, 30)
    }

    func testPersistStoresSanitizedMinutes() {
        let defaults = UserDefaults(suiteName: #function)!
        defaults.removePersistentDomain(forName: #function)

        PausedRecordingTimeout.persist(
            to: defaults,
            .init(minutes: 12)
        )

        XCTAssertEqual(
            defaults.double(forKey: PausedRecordingTimeout.userDefaultsKey),
            12
        )
    }
}

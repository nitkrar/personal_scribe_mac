import XCTest
@testable import PersonalScribeAppKit

final class MuteOutputWhileRecordingPreferenceTests: XCTestCase {
    private let suiteName = "PersonalScribeTestsMuteOutputWhileRecording"

    private func isolatedDefaults() -> UserDefaults {
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        return defaults
    }

    func testDefaultIsFalse() {
        XCTAssertFalse(MuteOutputWhileRecordingPreference.default)
    }

    func testResolveReturnsDefaultWhenKeyAbsent() {
        let defaults = isolatedDefaults()

        XCTAssertFalse(MuteOutputWhileRecordingPreference.resolve(from: defaults))
    }

    func testResolveReadsPersistedTrueDistinctFromUnset() {
        let defaults = isolatedDefaults()
        MuteOutputWhileRecordingPreference.persist(true, to: defaults)

        XCTAssertTrue(
            MuteOutputWhileRecordingPreference.resolve(from: defaults),
            "Explicit true must not fall through to the `false` default"
        )
    }

    func testPersistRoundTrip() {
        let defaults = isolatedDefaults()
        MuteOutputWhileRecordingPreference.persist(true, to: defaults)
        XCTAssertTrue(MuteOutputWhileRecordingPreference.resolve(from: defaults))

        MuteOutputWhileRecordingPreference.persist(false, to: defaults)
        XCTAssertFalse(MuteOutputWhileRecordingPreference.resolve(from: defaults))
    }

    func testUserDefaultsKey() {
        XCTAssertEqual(
            MuteOutputWhileRecordingPreference.userDefaultsKey,
            "MuteOutputWhileRecording"
        )
    }
}

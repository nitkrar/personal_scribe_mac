import XCTest
@testable import PersonalScribeCore

final class RecordAudioEnabledPreferenceTests: XCTestCase {
    private let suiteName = "PersonalScribeTestsRecordAudioEnabledPreference"

    private func isolatedDefaults() -> UserDefaults {
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        return defaults
    }

    func testDefaultIsTrue() {
        XCTAssertTrue(RecordAudioEnabledPreference.default)
    }

    func testResolveReturnsDefaultWhenKeyAbsent() {
        let defaults = isolatedDefaults()

        XCTAssertTrue(RecordAudioEnabledPreference.resolve(from: defaults))
    }

    func testResolveReadsPersistedFalseDistinctFromUnset() {
        let defaults = isolatedDefaults()
        RecordAudioEnabledPreference.persist(false, to: defaults)

        XCTAssertFalse(
            RecordAudioEnabledPreference.resolve(from: defaults),
            "Explicit false must not fall through to the `true` default"
        )
    }

    func testPersistRoundTrip() {
        let defaults = isolatedDefaults()
        RecordAudioEnabledPreference.persist(false, to: defaults)
        XCTAssertFalse(RecordAudioEnabledPreference.resolve(from: defaults))

        RecordAudioEnabledPreference.persist(true, to: defaults)
        XCTAssertTrue(RecordAudioEnabledPreference.resolve(from: defaults))
    }

    func testKey() {
        XCTAssertEqual(
            RecordAudioEnabledPreference.key,
            "RecordAudioEnabled"
        )
    }
}

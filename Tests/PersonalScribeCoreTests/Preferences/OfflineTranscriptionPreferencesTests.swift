import Foundation
import XCTest
@testable import PersonalScribeCore

final class OfflineTranscriptionPreferencesTests: XCTestCase {
    func testBatchModelPreferencePersistsFirstReadFromFallback() {
        let defaults = makeDefaults()

        let resolved = OfflineTranscriptionBatchModelPreference.resolve(
            from: defaults,
            activeFallback: { "whisperkit-small-216mb" }
        )

        XCTAssertEqual(resolved, "whisperkit-small-216mb")
        XCTAssertEqual(
            defaults.string(forKey: OfflineTranscriptionBatchModelPreference.key),
            "whisperkit-small-216mb"
        )
    }

    func testBatchModelPreferenceReturnsStoredValueOnSubsequentReads() {
        let defaults = makeDefaults()
        defaults.set("parakeet-tdt-0.6b-v2", forKey: OfflineTranscriptionBatchModelPreference.key)

        let resolved = OfflineTranscriptionBatchModelPreference.resolve(
            from: defaults,
            activeFallback: { "whisperkit-small-216mb" }
        )

        XCTAssertEqual(resolved, "parakeet-tdt-0.6b-v2")
    }

    func testBatchModelPreferenceExplicitPersistOverridesFallback() {
        let defaults = makeDefaults()

        OfflineTranscriptionBatchModelPreference.persist(
            "whispercpp-small-q5_1",
            to: defaults
        )

        let resolved = OfflineTranscriptionBatchModelPreference.resolve(
            from: defaults,
            activeFallback: { "parakeet-tdt-ctc-110m" }
        )

        XCTAssertEqual(resolved, "whispercpp-small-q5_1")
    }

    func testDiarizationPreferenceDefaultsToFalse() {
        let defaults = makeDefaults()

        XCTAssertFalse(OfflineTranscriptionDiarizationPreference.resolve(from: defaults))
    }

    func testDiarizationPreferenceRoundtrips() {
        let defaults = makeDefaults()

        OfflineTranscriptionDiarizationPreference.persist(true, to: defaults)

        XCTAssertTrue(OfflineTranscriptionDiarizationPreference.resolve(from: defaults))
    }

    private func makeDefaults() -> UserDefaults {
        let suiteName = "OfflineTranscriptionPreferencesTests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        return defaults
    }
}

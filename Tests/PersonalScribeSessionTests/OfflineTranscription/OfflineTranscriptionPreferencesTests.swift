import Foundation
import XCTest
@testable import PersonalScribeSession

final class OfflineTranscriptionPreferencesTests: XCTestCase {
    func testBatchModelPreferencePersistsFirstReadFromFallback() {
        let defaults = isolatedDefaults()
        var fallbackCallCount = 0

        let resolved = OfflineTranscriptionBatchModelPreference.resolve(from: defaults) {
            fallbackCallCount += 1
            return "fallback-model"
        }

        XCTAssertEqual(resolved, "fallback-model")
        XCTAssertEqual(fallbackCallCount, 1)
        XCTAssertEqual(defaults.string(forKey: OfflineTranscriptionBatchModelPreference.key), "fallback-model")
    }

    func testBatchModelPreferenceReturnsStoredValueOnSubsequentReads() {
        let defaults = isolatedDefaults()
        defaults.set("stored-model", forKey: OfflineTranscriptionBatchModelPreference.key)
        var fallbackCallCount = 0

        let resolved = OfflineTranscriptionBatchModelPreference.resolve(from: defaults) {
            fallbackCallCount += 1
            return "fallback-model"
        }

        XCTAssertEqual(resolved, "stored-model")
        XCTAssertEqual(fallbackCallCount, 0)
    }

    func testBatchModelPreferenceExplicitPersistOverridesFallback() {
        let defaults = isolatedDefaults()

        OfflineTranscriptionBatchModelPreference.persist("explicit-model", to: defaults)

        let resolved = OfflineTranscriptionBatchModelPreference.resolve(from: defaults) {
            "fallback-model"
        }

        XCTAssertEqual(resolved, "explicit-model")
        XCTAssertEqual(defaults.string(forKey: OfflineTranscriptionBatchModelPreference.key), "explicit-model")
    }

    func testDiarizationPreferenceDefaultsToFalse() {
        let defaults = isolatedDefaults()

        XCTAssertFalse(OfflineTranscriptionDiarizationPreference.resolve(from: defaults))
    }

    func testDiarizationPreferenceRoundtrips() {
        let defaults = isolatedDefaults()

        OfflineTranscriptionDiarizationPreference.persist(true, to: defaults)
        XCTAssertTrue(OfflineTranscriptionDiarizationPreference.resolve(from: defaults))

        OfflineTranscriptionDiarizationPreference.persist(false, to: defaults)
        XCTAssertFalse(OfflineTranscriptionDiarizationPreference.resolve(from: defaults))
    }
}

private extension OfflineTranscriptionPreferencesTests {
    func isolatedDefaults() -> UserDefaults {
        let suiteName = "PersonalScribeTests.OfflineTranscriptionPreferences.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        addTeardownBlock {
            UserDefaults(suiteName: suiteName)?.removePersistentDomain(forName: suiteName)
        }
        return defaults
    }
}

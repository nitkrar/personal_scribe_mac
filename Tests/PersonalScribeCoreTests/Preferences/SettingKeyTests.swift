import Foundation
import XCTest
@testable import PersonalScribeCore

/// #078.8 — `SettingKey<Value>` is a thin wrapper around the existing
/// `Preference<Value>` mechanism. Tests pin the resolution path to
/// UserDefaults, the fallback path when the key is absent, and the
/// presence of at least one expected entry in the central
/// `PreferenceKeys` registry.
final class SettingKeyTests: XCTestCase {

    private func isolatedDefaults() -> UserDefaults {
        let suiteName = "PersonalScribeTestsSettingKey.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        addTeardownBlock {
            UserDefaults(suiteName: suiteName)?.removePersistentDomain(forName: suiteName)
        }
        return defaults
    }

    func testSettingKeyResolvesFromUserDefaults() {
        let defaults = isolatedDefaults()
        let key = SettingKey<TimeInterval>(
            key: "SettingKeyTests.silenceThreshold",
            default: 5.0
        )
        // Persist a non-default value via the parallel `Preference` API
        // — `SettingKey.resolve(from:)` must read it back.
        Preference<TimeInterval>(
            key: key.key,
            default: key.default,
            defaults: defaults
        ).persist(2.5)

        XCTAssertEqual(key.resolve(from: defaults), 2.5, accuracy: 0.0001)
    }

    func testSettingKeyFallsBackToDefaultWhenAbsent() {
        let defaults = isolatedDefaults()
        let key = SettingKey<TimeInterval>(
            key: "SettingKeyTests.absentKey",
            default: 7.5
        )

        XCTAssertEqual(key.resolve(from: defaults), 7.5, accuracy: 0.0001)
    }

    func testRegistryIncludesVadSilenceThresholdKey() {
        // Pins that the central registry exposes the VAD silence
        // threshold key under a stable accessor — recipe parameters
        // reference `PreferenceKeys.vadSilenceThreshold` (#078.10).
        // The UserDefaults key + default mirror the existing
        // `VadSilenceThresholdPreference` in PersonalScribeAppKit.
        XCTAssertEqual(
            PreferenceKeys.vadSilenceThreshold.key,
            "VadSilenceDurationSeconds"
        )
        XCTAssertEqual(
            PreferenceKeys.vadSilenceThreshold.default,
            5.0,
            accuracy: 0.0001
        )
    }
}

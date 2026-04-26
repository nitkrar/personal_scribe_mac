import Foundation
import XCTest
@testable import PersonalScribeCore

/// #078.9 — `ParameterResolver` is the single resolution site for
/// `Parameter<Value>`. Tests pin the cascade rule (override > setting >
/// hardcoded default) and the eager-at-call-site semantics (L19/L25).
final class ParameterResolverTests: XCTestCase {

    private func isolatedDefaults() -> UserDefaults {
        let suiteName = "PersonalScribeTestsParameterResolver.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        addTeardownBlock {
            UserDefaults(suiteName: suiteName)?.removePersistentDomain(forName: suiteName)
        }
        return defaults
    }

    func testOverrideWinsOverSetting() {
        let defaults = isolatedDefaults()
        // Persist a setting value of 7.5; an override of 2.0 must
        // win regardless of what's in UserDefaults.
        Preference<TimeInterval>(
            key: "ResolverTests.threshold",
            default: 5.0,
            defaults: defaults
        ).persist(7.5)

        let parameter = Parameter<TimeInterval>.override(2.0)

        XCTAssertEqual(
            ParameterResolver.resolve(parameter, from: defaults),
            2.0,
            accuracy: 0.0001
        )
    }

    func testSettingFallsBackToHardcodedDefault() {
        let defaults = isolatedDefaults()
        // No persisted value under this key — the resolver must
        // surface the SettingKey's hardcoded default (5.0).
        let parameter = Parameter<TimeInterval>.setting(
            SettingKey<TimeInterval>(
                key: "ResolverTests.absentKey",
                default: 5.0
            )
        )

        XCTAssertEqual(
            ParameterResolver.resolve(parameter, from: defaults),
            5.0,
            accuracy: 0.0001
        )
    }

    func testResolverReturnsValueAtCallTime() {
        // Eager-at-call-site: the resolver reads UserDefaults once,
        // returns the captured value. A subsequent setting change
        // does not retroactively affect a previously-resolved value
        // (the captured `Value` is a struct copy).
        let defaults = isolatedDefaults()
        let preference = Preference<TimeInterval>(
            key: "ResolverTests.callTime",
            default: 5.0,
            defaults: defaults
        )
        preference.persist(3.0)

        let parameter = Parameter<TimeInterval>.setting(
            SettingKey<TimeInterval>(
                key: "ResolverTests.callTime",
                default: 5.0
            )
        )

        let firstRead = ParameterResolver.resolve(parameter, from: defaults)
        XCTAssertEqual(firstRead, 3.0, accuracy: 0.0001)

        // Mutate UserDefaults after first resolve — the captured
        // `firstRead` value is unchanged (eager).
        preference.persist(4.0)
        XCTAssertEqual(
            firstRead,
            3.0,
            accuracy: 0.0001,
            "Already-resolved value must not change when the underlying setting changes."
        )

        // A fresh resolve sees the new value (the resolver reads at
        // call time, not at parameter-construction time).
        let secondRead = ParameterResolver.resolve(parameter, from: defaults)
        XCTAssertEqual(secondRead, 4.0, accuracy: 0.0001)
    }
}

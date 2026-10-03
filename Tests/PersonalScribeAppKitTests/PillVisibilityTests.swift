import XCTest
import PersonalScribeCore
@testable import PersonalScribeAppKit

/// Tests for `PillVisibility` — the three-way pill visibility toggle
/// prescribed by
/// `plans/seshat_agent_bundle/03_Surfaces/PillOverlayWindow/architecture.png`.
///
/// Persistence contract: UserDefaults key `"PillVisibilityMode"` (preserved
/// across the type rename for backward compatibility), default `"auto-show"`
/// on first launch. This file tests the raw-value mapping, resolver
/// behaviour, and default.
final class PillVisibilityTests: XCTestCase {
    private let suiteName = "PersonalScribeTestsPillVisibility"

    private func isolatedDefaults() -> UserDefaults {
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        return defaults
    }

    // MARK: - Raw value stability

    func testRawValues() {
        XCTAssertEqual(PillVisibility.alwaysOn.rawValue, "always-on")
        XCTAssertEqual(PillVisibility.autoShow.rawValue, "auto-show")
    }

    func testInitFromRawValue() {
        XCTAssertEqual(PillVisibility(rawValue: "always-on"), .alwaysOn)
        XCTAssertEqual(PillVisibility(rawValue: "auto-show"), .autoShow)
        XCTAssertNil(PillVisibility(rawValue: "nonsense"))
    }

    // MARK: - Persistence key

    func testUserDefaultsKey() {
        XCTAssertEqual(PillVisibility.userDefaultsKey, "PillVisibilityMode")
    }

    // MARK: - Default on first launch

    func testDefaultIsAlwaysOn() {
        // First-launch default was auto-show matching the original mockup;
        // switched to always-on per user preference (dogfood feedback —
        // the pill is a useful visible affordance even between sessions).
        XCTAssertEqual(PillVisibility.default, .alwaysOn)
    }

    func testResolveReturnsAlwaysOnWhenKeyAbsent() {
        let defaults = isolatedDefaults()
        XCTAssertEqual(PillVisibility.resolve(from: defaults), .alwaysOn)
    }

    func testResolveReturnsAlwaysOnForUnrecognizedRawValue() {
        let defaults = isolatedDefaults()
        defaults.set("legacy-value", forKey: PillVisibility.userDefaultsKey)
        XCTAssertEqual(PillVisibility.resolve(from: defaults), .alwaysOn)
    }

    // MARK: - Round-trip

    func testPersistRoundTripAlwaysOn() {
        let defaults = isolatedDefaults()
        let preference = PillVisibility.preference(defaults: defaults)

        preference.persist(.alwaysOn)

        XCTAssertEqual(
            defaults.string(forKey: PillVisibility.userDefaultsKey),
            "always-on"
        )
        XCTAssertEqual(preference.resolve(), .alwaysOn)
        XCTAssertEqual(PillVisibility.resolve(from: defaults), .alwaysOn)
    }

    func testPersistRoundTripAutoShow() {
        let defaults = isolatedDefaults()
        PillVisibility.autoShow.persist(to: defaults)
        XCTAssertEqual(
            defaults.string(forKey: PillVisibility.userDefaultsKey),
            "auto-show"
        )
        XCTAssertEqual(PillVisibility.resolve(from: defaults), .autoShow)
    }

    // MARK: - Behaviour semantics

    func testCasesAreAlwaysOnAndAutoShow() {
        XCTAssertEqual(PillVisibility.allCases, [.alwaysOn, .autoShow])
    }
}

import XCTest
import PersonalScribeCore
@testable import PersonalScribeAppKit

/// Tests for `PillVisibilityMode` — the three-way pill visibility toggle
/// prescribed by
/// `plans/seshat_agent_bundle/03_Surfaces/PillOverlayWindow/architecture.png`.
///
/// Persistence contract: UserDefaults key `PillVisibilityMode`,
/// default `"auto-show"` on first launch. This file tests the raw-value
/// mapping, resolver behaviour, and default.
final class PillVisibilityModeTests: XCTestCase {
    private let suiteName = "PersonalScribeTestsPillVisibilityMode"

    private func isolatedDefaults() -> UserDefaults {
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        return defaults
    }

    // MARK: - Raw value stability

    func testRawValues() {
        XCTAssertEqual(PillVisibilityMode.alwaysOn.rawValue, "always-on")
        XCTAssertEqual(PillVisibilityMode.autoShow.rawValue, "auto-show")
        XCTAssertEqual(PillVisibilityMode.hidden.rawValue, "hidden")
    }

    func testInitFromRawValue() {
        XCTAssertEqual(PillVisibilityMode(rawValue: "always-on"), .alwaysOn)
        XCTAssertEqual(PillVisibilityMode(rawValue: "auto-show"), .autoShow)
        XCTAssertEqual(PillVisibilityMode(rawValue: "hidden"), .hidden)
        XCTAssertNil(PillVisibilityMode(rawValue: "nonsense"))
    }

    // MARK: - Persistence key

    func testUserDefaultsKey() {
        XCTAssertEqual(PillVisibilityMode.userDefaultsKey, "PillVisibilityMode")
    }

    // MARK: - Default on first launch

    func testResolveReturnsAutoShowWhenKeyAbsent() {
        let defaults = isolatedDefaults()
        XCTAssertEqual(PillVisibilityMode.resolve(from: defaults), .autoShow)
    }

    func testResolveReturnsAutoShowForUnrecognizedRawValue() {
        let defaults = isolatedDefaults()
        defaults.set("legacy-value", forKey: PillVisibilityMode.userDefaultsKey)
        XCTAssertEqual(PillVisibilityMode.resolve(from: defaults), .autoShow)
    }

    // MARK: - Round-trip

    func testPersistRoundTripAlwaysOn() {
        let defaults = isolatedDefaults()
        let preference = PillVisibilityMode.preference(defaults: defaults)

        preference.persist(.alwaysOn)

        XCTAssertEqual(
            defaults.string(forKey: PillVisibilityMode.userDefaultsKey),
            "always-on"
        )
        XCTAssertEqual(preference.resolve(), .alwaysOn)
        XCTAssertEqual(PillVisibilityMode.resolve(from: defaults), .alwaysOn)
    }

    func testPersistRoundTripHidden() {
        let defaults = isolatedDefaults()
        PillVisibilityMode.hidden.persist(to: defaults)
        XCTAssertEqual(
            defaults.string(forKey: PillVisibilityMode.userDefaultsKey),
            "hidden"
        )
        XCTAssertEqual(PillVisibilityMode.resolve(from: defaults), .hidden)
    }

    func testPersistRoundTripAutoShow() {
        let defaults = isolatedDefaults()
        PillVisibilityMode.autoShow.persist(to: defaults)
        XCTAssertEqual(
            defaults.string(forKey: PillVisibilityMode.userDefaultsKey),
            "auto-show"
        )
        XCTAssertEqual(PillVisibilityMode.resolve(from: defaults), .autoShow)
    }

    // MARK: - Behaviour semantics

    func testAllCasesAreCovered() {
        // Guard against an accidental case being added without tests.
        XCTAssertEqual(PillVisibilityMode.allCases.count, 3)
        XCTAssertTrue(PillVisibilityMode.allCases.contains(.alwaysOn))
        XCTAssertTrue(PillVisibilityMode.allCases.contains(.autoShow))
        XCTAssertTrue(PillVisibilityMode.allCases.contains(.hidden))
    }
}

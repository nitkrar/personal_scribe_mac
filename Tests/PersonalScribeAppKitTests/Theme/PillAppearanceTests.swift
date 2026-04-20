import AppKit
import XCTest
@testable import PersonalScribeAppKit

/// Tests for `PillAppearance` — the user-selectable floating-pill
/// appearance (Dark / Light / System). Reference:
/// `plans/App UI design/Claude_Final_Bundle_Prompt.md` §1 and the
/// `SeshatTheme.swift` drop-in (adopted verbatim, type/key names
/// adjusted per project naming rule — no "Seshat" prefix).
final class PillAppearanceTests: XCTestCase {
    // MARK: - Cases + UserDefaults round-trip

    func testCasesInclude_Dark_Light_System() {
        XCTAssertEqual(PillAppearance.allCases, [.dark, .light, .system])
    }

    func testDefaultResolvesToDark() {
        let defaults = Self.isolatedDefaults()
        XCTAssertEqual(PillAppearance.resolve(from: defaults), .dark)
    }

    func testResolveReadsPersistedLight() {
        let defaults = Self.isolatedDefaults()
        PillAppearance.light.persist(to: defaults)
        XCTAssertEqual(PillAppearance.resolve(from: defaults), .light)
    }

    func testResolveReadsPersistedSystem() {
        let defaults = Self.isolatedDefaults()
        PillAppearance.system.persist(to: defaults)
        XCTAssertEqual(PillAppearance.resolve(from: defaults), .system)
    }

    func testResolveFallsBackToDarkOnInvalidValue() {
        let defaults = Self.isolatedDefaults()
        defaults.set("NotAnAppearance", forKey: PillAppearance.userDefaultsKey)
        XCTAssertEqual(PillAppearance.resolve(from: defaults), .dark)
    }

    func testPersistWritesRawValue() {
        let defaults = Self.isolatedDefaults()
        PillAppearance.light.persist(to: defaults)
        XCTAssertEqual(
            defaults.string(forKey: PillAppearance.userDefaultsKey),
            "Light"
        )
    }

    func testUserDefaultsKeyHasNoPrefix() {
        XCTAssertEqual(PillAppearance.userDefaultsKey, "PillAppearance")
    }

    // MARK: - effectiveIsDark (core logic)

    func testEffectiveIsDarkForDarkCaseIgnoresSystem() {
        XCTAssertTrue(PillAppearance.dark.effectiveIsDark(systemIsDark: false))
        XCTAssertTrue(PillAppearance.dark.effectiveIsDark(systemIsDark: true))
    }

    func testEffectiveIsDarkForLightCaseIgnoresSystem() {
        XCTAssertFalse(PillAppearance.light.effectiveIsDark(systemIsDark: false))
        XCTAssertFalse(PillAppearance.light.effectiveIsDark(systemIsDark: true))
    }

    func testEffectiveIsDarkForSystemCaseFollowsSystem() {
        XCTAssertTrue(PillAppearance.system.effectiveIsDark(systemIsDark: true))
        XCTAssertFalse(PillAppearance.system.effectiveIsDark(systemIsDark: false))
    }

    // MARK: - nsAppearance

    func testNSAppearanceForDarkReturnsDarkAqua() {
        let appearance = PillAppearance.dark.nsAppearance(systemIsDark: false)
        XCTAssertEqual(appearance?.name, .darkAqua)
    }

    func testNSAppearanceForLightReturnsAqua() {
        let appearance = PillAppearance.light.nsAppearance(systemIsDark: true)
        XCTAssertEqual(appearance?.name, .aqua)
    }

    func testNSAppearanceForSystemReturnsNil() {
        XCTAssertNil(PillAppearance.system.nsAppearance(systemIsDark: true))
        XCTAssertNil(PillAppearance.system.nsAppearance(systemIsDark: false))
    }

    // MARK: - Helpers

    private static func isolatedDefaults() -> UserDefaults {
        let suiteName = "PillAppearanceTests-\(UUID().uuidString)"
        guard let defaults = UserDefaults(suiteName: suiteName) else {
            fatalError("Could not create isolated UserDefaults for test")
        }
        defaults.removePersistentDomain(forName: suiteName)
        return defaults
    }
}

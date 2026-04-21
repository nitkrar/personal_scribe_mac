import AppKit
import SwiftUI
import XCTest
@testable import PersonalScribeAppKit

/// Tests for `AppTheme` — the master app-level theme picker
/// (Light / Dark / System) introduced as part of mockup-gaps G to
/// retire the double-duty `WindowTint.dark` case.
///
/// Pattern borrowed verbatim from `PillAppearanceTests.swift` — raw
/// values, UserDefaults roundtrip, default-resolution, and the
/// `effectiveScheme` × `nsAppearance` truth matrices.
final class AppThemeTests: XCTestCase {
    // MARK: - Cases + UserDefaults round-trip

    func testCasesInclude_Light_Dark_System() {
        XCTAssertEqual(AppTheme.allCases, [.light, .dark, .system])
    }

    func testDefaultIsLight() {
        XCTAssertEqual(AppTheme.default, .light)
    }

    func testResolveFallsBackToDefaultWhenDefaultsEmpty() {
        let defaults = Self.isolatedDefaults()
        XCTAssertEqual(AppTheme.resolve(from: defaults), .light)
    }

    func testResolveReadsPersistedDark() {
        let defaults = Self.isolatedDefaults()
        AppTheme.dark.persist(to: defaults)
        XCTAssertEqual(AppTheme.resolve(from: defaults), .dark)
    }

    func testResolveReadsPersistedSystem() {
        let defaults = Self.isolatedDefaults()
        AppTheme.system.persist(to: defaults)
        XCTAssertEqual(AppTheme.resolve(from: defaults), .system)
    }

    func testResolveReadsPersistedLight() {
        let defaults = Self.isolatedDefaults()
        // Seed a different value first so .light isn't the "missing" fallback.
        AppTheme.dark.persist(to: defaults)
        AppTheme.light.persist(to: defaults)
        XCTAssertEqual(AppTheme.resolve(from: defaults), .light)
    }

    func testResolveFallsBackToDefaultOnInvalidValue() {
        let defaults = Self.isolatedDefaults()
        defaults.set("NotATheme", forKey: AppTheme.userDefaultsKey)
        XCTAssertEqual(AppTheme.resolve(from: defaults), .light)
    }

    func testPersistWritesRawValue() {
        let defaults = Self.isolatedDefaults()
        AppTheme.dark.persist(to: defaults)
        XCTAssertEqual(
            defaults.string(forKey: AppTheme.userDefaultsKey),
            "Dark"
        )
    }

    func testUserDefaultsKeyHasNoPrefix() {
        // Unprefixed per the PillAppearance / WindowTint convention —
        // the `com.nitkrar.personal_scribe` bundle already namespaces the
        // UserDefaults domain.
        XCTAssertEqual(AppTheme.userDefaultsKey, "AppTheme")
    }

    // MARK: - effectiveScheme matrix

    func testEffectiveSchemeForLightIgnoresSystem() {
        XCTAssertEqual(AppTheme.light.effectiveScheme(systemIsDark: false), .light)
        XCTAssertEqual(AppTheme.light.effectiveScheme(systemIsDark: true), .light)
    }

    func testEffectiveSchemeForDarkIgnoresSystem() {
        XCTAssertEqual(AppTheme.dark.effectiveScheme(systemIsDark: false), .dark)
        XCTAssertEqual(AppTheme.dark.effectiveScheme(systemIsDark: true), .dark)
    }

    func testEffectiveSchemeForSystemFollowsSystem() {
        XCTAssertEqual(AppTheme.system.effectiveScheme(systemIsDark: false), .light)
        XCTAssertEqual(AppTheme.system.effectiveScheme(systemIsDark: true), .dark)
    }

    // MARK: - nsAppearance matrix

    func testNSAppearanceForLightReturnsAqua() {
        XCTAssertEqual(AppTheme.light.nsAppearance(systemIsDark: false)?.name, .aqua)
        XCTAssertEqual(AppTheme.light.nsAppearance(systemIsDark: true)?.name, .aqua)
    }

    func testNSAppearanceForDarkReturnsDarkAqua() {
        XCTAssertEqual(AppTheme.dark.nsAppearance(systemIsDark: false)?.name, .darkAqua)
        XCTAssertEqual(AppTheme.dark.nsAppearance(systemIsDark: true)?.name, .darkAqua)
    }

    func testNSAppearanceForSystemReturnsNil() {
        XCTAssertNil(AppTheme.system.nsAppearance(systemIsDark: false))
        XCTAssertNil(AppTheme.system.nsAppearance(systemIsDark: true))
    }

    // MARK: - Helpers

    private static func isolatedDefaults() -> UserDefaults {
        let suiteName = "AppThemeTests-\(UUID().uuidString)"
        guard let defaults = UserDefaults(suiteName: suiteName) else {
            fatalError("Could not create isolated UserDefaults for test")
        }
        defaults.removePersistentDomain(forName: suiteName)
        return defaults
    }
}

import XCTest
@testable import PersonalScribeAppKit

/// Tests for `ShowInDockPreference` — the bool-backed "Show in Dock"
/// preference added in mockup-gaps D.2 alongside the APPLICATION
/// Settings section. Follows `PillAppearanceTests.swift` pattern
/// (isolated `UserDefaults` suites per test).
final class ShowInDockPreferenceTests: XCTestCase {
    func testDefaultIsTrue() {
        XCTAssertTrue(ShowInDockPreference.default)
    }

    func testResolveReturnsDefaultWhenKeyAbsent() {
        let defaults = Self.isolatedDefaults()
        XCTAssertTrue(ShowInDockPreference.resolve(from: defaults))
    }

    func testResolveReadsPersistedTrue() {
        let defaults = Self.isolatedDefaults()
        ShowInDockPreference.persist(true, to: defaults)
        XCTAssertTrue(ShowInDockPreference.resolve(from: defaults))
    }

    func testResolveReadsPersistedFalse() {
        let defaults = Self.isolatedDefaults()
        ShowInDockPreference.persist(false, to: defaults)
        XCTAssertFalse(ShowInDockPreference.resolve(from: defaults))
    }

    /// `UserDefaults.bool(forKey:)` returns `false` on absent keys —
    /// `resolve(from:)` must distinguish "never set" from
    /// "explicitly false" so an unmodified install still shows the
    /// Dock icon.
    func testResolveDistinguishesUnsetFromExplicitFalse() {
        let defaults = Self.isolatedDefaults()

        // Unset — defaults to true.
        XCTAssertTrue(ShowInDockPreference.resolve(from: defaults))

        // Explicitly false — now false.
        ShowInDockPreference.persist(false, to: defaults)
        XCTAssertFalse(ShowInDockPreference.resolve(from: defaults))
    }

    func testPersistWritesBool() {
        let defaults = Self.isolatedDefaults()
        ShowInDockPreference.persist(false, to: defaults)
        XCTAssertEqual(
            defaults.object(forKey: ShowInDockPreference.userDefaultsKey) as? Bool,
            false
        )
    }

    func testUserDefaultsKeyHasNoPrefix() {
        XCTAssertEqual(ShowInDockPreference.userDefaultsKey, "ShowInDock")
    }

    private static func isolatedDefaults() -> UserDefaults {
        let suiteName = "ShowInDockPreferenceTests-\(UUID().uuidString)"
        guard let defaults = UserDefaults(suiteName: suiteName) else {
            fatalError("Could not create isolated UserDefaults for test")
        }
        defaults.removePersistentDomain(forName: suiteName)
        return defaults
    }
}

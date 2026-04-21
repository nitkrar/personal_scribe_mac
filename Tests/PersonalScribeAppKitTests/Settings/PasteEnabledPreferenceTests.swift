import XCTest
@testable import PersonalScribeAppKit

/// Tests for `PasteEnabledPreference` — the master "paste result text"
/// toggle added in mockup-gaps D.3 alongside the TEXT INPUT Settings
/// section. Same pattern as `ShowInDockPreferenceTests`.
final class PasteEnabledPreferenceTests: XCTestCase {
    func testDefaultIsTrue() {
        XCTAssertTrue(PasteEnabledPreference.default)
    }

    func testResolveReturnsDefaultWhenKeyAbsent() {
        let defaults = Self.isolatedDefaults()
        XCTAssertTrue(PasteEnabledPreference.resolve(from: defaults))
    }

    func testResolveReadsPersistedTrue() {
        let defaults = Self.isolatedDefaults()
        PasteEnabledPreference.persist(true, to: defaults)
        XCTAssertTrue(PasteEnabledPreference.resolve(from: defaults))
    }

    func testResolveReadsPersistedFalse() {
        let defaults = Self.isolatedDefaults()
        PasteEnabledPreference.persist(false, to: defaults)
        XCTAssertFalse(PasteEnabledPreference.resolve(from: defaults))
    }

    func testResolveDistinguishesUnsetFromExplicitFalse() {
        let defaults = Self.isolatedDefaults()

        XCTAssertTrue(PasteEnabledPreference.resolve(from: defaults))

        PasteEnabledPreference.persist(false, to: defaults)
        XCTAssertFalse(PasteEnabledPreference.resolve(from: defaults))
    }

    func testPersistWritesBool() {
        let defaults = Self.isolatedDefaults()
        PasteEnabledPreference.persist(false, to: defaults)
        XCTAssertEqual(
            defaults.object(forKey: PasteEnabledPreference.userDefaultsKey) as? Bool,
            false
        )
    }

    func testUserDefaultsKeyHasNoPrefix() {
        XCTAssertEqual(PasteEnabledPreference.userDefaultsKey, "PasteEnabled")
    }

    private static func isolatedDefaults() -> UserDefaults {
        let suiteName = "PasteEnabledPreferenceTests-\(UUID().uuidString)"
        guard let defaults = UserDefaults(suiteName: suiteName) else {
            fatalError("Could not create isolated UserDefaults for test")
        }
        defaults.removePersistentDomain(forName: suiteName)
        return defaults
    }
}

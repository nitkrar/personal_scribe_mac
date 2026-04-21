import AppKit
import XCTest
@testable import PersonalScribeCore

final class HotkeyPreferenceTests: XCTestCase {
    private let suiteName = "PersonalScribeTestsHotkeyPreference"

    private func isolatedDefaults() -> UserDefaults {
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        return defaults
    }

    func testResolveReturnsOptSlashDefaultWhenKeyAbsent() {
        let defaults = isolatedDefaults()

        // Pill UX spec §3 (2026-04-21): default hotkey is `opt + /`.
        // keyCode 44 is the `/` key on a US keyboard; tapCount `1`
        // means single-tap (tap count is retained for Codable
        // compatibility but ignored by the monitor, which now handles
        // tap / hold / double-tap-debounce uniformly).
        XCTAssertEqual(
            HotkeyPreference.resolve(from: defaults),
            .default
        )
        XCTAssertEqual(
            HotkeyPreference.default,
            HotkeyPreference(
                keyCode: 44,
                tapCount: 1,
                modifiers: NSEvent.ModifierFlags.option.rawValue
            )
        )
    }

    func testPersistRoundTrip() {
        let defaults = isolatedDefaults()
        let preference = HotkeyPreference(
            keyCode: 1,
            tapCount: 1,
            modifiers: NSEvent.ModifierFlags.command.union(.shift).rawValue
        )

        HotkeyPreference.preference(defaults: defaults).persist(preference)

        XCTAssertNotNil(defaults.data(forKey: HotkeyPreference.userDefaultsKey))
        XCTAssertEqual(HotkeyPreference.preference(defaults: defaults).resolve(), preference)
        XCTAssertEqual(HotkeyPreference.resolve(from: defaults), preference)
    }

    func testResolveReturnsDefaultWhenStoredValueHasInvalidType() {
        let defaults = isolatedDefaults()
        defaults.set("legacy", forKey: HotkeyPreference.userDefaultsKey)

        XCTAssertEqual(
            HotkeyPreference.resolve(from: defaults),
            .default
        )
    }

    func testCodableRoundTrip() throws {
        let preference = HotkeyPreference(
            keyCode: 49,
            tapCount: 1,
            modifiers: NSEvent.ModifierFlags.option.rawValue
        )

        let data = try JSONEncoder().encode(preference)
        let decoded = try JSONDecoder().decode(HotkeyPreference.self, from: data)

        XCTAssertEqual(decoded, preference)
    }

    func testUserDefaultsKeyDropsSeshatPrefix() {
        XCTAssertEqual(HotkeyPreference.userDefaultsKey, "RecordingHotkey")
    }
}

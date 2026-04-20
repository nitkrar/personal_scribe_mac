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

    func testResolveReturnsDefaultDoubleTapRightOptionWhenKeyAbsent() {
        let defaults = isolatedDefaults()

        XCTAssertEqual(
            HotkeyPreference.resolve(from: defaults),
            .default
        )
        XCTAssertEqual(
            HotkeyPreference.default,
            HotkeyPreference(keyCode: 61, tapCount: 2, modifiers: 0)
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

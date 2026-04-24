import AppKit
import XCTest
import PersonalScribeCore
@testable import PersonalScribeAppKit

final class SystemHotkeyRegistryTests: XCTestCase {

    func testParsesFixturePlistToExpectedShortcuts() {
        let fixture: [String: Any] = [
            "AppleSymbolicHotKeys": [
                // Spotlight — Cmd+Space, enabled. cmd raw = 1 << 20 = 1048576.
                "64": [
                    "enabled": true,
                    "value": [
                        "parameters": [32, 49, 1048576],
                        "type": "standard",
                    ],
                ],
                // Mission Control — Ctrl+Up, disabled. ctrl raw = 1 << 18 = 262144.
                "32": [
                    "enabled": false,
                    "value": [
                        "parameters": [65535, 126, 262144],
                        "type": "standard",
                    ],
                ],
                // Modifier value carries extra noise bits (e.g., caps lock 1<<16,
                // numericPad 1<<21) — should be filtered to the 4 chord modifiers.
                "184": [
                    "enabled": true,
                    "value": [
                        "parameters": [0, 20, 1048576 | 524288 | 65536 | 2097152],  // cmd + opt + caps + numpad
                        "type": "standard",
                    ],
                ],
                // Entry with sentinel keyCode (0xFFFF) — no binding assigned; skip.
                "160": [
                    "enabled": true,
                    "value": [
                        "parameters": [0, 0xFFFF, 0],
                        "type": "standard",
                    ],
                ],
                // Non-standard type (e.g., button) — skip.
                "200": [
                    "enabled": true,
                    "value": [
                        "parameters": [0, 49, 0],
                        "type": "button",
                    ],
                ],
            ],
        ]

        let hotkeys = SystemHotkeyRegistry.parse(fixture)

        XCTAssertEqual(hotkeys.count, 3, "Expected 3 standard entries; sentinel + non-standard skipped")

        let spotlight = hotkeys.first { $0.identifier == 64 }
        XCTAssertNotNil(spotlight)
        XCTAssertEqual(spotlight?.keyCode, 49)
        XCTAssertEqual(spotlight?.modifiers, [.command])
        XCTAssertTrue(spotlight?.isEnabled == true)

        let missionControl = hotkeys.first { $0.identifier == 32 }
        XCTAssertNotNil(missionControl)
        XCTAssertEqual(missionControl?.keyCode, 126)
        XCTAssertEqual(missionControl?.modifiers, [.control])
        XCTAssertTrue(missionControl?.isEnabled == false)

        let screenshot = hotkeys.first { $0.identifier == 184 }
        XCTAssertNotNil(screenshot)
        XCTAssertEqual(
            screenshot?.modifiers,
            [.command, .option],
            "Caps lock + numeric pad bits should be filtered out"
        )
    }

    func testMissingPlistReturnsEmptySet() {
        let nonexistent = URL(fileURLWithPath: "/var/tmp/ninimma-nonexistent-\(UUID().uuidString).plist")
        XCTAssertEqual(SystemHotkeyRegistry.load(from: nonexistent), [])
    }

    func testCollisionIdentifiesEnabledAndDisabledHotkeys() {
        let hotkeys: [SystemHotkey] = [
            SystemHotkey(
                identifier: 64,
                keyCode: 49,
                modifiers: [.command],
                isEnabled: true,
                displayName: "Spotlight"
            ),
            SystemHotkey(
                identifier: 32,
                keyCode: 126,
                modifiers: [.control],
                isEnabled: false,
                displayName: "Mission Control"
            ),
        ]

        let cmdSpace = HotkeyPreference(
            keyCode: 49,
            tapCount: 1,
            modifiers: NSEvent.ModifierFlags.command.rawValue
        )
        XCTAssertEqual(
            SystemHotkeyRegistry.collision(for: cmdSpace, against: hotkeys),
            .enabled(name: "Spotlight")
        )

        let ctrlUp = HotkeyPreference(
            keyCode: 126,
            tapCount: 1,
            modifiers: NSEvent.ModifierFlags.control.rawValue
        )
        XCTAssertEqual(
            SystemHotkeyRegistry.collision(for: ctrlUp, against: hotkeys),
            .disabled(name: "Mission Control")
        )

        let unused = HotkeyPreference(
            keyCode: 44,
            tapCount: 1,
            modifiers: NSEvent.ModifierFlags.option.rawValue
        )
        XCTAssertNil(SystemHotkeyRegistry.collision(for: unused, against: hotkeys))
    }
}

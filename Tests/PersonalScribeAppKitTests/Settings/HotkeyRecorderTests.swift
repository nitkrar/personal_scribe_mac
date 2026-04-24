import AppKit
import XCTest
import PersonalScribeCore
@testable import PersonalScribeAppKit

@MainActor
final class HotkeyRecorderTests: XCTestCase {
    private let suiteName = "HotkeyRecorderTests"

    private func isolatedDefaults() -> UserDefaults {
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        return defaults
    }

    func testCaptureKeypressEventAndUpdatesPreferenceOnConfirm() throws {
        let defaults = isolatedDefaults()
        let model = HotkeyRecorderModel(
            onConfirm: {
                HotkeyPreference.preference(defaults: defaults).persist($0)
            },
            onCancel: { }
        )

        try model.handle(event: makeKeyDownEvent(
            keyCode: 15,
            modifierFlags: [.command, .shift],
            characters: "R",
            timestamp: 1.0
        ))

        let expectedPreference = HotkeyPreference(
            keyCode: 15,
            tapCount: 1,
            modifiers: NSEvent.ModifierFlags.command.union(.shift).rawValue
        )
        XCTAssertEqual(model.captureResult, .captured(expectedPreference))

        model.confirm()

        XCTAssertEqual(HotkeyPreference.resolve(from: defaults), expectedPreference)
    }

    func testRejectsCommandSpaceWithReason() throws {
        let model = HotkeyRecorderModel(onConfirm: { _ in }, onCancel: { })

        try model.handle(event: makeKeyDownEvent(
            keyCode: 49,
            modifierFlags: [.command],
            characters: " ",
            timestamp: 1.0
        ))

        guard case let .rejected(reason) = model.captureResult else {
            return XCTFail("Expected rejected capture result")
        }

        XCTAssertTrue(reason.contains("Cmd+Space"))
    }

    func testCaptureRejectsEscapeWithInAppReservedReason() throws {
        let model = HotkeyRecorderModel(onConfirm: { _ in }, onCancel: { })

        try model.handle(event: makeKeyDownEvent(
            keyCode: 53,
            modifierFlags: [.command],
            characters: "\u{1B}",
            timestamp: 1.0
        ))

        guard case let .rejected(reason) = model.captureResult else {
            return XCTFail("Expected rejected capture result for Cmd+Esc")
        }

        XCTAssertTrue(
            reason.contains("Escape"),
            "Expected rejection reason to reference Escape, got: \(reason)"
        )
    }

    func testRejectsModifierOnlyChordWithReason() throws {
        let model = HotkeyRecorderModel(onConfirm: { _ in }, onCancel: { })

        try model.handle(event: makeFlagsChangedEvent(
            keyCode: 56,
            modifierFlags: [.shift],
            timestamp: 1.0
        ))

        guard case let .rejected(reason) = model.captureResult else {
            return XCTFail("Expected rejected capture result")
        }

        XCTAssertTrue(reason.contains("Modifier-only"))
    }

    func testRejectsShortcutThatMatchesEnabledSystemShortcut() throws {
        // Cmd+E isn't in the built-in rejection table, so routing depends
        // solely on the injected system-registry snapshot.
        let simulated = SystemHotkey(
            identifier: 75,
            keyCode: 14,
            modifiers: [.command],
            isEnabled: true,
            displayName: "Look up"
        )
        let model = HotkeyRecorderModel(
            onConfirm: { _ in },
            onCancel: { },
            systemHotkeys: [simulated]
        )

        try model.handle(event: makeKeyDownEvent(
            keyCode: 14,
            modifierFlags: [.command],
            characters: "E",
            timestamp: 1.0
        ))

        guard case let .rejected(reason) = model.captureResult else {
            return XCTFail("Expected rejection for Cmd+E matching enabled system shortcut")
        }
        XCTAssertTrue(
            reason.contains("Look up"),
            "Expected rejection to name the conflicting system shortcut; got: \(reason)"
        )
        XCTAssertFalse(model.canConfirm)
    }

    func testCapturesWithWarningWhenSystemShortcutIsDisabled() throws {
        let disabled = SystemHotkey(
            identifier: 32,
            keyCode: 126,
            modifiers: [.control],
            isEnabled: false,
            displayName: "Mission Control"
        )
        let model = HotkeyRecorderModel(
            onConfirm: { _ in },
            onCancel: { },
            systemHotkeys: [disabled]
        )

        try model.handle(event: makeKeyDownEvent(
            keyCode: 126,
            modifierFlags: [.control],
            characters: "",
            timestamp: 1.0
        ))

        guard case let .capturedWithWarning(preference, warning) = model.captureResult else {
            return XCTFail("Expected capturedWithWarning for disabled system-shortcut match")
        }
        XCTAssertEqual(preference.keyCode, 126)
        XCTAssertTrue(
            warning.contains("Mission Control") && warning.contains("disabled"),
            "Expected warning to name the shortcut + mention disabled state; got: \(warning)"
        )
        XCTAssertTrue(model.canConfirm, "Warning state must still allow Set")
        XCTAssertEqual(model.warningMessage, warning)
    }

    private func makeKeyDownEvent(
        keyCode: UInt16,
        modifierFlags: NSEvent.ModifierFlags,
        characters: String,
        timestamp: TimeInterval
    ) throws -> NSEvent {
        try XCTUnwrap(
            NSEvent.keyEvent(
                with: .keyDown,
                location: .zero,
                modifierFlags: modifierFlags,
                timestamp: timestamp,
                windowNumber: 0,
                context: nil,
                characters: characters,
                charactersIgnoringModifiers: characters.lowercased(),
                isARepeat: false,
                keyCode: keyCode
            )
        )
    }

    private func makeFlagsChangedEvent(
        keyCode: UInt16,
        modifierFlags: NSEvent.ModifierFlags,
        timestamp: TimeInterval
    ) throws -> NSEvent {
        try XCTUnwrap(
            NSEvent.keyEvent(
                with: .flagsChanged,
                location: .zero,
                modifierFlags: modifierFlags,
                timestamp: timestamp,
                windowNumber: 0,
                context: nil,
                characters: "",
                charactersIgnoringModifiers: "",
                isARepeat: false,
                keyCode: keyCode
            )
        )
    }
}

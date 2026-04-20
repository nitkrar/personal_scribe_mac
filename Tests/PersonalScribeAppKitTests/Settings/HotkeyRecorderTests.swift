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

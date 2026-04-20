import XCTest
import PersonalScribeCore
@testable import PersonalScribeAppKit

/// Tests for the Microphone submenu contract added in M5.3
/// (`plans/App UI design/Manus_Final_Bundle_Prompt.md` §2).
///
/// The submenu is inserted between the `Paste Last Transcript` action
/// and the separator before `Check for Updates…`; it is omitted
/// entirely when no devices are discoverable so the rest of the menu
/// stays identical to the M5.2 baseline asserted in
/// `StatusItemMenuModelTests`.
@MainActor
final class StatusItemMenuModelSubmenuTests: XCTestCase {
    // MARK: - Empty devices → no submenu

    func testNoSubmenuWhenInputDevicesEmpty() {
        let model = StatusItemMenuModel.makeUnified(
            sessionState: .idle,
            micPermission: .granted,
            inputMonitoringPermission: .granted,
            activeModeName: ModeRegistry.dictation.name,
            inputDevices: [],
            currentInputDeviceID: nil
        )

        XCTAssertFalse(
            model.items.contains(where: { item in
                if case .submenu = item { return true } else { return false }
            }),
            "Empty device list must omit the submenu entirely"
        )
        // The M5.2 baseline shape (9 items) must not drift when no
        // devices are discoverable.
        XCTAssertEqual(model.items.count, 9)
    }

    // MARK: - Parent title reflects current selection

    func testSubmenuTitleIsCurrentDeviceName() {
        let devices = [
            AudioInputDevice(id: "uid-builtin", name: "MacBook Pro Microphone"),
            AudioInputDevice(id: "uid-ext", name: "Shure MV7"),
        ]
        let model = StatusItemMenuModel.makeUnified(
            sessionState: .idle,
            micPermission: .granted,
            inputMonitoringPermission: .granted,
            activeModeName: ModeRegistry.dictation.name,
            inputDevices: devices,
            currentInputDeviceID: "uid-ext"
        )

        let submenu = extractSubmenu(from: model)
        XCTAssertEqual(submenu.title, "Shure MV7")
    }

    func testSubmenuTitleIsMicrophoneFallbackWhenNoneSelected() {
        let devices = [
            AudioInputDevice(id: "uid-builtin", name: "MacBook Pro Microphone"),
        ]
        let model = StatusItemMenuModel.makeUnified(
            sessionState: .idle,
            micPermission: .granted,
            inputMonitoringPermission: .granted,
            activeModeName: ModeRegistry.dictation.name,
            inputDevices: devices,
            currentInputDeviceID: nil
        )

        let submenu = extractSubmenu(from: model)
        XCTAssertEqual(submenu.title, "Microphone")
    }

    func testSubmenuTitleFallsBackWhenSelectedDeviceNoLongerPresent() {
        // Hotplug edge: user previously selected a USB mic (persisted
        // in UserDefaults) and then unplugged it. The submenu should
        // not claim the stale device's name as the parent title.
        let devices = [
            AudioInputDevice(id: "uid-builtin", name: "MacBook Pro Microphone"),
        ]
        let model = StatusItemMenuModel.makeUnified(
            sessionState: .idle,
            micPermission: .granted,
            inputMonitoringPermission: .granted,
            activeModeName: ModeRegistry.dictation.name,
            inputDevices: devices,
            currentInputDeviceID: "uid-unplugged"
        )

        let submenu = extractSubmenu(from: model)
        XCTAssertEqual(submenu.title, "Microphone")
    }

    // MARK: - Children + checkmark

    func testSubmenuHasOneChildPerDevice() {
        let devices = [
            AudioInputDevice(id: "uid-1", name: "MacBook Pro Microphone"),
            AudioInputDevice(id: "uid-2", name: "Shure MV7"),
            AudioInputDevice(id: "uid-3", name: "AirPods"),
        ]
        let model = StatusItemMenuModel.makeUnified(
            sessionState: .idle,
            micPermission: .granted,
            inputMonitoringPermission: .granted,
            activeModeName: ModeRegistry.dictation.name,
            inputDevices: devices,
            currentInputDeviceID: "uid-1"
        )

        let submenu = extractSubmenu(from: model)
        XCTAssertEqual(submenu.children.count, 3)
        XCTAssertEqual(submenu.children.map(\.deviceID), ["uid-1", "uid-2", "uid-3"])
        XCTAssertEqual(submenu.children.map(\.title), [
            "MacBook Pro Microphone",
            "Shure MV7",
            "AirPods",
        ])
    }

    func testActiveChildMatchesCurrentInputDeviceID() {
        let devices = [
            AudioInputDevice(id: "uid-1", name: "MacBook Pro Microphone"),
            AudioInputDevice(id: "uid-2", name: "Shure MV7"),
            AudioInputDevice(id: "uid-3", name: "AirPods"),
        ]
        let model = StatusItemMenuModel.makeUnified(
            sessionState: .idle,
            micPermission: .granted,
            inputMonitoringPermission: .granted,
            activeModeName: ModeRegistry.dictation.name,
            inputDevices: devices,
            currentInputDeviceID: "uid-2"
        )

        let submenu = extractSubmenu(from: model)
        let activeChildren = submenu.children.filter(\.isActive)
        XCTAssertEqual(activeChildren.count, 1)
        XCTAssertEqual(activeChildren.first?.deviceID, "uid-2")
    }

    func testNoChildIsActiveWhenSelectionIsNil() {
        let devices = [
            AudioInputDevice(id: "uid-1", name: "MacBook Pro Microphone"),
            AudioInputDevice(id: "uid-2", name: "Shure MV7"),
        ]
        let model = StatusItemMenuModel.makeUnified(
            sessionState: .idle,
            micPermission: .granted,
            inputMonitoringPermission: .granted,
            activeModeName: ModeRegistry.dictation.name,
            inputDevices: devices,
            currentInputDeviceID: nil
        )

        let submenu = extractSubmenu(from: model)
        XCTAssertTrue(submenu.children.allSatisfy { !$0.isActive })
    }

    func testSubmenuParentCarriesMicIcon() {
        let devices = [
            AudioInputDevice(id: "uid-1", name: "MacBook Pro Microphone"),
        ]
        let model = StatusItemMenuModel.makeUnified(
            sessionState: .idle,
            micPermission: .granted,
            inputMonitoringPermission: .granted,
            activeModeName: ModeRegistry.dictation.name,
            inputDevices: devices,
            currentInputDeviceID: "uid-1"
        )

        let submenu = extractSubmenu(from: model)
        XCTAssertEqual(submenu.iconName, "mic")
    }

    // MARK: - Position inside the menu

    /// The submenu must land between the `Paste Last Transcript`
    /// action and the separator preceding `Check for Updates…`. The
    /// M5.2 baseline has 9 items: [brand, mode, Home, ---, Start,
    /// Paste, ---, Check, Quit]. M5.3 adds `[---, submenu]` between
    /// index 5 (Paste) and the existing separator at index 6, so the
    /// new layout is 11 items with the submenu at index 7.
    func testSubmenuIsInsertedBetweenPasteLastTranscriptAndCheckForUpdates() {
        let devices = [
            AudioInputDevice(id: "uid-1", name: "MacBook Pro Microphone"),
        ]
        let model = StatusItemMenuModel.makeUnified(
            sessionState: .idle,
            micPermission: .granted,
            inputMonitoringPermission: .granted,
            activeModeName: ModeRegistry.dictation.name,
            inputDevices: devices,
            currentInputDeviceID: "uid-1"
        )

        XCTAssertEqual(model.items.count, 11)

        // Paste Last Transcript sits at index 5 (same as M5.2).
        guard case let .action(paste) = model.items[5] else {
            return XCTFail("Expected Paste Last Transcript action at index 5")
        }
        XCTAssertEqual(paste.id, .pasteLastTranscript)

        // New separator + submenu at 6 / 7.
        XCTAssertEqual(model.items[6], .separator)
        guard case .submenu = model.items[7] else {
            return XCTFail("Expected microphone submenu at index 7")
        }

        // Then the existing separator and Check-for-Updates row.
        XCTAssertEqual(model.items[8], .separator)
        guard case let .action(check) = model.items[9] else {
            return XCTFail("Expected Check for Updates action at index 9")
        }
        XCTAssertEqual(check.id, .checkForUpdates)

        // Quit still terminates the menu.
        guard case let .action(quit) = model.items[10] else {
            return XCTFail("Expected Quit action at index 10")
        }
        XCTAssertEqual(quit.id, .quit)
    }

    // MARK: - Helpers

    private struct ExtractedSubmenu {
        let title: String
        let iconName: String?
        let children: [StatusItemMenuModel.SubmenuChild]
    }

    private func extractSubmenu(
        from model: StatusItemMenuModel,
        file: StaticString = #filePath,
        line: UInt = #line
    ) -> ExtractedSubmenu {
        for item in model.items {
            if case let .submenu(title, iconName, children) = item {
                return ExtractedSubmenu(title: title, iconName: iconName, children: children)
            }
        }
        XCTFail("Expected a submenu in model", file: file, line: line)
        return ExtractedSubmenu(title: "", iconName: nil, children: [])
    }
}

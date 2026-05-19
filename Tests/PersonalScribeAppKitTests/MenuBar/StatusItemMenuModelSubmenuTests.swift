import XCTest
import PersonalScribeCore
@testable import PersonalScribeAppKit

/// Tests for the Microphone submenu contract added in M5.3
/// (`plans/App UI design/Manus_Final_Bundle_Prompt.md` §2).
///
/// The submenu is inserted between the `Copy Last Transcript` action
/// and `Quit`; it is omitted entirely when no devices are
/// discoverable so the rest of the menu stays identical to the M5.2
/// baseline asserted in
/// `StatusItemMenuModelTests`.
@MainActor
final class StatusItemMenuModelSubmenuTests: XCTestCase {
    // MARK: - Empty devices → no submenu

    func testNoSubmenuWhenInputDevicesEmpty() {
        let model = StatusItemMenuModel.makeUnified(
            sessionState: .idle,
            micPermission: .granted,
            inputMonitoringPermission: .granted,
            activeModeName: WorkflowMode.dictation.name,
            inputDevices: [],
            currentInputDeviceID: nil
        )

        XCTAssertFalse(
            model.items.contains(where: { item in
                if case .submenu = item { return true } else { return false }
            }),
            "Empty device list must omit the submenu entirely"
        )
        // Baseline now includes "Retranscribe Last Recording" between
        // Copy and the trailing separator.
        XCTAssertEqual(model.items.count, 10)
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
            activeModeName: WorkflowMode.dictation.name,
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
            activeModeName: WorkflowMode.dictation.name,
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
            activeModeName: WorkflowMode.dictation.name,
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
            activeModeName: WorkflowMode.dictation.name,
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
            activeModeName: WorkflowMode.dictation.name,
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
            activeModeName: WorkflowMode.dictation.name,
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
            activeModeName: WorkflowMode.dictation.name,
            inputDevices: devices,
            currentInputDeviceID: "uid-1"
        )

        let submenu = extractSubmenu(from: model)
        XCTAssertEqual(submenu.iconName, "mic")
    }

    // MARK: - Position inside the menu

    /// The submenu must land between the `Copy Last Transcript`
    /// action and `Quit`. Post-#6+#16 baseline (mode active) is 9 items:
    /// [brand/mode, Home, History, Settings, ---, Start, Copy,
    ///  Retranscribe, ---, Quit].
    /// M5.3 adds the submenu after the trailing separator, so the layout
    /// becomes 11 items with the submenu at index 9 and Quit at index 10.
    func testSubmenuIsInsertedBetweenCopyLastTranscriptAndQuit() {
        let devices = [
            AudioInputDevice(id: "uid-1", name: "MacBook Pro Microphone"),
        ]
        let model = StatusItemMenuModel.makeUnified(
            sessionState: .idle,
            micPermission: .granted,
            inputMonitoringPermission: .granted,
            activeModeName: WorkflowMode.dictation.name,
            inputDevices: devices,
            currentInputDeviceID: "uid-1"
        )

        XCTAssertEqual(model.items.count, 11)

        // Copy Last Transcript sits at index 6 in the post-#6+#16 layout.
        guard case let .action(copy) = model.items[6] else {
            return XCTFail("Expected Copy Last Transcript action at index 6")
        }
        XCTAssertEqual(copy.id, .copyLastTranscript)

        guard case let .action(retranscribe) = model.items[7] else {
            return XCTFail("Expected Retranscribe Last Recording action at index 7")
        }
        XCTAssertEqual(retranscribe.id, .reTranscribeLastRecording)

        // Separator + submenu at 8 / 9.
        XCTAssertEqual(model.items[8], .separator)
        guard case .submenu = model.items[9] else {
            return XCTFail("Expected microphone submenu at index 9")
        }

        // Quit still terminates the menu.
        guard case let .action(quit) = model.items[10] else {
            return XCTFail("Expected Quit action at index 10")
        }
        XCTAssertEqual(quit.id, .quit)
    }

    // MARK: - Mode submenu (#068)

    func testModeSubmenuPresentWithChildrenAndActiveCheckmark() {
        let modes = [
            WorkflowMode.dictation,
            WorkflowMode(
                id: "command",
                name: "Command",
                pipelineShape: .batch,
                processors: [.transcriber(kind: .asr)],
                captureControllers: [.manualHotkey],
                outputSinks: [.frontmostPaste(enabled: .override(true))]
            ),
        ]
        let model = StatusItemMenuModel.makeUnified(
            sessionState: .idle,
            micPermission: .granted,
            inputMonitoringPermission: .granted,
            activeModeName: WorkflowMode.dictation.name,
            modes: modes,
            currentModeID: WorkflowMode.dictation.id
        )

        let modeSubmenu = extractModeSubmenu(from: model)
        XCTAssertEqual(modeSubmenu.title, WorkflowMode.dictation.name)
        XCTAssertEqual(modeSubmenu.iconName, "switch.2")
        XCTAssertEqual(modeSubmenu.children.map(\.modeID), [WorkflowMode.dictation.id, "command"])
        let activeChildren = modeSubmenu.children.filter(\.isActive)
        XCTAssertEqual(activeChildren.count, 1)
        XCTAssertEqual(activeChildren.first?.modeID, WorkflowMode.dictation.id)
    }

    func testNoModeSubmenuWhenModesEmpty() {
        let model = StatusItemMenuModel.makeUnified(
            sessionState: .idle,
            micPermission: .granted,
            inputMonitoringPermission: .granted,
            activeModeName: WorkflowMode.dictation.name,
            modes: [],
            currentModeID: nil
        )

        XCTAssertFalse(
            model.items.contains(where: { item in
                if case .modeSubmenu = item { return true } else { return false }
            }),
            "Empty modes list must omit the mode submenu entirely"
        )
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

    private struct ExtractedModeSubmenu {
        let title: String
        let iconName: String?
        let children: [StatusItemMenuModel.ModeSubmenuChild]
    }

    private func extractModeSubmenu(
        from model: StatusItemMenuModel,
        file: StaticString = #filePath,
        line: UInt = #line
    ) -> ExtractedModeSubmenu {
        for item in model.items {
            if case let .modeSubmenu(title, iconName, children) = item {
                return ExtractedModeSubmenu(title: title, iconName: iconName, children: children)
            }
        }
        XCTFail("Expected a mode submenu in model", file: file, line: line)
        return ExtractedModeSubmenu(title: "", iconName: nil, children: [])
    }
}

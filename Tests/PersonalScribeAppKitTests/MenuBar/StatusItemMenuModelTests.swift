import XCTest
import PersonalScribeCore
@testable import PersonalScribeAppKit

/// Tests for `StatusItemMenuModel` — the pure model describing the
/// status-bar NSMenu contents. Reference:
/// `plans/App UI design/Claude_Final_Bundle_Prompt.md` §2 (M5.1 layout).
@MainActor
final class StatusItemMenuModelTests: XCTestCase {
    // MARK: - Base structure

    /// M5.1 granted-mode baseline:
    ///
    /// ```
    /// [0] brand header (AppBrand.displayName)
    /// [1] mode header  (dictation)
    /// [2] Home                       house.fill
    /// [3] ---
    /// [4] Start Recording   ⌥⌥      waveform
    /// [5] Paste Last Transcript     doc.on.clipboard
    /// [6] ---
    /// [7] Check for Updates…        arrow.clockwise
    /// [8] Quit <displayName>        xmark.circle
    /// ```
    func testIdleGrantedMenuHasExpectedItemsInOrder() {
        let model = StatusItemMenuModel.makeUnified(
            sessionState: .idle,
            micPermission: .granted,
            inputMonitoringPermission: .granted,
            activeModeName: ModeRegistry.dictation.name
        )

        XCTAssertEqual(model.items.count, 9)
        assertHeader(model.items[0], AppBrand.displayName)
        assertHeader(model.items[1], ModeRegistry.dictation.name)
        assertAction(model.items[2], id: .openHome, title: "Home", iconName: "house.fill")
        XCTAssertEqual(model.items[3], .separator)
        assertAction(
            model.items[4],
            id: .startStopRecording,
            title: "Start Recording   ⌥⌥",
            iconName: "waveform"
        )
        assertAction(
            model.items[5],
            id: .pasteLastTranscript,
            title: "Paste Last Transcript",
            iconName: "doc.on.clipboard"
        )
        XCTAssertEqual(model.items[6], .separator)
        assertAction(
            model.items[7],
            id: .checkForUpdates,
            title: "Check for Updates…",
            iconName: "arrow.clockwise"
        )
        assertAction(
            model.items[8],
            id: .quit,
            title: "Quit \(AppBrand.displayName)",
            iconName: "xmark.circle"
        )
    }

    func testActiveModeNameIsReflectedInHeader() {
        let model = StatusItemMenuModel.makeUnified(
            sessionState: .idle,
            micPermission: .granted,
            inputMonitoringPermission: .granted,
            activeModeName: "Long-form"
        )
        // items[0] is the brand header; items[1] is the mode header.
        assertHeader(model.items[1], "Long-form")
    }

    // MARK: - Recording-toggle title switching

    func testRecordingStateSwitchesTitleToStop() {
        let model = StatusItemMenuModel.makeUnified(
            sessionState: .recording,
            micPermission: .granted,
            inputMonitoringPermission: .granted,
            activeModeName: ModeRegistry.dictation.name
        )
        // Start/Stop Recording sits at index 4 in the new layout.
        assertAction(
            model.items[4],
            id: .startStopRecording,
            title: "Stop Recording   ⌥⌥",
            iconName: "waveform"
        )
    }

    func testTranscribingStateDisablesRecordingItem() {
        let model = StatusItemMenuModel.makeUnified(
            sessionState: .transcribing,
            micPermission: .granted,
            inputMonitoringPermission: .granted,
            activeModeName: ModeRegistry.dictation.name
        )
        guard case let .action(item) = model.items[4] else {
            return XCTFail("Expected action at index 4")
        }
        XCTAssertEqual(item.id, .startStopRecording)
        XCTAssertEqual(item.title, "Transcribing…")
        XCTAssertFalse(item.isEnabled)
    }

    func testErrorStateShowsStartRecording() {
        let model = StatusItemMenuModel.makeUnified(
            sessionState: .error(.modelLoadFailure),
            micPermission: .granted,
            inputMonitoringPermission: .granted,
            activeModeName: ModeRegistry.dictation.name
        )
        assertAction(
            model.items[4],
            id: .startStopRecording,
            title: "Start Recording   ⌥⌥",
            iconName: "waveform"
        )
    }

    // MARK: - Permission warnings prepended

    func testDeniedMicrophonePrependsPermissionsNoteAndWarningItem() {
        let model = StatusItemMenuModel.makeUnified(
            sessionState: .idle,
            micPermission: .denied,
            inputMonitoringPermission: .granted
        )

        assertHeader(model.items[0], "Permissions needed before recording")
        guard case let .action(firstWarning) = model.items[1] else {
            return XCTFail("Expected second item to be a warning action")
        }
        XCTAssertEqual(firstWarning.id, .openMicrophoneSystemSettings)
        XCTAssertTrue(firstWarning.title.contains("Microphone"))
        XCTAssertTrue(firstWarning.isEnabled)
        XCTAssertEqual(model.items[2], .separator)
    }

    func testDeniedInputMonitoringPrependsPermissionsNoteAndWarningItem() {
        let model = StatusItemMenuModel.makeUnified(
            sessionState: .idle,
            micPermission: .granted,
            inputMonitoringPermission: .denied
        )

        assertHeader(model.items[0], "Permissions needed before recording")
        guard case let .action(firstWarning) = model.items[1] else {
            return XCTFail("Expected second item to be a warning action")
        }
        XCTAssertEqual(firstWarning.id, .openInputMonitoringSystemSettings)
        XCTAssertTrue(firstWarning.title.contains("Input Monitoring"))
        XCTAssertTrue(firstWarning.isEnabled)
        XCTAssertEqual(model.items[2], .separator)
    }

    func testBothPermissionsDeniedPrependsBothWarningsInOrder() {
        let model = StatusItemMenuModel.makeUnified(
            sessionState: .idle,
            micPermission: .denied,
            inputMonitoringPermission: .denied
        )

        assertHeader(model.items[0], "Permissions needed before recording")

        guard case let .action(first) = model.items[1] else {
            return XCTFail("Expected first warning to be Microphone")
        }
        XCTAssertEqual(first.id, .openMicrophoneSystemSettings)

        guard case let .action(second) = model.items[2] else {
            return XCTFail("Expected second warning to be Input Monitoring")
        }
        XCTAssertEqual(second.id, .openInputMonitoringSystemSettings)

        XCTAssertEqual(model.items[3], .separator)
    }

    func testPendingDoesNotPrependWarning() {
        // Fresh install: permission is still pending. The menu
        // should NOT show a warning before the user has even been
        // prompted — onboarding (Phase 3) covers that flow.
        let model = StatusItemMenuModel.makeUnified(
            sessionState: .idle,
            micPermission: .pending,
            inputMonitoringPermission: .pending,
            activeModeName: ModeRegistry.dictation.name
        )
        // First item is the brand header, not a warning.
        assertHeader(model.items[0], AppBrand.displayName)
        XCTAssertEqual(model.items.count, 9, "No warning items expected")
    }

    // MARK: - Action identifiers

    func testAllActionIdentifiersAreDistinct() {
        let model = StatusItemMenuModel.makeUnified(
            sessionState: .idle,
            micPermission: .denied,
            inputMonitoringPermission: .denied
        )
        let ids = model.items.compactMap { item -> StatusItemMenuModel.ActionID? in
            if case let .action(action) = item { return action.id }
            return nil
        }
        XCTAssertEqual(Set(ids).count, ids.count, "Action ids should be unique")
    }

    func testQuitItemHasCommandQKeyEquivalent() {
        let model = StatusItemMenuModel.makeUnified(
            sessionState: .idle,
            micPermission: .granted,
            inputMonitoringPermission: .granted,
            activeModeName: ModeRegistry.dictation.name
        )
        guard case let .action(quit) = model.items.last else {
            return XCTFail("Expected last item to be Quit action")
        }
        XCTAssertEqual(quit.id, .quit)
        XCTAssertEqual(quit.keyEquivalent, "q")
    }

    func testStartRecordingHasNoAppKitKeyEquivalent() {
        // The actual hotkey is a double-tap of right Option (see
        // GlobalHotkeyMonitor). AppKit's NSMenu can't bind that, so
        // no key-equivalent is published — the ⌥⌥ hint lives in the
        // title instead. Guards against re-introducing a wrong
        // shortcut like ⌥⌘R that doesn't actually trigger recording.
        let model = StatusItemMenuModel.makeUnified(
            sessionState: .idle,
            micPermission: .granted,
            inputMonitoringPermission: .granted,
            activeModeName: ModeRegistry.dictation.name
        )
        // Start/Stop Recording lives at index 4 in the M5.1 layout.
        guard case let .action(record) = model.items[4] else {
            return XCTFail("Expected record action at index 4")
        }
        XCTAssertEqual(record.keyEquivalent, "")
    }

    // MARK: - SF Symbol icons (M5.1)

    func testBrandHeaderHasDisplayName() {
        let model = StatusItemMenuModel.makeUnified(
            sessionState: .idle,
            micPermission: .granted,
            inputMonitoringPermission: .granted,
            activeModeName: ModeRegistry.dictation.name
        )
        // With permissions granted there are no warnings, so the
        // brand header is at index 0. It carries AppBrand.displayName
        // as its title — tests never hard-code the brand string; they
        // compare against AppBrand.displayName so a future rebrand
        // touches just the single source-of-truth constant.
        guard case let .header(title, _) = model.items[0] else {
            return XCTFail("Expected brand header at index 0")
        }
        XCTAssertEqual(title, AppBrand.displayName)
    }

    func testHomeItemHasHouseFillIcon() {
        assertIcon(actionID: .openHome, expectedIcon: "house.fill")
    }

    func testStartRecordingItemHasWaveformIcon() {
        assertIcon(actionID: .startStopRecording, expectedIcon: "waveform")
    }

    func testPasteLastTranscriptItemHasDocOnClipboardIcon() {
        assertIcon(actionID: .pasteLastTranscript, expectedIcon: "doc.on.clipboard")
    }

    func testCheckForUpdatesItemHasClockwiseIcon() {
        assertIcon(actionID: .checkForUpdates, expectedIcon: "arrow.clockwise")
    }

    func testQuitItemHasXMarkCircleIcon() {
        assertIcon(actionID: .quit, expectedIcon: "xmark.circle")
    }

    // MARK: - Helpers

    private func assertHeader(
        _ item: StatusItemMenuModel.Item,
        _ expectedTitle: String,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        guard case let .header(title, _) = item else {
            XCTFail("Expected header, got \(item)", file: file, line: line)
            return
        }
        XCTAssertEqual(title, expectedTitle, file: file, line: line)
    }

    private func assertAction(
        _ item: StatusItemMenuModel.Item,
        id: StatusItemMenuModel.ActionID,
        title: String,
        iconName: String? = nil,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        guard case let .action(action) = item else {
            XCTFail("Expected action, got \(item)", file: file, line: line)
            return
        }
        XCTAssertEqual(action.id, id, file: file, line: line)
        XCTAssertEqual(action.title, title, file: file, line: line)
        if let iconName {
            XCTAssertEqual(action.iconName, iconName, file: file, line: line)
        }
    }

    /// Assert that the action with the given id, emitted in the
    /// granted-permissions idle menu, carries the expected SF Symbol
    /// icon. Covers the M5.1 icon contract.
    private func assertIcon(
        actionID: StatusItemMenuModel.ActionID,
        expectedIcon: String,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        let model = StatusItemMenuModel.makeUnified(
            sessionState: .idle,
            micPermission: .granted,
            inputMonitoringPermission: .granted,
            activeModeName: ModeRegistry.dictation.name
        )
        let match = model.items.compactMap { item -> StatusItemMenuModel.ActionItem? in
            if case let .action(action) = item, action.id == actionID {
                return action
            }
            return nil
        }.first
        guard let match else {
            XCTFail("Expected action \(actionID) in menu", file: file, line: line)
            return
        }
        XCTAssertEqual(match.iconName, expectedIcon, file: file, line: line)
    }
}

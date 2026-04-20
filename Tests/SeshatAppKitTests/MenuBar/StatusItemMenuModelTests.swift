import XCTest
import SeshatCore
@testable import SeshatAppKit

/// Tests for `StatusItemMenuModel` — the pure model describing the
/// status-bar NSMenu contents. Reference:
/// `plans/seshat_agent_bundle/03_Surfaces/MenuBarMenu/IMPORTANT.md`.
@MainActor
final class StatusItemMenuModelTests: XCTestCase {
    // MARK: - Base structure

    func testIdleGrantedMenuHasExpectedItemsInOrder() {
        let model = StatusItemMenuModel.makeUnified(
            sessionState: .idle,
            micPermission: .granted,
            inputMonitoringPermission: .granted,
            activeModeName: ModeRegistry.dictation.name
        )

        XCTAssertEqual(model.items.count, 6)
        assertHeader(model.items[0], ModeRegistry.dictation.name)
        assertAction(model.items[1], id: .startStopRecording, title: "Start Recording   ⌥⌥")
        assertAction(model.items[2], id: .openHistory, title: "History")
        assertAction(model.items[3], id: .openSettings, title: "Settings")
        XCTAssertEqual(model.items[4], .separator)
        assertAction(model.items[5], id: .quit, title: "Quit Seshat")
    }

    func testActiveModeNameIsReflectedInHeader() {
        let model = StatusItemMenuModel.makeUnified(
            sessionState: .idle,
            micPermission: .granted,
            inputMonitoringPermission: .granted,
            activeModeName: "Long-form"
        )
        assertHeader(model.items[0], "Long-form")
    }

    func testSettingsAndHistoryAlwaysEnabledRegardlessOfOnboardingState() {
        // Regression guard: previously Settings + History were gated on
        // isOnboardingComplete, which grey-ed them out after a
        // `defaults delete com.nitkrar.seshat` reset (user stuck with
        // no way to reopen onboarding). Menu items should always be
        // enabled; routing into the Settings window handles the
        // permissions-needed UX instead.
        let model = StatusItemMenuModel.makeUnified(
            sessionState: .idle,
            micPermission: .granted,
            inputMonitoringPermission: .granted,
            activeModeName: ModeRegistry.dictation.name,
            isOnboardingComplete: false
        )

        guard case let .action(history) = model.items[2] else {
            return XCTFail("Expected History action at index 2")
        }
        guard case let .action(settings) = model.items[3] else {
            return XCTFail("Expected Settings action at index 3")
        }

        XCTAssertEqual(history.id, .openHistory)
        XCTAssertTrue(history.isEnabled)
        XCTAssertEqual(settings.id, .openSettings)
        XCTAssertTrue(settings.isEnabled)
    }

    // MARK: - Recording-toggle title switching

    func testRecordingStateSwitchesTitleToStop() {
        let model = StatusItemMenuModel.makeUnified(
            sessionState: .recording,
            micPermission: .granted,
            inputMonitoringPermission: .granted,
            activeModeName: ModeRegistry.dictation.name
        )
        assertAction(model.items[1], id: .startStopRecording, title: "Stop Recording   ⌥⌥")
    }

    func testTranscribingStateDisablesRecordingItem() {
        let model = StatusItemMenuModel.makeUnified(
            sessionState: .transcribing,
            micPermission: .granted,
            inputMonitoringPermission: .granted,
            activeModeName: ModeRegistry.dictation.name
        )
        guard case let .action(item) = model.items[1] else {
            return XCTFail("Expected action at index 1")
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
        assertAction(model.items[1], id: .startStopRecording, title: "Start Recording   ⌥⌥")
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
        // First item is the mode header, not a warning.
        if case .action(let first) = model.items[0] {
            XCTAssertNotEqual(first.id, .openMicrophoneSystemSettings)
            XCTAssertNotEqual(first.id, .openInputMonitoringSystemSettings)
        }
        XCTAssertEqual(model.items.count, 6, "No warning items expected")
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
        guard case let .action(record) = model.items[1] else {
            return XCTFail("Expected record action at index 1")
        }
        XCTAssertEqual(record.keyEquivalent, "")
    }

    // MARK: - Helpers

    private func assertHeader(
        _ item: StatusItemMenuModel.Item,
        _ expectedTitle: String,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        guard case let .header(title) = item else {
            XCTFail("Expected header, got \(item)", file: file, line: line)
            return
        }
        XCTAssertEqual(title, expectedTitle, file: file, line: line)
    }

    private func assertAction(
        _ item: StatusItemMenuModel.Item,
        id: StatusItemMenuModel.ActionID,
        title: String,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        guard case let .action(action) = item else {
            XCTFail("Expected action, got \(item)", file: file, line: line)
            return
        }
        XCTAssertEqual(action.id, id, file: file, line: line)
        XCTAssertEqual(action.title, title, file: file, line: line)
    }
}

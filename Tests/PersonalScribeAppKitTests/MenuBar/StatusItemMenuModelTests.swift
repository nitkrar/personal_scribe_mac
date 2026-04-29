import XCTest
import PersonalScribeCore
@testable import PersonalScribeAppKit

/// Tests for `StatusItemMenuModel` — the pure model describing the
/// status-bar NSMenu contents. Reference:
/// `plans/App UI design/Claude_Final_Bundle_Prompt.md` §2 (M5.1 layout).
@MainActor
final class StatusItemMenuModelTests: XCTestCase {
    /// Pinned-fixture global recording hotkey used by tests so the
    /// rendered chord is deterministic (production reads
    /// `HotkeyPreference.resolve()` from UserDefaults, which is
    /// non-deterministic in test runs).
    private static let testRecordingHotkey = HotkeyPreference.default

    private static var testRecordingHotkeyDisplay: String {
        HotkeyShortcutFormatter.displayString(for: testRecordingHotkey)
    }

    // MARK: - Base structure

    /// Post-#6 + #16 granted-mode baseline:
    ///
    /// ```
    /// [0] brand — mode header        (combined: "<displayName> — <mode>")
    /// [1] Home                       house.fill
    /// [2] History                    waveform
    /// [3] Settings                   gearshape
    /// [4] ---
    /// [5] Start Recording   <chord> waveform   (chord is the live
    ///                                           global recording hotkey,
    ///                                           e.g. `⌥/`)
    /// [6] Copy Last Transcript      doc.on.clipboard
    /// [7] ---
    /// [8] Quit <displayName>        xmark.circle
    /// ```
    func testIdleGrantedMenuHasExpectedItemsInOrder() {
        let model = StatusItemMenuModel.makeUnified(
            sessionState: .idle,
            micPermission: .granted,
            inputMonitoringPermission: .granted,
            activeModeName: WorkflowMode.dictation.name,
            recordingHotkey: Self.testRecordingHotkey
        )

        XCTAssertEqual(model.items.count, 9)
        assertHeader(model.items[0], "\(AppBrand.displayName) — \(WorkflowMode.dictation.name)")
        assertAction(model.items[1], id: .openHome, title: "Home", iconName: "house.fill")
        assertAction(model.items[2], id: .openTranscriptions, title: "History", iconName: "waveform")
        assertAction(model.items[3], id: .openSettings, title: "Settings", iconName: "gearshape")
        XCTAssertEqual(model.items[4], .separator)
        assertAction(
            model.items[5],
            id: .startStopRecording,
            title: "Start Recording   \(Self.testRecordingHotkeyDisplay)",
            iconName: "waveform"
        )
        assertAction(
            model.items[6],
            id: .copyLastTranscript,
            title: "Copy Last Transcript",
            iconName: "doc.on.clipboard"
        )
        XCTAssertEqual(model.items[7], .separator)
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
        // Post-#6: brand + mode collapse into a single header at index 0.
        assertHeader(model.items[0], "\(AppBrand.displayName) — Long-form")
    }

    func testBrandHeaderFallsBackToDisplayNameWhenNoActiveMode() {
        let model = StatusItemMenuModel.makeUnified(
            sessionState: .idle,
            micPermission: .granted,
            inputMonitoringPermission: .granted,
            activeModeName: nil
        )
        // No em-dash / mode suffix when activeModeName is nil.
        assertHeader(model.items[0], AppBrand.displayName)
    }

    // MARK: - Recording-toggle title switching

    func testRecordingStateSwitchesTitleToStop() {
        let model = StatusItemMenuModel.makeUnified(
            sessionState: .capturing,
            micPermission: .granted,
            inputMonitoringPermission: .granted,
            activeModeName: WorkflowMode.dictation.name,
            recordingHotkey: Self.testRecordingHotkey
        )
        // Start/Stop Recording sits at index 5 in the post-#6+#16 layout.
        assertAction(
            model.items[5],
            id: .startStopRecording,
            title: "Stop Recording   \(Self.testRecordingHotkeyDisplay)",
            iconName: "waveform"
        )
    }

    func testTranscribingStateDisablesRecordingItem() {
        let model = StatusItemMenuModel.makeUnified(
            sessionState: .transcribing,
            micPermission: .granted,
            inputMonitoringPermission: .granted,
            activeModeName: WorkflowMode.dictation.name
        )
        guard case let .action(item) = model.items[5] else {
            return XCTFail("Expected action at index 5")
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
            activeModeName: WorkflowMode.dictation.name,
            recordingHotkey: Self.testRecordingHotkey
        )
        assertAction(
            model.items[5],
            id: .startStopRecording,
            title: "Start Recording   \(Self.testRecordingHotkeyDisplay)",
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
            activeModeName: WorkflowMode.dictation.name
        )
        // First item is the combined brand — mode header, not a warning.
        assertHeader(model.items[0], "\(AppBrand.displayName) — \(WorkflowMode.dictation.name)")
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
            activeModeName: WorkflowMode.dictation.name
        )
        guard case let .action(quit) = model.items.last else {
            return XCTFail("Expected last item to be Quit action")
        }
        XCTAssertEqual(quit.id, .quit)
        XCTAssertEqual(quit.keyEquivalent, "q")
    }

    func testStartRecordingHasNoAppKitKeyEquivalent() {
        // `KeyEventRouter` (#028) handles the actual chord — AppKit's
        // NSMenu `keyEquivalent` is a single keystroke that can't
        // represent every chord we support (modifier-only, double-tap,
        // etc.), so no key-equivalent is published. The chord shows
        // as text in the title via `recordingItemTitle(...)`.
        let model = StatusItemMenuModel.makeUnified(
            sessionState: .idle,
            micPermission: .granted,
            inputMonitoringPermission: .granted,
            activeModeName: WorkflowMode.dictation.name,
            recordingHotkey: Self.testRecordingHotkey
        )
        // Start/Stop Recording lives at index 5 in the post-#6+#16 layout.
        guard case let .action(record) = model.items[5] else {
            return XCTFail("Expected record action at index 5")
        }
        XCTAssertEqual(record.keyEquivalent, "")
    }

    // MARK: - #028 follow-up: chord display reflects live hotkeys

    func testStartRecordingTitleReflectsCustomGlobalHotkey() {
        let custom = HotkeyPreference(
            keyCode: 15, // R
            tapCount: 1,
            modifiers: NSEvent.ModifierFlags.command.union(.shift).rawValue
        )
        let expectedChord = HotkeyShortcutFormatter.displayString(for: custom)

        let model = StatusItemMenuModel.makeUnified(
            sessionState: .idle,
            micPermission: .granted,
            inputMonitoringPermission: .granted,
            activeModeName: WorkflowMode.dictation.name,
            recordingHotkey: custom
        )

        guard case let .action(item) = model.items[5] else {
            return XCTFail("Expected record action at index 5")
        }
        XCTAssertEqual(item.title, "Start Recording   \(expectedChord)")
    }

    func testModeSubmenuChildShowsHotkeyWhenConfigured() {
        let hk = HotkeyPreference(
            keyCode: 2, // D
            tapCount: 1,
            modifiers: NSEvent.ModifierFlags.option.rawValue
        )
        let pinned = WorkflowMode(
            id: "with-hotkey",
            name: "Quick Note",
            glyph: "mic",
            hotkey: hk,
            pipelineShape: .batch,
            processors: [.transcriber(kind: .asr)],
            captureControllers: [.manualHotkey],
            outputSinks: [.transcriptHistorySQLite]
        )
        let unpinned = WorkflowMode(
            id: "no-hotkey",
            name: "Plain Note",
            glyph: "mic",
            hotkey: nil,
            pipelineShape: .batch,
            processors: [.transcriber(kind: .asr)],
            captureControllers: [.manualHotkey],
            outputSinks: [.transcriptHistorySQLite]
        )

        let model = StatusItemMenuModel.makeUnified(
            sessionState: .idle,
            micPermission: .granted,
            inputMonitoringPermission: .granted,
            modes: [pinned, unpinned],
            currentModeID: pinned.id
        )

        // The mode submenu sits between the trailing separator and the
        // Quit row. Locate it by case match.
        let submenu = model.items.first { item in
            if case .modeSubmenu = item { return true }
            return false
        }
        guard case let .modeSubmenu(parentTitle, _, children) = submenu else {
            return XCTFail("Expected a mode submenu in the items list")
        }
        // Parent reflects the current mode's chord.
        let expectedChord = HotkeyShortcutFormatter.displayString(for: hk)
        XCTAssertEqual(parentTitle, "Quick Note   \(expectedChord)")
        // Children mirror the same shape: hotkey-bearing modes append
        // the chord, hotkey-free modes show just the name.
        XCTAssertEqual(children.first { $0.modeID == "with-hotkey" }?.title,
                       "Quick Note   \(expectedChord)")
        XCTAssertEqual(children.first { $0.modeID == "no-hotkey" }?.title,
                       "Plain Note")
    }

    // MARK: - SF Symbol icons (M5.1)

    func testBrandHeaderHasDisplayName() {
        // Post-#6: no active mode → brand-only title. With an active
        // mode the format is `<displayName> — <modeName>` (covered by
        // testActiveModeNameIsReflectedInHeader).
        let model = StatusItemMenuModel.makeUnified(
            sessionState: .idle,
            micPermission: .granted,
            inputMonitoringPermission: .granted,
            activeModeName: nil
        )
        guard case let .header(title, _) = model.items[0] else {
            return XCTFail("Expected brand header at index 0")
        }
        XCTAssertEqual(title, AppBrand.displayName)
    }

    func testHistoryItemHasWaveformIcon() {
        assertIcon(actionID: .openTranscriptions, expectedIcon: "waveform")
    }

    func testSettingsItemHasGearshapeIcon() {
        assertIcon(actionID: .openSettings, expectedIcon: "gearshape")
    }

    func testHomeItemHasHouseFillIcon() {
        assertIcon(actionID: .openHome, expectedIcon: "house.fill")
    }

    func testStartRecordingItemHasWaveformIcon() {
        assertIcon(actionID: .startStopRecording, expectedIcon: "waveform")
    }

    func testCopyLastTranscriptItemHasDocOnClipboardIcon() {
        assertIcon(actionID: .copyLastTranscript, expectedIcon: "doc.on.clipboard")
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
            activeModeName: WorkflowMode.dictation.name
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

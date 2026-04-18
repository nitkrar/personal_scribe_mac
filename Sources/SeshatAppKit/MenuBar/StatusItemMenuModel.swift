import Foundation
import SeshatCore

/// Pure, testable description of the status-bar `NSMenu` contents.
///
/// `StatusItemController` consumes this to (re)build an `NSMenu`.
/// Separating the model from the AppKit surface keeps menu-composition
/// logic unit-testable without requiring a live status item.
///
/// Reference: `plans/seshat_agent_bundle/03_Surfaces/MenuBarMenu/IMPORTANT.md`
/// (authoritative — supersedes the earlier `menu_design.png`).
@MainActor
struct StatusItemMenuModel: Equatable {
    /// One rendered row. `.header` is a non-interactive grey title row
    /// (e.g. the current mode name); `.action` is a clickable item
    /// wired to an action identifier; `.separator` renders a divider.
    enum Item: Equatable {
        case header(title: String)
        case action(ActionItem)
        case separator
    }

    struct ActionItem: Equatable {
        /// Stable identifier used by `StatusItemController` to dispatch
        /// the user's click to the right handler. Does NOT appear in
        /// the rendered title.
        let id: ActionID
        let title: String
        /// Unshifted key for the Command-key equivalent (empty for none).
        /// Modifiers always include `.command` and `.option` — matching
        /// `Start Recording ⌥⌘` in `IMPORTANT.md`.
        let keyEquivalent: String
        let isEnabled: Bool
    }

    /// Stable identifiers for menu actions. Consumer wires each to a
    /// handler closure. Keeping identifiers out-of-band lets tests
    /// assert on the model without matching localised titles.
    enum ActionID: String, Equatable {
        case startStopRecording
        case openHistory
        case openSettings
        case openMicrophoneSystemSettings
        case openInputMonitoringSystemSettings
        case quit
    }

    let items: [Item]

    /// Build the menu for a given app state.
    ///
    /// Order follows `IMPORTANT.md`:
    ///
    /// ```
    /// [warning: microphone access required] (prepended when mic is not granted)
    /// [warning: input monitoring required]  (prepended when IM is not granted)
    /// [separator]                            (present when any warning shows)
    /// Quick Memo                             (header, non-interactive)
    /// Start Recording ⌥⌘                     (or "Stop Recording")
    /// History
    /// Settings
    /// ---
    /// Quit Seshat
    /// ```
    static func make(
        sessionState: SessionState,
        micPermission: MicrophonePermissionState,
        inputMonitoringPermission: InputMonitoringPermissionState,
        activeModeName: String = "Quick Memo"
    ) -> StatusItemMenuModel {
        var items: [Item] = []

        let hasMicWarning = (micPermission == .denied)
        let hasImWarning = (inputMonitoringPermission == .denied)

        if hasMicWarning {
            items.append(.action(ActionItem(
                id: .openMicrophoneSystemSettings,
                title: "⚠︎ Microphone access required — Open Settings",
                keyEquivalent: "",
                isEnabled: true
            )))
        }

        if hasImWarning {
            items.append(.action(ActionItem(
                id: .openInputMonitoringSystemSettings,
                title: "⚠︎ Input Monitoring required — Open Settings",
                keyEquivalent: "",
                isEnabled: true
            )))
        }

        if hasMicWarning || hasImWarning {
            items.append(.separator)
        }

        items.append(.header(title: activeModeName))

        items.append(.action(ActionItem(
            id: .startStopRecording,
            title: recordingItemTitle(for: sessionState),
            keyEquivalent: recordingItemKeyEquivalent(for: sessionState),
            isEnabled: recordingItemIsEnabled(for: sessionState)
        )))

        items.append(.action(ActionItem(
            id: .openHistory,
            title: "History",
            keyEquivalent: "",
            isEnabled: true
        )))

        items.append(.action(ActionItem(
            id: .openSettings,
            title: "Settings",
            keyEquivalent: "",
            isEnabled: true
        )))

        items.append(.separator)

        items.append(.action(ActionItem(
            id: .quit,
            title: "Quit Seshat",
            keyEquivalent: "q",
            isEnabled: true
        )))

        return StatusItemMenuModel(items: items)
    }

    // MARK: - Record/stop toggle helpers

    static func recordingItemTitle(for sessionState: SessionState) -> String {
        switch sessionState {
        case .idle, .error:
            return "Start Recording"
        case .recording:
            return "Stop Recording"
        case .transcribing:
            return "Transcribing…"
        }
    }

    static func recordingItemKeyEquivalent(for sessionState: SessionState) -> String {
        // ⌥⌘ modifier is applied by StatusItemController; here we
        // only publish the unshifted key character. During transcribe
        // the item is disabled but we still return the letter so the
        // shortcut doesn't reassign mid-state.
        return "r"
    }

    static func recordingItemIsEnabled(for sessionState: SessionState) -> Bool {
        switch sessionState {
        case .transcribing:
            return false
        case .idle, .recording, .error:
            return true
        }
    }
}

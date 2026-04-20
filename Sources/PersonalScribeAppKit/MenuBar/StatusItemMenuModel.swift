import Foundation
import PersonalScribeCore

/// Pure, testable description of the status-bar `NSMenu` contents.
///
/// `StatusItemController` consumes this to (re)build an `NSMenu`.
/// Separating the model from the AppKit surface keeps menu-composition
/// logic unit-testable without requiring a live status item.
///
/// Reference: `plans/App UI design/Claude_Final_Bundle_Prompt.md` §2
/// (Menu Bar Polish & Un-gating — the authoritative M5.1 layout).
@MainActor
struct StatusItemMenuModel: Equatable {
    /// One rendered row. `.header` is a non-interactive grey title row
    /// (e.g. the brand name or the current mode name); `.action` is a
    /// clickable item wired to an action identifier; `.separator`
    /// renders a divider. Headers may carry an optional SF Symbol
    /// icon; actions may likewise carry an optional icon.
    enum Item: Equatable {
        case header(title: String, iconName: String? = nil)
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
        /// Optional SF Symbol name (e.g. `"house.fill"`). When non-nil,
        /// `StatusItemController.rebuildMenu` renders the symbol as the
        /// menu item's leading image. `nil` means the item renders
        /// title-only (legacy behavior).
        let iconName: String?

        init(
            id: ActionID,
            title: String,
            keyEquivalent: String,
            isEnabled: Bool,
            iconName: String? = nil
        ) {
            self.id = id
            self.title = title
            self.keyEquivalent = keyEquivalent
            self.isEnabled = isEnabled
            self.iconName = iconName
        }
    }

    /// Stable identifiers for menu actions. Consumer wires each to a
    /// handler closure. Keeping identifiers out-of-band lets tests
    /// assert on the model without matching localised titles.
    enum ActionID: String, Equatable {
        case startStopRecording
        case openHome
        case pasteLastTranscript
        case checkForUpdates
        case openMicrophoneSystemSettings
        case openInputMonitoringSystemSettings
        case quit
    }

    let items: [Item]

    /// Build the menu for a given app state.
    ///
    /// Order follows `Claude_Final_Bundle_Prompt.md` §2 (M5.1):
    ///
    /// ```
    /// [warning: microphone access required] (prepended when mic is not granted)
    /// [warning: input monitoring required]  (prepended when IM is not granted)
    /// [separator]                            (present when any warning shows)
    /// <AppBrand.displayName>                 (brand header, non-interactive)
    /// <active mode name>                     (mode header, non-interactive)
    /// Home                                    (opens unified window)
    /// ---
    /// Start Recording ⌥⌥                     (or "Stop Recording")
    /// Paste Last Transcript                   (stub — handler lands in M5.2)
    /// ---
    /// Check for Updates…                      (stub — permanent no-op)
    /// Quit <AppBrand.displayName>
    /// ```
    ///
    /// The mic-device submenu called for by Manus §2 lands in M5.3 and
    /// is intentionally not emitted here yet.
    static func makeUnified(
        sessionState: SessionState,
        micPermission: PermissionStatus,
        inputMonitoringPermission: PermissionStatus,
        activeModeName: String? = nil,
        isOnboardingComplete: Bool = true
    ) -> StatusItemMenuModel {
        _ = isOnboardingComplete
        var items: [Item] = []

        let hasMicWarning = (micPermission == .denied)
        let hasImWarning = (inputMonitoringPermission == .denied)

        if hasMicWarning || hasImWarning {
            items.append(.header(title: "Permissions needed before recording"))
        }

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

        // Brand header — title is always the app display name. Icon
        // choice: `pencil.and.scribble` is the closest stock SF Symbol
        // to the project's quill motif (no exact "quill-ink" symbol
        // exists). Keeping it in one place here so a future design
        // swap (custom asset, different SF Symbol) touches just this
        // literal.
        items.append(.header(title: AppBrand.displayName, iconName: "pencil.and.scribble"))

        if let activeModeName {
            items.append(.header(title: activeModeName))
        }

        items.append(.action(ActionItem(
            id: .openHome,
            title: "Home",
            keyEquivalent: "",
            isEnabled: true,
            iconName: "house.fill"
        )))

        items.append(.separator)

        items.append(.action(ActionItem(
            id: .startStopRecording,
            title: recordingItemTitle(for: sessionState),
            keyEquivalent: recordingItemKeyEquivalent(for: sessionState),
            isEnabled: recordingItemIsEnabled(for: sessionState),
            iconName: "waveform"
        )))

        items.append(.action(ActionItem(
            id: .pasteLastTranscript,
            title: "Paste Last Transcript",
            keyEquivalent: "",
            isEnabled: true,
            iconName: "doc.on.clipboard"
        )))

        items.append(.separator)

        items.append(.action(ActionItem(
            id: .checkForUpdates,
            title: "Check for Updates…",
            keyEquivalent: "",
            isEnabled: true,
            iconName: "arrow.clockwise"
        )))

        items.append(.action(ActionItem(
            id: .quit,
            title: "Quit \(AppBrand.displayName)",
            keyEquivalent: "q",
            isEnabled: true,
            iconName: "xmark.circle"
        )))

        return StatusItemMenuModel(items: items)
    }

    // MARK: - Record/stop toggle helpers

    static func recordingItemTitle(for sessionState: SessionState) -> String {
        // Title includes the ⌥⌥ hint for the actual hotkey (double-tap
        // right Option, see GlobalHotkeyMonitor). AppKit NSMenu's
        // keyEquivalent cannot represent a double-tap sequence, so the
        // hotkey is surfaced as plain text in the title instead of an
        // AppKit key-equivalent binding.
        switch sessionState {
        case .idle, .error:
            return "Start Recording   ⌥⌥"
        case .recording:
            return "Stop Recording   ⌥⌥"
        case .transcribing:
            return "Transcribing…"
        }
    }

    static func recordingItemKeyEquivalent(for sessionState: SessionState) -> String {
        // Intentionally empty — the actual hotkey is a double-tap of
        // right Option (see GlobalHotkeyMonitor). NSMenu can't bind
        // that, so we publish no key-equivalent and put the ⌥⌥ hint in
        // the title instead. Earlier revisions advertised ⌥⌘R; that
        // was a lie — the AppKit shortcut didn't actually trigger
        // recording.
        return ""
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

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
    /// renders a divider; `.submenu` is a parent row with nested
    /// children (e.g. the Microphone input-device picker added in
    /// M5.3). Headers may carry an optional SF Symbol icon; actions
    /// and submenu parents may likewise carry an optional icon.
    enum Item: Equatable {
        case header(title: String, iconName: String? = nil)
        case action(ActionItem)
        case separator
        case submenu(title: String, iconName: String?, children: [SubmenuChild])
        case modeSubmenu(title: String, iconName: String?, children: [ModeSubmenuChild])
    }

    /// One row inside a `.submenu(...)`. Currently used only for the
    /// Microphone input-device picker; `deviceID` is the opaque
    /// `AudioInputDevice.id` payload that the consumer dispatches on
    /// when the user selects a row. `isActive == true` renders a
    /// checkmark (`NSMenuItem.state == .on`).
    struct SubmenuChild: Equatable {
        /// Opaque payload forwarded to
        /// `AudioInputDeviceProviding.selectDevice(id:)`.
        let deviceID: String
        let title: String
        let isActive: Bool

        init(deviceID: String, title: String, isActive: Bool) {
            self.deviceID = deviceID
            self.title = title
            self.isActive = isActive
        }
    }

    /// One row inside a `.modeSubmenu(...)`. `modeID` is the
    /// `WorkflowMode.id` payload forwarded to the `setActiveMode`
    /// closure when the user selects a row.
    struct ModeSubmenuChild: Equatable {
        let modeID: String
        let title: String
        let isActive: Bool

        init(modeID: String, title: String, isActive: Bool) {
            self.modeID = modeID
            self.title = title
            self.isActive = isActive
        }
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
        case openTranscriptions
        case openSettings
        case copyLastTranscript
        case openMicrophoneSystemSettings
        case openInputMonitoringSystemSettings
        case quit
        /// Dispatch id for Microphone-submenu device rows. The payload
        /// (`AudioInputDevice.id`) travels on the `SubmenuChild`, not
        /// through this enum — the controller hands the id straight
        /// to `AudioInputDeviceProviding.selectDevice(id:)`.
        case selectAudioInputDevice
        /// Dispatch id for Mode-submenu rows (#068). The payload
        /// (`WorkflowMode.id`) travels on the `ModeSubmenuChild`,
        /// not through this enum — the controller hands the id to
        /// the injected `setActiveMode` closure.
        case selectMode
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
    /// <AppBrand.displayName> — <active mode> (header, non-interactive;
    ///                                         falls back to brand-only
    ///                                         when no mode is active)
    /// Home                                    (opens unified window on Home tab)
    /// History                                 (opens unified window on Transcriptions tab)
    /// Settings                                (opens unified window on Settings tab)
    /// ---
    /// Start Recording <chord>                (or "Stop Recording";
    ///                                         <chord> is the live global
    ///                                         recording hotkey, e.g. ⌥/)
    /// Copy Last Transcript                    (writes most-recent transcript to clipboard)
    /// ---
    /// Quit <AppBrand.displayName>
    /// ```
    ///
    /// When `inputDevices` is non-empty (M5.3), a Microphone submenu is
    /// inserted between the separator after `Copy Last Transcript` and
    /// `Quit`, with the submenu's parent title showing the
    /// currently-selected device name (or "Microphone" if no user
    /// selection exists yet) and a checkmark on the child row whose id
    /// equals `currentInputDeviceID`. When `inputDevices` is empty the
    /// submenu is omitted entirely.
    static func makeUnified(
        sessionState: SessionState,
        micPermission: PermissionStatus,
        inputMonitoringPermission: PermissionStatus,
        activeModeName: String? = nil,
        isOnboardingComplete: Bool = true,
        inputDevices: [AudioInputDevice] = [],
        currentInputDeviceID: String? = nil,
        modes: [WorkflowMode] = [],
        currentModeID: String? = nil,
        recordingHotkey: HotkeyPreference = HotkeyPreference.resolve()
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

        // Single compact header row. When a mode is active we inline it
        // after the brand (em-dash separator) to avoid two adjacent grey
        // headers reading as a wrapped string (bug #6, 2026-04-21 dogfood).
        // Icon `pencil.and.scribble` — closest stock SF Symbol to the
        // project's quill motif — stays on the combined row.
        let brandHeaderTitle: String = {
            if let activeModeName {
                return "\(AppBrand.displayName) — \(activeModeName)"
            }
            return AppBrand.displayName
        }()
        items.append(.header(title: brandHeaderTitle, iconName: "pencil.and.scribble"))

        items.append(.action(ActionItem(
            id: .openHome,
            title: "Home",
            keyEquivalent: "",
            isEnabled: true,
            iconName: "house.fill"
        )))

        items.append(.action(ActionItem(
            id: .openTranscriptions,
            title: "History",
            keyEquivalent: "",
            isEnabled: true,
            iconName: "waveform"
        )))

        items.append(.action(ActionItem(
            id: .openSettings,
            title: "Settings",
            keyEquivalent: "",
            isEnabled: true,
            iconName: "gearshape"
        )))

        items.append(.separator)

        items.append(.action(ActionItem(
            id: .startStopRecording,
            title: recordingItemTitle(for: sessionState, recordingHotkey: recordingHotkey),
            keyEquivalent: recordingItemKeyEquivalent(for: sessionState),
            isEnabled: recordingItemIsEnabled(for: sessionState),
            iconName: "waveform"
        )))

        items.append(.action(ActionItem(
            id: .copyLastTranscript,
            title: "Copy Last Transcript",
            keyEquivalent: "",
            isEnabled: true,
            iconName: "doc.on.clipboard"
        )))

        // The final separator is always present; the optional Mode
        // submenu (#068) and Microphone submenu (M5.3) slot between it
        // and Quit. Mode renders above Mic when both are present —
        // "what the app does" above "what hardware it listens on".
        // Omitting either submenu when its source list is empty keeps
        // the baseline shape stable for unit tests.
        items.append(.separator)

        if !modes.isEmpty {
            // #028 follow-up: per-mode hotkey appears alongside the
            // mode name in BOTH the parent row (current mode) and each
            // child row. Mirrors the chord-display pattern used for
            // the global recording hotkey on the "Start Recording"
            // row above. Modes without a configured hotkey just show
            // their name unchanged.
            let parentTitle: String = {
                if let currentModeID,
                   let current = modes.first(where: { $0.id == currentModeID }) {
                    return modeRowTitle(for: current)
                }
                return "Mode"
            }()
            items.append(.modeSubmenu(
                title: parentTitle,
                iconName: "switch.2",
                children: modes.map { mode in
                    ModeSubmenuChild(
                        modeID: mode.id,
                        title: modeRowTitle(for: mode),
                        isActive: mode.id == currentModeID
                    )
                }
            ))
        }

        if !inputDevices.isEmpty {
            items.append(.submenu(
                title: currentInputDeviceName(
                    in: inputDevices,
                    selectedID: currentInputDeviceID
                ) ?? "Microphone",
                iconName: "mic",
                children: inputDevices.map { device in
                    SubmenuChild(
                        deviceID: device.id,
                        title: device.name,
                        isActive: device.id == currentInputDeviceID
                    )
                }
            ))
        }

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

    static func recordingItemTitle(
        for sessionState: SessionState,
        recordingHotkey: HotkeyPreference = HotkeyPreference.resolve()
    ) -> String {
        // Title carries the actual global recording hotkey as plain
        // text alongside the action verb. AppKit NSMenu's
        // `keyEquivalent` can't represent every chord we support
        // (double-tap, modifier-only, etc.), so the chord is surfaced
        // in the title instead of bound as a real key equivalent —
        // the user reads it as a hint, the actual dispatch goes
        // through `KeyEventRouter` -> `GlobalHotkeyMonitor`.
        let chord = HotkeyShortcutFormatter.displayString(for: recordingHotkey)
        switch sessionState {
        case .idle, .completed, .shortExit, .error:
            return "Start Recording   \(chord)"
        case .capturing, .holdRecording:
            return "Stop Recording   \(chord)"
        case .transcribing:
            return "Transcribing…"
        }
    }

    /// Format a `WorkflowMode`'s title for the menu — appends the
    /// chord display when the mode has a per-mode hotkey configured,
    /// matching the chord-on-row pattern used for the global hotkey.
    static func modeRowTitle(for mode: WorkflowMode) -> String {
        guard let hotkey = mode.hotkey else {
            return mode.name
        }
        let chord = HotkeyShortcutFormatter.displayString(for: hotkey)
        return "\(mode.name)   \(chord)"
    }

    static func recordingItemKeyEquivalent(for sessionState: SessionState) -> String {
        // Intentionally empty — `KeyEventRouter` (#028) handles the
        // chord. NSMenu's `keyEquivalent` is a single keystroke, so
        // it can't faithfully represent every chord we support
        // (modifier-only, double-tap, etc.). The hint is surfaced as
        // text in the title via `recordingItemTitle(for:recordingHotkey:)`.
        return ""
    }

    static func recordingItemIsEnabled(for sessionState: SessionState) -> Bool {
        switch sessionState {
        case .transcribing:
            return false
        case .idle, .completed, .shortExit, .capturing, .holdRecording, .error:
            return true
        }
    }

    // MARK: - Microphone submenu helpers (M5.3)

    /// Returns the display name of the currently-selected input device
    /// if it is still present in `devices`; returns `nil` if there is
    /// no selection or the previously-selected device has disappeared
    /// (e.g. USB mic unplugged). Callers fall back to a generic
    /// "Microphone" title in that case.
    static func currentInputDeviceName(
        in devices: [AudioInputDevice],
        selectedID: String?
    ) -> String? {
        guard let selectedID else { return nil }
        return devices.first(where: { $0.id == selectedID })?.name
    }
}

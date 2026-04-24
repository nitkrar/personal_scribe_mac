import AppKit
import SwiftUI
import PersonalScribeCore
import PersonalScribeVAD

@MainActor
public struct GeneralTab: View {
    @StateObject private var viewModel: GeneralTabViewModel
    @StateObject private var shortcutsViewModel: ShortcutsTabViewModel
    @State private var isRecordingHotkeyRecorderPresented = false
    @State private var isBackgroundModeInfoPresented = false
    @Environment(\.colorScheme) private var colorScheme

    public init(
        defaults: UserDefaults = .standard,
        menuBarVisibilityProvider: @escaping @MainActor () -> Bool = { true },
        menuBarVisibilitySetter: @escaping @MainActor (Bool) -> Void = { _ in },
        launchAtLoginService: any LaunchAtLoginServicing = SystemLaunchAtLoginService()
    ) {
        _viewModel = StateObject(
            wrappedValue: GeneralTabViewModel(
                defaults: defaults,
                menuBarVisibilityProvider: menuBarVisibilityProvider,
                menuBarVisibilitySetter: menuBarVisibilitySetter,
                launchAtLoginService: launchAtLoginService
            )
        )
        _shortcutsViewModel = StateObject(
            wrappedValue: ShortcutsTabViewModel(defaults: defaults)
        )
    }

    public var body: some View {
        SettingsTabContainer {
            SettingsSection(
                title: "General",
                description: "Core defaults for the pill overlay, menu bar surface, and transcript delivery."
            ) {
                VStack(alignment: .leading, spacing: SettingsLayout.itemSpacing) {
                    recordingWindowCard
                    appearanceCard
                    visibilityCard
                    applicationCard
                    textInputCard
                    autoStopCard
                    behaviorCard
                }
            }

            shortcutsSection
        }
        .sheet(isPresented: $isRecordingHotkeyRecorderPresented) {
            HotkeyRecorder(
                currentPreference: shortcutsViewModel.recordingHotkey,
                onConfirm: { preference in
                    shortcutsViewModel.setRecordingHotkey(preference)
                    isRecordingHotkeyRecorderPresented = false
                },
                onCancel: {
                    isRecordingHotkeyRecorderPresented = false
                }
            )
        }
    }

    /// RECORDING WINDOW section — mockup-gaps D.1 centerpiece.
    /// Live SwiftUI pill previews, one card per `PillStyle` case,
    /// champagne border on the selected card. Reads
    /// `viewModel.pillAppearance` so the preview adapts (navy
    /// `#1A1B2E` for `.dark`, pale `#F0EDE8` for `.light`).
    private var recordingWindowCard: some View {
        SettingsCard {
            Text("Style")
                .font(PersonalScribeTheme.Typography.body.font.weight(.semibold))

            HStack(alignment: .top, spacing: SettingsLayout.itemSpacing) {
                ForEach(PillStyle.allCases) { style in
                    PillStyleSelectorCard(
                        style: style,
                        isSelected: viewModel.pillStyle == style,
                        pillAppearance: viewModel.pillAppearance
                    ) {
                        viewModel.setPillStyle(style)
                    }
                    .frame(maxWidth: .infinity)
                }
            }
        }
        .onAppear {
            viewModel.refreshLaunchAtLoginStatus()
        }
    }

    /// APPLICATION section — mockup-gaps D.2. Absorbs the old
    /// `launchCard` (Launch at login toggle) and adds the new Show in
    /// Dock toggle. No cross-toggle invariant (unlike visibility's
    /// pill+menu-bar conflict) — Show in Dock stays independent by
    /// design; if a cross-check with menu-bar/pill visibility is needed
    /// later, it's a follow-up.
    private var applicationCard: some View {
        SettingsCard {
            Text("Application")
                .font(PersonalScribeTheme.Typography.body.font.weight(.semibold))

            HStack(spacing: SettingsLayout.inlineSpacing) {
                Toggle(
                    "Launch at login",
                    isOn: Binding(
                        get: { viewModel.launchAtLogin },
                        set: { viewModel.setLaunchAtLogin($0) }
                    )
                )

                // Status dot reflects the real registration state as last
                // re-read from the login-items service. Green when the
                // system reports `.enabled`, red otherwise — register()
                // failures surface here because setLaunchAtLogin re-reads
                // the service after the call (#005).
                launchStatusDot

                // Clickable deep-link: opens System Settings → General →
                // Login Items so the user can verify / change the
                // registration without leaving the app. macOS does not
                // natively prompt for Login Items, so we route them to
                // the pane that does. `.help(...)` stays as a hover
                // tooltip for the 50% of the time SwiftUI honors it on
                // a bare Image; the `.onTapGesture` is the primary
                // discoverable affordance (fixes #073).
                Image(systemName: "info.circle")
                    .foregroundStyle(.secondary)
                    .onTapGesture {
                        if let url = URL(string: "x-apple.systempreferences:com.apple.LoginItems-Settings.extension") {
                            NSWorkspace.shared.open(url)
                        }
                    }
                    .help("Open System Settings → General → Login Items")

                Spacer()
            }

            Divider()

            // Inline-icon label: info icon sits inside the Toggle's label
            // with a tap gesture driving the popover. Keeps the whole row
            // as a single Toggle — no sibling Button — and the info
            // affordance is discoverable on tap (not just hover), so it
            // doesn't inherit the tooltip-only discoverability bug from
            // the Launch at Login icon (#073).
            Toggle(
                isOn: Binding(
                    get: { viewModel.backgroundMode },
                    set: { viewModel.setBackgroundMode($0) }
                )
            ) {
                HStack(spacing: 4) {
                    Text("Background mode")
                    Image(systemName: "info.circle")
                        .foregroundStyle(.secondary)
                        .onTapGesture {
                            isBackgroundModeInfoPresented.toggle()
                        }
                        .popover(isPresented: $isBackgroundModeInfoPresented) {
                            Text(
                                "Background mode hides \(AppBrand.displayName) from the Dock, the Cmd+Tab switcher, and the Force Quit window. "
                                    + "Only the menu bar icon and the floating pill remain — useful for a clutter-free dictation setup. "
                                    + "Turn it off to run \(AppBrand.displayName) as a regular Mac app.")
                                .font(PersonalScribeTheme.Typography.body.font)
                                .padding()
                                .frame(width: 320)
                        }
                }
            }

            if viewModel.backgroundModeRestartRequired {
                RestartRequiredCaption(
                    message: "Restart \(AppBrand.displayName) for background-mode changes to take effect."
                )
            }
        }
    }

    private var launchStatusDot: some View {
        let palette = PersonalScribeTheme.Palette.for(scheme: colorScheme)
        let color = viewModel.launchAtLogin ? palette.statusReady : palette.statusRecording
        return Circle()
            .fill(color)
            .frame(width: 8, height: 8)
            .accessibilityHidden(true)
    }

    private var visibilityCard: some View {
        SettingsCard {
            Text("Visibility")
                .font(PersonalScribeTheme.Typography.body.font.weight(.semibold))

            Toggle(
                "Show menu bar item",
                isOn: Binding(
                    get: { viewModel.isMenuBarVisible },
                    set: { isVisible in
                        _ = viewModel.applyVisibilityConfig(
                            .init(
                                pillVisibilityMode: viewModel.pillVisibilityMode,
                                isMenuBarVisible: isVisible
                            )
                        )
                    }
                )
            )

            Divider()

            Picker(
                "Pill visibility",
                selection: Binding(
                    get: { viewModel.pillVisibilityMode },
                    set: { newValue in
                        _ = viewModel.applyVisibilityConfig(
                            .init(
                                pillVisibilityMode: newValue,
                                isMenuBarVisible: viewModel.isMenuBarVisible
                            )
                        )
                    }
                )
            ) {
                Text("Always-on").tag(PillVisibilityMode.alwaysOn)
                Text("Auto-show").tag(PillVisibilityMode.autoShow)
                Text("Hidden").tag(PillVisibilityMode.hidden)
            }

            if let visibilityErrorMessage = viewModel.visibilityErrorMessage {
                Divider()

                Label(visibilityErrorMessage, systemImage: "exclamationmark.triangle.fill")
                    .font(PersonalScribeTheme.Typography.caption.font)
                    .foregroundStyle(.secondary)
            }
        }
    }

    /// TEXT INPUT section — mockup-gaps D.3. Master "Paste result
    /// text" toggle + the existing Paste mode picker (moved here from
    /// the former `behaviorCard`).
    ///
    /// D.3 DEFERRAL: the master toggle's `pasteEnabled` value is
    /// persisted and published by the VM but NOT yet consulted by the
    /// downstream paste / clipboard service. Selecting "off" here only
    /// updates the preference; the next recording still pastes +
    /// writes the clipboard. Wiring is tracked in the backlog append.
    private var textInputCard: some View {
        SettingsCard {
            Text("Text Input")
                .font(PersonalScribeTheme.Typography.body.font.weight(.semibold))

            Toggle(
                "Paste result text",
                isOn: Binding(
                    get: { viewModel.pasteEnabled },
                    set: { viewModel.setPasteEnabled($0) }
                )
            )

            Divider()

            Picker(
                "Paste mode",
                selection: Binding(
                    get: { viewModel.pasteMode },
                    set: { viewModel.setPasteMode($0) }
                )
            ) {
                Text("Paste-at-cursor").tag(PasteMode.pasteAtCursor)
                Text("Clipboard-only").tag(PasteMode.clipboardOnly)
            }
        }
    }

    /// Auto-stop card (#046). Master toggle + silence threshold slider + two
    /// optional warn/notify toggles. Both-prefs preferences freeze at session
    /// start — mid-session edits apply to the NEXT recording only.
    ///
    /// Stage B collapsed layout: the master toggle stays always visible;
    /// the threshold slider + warn/notify toggles render only when the
    /// master is on. No `DisclosureGroup`; vertical stacking only. No
    /// `.animation(...)` — intentionally skipped for MVP per plan.
    private var autoStopCard: some View {
        SettingsCard {
            Text("Auto-stop")
                .font(PersonalScribeTheme.Typography.body.font.weight(.semibold))

            Toggle(
                "Auto-stop after silence",
                isOn: Binding(
                    get: { viewModel.vadAutoStopEnabled },
                    set: { viewModel.setVadAutoStopEnabled($0) }
                )
            )

            if viewModel.vadAutoStopEnabled {
                Divider()

                VStack(alignment: .leading, spacing: SettingsLayout.inlineSpacing) {
                    Text("Silence threshold")
                        .font(PersonalScribeTheme.Typography.body.font.weight(.medium))

                    Text(viewModel.vadSilenceThresholdDescription)
                        .font(PersonalScribeTheme.Typography.caption.font)
                        .foregroundStyle(.secondary)

                    Slider(
                        value: Binding(
                            get: { viewModel.vadSilenceThresholdSeconds },
                            set: { viewModel.setVadSilenceThresholdSeconds($0) }
                        ),
                        in: VadPreferences.minSilenceThresholdSeconds...VadPreferences.maxSilenceThresholdSeconds,
                        step: 0.5
                    )

                    Text("Changes apply to the next recording — the current session keeps its frozen setting.")
                        .font(PersonalScribeTheme.Typography.caption.font)
                        .foregroundStyle(.secondary)
                }

                Divider()

                Toggle(
                    "Warn before stopping",
                    isOn: Binding(
                        get: { viewModel.vadShowStoppingWarning },
                        set: { viewModel.setVadShowStoppingWarning($0) }
                    )
                )

                Toggle(
                    "Show stop notification",
                    isOn: Binding(
                        get: { viewModel.vadShowAutoStoppedNotification },
                        set: { viewModel.setVadShowAutoStoppedNotification($0) }
                    )
                )
            }
        }
    }

    /// Residual Behavior card — Waveform decay + Clipboard restore
    /// delay. The mockup is silent on these; D.3 deliberately keeps
    /// them in place rather than deleting functionality the reference
    /// doesn't call out. The Paste mode picker moved to `textInputCard`.
    private var behaviorCard: some View {
        SettingsCard {
            Text("Behavior")
                .font(PersonalScribeTheme.Typography.body.font.weight(.semibold))

            Picker(
                "Waveform decay",
                selection: Binding(
                    get: { viewModel.waveformDecayMode },
                    set: { viewModel.setWaveformDecayMode($0) }
                )
            ) {
                Text("Immediate").tag(WaveformDecayMode.immediate)
                Text("Animated").tag(WaveformDecayMode.animated)
            }

            Divider()

            VStack(alignment: .leading, spacing: SettingsLayout.inlineSpacing) {
                Text("Clipboard restore delay")
                    .font(PersonalScribeTheme.Typography.body.font.weight(.medium))

                Text(viewModel.pasteRestoreDelayDescription)
                    .font(PersonalScribeTheme.Typography.caption.font)
                    .foregroundStyle(.secondary)

                Slider(
                    value: Binding(
                        get: { viewModel.pasteRestoreDelay.seconds },
                        set: { viewModel.setPasteRestoreDelaySeconds($0) }
                    ),
                    in: 0.1...5.0,
                    step: 0.1
                )
            }
        }
    }

    private var appearanceCard: some View {
        SettingsCard {
            Text("Appearance")
                .font(PersonalScribeTheme.Typography.body.font.weight(.semibold))

            // Theme picker — master light/dark selector. Lives above
            // the Window tint picker; tint is a light-mode-only brand
            // flavor so it's fully hidden when the effective scheme is
            // dark (see `viewModel.showsTintPicker`).
            Picker(
                "Theme",
                selection: Binding(
                    get: { viewModel.appTheme },
                    set: { viewModel.setAppTheme($0) }
                )
            ) {
                Text("Light").tag(AppTheme.light)
                Text("Dark").tag(AppTheme.dark)
                Text("System").tag(AppTheme.system)
            }
            .pickerStyle(.segmented)

            if viewModel.showsTintPicker {
                Divider()

                Picker(
                    "Window tint",
                    selection: Binding(
                        get: { viewModel.windowTint },
                        set: { viewModel.setWindowTint($0) }
                    )
                ) {
                    Text("Warm").tag(WindowTint.warm)
                    Text("Neutral").tag(WindowTint.neutral)
                }
                .pickerStyle(.segmented)
            }

            Divider()

            Picker(
                "Pill theme",
                selection: Binding(
                    get: { viewModel.pillAppearance },
                    set: { viewModel.setPillAppearance($0) }
                )
            ) {
                Text("Dark").tag(PillAppearance.dark)
                Text("Light").tag(PillAppearance.light)
                Text("System").tag(PillAppearance.system)
            }
            .pickerStyle(.segmented)
        }
    }

    private var shortcutsSection: some View {
        SettingsSection(
            title: "Shortcuts",
            description: "Customize the recording toggle. Emergency quit remains fixed."
        ) {
            shortcutCard(
                title: "Record / stop dictation",
                shortcut: HotkeyShortcutFormatter.displayString(
                    for: shortcutsViewModel.recordingHotkey
                ),
                notes: "Starts a session from idle and stops the active session.",
                changeAction: {
                    isRecordingHotkeyRecorderPresented = true
                },
                changeEnabled: true,
                restartRequiredMessage: shortcutsViewModel.requiresRestartNotice
                    ? "Relaunch \(AppBrand.displayName) for the new recording hotkey to take effect."
                    : nil
            )
        }
    }

    @ViewBuilder
    private func shortcutCard(
        title: String,
        shortcut: String,
        notes: String,
        changeAction: @escaping () -> Void,
        changeEnabled: Bool,
        restartRequiredMessage: String?
    ) -> some View {
        SettingsCard {
            HStack(alignment: .top, spacing: SettingsLayout.itemSpacing) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(title)
                        .font(PersonalScribeTheme.Typography.body.font.weight(.semibold))
                    Text(notes)
                        .font(PersonalScribeTheme.Typography.caption.font)
                        .foregroundStyle(.secondary)
                }

                Spacer(minLength: 0)

                VStack(alignment: .trailing, spacing: SettingsLayout.inlineSpacing) {
                    Text(shortcut)
                        .font(.system(size: 12, weight: .semibold, design: .monospaced))
                        .textSelection(.enabled)

                    Button("Change…", action: changeAction)
                        .disabled(changeEnabled == false)
                }
            }

            if let restartRequiredMessage {
                Divider()
                RestartRequiredCaption(message: restartRequiredMessage)
            }
        }
    }
}

@MainActor
final class GeneralTabViewModel: ObservableObject {
    struct VisibilityConfig: Equatable {
        let pillVisibilityMode: PillVisibilityMode
        let isMenuBarVisible: Bool
    }

    enum VisibilityConfigError: Equatable {
        case conflict
    }

    @Published private(set) var pillVisibilityMode: PillVisibilityMode
    @Published private(set) var isMenuBarVisible: Bool
    @Published private(set) var waveformDecayMode: WaveformDecayMode
    @Published private(set) var pasteMode: PasteMode
    @Published private(set) var windowTint: WindowTint
    @Published private(set) var pillAppearance: PillAppearance
    @Published private(set) var pillStyle: PillStyle
    @Published private(set) var pasteRestoreDelay: PasteRestoreDelay
    @Published private(set) var visibilityError: VisibilityConfigError?
    @Published private(set) var launchAtLogin: Bool
    /// Background mode = menu-bar-only accessory app. Default `false`
    /// (app is a regular app with Dock icon / Cmd+Tab entry / Force Quit
    /// entry). When `true`, the app becomes an `NSApplicationActivationPolicy.accessory`
    /// process at NEXT launch. Changes do NOT take effect live — toggling
    /// sets `backgroundModeRestartRequired = true` and persists the pref;
    /// the runtime `NSApp.setActivationPolicy` call lives in
    /// `PersonalScribeAppMain` startup, which reads this pref once.
    @Published private(set) var backgroundMode: Bool
    /// `true` whenever the user has toggled `backgroundMode` since the
    /// Settings window opened. Drives the "Restart required" caption
    /// under the toggle. Does NOT clear on toggle-back — the relaunch
    /// gate is per-session regardless of whether the user ended up at
    /// the original value, which is acceptable UX and keeps the state
    /// machine trivial.
    @Published private(set) var backgroundModeRestartRequired: Bool = false
    @Published private(set) var pasteEnabled: Bool
    /// VAD auto-stop master toggle (#046). When `false`, orchestrator skips
    /// VAD wiring entirely — recording only stops via manual hotkey / pill / Esc.
    @Published private(set) var vadAutoStopEnabled: Bool
    /// Silence duration threshold in seconds. Range and step enforced by the
    /// Settings slider (1.0–10.0s, step 0.5). Read-clamped in the preference.
    @Published private(set) var vadSilenceThresholdSeconds: Double
    /// Stage B warn toggle (#046). When `true`, orchestrator opens a 3.0s
    /// grace window before auto-stop and ResponseCard surfaces a
    /// "…stopping, speak to continue" prompt. Default `false`.
    @Published private(set) var vadShowStoppingWarning: Bool
    /// Stage B notification toggle (#046). When `true`, ResponseCard shows
    /// "Auto stopped. Update settings to change." after VAD-triggered stop.
    /// Default `false`.
    @Published private(set) var vadShowAutoStoppedNotification: Bool
    /// Master theme (Light / Dark / System). Drives
    /// `showsTintPicker` — tint is hidden when the effective scheme
    /// is dark (mockup-gaps G, 2026-04-21).
    @Published private(set) var appTheme: AppTheme
    /// Snapshot of the system's effective appearance — `true` when
    /// macOS resolves to `.darkAqua`. Injected for testability; at
    /// runtime the default provider reads
    /// `NSApplication.shared.effectiveAppearance`. Re-published by
    /// the KVO observer so `showsTintPicker` reacts to system-theme
    /// flips while Settings is open.
    @Published private(set) var currentSystemIsDark: Bool

    private let defaults: UserDefaults
    private let menuBarVisibilitySetter: @MainActor (Bool) -> Void
    private let systemIsDarkProvider: @MainActor () -> Bool
    private var effectiveAppearanceObservation: NSKeyValueObservation?
    private let launchAtLoginService: any LaunchAtLoginServicing

    init(
        defaults: UserDefaults = .standard,
        menuBarVisibilityProvider: @escaping @MainActor () -> Bool = { true },
        menuBarVisibilitySetter: @escaping @MainActor (Bool) -> Void = { _ in },
        systemIsDarkProvider: @escaping @MainActor () -> Bool = {
            NSApplication.shared.effectiveAppearance.bestMatch(
                from: [.aqua, .darkAqua]
            ) == .darkAqua
        },
        launchAtLoginService: any LaunchAtLoginServicing = SystemLaunchAtLoginService()
    ) {
        self.defaults = defaults
        self.menuBarVisibilitySetter = menuBarVisibilitySetter
        self.systemIsDarkProvider = systemIsDarkProvider
        self.launchAtLoginService = launchAtLoginService
        self.pillVisibilityMode = PillVisibilityMode.resolve(from: defaults)
        // Snapshot-at-init: isMenuBarVisible is NOT re-read while the
        // Settings window is open. The General tab is the sole mutator
        // in Phase 3, so the snapshot is always current. If a second
        // path ever starts mutating menu-bar visibility (e.g. a hotkey
        // to toggle it), refresh here on view appear or swap to a
        // Published upstream source.
        self.isMenuBarVisible = menuBarVisibilityProvider()
        self.waveformDecayMode = WaveformDecayMode.resolve(from: defaults)
        self.pasteMode = PasteMode.resolve(from: defaults)
        self.windowTint = WindowTint.resolve(from: defaults)
        self.pillAppearance = PillAppearance.resolve(from: defaults)
        self.pillStyle = PillStyle.resolve(from: defaults)
        self.pasteRestoreDelay = PasteRestoreDelay.resolve(from: defaults)
        // launchAtLogin seeds from the injected service. The real impl
        // (`SystemLaunchAtLoginService`) reads SMAppService.mainApp.status
        // — .enabled means the app is registered to launch at login.
        self.launchAtLogin = launchAtLoginService.isEnabled
        self.backgroundMode = BackgroundModePreference.resolve(from: defaults)
        self.pasteEnabled = PasteEnabledPreference.resolve(from: defaults)
        self.vadAutoStopEnabled = VadAutoStopEnabledPreference.resolve(from: defaults)
        self.vadSilenceThresholdSeconds = VadSilenceThresholdPreference.resolve(from: defaults)
        self.vadShowStoppingWarning = VadShowStoppingWarningPreference.resolve(from: defaults)
        self.vadShowAutoStoppedNotification = VadShowAutoStoppedNotificationPreference.resolve(from: defaults)
        self.appTheme = AppTheme.resolve(from: defaults)
        self.currentSystemIsDark = systemIsDarkProvider()

        // KVO on `NSApplication.effectiveAppearance` so that when the
        // user flips the system theme while Settings is open and
        // `AppTheme == .system`, `showsTintPicker` recomputes without
        // the window needing to close/reopen. In tests we use the
        // injected provider snapshot and skip the observer — KVO on
        // the global NSApp instance doesn't fire deterministically in
        // an XCTest harness.
        effectiveAppearanceObservation = NSApplication.shared.observe(
            \.effectiveAppearance,
            options: [.new]
        ) { [weak self] _, _ in
            Task { @MainActor [weak self] in
                guard let self else { return }
                self.currentSystemIsDark = self.systemIsDarkProvider()
            }
        }
    }

    deinit {
        effectiveAppearanceObservation?.invalidate()
    }

    /// `true` when the Window-tint picker should be visible. Tint is
    /// a light-mode-only brand flavor; when the effective scheme is
    /// dark (`AppTheme == .dark`, or `AppTheme == .system` and the
    /// system resolves to dark) the picker is fully hidden from the
    /// Settings card.
    var showsTintPicker: Bool {
        appTheme.effectiveScheme(systemIsDark: currentSystemIsDark) == .light
    }

    var visibilityErrorMessage: String? {
        guard visibilityError == .conflict else { return nil }
        return "One surface must stay visible so you can reach the app."
    }

    @discardableResult
    func applyVisibilityConfig(_ config: VisibilityConfig) -> VisibilityConfigError? {
        guard !(config.pillVisibilityMode == .hidden && !config.isMenuBarVisible) else {
            visibilityError = .conflict
            return .conflict
        }

        visibilityError = nil
        pillVisibilityMode = config.pillVisibilityMode
        isMenuBarVisible = config.isMenuBarVisible
        config.pillVisibilityMode.persist(to: defaults)
        menuBarVisibilitySetter(config.isMenuBarVisible)
        return nil
    }

    func setWaveformDecayMode(_ mode: WaveformDecayMode) {
        waveformDecayMode = mode
        mode.persist(to: defaults)
    }

    func setPasteMode(_ mode: PasteMode) {
        pasteMode = mode
        mode.persist(to: defaults)
    }

    /// Persists the master "paste result text" toggle. D.3 only wires
    /// the preference + Settings UI; the downstream `OutputService`
    /// still delivers paste unconditionally until the follow-up
    /// (tracked in the D.3 backlog append) lands.
    func setPasteEnabled(_ enabled: Bool) {
        pasteEnabled = enabled
        PasteEnabledPreference.persist(enabled, to: defaults)
    }

    /// Description line rendered above the silence-threshold slider. Formats
    /// the current value with one decimal, consistent with the slider step.
    var vadSilenceThresholdDescription: String {
        String(format: "%.1fs of silence before auto-stop", vadSilenceThresholdSeconds)
    }

    func setVadAutoStopEnabled(_ enabled: Bool) {
        vadAutoStopEnabled = enabled
        VadAutoStopEnabledPreference.persist(enabled, to: defaults)
    }

    func setVadSilenceThresholdSeconds(_ seconds: Double) {
        vadSilenceThresholdSeconds = seconds
        VadSilenceThresholdPreference.persist(seconds, to: defaults)
    }

    func setVadShowStoppingWarning(_ enabled: Bool) {
        vadShowStoppingWarning = enabled
        VadShowStoppingWarningPreference.persist(enabled, to: defaults)
    }

    func setVadShowAutoStoppedNotification(_ enabled: Bool) {
        vadShowAutoStoppedNotification = enabled
        VadShowAutoStoppedNotificationPreference.persist(enabled, to: defaults)
    }

    func setWindowTint(_ tint: WindowTint) {
        windowTint = tint
        tint.persist(to: defaults)
    }

    /// Persists the master theme and applies the resolved
    /// `NSAppearance` to every currently-open app window. Persisting
    /// also triggers `UserDefaults.didChangeNotification` which the
    /// `UnifiedWindowController` observer picks up for next-open
    /// windows, so both live and future windows stay in sync.
    ///
    /// Pill appearance and window tint are NOT mutated — they are
    /// independent axes per user direction (2026-04-21).
    func setAppTheme(_ theme: AppTheme) {
        appTheme = theme
        theme.persist(to: defaults)
        let appearance = theme.nsAppearance(systemIsDark: currentSystemIsDark)
        for window in NSApplication.shared.windows {
            window.appearance = appearance
        }
    }

    func setPillAppearance(_ appearance: PillAppearance) {
        pillAppearance = appearance
        appearance.persist(to: defaults)
    }

    func setPillStyle(_ style: PillStyle) {
        pillStyle = style
        style.persist(to: defaults)
    }

    /// Persists the "Background mode" preference. Does NOT apply the
    /// activation policy live — flipping `NSApp.setActivationPolicy`
    /// mid-session while a window is open produces visible weirdness
    /// (Dock icon appearing / disappearing, Cmd+Tab list shifting
    /// under the user). Instead we flag the VM so the Settings UI can
    /// render a "Restart required" note; the real policy flip happens
    /// at next launch in `PersonalScribeAppMain`, which reads this
    /// preference once on startup and calls
    /// `NSApp.setActivationPolicy(.accessory)` if true.
    ///
    /// The app's `Info.plist` no longer carries `LSUIElement: true` —
    /// launch default is `.regular`. Users who want background mode opt
    /// in via this setter.
    func setBackgroundMode(_ enabled: Bool) {
        backgroundMode = enabled
        BackgroundModePreference.persist(enabled, to: defaults)
        backgroundModeRestartRequired = true
    }

    func setLaunchAtLogin(_ enabled: Bool) {
        do {
            if enabled {
                try launchAtLoginService.register()
            } else {
                try launchAtLoginService.unregister()
            }
            launchAtLogin = launchAtLoginService.isEnabled
        } catch {
            // Registration can fail if the user denies the system prompt
            // or if the bundle is not signed. Snap the toggle to the real
            // service status — `launchAtLogin` driving the dot color in
            // GeneralTab means a failed register visibly turns the dot
            // red without needing an alert (#005).
            launchAtLogin = launchAtLoginService.isEnabled
        }
    }

    // Re-reads the injected service and publishes the current state.
    // Invoked from GeneralTab.onAppear so the dot reflects out-of-band
    // changes (e.g. the user toggled Login Items in System Settings
    // while the window was closed).
    func refreshLaunchAtLoginStatus() {
        launchAtLogin = launchAtLoginService.isEnabled
    }

    func setPasteRestoreDelaySeconds(_ seconds: TimeInterval) {
        PasteRestoreDelay.persist(to: defaults, .init(seconds: seconds))
        pasteRestoreDelay = PasteRestoreDelay.resolve(from: defaults)
    }

    var pasteRestoreDelayDescription: String {
        "After paste, wait \(Self.formatSeconds(pasteRestoreDelay.seconds))s before restoring your clipboard"
    }

    private static func formatSeconds(_ seconds: TimeInterval) -> String {
        String(format: "%.1f", seconds)
    }
}

// MARK: - Pill-style selector card (mockup-gaps D.1)

/// One of three cards shown under RECORDING WINDOW → Style. Renders a
/// LIVE SwiftUI preview of the pill shape (Classic / Mini / None),
/// reacts to `pillAppearance` so the preview's background matches the
/// resolved pill theme (`#1A1B2E` dark / `#F0EDE8` light), and
/// paints a champagne border when the card is the selected style.
///
/// Per the mockup-gaps D brief, this view does NOT wire the preference
/// back to `PillOverlayView` runtime rendering — that wiring is a
/// separate follow-up. Selecting a style here only persists the
/// preference and updates the Settings UI selection chrome.
@MainActor
private struct PillStyleSelectorCard: View {
    let style: PillStyle
    let isSelected: Bool
    let pillAppearance: PillAppearance
    let onSelect: @MainActor () -> Void

    @Environment(\.colorScheme) private var colorScheme

    /// Mockup annotation: each selector card is ~72pt tall.
    private static let cardHeight: CGFloat = 72
    private static let cardCornerRadius: CGFloat = 10
    private static let selectedBorderWidth: CGFloat = 2
    private static let unselectedBorderWidth: CGFloat = 1

    var body: some View {
        let palette = PersonalScribeTheme.Palette.for(scheme: colorScheme)

        Button(action: onSelect) {
            VStack(spacing: 8) {
                preview
                    .frame(maxWidth: .infinity, maxHeight: .infinity)

                Text(style.rawValue)
                    .font(PersonalScribeTheme.Typography.caption.font)
                    .foregroundStyle(isSelected ? palette.primaryText : palette.secondaryText)
            }
            .padding(.vertical, 10)
            .padding(.horizontal, 12)
            .frame(height: Self.cardHeight + 24)  // extra height for label + padding
            .frame(maxWidth: .infinity)
            .background(
                RoundedRectangle(cornerRadius: Self.cardCornerRadius, style: .continuous)
                    .fill(palette.surface)
            )
            .overlay(
                RoundedRectangle(cornerRadius: Self.cardCornerRadius, style: .continuous)
                    .strokeBorder(
                        isSelected
                            ? palette.brandChampagne
                            : palette.brandChampagne.opacity(0.12),
                        lineWidth: isSelected
                            ? Self.selectedBorderWidth
                            : Self.unselectedBorderWidth
                    )
            )
            .shadow(
                color: isSelected ? .black.opacity(0.15) : .clear,
                radius: isSelected ? 4 : 0,
                y: isSelected ? 2 : 0
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Pill style \(style.rawValue)")
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    // MARK: - Per-style previews

    /// Resolves the pill surface colour the preview should render against.
    /// Mirrors the `PillOverlayView` fg/bg selection rule so the preview
    /// matches what the user will see at runtime.
    private var pillBackgroundColor: Color {
        let systemIsDark = colorScheme == .dark
        let pillIsDark = pillAppearance.effectiveIsDark(systemIsDark: systemIsDark)
        return pillIsDark
            ? PersonalScribeTheme.Pill.Dark.background
            : PersonalScribeTheme.Pill.Light.background
    }

    private var pillForegroundColor: Color {
        let systemIsDark = colorScheme == .dark
        let pillIsDark = pillAppearance.effectiveIsDark(systemIsDark: systemIsDark)
        return pillIsDark
            ? PersonalScribeTheme.Pill.Dark.waveform
            : PersonalScribeTheme.Pill.Light.waveform
    }

    @ViewBuilder
    private var preview: some View {
        switch style {
        case .classic:
            classicPreview
        case .mini:
            miniPreview
        case .none:
            nonePreview
        }
    }

    /// Classic — dark-navy pill with a short waveform sketch inside.
    /// Hand-rolled mini-waveform (4 bars) rather than reusing
    /// `WaveformView` so the preview is decoupled from audio-level
    /// bindings and the `TimelineView` animation it manages.
    private var classicPreview: some View {
        RoundedRectangle(cornerRadius: 16, style: .continuous)
            .fill(pillBackgroundColor)
            .overlay(
                HStack(spacing: 3) {
                    ForEach(0..<5, id: \.self) { index in
                        Capsule()
                            .fill(pillForegroundColor)
                            .frame(width: 2, height: classicBarHeight(for: index))
                    }
                }
            )
            .frame(height: 28)
    }

    /// 4-bar preview heights — evoke a short waveform snapshot. Static
    /// so the preview is stable across redraws (no TimelineView).
    private func classicBarHeight(for index: Int) -> CGFloat {
        let heights: [CGFloat] = [6, 12, 16, 10, 7]
        return heights[index % heights.count]
    }

    /// Mini — smaller flat pill, no content. Just the shape.
    private var miniPreview: some View {
        RoundedRectangle(cornerRadius: 14, style: .continuous)
            .fill(pillBackgroundColor)
            .frame(width: 40, height: 14)
    }

    /// None — communicates "hidden". Low-opacity surface + eye.slash glyph.
    private var nonePreview: some View {
        let palette = PersonalScribeTheme.Palette.for(scheme: colorScheme)

        return ZStack {
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(pillBackgroundColor.opacity(0.25))
                .frame(width: 56, height: 28)

            Image(systemName: "eye.slash")
                .font(.system(size: 14, weight: .medium))
                .foregroundColor(palette.primaryText)
        }
    }
}

// MARK: - Shortcuts subsection view model (bug #14)

@MainActor
final class ShortcutsTabViewModel: ObservableObject {
    @Published private(set) var recordingHotkey: HotkeyPreference
    @Published private(set) var requiresRestartNotice = false

    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        self.recordingHotkey = HotkeyPreference.resolve(from: defaults)
    }

    func setRecordingHotkey(_ preference: HotkeyPreference) {
        recordingHotkey = preference
        preference.persist(to: defaults)
        requiresRestartNotice = true
    }
}

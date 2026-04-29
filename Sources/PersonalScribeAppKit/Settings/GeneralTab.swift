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
        launchAtLoginService: any LaunchAtLoginServicing = SystemLaunchAtLoginService(),
        onHotkeyUpdate: @escaping @MainActor (HotkeyPreference) -> Void = { preference in
            AppComposition.hotkeyMonitor.updateRecordingHotkey(preference)
        },
        workflowModeRegistry: WorkflowModeRegistry = AppComposition.workflowModeRegistry
    ) {
        _viewModel = StateObject(
            wrappedValue: GeneralTabViewModel(
                defaults: defaults,
                menuBarVisibilityProvider: menuBarVisibilityProvider,
                menuBarVisibilitySetter: menuBarVisibilitySetter,
                launchAtLoginService: launchAtLoginService,
                workflowModeRegistry: workflowModeRegistry
            )
        )
        _shortcutsViewModel = StateObject(
            wrappedValue: ShortcutsTabViewModel(defaults: defaults, onHotkeyUpdate: onHotkeyUpdate)
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
                    transcribeOutputCard
                    autoStopCard
                    speakerSeparationCard
                    behaviorCard
                }
            }

            shortcutsSection
        }
        .toggleStyle(.switch)
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
                Text("Always-on").tag(PillVisibility.alwaysOn)
                Text("Auto-show").tag(PillVisibility.autoShow)
                Text("Hidden").tag(PillVisibility.hidden)
            }

            if let visibilityErrorMessage = viewModel.visibilityErrorMessage {
                Divider()

                Label(visibilityErrorMessage, systemImage: "exclamationmark.triangle.fill")
                    .font(PersonalScribeTheme.Typography.caption.font)
                    .foregroundStyle(.secondary)
            }
        }
    }

    /// Transcribe output — consolidates all transcript-delivery preferences
    /// (#072). Two orthogonal toggles:
    ///
    /// - **Auto-paste to cursor** gates the synthetic Cmd+V post. Off =
    ///   clipboard-only (copy transcript, no paste attempt). On = post
    ///   Cmd+V into the focused text field (subject to #042 gates: AX
    ///   permission + focus-externality probe).
    /// - **Restore clipboard** gates the scheduled restore of the user's
    ///   pre-transcript clipboard. Off = transcript stays forever (until
    ///   the next copy). On = restore after the slider-controlled delay,
    ///   with a `changeCount` guard that skips the restore if anything
    ///   else wrote to the clipboard in the meantime (#072 Step 2).
    ///
    /// Summary caption at bottom adapts to the current toggle combination
    /// so the user can see what will actually happen without mentally
    /// simulating the flow.
    private var transcribeOutputCard: some View {
        SettingsCard {
            Text("Transcribe output")
                .font(PersonalScribeTheme.Typography.body.font.weight(.semibold))

            Toggle(
                "Auto-paste to cursor",
                isOn: Binding(
                    get: { viewModel.autoPasteEnabled },
                    set: { viewModel.setAutoPasteEnabled($0) }
                )
            )

            Divider()

            Toggle(
                "Restore clipboard",
                isOn: Binding(
                    get: { viewModel.clipboardRestoreEnabled },
                    set: { viewModel.setClipboardRestoreEnabled($0) }
                )
            )

            if viewModel.clipboardRestoreEnabled {
                VStack(alignment: .leading, spacing: SettingsLayout.inlineSpacing) {
                    Text("Restore delay")
                        .font(PersonalScribeTheme.Typography.body.font.weight(.medium))

                    Text(viewModel.clipboardRestoreDelayDescription)
                        .font(PersonalScribeTheme.Typography.caption.font)
                        .foregroundStyle(.secondary)

                    Slider(
                        value: Binding(
                            get: { viewModel.clipboardRestoreDelay.seconds },
                            set: { viewModel.setClipboardRestoreDelaySeconds($0) }
                        ),
                        in: ClipboardRestoreDelay.minimumSeconds...ClipboardRestoreDelay.maximumSeconds,
                        step: 0.1
                    )
                }
            }

            Divider()

            Text(viewModel.transcribeOutputSummary)
                .font(PersonalScribeTheme.Typography.caption.font)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
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

    /// Speaker separation sensitivity (#092) — global default for the
    /// offline diarizer's merge-vs-split tuning. Applies to all diarized
    /// recipes (currently meeting mode) unless a per-mode override is
    /// set in the Modes editor. Each preset is a hardcoded combination
    /// of FluidAudio's `clusteringThreshold` + `minSegmentDurationSeconds`
    /// codified in `SpeakerSeparationSensitivity.parameters`.
    private var speakerSeparationCard: some View {
        SettingsCard {
            Text("Speaker separation sensitivity")
                .font(PersonalScribeTheme.Typography.body.font.weight(.semibold))

            Picker(
                "",
                selection: Binding(
                    get: { viewModel.speakerSeparationSensitivity },
                    set: { viewModel.setSpeakerSeparationSensitivity($0) }
                )
            ) {
                Text("Relaxed (split speakers more easily)")
                    .tag(SpeakerSeparationSensitivity.relaxed)
                Text("Balanced (recommended)")
                    .tag(SpeakerSeparationSensitivity.balanced)
                Text("Strict (prefer stable labels)")
                    .tag(SpeakerSeparationSensitivity.strict)
            }
            .labelsHidden()
            .pickerStyle(.menu)

            Text("Tunes how aggressively meeting recordings split similar voices into separate speaker labels. Per-mode override available in the Modes editor.")
                .font(PersonalScribeTheme.Typography.caption.font)
                .foregroundStyle(.secondary)
        }
    }

    /// Residual Behavior card — Waveform decay + Mute-while-recording.
    /// Restore-delay slider moved into `transcribeOutputCard` per #072.
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

            Toggle(
                "Mute system audio while recording",
                isOn: Binding(
                    get: { viewModel.muteOutputWhileRecording },
                    set: { viewModel.setMuteOutputWhileRecording($0) }
                )
            )
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
                isAtDefault: shortcutsViewModel.recordingHotkey == .default,
                restoreDefaultAction: {
                    shortcutsViewModel.restoreDefault()
                }
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
        isAtDefault: Bool,
        restoreDefaultAction: @escaping () -> Void
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

                    HStack(spacing: SettingsLayout.inlineSpacing) {
                        Button("Restore default", action: restoreDefaultAction)
                            .disabled(isAtDefault)

                        Button("Change…", action: changeAction)
                            .disabled(changeEnabled == false)
                    }
                }
            }
        }
    }
}

@MainActor
final class GeneralTabViewModel: ObservableObject {
    struct VisibilityConfig: Equatable {
        let pillVisibilityMode: PillVisibility
        let isMenuBarVisible: Bool
    }

    enum VisibilityConfigError: Equatable {
        case conflict
    }

    @Published private(set) var pillVisibilityMode: PillVisibility
    @Published private(set) var isMenuBarVisible: Bool
    @Published private(set) var waveformDecayMode: WaveformDecayMode
    @Published private(set) var windowTint: WindowTint
    @Published private(set) var pillAppearance: PillAppearance
    @Published private(set) var pillStyle: PillStyle
    @Published private(set) var clipboardRestoreDelay: ClipboardRestoreDelay
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
    /// "Auto-paste to cursor" toggle (#072). When `true`, `ClipboardBatchOutput`
    /// posts a synthetic `Cmd+V` after writing the transcript to the
    /// clipboard (subject to the remaining AX / externality gates).
    /// When `false`, clipboard only — user pastes manually.
    @Published private(set) var autoPasteEnabled: Bool
    /// "Restore clipboard" toggle (#072). When `true`, `ClipboardBatchOutput`
    /// schedules a `changeCount`-guarded restore of the user's pre-transcript
    /// clipboard after `clipboardRestoreDelay`. When `false`, the transcript
    /// stays on the clipboard until the user writes something new.
    @Published private(set) var clipboardRestoreEnabled: Bool
    /// "Mute system audio while recording" toggle. When `true`,
    /// `AVAudioCaptureService` mutes the OS volume flag at capture start
    /// and restores the prior state on every end-of-capture path.
    /// Prevents speaker → mic bleed from polluting the transcript.
    /// Default `false` — fresh installs behave exactly as before.
    @Published private(set) var muteOutputWhileRecording: Bool
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
    /// #092 — Global default for the offline diarizer's sensitivity
    /// preset. Applies to all diarized recipes that haven't set a
    /// per-mode `.override(...)`. Recipe parameters carry
    /// `.setting(PreferenceKeys.speakerSeparationSensitivity)` by
    /// default, so flipping this value here updates every untouched
    /// diarized mode at the next session bind.
    @Published private(set) var speakerSeparationSensitivity: SpeakerSeparationSensitivity
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
    /// Per #078.33 / L27: the three structural toggles (Auto-paste,
    /// Auto-stop after silence, Restore clipboard) bridge the legacy
    /// `UserDefaults` write to a recipe mutation on the active
    /// workflow mode. Optional so existing callers and tests that
    /// don't exercise the bridge keep compiling; production wiring
    /// (`AppComposition`) always supplies it. When `nil`, setters
    /// degrade to the pre-bridge UserDefaults-only behavior.
    private let workflowModeRegistry: WorkflowModeRegistry?

    init(
        defaults: UserDefaults = .standard,
        menuBarVisibilityProvider: @escaping @MainActor () -> Bool = { true },
        menuBarVisibilitySetter: @escaping @MainActor (Bool) -> Void = { _ in },
        systemIsDarkProvider: @escaping @MainActor () -> Bool = {
            NSApplication.shared.effectiveAppearance.bestMatch(
                from: [.aqua, .darkAqua]
            ) == .darkAqua
        },
        launchAtLoginService: any LaunchAtLoginServicing = SystemLaunchAtLoginService(),
        workflowModeRegistry: WorkflowModeRegistry? = nil
    ) {
        self.defaults = defaults
        self.menuBarVisibilitySetter = menuBarVisibilitySetter
        self.systemIsDarkProvider = systemIsDarkProvider
        self.launchAtLoginService = launchAtLoginService
        self.workflowModeRegistry = workflowModeRegistry
        self.pillVisibilityMode = PillVisibility.resolve(from: defaults)
        // Snapshot-at-init: isMenuBarVisible is NOT re-read while the
        // Settings window is open. The General tab is the sole mutator
        // in Phase 3, so the snapshot is always current. If a second
        // path ever starts mutating menu-bar visibility (e.g. a hotkey
        // to toggle it), refresh here on view appear or swap to a
        // Published upstream source.
        self.isMenuBarVisible = menuBarVisibilityProvider()
        self.waveformDecayMode = WaveformDecayMode.resolve(from: defaults)
        self.windowTint = WindowTint.resolve(from: defaults)
        self.pillAppearance = PillAppearance.resolve(from: defaults)
        self.pillStyle = PillStyle.resolve(from: defaults)
        self.clipboardRestoreDelay = ClipboardRestoreDelay.resolve(from: defaults)
        // launchAtLogin seeds from the injected service. The real impl
        // (`SystemLaunchAtLoginService`) reads SMAppService.mainApp.status
        // — .enabled means the app is registered to launch at login.
        self.launchAtLogin = launchAtLoginService.isEnabled
        self.backgroundMode = BackgroundLaunchPreference.resolve(from: defaults)
        self.autoPasteEnabled = AutoPasteEnabledPreference.resolve(from: defaults)
        self.clipboardRestoreEnabled = ClipboardRestoreEnabledPreference.resolve(from: defaults)
        self.muteOutputWhileRecording = MuteOutputWhileRecordingPreference.resolve(from: defaults)
        self.vadAutoStopEnabled = VadAutoStopEnabledPreference.resolve(from: defaults)
        self.vadSilenceThresholdSeconds = VadSilenceThresholdPreference.resolve(from: defaults)
        self.vadShowStoppingWarning = VadShowStoppingWarningPreference.resolve(from: defaults)
        self.vadShowAutoStoppedNotification = VadShowAutoStoppedNotificationPreference.resolve(from: defaults)
        self.appTheme = AppTheme.resolve(from: defaults)
        self.speakerSeparationSensitivity = SpeakerSeparationSensitivityPreference.resolve(from: defaults)
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

    func setAutoPasteEnabled(_ enabled: Bool) {
        autoPasteEnabled = enabled
        AutoPasteEnabledPreference.persist(enabled, to: defaults)
        // #089 L-27: GeneralTab toggles are plain UserDefaults writes.
        // Recipes consult the value via `Parameter.setting(...)`, so
        // there's no per-recipe mutation here — every recipe that uses
        // `.frontmostPaste(enabled: .setting(...))` will pick up the
        // new value on the next session start.
    }

    func setClipboardRestoreEnabled(_ enabled: Bool) {
        clipboardRestoreEnabled = enabled
        ClipboardRestoreEnabledPreference.persist(enabled, to: defaults)
        // #089 L-27: see setAutoPasteEnabled — plain UserDefaults write.
    }

    func setMuteOutputWhileRecording(_ enabled: Bool) {
        muteOutputWhileRecording = enabled
        MuteOutputWhileRecordingPreference.persist(enabled, to: defaults)
    }

    /// Description line rendered above the silence-threshold slider. Formats
    /// the current value with one decimal, consistent with the slider step.
    var vadSilenceThresholdDescription: String {
        String(format: "%.1fs of silence before auto-stop", vadSilenceThresholdSeconds)
    }

    func setVadAutoStopEnabled(_ enabled: Bool) {
        vadAutoStopEnabled = enabled
        VadAutoStopEnabledPreference.persist(enabled, to: defaults)
        // #089 L-27: VAD auto-stop is gated by the recipe's
        // `.vad(enabled: .setting(...))` parameter; plain
        // UserDefaults write is enough.
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
    func setSpeakerSeparationSensitivity(_ sensitivity: SpeakerSeparationSensitivity) {
        speakerSeparationSensitivity = sensitivity
        SpeakerSeparationSensitivityPreference.persist(sensitivity, to: defaults)
    }

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
        BackgroundLaunchPreference.persist(enabled, to: defaults)
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

    func setClipboardRestoreDelaySeconds(_ seconds: TimeInterval) {
        ClipboardRestoreDelay.persist(to: defaults, .init(seconds: seconds))
        clipboardRestoreDelay = ClipboardRestoreDelay.resolve(from: defaults)
    }

    var clipboardRestoreDelayDescription: String {
        "After paste, wait \(Self.formatSeconds(clipboardRestoreDelay.seconds))s before restoring your clipboard"
    }

    /// Plain-English summary that adapts to the current toggle/slider
    /// state. Rendered beneath the two toggles in `transcribeOutputCard`
    /// so the user can see the concrete behavior instead of mentally
    /// simulating the two-axis state space. `changeCount` guard is
    /// baked in silently — when restore is on, the transcript is only
    /// cleared if nothing else has touched the clipboard since our write.
    var transcribeOutputSummary: String {
        let seconds = Self.formatSeconds(clipboardRestoreDelay.seconds)
        switch (autoPasteEnabled, clipboardRestoreEnabled) {
        case (true, true):
            return "Transcripts paste into the focused text field and stay on your clipboard. After \(seconds)s, your previous clipboard is restored — unless you've copied something new in the meantime."
        case (true, false):
            return "Transcripts paste into the focused text field and stay on your clipboard until you copy something else."
        case (false, true):
            return "Transcripts are copied to your clipboard. Press ⌘V to paste. After \(seconds)s, your previous clipboard is restored — unless you've copied something new."
        case (false, false):
            return "Transcripts are copied to your clipboard. Press ⌘V to paste. Your previous clipboard is not restored."
        }
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

// MARK: - Shortcuts subsection view model (#017)

@MainActor
final class ShortcutsTabViewModel: ObservableObject {
    @Published private(set) var recordingHotkey: HotkeyPreference

    private let defaults: UserDefaults
    private let onHotkeyUpdate: @MainActor (HotkeyPreference) -> Void

    init(
        defaults: UserDefaults = .standard,
        onHotkeyUpdate: @escaping @MainActor (HotkeyPreference) -> Void = { _ in }
    ) {
        self.defaults = defaults
        self.onHotkeyUpdate = onHotkeyUpdate
        self.recordingHotkey = HotkeyPreference.resolve(from: defaults)
    }

    func setRecordingHotkey(_ preference: HotkeyPreference) {
        recordingHotkey = preference
        preference.persist(to: defaults)
        onHotkeyUpdate(preference)
    }

    func restoreDefault() {
        setRecordingHotkey(.default)
    }
}

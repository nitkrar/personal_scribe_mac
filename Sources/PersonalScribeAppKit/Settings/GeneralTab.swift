import AppKit
import SwiftUI
import PersonalScribeCore
import ServiceManagement

@MainActor
public struct GeneralTab: View {
    @StateObject private var viewModel: GeneralTabViewModel
    @StateObject private var shortcutsViewModel: ShortcutsTabViewModel
    @State private var isRecordingHotkeyRecorderPresented = false

    public init(
        defaults: UserDefaults = .standard,
        menuBarVisibilityProvider: @escaping @MainActor () -> Bool = { true },
        menuBarVisibilitySetter: @escaping @MainActor (Bool) -> Void = { _ in }
    ) {
        _viewModel = StateObject(
            wrappedValue: GeneralTabViewModel(
                defaults: defaults,
                menuBarVisibilityProvider: menuBarVisibilityProvider,
                menuBarVisibilitySetter: menuBarVisibilitySetter
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

            Toggle(
                "Launch at login",
                isOn: Binding(
                    get: { viewModel.launchAtLogin },
                    set: { viewModel.setLaunchAtLogin($0) }
                )
            )

            Divider()

            Toggle(
                "Show in Dock",
                isOn: Binding(
                    get: { viewModel.showInDock },
                    set: { viewModel.setShowInDock($0) }
                )
            )
        }
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
                footnoteIcon: "arrow.clockwise",
                footnote: shortcutsViewModel.requiresRestartNotice
                    ? "Restart required: relaunch \(AppBrand.displayName) before the new recording hotkey takes effect."
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
        footnoteIcon: String,
        footnote: String?
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

            if let footnote {
                Divider()

                Label(footnote, systemImage: footnoteIcon)
                    .font(PersonalScribeTheme.Typography.caption.font)
                    .foregroundStyle(.secondary)
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
    @Published private(set) var showInDock: Bool
    @Published private(set) var pasteEnabled: Bool

    private let defaults: UserDefaults
    private let menuBarVisibilitySetter: @MainActor (Bool) -> Void

    init(
        defaults: UserDefaults = .standard,
        menuBarVisibilityProvider: @escaping @MainActor () -> Bool = { true },
        menuBarVisibilitySetter: @escaping @MainActor (Bool) -> Void = { _ in }
    ) {
        self.defaults = defaults
        self.menuBarVisibilitySetter = menuBarVisibilitySetter
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
        // SMAppService.mainApp.status reflects the current registration
        // state. .enabled means the app is registered to launch at login.
        self.launchAtLogin = SMAppService.mainApp.status == .enabled
        self.showInDock = ShowInDockPreference.resolve(from: defaults)
        self.pasteEnabled = PasteEnabledPreference.resolve(from: defaults)
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

    func setWindowTint(_ tint: WindowTint) {
        windowTint = tint
        tint.persist(to: defaults)
    }

    func setPillAppearance(_ appearance: PillAppearance) {
        pillAppearance = appearance
        appearance.persist(to: defaults)
    }

    func setPillStyle(_ style: PillStyle) {
        pillStyle = style
        style.persist(to: defaults)
    }

    /// Persists the "Show in Dock" preference AND applies the new
    /// activation policy so the Dock icon is added / removed at
    /// runtime. `.regular` shows the app in the Dock; `.accessory`
    /// runs it as a menu-bar / pill-only process (LSUIElement-style).
    ///
    /// No cross-check against menu-bar / pill visibility: the brief
    /// keeps Show in Dock independent. If a user hides the menu bar
    /// AND pill AND Dock, they can still reach the app via hotkey
    /// (⌥/) — no conflict error is surfaced here.
    func setShowInDock(_ enabled: Bool) {
        showInDock = enabled
        ShowInDockPreference.persist(enabled, to: defaults)
        // `GeneralTabViewModel` is already `@MainActor`-isolated;
        // `NSApp.setActivationPolicy` therefore runs on the main
        // thread without additional dispatch. `NSApp` resolves to the
        // same shared application the unified window was created
        // under — safe to touch directly.
        NSApp.setActivationPolicy(enabled ? .regular : .accessory)
    }

    func setLaunchAtLogin(_ enabled: Bool) {
        do {
            if enabled {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
            launchAtLogin = SMAppService.mainApp.status == .enabled
        } catch {
            // Registration can fail if the user denies the system prompt
            // or if the bundle is not signed. Silently refresh the toggle
            // to reflect the actual state rather than the requested state.
            launchAtLogin = SMAppService.mainApp.status == .enabled
        }
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

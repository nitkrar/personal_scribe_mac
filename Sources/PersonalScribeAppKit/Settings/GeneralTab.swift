import SwiftUI
import PersonalScribeCore

@MainActor
public struct GeneralTab: View {
    @StateObject private var viewModel: GeneralTabViewModel

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
    }

    public var body: some View {
        SettingsTabContainer {
            SettingsSection(
                title: "General",
                description: "Core defaults for the pill overlay, menu bar surface, and transcript delivery."
            ) {
                VStack(alignment: .leading, spacing: SettingsLayout.itemSpacing) {
                    visibilityCard
                    appearanceCard
                    behaviorCard
                }
            }
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
                Text("Dark").tag(WindowTint.dark)
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
    @Published private(set) var pasteRestoreDelay: PasteRestoreDelay
    @Published private(set) var visibilityError: VisibilityConfigError?

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
        self.pasteRestoreDelay = PasteRestoreDelay.resolve(from: defaults)
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

    func setWindowTint(_ tint: WindowTint) {
        windowTint = tint
        tint.persist(to: defaults)
    }

    func setPillAppearance(_ appearance: PillAppearance) {
        pillAppearance = appearance
        appearance.persist(to: defaults)
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

import SwiftUI
import SeshatCore

@MainActor
public struct GeneralTab: View {
    private let defaults: UserDefaults
    private let menuBarVisibilityProvider: @MainActor () -> Bool
    private let menuBarVisibilitySetter: @MainActor (Bool) -> Void

    @State private var pillVisibilityMode: PillVisibilityMode
    @State private var waveformDecayMode: WaveformDecayMode
    @State private var pasteMode: SeshatPasteMode

    public init(
        defaults: UserDefaults = .standard,
        menuBarVisibilityProvider: @escaping @MainActor () -> Bool = { true },
        menuBarVisibilitySetter: @escaping @MainActor (Bool) -> Void = { _ in }
    ) {
        self.defaults = defaults
        self.menuBarVisibilityProvider = menuBarVisibilityProvider
        self.menuBarVisibilitySetter = menuBarVisibilitySetter
        _pillVisibilityMode = State(initialValue: PillVisibilityMode.resolve(from: defaults))
        _waveformDecayMode = State(initialValue: WaveformDecayMode.resolve(from: defaults))
        _pasteMode = State(initialValue: SeshatPasteMode.resolve(from: defaults))
    }

    public var body: some View {
        SettingsTabContainer {
            SettingsSection(
                title: "General",
                description: "Core defaults for the pill overlay and transcript delivery."
            ) {
                SettingsCard {
                    Picker(
                        "Pill visibility",
                        selection: Binding(
                            get: { pillVisibilityMode },
                            set: { newValue in
                                pillVisibilityMode = newValue
                                newValue.persist(to: defaults)
                            }
                        )
                    ) {
                        Text("Always-on").tag(PillVisibilityMode.alwaysOn)
                        Text("Auto-show").tag(PillVisibilityMode.autoShow)
                        Text("Hidden").tag(PillVisibilityMode.hidden)
                    }

                    Divider()

                    Picker(
                        "Waveform decay",
                        selection: Binding(
                            get: { waveformDecayMode },
                            set: { newValue in
                                waveformDecayMode = newValue
                                newValue.persist(to: defaults)
                            }
                        )
                    ) {
                        Text("Immediate").tag(WaveformDecayMode.immediate)
                        Text("Animated").tag(WaveformDecayMode.animated)
                    }

                    Divider()

                    Picker(
                        "Paste mode",
                        selection: Binding(
                            get: { pasteMode },
                            set: { newValue in
                                pasteMode = newValue
                                newValue.persist(to: defaults)
                            }
                        )
                    ) {
                        Text("Paste-at-cursor").tag(SeshatPasteMode.pasteAtCursor)
                        Text("Clipboard-only").tag(SeshatPasteMode.clipboardOnly)
                    }
                }
            }
        }
    }
}

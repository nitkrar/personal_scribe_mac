import SwiftUI
import PersonalScribeCore

@MainActor
public struct ShortcutsTab: View {
    @StateObject private var viewModel: ShortcutsTabViewModel
    @State private var isRecordingHotkeyRecorderPresented = false

    public init(defaults: UserDefaults = .standard) {
        _viewModel = StateObject(
            wrappedValue: ShortcutsTabViewModel(defaults: defaults)
        )
    }

    public var body: some View {
        SettingsTabContainer {
            SettingsSection(
                title: "Shortcuts",
                description: "Customize the recording toggle. Emergency quit remains fixed."
            ) {
                VStack(alignment: .leading, spacing: SettingsLayout.itemSpacing) {
                    shortcutCard(
                        title: "Record / stop dictation",
                        shortcut: HotkeyShortcutFormatter.displayString(for: viewModel.recordingHotkey),
                        notes: "Starts a session from idle and stops the active session.",
                        changeAction: {
                            isRecordingHotkeyRecorderPresented = true
                        },
                        changeEnabled: true,
                        footnoteIcon: "arrow.clockwise",
                        footnote: viewModel.requiresRestartNotice
                            ? "Restart required: relaunch \(AppBrand.displayName) before the new recording hotkey takes effect."
                            : nil
                    )

                    shortcutCard(
                        title: "Emergency quit",
                        shortcut: "Triple-tap ⌥",
                        notes: "Immediately exits \(AppBrand.displayName) when the monitor is active.",
                        changeAction: {},
                        changeEnabled: false,
                        footnoteIcon: "info.circle",
                        footnote: "Triple-tap option remains fixed in Phase 3.G."
                    )
                }
            }
        }
        .sheet(isPresented: $isRecordingHotkeyRecorderPresented) {
            HotkeyRecorder(
                currentPreference: viewModel.recordingHotkey,
                onConfirm: { preference in
                    viewModel.setRecordingHotkey(preference)
                    isRecordingHotkeyRecorderPresented = false
                },
                onCancel: {
                    isRecordingHotkeyRecorderPresented = false
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

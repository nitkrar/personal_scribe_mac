import SwiftUI

@MainActor
public struct ShortcutsTab: View {
    private let shortcuts: [ShortcutDescriptor] = [
        ShortcutDescriptor(
            id: "record",
            title: "Record / stop dictation",
            shortcut: "Double-tap ⌥",
            notes: "Starts a session from idle and stops the active session."
        ),
        ShortcutDescriptor(
            id: "quit",
            title: "Emergency quit",
            shortcut: "Triple-tap ⌥",
            notes: "Immediately exits Seshat when the monitor is active."
        ),
    ]

    public init() { }

    public var body: some View {
        SettingsTabContainer {
            SettingsSection(
                title: "Shortcuts",
                description: "Reference for the currently fixed global hotkeys."
            ) {
                VStack(alignment: .leading, spacing: SettingsLayout.itemSpacing) {
                    ForEach(shortcuts) { shortcut in
                        SettingsCard {
                            HStack(alignment: .firstTextBaseline) {
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(shortcut.title)
                                        .font(SeshatTheme.Typography.body.font.weight(.semibold))
                                    Text(shortcut.notes)
                                        .font(SeshatTheme.Typography.caption.font)
                                        .foregroundStyle(.secondary)
                                }

                                Spacer(minLength: 0)

                                Text(shortcut.shortcut)
                                    .font(.system(size: 12, weight: .semibold, design: .monospaced))
                                    .textSelection(.enabled)
                            }
                        }
                    }

                    Text("Shortcut customization lands in Phase 3.G.")
                        .font(SeshatTheme.Typography.caption.font)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }
}

private struct ShortcutDescriptor: Identifiable {
    let id: String
    let title: String
    let shortcut: String
    let notes: String
}

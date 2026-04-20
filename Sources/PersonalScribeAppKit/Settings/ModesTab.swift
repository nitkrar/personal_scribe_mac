import SwiftUI
import PersonalScribeCore

@MainActor
public struct ModesTab: View {
    private let modes: [ModeDescriptor]
    private let activeModeID: String

    public init(
        modes: [ModeDescriptor] = ModeRegistry.all,
        activeModeID: String = ModeRegistry.defaultModeID
    ) {
        self.modes = modes
        self.activeModeID = activeModeID
    }

    public var body: some View {
        SettingsTabContainer {
            SettingsSection(
                title: "Modes",
                description: "Preset voice-model and AI-instruction combinations."
            ) {
                VStack(alignment: .leading, spacing: SettingsLayout.itemSpacing) {
                    ForEach(modes) { mode in
                        ModeCard(
                            modeName: mode.name,
                            voiceModel: voiceModelName(for: mode),
                            aiModelPreset: mode.aiModelID ?? "No AI",
                            isActive: mode.id == activeModeID
                        )
                    }

                    Text("Mode editing lands in a later slice. The default Dictation mode is read-only here.")
                        .font(PersonalScribeTheme.Typography.caption.font)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    private func voiceModelName(for mode: ModeDescriptor) -> String {
        BuiltInModelCatalog.descriptor(for: mode.voiceModelID)?.displayName ?? mode.voiceModelID
    }
}

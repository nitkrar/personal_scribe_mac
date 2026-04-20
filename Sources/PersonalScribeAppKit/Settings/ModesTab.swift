import SwiftUI
import PersonalScribeCore

/// Legacy read-only Modes tab inside the old TabView-based settings
/// window. Retained until the unified-window `ModesTab` proves live
/// and PHASE_2_unified_ui.md Step 2.10 retires this surface.
///
/// Renamed from `ModesTab` to avoid a top-level type-name collision
/// with `UnifiedWindow/Tabs/ModesTab.swift` (M3.4).
@MainActor
public struct LegacySettingsModesTab: View {
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

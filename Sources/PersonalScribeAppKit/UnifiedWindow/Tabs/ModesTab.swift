import PersonalScribeCore
import SwiftUI

/// Modes tab for the unified NavigationSplitView window (M3.4).
///
/// Renders a vertical stack of `ModeCard` rows — one per available
/// mode — with the active-state indicator baked into each card. The
/// list source and active-mode derivation both live in
/// `ModesTabViewModel`; this view stays a pure projection.
///
/// Reference: `plans/App UI design/Claude_Final_Bundle_Prompt.md` §3C —
/// "List of available modes (Dictation, Command, Notes) as cards.
/// Show active state with a green dot."
///
/// The existing `ModeCard` composite (Phase 2 Sprint 2) renders the
/// active state via a ready-state `StatusPill`. Per the reference, the
/// pill's green indicator IS the "green dot" — reusing ModeCard keeps
/// the Modes tab consistent with every other mode surface (onboarding,
/// legacy settings).
@MainActor
struct ModesTab: View {
    @ObservedObject private var viewModel: ModesTabViewModel

    init(viewModel: ModesTabViewModel) {
        self.viewModel = viewModel
    }

    var body: some View {
        VStack(alignment: .leading, spacing: PersonalScribeTheme.Spacing.lg) {
            Text("Modes")
                .font(PersonalScribeTheme.Typography.largeTitle.font)

            VStack(alignment: .leading, spacing: PersonalScribeTheme.Spacing.md) {
                ForEach(viewModel.modes) { mode in
                    ModeCard(
                        modeName: mode.name,
                        voiceModel: voiceModelName(for: mode),
                        aiModelPreset: aiModelPresetName(for: mode),
                        isActive: viewModel.isActive(mode)
                    )
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: - Derivation helpers
    //
    // Matches the existing legacy ModesTab (`Settings/ModesTab.swift`)
    // formatting so the unified-window surface reads identically until
    // the legacy surface is retired (PHASE_2_unified_ui.md Step 2.10).

    private func voiceModelName(for mode: ModeDescriptor) -> String {
        BuiltInModelCatalog.descriptor(for: mode.voiceModelID)?.displayName
            ?? mode.voiceModelID
    }

    private func aiModelPresetName(for mode: ModeDescriptor) -> String {
        mode.aiModelID ?? "No AI"
    }
}

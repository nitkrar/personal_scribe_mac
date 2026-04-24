import PersonalScribeCore
import PersonalScribeSession
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
    @ObservedObject private var modelService: DefaultModelService

    init(
        viewModel: ModesTabViewModel,
        modelService: DefaultModelService = AppComposition.modelService
    ) {
        self.viewModel = viewModel
        self.modelService = modelService
    }

    var body: some View {
        VStack(alignment: .leading, spacing: PersonalScribeTheme.Spacing.lg) {
            Text("Modes")
                .font(PersonalScribeTheme.Typography.largeTitle.font)

            VStack(alignment: .leading, spacing: PersonalScribeTheme.Spacing.md) {
                // #024 follow-up: only show modes whose voice model is
                // on disk. Modes pointing at not-downloaded voice models
                // are hidden so `setActive` never fires on a missing
                // model. User downloads via the AI Models tab first.
                ForEach(downloadedModes) { mode in
                    ModeCard(
                        modeName: mode.name,
                        voiceModel: voiceModelName(for: mode),
                        aiModelPreset: aiModelPresetName(for: mode),
                        isActive: viewModel.isActive(mode),
                        onSetActive: viewModel.isActive(mode) ? nil : {
                            Task { await viewModel.setActive(mode) }
                        }
                    )
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var downloadedModes: [ModeDescriptor] {
        viewModel.modes.filter { mode in
            modelService.downloadStates[mode.voiceModelID]?.phase == .ready
        }
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

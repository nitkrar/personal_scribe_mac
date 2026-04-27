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
/// #078.36: post-cutover, `WorkflowMode` no longer carries a per-mode
/// `voiceModelID` / `aiModelID` (per L23 — recipes reference Kinds,
/// runtime late-binds via `ActiveModelService.activeDescriptor(for:)`).
/// All visible modes share the active asr descriptor for display
/// purposes. The card's voice-model row mirrors that single value;
/// per-mode override of voice model is a Modes-editor follow-up.
@MainActor
struct ModesTab: View {
    @ObservedObject private var viewModel: ModesTabViewModel
    @ObservedObject private var modelService: ActiveModelService

    init(
        viewModel: ModesTabViewModel,
        modelService: ActiveModelService = AppComposition.modelService
    ) {
        self.viewModel = viewModel
        self.modelService = modelService
    }

    var body: some View {
        VStack(alignment: .leading, spacing: PersonalScribeTheme.Spacing.lg) {
            Text("Modes")
                .font(PersonalScribeTheme.Typography.largeTitle.font)

            VStack(alignment: .leading, spacing: PersonalScribeTheme.Spacing.md) {
                // #024 follow-up: only show modes when there's an
                // active asr descriptor that's downloaded. Without one,
                // setActive would land on a missing model — the user
                // must download via the AI Models tab first.
                ForEach(visibleModes, id: \.id) { mode in
                    ModeCard(
                        modeName: mode.name,
                        voiceModel: activeVoiceModelName,
                        aiModelPreset: "No AI",
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

    private var visibleModes: [WorkflowMode] {
        guard
            let activeASR = modelService.activeDescriptor(for: .asr),
            modelService.downloadStates[activeASR.id]?.phase == .ready
        else {
            return []
        }
        return viewModel.modes
    }

    private var activeVoiceModelName: String {
        guard let activeASR = modelService.activeDescriptor(for: .asr) else {
            return "—"
        }
        return activeASR.displayName
    }
}

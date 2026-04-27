import Combine
import Foundation
import PersonalScribeCore
import PersonalScribeSession

/// View model for the unified-window Modes tab (M3.4).
///
/// Owns the list of available modes (sourced from the registry's
/// `allModes`) plus a published `activeModeID` driven by the
/// `WorkflowModeRegistry`'s active-mode stream.
///
/// #078.36: previously took an `ActiveModelService` and matched modes
/// to the active asr id by `voiceModelID`. Post-cutover, modes
/// reference Kinds (per L23) rather than concrete voice-model ids;
/// active-mode tracking moves to the registry directly.
@MainActor
public final class ModesTabViewModel: ObservableObject {
    /// All modes to render as cards in the tab.
    @Published public private(set) var modes: [WorkflowMode]

    /// Identifier of the currently-active mode. Drives the green-dot /
    /// active-state indicator on each card.
    @Published public private(set) var activeModeID: String

    private let registry: WorkflowModeRegistry?
    private let setActiveHandler: (@MainActor (WorkflowMode) async -> Void)?
    private var observationTask: Task<Void, Never>?

    public init(
        modes: [WorkflowMode] = WorkflowModeRegistry.builtInModes,
        registry: WorkflowModeRegistry? = nil,
        setActiveHandler: (@MainActor (WorkflowMode) async -> Void)? = nil
    ) {
        self.modes = modes
        self.registry = registry
        self.setActiveHandler = setActiveHandler
        self.activeModeID = registry?.activeMode.id ?? WorkflowMode.dictation.id

        if let registry {
            let stream = registry.activeModeStream()
            observationTask = Task { [weak self] in
                for await mode in stream {
                    guard let self else { return }
                    await MainActor.run {
                        self.activeModeID = mode.id
                    }
                }
            }
        }
    }

    deinit {
        observationTask?.cancel()
    }

    /// `true` if `mode` matches the currently-active mode id.
    public func isActive(_ mode: WorkflowMode) -> Bool {
        mode.id == activeModeID
    }

    /// Flip the active mode via the injected `setActiveHandler`. The
    /// registry's `activeModeStream()` then pushes the new id back
    /// through the observation loop, keeping the tab in lock-step.
    public func setActive(_ mode: WorkflowMode) async {
        guard let setActiveHandler else { return }
        await setActiveHandler(mode)
    }
}

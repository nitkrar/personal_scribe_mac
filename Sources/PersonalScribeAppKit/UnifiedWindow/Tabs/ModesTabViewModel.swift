import Combine
import Foundation
import PersonalScribeCore
import PersonalScribeSession

/// View model for the unified-window Modes tab (M3.4).
///
/// Owns the list of available modes plus a published `activeModeID`
/// derived from the injected `ActiveModelService`'s `.asr` slot. Kept
/// UI-free so it can be exercised directly by XCTest — see
/// `ModesTabViewModelTests`.
///
/// Reference: `plans/App UI design/Claude_Final_Bundle_Prompt.md` §3C —
/// "List of available modes (Dictation, Command, Notes) as cards. Show
/// active state with a green dot."
///
/// Phase-3 step #024.10: previously took an `activeModeProvider` /
/// `activeModeStream` closure pair sourced from the deleted
/// `AppKitActiveModeProvider`. Now reads the central
/// `ActiveModelService` directly and tracks `$activeModelIDs` via
/// Combine so the green dot follows AI Models tab activations live.
@MainActor
public final class ModesTabViewModel: ObservableObject {
    /// All modes to render as cards in the tab.
    @Published public private(set) var modes: [ModeDescriptor]

    /// Identifier of the currently-active mode, if any. Drives the
    /// green-dot / active-state indicator on each card.
    @Published public private(set) var activeModeID: String?

    private let modelService: ActiveModelService?
    private let setActiveHandler: (@MainActor (ModeDescriptor) async -> Void)?
    private var cancellables: Set<AnyCancellable> = []

    public init(
        modes: [ModeDescriptor] = ModeRegistry.all,
        modelService: ActiveModelService? = nil,
        setActiveHandler: (@MainActor (ModeDescriptor) async -> Void)? = nil
    ) {
        self.modes = modes
        self.modelService = modelService
        self.setActiveHandler = setActiveHandler
        self.activeModeID = Self.deriveActiveModeID(
            modes: modes,
            modelService: modelService
        )

        if let modelService {
            modelService.$activeModelIDs
                .sink { [weak self] activeIDs in
                    guard let self else { return }
                    let asrID = activeIDs[.asr]
                    self.activeModeID = self.modes.first { $0.voiceModelID == asrID }?.id
                }
                .store(in: &cancellables)
        }
    }

    /// Re-read the underlying service and republish `activeModeID` if
    /// it changed. Callsites should invoke this when the underlying
    /// active-mode source is known to have changed (e.g. on view
    /// appearance).
    public func refreshActiveMode() {
        let newID = Self.deriveActiveModeID(
            modes: modes,
            modelService: modelService
        )
        if newID != activeModeID {
            activeModeID = newID
        }
    }

    /// `true` if `mode` matches the currently-active mode id.
    public func isActive(_ mode: ModeDescriptor) -> Bool {
        guard let activeModeID else { return false }
        return mode.id == activeModeID
    }

    /// Flip the active mode via the injected `setActiveHandler`. The
    /// service's `$activeModelIDs` publisher then pushes the new id
    /// back through the Combine subscription, keeping the tab in
    /// lock-step.
    public func setActive(_ mode: ModeDescriptor) async {
        guard let setActiveHandler else { return }
        await setActiveHandler(mode)
    }

    private static func deriveActiveModeID(
        modes: [ModeDescriptor],
        modelService: ActiveModelService?
    ) -> String? {
        guard
            let modelService,
            let activeASRID = modelService.activeDescriptor(for: .asr)?.id
        else {
            return nil
        }
        return modes.first { $0.voiceModelID == activeASRID }?.id
    }
}

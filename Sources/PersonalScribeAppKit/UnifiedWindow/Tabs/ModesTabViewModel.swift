import Foundation
import PersonalScribeCore

/// View model for the unified-window Modes tab (M3.4).
///
/// Owns the list of available modes plus a published `activeModeID`
/// derived from an injected `activeModeProvider` closure. Kept UI-free
/// so it can be exercised directly by XCTest — see
/// `ModesTabViewModelTests`.
///
/// Reference: `plans/App UI design/Claude_Final_Bundle_Prompt.md` §3C —
/// "List of available modes (Dictation, Command, Notes) as cards. Show
/// active state with a green dot."
@MainActor
public final class ModesTabViewModel: ObservableObject {
    /// All modes to render as cards in the tab.
    @Published public private(set) var modes: [ModeDescriptor]

    /// Identifier of the currently-active mode, if any. Drives the
    /// green-dot / active-state indicator on each card.
    @Published public private(set) var activeModeID: String?

    /// Closure used to read the current active mode from the app
    /// state. Kept as a plain closure (no protocol dependency) so
    /// tests can inject a mutable reference with no ceremony.
    private let activeModeProvider: @MainActor () -> ModeDescriptor?

    public init(
        modes: [ModeDescriptor] = ModeRegistry.all,
        activeModeProvider: @escaping @MainActor () -> ModeDescriptor? = { nil }
    ) {
        self.modes = modes
        self.activeModeProvider = activeModeProvider
        self.activeModeID = activeModeProvider()?.id
    }

    /// Re-read `activeModeProvider` and republish `activeModeID` if it
    /// changed. Callsites should invoke this when the underlying
    /// active-mode source is known to have changed (e.g. on view
    /// appearance, or after an app-store snapshot update).
    public func refreshActiveMode() {
        let newID = activeModeProvider()?.id
        if newID != activeModeID {
            activeModeID = newID
        }
    }

    /// `true` if `mode` matches the currently-active mode id.
    public func isActive(_ mode: ModeDescriptor) -> Bool {
        guard let activeModeID else { return false }
        return mode.id == activeModeID
    }
}

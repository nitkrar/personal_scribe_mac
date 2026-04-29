import AppKit
import Foundation
import PersonalScribeCore

/// Global Esc-key monitor for the pill UX (spec §3: "Click ✕ or press
/// Esc | Pill is .holdToRecord or .recording | Discard audio; enter
/// .cancelled; show Cancel Card").
///
/// # Why not `.onKeyPress(.escape)`
///
/// The pill panel is non-activating (Issue 6) — `DraggablePanel.canBecomeKey
/// = false`. A non-key window cannot deliver `keyDown` to SwiftUI content,
/// so SwiftUI's `.onKeyPress` never fires.
///
/// # Wiring (post-#028)
///
/// `EscapeKeyMonitor` registers two subscriptions on the shared
/// `KeyEventRouter`:
///
/// * **Local decider** (`registerLocalDecider`) for keystrokes
///   delivered to Ninimma itself — needed since Ninimma launches as a
///   `.regular` app and can be frontmost while the user records
///   (Settings open, Notes window open, dock-icon focused). Returns
///   `true` to swallow when `onEscapePressed()` claims the event so it
///   doesn't bubble to text fields / SwiftUI handlers.
/// * **Global observer** (`registerGlobalObserver`) for keystrokes
///   delivered to OTHER apps — the canonical "user is recording into a
///   text editor and presses Esc" path. Observe-only by NSEvent
///   global-monitor design; we react but don't (and can't) swallow.
///
/// Pre-#028, this monitor owned its own NSEvent install/uninstall
/// pair. The router-based wiring centralizes monitor lifecycle and
/// makes registration order explicit (Esc registers first at app
/// launch, ahead of the recording-hotkey decider).
///
/// # Filter
///
/// `handle(event:)` returns `true` only when the closure handled the
/// event. The filter requires:
/// * Event type `.keyDown`
/// * `keyCode == 53` (Escape)
/// * No modifier keys held (plain Esc — not Cmd+Esc / Option+Esc)
/// * `onEscapePressed()` itself returned `true` (caller decided to act)
///
/// Keeps Esc unambiguous when recording is active without breaking
/// normal Esc behaviour when idle.
@MainActor
public final class EscapeKeyMonitor {
    /// Escape key `keyCode` on all supported macOS keyboards.
    public static let escapeKeyCode: UInt16 = 53

    private static let blockingModifierMask: NSEvent.ModifierFlags = [
        .command,
        .control,
        .option,
        .shift,
    ]

    private let router: KeyEventRouter
    private let onEscapePressed: @MainActor () -> Bool
    private var localToken: KeyEventRouterToken?
    private var globalToken: KeyEventRouterToken?

    public init(
        router: KeyEventRouter,
        onEscapePressed: @escaping @MainActor () -> Bool
    ) {
        self.router = router
        self.onEscapePressed = onEscapePressed
    }

    public var isActive: Bool {
        localToken != nil || globalToken != nil
    }

    public func start() {
        guard localToken == nil, globalToken == nil else { return }
        localToken = router.registerLocalDecider { [weak self] event in
            self?.handle(event: event) ?? false
        }
        globalToken = router.registerGlobalObserver { [weak self] event in
            _ = self?.handle(event: event)
        }
    }

    public func stop() {
        // Tokens' RAII deinit auto-unregisters via the router's
        // Task-dispatched cleanup. Setting to nil drops the strong
        // refs.
        localToken = nil
        globalToken = nil
    }

    @discardableResult
    internal func handle(event: HotkeyEvent) -> Bool {
        guard event.type == .keyDown else { return false }
        guard event.keyCode == Self.escapeKeyCode else { return false }
        let activeModifiers = event.modifierFlags.intersection(Self.blockingModifierMask)
        guard activeModifiers.isEmpty else { return false }

        return onEscapePressed()
    }
}

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
/// # Wiring
///
/// * **Local decider** — keystrokes delivered to Ninimma itself (it can
///   be frontmost while recording); swallows when `onEscapePressed()`
///   claims the event.
/// * **Registered chord** — while armed (`setArmed(true)`, i.e. during a
///   recording) Esc is registered with macOS as a hot key, so it cancels
///   and is swallowed in every app; disarming releases it immediately.
/// * **Global observer** — observe-only fallback if macOS refused the
///   Esc registration: still cancels, can't swallow.
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
    private var globalDeciderToken: KeyEventRouterToken?
    private var globalToken: KeyEventRouterToken?
    /// Esc registered with macOS while armed (recording), so it's
    /// swallowed for other apps only then. Nil when disarmed.
    private var escapeRegistration: KeyEventRouterChordRegistration?

    public init(
        router: KeyEventRouter,
        onEscapePressed: @escaping @MainActor () -> Bool
    ) {
        self.router = router
        self.onEscapePressed = onEscapePressed
    }

    public var isActive: Bool {
        localToken != nil || globalDeciderToken != nil || globalToken != nil
    }

    public func start() {
        guard localToken == nil, globalToken == nil else { return }
        localToken = router.registerLocalDecider { [weak self] event in
            self?.handle(event: event) ?? false
        }
        // Registered-chord path: receives Esc while armed (see setArmed).
        globalDeciderToken = router.registerGlobalDecider { [weak self] event in
            self?.handle(event: event) ?? false
        }
        // Fallback when macOS refused the Esc registration: the
        // observe-only monitor still cancels, but can't swallow. Quiet
        // while Esc is registered so one press doesn't cancel twice.
        globalToken = router.registerGlobalObserver { [weak self] event in
            guard let self, self.escapeRegistration?.isRegistered != true else { return }
            _ = self.handle(event: event)
        }
    }

    /// Arm while a recording is active: registers Esc as a hot key so it
    /// cancels and is swallowed; disarming releases it immediately so Esc
    /// behaves normally in every app again.
    public func setArmed(_ armed: Bool) {
        guard armed != (escapeRegistration != nil) else { return }
        escapeRegistration = armed
            ? router.registerGlobalChord(HotkeyChord(keyCode: Self.escapeKeyCode, modifiers: []))
            : nil
    }

    public func stop() {
        // Tokens' RAII deinit auto-unregisters via the router's
        // Task-dispatched cleanup. Setting to nil drops the strong
        // refs.
        localToken = nil
        globalDeciderToken = nil
        globalToken = nil
        escapeRegistration = nil
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

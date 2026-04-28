import AppKit
import Foundation
import PersonalScribeCore

/// `NSEvent` is not `Sendable`, but `addLocalMonitorForEvents`
/// callbacks are documented to run on the main thread — there is no
/// real cross-thread hop to guard against. This box lets us pass the
/// event through `MainActor.assumeIsolated` without fighting strict
/// concurrency.
private struct NSEventBox: @unchecked Sendable {
    let event: NSEvent
}

/// Global Esc-key monitor for the pill UX (spec §3: "Click ✕ or press
/// Esc | Pill is .holdToRecord or .recording | Discard audio; enter
/// .cancelled; show Cancel Card").
///
/// Why not `.onKeyPress(.escape)`:
///
/// The pill panel is non-activating (Issue 6) — `DraggablePanel.canBecomeKey
/// = false`. A non-key window cannot deliver `keyDown` to SwiftUI content,
/// so SwiftUI's `.onKeyPress` never fires.
///
/// # Two installer legs
///
/// * `installGlobal` (`NSEvent.addGlobalMonitorForEvents`) sees keystrokes
///   delivered to OTHER apps — the canonical "user is recording into a
///   text editor and presses Esc" path.
/// * `installLocal` (`NSEvent.addLocalMonitorForEvents`) sees keystrokes
///   delivered to Ninimma itself — needed since Ninimma now launches as
///   a `.regular` app (commit `6c6505f`) and can be frontmost while the
///   user records (Settings open, Notes window open, dock-icon focused).
///   Without this leg Esc was a no-op whenever Ninimma had focus.
///
/// Both legs share the same TCC grant as `GlobalHotkeyMonitor`, so
/// adding the local leg costs no additional permission.
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
/// The local monitor uses the return value to decide whether to swallow
/// the event (`nil`) or pass it through. Keeps Esc unambiguous when
/// recording is active without breaking normal Esc behaviour when idle.
@MainActor
public final class EscapeKeyMonitor {
    public typealias GlobalInstaller = @MainActor (
        _ mask: NSEvent.EventTypeMask,
        _ handler: @escaping (NSEvent) -> Void
    ) -> Any?
    public typealias LocalInstaller = @MainActor (
        _ mask: NSEvent.EventTypeMask,
        _ handler: @escaping (NSEvent) -> NSEvent?
    ) -> Any?
    public typealias Uninstaller = @MainActor (Any) -> Void

    /// Escape key `keyCode` on all supported macOS keyboards.
    public static let escapeKeyCode: UInt16 = 53

    private static let blockingModifierMask: NSEvent.ModifierFlags = [
        .command,
        .control,
        .option,
        .shift,
    ]

    private let onEscapePressed: @MainActor () -> Bool
    private let installGlobal: GlobalInstaller
    private let installLocal: LocalInstaller
    private let uninstall: Uninstaller
    private var globalMonitor: Any?
    private var localMonitor: Any?

    public convenience init(onEscapePressed: @escaping @MainActor () -> Bool) {
        self.init(
            onEscapePressed: onEscapePressed,
            installGlobal: { mask, handler in
                NSEvent.addGlobalMonitorForEvents(matching: mask, handler: handler)
            },
            installLocal: { mask, handler in
                NSEvent.addLocalMonitorForEvents(matching: mask, handler: handler)
            },
            uninstall: { handle in
                NSEvent.removeMonitor(handle)
            }
        )
    }

    init(
        onEscapePressed: @escaping @MainActor () -> Bool,
        installGlobal: @escaping GlobalInstaller,
        installLocal: @escaping LocalInstaller,
        uninstall: @escaping Uninstaller
    ) {
        self.onEscapePressed = onEscapePressed
        self.installGlobal = installGlobal
        self.installLocal = installLocal
        self.uninstall = uninstall
    }

    public var isActive: Bool {
        globalMonitor != nil || localMonitor != nil
    }

    public func start() {
        guard globalMonitor == nil, localMonitor == nil else { return }
        globalMonitor = installGlobal([.keyDown]) { [weak self] event in
            Task { @MainActor [weak self] in
                _ = self?.handle(event: event)
            }
        }
        localMonitor = installLocal([.keyDown]) { [weak self] event in
            guard let self else { return event }
            let box = NSEventBox(event: event)
            let handled = MainActor.assumeIsolated {
                self.handle(event: box.event)
            }
            return handled ? nil : event
        }
    }

    public func stop() {
        if let handle = globalMonitor {
            uninstall(handle)
            globalMonitor = nil
        }
        if let handle = localMonitor {
            uninstall(handle)
            localMonitor = nil
        }
    }

    @discardableResult
    internal func handle(event: NSEvent) -> Bool {
        guard event.type == .keyDown else { return false }
        guard event.keyCode == Self.escapeKeyCode else { return false }
        let activeModifiers = event.modifierFlags.intersection(Self.blockingModifierMask)
        guard activeModifiers.isEmpty else { return false }

        return onEscapePressed()
    }
}

import AppKit
import Foundation
import PersonalScribeCore

/// Global Esc-key monitor for the pill UX (spec §3: "Click ✕ or press
/// Esc | Pill is .holdToRecord or .recording | Discard audio; enter
/// .cancelled; show Cancel Card").
///
/// Why a global monitor and not `.onKeyPress(.escape)`:
///
/// The pill panel is non-activating (Issue 6) — `DraggablePanel.canBecomeKey
/// = false`. A non-key window cannot deliver `keyDown` to SwiftUI content,
/// so SwiftUI's `.onKeyPress` never fires while the user is focused in
/// another app (which is exactly when they'd press Esc to cancel).
/// `NSEvent.addGlobalMonitorForEvents` observes keyboard events globally
/// and requires the same Input Monitoring TCC grant as the main
/// `GlobalHotkeyMonitor`, so there's no additional permission cost.
///
/// # Filter
///
/// Only fires `onEscapePressed` when:
/// * Event type is `.keyDown`
/// * `keyCode == 53` (Escape)
/// * No modifier keys are held (plain Esc — not Cmd+Esc or Option+Esc)
///
/// # Gating at the call site
///
/// The monitor does NOT check pill state itself — the caller wires
/// `onEscapePressed` to a closure that consults the view model and only
/// acts when pill is `.holdToRecord` or `.recording`. Keeps the monitor
/// stateless and simple to test.
@MainActor
public final class EscapeKeyMonitor {
    public typealias Installer = @MainActor (
        _ mask: NSEvent.EventTypeMask,
        _ handler: @escaping (NSEvent) -> Void
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

    private let onEscapePressed: @MainActor () -> Void
    private let install: Installer
    private let uninstall: Uninstaller
    private var monitor: Any?

    public convenience init(onEscapePressed: @escaping @MainActor () -> Void) {
        self.init(
            onEscapePressed: onEscapePressed,
            install: { mask, handler in
                NSEvent.addGlobalMonitorForEvents(matching: mask, handler: handler)
            },
            uninstall: { handle in
                NSEvent.removeMonitor(handle)
            }
        )
    }

    init(
        onEscapePressed: @escaping @MainActor () -> Void,
        install: @escaping Installer,
        uninstall: @escaping Uninstaller
    ) {
        self.onEscapePressed = onEscapePressed
        self.install = install
        self.uninstall = uninstall
    }

    public var isActive: Bool {
        monitor != nil
    }

    public func start() {
        guard monitor == nil else { return }
        monitor = install([.keyDown]) { [weak self] event in
            Task { @MainActor [weak self] in
                self?.handle(event: event)
            }
        }
    }

    public func stop() {
        guard let handle = monitor else { return }
        uninstall(handle)
        monitor = nil
    }

    internal func handle(event: NSEvent) {
        guard event.type == .keyDown else { return }
        guard event.keyCode == Self.escapeKeyCode else { return }
        let activeModifiers = event.modifierFlags.intersection(Self.blockingModifierMask)
        guard activeModifiers.isEmpty else { return }

        onEscapePressed()
    }
}

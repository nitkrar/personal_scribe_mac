import AppKit
import CoreGraphics
import Foundation
import PersonalScribeCore

/// `CGEvent` is `@_nonSendable` in Swift 6 strict concurrency. The
/// CGEventTap callback is documented to run synchronously on the thread
/// owning the run loop the tap's source is installed on (main thread
/// for us) — there's no real cross-thread hop to guard against, so this
/// box lets us carry the event into `MainActor.assumeIsolated` without
/// fighting the concurrency checker.
private struct CGEventBox: @unchecked Sendable {
    let event: CGEvent
    let type: CGEventType
}

/// CGEventTap wrapper for system-wide hotkey monitoring.
///
/// Unlike `NSEvent.addGlobalMonitorForEvents` (passive — can only observe
/// events headed to other apps), a session-scoped `CGEventTap` at
/// `.headInsertEventTap` sits at the event-dispatch layer and can SWALLOW
/// events by returning `nil` from its callback. This is what stops the
/// `÷÷÷÷` leak into other apps during an ⌥+/ hold (bug #5, 2026-04-21
/// dogfood): matching keyDown auto-repeats are consumed before the focused
/// app's text field sees them.
///
/// Isolation: `@MainActor`. The C-ABI tap callback runs on the thread that
/// owns the run loop where the tap's source is installed. We install on
/// `CFRunLoopGetMain()` + `.commonModes`, so the callback fires on the main
/// thread. `MainActor.assumeIsolated` bridges the C boundary back to our
/// MainActor state without fighting strict concurrency.
///
/// Designed as a standalone class (not buried in `GlobalHotkeyMonitor`) so
/// the planned central `KeyEventRouter` (#19 backlog, 5a-v2) can reuse the
/// same tap plumbing by subscribing additional deciders rather than by
/// extracting code from `GlobalHotkeyMonitor` first.
@MainActor
public final class HotkeyEventTap {
    /// DI seam for `CGEvent.tapCreate` — tests substitute a fake that
    /// returns `nil` (simulate permission denied / OS failure) or a
    /// sentinel `CFMachPort` without touching the real HID event system.
    public typealias Installer = @MainActor (
        _ callback: CGHotkeyEventTapCallback,
        _ userInfo: UnsafeMutableRawPointer?
    ) -> CFMachPort?

    /// Decider called per event. Returning `true` swallows the event —
    /// the CGEventTap callback returns `nil` and the event is NOT
    /// delivered to the focused app. Returning `false` passes it through.
    public typealias Decider = @MainActor (HotkeyEvent) -> Bool

    private let decider: Decider
    private let installer: Installer
    private let logger: PersonalScribeLogger

    private var tap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?
    private var userInfo: UnsafeMutableRawPointer?

    public init(
        decider: @escaping Decider,
        installer: @escaping Installer = { callback, userInfo in
            CGHotkeyEventTapInstaller.createTap(callback: callback, userInfo: userInfo)
        },
        logger: PersonalScribeLogger
    ) {
        self.decider = decider
        self.installer = installer
        self.logger = logger
    }

    public var isActive: Bool { tap != nil }

    /// Installs the tap + adds its run-loop source. Returns `true` on
    /// success. Returns `false` if `CGEvent.tapCreate` returns `nil`
    /// (Input Monitoring permission denied, or a transient OS-level
    /// failure). Caller should route the `false` result through its
    /// existing permission-failure path.
    @discardableResult
    public func start() -> Bool {
        guard tap == nil else {
            logger.info("HotkeyEventTap already active; ignoring duplicate start")
            return true
        }

        let decider = self.decider
        let owner = HotkeyEventTapWeakRef()
        owner.value = self

        let context = CGHotkeyEventTapContext { _, type, event in
            // Callback runs on the main thread because our run loop
            // source is added to CFRunLoopGetMain().
            let box = CGEventBox(event: event, type: type)
            // Return only `Bool` across the isolation boundary so
            // CGEvent's non-Sendable status doesn't poison the transfer.
            // `nil` return (swallow) vs passing the event through is
            // reconstructed outside the assumeIsolated block.
            let shouldSwallow = MainActor.assumeIsolated { () -> Bool in
                // System-level tap disablement — re-enable in place.
                // These fire when the tap blocks the main run loop for
                // too long (timeout) or when user input triggers the
                // reset. Cheap to re-enable; don't consume the event.
                if box.type == .tapDisabledByTimeout || box.type == .tapDisabledByUserInput {
                    if let tap = owner.value?.tap {
                        CGEvent.tapEnable(tap: tap, enable: true)
                    }
                    return false
                }

                guard let hotkeyEvent = HotkeyEvent(cgEvent: box.event, type: box.type) else {
                    // Non-key event inside our mask is unexpected, but
                    // pass through defensively rather than consume.
                    return false
                }

                return decider(hotkeyEvent)
            }
            return shouldSwallow ? nil : Unmanaged.passUnretained(event)
        }

        let userInfo = context.makeUserInfo()

        guard let tap = installer(CGHotkeyEventTapContext.tapCallback, userInfo) else {
            // Installer failed — release the userInfo we retained above.
            CGHotkeyEventTapContext.releaseUserInfo(userInfo)
            return false
        }

        self.tap = tap
        self.userInfo = userInfo

        guard let source = CFMachPortCreateRunLoopSource(nil, tap, 0) else {
            logger.error("CFMachPortCreateRunLoopSource returned nil for an active CGEventTap — tearing down")
            stop()
            return false
        }
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        self.runLoopSource = source
        CGEvent.tapEnable(tap: tap, enable: true)

        return true
    }

    public func stop() {
        if let source = runLoopSource {
            CFRunLoopRemoveSource(CFRunLoopGetMain(), source, .commonModes)
            runLoopSource = nil
        }
        if let tap = tap {
            CGEvent.tapEnable(tap: tap, enable: false)
            // CFMachPortInvalidate is optional — releasing the CFMachPort
            // reference (by clearing `self.tap`) is enough; ARC handles
            // the port's lifetime.
            self.tap = nil
        }
        if userInfo != nil {
            CGHotkeyEventTapContext.releaseUserInfo(userInfo)
            userInfo = nil
        }
    }
}

/// Weak wrapper so the C-ABI callback's captured reference to
/// `HotkeyEventTap` doesn't force a retain cycle on the tap itself. The
/// callback is stored inside `CallbackBox`, which the tap retains via
/// `userInfo`; without this indirection we'd have
/// `HotkeyEventTap.callbackBox (retain) -> self (retain)`.
@MainActor
private final class HotkeyEventTapWeakRef {
    weak var value: HotkeyEventTap?
}

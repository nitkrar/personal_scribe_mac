import AppKit
import CoreGraphics
import Foundation

typealias CGHotkeyEventTapCallback = @convention(c) (
    CGEventTapProxy,
    CGEventType,
    CGEvent,
    UnsafeMutableRawPointer?
) -> Unmanaged<CGEvent>?

/// Retained-box forwarding from the C-ABI `CGEventTap` callback into a
/// Swift closure. The tap holds `userInfo` (an opaque pointer produced
/// by `makeUserInfo()`); on every event the `tapCallback` thunk unwraps
/// the pointer back to the `CallbackBox` and invokes the stored closure.
internal struct CGHotkeyEventTapContext: Sendable {
    internal final class CallbackBox: @unchecked Sendable {
        let callback: @Sendable (CGEventTapProxy, CGEventType, CGEvent) -> Unmanaged<CGEvent>?

        init(
            callback: @escaping @Sendable (CGEventTapProxy, CGEventType, CGEvent) -> Unmanaged<CGEvent>?
        ) {
            self.callback = callback
        }
    }

    let callbackBox: CallbackBox

    init(
        callback: @escaping @Sendable (CGEventTapProxy, CGEventType, CGEvent) -> Unmanaged<CGEvent>?
    ) {
        self.callbackBox = CallbackBox(callback: callback)
    }

    /// Returns an opaque pointer that retains `callbackBox` — pair with
    /// `releaseUserInfo` to release when the tap is torn down.
    func makeUserInfo() -> UnsafeMutableRawPointer {
        Unmanaged.passRetained(callbackBox).toOpaque()
    }

    static func releaseUserInfo(_ userInfo: UnsafeMutableRawPointer?) {
        guard let userInfo else {
            return
        }
        Unmanaged<CallbackBox>.fromOpaque(userInfo).release()
    }

    /// C-ABI thunk passed to `CGEvent.tapCreate`. Forwards to the
    /// retained `CallbackBox` on every event.
    static let tapCallback: CGHotkeyEventTapCallback = { proxy, type, event, userInfo in
        guard let userInfo else {
            return Unmanaged.passUnretained(event)
        }

        let callbackBox = Unmanaged<CallbackBox>.fromOpaque(userInfo).takeUnretainedValue()
        return callbackBox.callback(proxy, type, event)
    }
}

/// Thin DI-friendly wrapper over `CGEvent.tapCreate`. Takes the C-ABI
/// callback + opaque `userInfo` pointer separately so `HotkeyEventTap`
/// can manage the `CallbackBox` lifecycle and tests can inject a fake
/// installer that returns `nil` (simulating permission denied / OS
/// failure) without ever touching the real HID event system.
internal enum CGHotkeyEventTapInstaller {
    /// Event mask for `.keyDown | .keyUp | .flagsChanged`. Keeps the
    /// tap's interest scoped to keyboard events — mouse / scroll events
    /// pass through untouched.
    static let eventMask: CGEventMask =
        (1 << CGEventType.keyDown.rawValue) |
        (1 << CGEventType.keyUp.rawValue) |
        (1 << CGEventType.flagsChanged.rawValue)

    /// Creates a session-scoped tap at `.headInsertEventTap` so we see
    /// events BEFORE any other app-level handler — required to swallow
    /// matching events (return `nil`) before they reach the focused app.
    ///
    /// `.cgSessionEventTap` (not `.cghidEventTap`) — the HID tap is
    /// root-only on modern macOS; session tap is what LSUIElement apps
    /// can legitimately install with Input Monitoring permission.
    static func createTap(
        callback: CGHotkeyEventTapCallback,
        userInfo: UnsafeMutableRawPointer?
    ) -> CFMachPort? {
        CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .defaultTap,
            eventsOfInterest: eventMask,
            callback: callback,
            userInfo: userInfo
        )
    }
}

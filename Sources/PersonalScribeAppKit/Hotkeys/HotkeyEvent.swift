import AppKit
import CoreGraphics
import Foundation

/// Source-neutral representation of a keyboard event consumed by
/// `GlobalHotkeyMonitor`'s gesture state machine.
///
/// Both `NSEvent` (today's `addGlobalMonitorForEvents` / `addLocalMonitorForEvents`
/// path) and `CGEvent` (the upcoming CGEventTap path in 5a-v1 commit 2) feed
/// into the same `HotkeyEvent` so the state machine doesn't care which
/// framework produced the event.
///
/// Kept in its own file — and module-internal (no `public`) — so the planned
/// central `KeyEventRouter` (#19 backlog, 5a-v2) can consume the same type
/// without extracting it from `GlobalHotkeyMonitor.swift` first.
struct HotkeyEvent: Sendable {
    enum EventType: Equatable, Sendable {
        case keyDown
        case keyUp
        case flagsChanged
    }

    let type: EventType
    let keyCode: UInt16
    let modifierFlags: NSEvent.ModifierFlags
    let timestamp: TimeInterval
    let isARepeat: Bool
}

extension HotkeyEvent {
    /// Lossless adapter from `NSEvent`. `isARepeat` is only meaningful for
    /// `.keyDown` — explicit `false` for `.keyUp` / `.flagsChanged`.
    init(nsEvent: NSEvent) {
        self.type = {
            switch nsEvent.type {
            case .keyDown:
                return .keyDown
            case .keyUp:
                return .keyUp
            case .flagsChanged:
                return .flagsChanged
            default:
                fatalError("HotkeyEvent init called with non-key event: \(nsEvent.type)")
            }
        }()
        self.keyCode = nsEvent.keyCode
        self.modifierFlags = nsEvent.modifierFlags
        self.timestamp = nsEvent.timestamp
        self.isARepeat = (nsEvent.type == .keyDown) ? nsEvent.isARepeat : false
    }

    /// Adapter from a `CGEvent` delivered through `CGEventTap`. Returns
    /// `nil` for non-key event types (including tap-disabled events,
    /// which `HotkeyEventTap` handles separately before converting).
    ///
    /// Timestamp uses `ProcessInfo.systemUptime` — seconds since boot,
    /// matching `NSEvent.timestamp` semantics. Mixing sources in the
    /// state machine's timing math (e.g., keyDown from NSEvent +
    /// keyUp from CGEvent) remains consistent.
    init?(cgEvent: CGEvent, type: CGEventType) {
        let eventType: EventType
        switch type {
        case .keyDown:
            eventType = .keyDown
        case .keyUp:
            eventType = .keyUp
        case .flagsChanged:
            eventType = .flagsChanged
        default:
            return nil
        }
        self.type = eventType
        self.keyCode = UInt16(cgEvent.getIntegerValueField(.keyboardEventKeycode))
        self.modifierFlags = NSEvent.ModifierFlags(cgEventFlags: cgEvent.flags)
        self.timestamp = ProcessInfo.processInfo.systemUptime
        self.isARepeat = (type == .keyDown)
            ? (cgEvent.getIntegerValueField(.keyboardEventAutorepeat) != 0)
            : false
    }
}

extension NSEvent.ModifierFlags {
    /// Bitmask translation from `CGEventFlags` (CoreGraphics) to the
    /// `NSEvent.ModifierFlags` used by `HotkeyEvent.modifierFlags` and
    /// `HotkeyPreference`. Keeps modifier-matching logic in the state
    /// machine source-agnostic.
    init(cgEventFlags flags: CGEventFlags) {
        var result: NSEvent.ModifierFlags = []
        if flags.contains(.maskCommand) { result.insert(.command) }
        if flags.contains(.maskControl) { result.insert(.control) }
        if flags.contains(.maskAlternate) { result.insert(.option) }
        if flags.contains(.maskShift) { result.insert(.shift) }
        if flags.contains(.maskAlphaShift) { result.insert(.capsLock) }
        self = result
    }
}

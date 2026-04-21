import AppKit
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
}

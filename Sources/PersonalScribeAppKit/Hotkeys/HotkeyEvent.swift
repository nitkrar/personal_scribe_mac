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
/// Lifted to `public` (#028) because `KeyEventRouter`'s public
/// `Decider` typealias references this type — Swift requires
/// referenced types to be at least as accessible as the referencing
/// API. Originally module-internal per the 5a-v2 design brief.
public struct HotkeyEvent: Sendable {
    public enum EventType: Equatable, Sendable {
        case keyDown
        case keyUp
        case flagsChanged
    }

    public let type: EventType
    public let keyCode: UInt16
    public let modifierFlags: NSEvent.ModifierFlags
    public let timestamp: TimeInterval
    public let isARepeat: Bool
    /// Source characters when the event came from an `NSEvent` (local /
    /// global NSEvent monitor path). `nil` when the event came from the
    /// `CGEventTap` path — `CGEvent` does not surface readable
    /// characters in a Sendable form, and the CG-tap consumers
    /// (gesture state machine) don't need them. Used by `HotkeyRecorder`
    /// for chord-display rendering.
    public let charactersIgnoringModifiers: String?
    public let characters: String?

    /// Memberwise initializer with optional `characters` fields
    /// defaulted to `nil` — keeps existing test fixtures (which
    /// construct `HotkeyEvent` with the original 5 fields) compiling
    /// after #028's addition of character storage.
    public init(
        type: EventType,
        keyCode: UInt16,
        modifierFlags: NSEvent.ModifierFlags,
        timestamp: TimeInterval,
        isARepeat: Bool,
        charactersIgnoringModifiers: String? = nil,
        characters: String? = nil
    ) {
        self.type = type
        self.keyCode = keyCode
        self.modifierFlags = modifierFlags
        self.timestamp = timestamp
        self.isARepeat = isARepeat
        self.charactersIgnoringModifiers = charactersIgnoringModifiers
        self.characters = characters
    }
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
        // `NSEvent.characters` / `charactersIgnoringModifiers` are
        // valid ONLY for `.keyDown` / `.keyUp`. Reading either on a
        // `.flagsChanged` event throws `NSInternalInconsistencyException`
        // (unlike most NSEvent properties which return nil for
        // out-of-domain reads). Guard the reads explicitly.
        switch nsEvent.type {
        case .keyDown, .keyUp:
            self.charactersIgnoringModifiers = nsEvent.charactersIgnoringModifiers
            self.characters = nsEvent.characters
        default:
            self.charactersIgnoringModifiers = nil
            self.characters = nil
        }
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
        // CGEvent has no Sendable character accessor; HotkeyRecorder
        // (the only consumer that reads characters) is local-NSEvent-
        // only, so the CG path leaves these nil.
        self.charactersIgnoringModifiers = nil
        self.characters = nil
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

import AppKit
import Foundation

/// Source-neutral representation of a keyboard event consumed by
/// `GlobalHotkeyMonitor`'s gesture state machine.
///
/// Both `NSEvent` monitors and registered macOS hot keys (see
/// `KeyEventRouter`) feed into the same `HotkeyEvent` so the state
/// machine doesn't care which source produced the event.
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
    /// global NSEvent monitor path). `nil` for registered hot key events,
    /// whose consumers (gesture state machine) don't need them. Used by
    /// `HotkeyRecorder` for chord-display rendering.
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

}

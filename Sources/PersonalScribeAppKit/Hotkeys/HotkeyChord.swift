import AppKit
import Carbon.HIToolbox
import PersonalScribeCore

/// A key + modifiers shortcut registered with macOS as a hot key.
public struct HotkeyChord: Hashable, Sendable, CustomStringConvertible {
    public let keyCode: UInt16
    private let modifierBits: NSEvent.ModifierFlags.RawValue

    public var modifiers: NSEvent.ModifierFlags { NSEvent.ModifierFlags(rawValue: modifierBits) }

    public init(keyCode: UInt16, modifiers: NSEvent.ModifierFlags) {
        self.keyCode = keyCode
        self.modifierBits = modifiers.intersection([.command, .control, .option, .shift]).rawValue
    }

    public init(_ preference: HotkeyPreference) {
        self.init(keyCode: preference.keyCode, modifiers: preference.modifierFlags)
    }

    public var description: String { "keyCode=\(keyCode) modifiers=\(modifierBits)" }
}

/// Registers chords with the OS and reports their press / release.
/// `onEvent(id, pressed, timestamp)`; `timestamp` uses the system-uptime
/// clock, like `HotkeyEvent.timestamp`.
@MainActor
public protocol HotkeyChordRegistering: AnyObject {
    var onEvent: (@MainActor (_ id: UInt32, _ pressed: Bool, _ timestamp: TimeInterval) -> Void)? { get set }
    /// Returns false when macOS refuses the chord.
    func register(_ chord: HotkeyChord, id: UInt32) -> Bool
    func unregister(id: UInt32)
}

/// `RegisterEventHotKey`-backed registrar. The OS matches the chord and
/// delivers only that keystroke to us (swallowed for every other app);
/// no other key passes through Ninimma, and no Accessibility permission
/// is involved — so a stalled Ninimma or a permission change can never
/// hold up the user's typing.
@MainActor
public final class CarbonHotkeyRegistrar: HotkeyChordRegistering {
    public var onEvent: (@MainActor (UInt32, Bool, TimeInterval) -> Void)?

    private static let signature: OSType = 0x4E4E_4D41 // 'NNMA'
    private var hotKeys: [UInt32: EventHotKeyRef] = [:]
    private var handler: EventHandlerRef?
    private let logger: PersonalScribeLogger

    public init(logger: PersonalScribeLogger) {
        self.logger = logger
    }

    public func register(_ chord: HotkeyChord, id: UInt32) -> Bool {
        installHandlerIfNeeded()
        var ref: EventHotKeyRef?
        let status = RegisterEventHotKey(
            UInt32(chord.keyCode),
            Self.carbonModifiers(chord.modifiers),
            EventHotKeyID(signature: Self.signature, id: id),
            GetEventDispatcherTarget(),
            0,
            &ref
        )
        guard status == noErr, let ref else {
            logger.error("hotkey_register_failed — \(chord) status=\(status)")
            return false
        }
        hotKeys[id] = ref
        return true
    }

    public func unregister(id: UInt32) {
        guard let ref = hotKeys.removeValue(forKey: id) else { return }
        UnregisterEventHotKey(ref)
    }

    static func carbonModifiers(_ flags: NSEvent.ModifierFlags) -> UInt32 {
        var result: UInt32 = 0
        if flags.contains(.command) { result |= UInt32(cmdKey) }
        if flags.contains(.option) { result |= UInt32(optionKey) }
        if flags.contains(.control) { result |= UInt32(controlKey) }
        if flags.contains(.shift) { result |= UInt32(shiftKey) }
        return result
    }

    private func installHandlerIfNeeded() {
        guard handler == nil else { return }
        let types = [
            EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed)),
            EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyReleased)),
        ]
        let status = InstallEventHandler(
            GetEventDispatcherTarget(),
            { _, event, userData -> OSStatus in
                guard let event, let userData else { return OSStatus(eventNotHandledErr) }
                var hotKeyID = EventHotKeyID()
                let status = GetEventParameter(
                    event,
                    EventParamName(kEventParamDirectObject),
                    EventParamType(typeEventHotKeyID),
                    nil,
                    MemoryLayout<EventHotKeyID>.size,
                    nil,
                    &hotKeyID
                )
                guard status == noErr else { return status }
                let pressed = GetEventKind(event) == UInt32(kEventHotKeyPressed)
                let timestamp = GetEventTime(event)
                let id = hotKeyID.id
                // Hot key events are dispatched on the main event loop.
                MainActor.assumeIsolated {
                    let registrar = Unmanaged<CarbonHotkeyRegistrar>.fromOpaque(userData).takeUnretainedValue()
                    registrar.onEvent?(id, pressed, timestamp)
                }
                return noErr
            },
            types.count,
            types,
            Unmanaged.passUnretained(self).toOpaque(),
            &handler
        )
        if status != noErr {
            logger.error("hotkey_handler_install_failed — status=\(status)")
        }
    }
}

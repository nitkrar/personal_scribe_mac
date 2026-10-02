import AppKit
import Foundation
import PersonalScribeCore

/// `NSEvent` is not `Sendable`, but `addLocalMonitorForEvents` /
/// `addGlobalMonitorForEvents` callbacks are documented to run on the
/// main thread — there is no real cross-thread hop to guard against.
/// This box lets us pass the event through `MainActor.assumeIsolated`
/// without fighting strict concurrency.
private struct KeyEventRouterNSEventBox: @unchecked Sendable {
    let event: NSEvent
}

/// Centralized owner of Ninimma's keyboard-event sources (#028):
///
/// 1. **Registered chords** (`HotkeyChordRegistering`, macOS hot keys) —
///    shortcuts used while another app is frontmost. macOS delivers only
///    the registered chords, already swallowed, to the global deciders;
///    no other keystroke passes through Ninimma and no Accessibility
///    permission is involved (DECISIONS #25).
/// 2. **`NSEvent.addLocalMonitorForEvents`** — events delivered to
///    Ninimma itself; can swallow by returning `nil`.
/// 3. **`NSEvent.addGlobalMonitorForEvents`** — events delivered to
///    other apps; observe-only (cannot swallow).
///
/// Subscribers register a `Decider` (returns `true` to swallow) or an
/// `Observer` (observe-only) and receive a `KeyEventRouterToken`.
/// Holding the token keeps the registration alive; dropping it (e.g.
/// SwiftUI `@State` going out of scope) auto-unregisters the
/// subscriber. No explicit `remove(_:)` calls needed.
@MainActor
public final class KeyEventRouter {
    public enum Position: Sendable {
        case first
        case last
    }

    public typealias Decider = @MainActor (HotkeyEvent) -> Bool
    public typealias Observer = @MainActor (HotkeyEvent) -> Void

    public typealias LocalInstaller = @MainActor (
        _ mask: NSEvent.EventTypeMask,
        _ handler: @escaping (NSEvent) -> NSEvent?
    ) -> Any?
    public typealias GlobalInstaller = @MainActor (
        _ mask: NSEvent.EventTypeMask,
        _ handler: @escaping (NSEvent) -> Void
    ) -> Any?
    public typealias Uninstaller = @MainActor (Any) -> Void

    private struct Slot<Handler> {
        let id: UUID
        let handler: Handler
    }

    private var localDeciders: [Slot<Decider>] = []
    private var globalDeciders: [Slot<Decider>] = []
    private var globalObservers: [Slot<Observer>] = []

    private let installLocal: LocalInstaller
    private let installGlobal: GlobalInstaller
    private let uninstall: Uninstaller

    private var localMonitor: Any?
    private var globalMonitor: Any?

    private let chordRegistrar: any HotkeyChordRegistering
    private struct ChordEntry {
        let chord: HotkeyChord
        var refCount: Int
        var isRegistered: Bool
    }
    private var chordEntries: [UInt32: ChordEntry] = [:]
    private var nextChordID: UInt32 = 1
    private var chordSuspensionCount = 0

    public init(
        chordRegistrar: any HotkeyChordRegistering,
        installLocal: @escaping LocalInstaller = { mask, handler in
            NSEvent.addLocalMonitorForEvents(matching: mask, handler: handler)
        },
        installGlobal: @escaping GlobalInstaller = { mask, handler in
            NSEvent.addGlobalMonitorForEvents(matching: mask, handler: handler)
        },
        uninstall: @escaping Uninstaller = { handle in
            NSEvent.removeMonitor(handle)
        },
        logger: PersonalScribeLogger
    ) {
        self.chordRegistrar = chordRegistrar
        self.installLocal = installLocal
        self.installGlobal = installGlobal
        self.uninstall = uninstall
        chordRegistrar.onEvent = { [weak self] id, pressed, timestamp in
            self?.dispatchChord(id: id, pressed: pressed, timestamp: timestamp)
        }
    }

    /// True once the NSEvent monitors are installed.
    public var isActive: Bool {
        localMonitor != nil || globalMonitor != nil
    }

    /// Install the NSEvent local + global monitors. Idempotent.
    public func start() {
        guard localMonitor == nil, globalMonitor == nil else {
            return
        }

        let mask: NSEvent.EventTypeMask = [.keyDown, .keyUp, .flagsChanged]
        localMonitor = installLocal(mask) { [weak self] event in
            guard let self else { return event }
            let box = KeyEventRouterNSEventBox(event: event)
            let swallow = MainActor.assumeIsolated { () -> Bool in
                let hotkey = HotkeyEvent(nsEvent: box.event)
                return self.dispatchLocalDeciders(hotkey)
            }
            return swallow ? nil : event
        }
        globalMonitor = installGlobal(mask) { [weak self] event in
            guard let self else { return }
            let box = KeyEventRouterNSEventBox(event: event)
            Task { @MainActor [weak self] in
                guard let self else { return }
                let hotkey = HotkeyEvent(nsEvent: box.event)
                self.dispatchGlobalObservers(hotkey)
            }
        }
    }

    public func stop() {
        if let localMonitor {
            uninstall(localMonitor)
            self.localMonitor = nil
        }
        if let globalMonitor {
            uninstall(globalMonitor)
            self.globalMonitor = nil
        }
    }

    // MARK: - Registration

    /// Register a decider on the **local** NSEvent path (events delivered
    /// to Ninimma itself). Decider returns `true` to swallow; `false` to
    /// pass through. First decider to swallow short-circuits the chain.
    /// `position: .first` inserts at the front of the chain — useful for
    /// modal subscribers (e.g. `HotkeyRecorder`) that must take priority
    /// over already-registered consumers while their UI is active.
    @discardableResult
    public func registerLocalDecider(
        _ decider: @escaping Decider,
        position: Position = .last
    ) -> KeyEventRouterToken {
        let id = UUID()
        insert(Slot(id: id, handler: decider), into: &localDeciders, at: position)
        return KeyEventRouterToken { [weak self] in
            Task { @MainActor [weak self] in
                self?.localDeciders.removeAll { $0.id == id }
            }
        }
    }

    /// Register a decider for **registered chords** pressed while another
    /// app is frontmost (see `registerGlobalChord`). macOS has already
    /// swallowed the chord, so the decider's verdict only short-circuits
    /// later deciders.
    @discardableResult
    public func registerGlobalDecider(
        _ decider: @escaping Decider,
        position: Position = .last
    ) -> KeyEventRouterToken {
        let id = UUID()
        insert(Slot(id: id, handler: decider), into: &globalDeciders, at: position)
        return KeyEventRouterToken { [weak self] in
            Task { @MainActor [weak self] in
                self?.globalDeciders.removeAll { $0.id == id }
            }
        }
    }

    /// Register an observer on the **NSEvent global** path. Observe-only —
    /// NSEvent global monitors can't swallow. Used when a consumer needs
    /// to react to keystrokes destined for other apps without consuming
    /// them (e.g. `EscapeKeyMonitor`'s "user pressed Esc while recording
    /// into a text editor" detection).
    @discardableResult
    public func registerGlobalObserver(
        _ observer: @escaping Observer
    ) -> KeyEventRouterToken {
        let id = UUID()
        globalObservers.append(Slot(id: id, handler: observer))
        return KeyEventRouterToken { [weak self] in
            Task { @MainActor [weak self] in
                self?.globalObservers.removeAll { $0.id == id }
            }
        }
    }

    // MARK: - Registered chords

    /// Declare a shortcut that should reach the global deciders while
    /// another app is frontmost. The chord is registered with macOS for
    /// as long as the returned registration lives (released
    /// synchronously when dropped).
    public func registerGlobalChord(_ chord: HotkeyChord) -> KeyEventRouterChordRegistration {
        if let (id, entry) = chordEntries.first(where: { $0.value.chord == chord }) {
            chordEntries[id]?.refCount = entry.refCount + 1
            return KeyEventRouterChordRegistration(router: self, id: id)
        }
        let id = nextChordID
        nextChordID += 1
        let isRegistered = chordSuspensionCount == 0 && chordRegistrar.register(chord, id: id)
        chordEntries[id] = ChordEntry(chord: chord, refCount: 1, isRegistered: isRegistered)
        return KeyEventRouterChordRegistration(router: self, id: id)
    }

    /// Release every registered chord until the token is dropped — used by
    /// the shortcut recorder so pressing an existing shortcut is captured
    /// instead of triggering it.
    public func suspendGlobalChords() -> KeyEventRouterToken {
        chordSuspensionCount += 1
        if chordSuspensionCount == 1 {
            for (id, entry) in chordEntries where entry.isRegistered {
                chordRegistrar.unregister(id: id)
                chordEntries[id]?.isRegistered = false
            }
        }
        return KeyEventRouterToken { [weak self] in
            Task { @MainActor [weak self] in
                self?.resumeGlobalChords()
            }
        }
    }

    fileprivate func isChordRegistered(id: UInt32) -> Bool {
        chordEntries[id]?.isRegistered ?? false
    }

    fileprivate func releaseChord(id: UInt32) {
        guard var entry = chordEntries[id] else { return }
        entry.refCount -= 1
        guard entry.refCount == 0 else {
            chordEntries[id] = entry
            return
        }
        chordEntries[id] = nil
        if entry.isRegistered {
            chordRegistrar.unregister(id: id)
        }
    }

    private func resumeGlobalChords() {
        chordSuspensionCount -= 1
        guard chordSuspensionCount == 0 else { return }
        for (id, entry) in chordEntries where !entry.isRegistered {
            chordEntries[id]?.isRegistered = chordRegistrar.register(entry.chord, id: id)
        }
    }

    private func dispatchChord(id: UInt32, pressed: Bool, timestamp: TimeInterval) {
        guard let chord = chordEntries[id]?.chord else { return }
        let event = HotkeyEvent(
            type: pressed ? .keyDown : .keyUp,
            keyCode: chord.keyCode,
            modifierFlags: chord.modifiers,
            timestamp: timestamp,
            isARepeat: false
        )
        // The OS already swallowed the chord; decider verdicts don't matter.
        _ = dispatchGlobalDeciders(event)
    }

    // MARK: - Test seams

    /// Synthesize an NSEvent-shape event into the local-decider chain.
    /// Used by tests to drive the router without installing monitors.
    @discardableResult
    func handleLocal(_ event: HotkeyEvent) -> Bool {
        dispatchLocalDeciders(event)
    }

    /// Synthesize a registered-chord event into the global-decider chain.
    @discardableResult
    func handleGlobal(_ event: HotkeyEvent) -> Bool {
        dispatchGlobalDeciders(event)
    }

    /// Synthesize an NSEvent-global event into the observer chain.
    func handleGlobalObserved(_ event: HotkeyEvent) {
        dispatchGlobalObservers(event)
    }

    // MARK: - Internals

    private func insert<Handler>(
        _ slot: Slot<Handler>,
        into chain: inout [Slot<Handler>],
        at position: Position
    ) {
        switch position {
        case .first:
            chain.insert(slot, at: 0)
        case .last:
            chain.append(slot)
        }
    }

    private func dispatchLocalDeciders(_ event: HotkeyEvent) -> Bool {
        for slot in localDeciders {
            if slot.handler(event) {
                return true
            }
        }
        return false
    }

    private func dispatchGlobalDeciders(_ event: HotkeyEvent) -> Bool {
        for slot in globalDeciders {
            if slot.handler(event) {
                return true
            }
        }
        return false
    }

    private func dispatchGlobalObservers(_ event: HotkeyEvent) {
        for slot in globalObservers {
            slot.handler(event)
        }
    }
}

/// RAII token returned by `KeyEventRouter.register*`. Holding the
/// token keeps the registration alive; dropping it auto-unregisters
/// the subscriber. Consumers store the token in `@State` (SwiftUI),
/// `private let` (long-lived), or any property whose lifetime matches
/// the desired registration scope.
public final class KeyEventRouterToken: @unchecked Sendable {
    private let cleanup: @Sendable () -> Void

    fileprivate init(cleanup: @escaping @Sendable () -> Void) {
        self.cleanup = cleanup
    }

    deinit {
        cleanup()
    }
}

/// Live registration of one chord with `KeyEventRouter`. Dropping it
/// unregisters the chord synchronously (on the main actor), so a quick
/// disarm → re-arm can't race a deferred cleanup.
@MainActor
public final class KeyEventRouterChordRegistration {
    private weak var router: KeyEventRouter?
    private let id: UInt32

    fileprivate init(router: KeyEventRouter, id: UInt32) {
        self.router = router
        self.id = id
    }

    /// False when macOS refused the chord (or while suspended).
    public var isRegistered: Bool {
        router?.isChordRegistered(id: id) ?? false
    }

    isolated deinit {
        router?.releaseChord(id: id)
    }
}

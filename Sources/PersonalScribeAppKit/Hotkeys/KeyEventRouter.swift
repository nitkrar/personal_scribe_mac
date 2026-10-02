import AppKit
import CoreGraphics
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

/// Centralized owner of the three keyboard-event sources Ninimma uses
/// for hotkey dispatch (#028 / 5a-v2):
///
/// 1. **`HotkeyEventTap`** — `CGEventTap` at `headInsertEventTap` for
///    swallowing chords destined for *other* apps. Requires Input
///    Monitoring permission.
/// 2. **`NSEvent.addLocalMonitorForEvents`** — events delivered to
///    Ninimma itself; can swallow by returning `nil`.
/// 3. **`NSEvent.addGlobalMonitorForEvents`** — events delivered to
///    other apps; observe-only (cannot swallow).
///
/// Before #028, each consumer (`GlobalHotkeyMonitor`,
/// `EscapeKeyMonitor`, `HotkeyRecorder`) owned its own monitor stack.
/// That made event-dispatch order an implicit consequence of
/// `addLocalMonitorForEvents`'s LIFO semantics — easy to drift when
/// any consumer changed its install/uninstall lifecycle. The router
/// makes the dispatch order explicit (registration order) and reduces
/// the in-process monitor count to one CG tap + one local NSEvent
/// monitor + one global NSEvent monitor.
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

    /// How shortcuts bound for other apps reach Ninimma.
    /// * `keyboardTap` — the active `CGEventTap`: every keystroke passes
    ///   through the global deciders, which may swallow it. Needs
    ///   Accessibility, and a stalled tap or a permission change can hold
    ///   up all typing.
    /// * `registeredChords` — each shortcut is registered with macOS
    ///   (`registerGlobalChord`); the OS delivers only those chords, already
    ///   swallowed, to the global deciders. Nothing else passes through.
    public enum Backend {
        case keyboardTap
        case registeredChords(any HotkeyChordRegistering)
    }

    public typealias Decider = @MainActor (HotkeyEvent) -> Bool
    public typealias Observer = @MainActor (HotkeyEvent) -> Void

    public typealias TapFactory = @MainActor (@escaping HotkeyEventTap.Decider) -> HotkeyEventTap
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

    private let tapFactory: TapFactory
    private let installLocal: LocalInstaller
    private let installGlobal: GlobalInstaller
    private let uninstall: Uninstaller

    private var tap: HotkeyEventTap?
    private var localMonitor: Any?
    private var globalMonitor: Any?

    private let backend: Backend
    private struct ChordEntry {
        let chord: HotkeyChord
        var refCount: Int
        var isRegistered: Bool
    }
    private var chordEntries: [UInt32: ChordEntry] = [:]
    private var nextChordID: UInt32 = 1
    private var chordSuspensionCount = 0

    public init(
        tapFactory: TapFactory? = nil,
        installLocal: @escaping LocalInstaller = { mask, handler in
            NSEvent.addLocalMonitorForEvents(matching: mask, handler: handler)
        },
        installGlobal: @escaping GlobalInstaller = { mask, handler in
            NSEvent.addGlobalMonitorForEvents(matching: mask, handler: handler)
        },
        uninstall: @escaping Uninstaller = { handle in
            NSEvent.removeMonitor(handle)
        },
        logger: PersonalScribeLogger,
        backend: Backend = .keyboardTap
    ) {
        self.backend = backend
        self.tapFactory = tapFactory ?? { decider in
            HotkeyEventTap(
                decider: decider,
                logger: logger
            )
        }
        self.installLocal = installLocal
        self.installGlobal = installGlobal
        self.uninstall = uninstall
        if case .registeredChords(let registrar) = backend {
            registrar.onEvent = { [weak self] id, pressed, timestamp in
                self?.dispatchChord(id: id, pressed: pressed, timestamp: timestamp)
            }
        }
    }

    /// Only the keyboard-tap backend depends on Accessibility for hotkeys.
    public var needsAccessibilityForHotkeys: Bool {
        if case .keyboardTap = backend { return true }
        return false
    }

    /// True when at least one of the three monitors is live. The CG
    /// tap may fail to install (Accessibility not granted) while the
    /// NSEvent monitors still succeed — `start()` returns the tap
    /// result so the caller can surface the permission error, but the
    /// router stays usable for in-app keystrokes regardless.
    public var isActive: Bool {
        tap?.isActive == true || localMonitor != nil || globalMonitor != nil
    }

    /// True when the CG tap (system-wide swallow path) is alive. False
    /// when the tap install failed (Accessibility not granted) or the
    /// router has not been started. Consumers that need to surface a
    /// permission warning to the user (e.g. `GlobalHotkeyMonitor`'s
    /// "÷÷÷÷ leak" warning) read this getter after registering.
    public var isTapActive: Bool {
        tap?.isActive == true
    }

    /// Install all three monitor legs. Returns `true` only when the CG
    /// tap installed successfully (the same contract as
    /// `HotkeyEventTap.start`). NSEvent local + global installs are
    /// best-effort and don't gate the return value.
    @discardableResult
    public func start() -> Bool {
        guard tap == nil, localMonitor == nil, globalMonitor == nil else {
            return tap?.isActive == true || !needsAccessibilityForHotkeys
        }

        var tapStarted = true
        if needsAccessibilityForHotkeys {
            let tap = tapFactory({ [weak self] event in
                self?.dispatchGlobalDeciders(event) ?? false
            })
            tapStarted = tap.start()
            if tapStarted {
                self.tap = tap
            }
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

        return tapStarted
    }

    /// Re-attempt the CG tap install after `start()` failed (permission
    /// granted later while running). No-op returning `true` when the tap
    /// is already live, so callers can invoke it freely.
    @discardableResult
    public func retryTapIfNeeded() -> Bool {
        if tap?.isActive == true || !needsAccessibilityForHotkeys {
            return true
        }
        let tap = tapFactory({ [weak self] event in
            self?.dispatchGlobalDeciders(event) ?? false
        })
        guard tap.start() else {
            return false
        }
        self.tap = tap
        return true
    }

    public func stop() {
        tap?.stop()
        tap = nil
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

    /// Register a decider on the **CG tap** path (events bound for other
    /// apps). Same semantics as `registerLocalDecider`. Decider's
    /// `true` return swallows the event before it reaches the focused
    /// app — the bug-#5 use case.
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
    /// another app is frontmost. With `registeredChords` the chord is
    /// registered with macOS for as long as the returned registration
    /// lives (released synchronously when dropped); with `keyboardTap`
    /// the tap already sees every key, so this is a no-op.
    public func registerGlobalChord(_ chord: HotkeyChord) -> KeyEventRouterChordRegistration {
        guard case .registeredChords(let registrar) = backend else {
            return KeyEventRouterChordRegistration(router: nil, id: 0)
        }
        if let (id, entry) = chordEntries.first(where: { $0.value.chord == chord }) {
            chordEntries[id]?.refCount = entry.refCount + 1
            return KeyEventRouterChordRegistration(router: self, id: id)
        }
        let id = nextChordID
        nextChordID += 1
        let isRegistered = chordSuspensionCount == 0 && registrar.register(chord, id: id)
        chordEntries[id] = ChordEntry(chord: chord, refCount: 1, isRegistered: isRegistered)
        return KeyEventRouterChordRegistration(router: self, id: id)
    }

    /// Release every registered chord until the token is dropped — used by
    /// the shortcut recorder so pressing an existing shortcut is captured
    /// instead of triggering it.
    public func suspendGlobalChords() -> KeyEventRouterToken {
        chordSuspensionCount += 1
        if chordSuspensionCount == 1, case .registeredChords(let registrar) = backend {
            for (id, entry) in chordEntries where entry.isRegistered {
                registrar.unregister(id: id)
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
        if entry.isRegistered, case .registeredChords(let registrar) = backend {
            registrar.unregister(id: id)
        }
    }

    private func resumeGlobalChords() {
        chordSuspensionCount -= 1
        guard chordSuspensionCount == 0, case .registeredChords(let registrar) = backend else { return }
        for (id, entry) in chordEntries where !entry.isRegistered {
            chordEntries[id]?.isRegistered = registrar.register(entry.chord, id: id)
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
    /// Used by tests to drive the router without an event tap install.
    @discardableResult
    func handleLocal(_ event: HotkeyEvent) -> Bool {
        dispatchLocalDeciders(event)
    }

    /// Synthesize a CG-tap event into the global-decider chain.
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

    fileprivate init(router: KeyEventRouter?, id: UInt32) {
        self.router = router
        self.id = id
    }

    /// False when macOS refused the chord (or while suspended). Always
    /// true for the keyboard-tap backend, which needs no registration.
    public var isRegistered: Bool {
        guard id != 0 else { return true }
        return router?.isChordRegistered(id: id) ?? false
    }

    isolated deinit {
        guard id != 0 else { return }
        router?.releaseChord(id: id)
    }
}

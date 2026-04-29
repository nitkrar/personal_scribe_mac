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
final class KeyEventRouter {
    enum Position: Sendable {
        case first
        case last
    }

    typealias Decider = @MainActor (HotkeyEvent) -> Bool
    typealias Observer = @MainActor (HotkeyEvent) -> Void

    typealias TapFactory = @MainActor (@escaping HotkeyEventTap.Decider) -> HotkeyEventTap
    typealias LocalInstaller = @MainActor (
        _ mask: NSEvent.EventTypeMask,
        _ handler: @escaping (NSEvent) -> NSEvent?
    ) -> Any?
    typealias GlobalInstaller = @MainActor (
        _ mask: NSEvent.EventTypeMask,
        _ handler: @escaping (NSEvent) -> Void
    ) -> Any?
    typealias Uninstaller = @MainActor (Any) -> Void

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

    init(
        tapFactory: @escaping TapFactory = { decider in
            HotkeyEventTap(decider: decider)
        },
        installLocal: @escaping LocalInstaller = { mask, handler in
            NSEvent.addLocalMonitorForEvents(matching: mask, handler: handler)
        },
        installGlobal: @escaping GlobalInstaller = { mask, handler in
            NSEvent.addGlobalMonitorForEvents(matching: mask, handler: handler)
        },
        uninstall: @escaping Uninstaller = { handle in
            NSEvent.removeMonitor(handle)
        }
    ) {
        self.tapFactory = tapFactory
        self.installLocal = installLocal
        self.installGlobal = installGlobal
        self.uninstall = uninstall
    }

    /// True when at least one of the three monitors is live. The CG
    /// tap may fail to install (Input Monitoring denied) while the
    /// NSEvent monitors still succeed — `start()` returns the tap
    /// result so the caller can surface the permission error, but the
    /// router stays usable for in-app keystrokes regardless.
    var isActive: Bool {
        tap?.isActive == true || localMonitor != nil || globalMonitor != nil
    }

    /// True when the CG tap (system-wide swallow path) is alive. False
    /// when the tap install failed (Input Monitoring denied) or the
    /// router has not been started. Consumers that need to surface a
    /// permission warning to the user (e.g. `GlobalHotkeyMonitor`'s
    /// "÷÷÷÷ leak" warning) read this getter after registering.
    var isTapActive: Bool {
        tap?.isActive == true
    }

    /// Install all three monitor legs. Returns `true` only when the CG
    /// tap installed successfully (the same contract as
    /// `HotkeyEventTap.start`). NSEvent local + global installs are
    /// best-effort and don't gate the return value.
    @discardableResult
    func start() -> Bool {
        guard tap == nil, localMonitor == nil, globalMonitor == nil else {
            return tap?.isActive == true
        }

        let tap = tapFactory({ [weak self] event in
            self?.dispatchGlobalDeciders(event) ?? false
        })
        let tapStarted = tap.start()
        if tapStarted {
            self.tap = tap
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

    func stop() {
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
    func registerLocalDecider(
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
    func registerGlobalDecider(
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
    func registerGlobalObserver(
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
final class KeyEventRouterToken: @unchecked Sendable {
    private let cleanup: @Sendable () -> Void

    fileprivate init(cleanup: @escaping @Sendable () -> Void) {
        self.cleanup = cleanup
    }

    deinit {
        cleanup()
    }
}

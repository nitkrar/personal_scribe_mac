/// Global keyboard monitoring requires Input Monitoring permission in
/// System Settings -> Privacy & Security. The first call to
/// `NSEvent.addGlobalMonitorForEvents` may prompt for access or silently fail
/// until permission is granted. This is a separate permission prompt from
/// microphone access.
///
/// # Gesture model (pill UX spec §3, 2026-04-21)
///
/// The monitor implements three distinct gestures off the same
/// key + modifier combination:
///
/// * **Tap** — press and release within `holdThreshold` (300 ms). Fires
///   `onToggle` on release. Subsequent taps within `doubleTapWindow`
///   (400 ms) are absorbed silently — double-tap is an alias for
///   single-tap per the spec, not two actions.
/// * **Hold** — press and keep holding past `holdThreshold`. Fires
///   `onHoldStart` once the threshold elapses. On release fires
///   `onHoldRelease` (spec: transcribe what was captured during hold).
/// * **Double-tap** — two tap cycles < 400 ms apart. The second tap is
///   debounced; the gesture behaves as one single-tap (spec §3: "Same
///   as single tap — alias for muscle memory").
import AppKit
import Foundation
import PersonalScribeCore
import PersonalScribeSession

/// AppKit marks `NSEvent` as explicitly non-Sendable, but `NSEvent`
/// monitor callbacks are documented to run on the main thread — there
/// is no real cross-thread hop to guard against. This box lets us hand
/// the event into a `MainActor.assumeIsolated` block without fighting
/// the strict-concurrency checker.
private struct NSEventBox: @unchecked Sendable {
    let event: NSEvent
}

@MainActor
public final class GlobalHotkeyMonitor {
    public typealias HoldScheduler = @MainActor (
        _ delay: TimeInterval,
        _ action: @escaping @MainActor () -> Void
    ) -> HoldCanceller
    public typealias HoldCanceller = @MainActor () -> Void
    internal typealias GlobalMonitorInstaller = @MainActor (_ handler: @escaping (NSEvent) -> Void) -> Any?

    /// Threshold (seconds) separating tap vs hold. Matches spec §3
    /// ("press + release < 300 ms" = tap).
    public static let holdThreshold: TimeInterval = 0.3
    /// Window (seconds) after a tap fires during which subsequent taps
    /// are absorbed. Spec §3 "double-tap < 400 ms apart → same as single
    /// tap".
    public static let doubleTapWindow: TimeInterval = 0.4

    private static let recordingModifierMask: NSEvent.ModifierFlags = [
        .command,
        .control,
        .option,
        .shift,
    ]

    private let onToggle: @MainActor () -> Void
    private let onHoldStart: @MainActor () -> Void
    private let onHoldRelease: @MainActor () -> Void
    private let recordingHotkey: HotkeyPreference
    private let holdThreshold: TimeInterval
    private let doubleTapWindow: TimeInterval
    private let scheduleHoldDetection: HoldScheduler
    private let permissionService: any PermissionService
    private let logger: PersonalScribeLogger
    private let logSink: (@Sendable (_ level: String, _ message: String) -> Void)?
    private var installGlobalMonitor: GlobalMonitorInstaller

    private var globalMonitor: Any?
    private var localMonitor: Any?
    private var keyDownTimestamp: TimeInterval?
    private var hotkeyKeyDownSwallowed = false
    private var isHolding = false
    private var lastToggleTimestamp: TimeInterval?
    private var holdCanceller: HoldCanceller?

    public init(
        onToggle: @escaping @MainActor () -> Void,
        onHoldStart: @escaping @MainActor () -> Void = {},
        onHoldRelease: @escaping @MainActor () -> Void = {},
        recordingHotkey: HotkeyPreference = HotkeyPreference.resolve(),
        holdThreshold: TimeInterval = GlobalHotkeyMonitor.holdThreshold,
        doubleTapWindow: TimeInterval = GlobalHotkeyMonitor.doubleTapWindow,
        scheduleHoldDetection: @escaping HoldScheduler = { delay, action in
            let workItem = DispatchWorkItem {
                Task { @MainActor in
                    action()
                }
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: workItem)
            return {
                workItem.cancel()
            }
        },
        permissionService: (any PermissionService)? = nil,
        logger: PersonalScribeLogger = PersonalScribeLogger(category: PersonalScribeLogCategory.ui),
        logSink: (@Sendable (_ level: String, _ message: String) -> Void)? = nil
    ) {
        self.onToggle = onToggle
        self.onHoldStart = onHoldStart
        self.onHoldRelease = onHoldRelease
        self.recordingHotkey = recordingHotkey
        self.holdThreshold = holdThreshold
        self.doubleTapWindow = doubleTapWindow
        self.scheduleHoldDetection = scheduleHoldDetection
        self.permissionService = permissionService ?? AppKitPermissionService()
        self.logger = logger
        self.logSink = logSink
        self.installGlobalMonitor = { handler in
            NSEvent.addGlobalMonitorForEvents(
                matching: [.flagsChanged, .keyDown, .keyUp],
                handler: handler
            )
        }
    }

    internal convenience init(
        onToggle: @escaping @MainActor () -> Void,
        onHoldStart: @escaping @MainActor () -> Void = {},
        onHoldRelease: @escaping @MainActor () -> Void = {},
        recordingHotkey: HotkeyPreference = HotkeyPreference.resolve(),
        holdThreshold: TimeInterval = GlobalHotkeyMonitor.holdThreshold,
        doubleTapWindow: TimeInterval = GlobalHotkeyMonitor.doubleTapWindow,
        scheduleHoldDetection: @escaping HoldScheduler = { delay, action in
            let workItem = DispatchWorkItem {
                Task { @MainActor in
                    action()
                }
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: workItem)
            return {
                workItem.cancel()
            }
        },
        permissionService: (any PermissionService)? = nil,
        logger: PersonalScribeLogger = PersonalScribeLogger(category: PersonalScribeLogCategory.ui),
        logSink: (@Sendable (_ level: String, _ message: String) -> Void)? = nil,
        installGlobalMonitor: @escaping GlobalMonitorInstaller
    ) {
        self.init(
            onToggle: onToggle,
            onHoldStart: onHoldStart,
            onHoldRelease: onHoldRelease,
            recordingHotkey: recordingHotkey,
            holdThreshold: holdThreshold,
            doubleTapWindow: doubleTapWindow,
            scheduleHoldDetection: scheduleHoldDetection,
            permissionService: permissionService,
            logger: logger,
            logSink: logSink
        )
        self.installGlobalMonitor = installGlobalMonitor
    }

    public var isActive: Bool {
        globalMonitor != nil || localMonitor != nil
    }

    /// Introspection hooks for tests — `NSEvent` monitor handles are
    /// opaque `Any?` tokens, so tests check non-nil-ness here rather
    /// than invoke the real OS event system.
    internal var isGlobalMonitorActive: Bool { globalMonitor != nil }
    internal var isLocalMonitorActive: Bool { localMonitor != nil }

    public func start() {
        guard globalMonitor == nil, localMonitor == nil else {
            logger.info("Global hotkey monitor already active; ignoring duplicate start")
            return
        }

        resetState()
        // Keep `isActive` as an OR by refusing partial local-only setup.
        guard let globalMonitor = installGlobalMonitor({ [weak self] event in
            Task { @MainActor [weak self] in
                self?.handle(event: event)
            }
        }) else {
            handleMonitorInstallFailure()
            return
        }
        self.globalMonitor = globalMonitor

        // Local monitor fires for events headed to our own app — needed
        // so the hotkey works when Ninimma's window is frontmost (bug #4
        // 2026-04-21 dogfood). `addGlobalMonitorForEvents` only fires
        // for events to *other* apps. We swallow matching events so
        // `÷` doesn't leak into our own text fields while recording.
        localMonitor = NSEvent.addLocalMonitorForEvents(
            matching: [.flagsChanged, .keyDown, .keyUp]
        ) { [weak self] event in
            guard let self else { return event }
            let box = NSEventBox(event: event)
            // Run gesture-state + swallow decision on main actor; return
            // only `Bool` across the isolation boundary so NSEvent's
            // non-Sendable status doesn't poison the transfer.
            let shouldSwallow = MainActor.assumeIsolated {
                self.handle(event: box.event)
                return self.shouldSwallowLocal(box.event)
            }
            return shouldSwallow ? nil : event
        }
    }

    /// Emits the Input Monitoring warning when `addGlobalMonitorForEvents`
    /// returns nil. Probes the current TCC state so the log message can tell
    /// the reader whether permission is denied vs. still pending.
    internal func handleMonitorInstallFailure() {
        let state = permissionService.status(for: .inputMonitoring)
        let message = Self.monitorInstallFailureMessage(for: state)
        logger.error(message)
        logSink?("error", message)
    }

    internal static func monitorInstallFailureMessage(for state: PermissionStatus) -> String {
        let suffix = "Use the menu bar warning or grant access in System Settings -> "
            + "Privacy & Security -> Input Monitoring, then restart."
        switch state {
        case .denied:
            return "Global hotkey monitor failed to register — Input Monitoring permission denied. " + suffix
        case .pending:
            return "Global hotkey monitor failed to register — Input Monitoring permission still "
                + "pending (system may surface the TCC prompt on next attempt). " + suffix
        case .granted:
            return "Global hotkey monitor failed to register despite Input Monitoring reporting granted "
                + "— likely a transient AppKit failure. " + suffix
        }
    }

    public func stop() {
        if let handle = globalMonitor {
            NSEvent.removeMonitor(handle)
            globalMonitor = nil
        }
        if let handle = localMonitor {
            NSEvent.removeMonitor(handle)
            localMonitor = nil
        }
        resetState()
    }

    /// Local-monitor swallow decision. Returning `true` means the event
    /// will NOT be delivered to the downstream view chain (field editors
    /// etc.), preventing `÷` leakage in our own text fields.
    ///
    /// Rules:
    /// * `.keyDown` matching the hotkey (keyCode + modifiers, including
    ///   auto-repeat) → swallow.
    /// * `.keyUp` with the hotkey's keyCode → swallow only if the
    ///   matching keyDown was previously swallowed. Modifiers may
    ///   already have been released by the time keyUp lands, which is
    ///   why this ignores them (mirrors `handleKeyUp`).
    /// * `.flagsChanged` → pass through so unrelated keybindings that
    ///   care about modifier edges still work.
    /// * Everything else → pass through.
    internal func shouldSwallowLocal(_ event: NSEvent) -> Bool {
        switch event.type {
        case .keyDown:
            let shouldSwallow = matchesHotkey(HotkeyEvent(nsEvent: event))
            if shouldSwallow {
                hotkeyKeyDownSwallowed = true
            }
            return shouldSwallow
        case .keyUp:
            let shouldSwallow = hotkeyKeyDownSwallowed && event.keyCode == recordingHotkey.keyCode
            hotkeyKeyDownSwallowed = false
            return shouldSwallow
        default:
            return false
        }
    }

    internal func handle(event: NSEvent) {
        let hotkeyEvent = HotkeyEvent(nsEvent: event)
        handle(event: hotkeyEvent)
    }

    internal func handle(event: HotkeyEvent) {
        switch event.type {
        case .keyDown:
            handleKeyDown(event)
        case .keyUp:
            handleKeyUp(event)
        case .flagsChanged:
            // Pure modifier edges don't drive the gesture machine on
            // their own — `opt + /` needs the `/` keyDown/keyUp to
            // anchor tap/hold timing. The flagsChanged event is still
            // observed so `effectiveModifierFlags` stays accurate if we
            // re-introduce modifier-only hotkeys later.
            return
        }
    }

    private func handleKeyDown(_ event: HotkeyEvent) {
        guard matchesHotkey(event) else {
            return
        }

        // Auto-repeat keydowns come as separate events after macOS's
        // key-repeat delay. Ignore them — the gesture we care about is
        // the *first* keydown, which anchors tap vs hold timing.
        if event.isARepeat {
            return
        }

        keyDownTimestamp = event.timestamp
        isHolding = false

        holdCanceller?()
        holdCanceller = scheduleHoldDetection(holdThreshold) { [weak self] in
            self?.enterHoldIfStillPressed(downTimestamp: event.timestamp)
        }
    }

    private func handleKeyUp(_ event: HotkeyEvent) {
        guard event.keyCode == recordingHotkey.keyCode else {
            return
        }
        guard let downTimestamp = keyDownTimestamp else {
            return
        }

        keyDownTimestamp = nil
        holdCanceller?()
        holdCanceller = nil

        if isHolding {
            isHolding = false
            onHoldRelease()
            return
        }

        let duration = event.timestamp - downTimestamp
        if duration > holdThreshold {
            // Hold detector should have fired by now, but if it was
            // cancelled or the scheduler drifted, treat as a hold
            // release anyway.
            onHoldRelease()
            return
        }

        // Tap path — debounce against the previous tap.
        if let lastTs = lastToggleTimestamp,
           event.timestamp - lastTs <= doubleTapWindow {
            // Second tap within debounce window — silently absorbed.
            // Spec §3: double-tap is "same as single tap", not two
            // toggles in a row.
            return
        }

        lastToggleTimestamp = event.timestamp
        onToggle()
    }

    private func enterHoldIfStillPressed(downTimestamp: TimeInterval) {
        guard let currentDown = keyDownTimestamp, currentDown == downTimestamp else {
            return
        }
        guard !isHolding else {
            return
        }
        isHolding = true
        holdCanceller = nil
        onHoldStart()
    }

    private func matchesHotkey(_ event: HotkeyEvent) -> Bool {
        event.keyCode == recordingHotkey.keyCode &&
        effectiveModifierFlags(for: event) == recordingHotkey.modifierFlags
    }

    private func resetState() {
        keyDownTimestamp = nil
        hotkeyKeyDownSwallowed = false
        isHolding = false
        lastToggleTimestamp = nil
        holdCanceller?()
        holdCanceller = nil
    }

    private func effectiveModifierFlags(for event: HotkeyEvent) -> NSEvent.ModifierFlags {
        event.modifierFlags.intersection(Self.recordingModifierMask)
    }
}

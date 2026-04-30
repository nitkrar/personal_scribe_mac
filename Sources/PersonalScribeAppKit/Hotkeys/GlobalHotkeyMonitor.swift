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

@MainActor
public final class GlobalHotkeyMonitor {
    public typealias HoldScheduler = @MainActor (
        _ delay: TimeInterval,
        _ action: @escaping @MainActor () -> Void
    ) -> HoldCanceller
    public typealias HoldCanceller = @MainActor () -> Void

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
    /// Mutable so `updateRecordingHotkey(_:)` can swap the binding live
    /// when the user changes it in Settings — `matchesHotkey` and the
    /// swallow-decision paths read this property on every event, so no
    /// tap restart is needed.
    private(set) var recordingHotkey: HotkeyPreference
    private let holdThreshold: TimeInterval
    private let doubleTapWindow: TimeInterval
    private let scheduleHoldDetection: HoldScheduler
    private let permissionService: any PermissionService
    private let logger: PersonalScribeLogger
    private let logSink: (@Sendable (_ level: String, _ message: String) -> Void)?
    private let router: KeyEventRouter

    /// #028 — RAII registrations on the shared `KeyEventRouter`.
    /// `localToken` covers events delivered to Ninimma (swallow on
    /// match); `globalToken` covers events delivered to other apps via
    /// the CG tap (swallow on match — fixes the `÷÷÷÷` leak).
    private var localToken: KeyEventRouterToken?
    private var globalToken: KeyEventRouterToken?
    private var keyDownTimestamp: TimeInterval?
    private var hotkeyKeyDownSwallowed = false
    private var isHolding = false
    private var lastToggleTimestamp: TimeInterval?
    private var holdCanceller: HoldCanceller?

    /// #089 L-21..L-22 — per-mode hotkey table. Each entry pairs a
    /// `HotkeyPreference` with the `WorkflowMode.id` that should
    /// activate-and-record when the chord is pressed. Updated
    /// in-place via `updatePerModeHotkeys(_:)` — additive, never
    /// shadows the global recording hotkey (collision is a
    /// recorder-level rejection per L-23).
    private struct PerModeBinding {
        let preference: HotkeyPreference
        let modeID: String
    }
    private var perModeHotkeys: [PerModeBinding] = []
    /// Fires synchronously on per-mode hotkey keyDown. Wired by
    /// `AppComposition` to call `WorkflowModeRegistry.setCurrent(id:)`
    /// then start recording.
    private var perModeActivate: (@MainActor (String) -> Void)?
    /// Tracks the per-mode keyCode currently held so the matching
    /// keyUp swallows even when modifier flags have already lifted.
    private var perModeKeyDownSwallowedKeyCode: UInt16?

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
        router: KeyEventRouter? = nil,
        logger: PersonalScribeLogger,
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
        // Tests that don't exercise the lifecycle pass `router: nil`
        // and rely on the gesture-machine entry points (`handle(event:)`,
        // `shouldSwallowLocal(_:)`) directly. A fresh, never-started
        // `KeyEventRouter` is harmless for that mode.
        self.router = router ?? KeyEventRouter(logger: logger)
        self.logger = logger
        self.logSink = logSink
    }

    public var isActive: Bool {
        localToken != nil || globalToken != nil
    }

    /// Introspection hooks for tests. Both reflect whether the
    /// corresponding decider is currently registered with the router.
    internal var isGlobalMonitorActive: Bool { globalToken != nil }
    internal var isLocalMonitorActive: Bool { localToken != nil }

    public func start() {
        guard localToken == nil, globalToken == nil else {
            logger.info("Global hotkey monitor already active; ignoring duplicate start")
            return
        }

        resetState()

        // #028: register two deciders on the shared router — one for
        // events delivered to other apps (CG tap path; swallows the
        // `÷÷÷÷` leak during hold) and one for events delivered to
        // Ninimma itself (local NSEvent path; needed so the hotkey
        // works when our window is frontmost). Both share the same
        // gesture-machine + swallow logic.
        if !router.isTapActive {
            // Router's tap install failed (Input Monitoring denied or
            // transient OS failure). Surface the warning so the menu
            // bar can prompt the user. Local NSEvent path keeps
            // working — hotkey still fires when Ninimma is frontmost.
            handleMonitorInstallFailure()
        }

        let decider: @MainActor (HotkeyEvent) -> Bool = { [weak self] event in
            guard let self else { return false }
            self.handle(event: event)
            return self.shouldSwallowEvent(event)
        }
        localToken = router.registerLocalDecider(decider)
        globalToken = router.registerGlobalDecider(decider)
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
        // RAII deinit on each token Task-dispatches the actual
        // unregister. Setting to nil drops our strong refs.
        localToken = nil
        globalToken = nil
        resetState()
    }

    /// Swap the recording binding at runtime. Settings calls this the
    /// moment the user confirms a new shortcut in `HotkeyRecorder` so
    /// the change takes effect without a relaunch.
    ///
    /// In-flight gesture state is cleared so a release of the OLD
    /// keyCode arriving after the update doesn't ghost-fire either the
    /// old or new binding.
    public func updateRecordingHotkey(_ preference: HotkeyPreference) {
        recordingHotkey = preference
        resetState()
    }

    /// #089 L-22 — replace the per-mode hotkey table from the current
    /// `customModes` snapshot. Modes without a `hotkey` are skipped.
    /// Idempotent; the modes editor calls this whenever the registry's
    /// custom modes stream emits.
    public func updatePerModeHotkeys(_ modes: [WorkflowMode]) {
        perModeHotkeys = modes.compactMap { mode in
            guard let hotkey = mode.hotkey else { return nil }
            return PerModeBinding(preference: hotkey, modeID: mode.id)
        }
    }

    /// #089 L-22 — wire the side-effect closure that fires when a
    /// per-mode hotkey keyDown matches. The closure is expected to
    /// call `WorkflowModeRegistry.setCurrent(id:)` synchronously, then
    /// start recording. Async work is fine; the dispatch path returns
    /// immediately.
    public func setOnPerModeActivate(_ handler: @escaping @MainActor (String) -> Void) {
        perModeActivate = handler
    }

    /// Returns the per-mode binding matching `event` (keyDown), if any.
    /// Modifier comparison uses the same recording-modifier mask as the
    /// global hotkey so transient flags (e.g. CapsLock) don't break the
    /// match.
    private func perModeBinding(for event: HotkeyEvent) -> PerModeBinding? {
        let mods = event.modifierFlags.intersection(Self.recordingModifierMask)
        return perModeHotkeys.first { binding in
            binding.preference.keyCode == event.keyCode
                && binding.preference.modifierFlags == mods
        }
    }

    /// Swallow decision for the CGEventTap (global path). Same logic as
    /// `shouldSwallowLocal` — swallow matching keyDown (setting the
    /// balance flag), swallow matching-keyCode keyUp only when the
    /// prior keyDown was swallowed, pass flagsChanged through. Both
    /// paths share the `hotkeyKeyDownSwallowed` flag so a keyDown on
    /// one path + keyUp on the other stays balanced.
    internal func shouldSwallowEvent(_ event: HotkeyEvent) -> Bool {
        switch event.type {
        case .keyDown:
            if matchesHotkey(event) {
                hotkeyKeyDownSwallowed = true
                return true
            }
            if perModeBinding(for: event) != nil {
                perModeKeyDownSwallowedKeyCode = event.keyCode
                return true
            }
            return false
        case .keyUp:
            if hotkeyKeyDownSwallowed && event.keyCode == recordingHotkey.keyCode {
                hotkeyKeyDownSwallowed = false
                return true
            }
            if let pending = perModeKeyDownSwallowedKeyCode, pending == event.keyCode {
                perModeKeyDownSwallowedKeyCode = nil
                return true
            }
            return false
        case .flagsChanged:
            return false
        }
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
        let hk = HotkeyEvent(nsEvent: event)
        switch event.type {
        case .keyDown:
            if matchesHotkey(hk) {
                hotkeyKeyDownSwallowed = true
                return true
            }
            if perModeBinding(for: hk) != nil {
                perModeKeyDownSwallowedKeyCode = event.keyCode
                return true
            }
            return false
        case .keyUp:
            if hotkeyKeyDownSwallowed && event.keyCode == recordingHotkey.keyCode {
                hotkeyKeyDownSwallowed = false
                return true
            }
            if let pending = perModeKeyDownSwallowedKeyCode, pending == event.keyCode {
                perModeKeyDownSwallowedKeyCode = nil
                return true
            }
            return false
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
        if matchesHotkey(event) {
            // Auto-repeat keydowns come as separate events after macOS's
            // key-repeat delay. Ignore them — the gesture we care about
            // is the *first* keydown, which anchors tap vs hold timing.
            if event.isARepeat {
                return
            }

            keyDownTimestamp = event.timestamp
            isHolding = false

            holdCanceller?()
            holdCanceller = scheduleHoldDetection(holdThreshold) { [weak self] in
                self?.enterHoldIfStillPressed(downTimestamp: event.timestamp)
            }
            return
        }

        // #089 L-22 — per-mode hotkey: fire-on-keyDown (no tap/hold
        // gesture machine for V1). Auto-repeat is suppressed so a held
        // chord doesn't activate the same mode twice.
        if !event.isARepeat, let binding = perModeBinding(for: event) {
            perModeActivate?(binding.modeID)
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
        perModeKeyDownSwallowedKeyCode = nil
        isHolding = false
        lastToggleTimestamp = nil
        holdCanceller?()
        holdCanceller = nil
    }

    private func effectiveModifierFlags(for event: HotkeyEvent) -> NSEvent.ModifierFlags {
        event.modifierFlags.intersection(Self.recordingModifierMask)
    }
}

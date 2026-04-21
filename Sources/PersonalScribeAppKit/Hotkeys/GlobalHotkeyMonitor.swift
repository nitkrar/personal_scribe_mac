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
    private let recordingHotkey: HotkeyPreference
    private let holdThreshold: TimeInterval
    private let doubleTapWindow: TimeInterval
    private let scheduleHoldDetection: HoldScheduler
    private let permissionService: any PermissionService
    private let logger: PersonalScribeLogger
    private let logSink: (@Sendable (_ level: String, _ message: String) -> Void)?

    private var monitor: Any?
    private var keyDownTimestamp: TimeInterval?
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
    }

    public var isActive: Bool {
        monitor != nil
    }

    public func start() {
        guard monitor == nil else {
            logger.info("Global hotkey monitor already active; ignoring duplicate start")
            return
        }

        resetState()
        monitor = NSEvent.addGlobalMonitorForEvents(
            matching: [.flagsChanged, .keyDown, .keyUp]
        ) { [weak self] event in
            Task { @MainActor [weak self] in
                self?.handle(event: event)
            }
        }

        if monitor == nil {
            handleMonitorInstallFailure()
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
        guard let handle = monitor else {
            return
        }

        NSEvent.removeMonitor(handle)
        monitor = nil
        resetState()
    }

    internal func handle(event: NSEvent) {
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
        default:
            return
        }
    }

    private func handleKeyDown(_ event: NSEvent) {
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

    private func handleKeyUp(_ event: NSEvent) {
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

    private func matchesHotkey(_ event: NSEvent) -> Bool {
        event.keyCode == recordingHotkey.keyCode &&
        effectiveModifierFlags(for: event) == recordingHotkey.modifierFlags
    }

    private func resetState() {
        keyDownTimestamp = nil
        isHolding = false
        lastToggleTimestamp = nil
        holdCanceller?()
        holdCanceller = nil
    }

    private func effectiveModifierFlags(for event: NSEvent) -> NSEvent.ModifierFlags {
        event.modifierFlags.intersection(Self.recordingModifierMask)
    }
}

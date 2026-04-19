/// Global keyboard monitoring requires Input Monitoring permission in
/// System Settings -> Privacy & Security. The first call to
/// `NSEvent.addGlobalMonitorForEvents` may prompt for access or silently fail
/// until permission is granted. This is a separate permission prompt from
/// microphone access.
import AppKit
import Foundation
import SeshatCore
import SeshatSession

@MainActor
public final class GlobalHotkeyMonitor {
    internal typealias DeferredActionCanceller = @MainActor () -> Void
    internal typealias DeferredActionScheduler = @MainActor (
        _ delay: TimeInterval,
        _ action: @escaping @MainActor () -> Void
    ) -> DeferredActionCanceller

    private static let leftOptionKeyCode: UInt16 = 58
    private static let rightOptionKeyCode: UInt16 = 61
    private static let doubleTapWindow: TimeInterval = 0.4

    private let onTrigger: @MainActor () -> Void
    private let emergencyQuitRequested: @MainActor () -> Void
    private let tapWindow: TimeInterval
    private let scheduleDeferredTrigger: DeferredActionScheduler
    private let permissionProbe: any PermissionProbing
    private let logger: SeshatLogger
    private let logSink: (@Sendable (_ level: String, _ message: String) -> Void)?

    private var monitor: Any?
    private var pressedOptionKeyCodes: Set<UInt16> = []
    private var pendingToggleDeadline: TimeInterval?
    private var pendingToggleToken: UUID?
    private var pendingToggleCancellation: DeferredActionCanceller?
    private var tapCount = 0
    private var lastTapTimestamp: TimeInterval?

    public init(
        onTrigger: @escaping @MainActor () -> Void,
        emergencyQuitRequested: @escaping @MainActor () -> Void = {},
        tapWindow: TimeInterval = Self.doubleTapWindow,
        scheduleDeferredTrigger: @escaping DeferredActionScheduler = { delay, action in
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
        permissionProbe: any PermissionProbing = IOHIDPermissionProbe(),
        logger: SeshatLogger = SeshatLogger(category: SeshatLogCategory.ui),
        logSink: (@Sendable (_ level: String, _ message: String) -> Void)? = nil
    ) {
        self.onTrigger = onTrigger
        self.emergencyQuitRequested = emergencyQuitRequested
        self.tapWindow = tapWindow
        self.scheduleDeferredTrigger = scheduleDeferredTrigger
        self.permissionProbe = permissionProbe
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
        monitor = NSEvent.addGlobalMonitorForEvents(matching: .flagsChanged) { [weak self] event in
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
    /// the reader whether permission is denied vs. not-yet-prompted. UI
    /// remediation is deferred to Phase 2's NSMenu rebuild; until then,
    /// `log stream --predicate 'subsystem == "com.nitkrar.seshat"'` is how
    /// dogfood users discover the state.
    internal func handleMonitorInstallFailure() {
        let state = permissionProbe.checkInputMonitoring()
        let message = Self.monitorInstallFailureMessage(for: state)
        logger.error(message)
        logSink?("error", message)
    }

    internal static func monitorInstallFailureMessage(
        for state: InputMonitoringPermissionState
    ) -> String {
        let suffix = "Visible remediation will land with Phase 2 NSMenu; until then, grant access in "
            + "System Settings -> Privacy & Security -> Input Monitoring and restart."
        switch state {
        case .denied:
            return "Global hotkey monitor failed to register — Input Monitoring permission denied. " + suffix
        case .notDetermined:
            return "Global hotkey monitor failed to register — Input Monitoring permission not yet "
                + "determined (system may surface the TCC prompt on next attempt). " + suffix
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
        guard
            event.type == .flagsChanged,
            Self.isOptionKeyCode(event.keyCode)
        else {
            return
        }

        flushPendingToggleIfExpired(at: event.timestamp)

        guard handleOptionKeyEdge(for: event) else {
            return
        }

        handleTap(at: event.timestamp)
    }

    private static func isOptionKeyCode(_ keyCode: UInt16) -> Bool {
        keyCode == Self.leftOptionKeyCode || keyCode == Self.rightOptionKeyCode
    }

    private func handleOptionKeyEdge(for event: NSEvent) -> Bool {
        let wasPressed = pressedOptionKeyCodes.contains(event.keyCode)
        let isPressed = event.modifierFlags.contains(.option) && wasPressed == false

        if isPressed {
            pressedOptionKeyCodes.insert(event.keyCode)
        } else {
            pressedOptionKeyCodes.remove(event.keyCode)
        }

        return isPressed
    }

    private func handleTap(at timestamp: TimeInterval) {
        if
            let lastTapTimestamp,
            timestamp - lastTapTimestamp <= tapWindow
        {
            tapCount += 1
        } else {
            tapCount = 1
        }

        lastTapTimestamp = timestamp

        switch tapCount {
        case 2:
            schedulePendingToggle(after: tapWindow, deadline: timestamp + tapWindow)
        case 3:
            resetTapSequence()
            emergencyQuitRequested()
        default:
            return
        }
    }

    private func schedulePendingToggle(after delay: TimeInterval, deadline: TimeInterval) {
        cancelPendingToggle()

        let token = UUID()
        pendingToggleToken = token
        pendingToggleDeadline = deadline
        pendingToggleCancellation = scheduleDeferredTrigger(delay) { [weak self] in
            self?.firePendingToggle(token: token)
        }
    }

    private func flushPendingToggleIfExpired(at timestamp: TimeInterval) {
        guard
            let deadline = pendingToggleDeadline,
            timestamp > deadline,
            let token = pendingToggleToken
        else {
            return
        }

        firePendingToggle(token: token)
    }

    private func firePendingToggle(token: UUID) {
        guard pendingToggleToken == token else {
            return
        }

        cancelPendingToggle()
        tapCount = 0
        lastTapTimestamp = nil
        onTrigger()
    }

    private func resetTapSequence() {
        cancelPendingToggle()
        tapCount = 0
        lastTapTimestamp = nil
    }

    private func resetState() {
        resetTapSequence()
        pressedOptionKeyCodes.removeAll()
    }

    private func cancelPendingToggle() {
        pendingToggleCancellation?()
        pendingToggleCancellation = nil
        pendingToggleDeadline = nil
        pendingToggleToken = nil
    }
}

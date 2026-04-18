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
    private static let rightOptionKeyCode: UInt16 = 61
    private static let doubleTapWindow: TimeInterval = 0.4

    private let onTrigger: @MainActor () -> Void
    private let permissionProbe: any PermissionProbing
    private let logger: SeshatLogger
    private let logSink: (@Sendable (_ level: String, _ message: String) -> Void)?

    private var monitor: Any?
    private var isRightOptionPressed = false
    private var lastPressTimestamp: TimeInterval?

    public init(
        onTrigger: @escaping @MainActor () -> Void,
        permissionProbe: any PermissionProbing = IOHIDPermissionProbe(),
        logger: SeshatLogger = SeshatLogger(category: SeshatLogCategory.ui),
        logSink: (@Sendable (_ level: String, _ message: String) -> Void)? = nil
    ) {
        self.onTrigger = onTrigger
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

        isRightOptionPressed = false
        lastPressTimestamp = nil
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
        isRightOptionPressed = false
        lastPressTimestamp = nil
    }

    internal func handle(event: NSEvent) {
        guard
            event.type == .flagsChanged,
            event.keyCode == Self.rightOptionKeyCode
        else {
            return
        }

        let isPressed = event.modifierFlags.contains(.option)
        defer {
            isRightOptionPressed = isPressed
        }

        // Only care about rising edge (released → pressed).
        guard isPressed, isRightOptionPressed == false else {
            return
        }

        if
            let lastPressTimestamp,
            event.timestamp - lastPressTimestamp <= Self.doubleTapWindow
        {
            self.lastPressTimestamp = nil
            onTrigger()
            return
        }

        lastPressTimestamp = event.timestamp
    }
}

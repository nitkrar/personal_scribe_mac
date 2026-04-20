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
    public typealias DeferredActionCanceller = @MainActor () -> Void
    public typealias DeferredActionScheduler = @MainActor (
        _ delay: TimeInterval,
        _ action: @escaping @MainActor () -> Void
    ) -> DeferredActionCanceller

    private static let leftOptionKeyCode: UInt16 = 58
    private static let rightOptionKeyCode: UInt16 = 61
    public static let doubleTapWindow: TimeInterval = 0.4
    private static let recordingModifierMask: NSEvent.ModifierFlags = [
        .command,
        .control,
        .option,
        .shift,
    ]

    private let onTrigger: @MainActor () -> Void
    private let emergencyQuitRequested: @MainActor () -> Void
    private let recordingHotkey: HotkeyPreference
    private let tapWindow: TimeInterval
    private let scheduleDeferredTrigger: DeferredActionScheduler
    private let permissionService: any PermissionService
    private let logger: SeshatLogger
    private let logSink: (@Sendable (_ level: String, _ message: String) -> Void)?

    private var monitor: Any?
    private var pressedOptionKeyCodes: Set<UInt16> = []
    private var pendingToggleDeadline: TimeInterval?
    private var pendingToggleToken: UUID?
    private var pendingToggleCancellation: DeferredActionCanceller?
    private var optionTapCount = 0
    private var lastOptionTapTimestamp: TimeInterval?
    private var recordingTapCount = 0
    private var lastRecordingTapTimestamp: TimeInterval?

    public init(
        onTrigger: @escaping @MainActor () -> Void,
        emergencyQuitRequested: @escaping @MainActor () -> Void = {},
        recordingHotkey: HotkeyPreference = HotkeyPreference.resolve(),
        tapWindow: TimeInterval = GlobalHotkeyMonitor.doubleTapWindow,
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
        permissionService: (any PermissionService)? = nil,
        logger: SeshatLogger = SeshatLogger(category: SeshatLogCategory.ui),
        logSink: (@Sendable (_ level: String, _ message: String) -> Void)? = nil
    ) {
        self.onTrigger = onTrigger
        self.emergencyQuitRequested = emergencyQuitRequested
        self.recordingHotkey = recordingHotkey
        self.tapWindow = tapWindow
        self.scheduleDeferredTrigger = scheduleDeferredTrigger
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
            matching: [.flagsChanged, .keyDown]
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
    /// the reader whether permission is denied vs. still pending. Menu-bar
    /// warnings now surface the same remediation path; the log remains a
    /// secondary breadcrumb for startup failures and transient AppKit errors.
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
        flushPendingToggleIfExpired(at: event.timestamp)

        switch event.type {
        case .flagsChanged:
            handleFlagsChangedEvent(event)
        case .keyDown:
            handleKeyDownEvent(event)
        default:
            return
        }
    }

    private static func isOptionKeyCode(_ keyCode: UInt16) -> Bool {
        keyCode == Self.leftOptionKeyCode || keyCode == Self.rightOptionKeyCode
    }

    private func handleFlagsChangedEvent(_ event: NSEvent) {
        guard
            Self.isOptionKeyCode(event.keyCode),
            handleOptionKeyEdge(for: event)
        else {
            return
        }

        if handleOptionTap(at: event.timestamp) {
            return
        }

        handleRecordingHotkeyPress(
            keyCode: event.keyCode,
            modifierFlags: effectiveModifierFlags(for: event),
            timestamp: event.timestamp
        )
    }

    private func handleKeyDownEvent(_ event: NSEvent) {
        handleRecordingHotkeyPress(
            keyCode: event.keyCode,
            modifierFlags: effectiveModifierFlags(for: event),
            timestamp: event.timestamp
        )
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

    private func handleOptionTap(at timestamp: TimeInterval) -> Bool {
        if
            let lastOptionTapTimestamp,
            timestamp - lastOptionTapTimestamp <= tapWindow
        {
            optionTapCount += 1
        } else {
            optionTapCount = 1
        }

        lastOptionTapTimestamp = timestamp

        switch optionTapCount {
        case 3:
            resetTapSequences()
            emergencyQuitRequested()
            return true
        default:
            return false
        }
    }

    private func handleRecordingHotkeyPress(
        keyCode: UInt16,
        modifierFlags: NSEvent.ModifierFlags,
        timestamp: TimeInterval
    ) {
        guard
            keyCode == recordingHotkey.keyCode,
            modifierFlags == recordingHotkey.modifierFlags
        else {
            return
        }

        if pendingToggleToken != nil {
            return
        }

        guard recordingHotkey.tapCount > 1 else {
            onTrigger()
            return
        }

        if
            let lastRecordingTapTimestamp,
            timestamp - lastRecordingTapTimestamp <= tapWindow
        {
            recordingTapCount += 1
        } else {
            recordingTapCount = 1
        }

        self.lastRecordingTapTimestamp = timestamp

        guard recordingTapCount == recordingHotkey.tapCount else {
            return
        }

        schedulePendingToggle(after: tapWindow, deadline: timestamp + tapWindow)
        resetRecordingTapSequence()
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
        resetRecordingTapSequence()
        onTrigger()
    }

    private func resetTapSequences() {
        cancelPendingToggle()
        resetOptionTapSequence()
        resetRecordingTapSequence()
    }

    private func resetState() {
        resetTapSequences()
        pressedOptionKeyCodes.removeAll()
    }

    private func cancelPendingToggle() {
        pendingToggleCancellation?()
        pendingToggleCancellation = nil
        pendingToggleDeadline = nil
        pendingToggleToken = nil
    }

    private func resetOptionTapSequence() {
        optionTapCount = 0
        lastOptionTapTimestamp = nil
    }

    private func resetRecordingTapSequence() {
        recordingTapCount = 0
        lastRecordingTapTimestamp = nil
    }

    private func effectiveModifierFlags(for event: NSEvent) -> NSEvent.ModifierFlags {
        var modifierFlags = event.modifierFlags.intersection(Self.recordingModifierMask)
        if event.type == .flagsChanged, Self.isOptionKeyCode(event.keyCode) {
            modifierFlags.remove(.option)
        }
        return modifierFlags
    }
}

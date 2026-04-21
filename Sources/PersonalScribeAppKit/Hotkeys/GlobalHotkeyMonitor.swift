/// Global keyboard monitoring requires Input Monitoring permission in
/// System Settings -> Privacy & Security. The first call to
/// `NSEvent.addGlobalMonitorForEvents` may prompt for access or silently fail
/// until permission is granted. This is a separate permission prompt from
/// microphone access.
import AppKit
import Foundation
import PersonalScribeCore
import PersonalScribeSession

@MainActor
public final class GlobalHotkeyMonitor {
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
    private let recordingHotkey: HotkeyPreference
    private let tapWindow: TimeInterval
    private let permissionService: any PermissionService
    private let logger: PersonalScribeLogger
    private let logSink: (@Sendable (_ level: String, _ message: String) -> Void)?

    private var monitor: Any?
    private var pressedOptionKeyCodes: Set<UInt16> = []
    private var recordingTapCount = 0
    private var lastRecordingTapTimestamp: TimeInterval?

    public init(
        onTrigger: @escaping @MainActor () -> Void,
        recordingHotkey: HotkeyPreference = HotkeyPreference.resolve(),
        tapWindow: TimeInterval = GlobalHotkeyMonitor.doubleTapWindow,
        permissionService: (any PermissionService)? = nil,
        logger: PersonalScribeLogger = PersonalScribeLogger(category: PersonalScribeLogCategory.ui),
        logSink: (@Sendable (_ level: String, _ message: String) -> Void)? = nil
    ) {
        self.onTrigger = onTrigger
        self.recordingHotkey = recordingHotkey
        self.tapWindow = tapWindow
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

        resetRecordingTapSequence()
        onTrigger()
    }

    private func resetState() {
        resetRecordingTapSequence()
        pressedOptionKeyCodes.removeAll()
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

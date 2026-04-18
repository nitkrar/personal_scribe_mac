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
    private static let debounceInterval: TimeInterval = 0.2

    private let onTrigger: @MainActor () -> Void
    private let logger: SeshatLogger

    private var monitor: Any?
    private var isRightOptionPressed = false
    private var lastTriggerTimestamp: TimeInterval?

    public init(
        onTrigger: @escaping @MainActor () -> Void,
        logger: SeshatLogger = SeshatLogger(category: SeshatLogCategory.ui)
    ) {
        self.onTrigger = onTrigger
        self.logger = logger
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
        lastTriggerTimestamp = nil
        monitor = NSEvent.addGlobalMonitorForEvents(matching: .flagsChanged) { [weak self] event in
            Task { @MainActor [weak self] in
                self?.handle(event: event)
            }
        }
    }

    public func stop() {
        guard let handle = monitor else {
            return
        }

        NSEvent.removeMonitor(handle)
        monitor = nil
        isRightOptionPressed = false
        lastTriggerTimestamp = nil
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

        guard isPressed, isRightOptionPressed == false else {
            return
        }

        if let lastTriggerTimestamp, event.timestamp - lastTriggerTimestamp < Self.debounceInterval {
            return
        }

        lastTriggerTimestamp = event.timestamp
        onTrigger()
    }
}

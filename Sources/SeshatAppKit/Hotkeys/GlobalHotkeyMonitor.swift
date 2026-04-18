import AppKit
import Foundation
import SeshatCore
import SeshatSession

@MainActor
public final class GlobalHotkeyMonitor {
    private static let rightOptionKeyCode: UInt16 = 61

    private let onTrigger: @MainActor () -> Void
    private let logger: SeshatLogger

    private var monitor: Any?
    private var isRightOptionPressed = false

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

        monitor = NSEvent.addGlobalMonitorForEvents(matching: .flagsChanged) { [weak self] event in
            guard
                let self,
                event.keyCode == Self.rightOptionKeyCode
            else {
                return
            }

            let isPressed = event.modifierFlags.contains(.option)
            if isPressed, self.isRightOptionPressed == false {
                self.onTrigger()
            }

            self.isRightOptionPressed = isPressed
        }
    }

    public func stop() {
        guard let monitor else {
            return
        }

        NSEvent.removeMonitor(monitor)
        monitor = nil
        isRightOptionPressed = false
    }
}

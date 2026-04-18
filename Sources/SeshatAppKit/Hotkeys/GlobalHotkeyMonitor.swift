import AppKit
import Foundation
import SeshatCore
import SeshatSession

@MainActor
public final class GlobalHotkeyMonitor {
    private let onTrigger: @MainActor () -> Void
    private let logger: SeshatLogger

    private var monitor: Any?

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

        monitor = NSObject()
    }

    public func stop() {
        monitor = nil
    }
}

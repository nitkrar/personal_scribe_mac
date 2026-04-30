import Foundation
import os

public struct OSLogDiagnosticsSink: DiagnosticsSink {
    private let subsystem: String

    public init(subsystem: String = AppBrand.logSubsystem) {
        self.subsystem = subsystem
    }

    public func record(_ event: RedactedDiagnosticsEvent) async {
        let logger = Logger(subsystem: subsystem, category: event.category)
        let line = DiagnosticsLineRenderer.render(event)

        switch event.level {
        case .debug:
            logger.debug("\(line, privacy: .public)")
        case .info:
            logger.info("\(line, privacy: .public)")
        case .notice:
            logger.notice("\(line, privacy: .public)")
        case .error:
            logger.error("\(line, privacy: .public)")
        }
    }
}

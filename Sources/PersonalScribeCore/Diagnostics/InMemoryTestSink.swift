import Foundation

public actor InMemoryTestSink: DiagnosticsSink {
    private var events: [RedactedDiagnosticsEvent] = []

    public init() {}

    public func record(_ event: RedactedDiagnosticsEvent) async {
        events.append(event)
    }

    public func snapshot() -> [RedactedDiagnosticsEvent] {
        events
    }
}

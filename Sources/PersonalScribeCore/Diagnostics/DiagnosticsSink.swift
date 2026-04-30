import Foundation

public protocol DiagnosticsSink: Sendable {
    func record(_ event: RedactedDiagnosticsEvent) async
}

public struct AnyDiagnosticsSink: Sendable {
    private let recordClosure: @Sendable (RedactedDiagnosticsEvent) async -> Void

    public init<Sink: DiagnosticsSink>(_ sink: Sink) {
        recordClosure = { event in
            await sink.record(event)
        }
    }

    public func record(_ event: RedactedDiagnosticsEvent) async {
        await recordClosure(event)
    }
}

public extension DiagnosticsSink {
    func eraseToAnyDiagnosticsSink() -> AnyDiagnosticsSink {
        AnyDiagnosticsSink(self)
    }
}

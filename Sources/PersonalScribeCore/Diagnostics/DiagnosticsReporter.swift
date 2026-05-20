import Foundation

private final class DiagnosticsSinkFanout: @unchecked Sendable {
    private let continuation: AsyncStream<RedactedDiagnosticsEvent>.Continuation
    private let worker: Task<Void, Never>

    init(sinks: [AnyDiagnosticsSink]) {
        var streamContinuation: AsyncStream<RedactedDiagnosticsEvent>.Continuation?
        let stream = AsyncStream<RedactedDiagnosticsEvent> { continuation in
            streamContinuation = continuation
        }
        guard let streamContinuation else {
            preconditionFailure("Diagnostics sink fanout failed to initialize its event stream.")
        }

        continuation = streamContinuation
        worker = Task.detached(priority: .utility) {
            for await event in stream {
                for sink in sinks {
                    await sink.record(event)
                }
            }
        }
    }

    deinit {
        continuation.finish()
        worker.cancel()
    }

    func submit(_ event: RedactedDiagnosticsEvent) {
        continuation.yield(event)
    }
}

public struct DiagnosticsReporter: Sendable {
    private let fanout: DiagnosticsSinkFanout
    private let redactor: PIIRedactor
    private let now: @Sendable () -> Date

    public init(
        sinks: [any DiagnosticsSink] = [],
        redactor: PIIRedactor = PIIRedactor(),
        now: @escaping @Sendable () -> Date = Date.init
    ) {
        fanout = DiagnosticsSinkFanout(sinks: sinks.map { $0.eraseToAnyDiagnosticsSink() })
        self.redactor = redactor
        self.now = now
    }

    public static func testing(
        now: @escaping @Sendable () -> Date = Date.init
    ) -> DiagnosticsReporter {
        DiagnosticsReporter(sinks: [], redactor: PIIRedactor(), now: now)
    }

    public func debug(
        _ message: String,
        category: String,
        metadata: [String: String] = [:],
        file: StaticString = #fileID,
        function: StaticString = #function,
        line: UInt = #line
    ) {
        _ = emit(
            level: .debug,
            message: message,
            error: nil,
            category: category,
            metadata: metadata,
            userFacing: nil,
            file: file,
            function: function,
            line: line
        )
    }

    public func info(
        _ message: String,
        category: String,
        metadata: [String: String] = [:],
        file: StaticString = #fileID,
        function: StaticString = #function,
        line: UInt = #line
    ) {
        _ = emit(
            level: .info,
            message: message,
            error: nil,
            category: category,
            metadata: metadata,
            userFacing: nil,
            file: file,
            function: function,
            line: line
        )
    }

    public func notice(
        _ message: String,
        category: String,
        metadata: [String: String] = [:],
        file: StaticString = #fileID,
        function: StaticString = #function,
        line: UInt = #line
    ) {
        _ = emit(
            level: .notice,
            message: message,
            error: nil,
            category: category,
            metadata: metadata,
            userFacing: nil,
            file: file,
            function: function,
            line: line
        )
    }

    @discardableResult
    public func error(
        _ message: String,
        error: (any Error)? = nil,
        category: String,
        metadata: [String: String] = [:],
        userFacing: UserFacingDiagnostic? = nil,
        file: StaticString = #fileID,
        function: StaticString = #function,
        line: UInt = #line
    ) -> DiagnosticsEvent {
        emit(
            level: .error,
            message: message,
            error: error,
            category: category,
            metadata: metadata,
            userFacing: userFacing,
            file: file,
            function: function,
            line: line
        )
    }

    @discardableResult
    private func emit(
        level: DiagnosticsLevel,
        message: String,
        error: (any Error)?,
        category: String,
        metadata: [String: String],
        userFacing: UserFacingDiagnostic?,
        file: StaticString,
        function: StaticString,
        line: UInt
    ) -> DiagnosticsEvent {
        let event = DiagnosticsEvent(
            level: level,
            category: category,
            message: message,
            timestamp: now(),
            underlyingError: error.map(DiagnosticsUnderlyingError.init),
            metadata: metadata,
            userFacing: userFacing,
            sourceLocation: DiagnosticsSourceLocation(
                file: String(describing: file),
                function: String(describing: function),
                line: line
            )
        )

        let redacted = redactor.redact(event)
        fanout.submit(redacted)

        return event
    }
}

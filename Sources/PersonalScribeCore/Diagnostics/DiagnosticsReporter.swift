import Foundation

public struct DiagnosticsReporter: Sendable {
    private let sinks: [AnyDiagnosticsSink]
    private let redactor: PIIRedactor
    private let now: @Sendable () -> Date

    public init(
        sinks: [any DiagnosticsSink] = [],
        redactor: PIIRedactor = PIIRedactor(),
        now: @escaping @Sendable () -> Date = Date.init
    ) {
        self.sinks = sinks.map { $0.eraseToAnyDiagnosticsSink() }
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
        for sink in sinks {
            Task {
                await sink.record(redacted)
            }
        }

        return event
    }
}

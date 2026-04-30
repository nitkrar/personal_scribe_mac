import Foundation

public struct PersonalScribeLogger: Sendable {
    public static let subsystem = AppBrand.logSubsystem

    private let category: String
    private let reporter: DiagnosticsReporter

    public static func testing(
        category: String,
        now: @escaping @Sendable () -> Date = Date.init
    ) -> PersonalScribeLogger {
        PersonalScribeLogger(
            category: category,
            reporter: DiagnosticsReporter.testing(now: now)
        )
    }

    public init(category: String, reporter: DiagnosticsReporter) {
        self.category = category
        self.reporter = reporter
    }

    public func debug(
        _ message: @autoclosure () -> String,
        metadata: [String: String] = [:],
        file: StaticString = #fileID,
        function: StaticString = #function,
        line: UInt = #line
    ) {
        reporter.debug(
            message(),
            category: category,
            metadata: metadata,
            file: file,
            function: function,
            line: line
        )
    }

    public func info(
        _ message: @autoclosure () -> String,
        metadata: [String: String] = [:],
        file: StaticString = #fileID,
        function: StaticString = #function,
        line: UInt = #line
    ) {
        reporter.info(
            message(),
            category: category,
            metadata: metadata,
            file: file,
            function: function,
            line: line
        )
    }

    @discardableResult
    public func error(
        _ message: @autoclosure () -> String,
        error: (any Error)? = nil,
        metadata: [String: String] = [:],
        userFacing: UserFacingDiagnostic? = nil,
        file: StaticString = #fileID,
        function: StaticString = #function,
        line: UInt = #line
    ) -> DiagnosticsEvent {
        reporter.error(
            message(),
            error: error,
            category: category,
            metadata: metadata,
            userFacing: userFacing,
            file: file,
            function: function,
            line: line
        )
    }
}

public enum PersonalScribeLogCategory {
    public static let audio = "audio"
    public static let transcription = "transcription"
    public static let session = "session"
    public static let ui = "ui"
    public static let app = "app"
}

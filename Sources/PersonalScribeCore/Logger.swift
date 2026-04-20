import Foundation
import os

public struct PersonalScribeLogger: Sendable {
    public static let subsystem = AppBrand.logSubsystem

    private let logger: Logger

    public init(category: String) {
        logger = Logger(subsystem: Self.subsystem, category: category)
    }

    public func debug(
        _ message: @autoclosure () -> String,
        file: StaticString = #fileID,
        line: UInt = #line
    ) {
        let renderedMessage = message()
        let renderedFile = String(describing: file)
        logger.debug("\(renderedMessage, privacy: .public) [\(renderedFile, privacy: .public):\(line)]")
    }

    public func info(
        _ message: @autoclosure () -> String,
        file: StaticString = #fileID,
        line: UInt = #line
    ) {
        let renderedMessage = message()
        let renderedFile = String(describing: file)
        logger.info("\(renderedMessage, privacy: .public) [\(renderedFile, privacy: .public):\(line)]")
    }

    public func error(
        _ message: @autoclosure () -> String,
        error: (any Error)? = nil,
        file: StaticString = #fileID,
        line: UInt = #line
    ) {
        let renderedMessage = message()
        let renderedFile = String(describing: file)
        let detail = error.map { " \($0.localizedDescription)" } ?? ""
        logger.error("\(renderedMessage, privacy: .public)\(detail, privacy: .public) [\(renderedFile, privacy: .public):\(line)]")
    }
}

public enum PersonalScribeLogCategory {
    public static let audio = "audio"
    public static let transcription = "transcription"
    public static let session = "session"
    public static let ui = "ui"
    public static let app = "app"
}

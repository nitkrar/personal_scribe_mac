import Foundation
import os

public struct SeshatLogger: Sendable {
    public static let subsystem = "com.nitkrar.seshat"

    public init(category: String) {}

    public func debug(
        _ message: @autoclosure () -> String,
        file: StaticString = #fileID,
        line: UInt = #line
    ) {}

    public func info(
        _ message: @autoclosure () -> String,
        file: StaticString = #fileID,
        line: UInt = #line
    ) {}

    public func error(
        _ message: @autoclosure () -> String,
        error: (any Error)? = nil,
        file: StaticString = #fileID,
        line: UInt = #line
    ) {}
}

public enum SeshatLogCategory {
    public static let audio = "audio"
    public static let transcription = "transcription"
    public static let session = "session"
    public static let ui = "ui"
    public static let app = "app"
}

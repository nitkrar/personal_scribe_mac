import Foundation
import XCTest
@testable import PersonalScribeCore

final class FileDiagnosticsSinkTests: XCTestCase {
    func testDebugFileDiagnosticsSinkAcceptsDebugEvents() async throws {
        let tempDirectory = try makeTemporaryDirectory()
        let sink = DebugFileDiagnosticsSink(
            storageLocatorProvider: { FixedStorageLocator(baseDirectory: tempDirectory) }
        )

        await sink.record(makeEvent(level: .debug, message: "debug-event"))

        let contents = try XCTUnwrap(logContentsIfPresent(named: "debug.log", in: tempDirectory))
        XCTAssertTrue(contents.contains("level=debug"))
        XCTAssertTrue(contents.contains("message=\"debug-event\""))
    }

    func testDebugFileDiagnosticsSinkIgnoresNonDebugEvents() async throws {
        let tempDirectory = try makeTemporaryDirectory()
        let sink = DebugFileDiagnosticsSink(
            storageLocatorProvider: { FixedStorageLocator(baseDirectory: tempDirectory) }
        )

        await sink.record(makeEvent(level: .info, message: "info-event"))
        await sink.record(makeEvent(level: .notice, message: "notice-event"))
        await sink.record(makeEvent(level: .error, message: "error-event"))

        XCTAssertNil(logContentsIfPresent(named: "debug.log", in: tempDirectory))
    }

    func testDebugFileDiagnosticsSinkAppendsToCorrectFile() async throws {
        let tempDirectory = try makeTemporaryDirectory()
        let sink = DebugFileDiagnosticsSink(
            storageLocatorProvider: { FixedStorageLocator(baseDirectory: tempDirectory) }
        )

        await sink.record(makeEvent(level: .debug, message: "first-debug-event"))
        await sink.record(makeEvent(level: .debug, message: "second-debug-event"))

        let debugContents = try XCTUnwrap(logContentsIfPresent(named: "debug.log", in: tempDirectory))
        XCTAssertTrue(debugContents.contains("message=\"first-debug-event\""))
        XCTAssertTrue(debugContents.contains("message=\"second-debug-event\""))
        XCTAssertNil(logContentsIfPresent(named: "diagnostics.log", in: tempDirectory))
        XCTAssertNil(logContentsIfPresent(named: "errors.log", in: tempDirectory))
    }

    func testVerboseFileDiagnosticsSinkAcceptsInfoEvents() async throws {
        let tempDirectory = try makeTemporaryDirectory()
        let sink = VerboseFileDiagnosticsSink(
            storageLocatorProvider: { FixedStorageLocator(baseDirectory: tempDirectory) }
        )

        await sink.record(makeEvent(level: .info, message: "info-event"))

        let contents = try XCTUnwrap(logContentsIfPresent(named: "diagnostics.log", in: tempDirectory))
        XCTAssertTrue(contents.contains("level=info"))
        XCTAssertTrue(contents.contains("message=\"info-event\""))
    }

    func testVerboseFileDiagnosticsSinkAcceptsNoticeEvents() async throws {
        let tempDirectory = try makeTemporaryDirectory()
        let sink = VerboseFileDiagnosticsSink(
            storageLocatorProvider: { FixedStorageLocator(baseDirectory: tempDirectory) }
        )

        await sink.record(makeEvent(level: .notice, message: "notice-event"))

        let contents = try XCTUnwrap(logContentsIfPresent(named: "diagnostics.log", in: tempDirectory))
        XCTAssertTrue(contents.contains("level=notice"))
        XCTAssertTrue(contents.contains("message=\"notice-event\""))
    }

    func testVerboseFileDiagnosticsSinkIgnoresDebugEvents() async throws {
        let tempDirectory = try makeTemporaryDirectory()
        let sink = VerboseFileDiagnosticsSink(
            storageLocatorProvider: { FixedStorageLocator(baseDirectory: tempDirectory) }
        )

        await sink.record(makeEvent(level: .debug, message: "debug-event"))

        XCTAssertNil(logContentsIfPresent(named: "diagnostics.log", in: tempDirectory))
    }

    func testVerboseFileDiagnosticsSinkIgnoresErrorEvents() async throws {
        let tempDirectory = try makeTemporaryDirectory()
        let sink = VerboseFileDiagnosticsSink(
            storageLocatorProvider: { FixedStorageLocator(baseDirectory: tempDirectory) }
        )

        await sink.record(makeEvent(level: .error, message: "error-event"))

        XCTAssertNil(logContentsIfPresent(named: "diagnostics.log", in: tempDirectory))
    }

    func testAppendWritesToTheExistingFileInsteadOfReplacingIt() async throws {
        let tempDirectory = try makeTemporaryDirectory()
        let logURL = try makeLogsDirectory(in: tempDirectory).appendingPathComponent("diagnostics.log")
        try "earlier-line\n".write(to: logURL, atomically: true, encoding: .utf8)
        let inodeBefore = try inode(of: logURL)
        let sink = VerboseFileDiagnosticsSink(
            storageLocatorProvider: { FixedStorageLocator(baseDirectory: tempDirectory) }
        )

        await sink.record(makeEvent(level: .info, message: "appended-event"))

        let contents = try String(contentsOf: logURL, encoding: .utf8)
        XCTAssertTrue(contents.hasPrefix("earlier-line\n"))
        XCTAssertTrue(contents.contains("message=\"appended-event\""))
        XCTAssertEqual(try inode(of: logURL), inodeBefore)
    }

    func testReachingTheSizeCapArchivesTheFileAndStartsANewOne() async throws {
        let tempDirectory = try makeTemporaryDirectory()
        let logsDirectory = try makeLogsDirectory(in: tempDirectory)
        let lineLength = DiagnosticsLineRenderer.render(makeEvent(level: .info, message: "event-1")).utf8.count + 1
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = try XCTUnwrap(TimeZone(secondsFromGMT: 0))
        let rollovers = RolloverCounter()
        let sink = VerboseFileDiagnosticsSink(
            storageLocatorProvider: { FixedStorageLocator(baseDirectory: tempDirectory) },
            options: DiagnosticsLogFileOptions(
                maxLogSizeBytes: lineLength + lineLength / 2,
                now: { Date(timeIntervalSince1970: 1_790_000_000) }, // 2026-09-21 UTC
                calendar: calendar,
                onRollover: { rollovers.increment() }
            )
        )

        for index in 1...3 {
            await sink.record(makeEvent(level: .info, message: "event-\(index)"))
        }

        let files = try FileManager.default.contentsOfDirectory(atPath: logsDirectory.path).sorted()
        XCTAssertEqual(files, ["diagnostics.2026-09-21.1.log", "diagnostics.2026-09-21.log", "diagnostics.log"])
        func contents(_ name: String) throws -> String {
            try String(contentsOf: logsDirectory.appendingPathComponent(name), encoding: .utf8)
        }
        XCTAssertTrue(try contents("diagnostics.2026-09-21.log").contains("message=\"event-1\""))
        XCTAssertTrue(try contents("diagnostics.2026-09-21.1.log").contains("message=\"event-2\""))
        XCTAssertTrue(try contents("diagnostics.log").contains("message=\"event-3\""))
        XCTAssertEqual(rollovers.count, 2)
    }

    private func makeLogsDirectory(in baseDirectory: URL) throws -> URL {
        let logsDirectory = baseDirectory
            .appendingPathComponent(ManagedDirectory.logs.pathComponent, isDirectory: true)
        try FileManager.default.createDirectory(at: logsDirectory, withIntermediateDirectories: true)
        return logsDirectory
    }

    private func inode(of url: URL) throws -> Int {
        let attributes = try FileManager.default.attributesOfItem(atPath: url.path)
        return try XCTUnwrap(attributes[.systemFileNumber] as? Int)
    }

    func testLineTimestampUsesLocalTimeWithOffset() throws {
        let london = try XCTUnwrap(TimeZone(identifier: "Europe/London"))
        let line = DiagnosticsLineRenderer.render(makeEvent(level: .info, message: "x"), timeZone: london)

        XCTAssertTrue(line.hasPrefix("2026-05-03T04:09:37.123+01:00 "), line)
    }

    private func makeEvent(level: DiagnosticsLevel, message: String) -> RedactedDiagnosticsEvent {
        RedactedDiagnosticsEvent(
            level: level,
            category: PersonalScribeLogCategory.app,
            message: message,
            timestamp: Date(timeIntervalSince1970: 1_777_777_777.123),
            underlyingError: nil,
            metadata: [:],
            userFacing: nil,
            sourceLocation: DiagnosticsSourceLocation(
                file: "FileDiagnosticsSinkTests.swift",
                function: #function,
                line: #line
            )
        )
    }

    private func makeTemporaryDirectory() throws -> URL {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory
    }

    private func logContentsIfPresent(named fileName: String, in baseDirectory: URL) -> String? {
        let logURL = baseDirectory
            .appendingPathComponent(ManagedDirectory.logs.pathComponent, isDirectory: true)
            .appendingPathComponent(fileName)

        return try? String(contentsOf: logURL, encoding: .utf8)
    }
}

private final class RolloverCounter: @unchecked Sendable {
    private let lock = NSLock()
    private var value = 0

    var count: Int {
        lock.withLock { value }
    }

    func increment() {
        lock.withLock { value += 1 }
    }
}

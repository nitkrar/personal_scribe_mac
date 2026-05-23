import Foundation
import XCTest
@testable import PersonalScribeCore

final class FileDiagnosticsSinkTests: XCTestCase {
    func testDebugFileDiagnosticsSinkAcceptsDebugEvents() async throws {
        let tempDirectory = try makeTemporaryDirectory()
        let sink = DebugFileDiagnosticsSink(
            storageLocatorProvider: { FixedStorageLocator(baseDirectory: tempDirectory) },
            atomicFileWriter: FileManagerAtomicFileWriter(fileManager: .default)
        )

        await sink.record(makeEvent(level: .debug, message: "debug-event"))

        let contents = try XCTUnwrap(logContentsIfPresent(named: "debug.log", in: tempDirectory))
        XCTAssertTrue(contents.contains("level=debug"))
        XCTAssertTrue(contents.contains("message=\"debug-event\""))
    }

    func testDebugFileDiagnosticsSinkIgnoresNonDebugEvents() async throws {
        let tempDirectory = try makeTemporaryDirectory()
        let sink = DebugFileDiagnosticsSink(
            storageLocatorProvider: { FixedStorageLocator(baseDirectory: tempDirectory) },
            atomicFileWriter: FileManagerAtomicFileWriter(fileManager: .default)
        )

        await sink.record(makeEvent(level: .info, message: "info-event"))
        await sink.record(makeEvent(level: .notice, message: "notice-event"))
        await sink.record(makeEvent(level: .error, message: "error-event"))

        XCTAssertNil(logContentsIfPresent(named: "debug.log", in: tempDirectory))
    }

    func testDebugFileDiagnosticsSinkAppendsToCorrectFile() async throws {
        let tempDirectory = try makeTemporaryDirectory()
        let sink = DebugFileDiagnosticsSink(
            storageLocatorProvider: { FixedStorageLocator(baseDirectory: tempDirectory) },
            atomicFileWriter: FileManagerAtomicFileWriter(fileManager: .default)
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
            storageLocatorProvider: { FixedStorageLocator(baseDirectory: tempDirectory) },
            isEnabled: { true },
            atomicFileWriter: FileManagerAtomicFileWriter(fileManager: .default)
        )

        await sink.record(makeEvent(level: .info, message: "info-event"))

        let contents = try XCTUnwrap(logContentsIfPresent(named: "diagnostics.log", in: tempDirectory))
        XCTAssertTrue(contents.contains("level=info"))
        XCTAssertTrue(contents.contains("message=\"info-event\""))
    }

    func testVerboseFileDiagnosticsSinkAcceptsNoticeEvents() async throws {
        let tempDirectory = try makeTemporaryDirectory()
        let sink = VerboseFileDiagnosticsSink(
            storageLocatorProvider: { FixedStorageLocator(baseDirectory: tempDirectory) },
            isEnabled: { true },
            atomicFileWriter: FileManagerAtomicFileWriter(fileManager: .default)
        )

        await sink.record(makeEvent(level: .notice, message: "notice-event"))

        let contents = try XCTUnwrap(logContentsIfPresent(named: "diagnostics.log", in: tempDirectory))
        XCTAssertTrue(contents.contains("level=notice"))
        XCTAssertTrue(contents.contains("message=\"notice-event\""))
    }

    func testVerboseFileDiagnosticsSinkIgnoresDebugEvents() async throws {
        let tempDirectory = try makeTemporaryDirectory()
        let sink = VerboseFileDiagnosticsSink(
            storageLocatorProvider: { FixedStorageLocator(baseDirectory: tempDirectory) },
            isEnabled: { true },
            atomicFileWriter: FileManagerAtomicFileWriter(fileManager: .default)
        )

        await sink.record(makeEvent(level: .debug, message: "debug-event"))

        XCTAssertNil(logContentsIfPresent(named: "diagnostics.log", in: tempDirectory))
    }

    func testVerboseFileDiagnosticsSinkIgnoresErrorEvents() async throws {
        let tempDirectory = try makeTemporaryDirectory()
        let sink = VerboseFileDiagnosticsSink(
            storageLocatorProvider: { FixedStorageLocator(baseDirectory: tempDirectory) },
            isEnabled: { true },
            atomicFileWriter: FileManagerAtomicFileWriter(fileManager: .default)
        )

        await sink.record(makeEvent(level: .error, message: "error-event"))

        XCTAssertNil(logContentsIfPresent(named: "diagnostics.log", in: tempDirectory))
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

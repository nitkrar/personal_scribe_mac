import XCTest
@testable import PersonalScribeCore

final class SessionErrorReporterTests: XCTestCase {
    func testReportReturnsPayloadAndWritesStructuredLogEntry() async throws {
        let tempDirectory = try makeTemporaryDirectory()
        let fixedDate = Date(timeIntervalSince1970: 1_777_777_777.123)
        let reporter = SessionErrorReporter(
            logger: PersonalScribeLogger(category: PersonalScribeLogCategory.session),
            now: { fixedDate },
            storageLocatorProvider: { FixedStorageLocator(baseDirectory: tempDirectory) },
            atomicFileWriter: FileManagerAtomicFileWriter(fileManager: .default)
        )

        let reported = reporter.report(
            PersistenceFailure.writeFailed,
            mappedError: .transcriptionFailure,
            category: PersonalScribeLogCategory.session,
            detail: "writeFailed",
            context: [
                "stage": PipelineStepID.persistence.rawValue,
                "mode": "meeting",
            ],
            file: "SessionErrorReporterTests.swift",
            function: "testReportReturnsPayloadAndWritesStructuredLogEntry",
            line: 42
        )

        XCTAssertEqual(reported.mappedError, .transcriptionFailure)
        XCTAssertEqual(
            reported.userMessage,
            "Transcription failed. Try transcribing the recording again."
        )
        XCTAssertEqual(reported.detail, "writeFailed")
        XCTAssertEqual(reported.timestamp, fixedDate)
        XCTAssertEqual(reported.category, PersonalScribeLogCategory.session)
        XCTAssertEqual(reported.context["stage"], PipelineStepID.persistence.rawValue)

        let logURL = tempDirectory
            .appendingPathComponent(ManagedDirectory.logs.pathComponent, isDirectory: true)
            .appendingPathComponent("errors.log")
        let contents = try await waitForLogContents(at: logURL)

        XCTAssertTrue(contents.contains("2026-05-03T03:09:37.123Z"))
        XCTAssertTrue(contents.contains("[session]"))
        XCTAssertTrue(contents.contains("mappedError=transcriptionFailure"))
        XCTAssertTrue(contents.contains("detail=writeFailed"))
        XCTAssertTrue(contents.contains("stage=persistence"))
        XCTAssertTrue(contents.contains("mode=meeting"))
        XCTAssertTrue(contents.contains("file=SessionErrorReporterTests.swift"))
        XCTAssertTrue(contents.contains("function=testReportReturnsPayloadAndWritesStructuredLogEntry"))
        XCTAssertTrue(contents.contains("line=42"))
    }

    func testReportStillReturnsPayloadWhenLogWriteFails() async throws {
        let tempDirectory = try makeTemporaryDirectory()
        let reporter = SessionErrorReporter(
            logger: PersonalScribeLogger(category: PersonalScribeLogCategory.session),
            now: { Date(timeIntervalSince1970: 123) },
            storageLocatorProvider: { FixedStorageLocator(baseDirectory: tempDirectory) },
            atomicFileWriter: FailingAtomicFileWriter()
        )

        let reported = reporter.report(
            PersistenceFailure.writeFailed,
            mappedError: .transcriptionFailure,
            category: PersonalScribeLogCategory.session,
            detail: "writeFailed",
            context: [:],
            file: "SessionErrorReporterTests.swift",
            function: "testReportStillReturnsPayloadWhenLogWriteFails",
            line: 77
        )

        XCTAssertEqual(reported.mappedError, .transcriptionFailure)
        XCTAssertEqual(reported.detail, "writeFailed")

        try await Task.sleep(for: .milliseconds(50))
        let logURL = tempDirectory
            .appendingPathComponent(ManagedDirectory.logs.pathComponent, isDirectory: true)
            .appendingPathComponent("errors.log")
        XCTAssertFalse(FileManager.default.fileExists(atPath: logURL.path))
    }

    func testUserMessageStaysUnderResponseCardCap() throws {
        // The response card renders the user message in a single row.
        // Pin every PersonalScribeError case to the cap so a future
        // copy edit that lengthens errorDescription / recoverySuggestion
        // doesn't silently overflow the card.
        let tempDirectory = try makeTemporaryDirectory()
        let reporter = SessionErrorReporter(
            logger: PersonalScribeLogger(category: PersonalScribeLogCategory.session),
            now: { Date(timeIntervalSince1970: 0) },
            storageLocatorProvider: { FixedStorageLocator(baseDirectory: tempDirectory) },
            atomicFileWriter: FailingAtomicFileWriter()
        )

        let cases: [PersonalScribeError] = [
            .micPermissionDenied,
            .audioEngineFailure,
            .resampleFailure,
            .modelLoadFailure,
            .transcriptionFailure,
            .cancelled,
            .invalidState,
            .invalidActiveMode,
        ]

        for error in cases {
            let reported = reporter.report(
                error,
                mappedError: error,
                category: PersonalScribeLogCategory.session,
                detail: String(describing: error)
            )
            XCTAssertLessThanOrEqual(
                reported.userMessage.count,
                SessionErrorReporter.userMessageMaxLength,
                "userMessage for \(error) exceeded the response-card cap: \"\(reported.userMessage)\" (\(reported.userMessage.count) chars)"
            )
            XCTAssertFalse(
                reported.userMessage.isEmpty,
                "userMessage for \(error) was empty"
            )
        }
    }

    private func makeTemporaryDirectory() throws -> URL {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory
    }

    private func waitForLogContents(at url: URL) async throws -> String {
        for _ in 0..<100 {
            if let contents = try? String(contentsOf: url, encoding: .utf8) {
                return contents
            }
            try await Task.sleep(for: .milliseconds(10))
        }

        XCTFail("Timed out waiting for error log at \(url.path)")
        return ""
    }
}

private enum PersistenceFailure: Error {
    case writeFailed
}

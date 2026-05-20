import XCTest
@testable import PersonalScribeCore

final class DiagnosticsReporterTests: XCTestCase {
    func testErrorEmissionReturnsReportedPayloadAndWritesStructuredLogEntry() async throws {
        let tempDirectory = try makeTemporaryDirectory()
        let fixedDate = Date(timeIntervalSince1970: 1_777_777_777.123)
        let sink = InMemoryTestSink()
        let reporter = DiagnosticsReporter(
            sinks: [
                sink,
                ErrorFileDiagnosticsSink(
                    storageLocatorProvider: { FixedStorageLocator(baseDirectory: tempDirectory) },
                    atomicFileWriter: FileManagerAtomicFileWriter(fileManager: .default)
                ),
            ],
            now: { fixedDate }
        )

        let event = reporter.error(
            "Session pipeline failed",
            error: PersistenceFailure.writeFailed,
            category: PersonalScribeLogCategory.session,
            metadata: [
                "mappedError": String(describing: PersonalScribeError.transcriptionFailure),
                "detail": "writeFailed",
                "stage": PipelineStepID.persistence.rawValue,
                "mode": "meeting",
            ],
            userFacing: .sessionError(mapped: .transcriptionFailure),
            file: "DiagnosticsReporterTests.swift",
            function: "testErrorEmissionReturnsReportedPayloadAndWritesStructuredLogEntry",
            line: 42
        )

        let reported = try XCTUnwrap(ReportedError(event: event))
        XCTAssertEqual(reported.mappedError, .transcriptionFailure)
        XCTAssertEqual(
            reported.userMessage,
            "Transcription failed. Try transcribing the recording again."
        )
        XCTAssertEqual(reported.detail, "writeFailed")
        XCTAssertEqual(reported.timestamp, fixedDate)
        XCTAssertEqual(reported.category, PersonalScribeLogCategory.session)
        XCTAssertEqual(reported.context["stage"], PipelineStepID.persistence.rawValue)

        let recordedEvents = await waitForEvents(in: sink)
        XCTAssertEqual(recordedEvents.count, 1)

        let logURL = tempDirectory
            .appendingPathComponent(ManagedDirectory.logs.pathComponent, isDirectory: true)
            .appendingPathComponent("errors.log")
        let contents = try await waitForLogContents(at: logURL)

        XCTAssertTrue(contents.contains("2026-05-03T03:09:37.123Z"))
        XCTAssertTrue(contents.contains("level=\"error\"") || contents.contains("level=error"))
        XCTAssertTrue(contents.contains("category=\"session\""))
        XCTAssertTrue(contents.contains("mappedError=\"transcriptionFailure\""))
        XCTAssertTrue(contents.contains("detail=\"writeFailed\""))
        XCTAssertTrue(contents.contains("stage=\"persistence\""))
        XCTAssertTrue(contents.contains("mode=\"meeting\""))
        XCTAssertTrue(contents.contains("file=\"DiagnosticsReporterTests.swift\""))
        XCTAssertTrue(contents.contains("function=\"testErrorEmissionReturnsReportedPayloadAndWritesStructuredLogEntry\""))
        XCTAssertTrue(contents.contains("line=42"))
    }

    func testErrorEmissionStillReturnsPayloadWhenLogWriteFails() async throws {
        let tempDirectory = try makeTemporaryDirectory()
        let reporter = DiagnosticsReporter(
            sinks: [
                ErrorFileDiagnosticsSink(
                    storageLocatorProvider: { FixedStorageLocator(baseDirectory: tempDirectory) },
                    atomicFileWriter: FailingAtomicFileWriter()
                ),
            ],
            now: { Date(timeIntervalSince1970: 123) }
        )

        let event = reporter.error(
            "Session pipeline failed",
            error: PersistenceFailure.writeFailed,
            category: PersonalScribeLogCategory.session,
            metadata: [
                "mappedError": String(describing: PersonalScribeError.transcriptionFailure),
                "detail": "writeFailed",
            ],
            userFacing: .sessionError(mapped: .transcriptionFailure)
        )

        let reported = try XCTUnwrap(ReportedError(event: event))
        XCTAssertEqual(reported.mappedError, .transcriptionFailure)
        XCTAssertEqual(reported.detail, "writeFailed")

        try await Task.sleep(for: .milliseconds(50))
        let logURL = tempDirectory
            .appendingPathComponent(ManagedDirectory.logs.pathComponent, isDirectory: true)
            .appendingPathComponent("errors.log")
        XCTAssertFalse(FileManager.default.fileExists(atPath: logURL.path))
    }

    func testEmissionsReachOverlayStoreInEmissionOrderWhenEarlierDeliverySuspends() async {
        let store = DiagnosticsStore(capacity: 5)
        let reporter = DiagnosticsReporter(
            sinks: [
                DelayedStoreDiagnosticsSink(
                    store: store,
                    delays: ["first": .milliseconds(50)]
                ),
            ],
            now: { Date(timeIntervalSince1970: 123) }
        )

        reporter.error("first", category: PersonalScribeLogCategory.ui)
        reporter.error("second", category: PersonalScribeLogCategory.ui)

        let bufferedEvents = await waitForEvents(in: store, expectedCount: 2)
        XCTAssertEqual(bufferedEvents.map(\.message), ["second", "first"])
    }

    func testUserMessageStaysUnderResponseCardCap() throws {
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
            let event = DiagnosticsEvent(
                level: .error,
                category: PersonalScribeLogCategory.session,
                message: "Session pipeline failed",
                timestamp: .init(timeIntervalSince1970: 0),
                underlyingError: nil,
                metadata: ["detail": String(describing: error)],
                userFacing: .sessionError(mapped: error),
                sourceLocation: DiagnosticsSourceLocation(
                    file: "DiagnosticsReporterTests.swift",
                    function: #function,
                    line: #line
                )
            )
            let reported = try XCTUnwrap(ReportedError(event: event))
            XCTAssertLessThanOrEqual(
                reported.userMessage.count,
                ReportedError.userMessageMaxLength,
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

    private func waitForEvents(in sink: InMemoryTestSink) async -> [RedactedDiagnosticsEvent] {
        for _ in 0..<100 {
            let events = await sink.snapshot()
            if events.isEmpty == false {
                return events
            }
            try? await Task.sleep(for: .milliseconds(10))
        }

        XCTFail("Timed out waiting for diagnostics event")
        return []
    }

    private func waitForEvents(
        in store: DiagnosticsStore,
        expectedCount: Int
    ) async -> [RedactedDiagnosticsEvent] {
        for _ in 0..<100 {
            let events = await store.snapshot()
            if events.count >= expectedCount {
                return events
            }
            try? await Task.sleep(for: .milliseconds(10))
        }

        XCTFail("Timed out waiting for buffered diagnostics events")
        return []
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

private struct DelayedStoreDiagnosticsSink: DiagnosticsSink {
    let store: DiagnosticsStore
    let delays: [String: Duration]

    func record(_ event: RedactedDiagnosticsEvent) async {
        if let delay = delays[event.message] {
            try? await Task.sleep(for: delay)
        }

        await store.append(event)
    }
}

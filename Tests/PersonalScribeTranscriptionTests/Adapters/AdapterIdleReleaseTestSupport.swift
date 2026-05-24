import Foundation
import XCTest
@testable import PersonalScribeCore

func makeTranscriptionLogger(sink: InMemoryTestSink) -> PersonalScribeLogger {
    PersonalScribeLogger(
        category: PersonalScribeLogCategory.transcription,
        reporter: DiagnosticsReporter(
            sinks: [sink],
            now: { Date(timeIntervalSince1970: 0) }
        )
    )
}

func waitForTranscriptionLogMessage(
    in sink: InMemoryTestSink,
    containing fragment: String,
    timeout: Duration = .seconds(2),
    file: StaticString = #filePath,
    line: UInt = #line
) async throws -> RedactedDiagnosticsEvent {
    let clock = ContinuousClock()
    let deadline = clock.now.advanced(by: timeout)
    while clock.now < deadline {
        if let message = await sink.snapshot().first(where: { $0.message.contains(fragment) }) {
            return message
        }
        try await Task.sleep(for: .milliseconds(10))
    }

    XCTFail(
        "Timed out waiting for diagnostics message containing '\(fragment)'",
        file: file,
        line: line
    )
    let fallback = await sink.snapshot().first(where: { $0.message.contains(fragment) })
    return try XCTUnwrap(fallback, file: file, line: line)
}

import XCTest
import PersonalScribeCore
@testable import PersonalScribeTranscription

final class PrepareIdempotenceTests: PersonalScribeTranscriptionFilesystemTestCase {
    func testPrepareIsNoOpAfterSuccessfulFirstLoad() async throws {
        let inference = StubInferenceClient()
        let transcriber = FluidAudioTranscriber(inference: inference)

        try await transcriber.prepare()
        try await transcriber.prepare()

        let loadCount = await inference.loadCallCount
        XCTAssertEqual(loadCount, 1)
    }

    func testConcurrentPrepareCallsShareOneTask() async throws {
        let inference = StubInferenceClient()
        let transcriber = FluidAudioTranscriber(inference: inference)

        async let first: Void = transcriber.prepare()
        async let second: Void = transcriber.prepare()
        _ = try await (first, second)

        let loadCount = await inference.loadCallCount
        XCTAssertEqual(loadCount, 1)
    }
}

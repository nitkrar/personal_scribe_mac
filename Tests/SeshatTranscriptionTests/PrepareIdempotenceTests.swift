import XCTest
import SeshatCore
@testable import SeshatTranscription

final class PrepareIdempotenceTests: SeshatTranscriptionFilesystemTestCase {
    func testPrepareIsNoOpAfterSuccessfulFirstLoad() async throws {
        let downloader = StubModelDownloader()
        let inference = StubInferenceClient()
        let transcriber = FluidAudioTranscriber(
            downloader: downloader,
            inference: inference
        )

        try await transcriber.prepare()
        try await transcriber.prepare()

        XCTAssertEqual(await downloader.ensureCallCount, 1)
        XCTAssertEqual(await inference.loadCallCount, 1)
    }

    func testConcurrentPrepareCallsShareOneTask() async throws {
        let downloader = StubModelDownloader()
        let inference = StubInferenceClient()
        let transcriber = FluidAudioTranscriber(
            downloader: downloader,
            inference: inference
        )

        async let first: Void = transcriber.prepare()
        async let second: Void = transcriber.prepare()
        _ = try await (first, second)

        XCTAssertEqual(await downloader.ensureCallCount, 1)
        XCTAssertEqual(await inference.loadCallCount, 1)
    }
}

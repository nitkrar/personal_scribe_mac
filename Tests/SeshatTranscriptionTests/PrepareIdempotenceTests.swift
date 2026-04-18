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

        let ensureCount = await downloader.ensureCallCount
        let loadCount = await inference.loadCallCount
        XCTAssertEqual(ensureCount, 1)
        XCTAssertEqual(loadCount, 1)
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

        let ensureCount = await downloader.ensureCallCount
        let loadCount = await inference.loadCallCount
        XCTAssertEqual(ensureCount, 1)
        XCTAssertEqual(loadCount, 1)
    }
}

import XCTest
import PersonalScribeCore
@testable import PersonalScribeTranscription

final class ModelIntegrityTests: PersonalScribeTranscriptionFilesystemTestCase {
    func testCorruptDownloadRetriesOnceThenSucceeds() async throws {
        let downloader = RetryingStubModelDownloader(firstResult: .corrupt, secondResult: .valid)
        let transcriber = FluidAudioTranscriber(
            downloader: downloader,
            inference: StubInferenceClient()
        )

        try await transcriber.prepare()

        let attempts = await downloader.attemptCount
        XCTAssertEqual(attempts, 2)
    }

    func testCorruptDownloadTwiceThrowsModelDownloadFailure() async {
        let downloader = RetryingStubModelDownloader(firstResult: .corrupt, secondResult: .corrupt)
        let transcriber = FluidAudioTranscriber(
            downloader: downloader,
            inference: StubInferenceClient()
        )

        do {
            try await transcriber.prepare()
            XCTFail("Expected prepare() to throw")
        } catch let error as PersonalScribeError {
            XCTAssertEqual(error, .modelDownloadFailure)
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }
}

import XCTest
import SeshatCore
@testable import SeshatTranscription

final class ModelDownloadFailureTests: SeshatTranscriptionFilesystemTestCase {
    func testPrepareMapsDownloadFailureToSharedError() async {
        let transcriber = FluidAudioTranscriber(
            downloader: StubModelDownloader(error: URLError(.notConnectedToInternet)),
            inference: StubInferenceClient()
        )

        do {
            try await transcriber.prepare()
            XCTFail("Expected prepare() to throw")
        } catch let error as SeshatError {
            XCTAssertEqual(error, .modelDownloadFailure)
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }
}

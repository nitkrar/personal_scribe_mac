import XCTest
import PersonalScribeCore
@testable import PersonalScribeTranscription

final class ModelDownloadFailureTests: PersonalScribeTranscriptionFilesystemTestCase {
    func testPrepareMapsDownloadFailureToSharedError() async {
        let transcriber = FluidAudioTranscriber(
            downloader: StubModelDownloader(error: URLError(.notConnectedToInternet)),
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

    func testPrepareResetsProgressToIdleAfterDownloadFailure() async {
        let transcriber = FluidAudioTranscriber(
            downloader: StubModelDownloader(
                scriptedProgress: [
                    .init(phase: .downloading, fractionCompleted: 0.5, receivedBytes: 50, expectedBytes: 100)
                ],
                error: URLError(.notConnectedToInternet)
            ),
            inference: StubInferenceClient()
        )

        let stream = transcriber.modelDownloadProgress()
        let snapshotsTask = Task<[ModelDownloadProgress], Never> {
            var snapshots: [ModelDownloadProgress] = []
            for await value in stream {
                snapshots.append(value)
                if snapshots.count == 4 { break }
            }
            return snapshots
        }

        do {
            try await transcriber.prepare()
            XCTFail("Expected prepare() to throw")
        } catch {
            // Expected.
        }

        let snapshots = await snapshotsTask.value

        XCTAssertEqual(snapshots.first?.phase, .idle)
        XCTAssertEqual(snapshots.last?.phase, .idle)
        XCTAssertEqual(snapshots.filter { $0.phase == .downloading }.count, 2)
    }
}

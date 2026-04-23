import XCTest
import FluidAudio
import PersonalScribeCore
@testable import PersonalScribeTranscription

final class ModelDownloadFailureTests: PersonalScribeTranscriptionFilesystemTestCase {
    func testPrepareResetsProgressToIdleAfterLoadFailure() async {
        let transcriber = FluidAudioTranscriber(
            inference: StubInferenceClient(
                loadError: URLError(.notConnectedToInternet),
                scriptedLoadProgress: [
                    .init(fractionCompleted: 0.5, phase: .downloading(completedFiles: 2, totalFiles: 4)),
                ]
            )
        )

        let stream = transcriber.modelDownloadProgress()
        let snapshotsTask = Task<[ModelDownloadProgress], Never> {
            var snapshots: [ModelDownloadProgress] = []
            for await value in stream {
                snapshots.append(value)
                if snapshots.count > 1, snapshots.last?.phase == .idle { break }
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
        XCTAssertTrue(snapshots.contains(where: { $0.phase == .downloading }))
    }
}

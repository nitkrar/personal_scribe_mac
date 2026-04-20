import XCTest
import FluidAudio
import PersonalScribeCore
@testable import PersonalScribeTranscription

final class ModelDownloadProgressTests: PersonalScribeTranscriptionFilesystemTestCase {
    func testPrepareEmitsIdleDownloadingLoadingFinishedExactlyOnce() async throws {
        let inference = StubInferenceClient(
            scriptedLoadProgress: [
                .init(fractionCompleted: 0.25, phase: .downloading(completedFiles: 1, totalFiles: 4)),
                .init(fractionCompleted: 0.75, phase: .downloading(completedFiles: 3, totalFiles: 4)),
                .init(fractionCompleted: 1.0, phase: .downloading(completedFiles: 4, totalFiles: 4)),
                .init(fractionCompleted: 0.95, phase: .compiling(modelName: "Decoder")),
            ]
        )
        let transcriber = FluidAudioTranscriber(inference: inference)

        let stream = transcriber.modelDownloadProgress()
        let task: Task<[ModelDownloadProgress], Never> = Task {
            var result: [ModelDownloadProgress] = []
            for await value in stream {
                result.append(value)
                if result.count == 6 { break }
            }
            return result
        }

        try await transcriber.prepare()
        let snapshots = await task.value

        XCTAssertEqual(
            snapshots.first,
            .init(phase: .idle, fractionCompleted: 0, receivedBytes: 0, expectedBytes: nil)
        )
        XCTAssertTrue(snapshots.contains(where: { $0.phase == .loading }))
        XCTAssertEqual(snapshots.last?.phase, .finished)
        XCTAssertEqual(snapshots.filter { $0.phase == .finished }.count, 1)
        let downloadingFractions = snapshots
            .filter { $0.phase == .downloading }
            .map(\.fractionCompleted)
        XCTAssertEqual(downloadingFractions, downloadingFractions.sorted())
    }
}

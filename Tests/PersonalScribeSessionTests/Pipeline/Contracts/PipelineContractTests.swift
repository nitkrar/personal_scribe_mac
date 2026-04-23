import XCTest
import PersonalScribeCore
@testable import PersonalScribeSession

final class PipelineContractTests: XCTestCase {
    func testSessionSnapshotCarriesStageOneStateSurface() {
        let progress = TranscriptProgress(
            revision: 2,
            text: "Hello world.",
            isFinal: true,
            sourceStage: .postProcessing
        )
        let result = TranscriptionResult(
            text: "Hello world.",
            segments: [
                .init(text: "hello world", start: .zero, end: .seconds(1)),
            ],
            audioDuration: .seconds(1),
            processingDuration: .milliseconds(200)
        )
        let snapshot = SessionSnapshot(
            sessionState: .transcribing,
            activeStage: .postProcessing,
            transcriptProgress: progress,
            lastCompletedResult: result,
            recordingDuration: .seconds(1)
        )

        XCTAssertEqual(snapshot.sessionState, .transcribing)
        XCTAssertEqual(snapshot.activeStage, .postProcessing)
        XCTAssertEqual(snapshot.transcriptProgress, progress)
        XCTAssertEqual(snapshot.lastCompletedResult, result)
        XCTAssertEqual(snapshot.recordingDuration, .seconds(1))
    }

    func testSessionPipeliningAcceptsTrivialConformer() async throws {
        let expectedSnapshot = SessionSnapshot(
            sessionState: .idle,
            activeStage: nil,
            transcriptProgress: nil,
            lastCompletedResult: nil,
            recordingDuration: nil
        )
        let pipeline = StubPipeline(snapshot: expectedSnapshot)

        await pipeline.toggleCapture()
        try await pipeline.prepareTranscriber()

        let snapshot = await pipeline.snapshot()
        XCTAssertEqual(snapshot, expectedSnapshot)

        let snapshotStream = await pipeline.snapshotStream()
        var snapshotIterator = snapshotStream.makeAsyncIterator()
        let firstSnapshot = await snapshotIterator.next()
        XCTAssertEqual(firstSnapshot, expectedSnapshot)

        let levelStream = await pipeline.audioLevelStream()
        var levelIterator = levelStream.makeAsyncIterator()
        let firstLevel = await levelIterator.next()
        XCTAssertEqual(firstLevel, 0.25)

        let progressStream = await pipeline.modelDownloadProgress()
        var progressIterator = progressStream.makeAsyncIterator()
        let firstProgress = await progressIterator.next()
        XCTAssertEqual(
            firstProgress,
            ModelDownloadProgress(
                phase: .finished,
                fractionCompleted: 1.0,
                receivedBytes: 10,
                expectedBytes: 10
            )
        )
    }
}

private actor StubPipeline: SessionPipelining {
    private let currentSnapshot: SessionSnapshot

    init(snapshot: SessionSnapshot) {
        self.currentSnapshot = snapshot
    }

    func toggleCapture() async {}

    func startHoldCapture() async {}

    func cancelCapture() async {}

    func prepareTranscriber() async throws {}

    func snapshot() -> SessionSnapshot {
        currentSnapshot
    }

    func snapshotStream() -> AsyncStream<SessionSnapshot> {
        let snapshot = currentSnapshot
        return AsyncStream { continuation in
            continuation.yield(snapshot)
            continuation.finish()
        }
    }

    func audioLevelStream() -> AsyncStream<Float> {
        AsyncStream { continuation in
            continuation.yield(0.25)
            continuation.finish()
        }
    }

    nonisolated func modelDownloadProgress() -> AsyncStream<ModelDownloadProgress> {
        AsyncStream { continuation in
            continuation.yield(
                ModelDownloadProgress(
                    phase: .finished,
                    fractionCompleted: 1.0,
                    receivedBytes: 10,
                    expectedBytes: 10
                )
            )
            continuation.finish()
        }
    }
}

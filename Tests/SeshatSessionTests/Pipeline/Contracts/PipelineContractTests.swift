import XCTest
import SeshatCore
@testable import SeshatSession

final class PipelineContractTests: XCTestCase {
    func testPipelineSnapshotCarriesStageOneStateSurface() {
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
        let context = PipelineContextSnapshot(
            activeMode: ModeDescriptor(
                id: "dictation-plus",
                name: "Dictation Plus",
                voiceModelID: "voice.default",
                aiModelID: "gpt-5.4",
                systemPrompt: "Polish the final transcript."
            ),
            activeAIModelID: "gpt-5.4",
            systemPrompt: "Polish the final transcript.",
            streamingOutputEnabled: true
        )

        let snapshot = PipelineSnapshot(
            sessionState: .transcribing,
            activeStage: .postProcessing,
            transcriptProgress: progress,
            lastCompletedResult: result,
            recordingDuration: .seconds(1),
            context: context
        )

        XCTAssertEqual(snapshot.sessionState, .transcribing)
        XCTAssertEqual(snapshot.activeStage, .postProcessing)
        XCTAssertEqual(snapshot.transcriptProgress, progress)
        XCTAssertEqual(snapshot.lastCompletedResult, result)
        XCTAssertEqual(snapshot.recordingDuration, .seconds(1))
        XCTAssertEqual(snapshot.context, context)
    }

    func testSessionPipeliningAcceptsTrivialConformer() async throws {
        let expectedSnapshot = PipelineSnapshot(
            sessionState: .idle,
            activeStage: nil,
            transcriptProgress: nil,
            lastCompletedResult: nil,
            recordingDuration: nil,
            context: PipelineContextSnapshot(streamingOutputEnabled: false)
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
    private let currentSnapshot: PipelineSnapshot

    init(snapshot: PipelineSnapshot) {
        self.currentSnapshot = snapshot
    }

    func toggleCapture() async {}

    func prepareTranscriber() async throws {}

    func snapshot() -> PipelineSnapshot {
        currentSnapshot
    }

    func snapshotStream() -> AsyncStream<PipelineSnapshot> {
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

import XCTest
@testable import PersonalScribeCore
@testable import PersonalScribeSession

final class DiarizedTurnTranscriptionProcessorTests: XCTestCase {
    func testProcessDropsInterTurnGapsWithoutCallingASR() async throws {
        let firstTurn = makeTurn(speakerID: "speaker_0", startMS: 0, endMS: 200)
        let secondTurn = makeTurn(speakerID: "speaker_1", startMS: 500, endMS: 700)
        let diarizer = StubSpeakerDiarizer(events: [.terminal([firstTurn, secondTurn])])
        let transcriber = RecordingTranscriber(
            results: [
                makeResult(text: "alpha", startMS: 0, endMS: 200, processingMS: 8),
                makeResult(text: "beta", startMS: 0, endMS: 200, processingMS: 7),
            ]
        )
        let processor: any Processor = DiarizedTurnTranscriptionProcessor(
            diarizer: diarizer,
            transcriber: transcriber
        )

        let output = try await processor.process(audio: try makeBuffer(), priors: [])

        XCTAssertEqual(
            transcriber.recordedSampleBatches(),
            [
                [0, 1, 0, 0, 0, 0, 0, 0, 0, 0],
                [5, 6, 0, 0, 0, 0, 0, 0, 0, 0],
            ]
        )

        switch output {
        case .text(let result):
            XCTAssertEqual(result.text, "Speaker 1: alpha\n\nSpeaker 2: beta")
            XCTAssertEqual(result.audioDuration, .seconds(1))
            XCTAssertEqual(result.processingDuration, .milliseconds(15))
            XCTAssertEqual(
                result.segments,
                [
                    .init(text: "alpha", start: .zero, end: .milliseconds(200)),
                    .init(text: "beta", start: .milliseconds(500), end: .milliseconds(700)),
                ]
            )
        case .streamingText, .turns:
            XCTFail("Expected batch text output")
        }
    }

    func testProcessSlicesOverlapsEndToEndIncludingOverlapZone() async throws {
        let firstTurn = makeTurn(speakerID: "speaker_0", startMS: 0, endMS: 400)
        let secondTurn = makeTurn(speakerID: "speaker_1", startMS: 200, endMS: 600)
        let diarizer = StubSpeakerDiarizer(events: [.terminal([firstTurn, secondTurn])])
        let transcriber = RecordingTranscriber(
            results: [
                makeResult(text: "first", startMS: 0, endMS: 400),
                makeResult(text: "second", startMS: 0, endMS: 400),
            ]
        )
        let processor = DiarizedTurnTranscriptionProcessor(
            diarizer: diarizer,
            transcriber: transcriber
        )

        _ = try await processor.process(audio: try makeBuffer(), priors: [])

        XCTAssertEqual(
            transcriber.recordedSampleBatches(),
            [
                [0, 1, 2, 3, 0, 0, 0, 0, 0, 0],
                [2, 3, 4, 5, 0, 0, 0, 0, 0, 0],
            ]
        )
    }

    func testProcessOnlyTranscribesFinalizedTurns() async throws {
        let provisionalTurn = makeTurn(speakerID: "speaker_0", startMS: 0, endMS: 300)
        let finalizedTurn = makeTurn(speakerID: "speaker_0", startMS: 0, endMS: 400)
        let diarizer = StubSpeakerDiarizer(
            events: [
                .update(provisional: [provisionalTurn], finalized: []),
                .update(provisional: [], finalized: [finalizedTurn]),
                .terminal([finalizedTurn]),
            ]
        )
        let transcriber = RecordingTranscriber(
            results: [makeResult(text: "stable", startMS: 0, endMS: 400)]
        )
        let processor = DiarizedTurnTranscriptionProcessor(
            diarizer: diarizer,
            transcriber: transcriber
        )

        let output = try await processor.process(audio: try makeBuffer(), priors: [])

        XCTAssertEqual(
            transcriber.recordedSampleBatches(),
            [[0, 1, 2, 3, 0, 0, 0, 0, 0, 0]]
        )

        switch output {
        case .text(let result):
            XCTAssertEqual(result.text, "Speaker 1: stable")
        case .streamingText, .turns:
            XCTFail("Expected batch text output")
        }
    }

    func testProcessRepeatsSpeakerLabelForConsecutiveSameSpeakerTurns() async throws {
        let firstTurn = makeTurn(speakerID: "speaker_0", startMS: 0, endMS: 200)
        let secondTurn = makeTurn(speakerID: "speaker_0", startMS: 500, endMS: 700)
        let diarizer = StubSpeakerDiarizer(events: [.terminal([firstTurn, secondTurn])])
        let transcriber = RecordingTranscriber(
            results: [
                makeResult(text: "alpha", startMS: 0, endMS: 200),
                makeResult(text: "beta", startMS: 0, endMS: 200),
            ]
        )
        let processor: any Processor = DiarizedTurnTranscriptionProcessor(
            diarizer: diarizer,
            transcriber: transcriber
        )

        let output = try await processor.process(audio: try makeBuffer(), priors: [])

        switch output {
        case .text(let result):
            XCTAssertEqual(result.text, "Speaker 1: alpha\n\nSpeaker 1: beta")
        case .streamingText, .turns:
            XCTFail("Expected batch text output")
        }
    }

    // Vendor IDs are not guaranteed to start at 0 or be contiguous — the
    // aggregator must assign labels by order of first appearance, not by
    // parsing the vendor string.
    func testProcessAssignsLabelsByOrderOfAppearanceNotVendorID() async throws {
        let firstTurn = makeTurn(speakerID: "speaker_5", startMS: 0, endMS: 200)
        let secondTurn = makeTurn(speakerID: "speaker_2", startMS: 500, endMS: 700)
        let diarizer = StubSpeakerDiarizer(events: [.terminal([firstTurn, secondTurn])])
        let transcriber = RecordingTranscriber(
            results: [
                makeResult(text: "alpha", startMS: 0, endMS: 200),
                makeResult(text: "beta", startMS: 0, endMS: 200),
            ]
        )
        let processor: any Processor = DiarizedTurnTranscriptionProcessor(
            diarizer: diarizer,
            transcriber: transcriber
        )

        let output = try await processor.process(audio: try makeBuffer(), priors: [])

        switch output {
        case .text(let result):
            XCTAssertEqual(result.text, "Speaker 1: alpha\n\nSpeaker 2: beta")
        case .streamingText, .turns:
            XCTFail("Expected batch text output")
        }
    }

    func testPrepareLoadsBothChildrenAndProgressIncludesBothStreams() async throws {
        let diarizerProgress = [
            makeProgress(phase: .downloading, fractionCompleted: 0.25),
            makeProgress(phase: .finished, fractionCompleted: 1),
        ]
        let transcriberProgress = [
            makeProgress(phase: .loading, fractionCompleted: 0.5),
            makeProgress(phase: .finished, fractionCompleted: 1),
        ]
        let diarizer = StubSpeakerDiarizer(
            events: [.terminal([])],
            progressSnapshots: diarizerProgress
        )
        let transcriber = RecordingTranscriber(
            results: [],
            progressSnapshots: transcriberProgress
        )
        let processor: any Processor = DiarizedTurnTranscriptionProcessor(
            diarizer: diarizer,
            transcriber: transcriber
        )
        let lifecycle: any ModelLifecycle = processor

        try await lifecycle.prepare()
        let progress = await collectProgress(from: lifecycle.modelDownloadProgress())

        XCTAssertEqual(diarizer.prepareCallCount(), 1)
        XCTAssertEqual(transcriber.prepareCallCount(), 1)
        XCTAssertEqual(progress.count, 4)
        XCTAssertTrue(progress.contains(diarizerProgress[0]))
        XCTAssertTrue(progress.contains(diarizerProgress[1]))
        XCTAssertTrue(progress.contains(transcriberProgress[0]))
        XCTAssertTrue(progress.contains(transcriberProgress[1]))
    }

    func testProcessRethrowsWhenDiarizerEmitsFailedEvent() async throws {
        // The fusion processor must surface adapter-side failures as a
        // thrown error so the orchestrator can publish a session
        // `.error(...)` snapshot — silent empty transcripts hide real
        // problems (FluidAudio crashes, config validation failures,
        // model corruption) from the user.
        let diarizer = StubSpeakerDiarizer(
            events: [.failed(reason: "synthesised adapter failure")]
        )
        let transcriber = RecordingTranscriber(results: [])
        let processor = DiarizedTurnTranscriptionProcessor(
            diarizer: diarizer,
            transcriber: transcriber
        )

        do {
            _ = try await processor.process(audio: try makeBuffer(), priors: [])
            XCTFail("Expected .failed event to throw")
        } catch let error as PersonalScribeError {
            XCTAssertEqual(error, .transcriptionFailure)
        }
    }

    func testProcessAppliesSensitivityBeforePreparingDiarizer() async throws {
        let turn = makeTurn(speakerID: "speaker_0", startMS: 0, endMS: 200)
        let diarizer = StubSpeakerDiarizer(
            events: [.terminal([turn])],
            requiredSensitivityForPrepare: .strict
        )
        let transcriber = RecordingTranscriber(
            results: [makeResult(text: "alpha", startMS: 0, endMS: 200)]
        )
        let processor = DiarizedTurnTranscriptionProcessor(
            diarizer: diarizer,
            transcriber: transcriber,
            sensitivity: .strict
        )

        _ = try await processor.process(audio: try makeBuffer(), priors: [])

        XCTAssertEqual(
            diarizer.recordedAppliedSensitivities(),
            [SpeakerSeparationSensitivity.strict]
        )
        XCTAssertEqual(diarizer.prepareCallCount(), 1)
    }

    func testProcessPadsShortTurnsBeforePerTurnASRAndClampsReturnedSegments() async throws {
        let shortTurn = makeTurn(speakerID: "speaker_0", startMS: 0, endMS: 600)
        let diarizer = StubSpeakerDiarizer(events: [.terminal([shortTurn])])
        let transcriber = RecordingTranscriber(
            results: [makeResult(text: "alpha", startMS: 0, endMS: 1_000)],
            minimumSampleCountForSuccess: 10
        )
        let processor = DiarizedTurnTranscriptionProcessor(
            diarizer: diarizer,
            transcriber: transcriber
        )

        let output = try await processor.process(audio: try makeBuffer(), priors: [])

        XCTAssertEqual(transcriber.recordedSampleBatches(), [[0, 1, 2, 3, 4, 5, 0, 0, 0, 0]])

        switch output {
        case .text(let result):
            XCTAssertEqual(result.text, "Speaker 1: alpha")
            XCTAssertEqual(
                result.segments,
                [
                    .init(text: "alpha", start: .zero, end: .milliseconds(600)),
                ]
            )
        case .streamingText, .turns:
            XCTFail("Expected batch text output")
        }
    }
}

private extension DiarizedTurnTranscriptionProcessorTests {
    func makeBuffer() throws -> PCMBuffer {
        try PCMBuffer(
            samples: (0..<10).map(Float.init),
            sampleRate: 10,
            channelCount: 1,
            timestamp: ContinuousClock().now
        )
    }

    func makeTurn(
        speakerID: String,
        startMS: Int,
        endMS: Int
    ) -> SpeakerTurn {
        SpeakerTurn(
            speakerID: speakerID,
            start: .milliseconds(startMS),
            end: .milliseconds(endMS)
        )
    }

    func makeResult(
        text: String,
        startMS: Int,
        endMS: Int,
        processingMS: Int = 5
    ) -> TranscriptionResult {
        TranscriptionResult(
            text: text,
            segments: [
                .init(
                    text: text,
                    start: .milliseconds(startMS),
                    end: .milliseconds(endMS)
                ),
            ],
            audioDuration: .milliseconds(endMS - startMS),
            processingDuration: .milliseconds(processingMS)
        )
    }

    func makeProgress(
        phase: ModelDownloadProgress.Phase,
        fractionCompleted: Double
    ) -> ModelDownloadProgress {
        ModelDownloadProgress(
            phase: phase,
            fractionCompleted: fractionCompleted,
            receivedBytes: 0,
            expectedBytes: nil
        )
    }

    func collectProgress(
        from stream: AsyncStream<ModelDownloadProgress>
    ) async -> [ModelDownloadProgress] {
        var progress: [ModelDownloadProgress] = []
        for await snapshot in stream {
            progress.append(snapshot)
        }
        return progress
    }
}

private final class StubSpeakerDiarizer: @unchecked Sendable, SpeakerDiarizer {
    private let events: [SpeakerDiarizationEvent]
    private let progressSnapshots: [ModelDownloadProgress]
    private let requiredSensitivityForPrepare: SpeakerSeparationSensitivity?
    private let lock = NSLock()
    private var prepareCalls = 0
    private var appliedSensitivityHistory: [SpeakerSeparationSensitivity] = []

    init(
        events: [SpeakerDiarizationEvent],
        progressSnapshots: [ModelDownloadProgress] = [],
        requiredSensitivityForPrepare: SpeakerSeparationSensitivity? = nil
    ) {
        self.events = events
        self.progressSnapshots = progressSnapshots
        self.requiredSensitivityForPrepare = requiredSensitivityForPrepare
    }

    func prepare() async throws {
        lock.withLock {
            if let requiredSensitivityForPrepare {
                XCTAssertEqual(
                    appliedSensitivityHistory.last,
                    requiredSensitivityForPrepare,
                    "fusion processor must apply the session sensitivity before diarizer.prepare()"
                )
            }
            prepareCalls += 1
        }
    }

    func applySensitivity(_ sensitivity: SpeakerSeparationSensitivity) async {
        lock.withLock {
            appliedSensitivityHistory.append(sensitivity)
        }
    }

    func modelDownloadProgress() -> AsyncStream<ModelDownloadProgress> {
        let progressSnapshots = self.progressSnapshots
        return AsyncStream { continuation in
            for snapshot in progressSnapshots {
                continuation.yield(snapshot)
            }
            continuation.finish()
        }
    }

    func diarize(
        stream: AsyncThrowingStream<PCMBuffer, Error>
    ) -> AsyncStream<SpeakerDiarizationEvent> {
        let events = self.events
        return AsyncStream { continuation in
            let task = Task {
                do {
                    for try await _ in stream { /* drain */ }
                } catch { /* drain */ }

                for event in events {
                    continuation.yield(event)
                }
                continuation.finish()
            }

            continuation.onTermination = { _ in
                task.cancel()
            }
        }
    }

    func prepareCallCount() -> Int {
        lock.withLock { prepareCalls }
    }

    func recordedAppliedSensitivities() -> [SpeakerSeparationSensitivity] {
        lock.withLock { appliedSensitivityHistory }
    }
}

private final class RecordingTranscriber: @unchecked Sendable, Transcriber {
    let capabilities = TranscriberCapabilities()

    private let progressSnapshots: [ModelDownloadProgress]
    private let minimumSampleCountForSuccess: Int?
    private let lock = NSLock()
    private var queuedResults: [TranscriptionResult]
    private var prepareCalls = 0
    private var sampleBatches: [[Float]] = []

    init(
        results: [TranscriptionResult],
        progressSnapshots: [ModelDownloadProgress] = [],
        minimumSampleCountForSuccess: Int? = nil
    ) {
        self.queuedResults = results
        self.progressSnapshots = progressSnapshots
        self.minimumSampleCountForSuccess = minimumSampleCountForSuccess
    }

    func prepare() async throws {
        lock.withLock {
            prepareCalls += 1
        }
    }

    func modelDownloadProgress() -> AsyncStream<ModelDownloadProgress> {
        let progressSnapshots = self.progressSnapshots
        return AsyncStream { continuation in
            for snapshot in progressSnapshots {
                continuation.yield(snapshot)
            }
            continuation.finish()
        }
    }

    func transcribe(_ audio: PCMBuffer) async throws -> TranscriptionResult {
        try lock.withLock {
            if let minimumSampleCountForSuccess, audio.samples.count < minimumSampleCountForSuccess {
                struct ShortInputError: Error {}
                sampleBatches.append(audio.samples)
                throw ShortInputError()
            }
            sampleBatches.append(audio.samples)
            precondition(!queuedResults.isEmpty, "Expected a pinned transcription result")
            return queuedResults.removeFirst()
        }
    }

    func recordedSampleBatches() -> [[Float]] {
        lock.withLock { sampleBatches }
    }

    func prepareCallCount() -> Int {
        lock.withLock { prepareCalls }
    }
}

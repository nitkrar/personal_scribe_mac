import XCTest
@testable import PersonalScribeCore
import PersonalScribeTestSupport
@testable import PersonalScribeSession

final class SessionPipelineOrchestratorTests: XCTestCase {
    func testSnapshotStreamDeliversInitialIdleSnapshotImmediately() async {
        let context = makeContext(streamingOutputEnabled: false)
        let orchestrator = makeOrchestrator(context: context)

        let stream = await orchestrator.snapshotStream()
        var iterator = stream.makeAsyncIterator()
        let initialSnapshot = await iterator.next()

        XCTAssertEqual(initialSnapshot, SessionSnapshot())
        let liveSnapshot = await orchestrator.snapshot()
        XCTAssertEqual(liveSnapshot, SessionSnapshot())
    }

    func testToggleCapturePublishesStagesProgressAndFinalResult() async throws {
        let buffer = try makeBuffer(sampleCount: 16_000)
        let sink = TestPipelineOutputSink()
        let context = makeContext(streamingOutputEnabled: true)
        let orchestrator = makeOrchestrator(
            capture: FakeAudioCapturer(buffers: [buffer]),
            transcriber: FakeTranscriber(
                result: TranscriptionResult(
                    text: "um hello uh world",
                    segments: [
                        .init(text: "um hello uh world", start: .zero, end: .seconds(1)),
                    ],
                    audioDuration: .seconds(1),
                    processingDuration: .milliseconds(200)
                )
            ),
            outputSink: sink,
            context: context
        )

        let stream = await orchestrator.snapshotStream()
        let observedTask = Task { () -> [SessionSnapshot] in
            var snapshots: [SessionSnapshot] = []
            for await snapshot in stream {
                snapshots.append(snapshot)
                if snapshot.sessionState == .completed && snapshot.lastCompletedResult != nil {
                    break
                }
            }
            return snapshots
        }

        await orchestrator.toggleCapture()
        await orchestrator.toggleCapture()

        let observed = try await withTimeout(.seconds(1)) {
            await observedTask.value
        }
        let uniqueStages = deduplicatedStages(from: observed)
        let progressByRevision = progressSnapshotsByRevision(from: observed)
        let rawProgress = try XCTUnwrap(progressByRevision[1])
        let cleanedProgress = try XCTUnwrap(progressByRevision[2])
        let finalSnapshot = try XCTUnwrap(observed.last)
        let partials = await sink.partialDeliveries()
        let finals = await sink.finalDeliveries()

        XCTAssertEqual(uniqueStages, [.capture, .transcription, .postProcessing, .persistence, .output])

        XCTAssertEqual(
            rawProgress,
            TranscriptProgress(
                revision: 1,
                text: "um hello uh world",
                isFinal: true,
                sourceStage: .transcription
            )
        )
        XCTAssertEqual(
            cleanedProgress,
            TranscriptProgress(
                revision: 2,
                text: "Hello world.",
                isFinal: true,
                sourceStage: .postProcessing
            )
        )
        XCTAssertEqual(finalSnapshot.sessionState, .completed)
        XCTAssertNil(finalSnapshot.activeStage)
        XCTAssertEqual(finalSnapshot.lastCompletedResult?.text, "Hello world.")
        XCTAssertEqual(finalSnapshot.recordingDuration, .seconds(1))
        XCTAssertNil(finalSnapshot.reportedError)
        XCTAssertEqual(partials, [rawProgress, cleanedProgress])
        XCTAssertEqual(
            finals,
            [
                TranscriptionResult(
                    text: "Hello world.",
                    segments: [
                        .init(text: "um hello uh world", start: .zero, end: .seconds(1)),
                    ],
                    audioDuration: .seconds(1),
                    processingDuration: .milliseconds(200)
                ),
            ]
        )
        let sinkResetCount1 = await sink.resetCount()
        XCTAssertEqual(sinkResetCount1, 1)
        let stageFailure1 = await orchestrator.latestStageFailureForTesting()
        XCTAssertNil(stageFailure1)
    }

    func testCaptureFailurePublishesTypedStageFailureAndNextToggleRetries() async throws {
        let sink = TestPipelineOutputSink()
        let orchestrator = makeOrchestrator(
            capture: FakeAudioCapturer(error: .audioEngineFailure),
            transcriber: FakeTranscriber(
                result: TranscriptionResult(
                    text: "retry",
                    audioDuration: .seconds(1),
                    processingDuration: .zero
                )
            ),
            outputSink: sink
        )

        let stream = await orchestrator.snapshotStream()
        let observedTask = Task { () -> [SessionSnapshot] in
            var snapshots: [SessionSnapshot] = []
            for await snapshot in stream.prefix(5) {
                snapshots.append(snapshot)
            }
            return snapshots
        }

        await orchestrator.toggleCapture()
        try await Task.sleep(for: .milliseconds(50))

        let failure = await orchestrator.latestStageFailureForTesting()
        XCTAssertEqual(failure?.stage, .capture)
        XCTAssertEqual(failure?.detail, "audioEngineFailure")
        XCTAssertEqual(failure?.mappedError, .audioEngineFailure)

        await orchestrator.toggleCapture()

        let observed = try await withTimeout(.seconds(1)) {
            await observedTask.value
        }

        XCTAssertEqual(
            observed.map(\.sessionState),
            [.idle, .capturing, .error(.audioEngineFailure), .idle, .capturing]
        )
        XCTAssertEqual(observed.map(\.activeStage), [nil, .capture, .capture, nil, .capture])
        let sinkResetCount2 = await sink.resetCount()
        XCTAssertEqual(sinkResetCount2, 2)
    }

    func testShortRecordingPublishesShortExitWithoutCallingTranscriber() async throws {
        let shortBuffer = try makeBuffer(sampleCount: 8_000)
        let transcriber = CountingTranscriber(
            result: TranscriptionResult(
                text: "should not be called",
                audioDuration: .milliseconds(500),
                processingDuration: .zero
            )
        )
        let orchestrator = makeOrchestrator(
            capture: FakeAudioCapturer(buffers: [shortBuffer]),
            transcriber: transcriber
        )

        let stream = await orchestrator.snapshotStream()
        let observedTask = Task { () -> [SessionSnapshot] in
            var snapshots: [SessionSnapshot] = []
            for await snapshot in stream {
                snapshots.append(snapshot)
                if snapshot.sessionState == .shortExit {
                    break
                }
            }
            return snapshots
        }

        await orchestrator.toggleCapture()
        try await Task.sleep(for: .milliseconds(50))
        await orchestrator.toggleCapture()

        let observed = try await withTimeout(.seconds(1)) {
            await observedTask.value
        }

        // Sub-1s recording exits cleanly via `.shortExit` (non-error
        // terminal) rather than the old `.error(.recordingTooShort)`.
        // See `#075`.
        XCTAssertEqual(
            deduplicatedSessionStates(from: observed),
            [.idle, .capturing, .shortExit]
        )
        let transcribeCount0 = await transcriber.transcribeCallCount()
        XCTAssertEqual(transcribeCount0, 0)
        let stageFailure2 = await orchestrator.latestStageFailureForTesting()
        XCTAssertNil(stageFailure2)
    }

    func testRepeatedToggleDuringTranscribingIsIgnoredAndFinalResultSurvives() async throws {
        let buffer = try makeBuffer(sampleCount: 16_000)
        let sink = TestPipelineOutputSink()
        let orchestrator = makeOrchestrator(
            capture: FakeAudioCapturer(buffers: [buffer]),
            transcriber: FakeTranscriber(
                result: TranscriptionResult(
                    text: "hello",
                    audioDuration: .seconds(1),
                    processingDuration: .milliseconds(200)
                ),
                delay: .milliseconds(200)
            ),
            outputSink: sink,
            context: makeContext(streamingOutputEnabled: true)
        )

        let stream = await orchestrator.snapshotStream()
        let observedTask = Task { () -> [SessionSnapshot] in
            var snapshots: [SessionSnapshot] = []
            for await snapshot in stream {
                snapshots.append(snapshot)
                if snapshot.sessionState == .completed && snapshot.lastCompletedResult != nil {
                    break
                }
            }
            return snapshots
        }
        let toggles = Task {
            await orchestrator.toggleCapture()
            await orchestrator.toggleCapture()
        }

        try await Task.sleep(for: .milliseconds(50))
        await orchestrator.toggleCapture()

        await toggles.value
        let observed = try await withTimeout(.seconds(1)) {
            await observedTask.value
        }
        let finals = await sink.finalDeliveries()

        XCTAssertEqual(observed.last?.sessionState, .completed)
        XCTAssertEqual(observed.last?.lastCompletedResult?.text, "Hello.")
        XCTAssertEqual(finals.count, 1)
    }

    func testSnapshotStreamPublishesRecordingDurationDuringCapture() async throws {
        let buffers = [
            try makeBuffer(sampleCount: 1_600, sampleValue: 0.1),
            try makeBuffer(sampleCount: 1_600, sampleValue: 0.2),
            try makeBuffer(sampleCount: 1_600, sampleValue: 0.3),
        ]
        let orchestrator = makeOrchestrator(
            capture: FakeAudioCapturer(
                buffers: buffers,
                delayPerBuffer: .milliseconds(100)
            )
        )

        let stream = await orchestrator.snapshotStream()
        let observedTask = Task { () -> [SessionSnapshot] in
            var snapshots: [SessionSnapshot] = []
            for await snapshot in stream.prefix(5) {
                snapshots.append(snapshot)
            }
            return snapshots
        }

        await orchestrator.toggleCapture()

        let observed = try await withTimeout(.seconds(1)) {
            await observedTask.value
        }

        await orchestrator.toggleCapture()

        let recordingDurations = observed
            .filter { $0.sessionState == .capturing }
            .compactMap(\.recordingDuration)
        let expectedDurations = [
            Duration.zero,
            buffers[0].duration,
            buffers[0].duration + buffers[1].duration,
            buffers[0].duration + buffers[1].duration + buffers[2].duration,
        ]

        XCTAssertEqual(recordingDurations, expectedDurations)
    }

    func testStartRecordingKicksOffPrepareBeforePublishingRecording() async throws {
        // Regression: before the session-start race fix, startRecording()
        // published `.capturing` and *then* spawned a `.background`-
        // priority detached Task for prepare. If the user stopped
        // recording quickly, the pipeline would transition to
        // `.transcribing` and sit there for minutes because prepare had
        // never been scheduled. This test pins the corrected ordering:
        // prepare begins executing BEFORE the user can observe the
        // `.capturing` snapshot externally.
        let buffer = try makeBuffer(sampleCount: 16_000, sampleValue: 0.1)
        let transcriber = SlowPrepareTranscriber(
            result: TranscriptionResult(
                text: "",
                audioDuration: .seconds(1),
                processingDuration: .milliseconds(1)
            )
        )
        let orchestrator = makeOrchestrator(
            capture: FakeAudioCapturer(buffers: [buffer]),
            transcriber: transcriber
        )

        defer {
            Task {
                await transcriber.releasePrepare()
            }
        }

        await orchestrator.toggleCapture()

        // At `.userInitiated` priority prepare should enter its body
        // within a few ms of being spawned. A 2s window is generous and
        // robust to CI load. Timing out indicates either reorder or
        // priority fix regressed.
        try await withTimeout(.seconds(2)) {
            await transcriber.waitUntilPrepareStarted()
        }

        let snapshot = await orchestrator.snapshot()
        XCTAssertEqual(snapshot.sessionState, .capturing,
                       "startRecording must have published `.capturing` by the time prepare has entered")
    }

    func testStreamingRecipePublishesTranscriptProgressDuringCapture() async throws {
        let buffers = [
            try makeBuffer(sampleCount: 1_600, sampleValue: 0.1),
            try makeBuffer(sampleCount: 1_600, sampleValue: 0.2),
            try makeBuffer(sampleCount: 1_600, sampleValue: 0.3),
        ]
        let streamingTranscriber = ScriptedStreamingTranscriber(
            perBufferEvents: [
                [.partial(text: "hello")],
                [.partial(text: "hello world")],
                [.endOfUtterance(text: "hello world again")],
            ],
            terminalResult: TranscriptionResult(
                text: "hello world again",
                audioDuration: .milliseconds(300),
                processingDuration: .milliseconds(40)
            )
        )
        let orchestrator = makeOrchestrator(
            capture: FakeAudioCapturer(
                buffers: buffers,
                delayPerBuffer: .milliseconds(50)
            ),
            boundRecipe: makeStreamingRecipe(
                streamingTranscriber: streamingTranscriber,
                streamingBehavior: BoundStreamingBehavior(
                    liveCardEnabled: true,
                    liveCursorEnabled: false,
                    secondPassEnabled: false
                )
            )
        )

        let stream = await orchestrator.snapshotStream()
        let observedTask = Task { () -> [SessionSnapshot] in
            var snapshots: [SessionSnapshot] = []
            for await snapshot in stream {
                snapshots.append(snapshot)
                if snapshot.sessionState == .capturing,
                   snapshot.transcriptProgress?.text == "hello world again" {
                    break
                }
            }
            return snapshots
        }

        await orchestrator.toggleCapture()
        let observed = try await withTimeout(.seconds(2)) {
            await observedTask.value
        }

        XCTAssertTrue(
            observed.contains {
                $0.sessionState == .capturing &&
                $0.transcriptProgress?.text == "hello"
            }
        )
        XCTAssertTrue(
            observed.contains {
                $0.sessionState == .capturing &&
                $0.transcriptProgress?.text == "hello world"
            }
        )
        XCTAssertTrue(
            observed.contains {
                $0.sessionState == .capturing &&
                $0.transcriptProgress?.text == "hello world again"
            }
        )

        await orchestrator.toggleCapture()
    }

    func testStreamingLiveCardDisabledSuppressesCaptureTimeTranscriptPublication() async throws {
        let buffers = [
            try makeBuffer(sampleCount: 1_600),
            try makeBuffer(sampleCount: 1_600),
        ]
        let streamingTranscriber = ScriptedStreamingTranscriber(
            perBufferEvents: [
                [.partial(text: "hidden")],
                [.endOfUtterance(text: "hidden transcript")],
            ],
            terminalResult: TranscriptionResult(
                text: "hidden transcript",
                audioDuration: .milliseconds(200),
                processingDuration: .milliseconds(10)
            )
        )
        let orchestrator = makeOrchestrator(
            capture: FakeAudioCapturer(
                buffers: buffers,
                delayPerBuffer: .milliseconds(40)
            ),
            boundRecipe: makeStreamingRecipe(
                streamingTranscriber: streamingTranscriber,
                streamingBehavior: BoundStreamingBehavior(
                    liveCardEnabled: false,
                    liveCursorEnabled: false,
                    secondPassEnabled: false
                )
            )
        )

        let stream = await orchestrator.snapshotStream()
        let observedTask = Task { () -> [SessionSnapshot] in
            var snapshots: [SessionSnapshot] = []
            for await snapshot in stream {
                snapshots.append(snapshot)
                if snapshot.sessionState == .completed,
                   snapshot.lastCompletedResult != nil {
                    break
                }
            }
            return snapshots
        }

        await orchestrator.toggleCapture()
        try await Task.sleep(for: .milliseconds(120))
        await orchestrator.toggleCapture()

        let observed = try await withTimeout(.seconds(2)) {
            await observedTask.value
        }

        XCTAssertFalse(
            observed.contains {
                ($0.sessionState == .capturing || $0.sessionState == .holdRecording) &&
                $0.transcriptProgress != nil
            }
        )
        XCTAssertEqual(observed.last?.lastCompletedResult?.text, "Hidden transcript.")
    }

    func testStreamingMissingFinalizedFallsBackToAccumulatorTerminalText() async throws {
        let buffers = [
            try makeBuffer(sampleCount: 1_600),
            try makeBuffer(sampleCount: 1_600),
        ]
        let streamingTranscriber = ScriptedStreamingTranscriber(
            perBufferEvents: [
                [.partial(text: "hello")],
                [.endOfUtterance(text: "hello world")],
            ],
            terminalResult: nil
        )
        let orchestrator = makeOrchestrator(
            capture: FakeAudioCapturer(buffers: buffers),
            boundRecipe: makeStreamingRecipe(
                streamingTranscriber: streamingTranscriber,
                streamingBehavior: BoundStreamingBehavior(
                    liveCardEnabled: true,
                    liveCursorEnabled: false,
                    secondPassEnabled: false
                )
            )
        )

        await orchestrator.toggleCapture()
        await orchestrator.toggleCapture()
        try await withTimeout(.seconds(2)) {
            while await orchestrator.snapshot().lastCompletedResult == nil {
                try? await Task.sleep(for: .milliseconds(10))
            }
        }

        let snapshot = await orchestrator.snapshot()
        XCTAssertEqual(snapshot.lastCompletedResult?.text, "Hello world.")
    }

    func testStreamingSecondPassBecomesAuthoritativeWhenAvailable() async throws {
        let buffers = [
            try makeBuffer(sampleCount: 1_600),
            try makeBuffer(sampleCount: 1_600),
        ]
        let streamingTranscriber = ScriptedStreamingTranscriber(
            perBufferEvents: [
                [.partial(text: "streaming")],
                [.endOfUtterance(text: "streaming final")],
            ],
            terminalResult: TranscriptionResult(
                text: "streaming final",
                audioDuration: .milliseconds(200),
                processingDuration: .milliseconds(10)
            )
        )
        let orchestrator = makeOrchestrator(
            capture: FakeAudioCapturer(buffers: buffers),
            boundRecipe: makeStreamingRecipe(
                streamingTranscriber: streamingTranscriber,
                streamingBehavior: BoundStreamingBehavior(
                    liveCardEnabled: true,
                    liveCursorEnabled: false,
                    secondPassEnabled: true
                ),
                secondPassTranscriber: ReturningTranscriber(
                    result: TranscriptionResult(
                        text: "authoritative final",
                        audioDuration: .milliseconds(200),
                        processingDuration: .milliseconds(15)
                    )
                )
            )
        )

        await orchestrator.toggleCapture()
        await orchestrator.toggleCapture()
        try await withTimeout(.seconds(2)) {
            while await orchestrator.snapshot().lastCompletedResult == nil {
                try? await Task.sleep(for: .milliseconds(10))
            }
        }

        let snapshot = await orchestrator.snapshot()
        XCTAssertEqual(snapshot.lastCompletedResult?.text, "Authoritative final.")
    }

    func testStreamingSecondPassBlankResultFallsBackToStreamingFinal() async throws {
        let buffers = [
            try makeBuffer(sampleCount: 1_600),
            try makeBuffer(sampleCount: 1_600),
        ]
        let streamingTranscriber = ScriptedStreamingTranscriber(
            perBufferEvents: [
                [.partial(text: "streaming")],
                [.endOfUtterance(text: "streaming final")],
            ],
            terminalResult: TranscriptionResult(
                text: "streaming final",
                audioDuration: .milliseconds(200),
                processingDuration: .milliseconds(10)
            )
        )
        let orchestrator = makeOrchestrator(
            capture: FakeAudioCapturer(buffers: buffers),
            boundRecipe: makeStreamingRecipe(
                streamingTranscriber: streamingTranscriber,
                streamingBehavior: BoundStreamingBehavior(
                    liveCardEnabled: true,
                    liveCursorEnabled: false,
                    secondPassEnabled: true
                ),
                secondPassTranscriber: ReturningTranscriber(
                    result: TranscriptionResult(
                        text: "   ",
                        audioDuration: .milliseconds(200),
                        processingDuration: .milliseconds(15)
                    )
                )
            )
        )

        await orchestrator.toggleCapture()
        await orchestrator.toggleCapture()
        try await withTimeout(.seconds(2)) {
            while await orchestrator.snapshot().lastCompletedResult == nil {
                try? await Task.sleep(for: .milliseconds(10))
            }
        }

        let snapshot = await orchestrator.snapshot()
        XCTAssertEqual(snapshot.lastCompletedResult?.text, "Streaming final.")
    }

    func testStreamingLiveCursorDeliversEachEouChunkToOutputSink() async throws {
        let buffers = [
            try makeBuffer(sampleCount: 1_600, sampleValue: 0.1),
            try makeBuffer(sampleCount: 1_600, sampleValue: 0.2),
        ]
        let streamingTranscriber = ScriptedStreamingTranscriber(
            perBufferEvents: [
                [.partial(text: "hello"), .endOfUtterance(text: "hello")],
                [.partial(text: "world"), .endOfUtterance(text: "world")],
            ],
            terminalResult: TranscriptionResult(
                text: "hello world",
                audioDuration: .milliseconds(200),
                processingDuration: .milliseconds(20)
            )
        )
        let sink = TestPipelineOutputSink()
        let orchestrator = makeOrchestrator(
            capture: FakeAudioCapturer(
                buffers: buffers,
                delayPerBuffer: .milliseconds(40)
            ),
            outputSink: sink,
            boundRecipe: makeStreamingRecipe(
                streamingTranscriber: streamingTranscriber,
                streamingBehavior: BoundStreamingBehavior(
                    liveCardEnabled: false,
                    liveCursorEnabled: true,
                    secondPassEnabled: false
                )
            )
        )

        await orchestrator.toggleCapture()
        try await Task.sleep(for: .milliseconds(150))
        await orchestrator.toggleCapture()

        try await withTimeout(.seconds(2)) {
            while await orchestrator.snapshot().lastCompletedResult == nil {
                try? await Task.sleep(for: .milliseconds(10))
            }
        }

        let partials = await sink.partialDeliveries()
        let chunkTexts = partials.map { $0.text }
        XCTAssertTrue(
            chunkTexts.contains("hello"),
            "Expected partials to contain EOU chunk 'hello'; got \(chunkTexts)"
        )
        XCTAssertTrue(
            chunkTexts.contains("world"),
            "Expected partials to contain EOU chunk 'world'; got \(chunkTexts)"
        )
        XCTAssertFalse(
            chunkTexts.contains("hello world"),
            "Expected per-EOU chunks (not cumulative); got \(chunkTexts)"
        )
    }

    func testStreamingLiveCursorDoesNotDeliverWhenDisabled() async throws {
        let buffers = [
            try makeBuffer(sampleCount: 1_600, sampleValue: 0.1),
        ]
        let streamingTranscriber = ScriptedStreamingTranscriber(
            perBufferEvents: [
                [.endOfUtterance(text: "hello")],
            ],
            terminalResult: TranscriptionResult(
                text: "hello",
                audioDuration: .milliseconds(100),
                processingDuration: .milliseconds(10)
            )
        )
        let sink = TestPipelineOutputSink()
        let orchestrator = makeOrchestrator(
            capture: FakeAudioCapturer(
                buffers: buffers,
                delayPerBuffer: .milliseconds(40)
            ),
            outputSink: sink,
            boundRecipe: makeStreamingRecipe(
                streamingTranscriber: streamingTranscriber,
                streamingBehavior: BoundStreamingBehavior(
                    liveCardEnabled: true,
                    liveCursorEnabled: false,
                    secondPassEnabled: false
                )
            )
        )

        await orchestrator.toggleCapture()
        try await Task.sleep(for: .milliseconds(80))
        await orchestrator.toggleCapture()

        try await withTimeout(.seconds(2)) {
            while await orchestrator.snapshot().lastCompletedResult == nil {
                try? await Task.sleep(for: .milliseconds(10))
            }
        }

        let partials = await sink.partialDeliveries()
        XCTAssertTrue(
            partials.isEmpty,
            "Expected no partial deliveries when liveCursorEnabled = false; got \(partials.map { $0.text })"
        )
    }

    func testStreamingLiveCursorIgnoresPartialEvents() async throws {
        let buffers = [
            try makeBuffer(sampleCount: 1_600, sampleValue: 0.1),
        ]
        let streamingTranscriber = ScriptedStreamingTranscriber(
            perBufferEvents: [
                [.partial(text: "hel"), .partial(text: "hello")],
            ],
            terminalResult: TranscriptionResult(
                text: "hello",
                audioDuration: .milliseconds(100),
                processingDuration: .milliseconds(10)
            )
        )
        let sink = TestPipelineOutputSink()
        let orchestrator = makeOrchestrator(
            capture: FakeAudioCapturer(
                buffers: buffers,
                delayPerBuffer: .milliseconds(40)
            ),
            outputSink: sink,
            boundRecipe: makeStreamingRecipe(
                streamingTranscriber: streamingTranscriber,
                streamingBehavior: BoundStreamingBehavior(
                    liveCardEnabled: false,
                    liveCursorEnabled: true,
                    secondPassEnabled: false
                )
            )
        )

        await orchestrator.toggleCapture()
        try await Task.sleep(for: .milliseconds(80))
        await orchestrator.toggleCapture()

        try await withTimeout(.seconds(2)) {
            while await orchestrator.snapshot().lastCompletedResult == nil {
                try? await Task.sleep(for: .milliseconds(10))
            }
        }

        let partials = await sink.partialDeliveries()
        XCTAssertTrue(
            partials.isEmpty,
            "Expected no partial deliveries from .partial events; got \(partials.map { $0.text })"
        )
    }

    func testEndSessionFiresOnSuccessfulCompletion() async throws {
        let buffer = try makeBuffer(sampleCount: 16_000)
        let transcriber = ReturningTranscriber(
            result: TranscriptionResult(
                text: "hello",
                audioDuration: .seconds(1),
                processingDuration: .milliseconds(10)
            )
        )
        let sink = TestPipelineOutputSink()
        let orchestrator = makeOrchestrator(
            capture: FakeAudioCapturer(buffers: [buffer]),
            transcriber: transcriber,
            outputSink: sink
        )

        await orchestrator.toggleCapture()
        await orchestrator.toggleCapture()

        try await withTimeout(.seconds(2)) {
            while await orchestrator.snapshot().lastCompletedResult == nil {
                try? await Task.sleep(for: .milliseconds(10))
            }
        }

        let count = await sink.endSessionCount()
        XCTAssertEqual(count, 1, "Expected endSession to fire exactly once after successful completion; got \(count)")
    }

    func testEndSessionFiresOnShortExit() async throws {
        // Sub-1s buffer in a non-streaming recipe → shortExit path.
        let buffer = try makeBuffer(sampleCount: 1_600)
        let sink = TestPipelineOutputSink()
        let orchestrator = makeOrchestrator(
            capture: FakeAudioCapturer(buffers: [buffer]),
            outputSink: sink
        )

        await orchestrator.toggleCapture()
        await orchestrator.toggleCapture()

        try await withTimeout(.seconds(2)) {
            while await orchestrator.snapshot().sessionState != .shortExit {
                try? await Task.sleep(for: .milliseconds(10))
            }
        }

        let count = await sink.endSessionCount()
        XCTAssertEqual(count, 1, "Expected endSession to fire exactly once after shortExit; got \(count)")
    }

    func testEndSessionFiresOnCancel() async throws {
        let buffer = try makeBuffer(sampleCount: 16_000)
        let sink = TestPipelineOutputSink()
        let orchestrator = makeOrchestrator(
            capture: FakeAudioCapturer(
                buffers: [buffer],
                delayPerBuffer: .milliseconds(50)
            ),
            outputSink: sink
        )

        await orchestrator.toggleCapture()
        try await Task.sleep(for: .milliseconds(20))
        await orchestrator.cancelCapture()

        try await withTimeout(.seconds(2)) {
            while await orchestrator.snapshot().sessionState != .idle {
                try? await Task.sleep(for: .milliseconds(10))
            }
        }

        let count = await sink.endSessionCount()
        XCTAssertEqual(count, 1, "Expected endSession to fire exactly once after cancel; got \(count)")
    }

    func testEndSessionFiresOnError() async throws {
        let buffer = try makeBuffer(sampleCount: 16_000)
        let sink = TestPipelineOutputSink(failurePoint: .final)
        let orchestrator = makeOrchestrator(
            capture: FakeAudioCapturer(buffers: [buffer]),
            outputSink: sink
        )

        await orchestrator.toggleCapture()
        await orchestrator.toggleCapture()

        try await withTimeout(.seconds(2)) {
            while true {
                if case .error = await orchestrator.snapshot().sessionState {
                    return
                }
                try? await Task.sleep(for: .milliseconds(10))
            }
        }

        let count = await sink.endSessionCount()
        XCTAssertEqual(count, 1, "Expected endSession to fire exactly once after error; got \(count)")
    }

    func testStreamingShortCaptureWithoutTranscriptStillShortExits() async throws {
        let buffer = try makeBuffer(sampleCount: 1_600)
        let orchestrator = makeOrchestrator(
            capture: FakeAudioCapturer(buffers: [buffer]),
            boundRecipe: makeStreamingRecipe(
                streamingTranscriber: ScriptedStreamingTranscriber(
                    perBufferEvents: [[]],
                    terminalResult: nil
                ),
                streamingBehavior: BoundStreamingBehavior(
                    liveCardEnabled: true,
                    liveCursorEnabled: false,
                    secondPassEnabled: false
                )
            )
        )

        let stream = await orchestrator.snapshotStream()
        let observedTask = Task { () -> [SessionSnapshot] in
            var snapshots: [SessionSnapshot] = []
            for await snapshot in stream {
                snapshots.append(snapshot)
                switch snapshot.sessionState {
                case .shortExit, .completed, .error:
                    return snapshots
                default:
                    continue
                }
            }
            return snapshots
        }

        await orchestrator.toggleCapture()
        try await Task.sleep(for: .milliseconds(50))
        await orchestrator.toggleCapture()

        let observed = try await withTimeout(.seconds(1)) {
            await observedTask.value
        }

        XCTAssertEqual(
            deduplicatedSessionStates(from: observed),
            [.idle, .capturing, .shortExit]
        )
        XCTAssertNil(observed.last?.lastCompletedResult)
    }

    func testStreamingFailureMidCaptureStillPreservesBufferedAudioForSecondPass() async throws {
        let buffers = [
            try makeBuffer(sampleCount: 8_000, sampleValue: 0.1),
            try makeBuffer(sampleCount: 8_000, sampleValue: 0.2),
        ]
        let secondPassTranscriber = InspectingTranscriber(resultText: "authoritative final")
        let orchestrator = makeOrchestrator(
            capture: FakeAudioCapturer(
                buffers: buffers,
                delayPerBuffer: .milliseconds(40)
            ),
            boundRecipe: makeStreamingRecipe(
                streamingTranscriber: FailingStreamingTranscriber(
                    perBufferEvents: [
                        [.partial(text: "streaming")],
                        [],
                    ],
                    failureAfterBufferCount: 2,
                    error: StreamTestError.streamFailed
                ),
                streamingBehavior: BoundStreamingBehavior(
                    liveCardEnabled: true,
                    liveCursorEnabled: false,
                    secondPassEnabled: true
                ),
                secondPassTranscriber: secondPassTranscriber
            )
        )

        await orchestrator.toggleCapture()
        try await Task.sleep(for: .milliseconds(120))
        await orchestrator.toggleCapture()

        try await withTimeout(.seconds(2)) {
            while await orchestrator.snapshot().lastCompletedResult == nil {
                try? await Task.sleep(for: .milliseconds(10))
            }
        }

        let snapshot = await orchestrator.snapshot()
        XCTAssertEqual(snapshot.lastCompletedResult?.text, "Authoritative final.")
        let sampleCount = await secondPassTranscriber.lastSampleCount()
        XCTAssertEqual(sampleCount, 16_000)
    }

    func testCancelCaptureTerminatesLiveStreamingEventStream() async throws {
        let tracker = StreamTerminationTracker()
        let streamingTranscriber = HangingStreamingTranscriber(
            perBufferEvents: [[.partial(text: "live")]],
            tracker: tracker
        )
        let orchestrator = makeOrchestrator(
            capture: FakeAudioCapturer(
                buffers: [try makeBuffer(sampleCount: 16_000)],
                delayPerBuffer: .milliseconds(30)
            ),
            boundRecipe: makeStreamingRecipe(
                streamingTranscriber: streamingTranscriber,
                streamingBehavior: BoundStreamingBehavior(
                    liveCardEnabled: true,
                    liveCursorEnabled: false,
                    secondPassEnabled: false
                )
            ),
            liveStreamingEventShutdownTimeout: .milliseconds(20)
        )

        await orchestrator.toggleCapture()
        try await withTimeout(.seconds(1)) {
            await tracker.waitUntilStarted()
        }

        await orchestrator.cancelCapture()

        try await withTimeout(.seconds(1)) {
            await tracker.waitUntilTerminated()
        }

        let snapshot = await orchestrator.snapshot()
        XCTAssertEqual(snapshot.sessionState, .idle)
        XCTAssertNil(snapshot.lastCompletedResult)
    }

    func testStopStreamingCompletesWhenEventConsumerHangsAfterInputFinishes() async throws {
        let tracker = StreamTerminationTracker()
        let streamingTranscriber = HangingStreamingTranscriber(
            perBufferEvents: [[.endOfUtterance(text: "hello world")]],
            tracker: tracker
        )
        let orchestrator = makeOrchestrator(
            capture: FakeAudioCapturer(buffers: [try makeBuffer(sampleCount: 16_000)]),
            boundRecipe: makeStreamingRecipe(
                streamingTranscriber: streamingTranscriber,
                streamingBehavior: BoundStreamingBehavior(
                    liveCardEnabled: true,
                    liveCursorEnabled: false,
                    secondPassEnabled: false
                )
            ),
            liveStreamingEventShutdownTimeout: .milliseconds(20)
        )

        await orchestrator.toggleCapture()
        try await withTimeout(.seconds(1)) {
            await tracker.waitUntilStarted()
        }
        try await withTimeout(.seconds(1)) {
            await orchestrator.toggleCapture()
        }

        let snapshot = await orchestrator.snapshot()
        XCTAssertEqual(snapshot.sessionState, .completed)
        XCTAssertEqual(snapshot.lastCompletedResult?.text, "Hello world.")
    }

    func testStopCompletesWhileBackgroundPrepareIsStillRunning() async throws {
        let buffer = try makeBuffer(sampleCount: 16_000, sampleValue: 0.25)
        let transcriber = SlowPrepareTranscriber(
            result: TranscriptionResult(
                text: "hello",
                audioDuration: .seconds(1),
                processingDuration: .milliseconds(50)
            )
        )
        let orchestrator = makeOrchestrator(
            capture: FakeAudioCapturer(buffers: [buffer]),
            transcriber: transcriber
        )

        defer {
            Task {
                await transcriber.releasePrepare()
            }
        }

        await orchestrator.toggleCapture()
        await transcriber.waitUntilPrepareStarted()

        let stopTask = Task {
            await orchestrator.toggleCapture()
        }

        try await withTimeout(.seconds(1)) {
            await stopTask.value
        }

        let snapshot = await orchestrator.snapshot()

        XCTAssertEqual(snapshot.sessionState, .completed)
        XCTAssertEqual(snapshot.lastCompletedResult?.text, "Hello.")
        let transcribeCount1 = await transcriber.transcribeCallCount()
        XCTAssertEqual(transcribeCount1, 1)
    }

    func testAudioLevelStreamRepublishesLevelsDuringRecording() async throws {
        let buffer = try makeBuffer(sampleCount: 16_000)
        let canned: [Float] = [0.15, 0.25, 0.5, 0.75, 0.95]
        let orchestrator = makeOrchestrator(
            capture: FakeAudioCapturer(buffers: [buffer], levels: canned),
            transcriber: FakeTranscriber(
                result: TranscriptionResult(
                    text: "",
                    audioDuration: .seconds(1),
                    processingDuration: .zero
                )
            )
        )

        let levelStream = await orchestrator.audioLevelStream()
        var iterator = levelStream.makeAsyncIterator()

        let firstLevel = await iterator.next()
        XCTAssertEqual(firstLevel, 0.0)

        await orchestrator.toggleCapture()

        var observed: [Float] = []
        let deadline = ContinuousClock.now.advanced(by: .seconds(3))
        while observed.count < canned.count, ContinuousClock.now < deadline {
            guard let level = await iterator.next() else { break }
            observed.append(level)
        }

        await orchestrator.toggleCapture()

        XCTAssertEqual(observed, canned)
    }

    func testMultipleAudioLevelSubscribersEachReceiveEveryLevel() async throws {
        let buffer = try makeBuffer(sampleCount: 16_000)
        let canned: [Float] = [0.1, 0.2, 0.3]
        let orchestrator = makeOrchestrator(
            capture: FakeAudioCapturer(buffers: [buffer], levels: canned),
            transcriber: FakeTranscriber(
                result: TranscriptionResult(
                    text: "",
                    audioDuration: .seconds(1),
                    processingDuration: .zero
                )
            )
        )

        let streamA = await orchestrator.audioLevelStream()
        let streamB = await orchestrator.audioLevelStream()
        var iteratorA = streamA.makeAsyncIterator()
        var iteratorB = streamB.makeAsyncIterator()

        _ = await iteratorA.next()
        _ = await iteratorB.next()

        await orchestrator.toggleCapture()

        var observedA: [Float] = []
        var observedB: [Float] = []
        let deadline = ContinuousClock.now.advanced(by: .seconds(3))
        while (observedA.count < canned.count || observedB.count < canned.count),
              ContinuousClock.now < deadline {
            if observedA.count < canned.count, let next = await iteratorA.next() {
                observedA.append(next)
            }
            if observedB.count < canned.count, let next = await iteratorB.next() {
                observedB.append(next)
            }
        }

        await orchestrator.toggleCapture()

        XCTAssertEqual(observedA, canned)
        XCTAssertEqual(observedB, canned)
    }

    // #078.29 Replace removed `orchestrator.modelDownloadProgress()` —
    // progress now flows via `snapshot.modelDownloadProgress` field
    // populated by the bound recipe's processor. The legacy passthrough
    // assertion this test pinned is no longer meaningful at the
    // orchestrator level. Recipe-driven progress is exercised by
    // `RecipeDrivenOrchestratorTests`.

    func testSuccessfulTranscriptionAppendsEntryToSQLiteStore() async throws {
        let temporaryDirectory = try makeTemporaryDirectory()
        defer {
            try? FileManager.default.removeItem(at: temporaryDirectory)
        }

        let repository = try makeRepository(in: temporaryDirectory)
        let buffer = try makeBuffer(sampleCount: 16_000)
        let orchestrator = makeOrchestrator(
            capture: FakeAudioCapturer(buffers: [buffer]),
            transcriber: FakeTranscriber(
                result: TranscriptionResult(
                    text: "hello",
                    audioDuration: .seconds(1),
                    processingDuration: .milliseconds(200)
                )
            ),
            transcriptRepository: repository
        )

        await orchestrator.toggleCapture()
        await orchestrator.toggleCapture()
        try await waitUntilRepositoryHasEntries(repository, minimum: 1)

        let count = await repository.count()
        let entries = await repository.recent(limit: 10)

        XCTAssertEqual(count, 1)
        XCTAssertEqual(entries.count, 1)
        XCTAssertEqual(entries.first?.text, "Hello.")
        XCTAssertEqual(entries.first?.audioDuration ?? 0, 1.0, accuracy: 0.01)
        XCTAssertEqual(entries.first?.processingDuration ?? 0, 0.2, accuracy: 0.01)
    }

    func testCurrentBoundRecipeStaysSessionFrozenDespiteMidTranscriptionRebind() async throws {
        let buffer = try makeBuffer(sampleCount: 16_000)
        let transcriber = CountingTranscriber(
            result: TranscriptionResult(
                text: "hello",
                audioDuration: .seconds(1),
                processingDuration: .milliseconds(200)
            ),
            delay: .milliseconds(250)
        )
        let reboundTranscriber = CountingTranscriber(
            result: TranscriptionResult(
                text: "should not run",
                audioDuration: .seconds(1),
                processingDuration: .zero
            )
        )
        let persisted = PersistedEntries()
        let sessionRecipe = BoundRecipe(
            recipeID: "notes-session",
            recipeName: "Notes",
            pipelineShape: .batch,
            processors: [.transcriber(transcriber)],
            captureControllers: [.manualHotkey],
            outputSinks: [.frontmostPaste(enabled: true)]
        )
        let reboundRecipe = BoundRecipe(
            recipeID: "meeting-next",
            recipeName: "Meeting",
            pipelineShape: .batch,
            processors: [.transcriber(reboundTranscriber)],
            captureControllers: [.manualHotkey],
            outputSinks: [.frontmostPaste(enabled: true)]
        )
        let orchestrator = SessionPipelineOrchestrator(
            capture: FakeAudioCapturer(buffers: [buffer]),
            logger: PersonalScribeLogger.testing(category: PersonalScribeLogCategory.session),
            postProcessingPipeline: DefaultPostProcessingPipeline(),
            outputSink: TestPipelineOutputSink(),
            contextProvider: StaticPipelineContextProvider(
                context: makeContext(streamingOutputEnabled: false)
            ),
            persistenceHandler: { entry in
                await persisted.append(entry)
            },
            boundRecipe: sessionRecipe
        )

        await orchestrator.toggleCapture()
        await orchestrator.toggleCapture()
        for _ in 0..<100 {
            if await transcriber.transcribeCallCount() >= 1 {
                break
            }
            try await Task.sleep(for: .milliseconds(10))
        }
        let didStartTranscribing = await transcriber.transcribeCallCount() >= 1
        XCTAssertTrue(didStartTranscribing)

        // Rebind the NEXT-session recipe while the current session is
        // still transcribing. Persistence must continue to report the
        // session-start recipe, not this new binding.
        await orchestrator.bindRecipeForNextSession(reboundRecipe)
        let currentRecipe = await orchestrator.currentBoundRecipe()
        XCTAssertEqual(currentRecipe?.recipeID, "notes-session")

        for _ in 0..<100 {
            if await persisted.count() >= 1 {
                break
            }
            try await Task.sleep(for: .milliseconds(10))
        }
        let persistedCount = await persisted.count()
        XCTAssertEqual(persistedCount, 1)

        let capturedEntry = await persisted.first()
        let entry = try XCTUnwrap(capturedEntry)
        XCTAssertEqual(entry.modeId, "notes-session")
        let reboundCalls = await reboundTranscriber.transcribeCallCount()
        XCTAssertEqual(reboundCalls, 0)
    }

    func testPostProcessingFailurePublishesTypedStageFailure() async throws {
        let buffer = try makeBuffer(sampleCount: 16_000)
        let orchestrator = makeOrchestrator(
            capture: FakeAudioCapturer(buffers: [buffer]),
            transcriber: FakeTranscriber(
                result: TranscriptionResult(
                    text: "hello",
                    audioDuration: .seconds(1),
                    processingDuration: .milliseconds(100)
                )
            ),
            postProcessingPipeline: ThrowingPostProcessingPipeline()
        )

        await orchestrator.toggleCapture()
        await orchestrator.toggleCapture()
        try await Task.sleep(for: .milliseconds(50))

        let snapshot = await orchestrator.snapshot()
        let failure = await orchestrator.latestStageFailureForTesting()

        XCTAssertEqual(snapshot.sessionState, .error(.transcriptionFailure))
        XCTAssertEqual(snapshot.activeStage, .postProcessing)
        XCTAssertEqual(snapshot.reportedError?.mappedError, .transcriptionFailure)
        XCTAssertEqual(snapshot.reportedError?.detail, "post-processing-failure")
        XCTAssertEqual(snapshot.reportedError?.category, PersonalScribeLogCategory.session)
        XCTAssertEqual(snapshot.reportedError?.context["stage"], PipelineStepID.postProcessing.rawValue)
        XCTAssertEqual(failure?.stage, .postProcessing)
        XCTAssertEqual(failure?.detail, "post-processing-failure")
        XCTAssertEqual(failure?.mappedError, .transcriptionFailure)
    }

    func testPersistenceFailurePublishesTypedStageFailure() async throws {
        let buffer = try makeBuffer(sampleCount: 16_000)
        let sink = TestPipelineOutputSink()
        let orchestrator = makeOrchestrator(
            capture: FakeAudioCapturer(buffers: [buffer]),
            transcriber: FakeTranscriber(
                result: TranscriptionResult(
                    text: "hello",
                    audioDuration: .seconds(1),
                    processingDuration: .milliseconds(100)
                )
            ),
            outputSink: sink,
            persistenceHandler: { _ in
                throw PersistenceFailure.writeFailed
            }
        )

        await orchestrator.toggleCapture()
        await orchestrator.toggleCapture()
        try await Task.sleep(for: .milliseconds(50))

        let snapshot = await orchestrator.snapshot()
        let failure = await orchestrator.latestStageFailureForTesting()
        let finals = await sink.finalDeliveries()

        XCTAssertEqual(snapshot.sessionState, .error(.transcriptionFailure))
        XCTAssertEqual(snapshot.activeStage, .persistence)
        XCTAssertEqual(failure?.stage, .persistence)
        XCTAssertEqual(failure?.detail, "writeFailed")
        XCTAssertEqual(failure?.mappedError, .transcriptionFailure)
        XCTAssertTrue(finals.isEmpty)
    }

    func testOutputFailurePublishesTypedStageFailure() async throws {
        let buffer = try makeBuffer(sampleCount: 16_000)
        let sink = TestPipelineOutputSink(failurePoint: .final)
        let orchestrator = makeOrchestrator(
            capture: FakeAudioCapturer(buffers: [buffer]),
            transcriber: FakeTranscriber(
                result: TranscriptionResult(
                    text: "hello",
                    audioDuration: .seconds(1),
                    processingDuration: .milliseconds(100)
                )
            ),
            outputSink: sink,
            context: makeContext(streamingOutputEnabled: true)
        )

        await orchestrator.toggleCapture()
        await orchestrator.toggleCapture()
        try await Task.sleep(for: .milliseconds(50))

        let snapshot = await orchestrator.snapshot()
        let failure = await orchestrator.latestStageFailureForTesting()

        XCTAssertEqual(snapshot.sessionState, .error(.transcriptionFailure))
        XCTAssertEqual(snapshot.activeStage, .output)
        XCTAssertEqual(failure?.stage, .output)
        XCTAssertEqual(failure?.detail, "finalDeliveryFailed")
        XCTAssertEqual(failure?.mappedError, .transcriptionFailure)
    }

    // MARK: - #071 — hold-path transitions

    /// Happy path: `startHoldCapture()` publishes `.holdRecording`, and a
    /// subsequent `toggleCapture()` (the stop route used by hold-release)
    /// drives the normal transcribe pipeline.
    func testStartHoldCaptureFromIdlePublishesHoldRecordingThenTranscribesOnStop() async throws {
        let buffer = try makeBuffer(sampleCount: 16_000)
        let orchestrator = makeOrchestrator(
            capture: FakeAudioCapturer(buffers: [buffer]),
            transcriber: FakeTranscriber(
                result: TranscriptionResult(
                    text: "hello from hold",
                    audioDuration: .seconds(1),
                    processingDuration: .milliseconds(10)
                )
            )
        )

        let stream = await orchestrator.snapshotStream()
        let observedTask = Task { () -> [SessionSnapshot] in
            var snapshots: [SessionSnapshot] = []
            for await snapshot in stream {
                snapshots.append(snapshot)
                if snapshot.sessionState == .completed && snapshot.lastCompletedResult != nil {
                    break
                }
            }
            return snapshots
        }

        await orchestrator.startHoldCapture()
        await orchestrator.toggleCapture()

        let observed = try await withTimeout(.seconds(1)) {
            await observedTask.value
        }

        let states = deduplicatedSessionStates(from: observed)
        XCTAssertTrue(states.contains(.holdRecording),
                      "Pipeline must transition through .holdRecording")
        XCTAssertTrue(states.contains(.transcribing),
                      "Pipeline must transition through .transcribing after stop")
        XCTAssertEqual(observed.last?.sessionState, .completed)
        XCTAssertEqual(observed.last?.lastCompletedResult?.text, "Hello from hold.")
    }

    /// Race-fix invariant: `.holdRecording` must be published **before**
    /// `capture.start()` resolves, so a concurrent release routed through
    /// `toggleCapture()` observes `.holdRecording` instead of `.idle`.
    /// Without this ordering, hold-release silently no-ops and the
    /// session wedges (#071 root cause).
    func testStartHoldCapturePublishesHoldRecordingBeforeAwaitingCaptureStart() async throws {
        let capture = HangingStartCapture()
        let orchestrator = makeOrchestrator(capture: capture)

        let stream = await orchestrator.snapshotStream()
        let observerTask = Task { () -> [SessionState] in
            var observed: [SessionState] = []
            for await snapshot in stream {
                observed.append(snapshot.sessionState)
                if snapshot.sessionState == .holdRecording {
                    break
                }
            }
            return observed
        }

        let holdTask = Task { await orchestrator.startHoldCapture() }

        let observed = try await withTimeout(.seconds(1)) {
            await observerTask.value
        }

        XCTAssertTrue(observed.contains(.holdRecording),
                      "startHoldCapture must publish .holdRecording before capture.start() resolves — otherwise a concurrent stop observes .idle and no-ops (see #071)")

        holdTask.cancel()
        await capture.release()
    }

    // MARK: - #002 — true-discard cancel path

    /// `cancelCapture()` from `.capturing` must drop the buffered audio,
    /// skip transcribing, and return to `.idle` — never calling the
    /// transcriber or output sink.
    func testCancelCaptureFromRecordingSkipsTranscribeAndReturnsToIdle() async throws {
        let buffer = try makeBuffer(sampleCount: 16_000)
        let tracker = TranscriberTracker()
        let transcriber = TrackedTranscriber(
            result: TranscriptionResult(
                text: "should not be returned",
                audioDuration: .seconds(1),
                processingDuration: .milliseconds(10)
            ),
            progressEvents: [],
            tracker: tracker
        )
        let sink = TestPipelineOutputSink()
        let orchestrator = makeOrchestrator(
            capture: FakeAudioCapturer(buffers: [buffer]),
            transcriber: transcriber,
            outputSink: sink
        )

        await orchestrator.toggleCapture()

        // Wait for .capturing before cancelling. Without this the cancel
        // could slip in before startRecording's publish lands.
        try await withTimeout(.seconds(1)) {
            while await orchestrator.snapshot().sessionState != .capturing {
                try? await Task.sleep(for: .milliseconds(5))
            }
        }

        await orchestrator.cancelCapture()

        let snapshot = await orchestrator.snapshot()
        XCTAssertEqual(snapshot.sessionState, .idle)
        XCTAssertNil(snapshot.activeStage)
        XCTAssertNil(snapshot.lastCompletedResult,
                     "cancel must NOT produce a completed transcript")
        XCTAssertNil(snapshot.recordingDuration)

        let transcribeCalls = await tracker.transcribeCallCount()
        XCTAssertEqual(transcribeCalls, 0, "transcriber must not be invoked on cancel")

        let partials = await sink.partialDeliveries()
        let finals = await sink.finalDeliveries()
        XCTAssertEqual(partials, [], "no partial output on cancel")
        XCTAssertEqual(finals, [], "no final output on cancel")
    }

    /// Same invariant for the hold path: `cancelCapture()` from
    /// `.holdRecording` drops the buffer and transitions to `.idle`
    /// without transcribing.
    func testCancelCaptureFromHoldRecordingSkipsTranscribeAndReturnsToIdle() async throws {
        let buffer = try makeBuffer(sampleCount: 16_000)
        let tracker = TranscriberTracker()
        let transcriber = TrackedTranscriber(
            result: TranscriptionResult(
                text: "should not be returned",
                audioDuration: .seconds(1),
                processingDuration: .milliseconds(10)
            ),
            progressEvents: [],
            tracker: tracker
        )
        let orchestrator = makeOrchestrator(
            capture: FakeAudioCapturer(buffers: [buffer]),
            transcriber: transcriber
        )

        await orchestrator.startHoldCapture()

        try await withTimeout(.seconds(1)) {
            while await orchestrator.snapshot().sessionState != .holdRecording {
                try? await Task.sleep(for: .milliseconds(5))
            }
        }

        await orchestrator.cancelCapture()

        let snapshot = await orchestrator.snapshot()
        XCTAssertEqual(snapshot.sessionState, .idle)
        XCTAssertNil(snapshot.lastCompletedResult)

        let transcribeCalls = await tracker.transcribeCallCount()
        XCTAssertEqual(transcribeCalls, 0)
    }

    /// Cancel from `.idle` must be a no-op — no state change, no side
    /// effects. Safety-net for Esc keys arriving when nothing is live.
    func testCancelCaptureFromIdleIsNoOp() async throws {
        let orchestrator = makeOrchestrator()

        await orchestrator.cancelCapture()

        let snapshot = await orchestrator.snapshot()
        XCTAssertEqual(snapshot.sessionState, .idle)
    }

    /// Snapshot stream must NEVER observe `.transcribing` on the cancel
    /// path. This pins the "true discard" invariant at the stream level
    /// so downstream observers (`AppStore`, pill, metrics) can rely on
    /// it.
    func testCancelCapturePathNeverPublishesTranscribing() async throws {
        let buffer = try makeBuffer(sampleCount: 16_000)
        let orchestrator = makeOrchestrator(capture: FakeAudioCapturer(buffers: [buffer]))

        let stream = await orchestrator.snapshotStream()
        let observed = Task { () -> [SessionState] in
            var states: [SessionState] = []
            for await snapshot in stream {
                states.append(snapshot.sessionState)
                if snapshot.sessionState == .idle && !states.contains(.capturing) {
                    continue
                }
                if snapshot.sessionState == .idle && states.contains(.capturing) {
                    break
                }
            }
            return states
        }

        await orchestrator.toggleCapture()
        try await withTimeout(.seconds(1)) {
            while await orchestrator.snapshot().sessionState != .capturing {
                try? await Task.sleep(for: .milliseconds(5))
            }
        }
        await orchestrator.cancelCapture()

        let states = try await withTimeout(.seconds(1)) {
            await observed.value
        }

        XCTAssertFalse(
            states.contains(.transcribing),
            "cancel path must never emit .transcribing — saw states: \(states)"
        )
    }

    private func makeOrchestrator(
        capture: any AudioCapturer = FakeAudioCapturer(),
        transcriber: any Transcriber = FakeTranscriber(
            result: TranscriptionResult(
                text: "",
                audioDuration: .seconds(1),
                processingDuration: .zero
            )
        ),
        transcriptRepository: TranscriptRepository? = nil,
        postProcessingPipeline: any PostProcessingPipeline = DefaultPostProcessingPipeline(),
        outputSink: any PipelineOutputSink = TestPipelineOutputSink(),
        context: PipelineContextSnapshot = PipelineContextSnapshot(streamingOutputEnabled: false),
        persistenceHandler: (@Sendable (TranscriptEntry) async throws -> Void)? = nil,
        boundRecipe: BoundRecipe? = nil,
        liveStreamingEventShutdownTimeout: Duration = .seconds(2)
    ) -> SessionPipelineOrchestrator {
        // #078.31b: orchestrator init takes a `BoundRecipe` post-cutover.
        // Wrap the `transcriber:` arg as the asr processor of a built-in
        // batch dictation recipe so existing test names + bodies stay
        // unchanged.
        let resolvedRecipe = boundRecipe ?? BoundRecipe(
            recipeID: "dictation",
            recipeName: "Dictation",
            pipelineShape: .batch,
            processors: [.transcriber(transcriber)],
            captureControllers: [.manualHotkey],
            outputSinks: [.frontmostPaste(enabled: true)]
        )
        let contextProvider = StaticPipelineContextProvider(context: context)
        if let persistenceHandler {
            return SessionPipelineOrchestrator(
                capture: capture,
                logger: PersonalScribeLogger.testing(category: PersonalScribeLogCategory.session),
                postProcessingPipeline: postProcessingPipeline,
                outputSink: outputSink,
                contextProvider: contextProvider,
                persistenceHandler: persistenceHandler,
                boundRecipe: resolvedRecipe,
                liveStreamingEventShutdownTimeout: liveStreamingEventShutdownTimeout
            )
        }

        return SessionPipelineOrchestrator(
            capture: capture,
            transcriptRepository: transcriptRepository,
            logger: PersonalScribeLogger.testing(category: PersonalScribeLogCategory.session),
            postProcessingPipeline: postProcessingPipeline,
            outputSink: outputSink,
            contextProvider: contextProvider,
            boundRecipe: resolvedRecipe,
            liveStreamingEventShutdownTimeout: liveStreamingEventShutdownTimeout
        )
    }

    private func makeStreamingRecipe(
        streamingTranscriber: any StreamingTranscriber,
        streamingBehavior: BoundStreamingBehavior,
        secondPassTranscriber: (any Transcriber)? = nil
    ) -> BoundRecipe {
        BoundRecipe(
            recipeID: "streaming-dictation",
            recipeName: "Streaming Dictation",
            pipelineShape: .streaming,
            processors: [.streamingTranscriber(streamingTranscriber)],
            captureControllers: [.manualHotkey],
            outputSinks: [.frontmostPaste(enabled: true)],
            streamingBehavior: streamingBehavior,
            streamingSecondPassTranscriber: secondPassTranscriber
        )
    }

    private func makeContext(streamingOutputEnabled: Bool) -> PipelineContextSnapshot {
        // #078.31a: activeMode field now carries the new `WorkflowMode`
        // shape. The legacy aiModelID + systemPrompt fields stay as
        // separate snapshot fields (post-processing dispatch hooks).
        return PipelineContextSnapshot(
            activeMode: WorkflowMode.dictation,
            activeAIModelID: "gpt-5.4",
            systemPrompt: "Polish the final transcript.",
            streamingOutputEnabled: streamingOutputEnabled
        )
    }

    private func makeBuffer(
        sampleCount: Int,
        sampleValue: Float = 0
    ) throws -> PCMBuffer {
        try PCMBuffer(
            samples: Array(repeating: sampleValue, count: sampleCount),
            timestamp: ContinuousClock().now
        )
    }

    private func deduplicatedStages(from snapshots: [SessionSnapshot]) -> [PipelineStepID] {
        var stages: [PipelineStepID] = []
        for stage in snapshots.compactMap(\.activeStage) where stages.last != stage {
            stages.append(stage)
        }
        return stages
    }

    private func deduplicatedSessionStates(from snapshots: [SessionSnapshot]) -> [SessionState] {
        var states: [SessionState] = []
        for state in snapshots.map(\.sessionState) where states.last != state {
            states.append(state)
        }
        return states
    }

    private func progressSnapshotsByRevision(
        from snapshots: [SessionSnapshot]
    ) -> [Int: TranscriptProgress] {
        var revisions: [Int: TranscriptProgress] = [:]
        for progress in snapshots.compactMap(\.transcriptProgress) {
            revisions[progress.revision] = progress
        }
        return revisions
    }

    private func makeRepository(in tempDirectory: URL) throws -> TranscriptRepository {
        let recordings = tempDirectory.appendingPathComponent("recordings", isDirectory: true)
        try FileManager.default.createDirectory(at: recordings, withIntermediateDirectories: true)
        let locator = FixedBaseDirectoryStorageLocator(
            baseDirectory: tempDirectory,
            managedDirectoryOverrides: [.recordings: recordings]
        )
        let database = try AppDatabase(locator: locator)
        return TranscriptRepository(
            database: database,
            logger: PersonalScribeLogger.testing(category: PersonalScribeLogCategory.app)
        )
    }

    private func waitUntilRepositoryHasEntries(
        _ repository: TranscriptRepository,
        minimum: Int
    ) async throws {
        for _ in 0..<100 {
            if await repository.count() >= minimum {
                return
            }
            try await Task.sleep(for: .milliseconds(10))
        }

        XCTFail("TranscriptRepository never reached \(minimum) entries")
    }

    private func makeTemporaryDirectory() throws -> URL {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory
    }

    private func withTimeout<T: Sendable>(
        _ duration: Duration,
        operation: @escaping @Sendable () async -> T
    ) async throws -> T {
        try await withThrowingTaskGroup(of: T.self) { group in
            group.addTask {
                await operation()
            }
            group.addTask {
                try await Task.sleep(for: duration)
                throw TimeoutError()
            }

            let value = try await group.next()!
            group.cancelAll()
            return value
        }
    }

    private struct TimeoutError: Error {}
}

private struct StaticPipelineContextProvider: PipelineContextProviding {
    let context: PipelineContextSnapshot

    func currentContext() -> PipelineContextSnapshot {
        context
    }
}

private actor TestPipelineOutputSink: PipelineOutputSink {
    enum FailurePoint: Sendable {
        case final
    }

    private let failurePoint: FailurePoint?
    private var partials: [TranscriptProgress] = []
    private var finals: [TranscriptionResult] = []
    private var resets = 0
    private var endSessions = 0

    init(failurePoint: FailurePoint? = nil) {
        self.failurePoint = failurePoint
    }

    func deliverPartial(_ revision: TranscriptProgress) async throws {
        partials.append(revision)
    }

    func deliverFinal(_ result: TranscriptionResult) async throws {
        if case .final? = failurePoint {
            throw OutputFailure.finalDeliveryFailed
        }
        finals.append(result)
    }

    func resetForNewSession() async {
        resets += 1
        partials.removeAll()
        finals.removeAll()
    }

    func endSession() async {
        endSessions += 1
    }

    func partialDeliveries() -> [TranscriptProgress] {
        partials
    }

    func finalDeliveries() -> [TranscriptionResult] {
        finals
    }

    func resetCount() -> Int {
        resets
    }

    func endSessionCount() -> Int {
        endSessions
    }
}

private struct ThrowingPostProcessingPipeline: PostProcessingPipeline {
    func run(_ text: String, context: PostProcessingContext) async throws -> String {
        throw PostProcessingFailure.postProcessingFailure
    }
}

private enum PostProcessingFailure: Error, CustomStringConvertible, Sendable {
    case postProcessingFailure

    var description: String {
        "post-processing-failure"
    }
}

private enum PersistenceFailure: Error, CustomStringConvertible, Sendable {
    case writeFailed

    var description: String {
        "writeFailed"
    }
}

private enum OutputFailure: Error, CustomStringConvertible, Sendable {
    case finalDeliveryFailed

    var description: String {
        "finalDeliveryFailed"
    }
}

private actor CountingTranscriber: Transcriber {
    nonisolated let capabilities = TranscriberCapabilities()

    private let result: TranscriptionResult
    private let delay: Duration?
    private var calls = 0

    init(
        result: TranscriptionResult,
        delay: Duration? = nil
    ) {
        self.result = result
        self.delay = delay
    }

    func prepare() async throws {}

    nonisolated func modelDownloadProgress() -> AsyncStream<ModelDownloadProgress> {
        AsyncStream { continuation in
            continuation.yield(
                ModelDownloadProgress(
                    phase: .idle,
                    fractionCompleted: 0,
                    receivedBytes: 0,
                    expectedBytes: nil
                )
            )
            continuation.finish()
        }
    }

    func transcribe(_ audio: PCMBuffer) async throws -> TranscriptionResult {
        calls += 1
        if let delay {
            try? await Task.sleep(for: delay)
        }
        return result
    }

    func transcribeCallCount() -> Int {
        calls
    }
}

private actor SlowPrepareTranscriber: Transcriber {
    nonisolated let capabilities = TranscriberCapabilities()

    private let result: TranscriptionResult
    private var didStartPrepare = false
    private var prepareContinuation: CheckedContinuation<Void, Never>?
    private var startWaiters: [CheckedContinuation<Void, Never>] = []
    private var transcribeCount = 0

    init(result: TranscriptionResult) {
        self.result = result
    }

    func prepare() async throws {
        didStartPrepare = true
        let waiters = startWaiters
        startWaiters.removeAll()
        for waiter in waiters {
            waiter.resume()
        }

        await withCheckedContinuation { continuation in
            prepareContinuation = continuation
        }
    }

    nonisolated func modelDownloadProgress() -> AsyncStream<ModelDownloadProgress> {
        AsyncStream { continuation in
            continuation.yield(
                ModelDownloadProgress(
                    phase: .idle,
                    fractionCompleted: 0,
                    receivedBytes: 0,
                    expectedBytes: nil
                )
            )
            continuation.finish()
        }
    }

    func transcribe(_ audio: PCMBuffer) async throws -> TranscriptionResult {
        transcribeCount += 1
        return result
    }

    func waitUntilPrepareStarted() async {
        if didStartPrepare {
            return
        }

        await withCheckedContinuation { continuation in
            startWaiters.append(continuation)
        }
    }

    func releasePrepare() {
        prepareContinuation?.resume()
        prepareContinuation = nil
    }

    func transcribeCallCount() -> Int {
        transcribeCount
    }
}

private actor ReturningTranscriber: Transcriber {
    nonisolated let capabilities = TranscriberCapabilities()
    private let result: TranscriptionResult

    init(result: TranscriptionResult) {
        self.result = result
    }

    func prepare() async throws {}

    nonisolated func modelDownloadProgress() -> AsyncStream<ModelDownloadProgress> {
        AsyncStream { $0.finish() }
    }

    func transcribe(_ audio: PCMBuffer) async throws -> TranscriptionResult {
        result
    }
}

private actor InspectingTranscriber: Transcriber {
    nonisolated let capabilities = TranscriberCapabilities()
    private let resultText: String
    private var lastObservedSampleCount: Int?

    init(resultText: String) {
        self.resultText = resultText
    }

    func prepare() async throws {}

    nonisolated func modelDownloadProgress() -> AsyncStream<ModelDownloadProgress> {
        AsyncStream { $0.finish() }
    }

    func transcribe(_ audio: PCMBuffer) async throws -> TranscriptionResult {
        lastObservedSampleCount = audio.samples.count
        return TranscriptionResult(
            text: resultText,
            audioDuration: audio.duration,
            processingDuration: .zero
        )
    }

    func lastSampleCount() -> Int? {
        lastObservedSampleCount
    }
}

private actor ScriptedStreamingTranscriber: StreamingTranscriber {
    nonisolated let capabilities = TranscriberCapabilities()

    private let perBufferEvents: [[StreamingTranscriptionEvent]]
    private let terminalResult: TranscriptionResult?

    init(
        perBufferEvents: [[StreamingTranscriptionEvent]],
        terminalResult: TranscriptionResult?
    ) {
        self.perBufferEvents = perBufferEvents
        self.terminalResult = terminalResult
    }

    func prepare() async throws {}

    nonisolated func modelDownloadProgress() -> AsyncStream<ModelDownloadProgress> {
        AsyncStream { $0.finish() }
    }

    nonisolated func transcribe(
        stream: AsyncThrowingStream<PCMBuffer, Error>
    ) -> AsyncThrowingStream<StreamingTranscriptionEvent, Error> {
        let perBufferEvents = self.perBufferEvents
        let terminalResult = self.terminalResult
        return AsyncThrowingStream { continuation in
            Task {
                do {
                    var index = 0
                    for try await _ in stream {
                        if index < perBufferEvents.count {
                            for event in perBufferEvents[index] {
                                continuation.yield(event)
                            }
                        }
                        index += 1
                    }

                    if let terminalResult {
                        continuation.yield(.finalized(terminalResult))
                    }
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
        }
    }
}

private actor FailingStreamingTranscriber: StreamingTranscriber {
    nonisolated let capabilities = TranscriberCapabilities()

    private let perBufferEvents: [[StreamingTranscriptionEvent]]
    private let failureAfterBufferCount: Int
    private let error: any Error

    init(
        perBufferEvents: [[StreamingTranscriptionEvent]],
        failureAfterBufferCount: Int,
        error: any Error
    ) {
        self.perBufferEvents = perBufferEvents
        self.failureAfterBufferCount = failureAfterBufferCount
        self.error = error
    }

    func prepare() async throws {}

    nonisolated func modelDownloadProgress() -> AsyncStream<ModelDownloadProgress> {
        AsyncStream { $0.finish() }
    }

    nonisolated func transcribe(
        stream: AsyncThrowingStream<PCMBuffer, Error>
    ) -> AsyncThrowingStream<StreamingTranscriptionEvent, Error> {
        let perBufferEvents = self.perBufferEvents
        let failureAfterBufferCount = self.failureAfterBufferCount
        let error = self.error
        return AsyncThrowingStream { continuation in
            Task {
                do {
                    var processedBufferCount = 0
                    for try await _ in stream {
                        if processedBufferCount < perBufferEvents.count {
                            for event in perBufferEvents[processedBufferCount] {
                                continuation.yield(event)
                            }
                        }
                        processedBufferCount += 1
                        if processedBufferCount >= failureAfterBufferCount {
                            continuation.finish(throwing: error)
                            return
                        }
                    }
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
        }
    }
}

private actor HangingStreamingTranscriber: StreamingTranscriber {
    nonisolated let capabilities = TranscriberCapabilities()

    private let perBufferEvents: [[StreamingTranscriptionEvent]]
    private let tracker: StreamTerminationTracker

    init(
        perBufferEvents: [[StreamingTranscriptionEvent]],
        tracker: StreamTerminationTracker
    ) {
        self.perBufferEvents = perBufferEvents
        self.tracker = tracker
    }

    func prepare() async throws {}

    nonisolated func modelDownloadProgress() -> AsyncStream<ModelDownloadProgress> {
        AsyncStream { $0.finish() }
    }

    nonisolated func transcribe(
        stream: AsyncThrowingStream<PCMBuffer, Error>
    ) -> AsyncThrowingStream<StreamingTranscriptionEvent, Error> {
        let perBufferEvents = self.perBufferEvents
        let tracker = self.tracker
        return AsyncThrowingStream { continuation in
            Task {
                await tracker.recordStart()
            }

            let inputObserver = Task {
                do {
                    var index = 0
                    for try await _ in stream {
                        if index < perBufferEvents.count {
                            for event in perBufferEvents[index] {
                                continuation.yield(event)
                            }
                        }
                        index += 1
                    }
                    // Intentionally leave the continuation open after
                    // input closes. This simulates a buggy adapter that
                    // never terminates its event stream at stop-time.
                } catch {
                    continuation.finish(throwing: error)
                }
            }

            continuation.onTermination = { _ in
                inputObserver.cancel()
                Task {
                    await tracker.recordTermination()
                }
            }
        }
    }
}

private actor StreamTerminationTracker {
    private var started = false
    private var terminated = false
    private var startWaiters: [CheckedContinuation<Void, Never>] = []
    private var terminationWaiters: [CheckedContinuation<Void, Never>] = []

    func recordStart() {
        guard !started else {
            return
        }
        started = true
        let waiters = startWaiters
        startWaiters.removeAll()
        for waiter in waiters {
            waiter.resume()
        }
    }

    func recordTermination() {
        guard !terminated else {
            return
        }
        terminated = true
        let waiters = terminationWaiters
        terminationWaiters.removeAll()
        for waiter in waiters {
            waiter.resume()
        }
    }

    func waitUntilStarted() async {
        if started {
            return
        }
        await withCheckedContinuation { continuation in
            startWaiters.append(continuation)
        }
    }

    func waitUntilTerminated() async {
        if terminated {
            return
        }
        await withCheckedContinuation { continuation in
            terminationWaiters.append(continuation)
        }
    }
}

private enum StreamTestError: Error {
    case streamFailed
}

private struct TrackedTranscriber: Transcriber {
    let capabilities = TranscriberCapabilities()
    let result: TranscriptionResult
    let progressEvents: [ModelDownloadProgress]
    let tracker: TranscriberTracker

    func prepare() async throws {
        await tracker.recordPrepare()
    }

    func modelDownloadProgress() -> AsyncStream<ModelDownloadProgress> {
        let events = progressEvents
        return AsyncStream { continuation in
            for event in events {
                continuation.yield(event)
            }
            continuation.finish()
        }
    }

    func transcribe(_ audio: PCMBuffer) async throws -> TranscriptionResult {
        await tracker.recordTranscribe()
        return result
    }
}

private actor TranscriberTracker {
    private var prepareCalls = 0
    private var transcribeCalls = 0

    func recordPrepare() {
        prepareCalls += 1
    }

    func recordTranscribe() {
        transcribeCalls += 1
    }

    func prepareCallCount() -> Int {
        prepareCalls
    }

    func transcribeCallCount() -> Int {
        transcribeCalls
    }
}

private actor PersistedEntries {
    private var entries: [TranscriptEntry] = []

    func append(_ entry: TranscriptEntry) {
        entries.append(entry)
    }

    func count() -> Int {
        entries.count
    }

    func first() -> TranscriptEntry? {
        entries.first
    }
}

/// Used by the `#071` race-fix test: `start()` blocks until `release()`
/// is called, letting the test inspect orchestrator state while capture
/// is still being awaited.
private actor HangingStartCapture: AudioCapturer {
    private var waiters: [CheckedContinuation<AsyncThrowingStream<PCMBuffer, Error>, Error>] = []
    private var released = false

    func start() async throws -> AsyncThrowingStream<PCMBuffer, Error> {
        if released {
            return AsyncThrowingStream { $0.finish() }
        }
        return try await withCheckedThrowingContinuation { continuation in
            waiters.append(continuation)
        }
    }

    func stop() async {}

    func audioLevelStream() async -> AsyncStream<Float> {
        AsyncStream { $0.finish() }
    }

    func release() {
        released = true
        let pending = waiters
        waiters.removeAll()
        for continuation in pending {
            continuation.resume(returning: AsyncThrowingStream<PCMBuffer, Error> { $0.finish() })
        }
    }
}

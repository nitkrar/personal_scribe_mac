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

        XCTAssertEqual(initialSnapshot, PipelineSnapshot(context: context))
        let liveSnapshot = await orchestrator.snapshot()
        XCTAssertEqual(liveSnapshot, PipelineSnapshot(context: context))
    }

    func testToggleCapturePublishesStagesProgressAndFinalResult() async throws {
        let buffer = try makeBuffer(sampleCount: 16_000)
        let sink = TestPipelineOutputSink()
        let context = makeContext(streamingOutputEnabled: true)
        let orchestrator = makeOrchestrator(
            capture: FakeAudioCapturing(buffers: [buffer]),
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
        let observedTask = Task { () -> [PipelineSnapshot] in
            var snapshots: [PipelineSnapshot] = []
            for await snapshot in stream {
                snapshots.append(snapshot)
                if snapshot.sessionState == .idle && snapshot.lastCompletedResult != nil {
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
        XCTAssertEqual(finalSnapshot.sessionState, .idle)
        XCTAssertNil(finalSnapshot.activeStage)
        XCTAssertEqual(finalSnapshot.lastCompletedResult?.text, "Hello world.")
        XCTAssertEqual(finalSnapshot.recordingDuration, .seconds(1))
        XCTAssertEqual(finalSnapshot.context, context)
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
            capture: FakeAudioCapturing(error: .audioEngineFailure),
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
        let observedTask = Task { () -> [PipelineSnapshot] in
            var snapshots: [PipelineSnapshot] = []
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
            [.idle, .recording, .error(.audioEngineFailure), .idle, .recording]
        )
        XCTAssertEqual(observed.map(\.activeStage), [nil, .capture, .capture, nil, .capture])
        let sinkResetCount2 = await sink.resetCount()
        XCTAssertEqual(sinkResetCount2, 2)
    }

    func testShortRecordingPublishesRecordingTooShortWithoutCallingTranscriber() async throws {
        let shortBuffer = try makeBuffer(sampleCount: 8_000)
        let transcriber = CountingTranscriber(
            result: TranscriptionResult(
                text: "should not be called",
                audioDuration: .milliseconds(500),
                processingDuration: .zero
            )
        )
        let orchestrator = makeOrchestrator(
            capture: FakeAudioCapturing(buffers: [shortBuffer]),
            transcriber: transcriber
        )

        let stream = await orchestrator.snapshotStream()
        let observedTask = Task { () -> [PipelineSnapshot] in
            var snapshots: [PipelineSnapshot] = []
            for await snapshot in stream {
                snapshots.append(snapshot)
                if snapshot.sessionState == .error(.recordingTooShort) {
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

        XCTAssertEqual(
            deduplicatedSessionStates(from: observed),
            [.idle, .recording, .error(.recordingTooShort)]
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
            capture: FakeAudioCapturing(buffers: [buffer]),
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
        let observedTask = Task { () -> [PipelineSnapshot] in
            var snapshots: [PipelineSnapshot] = []
            for await snapshot in stream {
                snapshots.append(snapshot)
                if snapshot.sessionState == .idle && snapshot.lastCompletedResult != nil {
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

        XCTAssertEqual(observed.last?.sessionState, .idle)
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
            capture: FakeAudioCapturing(
                buffers: buffers,
                delayPerBuffer: .milliseconds(100)
            )
        )

        let stream = await orchestrator.snapshotStream()
        let observedTask = Task { () -> [PipelineSnapshot] in
            var snapshots: [PipelineSnapshot] = []
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
            .filter { $0.sessionState == .recording }
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
        // published `.recording` and *then* spawned a `.background`-
        // priority detached Task for prepare. If the user stopped
        // recording quickly, the pipeline would transition to
        // `.transcribing` and sit there for minutes because prepare had
        // never been scheduled. This test pins the corrected ordering:
        // prepare begins executing BEFORE the user can observe the
        // `.recording` snapshot externally.
        let buffer = try makeBuffer(sampleCount: 16_000, sampleValue: 0.1)
        let transcriber = SlowPrepareTranscriber(
            result: TranscriptionResult(
                text: "",
                audioDuration: .seconds(1),
                processingDuration: .milliseconds(1)
            )
        )
        let orchestrator = makeOrchestrator(
            capture: FakeAudioCapturing(buffers: [buffer]),
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
        XCTAssertEqual(snapshot.sessionState, .recording,
                       "startRecording must have published `.recording` by the time prepare has entered")
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
            capture: FakeAudioCapturing(buffers: [buffer]),
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

        XCTAssertEqual(snapshot.sessionState, .idle)
        XCTAssertEqual(snapshot.lastCompletedResult?.text, "Hello.")
        let transcribeCount1 = await transcriber.transcribeCallCount()
        XCTAssertEqual(transcribeCount1, 1)
    }

    func testAudioLevelStreamRepublishesLevelsDuringRecording() async throws {
        let buffer = try makeBuffer(sampleCount: 16_000)
        let canned: [Float] = [0.15, 0.25, 0.5, 0.75, 0.95]
        let orchestrator = makeOrchestrator(
            capture: FakeAudioCapturing(buffers: [buffer], levels: canned),
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
            capture: FakeAudioCapturing(buffers: [buffer], levels: canned),
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

    func testPrepareTranscriberAndModelDownloadProgressPassThrough() async throws {
        let tracker = TranscriberTracker()
        let transcriber = TrackedTranscriber(
            result: TranscriptionResult(
                text: "hello",
                audioDuration: .seconds(1),
                processingDuration: .milliseconds(100)
            ),
            progressEvents: [
                .init(phase: .downloading, fractionCompleted: 0.4, receivedBytes: 40, expectedBytes: 100),
                .init(phase: .finished, fractionCompleted: 1.0, receivedBytes: 100, expectedBytes: 100),
            ],
            tracker: tracker
        )
        let orchestrator = makeOrchestrator(transcriber: transcriber)

        try await orchestrator.prepareTranscriber()

        let progressStream = await orchestrator.modelDownloadProgress()
        var iterator = progressStream.makeAsyncIterator()
        let first = await iterator.next()
        let second = await iterator.next()

        let prepareCount = await tracker.prepareCallCount()
        XCTAssertEqual(prepareCount, 1)
        XCTAssertEqual(first?.phase, .downloading)
        XCTAssertEqual(first?.fractionCompleted, 0.4)
        XCTAssertEqual(second?.phase, .finished)
    }

    func testSuccessfulTranscriptionAppendsEntryToSQLiteStore() async throws {
        let temporaryDirectory = try makeTemporaryDirectory()
        defer {
            try? FileManager.default.removeItem(at: temporaryDirectory)
        }

        let repository = try makeRepository(in: temporaryDirectory)
        let buffer = try makeBuffer(sampleCount: 16_000)
        let orchestrator = makeOrchestrator(
            capture: FakeAudioCapturing(buffers: [buffer]),
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

    func testPostProcessingFailurePublishesTypedStageFailure() async throws {
        let buffer = try makeBuffer(sampleCount: 16_000)
        let orchestrator = makeOrchestrator(
            capture: FakeAudioCapturing(buffers: [buffer]),
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
        XCTAssertEqual(failure?.stage, .postProcessing)
        XCTAssertEqual(failure?.detail, "post-processing-failure")
        XCTAssertEqual(failure?.mappedError, .transcriptionFailure)
    }

    func testPersistenceFailurePublishesTypedStageFailure() async throws {
        let buffer = try makeBuffer(sampleCount: 16_000)
        let sink = TestPipelineOutputSink()
        let orchestrator = makeOrchestrator(
            capture: FakeAudioCapturing(buffers: [buffer]),
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
            capture: FakeAudioCapturing(buffers: [buffer]),
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
            capture: FakeAudioCapturing(buffers: [buffer]),
            transcriber: FakeTranscriber(
                result: TranscriptionResult(
                    text: "hello from hold",
                    audioDuration: .seconds(1),
                    processingDuration: .milliseconds(10)
                )
            )
        )

        let stream = await orchestrator.snapshotStream()
        let observedTask = Task { () -> [PipelineSnapshot] in
            var snapshots: [PipelineSnapshot] = []
            for await snapshot in stream {
                snapshots.append(snapshot)
                if snapshot.sessionState == .idle && snapshot.lastCompletedResult != nil {
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
        XCTAssertEqual(observed.last?.sessionState, .idle)
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

    /// `cancelCapture()` from `.recording` must drop the buffered audio,
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
            capture: FakeAudioCapturing(buffers: [buffer]),
            transcriber: transcriber,
            outputSink: sink
        )

        await orchestrator.toggleCapture()

        // Wait for .recording before cancelling. Without this the cancel
        // could slip in before startRecording's publish lands.
        try await withTimeout(.seconds(1)) {
            while await orchestrator.snapshot().sessionState != .recording {
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
            capture: FakeAudioCapturing(buffers: [buffer]),
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
        let orchestrator = makeOrchestrator(capture: FakeAudioCapturing(buffers: [buffer]))

        let stream = await orchestrator.snapshotStream()
        let observed = Task { () -> [SessionState] in
            var states: [SessionState] = []
            for await snapshot in stream {
                states.append(snapshot.sessionState)
                if snapshot.sessionState == .idle && !states.contains(.recording) {
                    continue
                }
                if snapshot.sessionState == .idle && states.contains(.recording) {
                    break
                }
            }
            return states
        }

        await orchestrator.toggleCapture()
        try await withTimeout(.seconds(1)) {
            while await orchestrator.snapshot().sessionState != .recording {
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
        capture: any AudioCapturing = FakeAudioCapturing(),
        transcriber: any Transcribing = FakeTranscriber(
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
        persistenceHandler: (@Sendable (TranscriptEntry) async throws -> Void)? = nil
    ) -> SessionPipelineOrchestrator {
        let contextProvider = StaticPipelineContextProvider(context: context)
        if let persistenceHandler {
            return SessionPipelineOrchestrator(
                capture: capture,
                transcriber: transcriber,
                logger: PersonalScribeLogger(category: PersonalScribeLogCategory.session),
                postProcessingPipeline: postProcessingPipeline,
                outputSink: outputSink,
                contextProvider: contextProvider,
                persistenceHandler: persistenceHandler
            )
        }

        return SessionPipelineOrchestrator(
            capture: capture,
            transcriber: transcriber,
            transcriptRepository: transcriptRepository,
            logger: PersonalScribeLogger(category: PersonalScribeLogCategory.session),
            postProcessingPipeline: postProcessingPipeline,
            outputSink: outputSink,
            contextProvider: contextProvider
        )
    }

    private func makeContext(streamingOutputEnabled: Bool) -> PipelineContextSnapshot {
        let mode = ModeDescriptor(
            id: "dictation-plus",
            name: "Dictation Plus",
            voiceModelID: "voice.default",
            aiModelID: "gpt-5.4",
            systemPrompt: "Polish the final transcript."
        )
        return PipelineContextSnapshot(
            activeMode: mode,
            activeAIModelID: mode.aiModelID,
            systemPrompt: mode.systemPrompt,
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

    private func deduplicatedStages(from snapshots: [PipelineSnapshot]) -> [PipelineStageID] {
        var stages: [PipelineStageID] = []
        for stage in snapshots.compactMap(\.activeStage) where stages.last != stage {
            stages.append(stage)
        }
        return stages
    }

    private func deduplicatedSessionStates(from snapshots: [PipelineSnapshot]) -> [SessionState] {
        var states: [SessionState] = []
        for state in snapshots.map(\.sessionState) where states.last != state {
            states.append(state)
        }
        return states
    }

    private func progressSnapshotsByRevision(
        from snapshots: [PipelineSnapshot]
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
        return TranscriptRepository(database: database)
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

    func partialDeliveries() -> [TranscriptProgress] {
        partials
    }

    func finalDeliveries() -> [TranscriptionResult] {
        finals
    }

    func resetCount() -> Int {
        resets
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

private actor CountingTranscriber: Transcribing {
    private let result: TranscriptionResult
    private var calls = 0

    init(result: TranscriptionResult) {
        self.result = result
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
        return result
    }

    func transcribe(stream: AsyncThrowingStream<PCMBuffer, Error>) async throws -> TranscriptionResult {
        for try await _ in stream {}
        calls += 1
        return result
    }

    func transcribeCallCount() -> Int {
        calls
    }
}

private actor SlowPrepareTranscriber: Transcribing {
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

    func transcribe(stream: AsyncThrowingStream<PCMBuffer, Error>) async throws -> TranscriptionResult {
        for try await _ in stream {}
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

private struct TrackedTranscriber: Transcribing {
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

    func transcribe(stream: AsyncThrowingStream<PCMBuffer, Error>) async throws -> TranscriptionResult {
        for try await _ in stream {}
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

/// Used by the `#071` race-fix test: `start()` blocks until `release()`
/// is called, letting the test inspect orchestrator state while capture
/// is still being awaited.
private actor HangingStartCapture: AudioCapturing {
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

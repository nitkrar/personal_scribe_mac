import XCTest
@testable import PersonalScribeCore

@MainActor
final class AppStoreTests: XCTestCase {
    func testSnapshotRepublishesSessionStateAndModelDownloadProgress() async {
        let session = FakeAppStoreSessionProvider()
        let permissions = FakePermissionService()
        let visibilityModeProvider = FakeVisibilityModeProvider()
        let store = makeStore(
            session: session,
            permissions: permissions,
            registry: makeRegistry(),
            visibilityModeProvider: visibilityModeProvider
        )

        store.start()

        let downloading = ModelDownloadProgress(
            phase: .downloading,
            fractionCompleted: 0.42,
            receivedBytes: 42,
            expectedBytes: 100
        )
        session.emitProgress(downloading)
        await waitUntil {
            store.snapshot.modelDownloadProgress == downloading
        }

        XCTAssertEqual(store.snapshot.modelDownloadProgress, downloading)
        XCTAssertEqual(store.snapshot.pillVisibility, .downloading(fractionCompleted: 0.42))

        session.emitState(.capturing)
        await waitUntil {
            store.snapshot.sessionState == .capturing
        }

        XCTAssertEqual(store.snapshot.sessionState, .capturing)
        XCTAssertEqual(store.snapshot.pillVisibility, .recording)

        let finished = ModelDownloadProgress(
            phase: .finished,
            fractionCompleted: 1.0,
            receivedBytes: 100,
            expectedBytes: 100
        )
        session.emitProgress(finished)
        await waitUntil {
            store.snapshot.modelDownloadProgress == nil
        }

        XCTAssertNil(store.snapshot.modelDownloadProgress)
    }

    func testSnapshotRetainsStreamingTranscriptFieldsFromSession() async {
        let session = FakeAppStoreSessionProvider()
        let store = makeStore(
            session: session,
            permissions: FakePermissionService(),
            registry: makeRegistry(),
            visibilityModeProvider: FakeVisibilityModeProvider()
        )

        store.start()

        let progress = TranscriptProgress(
            revision: 1,
            text: "hello world",
            isFinal: false,
            sourceStage: .transcription
        )
        session.emitSnapshot(
            SessionSnapshot(
                sessionState: .capturing,
                transcriptProgress: progress,
                isStreamingSession: true
            )
        )

        await waitUntil {
            store.snapshot.session.transcriptProgress == progress
        }

        XCTAssertEqual(store.snapshot.session.transcriptProgress, progress)
        XCTAssertTrue(store.snapshot.session.isStreamingSession)
        XCTAssertEqual(store.snapshot.pillVisibility, .recording)
    }

    /// #071 — `.holdRecording` session state must drive `.holdToRecord`
    /// pill visibility through the store, so the hotkey layer does not
    /// need to push visibility via a side-channel.
    func testHoldRecordingSessionStateDerivesHoldToRecordPillVisibility() async {
        let session = FakeAppStoreSessionProvider()
        let store = makeStore(
            session: session,
            permissions: FakePermissionService(),
            registry: makeRegistry(),
            visibilityModeProvider: FakeVisibilityModeProvider()
        )

        store.start()

        session.emitState(.holdRecording)
        await waitUntil {
            store.snapshot.sessionState == .holdRecording
        }

        XCTAssertEqual(store.snapshot.sessionState, .holdRecording)
        XCTAssertEqual(store.snapshot.pillVisibility, .holdToRecord)
    }

    func testPausedSessionDerivesPausedPillWithCapturedDuration() async {
        let session = FakeAppStoreSessionProvider()
        let store = makeStore(
            session: session,
            permissions: FakePermissionService(),
            registry: makeRegistry(),
            visibilityModeProvider: FakeVisibilityModeProvider()
        )
        store.start()

        session.emitSnapshot(
            SessionSnapshot(
                sessionState: .paused,
                recordingDuration: .seconds(83)
            )
        )
        await waitUntil { store.snapshot.sessionState == .paused }

        XCTAssertEqual(store.snapshot.pillVisibility, .paused(elapsedSeconds: 83))
    }

    func testPermissionRefreshRepublishesSnapshot() async {
        let session = FakeAppStoreSessionProvider()
        let permissions = FakePermissionService(statuses: [
            .microphone: .pending,
            .accessibility: .denied,
        ])
        let store = makeStore(
            session: session,
            permissions: permissions,
            registry: makeRegistry(),
            visibilityModeProvider: FakeVisibilityModeProvider()
        )

        store.start()

        let refreshedStatuses: [Permission: PermissionStatus] = [
            .microphone: .granted,
            .accessibility: .granted,
        ]
        permissions.nextRefreshStatuses = refreshedStatuses
        permissions.refresh()

        await waitUntil {
            store.snapshot.permissions == refreshedStatuses
        }

        XCTAssertEqual(store.snapshot.permissions, refreshedStatuses)
    }

    func testActiveModeChangesRepublishSnapshot() async throws {
        // #078.36 + #089: AppStore consumes WorkflowModeRegistry's
        // currentModeStream(); the snapshot DTO field is still
        // `activeMode` (renamed source per #089 L-evidence).
        let registry = makeRegistry()
        let coding = makeMode(id: "coding", name: "Coding")
        try registry.saveCustom(coding)
        let store = makeStore(
            session: FakeAppStoreSessionProvider(),
            permissions: FakePermissionService(),
            registry: registry,
            visibilityModeProvider: FakeVisibilityModeProvider()
        )

        store.start()
        await waitUntil {
            store.snapshot.activeMode?.id == WorkflowMode.dictation.id
        }

        registry.setCurrent(id: "coding")
        await waitUntil {
            store.snapshot.activeMode?.id == "coding"
        }

        XCTAssertEqual(store.snapshot.activeMode?.id, "coding")
    }

    func testResumableCancelledCaptureShowsCancelCardInAutoShow() async {
        let session = FakeAppStoreSessionProvider()
        let store = makeStore(
            session: session,
            permissions: FakePermissionService(),
            registry: makeRegistry(),
            visibilityModeProvider: FakeVisibilityModeProvider(initialVisibilityMode: .autoShow)
        )
        store.start()

        session.emitSnapshot(SessionSnapshot(sessionState: .idle, cancelledCaptureResumable: true))
        await waitUntil { store.snapshot.pillVisibility == .cancelled }
        XCTAssertEqual(store.snapshot.pillVisibility, .cancelled)

        session.emitSnapshot(SessionSnapshot(sessionState: .idle))
        await waitUntil { store.snapshot.pillVisibility == .hidden }
        XCTAssertEqual(store.snapshot.pillVisibility, .hidden)
    }

    func testVisibilityModeChangesRecomputePillVisibility() async {
        let visibilityModeProvider = FakeVisibilityModeProvider(initialVisibilityMode: .autoShow)
        let store = makeStore(
            session: FakeAppStoreSessionProvider(),
            permissions: FakePermissionService(),
            registry: makeRegistry(),
            visibilityModeProvider: visibilityModeProvider
        )

        store.start()
        await waitUntil {
            store.snapshot.pillVisibility == .hidden
        }

        visibilityModeProvider.emit(.alwaysOn)
        await waitUntil {
            store.snapshot.pillVisibility == .idle
        }

        visibilityModeProvider.emit(.autoShow)
        await waitUntil {
            store.snapshot.pillVisibility == .hidden
        }

        XCTAssertEqual(store.snapshot.pillVisibility, .hidden)
    }

    func testLastTranscriptionResultRefreshesOnlyOnCompletedSessionSnapshot() async {
        let session = FakeAppStoreSessionProvider()
        let store = makeStore(
            session: session,
            permissions: FakePermissionService(),
            registry: makeRegistry(),
            visibilityModeProvider: FakeVisibilityModeProvider()
        )

        store.start()

        session.setLastResult(makeResult(text: "Ignored initial"))
        session.emitState(.idle)
        await Task.yield()
        XCTAssertNil(store.snapshot.lastTranscriptionResult)

        session.emitState(.capturing)
        await waitUntil {
            store.snapshot.sessionState == .capturing
        }
        session.setLastResult(makeResult(text: "Ignored recording to idle"))
        session.emitState(.idle)
        await waitUntil {
            store.snapshot.sessionState == .idle
        }
        XCTAssertNil(store.snapshot.lastTranscriptionResult)

        let expected = makeResult(text: "Accepted result")
        session.emitState(.transcribing)
        await waitUntil {
            store.snapshot.sessionState == .transcribing
        }
        session.setLastResult(expected)
        session.emitState(.completed)
        await waitUntil {
            store.snapshot.lastTranscriptionResult == expected
        }

        let ignoredAfterError = makeResult(text: "Ignored error to idle")
        session.setLastResult(ignoredAfterError)
        session.emitState(.error(.transcriptionFailure))
        await waitUntil {
            store.snapshot.sessionState == .error(.transcriptionFailure)
        }
        session.emitState(.idle)
        await waitUntil {
            store.snapshot.sessionState == .idle
        }

        XCTAssertEqual(store.snapshot.lastTranscriptionResult, expected)
    }

    func testCompletedSessionReturnsDirectlyToIdleVisibility() async {
        let session = FakeAppStoreSessionProvider()
        let store = makeStore(
            session: session,
            permissions: FakePermissionService(),
            registry: makeRegistry(),
            visibilityModeProvider: FakeVisibilityModeProvider()
        )

        store.start()

        session.emitState(.transcribing)
        await waitUntil {
            store.snapshot.pillVisibility == .transcribing
        }

        session.emitState(.completed)
        await waitUntil {
            store.snapshot.pillVisibility == .hidden
        }

        XCTAssertEqual(store.snapshot.pillVisibility, .hidden)
    }

    func testCompletedSessionReturnsDirectlyToAlwaysOnIdle() async {
        let session = FakeAppStoreSessionProvider()
        let store = makeStore(
            session: session,
            permissions: FakePermissionService(),
            registry: makeRegistry(),
            visibilityModeProvider: FakeVisibilityModeProvider(
                initialVisibilityMode: .alwaysOn
            )
        )

        store.start()
        session.emitState(.transcribing)
        await waitUntil {
            store.snapshot.pillVisibility == .transcribing
        }

        session.emitState(.completed)
        await waitUntil {
            store.snapshot.pillVisibility == .idle
        }

        XCTAssertEqual(store.snapshot.pillVisibility, .idle)
    }

    /// `#075`: `.shortExit` flips pill straight to idle — no chip, no
    /// message. The short hold itself is the user-facing signal; the
    /// pill returning to idle confirms the pipeline exited. Session
    /// state display-maps `.shortExit → .idle` so entry guards accept
    /// the next action.
    func testShortExitFlipsPillStraightToIdle() async {
        let session = FakeAppStoreSessionProvider()
        let store = makeStore(
            session: session,
            permissions: FakePermissionService(),
            registry: makeRegistry(),
            visibilityModeProvider: FakeVisibilityModeProvider()
        )

        store.start()

        session.emitState(.shortExit)
        await waitUntil {
            store.snapshot.pillVisibility == .hidden
        }

        XCTAssertEqual(
            store.snapshot.sessionState, .idle,
            "`.shortExit` display-maps to `.idle` via AppStoreSnapshot.sessionState"
        )
        XCTAssertEqual(store.snapshot.pillVisibility, .hidden)
    }

    func testErrorStateFallsBackToIdleVisibilityInsteadOfShowingErrorPill() async {
        let session = FakeAppStoreSessionProvider()
        let store = makeStore(
            session: session,
            permissions: FakePermissionService(),
            registry: makeRegistry(),
            visibilityModeProvider: FakeVisibilityModeProvider()
        )

        store.start()

        session.emitState(.error(.resampleFailure))
        await waitUntil {
            store.snapshot.sessionState == .error(.resampleFailure)
        }

        XCTAssertEqual(store.snapshot.sessionState, .error(.resampleFailure))
        XCTAssertEqual(store.snapshot.pillVisibility, .hidden)
    }

    private func makeStore(
        session: FakeAppStoreSessionProvider,
        permissions: FakePermissionService,
        registry: WorkflowModeRegistry,
        visibilityModeProvider: FakeVisibilityModeProvider
    ) -> AppStore {
        AppStore(
            session: session,
            permissions: permissions,
            workflowModeRegistry: registry,
            visibilityModeSource: visibilityModeProvider
        )
    }

    private func makeRegistry() -> WorkflowModeRegistry {
        // swiftlint:disable:next force_try
        try! WorkflowModeRegistry(
            store: InMemoryWorkflowModeStore(),
            availableKindsProvider: { Set(ModelKind.allCases) }
        )
    }

    private func makeMode(id: String, name: String) -> WorkflowMode {
        WorkflowMode(
            id: id,
            name: name,
            pipelineShape: .batch,
            processors: [.transcriber(kind: .asr)],
            captureControllers: [.manualHotkey],
            outputSinks: [.frontmostPaste(enabled: .override(true))]
        )
    }

    private func makeResult(text: String) -> TranscriptionResult {
        TranscriptionResult(
            text: text,
            audioDuration: .seconds(2),
            processingDuration: .milliseconds(500)
        )
    }

    /// Wall-clock polling loop (project memory: `condition-based-waiting`).
    /// Replaces the previous `Task.yield()`-only loop which flaked whenever
    /// the AppStore's AsyncStream consumer Task didn't get immediate
    /// forward progress on a yield. Real-time deadline keeps the test fast
    /// in the common case but robust under CI load.
    private func waitUntil(
        timeout: Duration = .seconds(5),
        pollInterval: Duration = .milliseconds(5),
        condition: @escaping @MainActor () -> Bool
    ) async {
        let clock = ContinuousClock()
        let deadline = clock.now.advanced(by: timeout)
        while clock.now < deadline {
            if condition() {
                return
            }
            try? await Task.sleep(for: pollInterval, tolerance: pollInterval)
        }
        XCTFail("Timed out waiting for condition after \(timeout)")
    }
}

private final class DeferredInitialYieldVisibilityModeProvider: @unchecked Sendable, AppStoreVisibilityModeProviding {
    private var currentMode: AppStoreVisibilityMode
    private var continuation: AsyncStream<AppStoreVisibilityMode>.Continuation?
    private(set) var hasSubscriber = false
    private var hasEmittedInitialReplay = false

    init(initialVisibilityMode: AppStoreVisibilityMode) {
        currentMode = initialVisibilityMode
    }

    func currentVisibilityMode() -> AppStoreVisibilityMode {
        currentMode
    }

    func visibilityModeStream() -> AsyncStream<AppStoreVisibilityMode> {
        AsyncStream { continuation in
            self.hasSubscriber = true
            self.continuation = continuation
            continuation.onTermination = { [weak self] _ in
                self?.hasSubscriber = false
                self?.continuation = nil
            }
        }
    }

    func emitInitialReplay() {
        guard !hasEmittedInitialReplay else {
            return
        }

        hasEmittedInitialReplay = true
        continuation?.yield(currentMode)
    }
}

import XCTest
@testable import PersonalScribeCore

@MainActor
final class AppStoreTests: XCTestCase {
    func testSnapshotRepublishesSessionStateAndModelDownloadProgress() async {
        let session = FakeAppStoreSessionProvider()
        let permissions = FakePermissionService()
        let activeModeProvider = FakeActiveModeProvider()
        let visibilityModeProvider = FakeVisibilityModeProvider()
        let clock = ManualAppStoreClock()
        let store = makeStore(
            session: session,
            permissions: permissions,
            activeModeProvider: activeModeProvider,
            visibilityModeProvider: visibilityModeProvider,
            clock: clock
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

        session.emitState(.recording)
        await waitUntil {
            store.snapshot.sessionState == .recording
        }

        XCTAssertEqual(store.snapshot.sessionState, .recording)
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

    /// #071 — `.holdRecording` session state must drive `.holdToRecord`
    /// pill visibility through the store, so the hotkey layer does not
    /// need to push visibility via a side-channel.
    func testHoldRecordingSessionStateDerivesHoldToRecordPillVisibility() async {
        let session = FakeAppStoreSessionProvider()
        let store = makeStore(
            session: session,
            permissions: FakePermissionService(),
            activeModeProvider: FakeActiveModeProvider(),
            visibilityModeProvider: FakeVisibilityModeProvider(),
            clock: ManualAppStoreClock()
        )

        store.start()

        session.emitState(.holdRecording)
        await waitUntil {
            store.snapshot.sessionState == .holdRecording
        }

        XCTAssertEqual(store.snapshot.sessionState, .holdRecording)
        XCTAssertEqual(store.snapshot.pillVisibility, .holdToRecord)
    }

    func testPermissionRefreshRepublishesSnapshot() async {
        let session = FakeAppStoreSessionProvider()
        let permissions = FakePermissionService(statuses: [
            .microphone: .pending,
            .inputMonitoring: .pending,
            .accessibility: .denied,
        ])
        let store = makeStore(
            session: session,
            permissions: permissions,
            activeModeProvider: FakeActiveModeProvider(),
            visibilityModeProvider: FakeVisibilityModeProvider(),
            clock: ManualAppStoreClock()
        )

        store.start()

        let refreshedStatuses: [Permission: PermissionStatus] = [
            .microphone: .granted,
            .inputMonitoring: .granted,
            .accessibility: .granted,
        ]
        permissions.nextRefreshStatuses = refreshedStatuses
        permissions.refresh()

        await waitUntil {
            store.snapshot.permissions == refreshedStatuses
        }

        XCTAssertEqual(store.snapshot.permissions, refreshedStatuses)
    }

    func testActiveModeChangesRepublishSnapshot() async {
        let activeModeProvider = FakeActiveModeProvider()
        let dictation = makeMode(id: "dictation", name: "Dictation")
        let coding = makeMode(id: "coding", name: "Coding")
        let store = makeStore(
            session: FakeAppStoreSessionProvider(),
            permissions: FakePermissionService(),
            activeModeProvider: activeModeProvider,
            visibilityModeProvider: FakeVisibilityModeProvider(),
            clock: ManualAppStoreClock()
        )

        activeModeProvider.emit(dictation)
        store.start()
        await waitUntil {
            store.snapshot.activeMode == dictation
        }

        activeModeProvider.emit(coding)
        await waitUntil {
            store.snapshot.activeMode == coding
        }

        XCTAssertEqual(store.snapshot.activeMode, coding)
    }

    func testVisibilityModeChangesRecomputePillVisibility() async {
        let visibilityModeProvider = FakeVisibilityModeProvider(initialVisibilityMode: .hidden)
        let store = makeStore(
            session: FakeAppStoreSessionProvider(),
            permissions: FakePermissionService(),
            activeModeProvider: FakeActiveModeProvider(),
            visibilityModeProvider: visibilityModeProvider,
            clock: ManualAppStoreClock()
        )

        store.start()
        await waitUntil {
            store.snapshot.pillVisibility == .hidden
        }

        visibilityModeProvider.emit(.alwaysOn)
        await waitUntil {
            store.snapshot.pillVisibility == .idle
        }

        visibilityModeProvider.emit(.hidden)
        await waitUntil {
            store.snapshot.pillVisibility == .hidden
        }

        XCTAssertEqual(store.snapshot.pillVisibility, .hidden)
    }

    func testLastTranscriptionResultRefreshesOnlyOnTranscribingToIdleTransition() async {
        let session = FakeAppStoreSessionProvider()
        let store = makeStore(
            session: session,
            permissions: FakePermissionService(),
            activeModeProvider: FakeActiveModeProvider(),
            visibilityModeProvider: FakeVisibilityModeProvider(),
            clock: ManualAppStoreClock()
        )

        store.start()

        session.setLastResult(makeResult(text: "Ignored initial"))
        session.emitState(.idle)
        await Task.yield()
        XCTAssertNil(store.snapshot.lastTranscriptionResult)

        session.emitState(.recording)
        await waitUntil {
            store.snapshot.sessionState == .recording
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
        session.emitState(.idle)
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

    func testDoneVisibilityIsTransientAfterTranscribingToIdle() async {
        let session = FakeAppStoreSessionProvider()
        let clock = ManualAppStoreClock()
        let store = makeStore(
            session: session,
            permissions: FakePermissionService(),
            activeModeProvider: FakeActiveModeProvider(),
            visibilityModeProvider: FakeVisibilityModeProvider(),
            clock: clock
        )

        store.start()

        session.emitState(.transcribing)
        await waitUntil {
            store.snapshot.pillVisibility == .transcribing
        }

        session.emitState(.idle)
        await waitUntil {
            store.snapshot.pillVisibility == .done
        }

        await clock.advance(by: .milliseconds(999))
        XCTAssertEqual(store.snapshot.pillVisibility, .done)

        await clock.advance(by: .milliseconds(1))
        await waitUntil {
            store.snapshot.pillVisibility == .hidden
        }

        XCTAssertEqual(store.snapshot.pillVisibility, .hidden)
    }

    func testInitialVisibilityModeReplayDoesNotClobberDoneTransient() async {
        let session = FakeAppStoreSessionProvider()
        let visibilityModeProvider = DeferredInitialYieldVisibilityModeProvider(
            initialVisibilityMode: .hidden
        )
        let clock = ManualAppStoreClock()
        let store = AppStore(
            session: session,
            permissions: FakePermissionService(),
            activeModeSource: FakeActiveModeProvider(),
            visibilityModeSource: visibilityModeProvider,
            clock: clock
        )

        store.start()
        await waitUntil {
            visibilityModeProvider.hasSubscriber
        }

        session.emitState(.transcribing)
        await waitUntil {
            store.snapshot.pillVisibility == .transcribing
        }

        session.emitState(.idle)
        await waitUntil {
            store.snapshot.pillVisibility == .done
        }

        visibilityModeProvider.emitInitialReplay()
        await Task.yield()
        XCTAssertEqual(store.snapshot.pillVisibility, .done)

        await clock.advance(by: .milliseconds(999))
        XCTAssertEqual(store.snapshot.pillVisibility, .done)

        await clock.advance(by: .milliseconds(1))
        await waitUntil {
            store.snapshot.pillVisibility == .hidden
        }

        XCTAssertEqual(store.snapshot.pillVisibility, .hidden)
    }

    func testErrorVisibilityIsTransientAfterErrorState() async {
        let session = FakeAppStoreSessionProvider()
        let clock = ManualAppStoreClock()
        let store = makeStore(
            session: session,
            permissions: FakePermissionService(),
            activeModeProvider: FakeActiveModeProvider(),
            visibilityModeProvider: FakeVisibilityModeProvider(),
            clock: clock
        )

        store.start()
        await clock.advance(by: .zero)

        session.emitState(.error(.recordingTooShort))
        await waitUntil {
            store.snapshot.pillVisibility == .error(message: "Too short — try again")
        }

        await clock.advance(by: .milliseconds(1_499))
        XCTAssertEqual(
            store.snapshot.pillVisibility,
            .error(message: "Too short — try again")
        )

        await clock.advance(by: .milliseconds(1))
        await waitUntil {
            store.snapshot.pillVisibility == .hidden
        }

        XCTAssertEqual(store.snapshot.sessionState, .error(.recordingTooShort))
        XCTAssertEqual(store.snapshot.pillVisibility, .hidden)
    }

    func testRecordingDurationTicksAndClearsOutsideRecording() async {
        let session = FakeAppStoreSessionProvider()
        let clock = ManualAppStoreClock()
        let store = makeStore(
            session: session,
            permissions: FakePermissionService(),
            activeModeProvider: FakeActiveModeProvider(),
            visibilityModeProvider: FakeVisibilityModeProvider(),
            clock: clock
        )

        store.start()

        session.emitState(.recording)
        await waitUntil {
            store.snapshot.currentRecordingDuration == .zero
        }

        await clock.advance(by: .milliseconds(250))
        await waitUntil {
            store.snapshot.currentRecordingDuration == .milliseconds(250)
        }

        await clock.advance(by: .milliseconds(750))
        await waitUntil {
            store.snapshot.currentRecordingDuration == .seconds(1)
        }

        session.emitState(.transcribing)
        await waitUntil {
            store.snapshot.currentRecordingDuration == nil
        }

        XCTAssertNil(store.snapshot.currentRecordingDuration)
    }

    private func makeStore(
        session: FakeAppStoreSessionProvider,
        permissions: FakePermissionService,
        activeModeProvider: FakeActiveModeProvider,
        visibilityModeProvider: FakeVisibilityModeProvider,
        clock: ManualAppStoreClock
    ) -> AppStore {
        AppStore(
            session: session,
            permissions: permissions,
            activeModeSource: activeModeProvider,
            visibilityModeSource: visibilityModeProvider,
            clock: clock
        )
    }

    private func makeMode(id: String, name: String) -> ModeDescriptor {
        ModeDescriptor(
            id: id,
            name: name,
            voiceModelID: "voice-\(id)"
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

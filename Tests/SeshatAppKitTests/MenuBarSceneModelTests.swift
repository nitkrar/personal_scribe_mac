import AppKit
import Combine
import XCTest
import SeshatCore
import SeshatSession
import SeshatTestSupport
@testable import SeshatAppKit

@MainActor
final class MenuBarSceneModelTests: XCTestCase {
    func testInitSeedsPermissionStateFromProvider() async throws {
        let coordinator = try makeCoordinator()
        let model = MenuBarSceneModel(
            coordinator: coordinator,
            permissionRequester: TestPermissionRequester(result: true),
            permissionStateProvider: { .denied },
            clipboardWriter: { _ in },
            pasteInjector: { _ in .pasteAtCursor },
            openSettings: {},
            logger: SeshatLogger(category: SeshatLogCategory.ui)
        )

        XCTAssertEqual(model.permissionState, .denied)
    }

    func testRequestingAccessUpdatesPermissionStateToDeniedWhenPromptReturnsFalse() async throws {
        let coordinator = try makeCoordinator()
        let model = MenuBarSceneModel(
            coordinator: coordinator,
            permissionRequester: TestPermissionRequester(result: false),
            permissionStateProvider: { .notYetRequested },
            clipboardWriter: { _ in },
            pasteInjector: { _ in .pasteAtCursor },
            openSettings: {},
            logger: SeshatLogger(category: SeshatLogCategory.ui)
        )

        await model.handleRecordButtonTap()

        XCTAssertEqual(model.permissionState, .denied)
        let sessionState = await coordinator.state()
        XCTAssertEqual(sessionState, .idle)
    }

    func testHandleRecordButtonTapTogglesWhenPermissionAlreadyGranted() async throws {
        let coordinator = try makeCoordinator()
        let requester = TestPermissionRequester(result: true)
        let model = MenuBarSceneModel(
            coordinator: coordinator,
            permissionRequester: requester,
            permissionStateProvider: { .granted },
            clipboardWriter: { _ in },
            pasteInjector: { _ in .pasteAtCursor },
            openSettings: {},
            logger: SeshatLogger(category: SeshatLogCategory.ui)
        )

        await model.handleRecordButtonTap()

        let sessionState = await coordinator.state()
        let requestCount = await requester.callCount()
        XCTAssertEqual(sessionState, .recording)
        XCTAssertEqual(requestCount, 0)
    }

    func testHandleRecordButtonTapRequestsAccessThenTogglesWhenPromptSucceeds() async throws {
        let coordinator = try makeCoordinator()
        let requester = TestPermissionRequester(result: true)
        let model = MenuBarSceneModel(
            coordinator: coordinator,
            permissionRequester: requester,
            permissionStateProvider: { .notYetRequested },
            clipboardWriter: { _ in },
            pasteInjector: { _ in .pasteAtCursor },
            openSettings: {},
            logger: SeshatLogger(category: SeshatLogCategory.ui)
        )

        await model.handleRecordButtonTap()

        let sessionState = await coordinator.state()
        let requestCount = await requester.callCount()
        XCTAssertEqual(model.permissionState, .granted)
        XCTAssertEqual(sessionState, .recording)
        XCTAssertEqual(requestCount, 1)
    }

    func testHandleRecordButtonTapDoesNotToggleWhenPromptReturnsFalse() async throws {
        let coordinator = try makeCoordinator()
        let requester = TestPermissionRequester(result: false)
        let model = MenuBarSceneModel(
            coordinator: coordinator,
            permissionRequester: requester,
            permissionStateProvider: { .notYetRequested },
            clipboardWriter: { _ in },
            pasteInjector: { _ in .pasteAtCursor },
            openSettings: {},
            logger: SeshatLogger(category: SeshatLogCategory.ui)
        )

        await model.handleRecordButtonTap()

        let sessionState = await coordinator.state()
        let requestCount = await requester.callCount()
        XCTAssertEqual(model.permissionState, .denied)
        XCTAssertEqual(sessionState, .idle)
        XCTAssertEqual(requestCount, 1)
    }

    func testHandleRecordButtonTapRequestsOnboardingInsteadOfTogglingWhenPermissionDenied() async throws {
        let coordinator = try makeCoordinator()
        let requester = TestPermissionRequester(result: true)
        var openOnboardingRequestCount = 0
        let model = MenuBarSceneModel(
            coordinator: coordinator,
            permissionRequester: requester,
            permissionStateProvider: { .denied },
            clipboardWriter: { _ in },
            pasteInjector: { _ in .pasteAtCursor },
            openSettings: {},
            openOnboardingRequested: {
                openOnboardingRequestCount += 1
            },
            logger: SeshatLogger(category: SeshatLogCategory.ui)
        )

        await model.handleRecordButtonTap()

        let sessionState = await coordinator.state()
        let requestCount = await requester.callCount()
        XCTAssertEqual(sessionState, .idle)
        XCTAssertEqual(requestCount, 0)
        XCTAssertEqual(openOnboardingRequestCount, 1)
    }

    func testHandleRecordButtonTapRequestsOnboardingWhenCriticalPermissionGateFails() async throws {
        let coordinator = try makeCoordinator()
        let requester = TestPermissionRequester(result: true)
        var openOnboardingRequestCount = 0
        let model = MenuBarSceneModel(
            coordinator: coordinator,
            permissionRequester: requester,
            permissionStateProvider: { .granted },
            clipboardWriter: { _ in },
            pasteInjector: { _ in .pasteAtCursor },
            openSettings: {},
            areCriticalPermissionsGranted: { false },
            openOnboardingRequested: {
                openOnboardingRequestCount += 1
            },
            logger: SeshatLogger(category: SeshatLogCategory.ui)
        )

        await model.handleRecordButtonTap()

        let sessionState = await coordinator.state()
        let requestCount = await requester.callCount()
        XCTAssertEqual(sessionState, .idle)
        XCTAssertEqual(requestCount, 0)
        XCTAssertEqual(openOnboardingRequestCount, 1)
    }

    func testHandleRecordButtonTapRequestsOnboardingWhenOnboardingIncompleteAndMicrophoneNotYetRequested() async throws {
        let coordinator = try makeCoordinator()
        let requester = TestPermissionRequester(result: true)
        var openOnboardingRequestCount = 0
        let model = MenuBarSceneModel(
            coordinator: coordinator,
            permissionRequester: requester,
            permissionStateProvider: { .notYetRequested },
            clipboardWriter: { _ in },
            pasteInjector: { _ in .pasteAtCursor },
            openSettings: {},
            areCriticalPermissionsGranted: { false },
            openOnboardingRequested: {
                openOnboardingRequestCount += 1
            },
            logger: SeshatLogger(category: SeshatLogCategory.ui)
        )

        await model.handleRecordButtonTap()

        let sessionState = await coordinator.state()
        let requestCount = await requester.callCount()
        XCTAssertEqual(model.permissionState, .notYetRequested)
        XCTAssertEqual(sessionState, .idle)
        XCTAssertEqual(requestCount, 0)
        XCTAssertEqual(openOnboardingRequestCount, 1)
    }

    func testSettingsMenuActionRaisesOpenSettingsRequestedSignal() async throws {
        _ = NSApplication.shared
        let coordinator = try makeCoordinator()
        let model = MenuBarSceneModel(
            coordinator: coordinator,
            permissionRequester: TestPermissionRequester(result: true),
            permissionStateProvider: { .granted },
            clipboardWriter: { _ in },
            pasteInjector: { _ in .pasteAtCursor },
            openSettings: {},
            logger: SeshatLogger(category: SeshatLogCategory.ui)
        )
        var openSettingsRequestCount = 0
        let controller = StatusItemController(
            sceneModel: model,
            imPermissionProbe: GrantedInputMonitoringProbe(),
            openHistory: {},
            openSettings: {
                openSettingsRequestCount += 1
            }
        )

        controller.performMenuAction(.openSettings)

        XCTAssertEqual(openSettingsRequestCount, 1)
    }

    func testStartObservingPublishesRecordingAfterCoordinatorToggle() async throws {
        let coordinator = try makeCoordinator()
        let model = MenuBarSceneModel(
            coordinator: coordinator,
            permissionRequester: TestPermissionRequester(result: true),
            permissionStateProvider: { .granted },
            clipboardWriter: { _ in },
            pasteInjector: { _ in .pasteAtCursor },
            openSettings: {},
            logger: SeshatLogger(category: SeshatLogCategory.ui)
        )

        model.startObserving()
        await coordinator.toggle()
        await waitForState(.recording, on: model)

        XCTAssertEqual(model.state, .recording)
    }

    func testStartObservingIsIdempotent() async throws {
        let coordinator = try makeCoordinator()
        let model = MenuBarSceneModel(
            coordinator: coordinator,
            permissionRequester: TestPermissionRequester(result: true),
            permissionStateProvider: { .granted },
            clipboardWriter: { _ in },
            pasteInjector: { _ in .pasteAtCursor },
            openSettings: {},
            logger: SeshatLogger(category: SeshatLogCategory.ui)
        )

        model.startObserving()
        model.startObserving()

        XCTAssertEqual(model.observationTaskCreationCount, 1)
    }

    func testDeinitCancelsObservationTask() async throws {
        let coordinator = try makeCoordinator()
        let cancellationExpectation = expectation(description: "Observation task cancelled")
        var model: MenuBarSceneModel? = MenuBarSceneModel(
            coordinator: coordinator,
            permissionRequester: TestPermissionRequester(result: true),
            permissionStateProvider: { .granted },
            clipboardWriter: { _ in },
            pasteInjector: { _ in .pasteAtCursor },
            openSettings: {},
            onObservationCancelled: {
                cancellationExpectation.fulfill()
            },
            logger: SeshatLogger(category: SeshatLogCategory.ui)
        )
        weak var weakModel = model

        model?.startObserving()
        model = nil

        XCTAssertNil(weakModel)
        await fulfillment(of: [cancellationExpectation], timeout: 1.0)
    }

    func testIdleTransitionRefreshesLastResultTextFromCoordinator() async throws {
        let coordinator = try makeCoordinator()
        let model = MenuBarSceneModel(
            coordinator: coordinator,
            permissionRequester: TestPermissionRequester(result: true),
            permissionStateProvider: { .granted },
            clipboardWriter: { _ in },
            pasteInjector: { _ in .pasteAtCursor },
            openSettings: {},
            logger: SeshatLogger(category: SeshatLogCategory.ui)
        )

        model.startObserving()
        await coordinator.toggle()
        await waitForState(.recording, on: model)
        await coordinator.toggle()
        await waitForState(.idle, on: model)
        await waitForTranscriptText("Stub transcript.", on: model)

        XCTAssertEqual(model.lastResultText, "Stub transcript.")
    }

    func testIdleTransitionAutoPastesCleanedTranscriptExactlyOnce() async throws {
        let coordinator = try makeCoordinator()
        var pastedValues: [String] = []
        let model = MenuBarSceneModel(
            coordinator: coordinator,
            permissionRequester: TestPermissionRequester(result: true),
            permissionStateProvider: { .granted },
            clipboardWriter: { _ in },
            pasteInjector: { text in
                pastedValues.append(text)
                return .pasteAtCursor
            },
            openSettings: {},
            logger: SeshatLogger(category: SeshatLogCategory.ui)
        )

        model.startObserving()
        await coordinator.toggle()
        await waitForState(.recording, on: model)
        await coordinator.toggle()
        await waitForState(.idle, on: model)
        await waitForTranscriptText("Stub transcript.", on: model)
        await Task.yield()

        XCTAssertEqual(pastedValues, ["Stub transcript."])
    }

    func testIdleTransitionTriggersClipboardOnlyNoticeWhenPasteRouteSkipsPaste() async throws {
        let coordinator = try makeCoordinator()
        var pastedValues: [String] = []
        var clipboardOnlyNoticeCount = 0
        let model = MenuBarSceneModel(
            coordinator: coordinator,
            permissionRequester: TestPermissionRequester(result: true),
            permissionStateProvider: { .granted },
            clipboardWriter: { _ in },
            pasteInjector: { text in
                pastedValues.append(text)
                return .clipboardOnly(reason: .frontmostAppIsSeshat)
            },
            openSettings: {},
            onClipboardOnlyCopy: {
                clipboardOnlyNoticeCount += 1
            },
            logger: SeshatLogger(category: SeshatLogCategory.ui)
        )

        model.startObserving()
        await coordinator.toggle()
        await waitForState(.recording, on: model)
        await coordinator.toggle()
        await waitForState(.idle, on: model)
        await waitForTranscriptText("Stub transcript.", on: model)
        await Task.yield()

        XCTAssertEqual(pastedValues, ["Stub transcript."])
        XCTAssertEqual(clipboardOnlyNoticeCount, 1)
    }

    func testIdleTransitionDoesNotTriggerClipboardOnlyNoticeWhenPasteRouteTargetsCursor() async throws {
        let coordinator = try makeCoordinator()
        var clipboardOnlyNoticeCount = 0
        let model = MenuBarSceneModel(
            coordinator: coordinator,
            permissionRequester: TestPermissionRequester(result: true),
            permissionStateProvider: { .granted },
            clipboardWriter: { _ in },
            pasteInjector: { _ in
                .pasteAtCursor
            },
            openSettings: {},
            onClipboardOnlyCopy: {
                clipboardOnlyNoticeCount += 1
            },
            logger: SeshatLogger(category: SeshatLogCategory.ui)
        )

        model.startObserving()
        await coordinator.toggle()
        await waitForState(.recording, on: model)
        await coordinator.toggle()
        await waitForState(.idle, on: model)
        await waitForTranscriptText("Stub transcript.", on: model)
        await Task.yield()

        XCTAssertEqual(clipboardOnlyNoticeCount, 0)
    }

    func testSecondIdleTransitionDoesNotAutoPasteWhenTranscriptIsUnchanged() async throws {
        let coordinator = try makeCoordinator()
        var pastedValues: [String] = []
        let model = MenuBarSceneModel(
            coordinator: coordinator,
            permissionRequester: TestPermissionRequester(result: true),
            permissionStateProvider: { .granted },
            clipboardWriter: { _ in },
            pasteInjector: { text in
                pastedValues.append(text)
                return .pasteAtCursor
            },
            openSettings: {},
            logger: SeshatLogger(category: SeshatLogCategory.ui)
        )

        model.startObserving()
        await coordinator.toggle()
        await waitForState(.recording, on: model)
        await coordinator.toggle()
        await waitForState(.idle, on: model)
        await waitForTranscriptText("Stub transcript.", on: model)
        await Task.yield()

        await coordinator.toggle()
        await waitForState(.recording, on: model)
        await coordinator.toggle()
        await waitForState(.idle, on: model)
        await waitForTranscriptText("Stub transcript.", on: model)
        await Task.yield()

        XCTAssertEqual(pastedValues, ["Stub transcript."])
    }

    func testCopyLatestTranscriptWritesCurrentTranscriptToClipboard() async throws {
        let coordinator = try makeCoordinator()
        var copiedText: String?
        let model = MenuBarSceneModel(
            coordinator: coordinator,
            permissionRequester: TestPermissionRequester(result: true),
            permissionStateProvider: { .granted },
            clipboardWriter: { text in
                copiedText = text
            },
            pasteInjector: { _ in .pasteAtCursor },
            openSettings: {},
            logger: SeshatLogger(category: SeshatLogCategory.ui)
        )
        model.lastResultText = "copied transcript"

        model.copyLatestTranscript()

        XCTAssertEqual(copiedText, "copied transcript")
    }

    func testCopyLatestTranscriptDoesNothingWhenTranscriptIsMissing() async throws {
        let coordinator = try makeCoordinator()
        var copiedValues: [String] = []
        let model = MenuBarSceneModel(
            coordinator: coordinator,
            permissionRequester: TestPermissionRequester(result: true),
            permissionStateProvider: { .granted },
            clipboardWriter: { text in
                copiedValues.append(text)
            },
            pasteInjector: { _ in .pasteAtCursor },
            openSettings: {},
            logger: SeshatLogger(category: SeshatLogCategory.ui)
        )

        model.copyLatestTranscript()

        XCTAssertTrue(copiedValues.isEmpty)
    }

    func testOpenMicrophonePrivacySettingsInvokesInjectedSettingsAction() async throws {
        let coordinator = try makeCoordinator()
        var openSettingsCallCount = 0
        let model = MenuBarSceneModel(
            coordinator: coordinator,
            permissionRequester: TestPermissionRequester(result: true),
            permissionStateProvider: { .denied },
            clipboardWriter: { _ in },
            pasteInjector: { _ in .pasteAtCursor },
            openSettings: {
                openSettingsCallCount += 1
            },
            logger: SeshatLogger(category: SeshatLogCategory.ui)
        )

        model.openMicrophonePrivacySettings()

        XCTAssertEqual(openSettingsCallCount, 1)
    }

    func testStartObservingTracksPreparationProgressLifecycle() async throws {
        let transcriber = ProgressReportingTranscriber(result: makeResult())
        let coordinator = SessionCoordinator(
            capture: FakeAudioCapturing(),
            transcriber: transcriber,
            logger: SeshatLogger(category: SeshatLogCategory.ui)
        )
        let model = MenuBarSceneModel(
            coordinator: coordinator,
            permissionRequester: TestPermissionRequester(result: true),
            permissionStateProvider: { .granted },
            clipboardWriter: { _ in },
            pasteInjector: { _ in .pasteAtCursor },
            openSettings: {},
            logger: SeshatLogger(category: SeshatLogCategory.ui)
        )

        model.startObserving()

        transcriber.emit(
            .init(
                phase: .downloading,
                fractionCompleted: 0.42,
                receivedBytes: 42,
                expectedBytes: 100
            )
        )
        await waitUntil {
            model.preparationProgress?.phase == .downloading
        }
        XCTAssertEqual(model.preparationProgress?.fractionCompleted, 0.42)

        transcriber.emit(
            .init(
                phase: .loading,
                fractionCompleted: 1.0,
                receivedBytes: 0,
                expectedBytes: nil
            )
        )
        await waitUntil {
            model.preparationProgress?.phase == .loading
        }

        transcriber.emit(
            .init(
                phase: .finished,
                fractionCompleted: 1.0,
                receivedBytes: 100,
                expectedBytes: 100
            )
        )
        await waitUntil {
            model.preparationProgress == nil
        }
    }

    func testCanInstantiateSeshatAppWithCoordinatorAndPermissionRequester() async throws {
        let coordinator = try makeCoordinator()
        let app = SeshatApp(
            coordinator: coordinator,
            permissionRequester: TestPermissionRequester(result: true),
            permissionStateProvider: { .granted },
            clipboardWriter: { _ in },
            openSettings: {}
        )

        _ = app.body
        XCTAssertNotNil(app)
    }

    private func makeCoordinator() throws -> SessionCoordinator {
        SessionCoordinator(
            capture: FakeAudioCapturing(buffers: [try makeBuffer()]),
            transcriber: FakeTranscriber(result: makeResult()),
            logger: SeshatLogger(category: SeshatLogCategory.ui)
        )
    }

    private func makeBuffer() throws -> PCMBuffer {
        try PCMBuffer(samples: [0.25], timestamp: ContinuousClock().now)
    }

    private func makeResult() -> TranscriptionResult {
        TranscriptionResult(
            text: "Stub transcript.",
            audioDuration: .seconds(1),
            processingDuration: .milliseconds(200)
        )
    }

    private func waitForState(_ expected: SessionState, on model: MenuBarSceneModel) async {
        if model.state == expected {
            return
        }

        let expectation = expectation(description: "Wait for state \(String(describing: expected))")
        var didFulfill = false
        let cancellable = model.$state.sink { state in
            guard !didFulfill, state == expected else { return }
            didFulfill = true
            expectation.fulfill()
        }

        await fulfillment(of: [expectation], timeout: 1.0)
        cancellable.cancel()
    }

    private func waitForTranscriptText(_ expected: String, on model: MenuBarSceneModel) async {
        if model.lastResultText == expected {
            return
        }

        let expectation = expectation(description: "Wait for transcript text \(expected)")
        var didFulfill = false
        let cancellable = model.$lastResultText.sink { text in
            guard !didFulfill, text == expected else { return }
            didFulfill = true
            expectation.fulfill()
        }

        await fulfillment(of: [expectation], timeout: 1.0)
        cancellable.cancel()
    }

    private func waitUntil(
        maxIterations: Int = 500,
        condition: @escaping @MainActor () -> Bool
    ) async {
        for _ in 0..<maxIterations {
            if condition() {
                return
            }

            await Task.yield()
        }

        XCTFail("Timed out waiting for condition")
    }
}

private actor TestPermissionRequester: MicrophonePermissionRequesting {
    let result: Bool
    private var requestCount = 0

    init(result: Bool) {
        self.result = result
    }

    func requestAccess() async -> Bool {
        requestCount += 1
        return result
    }

    func callCount() -> Int {
        requestCount
    }
}

private struct GrantedInputMonitoringProbe: PermissionProbing {
    func checkInputMonitoring() -> InputMonitoringPermissionState {
        .granted
    }
}

private final class ProgressReportingTranscriber: @unchecked Sendable, Transcribing {
    private let relay = ProgressRelay()
    private let result: TranscriptionResult

    init(result: TranscriptionResult) {
        self.result = result
    }

    func prepare() async throws {}

    func modelDownloadProgress() -> AsyncStream<ModelDownloadProgress> {
        relay.stream()
    }

    func transcribe(_ audio: PCMBuffer) async throws -> TranscriptionResult {
        result
    }

    func transcribe(stream: AsyncThrowingStream<PCMBuffer, Error>) async throws -> TranscriptionResult {
        for try await _ in stream {}
        return result
    }

    func emit(_ progress: ModelDownloadProgress) {
        relay.emit(progress)
    }
}

private final class ProgressRelay: @unchecked Sendable {
    private let lock = NSLock()
    private var continuation: AsyncStream<ModelDownloadProgress>.Continuation?
    private var snapshot = ModelDownloadProgress(
        phase: .idle,
        fractionCompleted: 0,
        receivedBytes: 0,
        expectedBytes: nil
    )

    func stream() -> AsyncStream<ModelDownloadProgress> {
        AsyncStream { continuation in
            lock.lock()
            self.continuation = continuation
            let snapshot = self.snapshot
            lock.unlock()

            continuation.yield(snapshot)
            continuation.onTermination = { [weak self] _ in
                guard let self else { return }
                self.lock.lock()
                self.continuation = nil
                self.lock.unlock()
            }
        }
    }

    func emit(_ progress: ModelDownloadProgress) {
        lock.lock()
        snapshot = progress
        let continuation = continuation
        lock.unlock()
        continuation?.yield(progress)
    }
}

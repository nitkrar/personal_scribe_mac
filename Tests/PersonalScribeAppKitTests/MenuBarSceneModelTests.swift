import AppKit
import Combine
import XCTest
import PersonalScribeCore
import PersonalScribeSession
import PersonalScribeTestSupport
@testable import PersonalScribeAppKit

@MainActor
final class MenuBarSceneModelTests: XCTestCase {
    func testInitSeedsSnapshotPermissionsFromService() async throws {
        let permissionService = FakePermissionService(statuses: [
            .microphone: .denied,
            .inputMonitoring: .granted,
            .accessibility: .granted,
        ])
        let model = try makeModel(permissionService: permissionService)

        XCTAssertEqual(model.snapshot.permissions[.microphone], .denied)
    }

    func testRequestingAccessUpdatesSnapshotPermissionToDeniedWhenPromptReturnsFalse() async throws {
        let coordinator = try makeCoordinator()
        let permissionService = FakePermissionService(statuses: [
            .microphone: .pending,
            .inputMonitoring: .granted,
            .accessibility: .granted,
        ])
        permissionService.statusUpdatesAfterRequest[.microphone] = .denied
        permissionService.requestOutcomes[.microphone] = RequestOutcome(
            prompted: true,
            openedSettings: false,
            requiresRelaunch: false,
            finalStatus: .denied
        )
        let model = try makeModel(
            coordinator: coordinator,
            permissionService: permissionService
        )

        await model.handleRecordButtonTap()
        await waitUntil {
            model.snapshot.permissions[.microphone] == .denied
        }

        XCTAssertEqual(model.snapshot.permissions[.microphone], .denied)
        // The record path always
        // toggles the coordinator after a permission prompt, surfacing
        // failure via SessionCoordinator → .error rather than blocking the tap.
        let sessionState = await coordinator.state()
        let requestCount = permissionService.callCount(for: .microphone)
        XCTAssertEqual(sessionState, .recording)
        XCTAssertEqual(requestCount, 1)
    }

    func testHandleRecordButtonTapTogglesWhenPermissionAlreadyGranted() async throws {
        let coordinator = try makeCoordinator()
        let permissionService = FakePermissionService()
        let model = try makeModel(
            coordinator: coordinator,
            permissionService: permissionService
        )

        await model.handleRecordButtonTap()

        let sessionState = await coordinator.state()
        let requestCount = permissionService.callCount(for: .microphone)
        XCTAssertEqual(sessionState, .recording)
        XCTAssertEqual(requestCount, 0)
    }

    func testHandleRecordButtonTapRequestsAccessThenTogglesWhenPromptSucceeds() async throws {
        let coordinator = try makeCoordinator()
        let permissionService = FakePermissionService(statuses: [
            .microphone: .pending,
            .inputMonitoring: .granted,
            .accessibility: .granted,
        ])
        permissionService.statusUpdatesAfterRequest[.microphone] = .granted
        permissionService.requestOutcomes[.microphone] = RequestOutcome(
            prompted: true,
            openedSettings: false,
            requiresRelaunch: false,
            finalStatus: .granted
        )
        let model = try makeModel(
            coordinator: coordinator,
            permissionService: permissionService
        )

        await model.handleRecordButtonTap()
        await waitUntil {
            model.snapshot.permissions[.microphone] == .granted
        }

        let sessionState = await coordinator.state()
        let requestCount = permissionService.callCount(for: .microphone)
        XCTAssertEqual(model.snapshot.permissions[.microphone], .granted)
        XCTAssertEqual(sessionState, .recording)
        XCTAssertEqual(requestCount, 1)
    }

    func testHandleRecordButtonTapTogglesEvenWhenPermissionsDeniedOrIncomplete() async throws {
        // Regression guard for 2026-04-19 fix: menu-bar record path used
        // to route to openOnboardingRequested when mic was denied, IM
        // was denied, or onboarding was incomplete. User explicitly
        // asked for the gate removed — clicks should always try to
        // toggle the coordinator; failure surfaces through the session
        // state stream (OS mic prompt, coordinator.error etc.), not via
        // silent onboarding-window reroutes.
        let coordinator = try makeCoordinator()
        let permissionService = FakePermissionService(statuses: [
            .microphone: .denied,
            .inputMonitoring: .denied,
            .accessibility: .pending,
        ])
        let model = try makeModel(
            coordinator: coordinator,
            permissionService: permissionService
        )

        await model.handleRecordButtonTap()

        let sessionState = await coordinator.state()
        let requestCount = permissionService.callCount(for: .microphone)
        XCTAssertEqual(sessionState, .recording,
                       "Coordinator toggle must fire even when permissions are denied")
        XCTAssertEqual(requestCount, 0,
                       "Denied microphone state should not regress into a legacy prompt path")
    }

    func testStartObservingPublishesRecordingAfterCoordinatorToggle() async throws {
        let coordinator = try makeCoordinator()
        let model = try makeModel(coordinator: coordinator)

        model.startObserving()
        await coordinator.toggle()
        await waitForState(.recording, on: model)

        XCTAssertEqual(model.state, .recording)
    }

    func testStartObservingIsIdempotent() async throws {
        let coordinator = try makeCoordinator()
        let model = try makeModel(coordinator: coordinator)

        model.startObserving()
        model.startObserving()

        XCTAssertEqual(model.observationTaskCreationCount, 1)
    }

    func testDeinitCancelsObservationTask() async throws {
        let coordinator = try makeCoordinator()
        let cancellationExpectation = expectation(description: "Observation task cancelled")
        var model: MenuBarSceneModel? = try makeModel(
            coordinator: coordinator,
            onObservationCancelled: {
                cancellationExpectation.fulfill()
            }
        )
        weak var weakModel = model

        model?.startObserving()
        model = nil

        XCTAssertNil(weakModel)
        await fulfillment(of: [cancellationExpectation], timeout: 1.0)
    }

    func testIdleTransitionRefreshesLastResultTextFromCoordinator() async throws {
        let coordinator = try makeCoordinator()
        let model = try makeModel(coordinator: coordinator)

        model.startObserving()
        await coordinator.toggle()
        await waitForState(.recording, on: model)
        await coordinator.toggle()
        await waitForState(.idle, on: model)
        await waitForTranscriptText("Stub transcript.", on: model)

        XCTAssertEqual(model.lastResultText, "Stub transcript.")
    }

    func testIdleTransitionAutoDeliversTranscriptExactlyOnce() async throws {
        let coordinator = try makeCoordinator()
        let outputService = RecordingOutputService()
        let model = try makeModel(
            coordinator: coordinator,
            outputService: outputService
        )

        model.startObserving()
        await coordinator.toggle()
        await waitForState(.recording, on: model)
        await coordinator.toggle()
        await waitForState(.idle, on: model)
        await waitForTranscriptText("Stub transcript.", on: model)
        await waitUntil {
            outputService.deliveredTexts == ["Stub transcript."]
        }

        XCTAssertEqual(outputService.deliveredTexts, ["Stub transcript."])
    }

    func testIdleTransitionTriggersClipboardOnlyNoticeWhenOutputTargetsSelfFrontmost() async throws {
        let coordinator = try makeCoordinator()
        var clipboardOnlyNoticeCount = 0
        let outputService = RecordingOutputService(
            result: .delivered(target: .selfFrontmost, delivery: .clipboardOnly)
        )
        let model = try makeModel(
            coordinator: coordinator,
            outputService: outputService,
            onClipboardOnlyCopy: {
                clipboardOnlyNoticeCount += 1
            },
        )

        model.startObserving()
        await coordinator.toggle()
        await waitForState(.recording, on: model)
        await coordinator.toggle()
        await waitForState(.idle, on: model)
        await waitForTranscriptText("Stub transcript.", on: model)
        await waitUntil {
            outputService.deliveredTexts == ["Stub transcript."]
        }

        XCTAssertEqual(outputService.deliveredTexts, ["Stub transcript."])
        XCTAssertEqual(clipboardOnlyNoticeCount, 1)
    }

    func testIdleTransitionDoesNotTriggerClipboardOnlyNoticeWhenOutputTargetsFrontmostApp() async throws {
        let coordinator = try makeCoordinator()
        var clipboardOnlyNoticeCount = 0
        let outputService = RecordingOutputService(
            result: .delivered(target: .frontmostApp, delivery: .paste)
        )
        let model = try makeModel(
            coordinator: coordinator,
            outputService: outputService,
            onClipboardOnlyCopy: {
                clipboardOnlyNoticeCount += 1
            },
        )

        model.startObserving()
        await coordinator.toggle()
        await waitForState(.recording, on: model)
        await coordinator.toggle()
        await waitForState(.idle, on: model)
        await waitForTranscriptText("Stub transcript.", on: model)
        await waitUntil {
            outputService.deliveredTexts == ["Stub transcript."]
        }

        XCTAssertEqual(clipboardOnlyNoticeCount, 0)
    }

    func testSecondIdleTransitionDoesNotReDeliverWhenTranscriptIsUnchanged() async throws {
        let coordinator = try makeCoordinator()
        let outputService = RecordingOutputService()
        let model = try makeModel(
            coordinator: coordinator,
            outputService: outputService
        )

        model.startObserving()
        await coordinator.toggle()
        await waitForState(.recording, on: model)
        await coordinator.toggle()
        await waitForState(.idle, on: model)
        await waitForTranscriptText("Stub transcript.", on: model)
        await waitUntil {
            outputService.deliveredTexts == ["Stub transcript."]
        }

        await coordinator.toggle()
        await waitForState(.recording, on: model)
        await coordinator.toggle()
        await waitForState(.idle, on: model)
        await waitForTranscriptText("Stub transcript.", on: model)
        await Task.yield()

        XCTAssertEqual(outputService.deliveredTexts, ["Stub transcript."])
    }

    func testCopyLatestTranscriptWritesCurrentTranscriptToClipboard() async throws {
        let coordinator = try makeCoordinator()
        var copiedText: String?
        let model = try makeModel(
            coordinator: coordinator,
            clipboardWriter: { text in
                copiedText = text
            },
        )
        model.lastResultText = "copied transcript"

        model.copyLatestTranscript()

        XCTAssertEqual(copiedText, "copied transcript")
    }

    func testCopyLatestTranscriptDoesNothingWhenTranscriptIsMissing() async throws {
        let coordinator = try makeCoordinator()
        var copiedValues: [String] = []
        let model = try makeModel(
            coordinator: coordinator,
            clipboardWriter: { text in
                copiedValues.append(text)
            },
        )

        model.copyLatestTranscript()

        XCTAssertTrue(copiedValues.isEmpty)
    }

    func testOpenMicrophonePrivacySettingsInvokesInjectedSettingsAction() async throws {
        let coordinator = try makeCoordinator()
        var openSettingsCallCount = 0
        let permissionService = FakePermissionService(statuses: [
            .microphone: .denied,
            .inputMonitoring: .granted,
            .accessibility: .granted,
        ])
        let model = try makeModel(
            coordinator: coordinator,
            permissionService: permissionService,
            openSettings: {
                openSettingsCallCount += 1
            },
        )

        model.openMicrophonePrivacySettings()

        XCTAssertEqual(openSettingsCallCount, 1)
    }

    func testStartObservingTracksPreparationProgressLifecycle() async throws {
        let transcriber = ProgressReportingTranscriber(result: makeResult())
        let coordinator = SessionCoordinator(
            capture: FakeAudioCapturer(),
            transcriber: transcriber,
            logger: PersonalScribeLogger(category: PersonalScribeLogCategory.ui)
        )
        let model = try makeModel(coordinator: coordinator)

        model.startObserving()
        await Task.yield()

        // Layer 6 Stage 2 moved preparation progress behind
        // SessionCoordinator's rebroadcast stream, so the coordinator must
        // enter the prepare path before menu-bar observation can receive
        // transcriber snapshots.
        let prepareTask = Task {
            try await coordinator.prepareTranscriber()
        }
        defer {
            transcriber.releasePrepare()
        }

        await waitUntil {
            transcriber.prepareDidStart()
        }

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

        transcriber.releasePrepare()
        try await prepareTask.value
    }

    func testCanInstantiatePersonalScribeAppWithCoordinatorAndPermissionService() async throws {
        let coordinator = try makeCoordinator()
        let app = PersonalScribeApp(
            coordinator: coordinator,
            permissionService: FakePermissionService(),
            clipboardWriter: { _ in },
            openSettings: {}
        )

        _ = app.body
        XCTAssertNotNil(app)
    }

    private func makeCoordinator() throws -> SessionCoordinator {
        SessionCoordinator(
            capture: FakeAudioCapturer(buffers: [try makeBuffer()]),
            transcriber: FakeTranscriber(result: makeResult()),
            logger: PersonalScribeLogger(category: PersonalScribeLogCategory.ui)
        )
    }

    private func makeBuffer() throws -> PCMBuffer {
        // >= 1s of audio to clear SessionPipelineOrchestrator's `.shortExit` guard.
        try PCMBuffer(
            samples: Array(repeating: 0.25, count: 16_000),
            timestamp: ContinuousClock().now
        )
    }

    private func makeResult() -> TranscriptionResult {
        TranscriptionResult(
            text: "Stub transcript.",
            audioDuration: .seconds(1),
            processingDuration: .milliseconds(200)
        )
    }

    private func makeModel(
        coordinator: SessionCoordinator? = nil,
        permissionService: FakePermissionService = FakePermissionService(),
        clipboardWriter: @escaping @MainActor (String) -> Void = { _ in },
        outputService: any OutputService = RecordingOutputService(),
        openSettings: @escaping @MainActor () -> Void = {},
        onClipboardOnlyCopy: @escaping @MainActor () -> Void = {},
        onObservationCancelled: (@Sendable () -> Void)? = nil
    ) throws -> MenuBarSceneModel {
        let resolvedCoordinator = try coordinator ?? makeCoordinator()
        return MenuBarSceneModel(
            coordinator: resolvedCoordinator,
            clipboardWriter: clipboardWriter,
            outputService: outputService,
            openSettings: openSettings,
            permissionService: permissionService,
            onClipboardOnlyCopy: onClipboardOnlyCopy,
            onObservationCancelled: onObservationCancelled,
            logger: PersonalScribeLogger(category: PersonalScribeLogCategory.ui)
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

@MainActor
private final class FakePermissionService: PermissionService {
    @Published private(set) var statuses: [Permission: PermissionStatus]

    var requestOutcomes: [Permission: RequestOutcome] = [:]
    var statusUpdatesAfterRequest: [Permission: PermissionStatus] = [:]

    private var requestCounts: [Permission: Int] = [:]

    init(
        statuses: [Permission: PermissionStatus] = [
            .microphone: .granted,
            .inputMonitoring: .granted,
            .accessibility: .granted,
        ]
    ) {
        self.statuses = statuses
    }

    func status(for permission: Permission) -> PermissionStatus {
        statuses[permission] ?? .pending
    }

    func request(_ permission: Permission) async -> RequestOutcome {
        requestCounts[permission, default: 0] += 1
        if let updatedStatus = statusUpdatesAfterRequest[permission] {
            statuses[permission] = updatedStatus
        }

        return requestOutcomes[permission]
            ?? RequestOutcome(
                prompted: false,
                openedSettings: false,
                requiresRelaunch: false,
                finalStatus: status(for: permission)
            )
    }

    func statusSnapshot() -> [Permission: PermissionStatus] {
        statuses
    }

    func refresh() {}

    func systemSettingsDeepLink(for permission: Permission) -> URL {
        URL(string: "https://example.invalid/\(permission.rawValue)")!
    }

    func callCount(for permission: Permission) -> Int {
        requestCounts[permission, default: 0]
    }
}

private final class ProgressReportingTranscriber: @unchecked Sendable, Transcriber {
    private let lock = NSLock()
    private let relay = ProgressRelay()
    private let result: TranscriptionResult
    private var didStartPrepare = false
    private var prepareContinuation: CheckedContinuation<Void, Never>?
    private var releasePrepareEarly = false

    init(result: TranscriptionResult) {
        self.result = result
    }

    func prepare() async throws {
        let shouldReturnImmediately = lock.withLock { () -> Bool in
            didStartPrepare = true
            if releasePrepareEarly {
                releasePrepareEarly = false
                return true
            }
            return false
        }
        guard !shouldReturnImmediately else { return }

        await withCheckedContinuation { continuation in
            let shouldResumeImmediately = lock.withLock { () -> Bool in
                if releasePrepareEarly {
                    releasePrepareEarly = false
                    return true
                }

                prepareContinuation = continuation
                return false
            }

            if shouldResumeImmediately {
                continuation.resume()
            }
        }
    }

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

    func prepareDidStart() -> Bool {
        lock.withLock { didStartPrepare }
    }

    func releasePrepare() {
        let continuation = lock.withLock { () -> CheckedContinuation<Void, Never>? in
            if let prepareContinuation {
                self.prepareContinuation = nil
                return prepareContinuation
            }

            releasePrepareEarly = true
            return nil
        }

        continuation?.resume()
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

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
            pasteInjector: { _ in },
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
            pasteInjector: { _ in },
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
            pasteInjector: { _ in },
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
            pasteInjector: { _ in },
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
            pasteInjector: { _ in },
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

    func testHandleRecordButtonTapDoesNothingWhenPermissionDenied() async throws {
        let coordinator = try makeCoordinator()
        let requester = TestPermissionRequester(result: true)
        let model = MenuBarSceneModel(
            coordinator: coordinator,
            permissionRequester: requester,
            permissionStateProvider: { .denied },
            clipboardWriter: { _ in },
            pasteInjector: { _ in },
            openSettings: {},
            logger: SeshatLogger(category: SeshatLogCategory.ui)
        )

        await model.handleRecordButtonTap()

        let sessionState = await coordinator.state()
        let requestCount = await requester.callCount()
        XCTAssertEqual(sessionState, .idle)
        XCTAssertEqual(requestCount, 0)
    }

    func testStartObservingPublishesRecordingAfterCoordinatorToggle() async throws {
        let coordinator = try makeCoordinator()
        let model = MenuBarSceneModel(
            coordinator: coordinator,
            permissionRequester: TestPermissionRequester(result: true),
            permissionStateProvider: { .granted },
            clipboardWriter: { _ in },
            pasteInjector: { _ in },
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
            pasteInjector: { _ in },
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
            pasteInjector: { _ in },
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
            pasteInjector: { _ in },
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
            pasteInjector: { _ in },
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
            pasteInjector: { _ in },
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
            pasteInjector: { _ in },
            openSettings: {
                openSettingsCallCount += 1
            },
            logger: SeshatLogger(category: SeshatLogCategory.ui)
        )

        model.openMicrophonePrivacySettings()

        XCTAssertEqual(openSettingsCallCount, 1)
    }

    func testGrantedPermissionShowsRecordButtonModel() async throws {
        let coordinator = try makeCoordinator()
        let model = MenuBarSceneModel(
            coordinator: coordinator,
            permissionRequester: TestPermissionRequester(result: true),
            permissionStateProvider: { .granted },
            clipboardWriter: { _ in },
            pasteInjector: { _ in },
            openSettings: {},
            logger: SeshatLogger(category: SeshatLogCategory.ui)
        )

        XCTAssertEqual(model.recordButton, RecordButtonViewModel.make(from: .idle))
    }

    func testNotYetRequestedPermissionShowsGrantPrimaryCTA() {
        XCTAssertEqual(
            MenuBarScene.primaryActionTitle(for: .notYetRequested),
            "Grant microphone access"
        )
    }

    func testDeniedPermissionShowsSettingsPrimaryCTA() {
        XCTAssertEqual(
            MenuBarScene.primaryActionTitle(for: .denied),
            "Open System Settings"
        )
    }

    func testCanInstantiateSeshatAppWithCoordinatorAndPermissionRequester() async throws {
        let coordinator = try makeCoordinator()
        let app = SeshatApp(
            coordinator: coordinator,
            permissionRequester: TestPermissionRequester(result: true),
            permissionStateProvider: { .granted }
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

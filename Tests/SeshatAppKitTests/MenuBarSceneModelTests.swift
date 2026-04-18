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
            openSettings: {},
            logger: SeshatLogger(category: SeshatLogCategory.ui)
        )

        await model.handleRecordButtonTap()

        let sessionState = await coordinator.state()
        let requestCount = await requester.callCount()
        XCTAssertEqual(sessionState, .idle)
        XCTAssertEqual(requestCount, 0)
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
            text: "stub transcript",
            audioDuration: .seconds(1),
            processingDuration: .milliseconds(200)
        )
    }
}

private actor TestPermissionRequester: MicrophonePermissionRequesting {
    let result: Bool
    private var requestCount = 0

    func requestAccess() async -> Bool {
        requestCount += 1
        result
    }

    func callCount() -> Int {
        requestCount
    }
}

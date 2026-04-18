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

private struct TestPermissionRequester: MicrophonePermissionRequesting {
    let result: Bool

    func requestAccess() async -> Bool {
        result
    }
}

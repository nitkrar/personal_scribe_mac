import Combine
import XCTest
import SeshatCore
@testable import SeshatAppKit

@MainActor
final class MenuBarFlowIntegrationTests: XCTestCase {
    func testDevelopmentCompositionCreatesIdleTestingCoordinator() async {
        let coordinator = DevelopmentComposition.makeTestingSessionCoordinator()

        let state = await coordinator.state()
        XCTAssertEqual(state, .idle)
    }

    func testRecordStopTranscribeIdleFlowPublishesLatestResult() async {
        let coordinator = DevelopmentComposition.makeTestingSessionCoordinator()
        let model = MenuBarSceneModel(
            coordinator: coordinator,
            permissionRequester: IntegrationPermissionRequester(),
            permissionStateProvider: { .granted },
            clipboardWriter: { _ in },
            openSettings: {},
            logger: SeshatLogger(category: SeshatLogCategory.ui)
        )

        model.startObserving()
        await model.handleRecordButtonTap()
        await waitForState(.recording, on: model)

        let transitionExpectation = expectation(description: "Wait for transcribing then idle")
        var observedStates: [SessionState] = []
        var didFulfill = false
        let stateCancellable = model.$state.sink { state in
            observedStates.append(state)
            guard !didFulfill else { return }

            if observedStates.contains(.transcribing), state == .idle {
                didFulfill = true
                transitionExpectation.fulfill()
            }
        }

        await model.handleRecordButtonTap()
        await fulfillment(of: [transitionExpectation], timeout: 1.0)
        stateCancellable.cancel()
        await waitForTranscriptText("development transcript", on: model)

        XCTAssertEqual(model.lastResultText, "development transcript")
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

private struct IntegrationPermissionRequester: MicrophonePermissionRequesting {
    func requestAccess() async -> Bool {
        true
    }
}

import Combine
import Foundation
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
        await waitForTranscriptText("Development transcript.", on: model)

        XCTAssertEqual(model.lastResultText, "Development transcript.")
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

    // MARK: - Phase 1 Step 1.3b — menu bar install ordering regression

    /// `SeshatAppMain.init()` schedules `startupCoordinator.start()` through
    /// `Task { await Task.yield(); ... }` so SwiftUI finishes installing the
    /// `MenuBarExtra` status item before background startup work (which
    /// eventually installs `GlobalHotkeyMonitor`) runs on the MainActor. A
    /// regression that removed the wrapper — calling `start()` synchronously
    /// in init — would reintroduce the per-launch menu bar click freeze
    /// diagnosed in `1cb665c`. The hotkey monitor firing synchronously with
    /// init is the observable proxy for that reordering.
    func testStartupCoordinatorIsNotInvokedSynchronouslyDuringInit() async {
        let flag = HotkeyFireFlag()
        let sessionCoordinator = DevelopmentComposition.makeTestingSessionCoordinator()
        let startupCoordinator = AppStartupCoordinator(
            hotkeyDelay: .zero,
            prepareDelay: .zero,
            startHotkeyMonitor: { flag.mark() },
            prepareTranscriber: {},
            sleep: { _ in }
        )

        _ = SeshatAppMain(
            coordinator: sessionCoordinator,
            permissionRequester: IntegrationPermissionRequester(),
            startupCoordinator: startupCoordinator
        )

        XCTAssertFalse(
            flag.hasFired,
            "SeshatAppMain.init() appears to invoke startupCoordinator.start() "
                + "synchronously — Task.yield() wrapper may have been removed."
        )

        for _ in 0..<500 {
            if flag.hasFired { break }
            await Task.yield()
        }
        XCTAssertTrue(
            flag.hasFired,
            "startupCoordinator.start() was never invoked after SeshatAppMain.init()."
        )
    }
}

private struct IntegrationPermissionRequester: MicrophonePermissionRequesting {
    func requestAccess() async -> Bool {
        true
    }
}

private final class HotkeyFireFlag: @unchecked Sendable {
    private let lock = NSLock()
    private var fired = false

    func mark() {
        lock.withLock { fired = true }
    }

    var hasFired: Bool {
        lock.withLock { fired }
    }
}

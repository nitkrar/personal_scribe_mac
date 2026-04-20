import AppKit
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
        let outputService = RecordingOutputService()
        let model = MenuBarSceneModel(
            coordinator: coordinator,
            clipboardWriter: { _ in },
            outputService: outputService,
            openSettings: {},
            permissionService: FakePermissionService(),
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
        await waitUntil {
            outputService.deliveredTexts == ["Development transcript."]
        }

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

    /// Guards against re-introducing the per-launch menu bar click freeze
    /// diagnosed in `1cb665c`. The root cause was heavy startup work running
    /// synchronously inside `SeshatAppMain.init()`; the fix was extracting
    /// hotkey + transcriber-prepare into `AppStartupCoordinator`, whose
    /// `start()` schedules a background Task and returns immediately.
    ///
    /// This test asserts the fire-and-forget shape holds: after init returns,
    /// the hotkey-install callback has not yet fired. If a future refactor
    /// puts blocking MainActor work back into init (e.g. awaiting the hotkey
    /// install synchronously), the flag would be set before init returns.
    ///
    /// Caveat: this is a weak proxy. It does NOT observe MenuBarExtra
    /// installation directly, and it won't catch someone bypassing
    /// `AppStartupCoordinator` to install the hotkey monitor from init. The
    /// 20-click runtime sanity check (Step 1.3a) remains ground truth.
    func testStartupCoordinatorDoesNotBlockInitOnHotkeyInstall() async {
        let flag = HotkeyFireFlag()
        let sessionCoordinator = DevelopmentComposition.makeTestingSessionCoordinator()
        let startupCoordinator = AppStartupCoordinator(
            hotkeyDelay: .zero,
            prepareDelay: .zero,
            startHotkeyMonitor: { flag.mark() },
            prepareTranscriber: {},
            sleep: { _ in }
        )
        let defaults = makeCompletedOnboardingDefaults()
        let outputService = RecordingOutputService()

        _ = SeshatAppMain(
            coordinator: sessionCoordinator,
            permissionService: FakePermissionService(),
            clipboardWriter: { _ in },
            outputService: outputService,
            openSettings: {},
            overlayPanelBuilder: NoOpPanelBuilder(),
            defaults: defaults,
            startupCoordinator: startupCoordinator
        )

        XCTAssertFalse(
            flag.hasFired,
            "SeshatAppMain.init() appears to block on hotkey install — "
                + "AppStartupCoordinator should schedule the work and return."
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

    private func makeCompletedOnboardingDefaults() -> UserDefaults {
        let suiteName = "MenuBarFlowIntegrationTests.\(#function)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        Preference(
            key: "SeshatOnboardingCompleted",
            default: false,
            defaults: defaults
        ).persist(true)
        return defaults
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
    @Published private(set) var statuses: [Permission: PermissionStatus] = [
        .microphone: .granted,
        .inputMonitoring: .granted,
        .accessibility: .granted,
    ]

    func status(for permission: Permission) -> PermissionStatus {
        statuses[permission] ?? .pending
    }

    func request(_ permission: Permission) async -> RequestOutcome {
        RequestOutcome(
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

@MainActor
private struct NoOpPanelBuilder: PillOverlayPanelBuilding {
    func makePanel(
        model: PillOverlayViewModel,
        panelSize: NSSize,
        onTap: @escaping @MainActor () -> Void,
        onMouseDragged: @escaping @MainActor () -> Void,
        isTapEnabled: @escaping @MainActor () -> Bool
    ) -> any PillOverlayPaneling {
        RecordingOverlayPanel()
    }
}

@MainActor
private final class RecordingOverlayPanel: PillOverlayPaneling {
    var isVisible = false
    var frame = NSRect(x: 0, y: 0, width: 280, height: 60)

    func orderFrontRegardless() {
        isVisible = true
    }

    func orderOut(_ sender: Any?) {
        isVisible = false
    }

    func setFrameOrigin(_ point: NSPoint) {
        frame.origin = point
    }
}

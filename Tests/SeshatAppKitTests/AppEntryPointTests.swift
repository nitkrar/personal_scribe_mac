import AppKit
import XCTest
import SeshatCore
import SeshatSession
@testable import SeshatAppKit

@MainActor
final class AppEntryPointTests: XCTestCase {
    func testSeshatAppMainBuildsSceneModelFromComposition() async {
        let coordinator = DevelopmentComposition.makeTestingSessionCoordinator()
        let startupCoordinator = AppStartupCoordinator(
            startHotkeyMonitor: {},
            prepareTranscriber: {},
            sleep: { _ in }
        )
        let defaults = makeCompletedOnboardingDefaults()
        let outputService = RecordingOutputService()
        let entry = SeshatAppMain(
            coordinator: coordinator,
            permissionRequester: EntryPointPermissionRequester(),
            clipboardWriter: { _ in },
            outputService: outputService,
            openSettings: {},
            overlayPanelBuilder: NoOpPanelBuilder(),
            defaults: defaults,
            startupCoordinator: startupCoordinator
        )

        await coordinator.toggle()
        await coordinator.toggle()
        await waitUntil {
            outputService.deliveredTexts == ["Development transcript."]
        }

        XCTAssertTrue(entry.coordinator === coordinator)
        let state = await entry.coordinator.state()
        XCTAssertEqual(state, .idle)
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

    private func makeCompletedOnboardingDefaults() -> UserDefaults {
        let suiteName = "AppEntryPointTests.\(#function)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        OnboardingState.completed.persist(to: defaults)
        return defaults
    }
}

private struct EntryPointPermissionRequester: MicrophonePermissionRequesting {
    func requestAccess() async -> Bool { true }
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

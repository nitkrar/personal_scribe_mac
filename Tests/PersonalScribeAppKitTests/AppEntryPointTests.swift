import AppKit
import Combine
import XCTest
import PersonalScribeCore
import PersonalScribeSession
@testable import PersonalScribeAppKit

@MainActor
final class AppEntryPointTests: XCTestCase {
    func testPersonalScribeAppMainBuildsSceneModelFromComposition() async {
        let coordinator = DevelopmentComposition.makeTestingSessionCoordinator()
        let startupCoordinator = AppStartupCoordinator(
            startHotkeyMonitor: {},
            prepareTranscriber: {},
            sleep: { _ in }
        )
        let defaults = makeCompletedOnboardingDefaults()
        let outputService = RecordingOutputService()
        let entry = PersonalScribeAppMain(
            coordinator: coordinator,
            permissionService: FakePermissionService(),
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
        Preference(
            key: "SeshatOnboardingCompleted",
            default: false,
            defaults: defaults
        ).persist(true)
        return defaults
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

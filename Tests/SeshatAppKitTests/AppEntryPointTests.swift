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
        let entry = SeshatAppMain(
            coordinator: coordinator,
            permissionRequester: EntryPointPermissionRequester(),
            startupCoordinator: startupCoordinator
        )

        XCTAssertTrue(entry.coordinator === coordinator)
        let state = await entry.coordinator.state()
        XCTAssertEqual(state, .idle)
    }
}

private struct EntryPointPermissionRequester: MicrophonePermissionRequesting {
    func requestAccess() async -> Bool { true }
}

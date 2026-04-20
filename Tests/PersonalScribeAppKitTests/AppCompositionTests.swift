import Combine
import XCTest
import PersonalScribeCore
import PersonalScribeSession
@testable import PersonalScribeAppKit

@MainActor
final class AppCompositionTests: XCTestCase {
    func testMakePermissionServiceReturnsProductionType() {
        let service = AppComposition.makePermissionService()

        XCTAssertEqual(
            String(reflecting: type(of: service)),
            String(reflecting: AppKitPermissionService.self)
        )
    }

    func testMakeGlobalHotkeyMonitorAcceptsUnifiedPermissionService() {
        let monitor = AppComposition.makeGlobalHotkeyMonitor(
            permissionService: FakePermissionService(),
            coordinator: DevelopmentComposition.makeTestingSessionCoordinator()
        )

        XCTAssertFalse(monitor.isActive)
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

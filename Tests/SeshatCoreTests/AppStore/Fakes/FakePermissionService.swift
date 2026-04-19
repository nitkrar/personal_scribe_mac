import Combine
import Foundation
import SeshatCore

@MainActor
final class FakePermissionService: PermissionService {
    @Published private(set) var statuses: [Permission: PermissionStatus]

    var nextRefreshStatuses: [Permission: PermissionStatus]

    init(
        statuses: [Permission: PermissionStatus] = [
            .microphone: .pending,
            .inputMonitoring: .pending,
            .accessibility: .pending,
        ]
    ) {
        self.statuses = statuses
        self.nextRefreshStatuses = statuses
    }

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

    func refresh() {
        statuses = nextRefreshStatuses
    }

    func systemSettingsDeepLink(for permission: Permission) -> URL {
        URL(string: "https://example.invalid/\(permission.rawValue)")!
    }
}

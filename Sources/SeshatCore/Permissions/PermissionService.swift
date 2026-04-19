import Foundation

@MainActor
public protocol PermissionService: Sendable {
    func status(for permission: Permission) -> PermissionStatus
    func request(_ permission: Permission) async -> RequestOutcome
    func statusSnapshot() -> [Permission: PermissionStatus]
    func refresh()
    func systemSettingsDeepLink(for permission: Permission) -> URL
}

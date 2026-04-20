import AppKit
import Combine
import Foundation
import PersonalScribeCore

/// View model backing the unified-window Settings → Permissions sub-tab.
///
/// Observes a `PermissionService` and republishes its statuses so the
/// SwiftUI view can render the current state of Microphone, Input
/// Monitoring, and Accessibility permissions. `grantAccess` opens the
/// matching Privacy pane in System Settings via a deep link resolved
/// from `PermissionServiceAdapter.defaultSystemSettingsDeepLink(for:)`.
///
/// Reference: `plans/App UI design/Claude_Final_Bundle_Prompt.md` §3D —
/// "Permissions Sub-tab: Replaces the standalone Onboarding window."
@MainActor
final class PermissionsSubTabViewModel: ObservableObject {
    @Published private(set) var statuses: [Permission: PermissionStatus]

    private let permissionService: any PermissionService
    private let openURL: @MainActor (URL) -> Void
    private var permissionObservation: AnyCancellable?

    init(
        permissionService: any PermissionService,
        openURL: @escaping @MainActor (URL) -> Void = { url in
            NSWorkspace.shared.open(url)
        }
    ) {
        self.permissionService = permissionService
        self.openURL = openURL
        self.statuses = permissionService.statusSnapshot()
        self.permissionObservation = Self.observePermissionChanges(
            for: permissionService
        ) { [weak self] latest in
            self?.statuses = latest
        }
    }

    /// Read the current status for a given permission. Returns
    /// `.pending` when the service has not yet reported a value so the
    /// UI can render a sensible default rather than crashing on a
    /// dictionary miss.
    func status(for permission: Permission) -> PermissionStatus {
        statuses[permission] ?? .pending
    }

    /// Open the Privacy pane in System Settings for `permission`. Uses
    /// `PermissionServiceAdapter.defaultSystemSettingsDeepLink(for:)`
    /// for every case — that helper already covers all three
    /// permissions, including Accessibility.
    func grantAccess(for permission: Permission) {
        let url = PermissionServiceAdapter.defaultSystemSettingsDeepLink(
            for: permission
        )
        openURL(url)
    }

    private static func observePermissionChanges<Service: PermissionService>(
        for service: Service,
        onChange: @escaping @MainActor ([Permission: PermissionStatus]) -> Void
    ) -> AnyCancellable {
        // `objectWillChange` fires before the service mutates its
        // `@Published` storage, so defer the snapshot read to the next
        // runloop tick to pick up the post-change value. Mirrors the
        // pattern in `PermissionServiceAdapter` / `OnboardingViewModel`.
        service.objectWillChange.sink { _ in
            DispatchQueue.main.async {
                MainActor.assumeIsolated {
                    onChange(service.statusSnapshot())
                }
            }
        }
    }
}

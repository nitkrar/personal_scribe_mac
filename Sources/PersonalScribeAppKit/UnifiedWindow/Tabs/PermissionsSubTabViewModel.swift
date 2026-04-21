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

    /// Currently-bound recording hotkey, resolved from UserDefaults on
    /// init and re-resolved on `refresh()`. Drives the Input Monitoring
    /// row's subtitle so the displayed hint tracks the user's actual
    /// binding (mockup-gaps C.7, same plumbing pattern as Home tab's
    /// empty-state hint — see `HomeTabViewModel.recordingHotkey`).
    @Published private(set) var recordingHotkey: HotkeyPreference

    private let permissionService: any PermissionService
    private let defaults: UserDefaults
    private let openURL: @MainActor (URL) -> Void
    private var permissionObservation: AnyCancellable?

    init(
        permissionService: any PermissionService,
        defaults: UserDefaults = .standard,
        openURL: @escaping @MainActor (URL) -> Void = { url in
            NSWorkspace.shared.open(url)
        }
    ) {
        self.permissionService = permissionService
        self.defaults = defaults
        self.openURL = openURL
        self.statuses = permissionService.statusSnapshot()
        self.recordingHotkey = HotkeyPreference.resolve(from: defaults)
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

    /// Label text shown beside the status dot. Granted permissions
    /// render **Granted** (green); pending / denied permissions render
    /// **Required** (orange), which sits to the left of the
    /// "Grant Access" pill in the row's trailing cluster. Mockup:
    /// `plans/App UI design/final_settings_permissions_v2.png`.
    func statusLabel(for permission: Permission) -> String {
        switch status(for: permission) {
        case .granted:
            return "Granted"
        case .pending, .denied:
            return "Required"
        }
    }

    /// Subtitle text shown beneath each permission title. Copy matches
    /// the mockup verbatim
    /// (`plans/App UI design/final_settings_permissions_v2.png`). The
    /// Input Monitoring subtitle embeds the currently-bound recording
    /// hotkey hint; the microphone and accessibility subtitles are
    /// static mockup copy.
    func subtitle(for permission: Permission) -> String {
        switch permission {
        case .microphone:
            return "Required for voice recording"
        case .inputMonitoring:
            return inputMonitoringSubtitle
        case .accessibility:
            return "Required for paste injection"
        }
    }

    /// Dynamic subtitle for the Input Monitoring row. Embeds the live
    /// hotkey display string formatted by `HotkeyShortcutFormatter` so
    /// the copy tracks whatever binding the user has selected in
    /// Settings → Shortcuts.
    var inputMonitoringSubtitle: String {
        let hint = HotkeyShortcutFormatter.displayString(for: recordingHotkey)
        return "Required for global hotkey \(hint)"
    }

    /// Re-query TCC and publish the fresh snapshot. Call from
    /// `PermissionsSubTab.onAppear` so navigating to the tab always
    /// shows current state — the `didBecomeActiveNotification` observer
    /// in `AppKitPermissionService` misses the mic TCC prompt accept
    /// (system-modal; app never deactivates).
    func refresh() {
        permissionService.refresh()
        statuses = permissionService.statusSnapshot()
        // Re-resolve the hotkey so the Input Monitoring subtitle
        // reflects any change the user made in Settings → Shortcuts
        // while the tab was off-screen.
        recordingHotkey = HotkeyPreference.resolve(from: defaults)
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
        // pattern in `PermissionServiceAdapter`.
        service.objectWillChange.sink { _ in
            DispatchQueue.main.async {
                MainActor.assumeIsolated {
                    onChange(service.statusSnapshot())
                }
            }
        }
    }
}

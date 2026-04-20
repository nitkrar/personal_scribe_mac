import Combine
import Foundation
import PersonalScribeCore

enum OnboardingPermissionRowState: Equatable, Sendable {
    case pending
    case granted
    case openSettings
    case skipped
}

@MainActor
final class OnboardingViewModel: ObservableObject {
    @Published private(set) var microphoneState: OnboardingPermissionRowState = .pending
    @Published private(set) var inputMonitoringState: OnboardingPermissionRowState = .pending
    @Published private(set) var accessibilityState: OnboardingPermissionRowState = .pending
    @Published private(set) var isOnboardingComplete = false

    var canContinue: Bool {
        permissionStatuses[.microphone] == .granted
            && permissionStatuses[.inputMonitoring] == .granted
    }

    var showsAccessibilityWarning: Bool {
        accessibilityState == .openSettings || accessibilityState == .skipped
    }

    private let permissionService: any PermissionService
    private let persistCompletion: @MainActor () -> Void
    private var permissionObservation: AnyCancellable?
    private var permissionStatuses: [Permission: PermissionStatus]
    private var requestedPermissions: Set<Permission> = []
    private var didSkipAccessibility = false

    init(
        permissionService: (any PermissionService)? = nil,
        persistCompletion: @escaping @MainActor () -> Void = {}
    ) {
        let resolvedPermissionService = permissionService ?? AppKitPermissionService()
        self.permissionService = resolvedPermissionService
        self.persistCompletion = persistCompletion
        self.permissionStatuses = resolvedPermissionService.statusSnapshot()
        syncFromService()
        self.permissionObservation = Self.observePermissionChanges(for: resolvedPermissionService) { [weak self] in
            self?.syncFromService()
        }
    }

    private static func observePermissionChanges<Service: PermissionService>(
        for service: Service,
        onChange: @escaping @MainActor () -> Void
    ) -> AnyCancellable {
        service.objectWillChange.sink { _ in
            DispatchQueue.main.async {
                MainActor.assumeIsolated {
                    onChange()
                }
            }
        }
    }

    func requestMicrophoneAccess() async {
        await requestAccess(for: .microphone)
    }

    func requestInputMonitoringAccess() async {
        await requestAccess(for: .inputMonitoring)
    }

    func requestAccessibilityAccess() async {
        didSkipAccessibility = false
        await requestAccess(for: .accessibility)
    }

    func skipAccessibilityAccess() {
        didSkipAccessibility = true
        requestedPermissions.remove(.accessibility)
        updateDisplayStates()
    }

    func continueTapped() {
        guard canContinue else { return }

        if accessibilityState == .pending {
            didSkipAccessibility = true
            updateDisplayStates()
        }

        persistCompletion()
        isOnboardingComplete = true
    }

    func skipSetupTapped() {
        persistCompletion()
        isOnboardingComplete = true
    }

    func systemSettingsDeepLink(for permission: Permission) -> URL {
        permissionService.systemSettingsDeepLink(for: permission)
    }

    private func requestAccess(for permission: Permission) async {
        let outcome = await permissionService.request(permission)
        if outcome.finalStatus == .granted {
            requestedPermissions.remove(permission)
        } else {
            requestedPermissions.insert(permission)
        }
        syncFromService(overrides: [permission: outcome.finalStatus])
    }

    private func syncFromService(overrides: [Permission: PermissionStatus] = [:]) {
        permissionStatuses = permissionService.statusSnapshot()
        for (permission, status) in overrides {
            permissionStatuses[permission] = status
        }
        for permission in Permission.allCases where permissionStatuses[permission] == .granted {
            requestedPermissions.remove(permission)
        }
        if permissionStatuses[.accessibility] == .granted {
            didSkipAccessibility = false
        }
        updateDisplayStates()
    }

    private func updateDisplayStates() {
        microphoneState = rowState(for: .microphone)
        inputMonitoringState = rowState(for: .inputMonitoring)
        accessibilityState = rowState(for: .accessibility)
    }

    private func rowState(for permission: Permission) -> OnboardingPermissionRowState {
        let status = permissionStatuses[permission] ?? .pending

        if permission == .accessibility, didSkipAccessibility, status != .granted {
            return .skipped
        }

        switch status {
        case .pending:
            return requestedPermissions.contains(permission) ? .openSettings : .pending
        case .granted:
            return .granted
        case .denied:
            return .openSettings
        }
    }
}

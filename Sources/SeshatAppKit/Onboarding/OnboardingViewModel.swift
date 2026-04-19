import Combine
import Foundation
import SeshatCore

enum OnboardingPermissionOutcome: Equatable, Sendable {
    case pending
    case granted
    case denied
    case skipped
}

@MainActor
final class OnboardingViewModel: ObservableObject {
    @Published private(set) var microphoneOutcome: OnboardingPermissionOutcome = .pending
    @Published private(set) var inputMonitoringOutcome: OnboardingPermissionOutcome = .pending
    @Published private(set) var accessibilityOutcome: OnboardingPermissionOutcome = .pending
    @Published private(set) var isOnboardingComplete = false

    var canContinue: Bool {
        microphoneOutcome == .granted && inputMonitoringOutcome == .granted
    }

    var showsAccessibilityWarning: Bool {
        accessibilityOutcome == .denied || accessibilityOutcome == .skipped
    }

    private let permissionService: PermissionServiceAdapter
    private let persistCompletion: @MainActor () -> Void
    private var permissionObservation: AnyCancellable?
    private var didSkipAccessibility = false

    init(
        permissionService: PermissionServiceAdapter? = nil,
        permissionProbe: any OnboardingPermissionProbing = PermissionRequester(),
        persistCompletion: @escaping @MainActor () -> Void = {}
    ) {
        self.permissionService = permissionService
            ?? Self.makeCompatibilityPermissionService(permissionProbe: permissionProbe)
        self.persistCompletion = persistCompletion
        syncFromService()
        self.permissionObservation = self.permissionService.$statuses
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.syncFromService()
            }
    }

    func requestMicrophoneAccess() async {
        _ = await permissionService.request(.microphone)
        syncFromService()
    }

    func requestInputMonitoringAccess() async {
        _ = await permissionService.request(.inputMonitoring)
        syncFromService()
    }

    func requestAccessibilityAccess() async {
        didSkipAccessibility = false
        _ = await permissionService.request(.accessibility)
        syncFromService()
    }

    func skipAccessibilityAccess() {
        didSkipAccessibility = true
        accessibilityOutcome = .skipped
    }

    func continueTapped() {
        guard canContinue else { return }

        if accessibilityOutcome == .pending {
            accessibilityOutcome = .skipped
        }

        persistCompletion()
        isOnboardingComplete = true
    }

    func skipSetupTapped() {
        persistCompletion()
        isOnboardingComplete = true
    }

    private func syncFromService() {
        microphoneOutcome = permissionService.status(for: .microphone).onboardingOutcome
        inputMonitoringOutcome = permissionService.status(for: .inputMonitoring).onboardingOutcome

        let accessibilityStatus = permissionService.status(for: .accessibility)
        if accessibilityStatus == .granted {
            didSkipAccessibility = false
            accessibilityOutcome = .granted
        } else if didSkipAccessibility {
            accessibilityOutcome = .skipped
        } else {
            accessibilityOutcome = accessibilityStatus.onboardingOutcome
        }
    }

    private static func makeCompatibilityPermissionService(
        permissionProbe: any OnboardingPermissionProbing
    ) -> PermissionServiceAdapter {
        @MainActor
        final class StateBox {
            var statuses: [Permission: PermissionStatus] = [
                .microphone: .pending,
                .inputMonitoring: .pending,
                .accessibility: .pending,
            ]
        }

        let box = StateBox()
        return PermissionServiceAdapter(
            initialStatuses: box.statuses,
            statusReader: { permission in
                box.statuses[permission] ?? .pending
            },
            requester: { permission in
                let finalStatus: PermissionStatus
                switch permission {
                case .microphone:
                    finalStatus = await permissionProbe.requestMicrophoneAccess().unifiedPermissionStatus
                case .inputMonitoring:
                    finalStatus = await permissionProbe.requestInputMonitoringAccess().unifiedPermissionStatus
                case .accessibility:
                    finalStatus = await permissionProbe.requestAccessibilityAccess().unifiedPermissionStatus
                }

                box.statuses[permission] = finalStatus
                return RequestOutcome(
                    prompted: true,
                    openedSettings: false,
                    requiresRelaunch: permission == .inputMonitoring,
                    finalStatus: finalStatus
                )
            },
            refresher: {
                box.statuses
            }
        )
    }
}

private extension OnboardingPermissionOutcome {
    var unifiedPermissionStatus: PermissionStatus {
        switch self {
        case .pending, .skipped:
            return .pending
        case .granted:
            return .granted
        case .denied:
            return .denied
        }
    }
}

import Combine
import Foundation

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

    private let permissionProbe: any OnboardingPermissionProbing
    private let persistCompletion: @MainActor () -> Void

    init(
        permissionProbe: any OnboardingPermissionProbing = PermissionRequester(),
        persistCompletion: @escaping @MainActor () -> Void = {}
    ) {
        self.permissionProbe = permissionProbe
        self.persistCompletion = persistCompletion
    }

    func requestMicrophoneAccess() async {
        microphoneOutcome = await permissionProbe.requestMicrophoneAccess()
    }

    func requestInputMonitoringAccess() async {
        inputMonitoringOutcome = await permissionProbe.requestInputMonitoringAccess()
    }

    func requestAccessibilityAccess() async {
        accessibilityOutcome = await permissionProbe.requestAccessibilityAccess()
    }

    func skipAccessibilityAccess() {
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
}

import Combine
import Foundation

enum OnboardingPane: Equatable, Sendable {
    case welcome
    case microphone
    case inputMonitoring
    case accessibility
    case done
}

enum OnboardingPermissionOutcome: Equatable, Sendable {
    case pending
    case granted
    case denied
    case skipped

    var isResolved: Bool {
        switch self {
        case .pending:
            false
        case .granted, .denied, .skipped:
            true
        }
    }
}

@MainActor
final class OnboardingViewModel: ObservableObject {
    @Published private(set) var currentPane: OnboardingPane = .welcome
    @Published private(set) var microphoneOutcome: OnboardingPermissionOutcome = .pending
    @Published private(set) var inputMonitoringOutcome: OnboardingPermissionOutcome = .pending
    @Published private(set) var accessibilityOutcome: OnboardingPermissionOutcome = .pending
    @Published private(set) var isOnboardingComplete = false

    private let permissionProbe: any OnboardingPermissionProbing

    init(permissionProbe: any OnboardingPermissionProbing = PermissionRequester()) {
        self.permissionProbe = permissionProbe
    }

    func advance() {
        switch currentPane {
        case .welcome:
            currentPane = nextUnresolvedPane()
        case .microphone where microphoneOutcome.isResolved:
            currentPane = nextUnresolvedPane()
        case .inputMonitoring where inputMonitoringOutcome.isResolved:
            currentPane = nextUnresolvedPane()
        case .accessibility where accessibilityOutcome.isResolved:
            currentPane = nextUnresolvedPane()
        case .done:
            break
        default:
            return
        }

        isOnboardingComplete = (currentPane == .done)
    }

    func requestCurrentPermission() async {
        switch currentPane {
        case .welcome:
            advance()
        case .microphone:
            microphoneOutcome = await permissionProbe.requestMicrophoneAccess()
            if microphoneOutcome == .granted {
                advance()
            }
        case .inputMonitoring:
            inputMonitoringOutcome = await permissionProbe.requestInputMonitoringAccess()
            if inputMonitoringOutcome == .granted {
                advance()
            }
        case .accessibility:
            accessibilityOutcome = await permissionProbe.requestAccessibilityAccess()
            if accessibilityOutcome == .granted {
                advance()
            }
        case .done:
            break
        }
    }

    func skipCurrentPermission() {
        switch currentPane {
        case .welcome:
            advance()
        case .microphone:
            microphoneOutcome = .skipped
            advance()
        case .inputMonitoring:
            inputMonitoringOutcome = .skipped
            advance()
        case .accessibility:
            accessibilityOutcome = .skipped
            advance()
        case .done:
            break
        }
    }

    private func nextUnresolvedPane() -> OnboardingPane {
        if !microphoneOutcome.isResolved {
            return .microphone
        }

        if !inputMonitoringOutcome.isResolved {
            return .inputMonitoring
        }

        if !accessibilityOutcome.isResolved {
            return .accessibility
        }

        return .done
    }
}

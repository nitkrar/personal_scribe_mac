import Combine
import Foundation
import SeshatCore

@MainActor
final class PermissionServiceAdapter: PermissionService {
    @Published private(set) var statuses: [Permission: PermissionStatus]

    private let statusReader: @MainActor (Permission) -> PermissionStatus
    private let requester: @MainActor (Permission) async -> RequestOutcome
    private let refresher: @MainActor () -> [Permission: PermissionStatus]
    private let deepLinkProvider: @MainActor (Permission) -> URL
    private var observation: AnyCancellable?

    init<Service: PermissionService>(wrapping service: Service) {
        self.statuses = service.statusSnapshot()
        self.statusReader = { permission in
            service.status(for: permission)
        }
        self.requester = { permission in
            await service.request(permission)
        }
        self.refresher = {
            service.statusSnapshot()
        }
        self.deepLinkProvider = { permission in
            service.systemSettingsDeepLink(for: permission)
        }
        self.observation = service.objectWillChange.sink { [weak self] _ in
            self?.statuses = service.statusSnapshot()
        }
    }

    init(
        initialStatuses: [Permission: PermissionStatus],
        statusReader: @escaping @MainActor (Permission) -> PermissionStatus,
        requester: @escaping @MainActor (Permission) async -> RequestOutcome,
        refresher: @escaping @MainActor () -> [Permission: PermissionStatus],
        deepLinkProvider: @escaping @MainActor (Permission) -> URL = PermissionServiceAdapter.defaultSystemSettingsDeepLink(for:)
    ) {
        self.statuses = initialStatuses
        self.statusReader = statusReader
        self.requester = requester
        self.refresher = refresher
        self.deepLinkProvider = deepLinkProvider
    }

    func status(for permission: Permission) -> PermissionStatus {
        statusReader(permission)
    }

    func request(_ permission: Permission) async -> RequestOutcome {
        let outcome = await requester(permission)
        refresh()
        if statuses[permission] == nil {
            statuses[permission] = outcome.finalStatus
        }
        return outcome
    }

    func statusSnapshot() -> [Permission: PermissionStatus] {
        refresher()
    }

    func refresh() {
        statuses = refresher()
    }

    func systemSettingsDeepLink(for permission: Permission) -> URL {
        deepLinkProvider(permission)
    }

    static func defaultSystemSettingsDeepLink(for permission: Permission) -> URL {
        switch permission {
        case .microphone:
            return URL(
                string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Microphone"
            )!
        case .inputMonitoring:
            return URL(
                string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ListenEvent"
            )!
        case .accessibility:
            return URL(
                string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility"
            )!
        }
    }
}

extension MicrophonePermissionState {
    var unifiedPermissionStatus: PermissionStatus {
        switch self {
        case .notYetRequested:
            return .pending
        case .granted:
            return .granted
        case .denied:
            return .denied
        }
    }
}

extension InputMonitoringPermissionState {
    var unifiedPermissionStatus: PermissionStatus {
        switch self {
        case .notDetermined:
            return .pending
        case .granted:
            return .granted
        case .denied:
            return .denied
        }
    }
}

extension PermissionStatus {
    var microphonePermissionState: MicrophonePermissionState {
        switch self {
        case .pending:
            return .notYetRequested
        case .granted:
            return .granted
        case .denied:
            return .denied
        }
    }

    var onboardingOutcome: OnboardingPermissionOutcome {
        switch self {
        case .pending:
            return .pending
        case .granted:
            return .granted
        case .denied:
            return .denied
        }
    }
}

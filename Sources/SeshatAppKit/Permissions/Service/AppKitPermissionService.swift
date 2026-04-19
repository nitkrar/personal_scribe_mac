import AVFoundation
import Combine
import Foundation
import SeshatCore

@MainActor
final class AppKitPermissionService: ObservableObject, PermissionService {
    @Published private(set) var statuses: [Permission: PermissionStatus] = [:]

    private let microphone: MicrophonePermissionClient
    private let inputMonitoring: InputMonitoringPermissionClient
    private let accessibility: AccessibilityPermissionClient
    private let urlOpener: PermissionURLOpener
    private var activationObservation: ActivationObservation!

    init(
        microphone: MicrophonePermissionClient = .live,
        inputMonitoring: InputMonitoringPermissionClient = .live,
        accessibility: AccessibilityPermissionClient = .live,
        urlOpener: PermissionURLOpener = .live,
        activationObserver: ApplicationActivationObserver = .live
    ) {
        self.microphone = microphone
        self.inputMonitoring = inputMonitoring
        self.accessibility = accessibility
        self.urlOpener = urlOpener
        self.activationObservation = activationObserver.observe { [weak self] in
            self?.refresh()
        }
        refresh()
    }

    func status(for permission: Permission) -> PermissionStatus {
        switch permission {
        case .microphone:
            return mapMicrophoneStatus(microphone.authorizationStatus())
        case .inputMonitoring:
            return inputMonitoring.status()
        case .accessibility:
            return accessibility.isTrusted() ? .granted : .pending
        }
    }

    func request(_ permission: Permission) async -> RequestOutcome {
        switch permission {
        case .microphone:
            return await requestMicrophone()
        case .inputMonitoring:
            return requestInputMonitoring()
        case .accessibility:
            return requestAccessibility()
        }
    }

    func statusSnapshot() -> [Permission: PermissionStatus] {
        Dictionary(
            uniqueKeysWithValues: Permission.allCases.map { permission in
                (permission, status(for: permission))
            }
        )
    }

    func refresh() {
        statuses = statusSnapshot()
    }

    func systemSettingsDeepLink(for permission: Permission) -> URL {
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

    isolated deinit {
        activationObservation.cancel()
    }

    private func requestMicrophone() async -> RequestOutcome {
        switch status(for: .microphone) {
        case .granted:
            return refreshedOutcome(for: .microphone)
        case .pending:
            _ = await microphone.requestAccess()
            return refreshedOutcome(
                for: .microphone,
                prompted: true
            )
        case .denied:
            urlOpener.open(systemSettingsDeepLink(for: .microphone))
            return refreshedOutcome(
                for: .microphone,
                openedSettings: true
            )
        }
    }

    private func requestInputMonitoring() -> RequestOutcome {
        switch status(for: .inputMonitoring) {
        case .granted:
            return refreshedOutcome(for: .inputMonitoring)
        case .pending:
            _ = inputMonitoring.requestAccess()
            return refreshedOutcome(
                for: .inputMonitoring,
                prompted: true,
                requiresRelaunch: true
            )
        case .denied:
            urlOpener.open(systemSettingsDeepLink(for: .inputMonitoring))
            return refreshedOutcome(
                for: .inputMonitoring,
                openedSettings: true,
                requiresRelaunch: true
            )
        }
    }

    private func requestAccessibility() -> RequestOutcome {
        switch status(for: .accessibility) {
        case .granted:
            return refreshedOutcome(for: .accessibility)
        case .pending, .denied:
            _ = accessibility.requestAccess()
            return refreshedOutcome(
                for: .accessibility,
                prompted: true
            )
        }
    }

    private func refreshedOutcome(
        for permission: Permission,
        prompted: Bool = false,
        openedSettings: Bool = false,
        requiresRelaunch: Bool = false
    ) -> RequestOutcome {
        refresh()
        let finalStatus = statuses[permission] ?? status(for: permission)
        return RequestOutcome(
            prompted: prompted,
            openedSettings: openedSettings,
            requiresRelaunch: requiresRelaunch,
            finalStatus: finalStatus
        )
    }

    private func mapMicrophoneStatus(_ status: AVAuthorizationStatus) -> PermissionStatus {
        switch status {
        case .notDetermined:
            return .pending
        case .authorized:
            return .granted
        case .denied, .restricted:
            return .denied
        @unknown default:
            return .denied
        }
    }
}

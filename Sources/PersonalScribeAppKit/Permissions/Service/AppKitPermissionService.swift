import AVFoundation
import Combine
import Foundation
import PersonalScribeCore

@MainActor
final class AppKitPermissionService: ObservableObject, PermissionService {
    @Published private(set) var statuses: [Permission: PermissionStatus] = [:]

    private let microphone: MicrophonePermissionClient
    private let accessibility: AccessibilityPermissionClient
    private let urlOpener: PermissionURLOpener
    private var activationObservation: ActivationObservation!
    private var pollObservation: ActivationObservation!
    private let logStatusChange: @MainActor (String) -> Void
    private var hasLoggedInitialStatuses = false

    init(
        microphone: MicrophonePermissionClient = .live,
        accessibility: AccessibilityPermissionClient = .live,
        urlOpener: PermissionURLOpener = .live,
        activationObserver: ApplicationActivationObserver = .live,
        statusPoller: ApplicationActivationObserver = .polling(every: 1),
        logStatusChange: @escaping @MainActor (String) -> Void = { _ in }
    ) {
        self.microphone = microphone
        self.accessibility = accessibility
        self.urlOpener = urlOpener
        self.logStatusChange = logStatusChange
        self.activationObservation = activationObserver.observe { [weak self] in
            self?.refresh()
        }
        // Activation alone misses grants made through system-modal
        // prompts (the mic prompt raised by the audio engine never
        // deactivates the app) and System Settings toggles while a
        // Ninimma window stays key. The poll catches both; `refresh()`
        // only publishes on change, so idle ticks cost three status
        // reads and nothing else.
        self.pollObservation = statusPoller.observe { [weak self] in
            self?.refresh()
        }
        refresh()
    }

    func status(for permission: Permission) -> PermissionStatus {
        switch permission {
        case .microphone:
            return mapMicrophoneStatus(microphone.authorizationStatus())
        case .accessibility:
            return accessibility.isTrusted() ? .granted : .pending
        }
    }

    func request(_ permission: Permission) async -> RequestOutcome {
        switch permission {
        case .microphone:
            return await requestMicrophone()
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
        let snapshot = statusSnapshot()
        logTransitions(from: statuses, to: snapshot)
        guard snapshot != statuses else { return }
        statuses = snapshot
    }

    /// Diagnostics for intermittent TCC behavior (e.g. a macOS
    /// Accessibility prompt while the toggle is already on): one line
    /// with the launch state, then one line per actual transition —
    /// never per poll tick.
    private func logTransitions(
        from previous: [Permission: PermissionStatus],
        to current: [Permission: PermissionStatus]
    ) {
        guard hasLoggedInitialStatuses else {
            hasLoggedInitialStatuses = true
            let summary = Permission.allCases
                .map { "\($0.rawValue)=\(current[$0] ?? .pending)" }
                .joined(separator: " ")
            logStatusChange("permission_status_initial — \(summary)")
            return
        }
        let changes = Permission.allCases.compactMap { permission -> String? in
            let before = previous[permission] ?? .pending
            let after = current[permission] ?? .pending
            return before == after ? nil : "\(permission.rawValue)=\(before)→\(after)"
        }
        guard !changes.isEmpty else { return }
        logStatusChange("permission_status_changed — \(changes.joined(separator: " "))")
    }

    func systemSettingsDeepLink(for permission: Permission) -> URL {
        switch permission {
        case .microphone:
            return URL(
                string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Microphone"
            )!
        case .accessibility:
            return URL(
                string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility"
            )!
        }
    }

    isolated deinit {
        activationObservation.cancel()
        pollObservation.cancel()
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

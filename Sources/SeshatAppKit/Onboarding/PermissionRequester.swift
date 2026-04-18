import AVFoundation
import ApplicationServices
import Foundation
import SeshatCore
#if canImport(IOKit)
import IOKit.hid
#endif

protocol OnboardingPermissionProbing: Sendable {
    func requestMicrophoneAccess() async -> OnboardingPermissionOutcome
    func requestInputMonitoringAccess() async -> OnboardingPermissionOutcome
    func requestAccessibilityAccess() async -> OnboardingPermissionOutcome
}

actor PermissionRequester: OnboardingPermissionProbing {
    func requestMicrophoneAccess() async -> OnboardingPermissionOutcome {
        switch AVCaptureDevice.authorizationStatus(for: .audio) {
        case .authorized:
            return .granted
        case .denied, .restricted:
            return .denied
        case .notDetermined:
            let granted = await withCheckedContinuation { continuation in
                AVCaptureDevice.requestAccess(for: .audio) { didGrant in
                    continuation.resume(returning: didGrant)
                }
            }
            return granted ? .granted : .denied
        @unknown default:
            return .denied
        }
    }

    func requestInputMonitoringAccess() async -> OnboardingPermissionOutcome {
        requestInputMonitoringState()
    }

    func requestAccessibilityAccess() async -> OnboardingPermissionOutcome {
        let options = ["AXTrustedCheckOptionPrompt": true] as CFDictionary
        return AXIsProcessTrustedWithOptions(options) ? .granted : .denied
    }

    private func requestInputMonitoringState() -> OnboardingPermissionOutcome {
#if canImport(IOKit)
        if IOHIDRequestAccess(kIOHIDRequestTypeListenEvent) {
            return .granted
        }

        return map(IOHIDPermissionProbe().checkInputMonitoring())
#else
        return .denied
#endif
    }

    private func map(_ state: InputMonitoringPermissionState) -> OnboardingPermissionOutcome {
        switch state {
        case .granted:
            .granted
        case .denied, .notDetermined:
            .denied
        }
    }
}

import AVFoundation
import AppKit
import ApplicationServices
import Foundation
import PersonalScribeCore
#if canImport(IOKit)
import IOKit.hid
#endif

struct MicrophonePermissionClient {
    let authorizationStatus: @MainActor () -> AVAuthorizationStatus
    let requestAccess: @MainActor () async -> Bool

    static var live: Self {
        Self(
            authorizationStatus: {
                // `AVCaptureDevice.authorizationStatus` caches its first
                // answer per process: a grant made through the prompt the
                // audio engine raises (first recording) is never reflected
                // until relaunch. `AVAudioApplication.recordPermission`
                // reads the live grant, so either reporting granted wins.
                let captureStatus = AVCaptureDevice.authorizationStatus(for: .audio)
                if captureStatus != .authorized,
                   AVAudioApplication.shared.recordPermission == .granted {
                    return .authorized
                }
                return captureStatus
            },
            requestAccess: {
                await withCheckedContinuation { continuation in
                    AVCaptureDevice.requestAccess(for: .audio) { granted in
                        continuation.resume(returning: granted)
                    }
                }
            }
        )
    }
}

struct InputMonitoringPermissionClient {
    let status: @MainActor () -> PermissionStatus
    let requestAccess: @MainActor () -> Bool

    static var live: Self {
        Self(
            status: {
#if canImport(IOKit)
                switch IOHIDCheckAccess(kIOHIDRequestTypeListenEvent) {
                case kIOHIDAccessTypeGranted:
                    return .granted
                case kIOHIDAccessTypeDenied:
                    return .denied
                default:
                    return .pending
                }
#else
                return .pending
#endif
            },
            requestAccess: {
#if canImport(IOKit)
                return IOHIDRequestAccess(kIOHIDRequestTypeListenEvent)
#else
                return false
#endif
            }
        )
    }
}

struct AccessibilityPermissionClient {
    let isTrusted: @MainActor () -> Bool
    let requestAccess: @MainActor () -> Bool

    static var live: Self {
        Self(
            isTrusted: {
                AXIsProcessTrusted()
            },
            requestAccess: {
                let options = ["AXTrustedCheckOptionPrompt": true] as CFDictionary
                return AXIsProcessTrustedWithOptions(options)
            }
        )
    }
}

struct PermissionURLOpener {
    let open: @MainActor (URL) -> Void

    static var live: Self {
        Self(open: { url in
            _ = NSWorkspace.shared.open(url)
        })
    }
}

struct ActivationObservation {
    let cancel: @MainActor () -> Void
}

struct ApplicationActivationObserver {
    let observe: @MainActor (@escaping @MainActor () -> Void) -> ActivationObservation

    /// Repeating main-runloop timer with the same observe/cancel shape,
    /// used as a refresh trigger for state the OS doesn't notify about.
    static func polling(every interval: TimeInterval) -> Self {
        Self(observe: { handler in
            let timer = Timer.scheduledTimer(withTimeInterval: interval, repeats: true) { _ in
                MainActor.assumeIsolated {
                    handler()
                }
            }
            return ActivationObservation(cancel: {
                timer.invalidate()
            })
        })
    }

    static var live: Self {
        Self(observe: { handler in
            let center = NotificationCenter.default
            let token = center.addObserver(
                forName: NSApplication.didBecomeActiveNotification,
                object: nil,
                queue: .main
            ) { _ in
                MainActor.assumeIsolated {
                    handler()
                }
            }

            return ActivationObservation(cancel: {
                center.removeObserver(token)
            })
        })
    }
}

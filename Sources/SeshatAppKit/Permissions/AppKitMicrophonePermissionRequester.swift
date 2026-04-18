import AVFoundation
import SeshatCore

@MainActor
struct AppKitMicrophonePermissionRequester: MicrophonePermissionRequesting {
    private let statusProvider: @MainActor () -> AVAuthorizationStatus
    private let accessRequester: @MainActor () async -> Bool

    init() {
        self.init(
            statusProvider: { AVCaptureDevice.authorizationStatus(for: .audio) },
            accessRequester: {
                await withCheckedContinuation { continuation in
                    AVCaptureDevice.requestAccess(for: .audio) { granted in
                        continuation.resume(returning: granted)
                    }
                }
            }
        )
    }

    init(
        statusProvider: @escaping @MainActor () -> AVAuthorizationStatus,
        accessRequester: @escaping @MainActor () async -> Bool
    ) {
        self.statusProvider = statusProvider
        self.accessRequester = accessRequester
    }

    func requestAccess() async -> Bool {
        switch currentState() {
        case .granted:
            true
        case .denied:
            false
        case .notYetRequested:
            await accessRequester()
        }
    }

    func currentState() -> MicrophonePermissionState {
        map(statusProvider())
    }

    private func map(_ status: AVAuthorizationStatus) -> MicrophonePermissionState {
        switch status {
        case .notDetermined:
            .notYetRequested
        case .authorized:
            .granted
        case .denied, .restricted:
            .denied
        @unknown default:
            .denied
        }
    }
}

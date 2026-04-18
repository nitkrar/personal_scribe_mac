import Foundation
import SeshatAudio
import SeshatCore
import SeshatSession
import SeshatTranscription

@MainActor
public enum AppComposition {
    public static let sessionCoordinator: SessionCoordinator = {
        let logger = SeshatLogger(category: SeshatLogCategory.session)
        let capture = AVAudioCaptureService(
            logger: SeshatLogger(category: SeshatLogCategory.audio)
        )
        let transcriber = FluidAudioTranscriber(
            logger: SeshatLogger(category: SeshatLogCategory.transcription)
        )

        return SessionCoordinator(
            capture: capture,
            transcriber: transcriber,
            logger: logger
        )
    }()

    public static func makeSessionCoordinator() -> SessionCoordinator {
        sessionCoordinator
    }

    public static func makeGlobalHotkeyMonitor(
        coordinator: SessionCoordinator = AppComposition.sessionCoordinator
    ) -> GlobalHotkeyMonitor {
        GlobalHotkeyMonitor(onTrigger: {
            Task {
                await coordinator.toggle()
            }
        })
    }

    @MainActor
    public static let hotkeyMonitor: GlobalHotkeyMonitor = makeGlobalHotkeyMonitor()

    public static func makeMicrophonePermissionRequester() -> any MicrophonePermissionRequesting {
        AppKitMicrophonePermissionRequester()
    }
}

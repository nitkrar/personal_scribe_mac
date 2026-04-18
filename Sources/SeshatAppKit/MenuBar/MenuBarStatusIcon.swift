import Foundation
import SeshatCore

@MainActor
struct MenuBarStatusIcon: Equatable {
    let systemImageName: String
    let accessibilityLabel: String
    let showsActiveAccent: Bool

    static func make(
        sessionState: SessionState,
        permissionState: MicrophonePermissionState
    ) -> MenuBarStatusIcon {
        switch permissionState {
        case .denied:
            MenuBarStatusIcon(
                systemImageName: "mic.slash",
                accessibilityLabel: "Microphone permission denied",
                showsActiveAccent: false
            )
        case .granted:
            switch sessionState {
            case .idle:
                MenuBarStatusIcon(
                    systemImageName: "mic",
                    accessibilityLabel: "Idle",
                    showsActiveAccent: false
                )
            case .recording:
                MenuBarStatusIcon(
                    systemImageName: "mic.fill",
                    accessibilityLabel: "Recording",
                    showsActiveAccent: true
                )
            case .transcribing:
                MenuBarStatusIcon(
                    systemImageName: "mic.fill",
                    accessibilityLabel: "Transcribing",
                    showsActiveAccent: true
                )
            case .error:
                MenuBarStatusIcon(
                    systemImageName: "mic",
                    accessibilityLabel: "Error",
                    showsActiveAccent: false
                )
            }
        case .notYetRequested:
            MenuBarStatusIcon(
                systemImageName: "mic",
                accessibilityLabel: "Permission not requested",
                showsActiveAccent: false
            )
        }
    }
}

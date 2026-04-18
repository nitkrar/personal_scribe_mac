import AppKit
import SwiftUI
import SeshatCore

@MainActor
struct MenuBarScene: View {
    @ObservedObject private var model: MenuBarSceneModel

    init(model: MenuBarSceneModel) {
        self.model = model
    }

    var body: some View {
        Text("Seshat — \(Self.stateLabel(for: model.state))")

        if let preparationStatusText = model.preparationStatusText {
            Text(preparationStatusText)
        }

        switch model.permissionState {
        case .granted:
            Button(model.recordButton.title) {
                Task {
                    await model.handleRecordButtonTap()
                }
            }
            .disabled(!model.recordButton.isEnabled)
            .keyboardShortcut("r")
        case .notYetRequested:
            Button(Self.primaryActionTitle(for: .notYetRequested)) {
                Task {
                    await model.handleRecordButtonTap()
                }
            }
        case .denied:
            Button(Self.primaryActionTitle(for: .denied)) {
                model.openMicrophonePrivacySettings()
            }
        }

        if let lastResultText = model.lastResultText, !lastResultText.isEmpty {
            Button("Copy Last Transcript") {
                model.copyLatestTranscript()
            }
            .keyboardShortcut("c")
        }

        Divider()

        Button("Quit Seshat") {
            NSApp.terminate(nil)
        }
        .keyboardShortcut("q")

        Text(BuildInfo.current.displayString)
    }

    static func stateLabel(for state: SessionState) -> String {
        switch state {
        case .idle:
            "Idle"
        case .recording:
            "Recording"
        case .transcribing:
            "Transcribing"
        case .error:
            "Error"
        }
    }

    static func primaryActionTitle(for permissionState: MicrophonePermissionState) -> String {
        switch permissionState {
        case .granted:
            "Record"
        case .notYetRequested:
            "Grant microphone access"
        case .denied:
            "Open System Settings"
        }
    }
}

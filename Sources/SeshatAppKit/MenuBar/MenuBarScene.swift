import SwiftUI
import SeshatCore

@MainActor
struct MenuBarScene: View {
    @ObservedObject private var model: MenuBarSceneModel

    init(model: MenuBarSceneModel) {
        self.model = model
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Seshat")
                .font(.headline)

            Text(Self.stateLabel(for: model.state))
                .font(.subheadline)
                .foregroundStyle(.secondary)

            switch model.permissionState {
            case .granted:
                RecordButtonView(
                    viewModel: model.recordButton,
                    action: model.handleRecordButtonTap
                )
            case .notYetRequested:
                Button(Self.primaryActionTitle(for: .notYetRequested)) {
                    Task {
                        await model.handleRecordButtonTap()
                    }
                }

                Text("Recording starts immediately after access is granted.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            case .denied:
                Button(Self.primaryActionTitle(for: .denied)) {
                    model.openMicrophonePrivacySettings()
                }

                Text("Microphone access is denied. Enable it in Privacy → Microphone.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }

            if let lastResultText = model.lastResultText, !lastResultText.isEmpty {
                Text(lastResultText)
                    .font(.body)

                Button("Copy Last Transcript") {
                    model.copyLatestTranscript()
                }
            }
        }
        .padding(14)
        .frame(minWidth: 280)
        .task {
            model.startObserving()
        }
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

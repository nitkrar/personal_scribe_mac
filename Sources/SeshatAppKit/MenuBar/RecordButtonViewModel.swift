import Foundation
import SeshatCore

@MainActor
struct RecordButtonViewModel: Equatable {
    let title: String
    let systemImageName: String
    let isEnabled: Bool
    let usesDestructiveRole: Bool

    static func make(from sessionState: SessionState) -> RecordButtonViewModel {
        switch sessionState {
        case .idle:
            RecordButtonViewModel(
                title: "Record",
                systemImageName: "mic.circle.fill",
                isEnabled: true,
                usesDestructiveRole: false
            )
        case .recording:
            RecordButtonViewModel(
                title: "Stop",
                systemImageName: "stop.circle.fill",
                isEnabled: true,
                usesDestructiveRole: true
            )
        case .transcribing:
            RecordButtonViewModel(
                title: "Transcribing…",
                systemImageName: "waveform.circle.fill",
                isEnabled: false,
                usesDestructiveRole: false
            )
        case .error:
            RecordButtonViewModel(
                title: "Record Again",
                systemImageName: "arrow.clockwise.circle.fill",
                isEnabled: true,
                usesDestructiveRole: false
            )
        }
    }
}

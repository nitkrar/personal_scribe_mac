import Foundation
import PersonalScribeCore

/// Pure state machine that turns the current `SessionState` +
/// `ModelDownloadProgress` into the text the persistent "record-without-
/// transcribe" ResponseCard should show, or `nil` if the card should be
/// hidden.
///
/// Kept as a free-standing pure function so wiring in
/// `PillOverlayController` stays trivially testable and the UX strings
/// are pinned by tests.
enum RecordingStatusCardDriver {
    static func statusText(
        sessionState: SessionState,
        progress: ModelDownloadProgress?
    ) -> String? {
        guard let progress else {
            return nil
        }

        switch sessionState {
        case .recording:
            return recordingMessage(for: progress)
        case .transcribing:
            return transcribingMessage(for: progress)
        case .idle, .error:
            return nil
        }
    }

    private static func recordingMessage(for progress: ModelDownloadProgress) -> String? {
        switch progress.phase {
        case .downloading:
            let percent = Int((progress.fractionCompleted * 100).rounded())
            return "Recording — transcribing when model is ready (\(percent)%)"
        case .loading:
            return "Recording — model loading, transcription starts shortly"
        case .idle, .finished:
            return nil
        }
    }

    private static func transcribingMessage(for progress: ModelDownloadProgress) -> String? {
        switch progress.phase {
        case .downloading:
            let percent = Int((progress.fractionCompleted * 100).rounded())
            return "Waiting — finishing model download (\(percent)%)"
        case .loading:
            return "Waiting — model loading"
        case .idle, .finished:
            return nil
        }
    }
}

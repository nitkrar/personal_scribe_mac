import Combine
import Foundation
import PersonalScribeCore

@MainActor
public final class PillOverlayViewModel: ObservableObject {
    public typealias Visibility = PillVisibilityState

    @Published public private(set) var visibility: Visibility
    @Published public private(set) var visibilityMode: PillVisibilityMode
    @Published public var audioLevel: Double = 0

    public var isAudioActive: Bool {
        visibility == .recording
    }

    public init(
        visibility: Visibility = .idle,
        visibilityMode: PillVisibilityMode = .autoShow
    ) {
        self.visibility = visibility
        self.visibilityMode = visibilityMode
    }

    public func apply(
        visibility: Visibility,
        visibilityMode: PillVisibilityMode? = nil
    ) {
        if let visibilityMode {
            self.visibilityMode = visibilityMode
        }

        self.visibility = visibility
    }

    public func setVisibilityMode(_ mode: PillVisibilityMode) {
        visibilityMode = mode
    }

    // Backward-compatible helper for older previews/tests that still push
    // raw session inputs. Production wiring now applies store-derived
    // `PillVisibilityState` via `apply(visibility:visibilityMode:)`.
    public func apply(
        sessionState: SessionState,
        preparationProgress: ModelDownloadProgress?
    ) {
        if visibility == .transcribing, case .idle = sessionState {
            visibility = .done
            return
        }

        if case .error(let seshatError) = sessionState {
            visibility = .error(message: Self.pillMessage(for: seshatError))
            return
        }

        if case .recording = sessionState {
            visibility = .recording
            return
        }

        if case .transcribing = sessionState {
            visibility = compatibilityTranscribingVisibility(progress: preparationProgress)
            return
        }

        visibility = compatibilityIdleVisibility(progress: preparationProgress)
    }

    static func pillMessage(for error: PersonalScribeError) -> String {
        switch error {
        case .recordingTooShort:
            return "Too short — try again"
        case .transcriptionFailure:
            return "Transcription failed"
        case .micPermissionDenied:
            return "Microphone permission needed"
        case .audioEngineFailure, .resampleFailure:
            return "Recording failed"
        case .modelLoadFailure:
            return "Model unavailable"
        case .cancelled:
            return "Cancelled"
        case .invalidState:
            return "Session error"
        }
    }

    private func compatibilityIdleVisibility(
        progress: ModelDownloadProgress?
    ) -> Visibility {
        if let progress {
            switch progress.phase {
            case .idle, .finished:
                break
            case .downloading:
                return .downloading(fractionCompleted: progress.fractionCompleted)
            case .loading:
                return .loading
            }
        }

        switch visibilityMode {
        case .alwaysOn:
            return .idle
        case .autoShow, .hidden:
            return .hidden
        }
    }

    private func compatibilityTranscribingVisibility(
        progress: ModelDownloadProgress?
    ) -> Visibility {
        guard let progress else {
            return .transcribing
        }

        switch progress.phase {
        case .idle, .finished:
            return .transcribing
        case .downloading:
            return .downloading(fractionCompleted: progress.fractionCompleted)
        case .loading:
            return .loading
        }
    }
}

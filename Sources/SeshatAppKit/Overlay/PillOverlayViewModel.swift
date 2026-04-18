import Combine
import Foundation
import SeshatCore

@MainActor
public final class PillOverlayViewModel: ObservableObject {
    public enum Visibility: Equatable, Sendable {
        case hidden
        case idle
        case downloading(fractionCompleted: Double)
        case loading
        case recording
        case transcribing
    }

    @Published public private(set) var visibility: Visibility = .idle

    public init() {}

    /// Combined mapping from session state + model preparation progress.
    /// Active recording always wins so the stop affordance stays visible.
    public func apply(
        sessionState: SessionState,
        preparationProgress: ModelDownloadProgress?
    ) {
        switch sessionState {
        case .idle:
            visibility = visibilityForIdleState(preparationProgress)
        case .recording:
            visibility = .recording
        case .transcribing:
            visibility = visibilityForTranscribingState(preparationProgress)
        case .error:
            visibility = .hidden
        }
    }

    private func visibilityForIdleState(_ preparationProgress: ModelDownloadProgress?) -> Visibility {
        guard let preparationProgress else {
            return .idle
        }

        switch preparationProgress.phase {
        case .idle, .finished:
            return .idle
        case .downloading:
            return .downloading(fractionCompleted: preparationProgress.fractionCompleted)
        case .loading:
            return .loading
        }
    }

    private func visibilityForTranscribingState(_ preparationProgress: ModelDownloadProgress?) -> Visibility {
        guard let preparationProgress else {
            return .transcribing
        }

        switch preparationProgress.phase {
        case .idle, .finished:
            return .transcribing
        case .downloading:
            return .downloading(fractionCompleted: preparationProgress.fractionCompleted)
        case .loading:
            return .loading
        }
    }
}

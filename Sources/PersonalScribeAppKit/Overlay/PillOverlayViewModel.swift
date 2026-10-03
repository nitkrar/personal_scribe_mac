import Combine
import SwiftUI
import Foundation
import PersonalScribeCore

@MainActor
public final class PillOverlayViewModel: ObservableObject {
    public typealias Visibility = PillVisibilityState

    @Published public private(set) var visibility: Visibility
    @Published public private(set) var pillStyle: PillStyle = .classic
    @Published public private(set) var visibilityMode: PillVisibility
    @Published public var audioLevel: Double = 0
    /// Side of the panel the pill content is pinned to (set by the
    /// presenter from the pill's `PillAnchor`).
    @Published var contentAlignment: Alignment = .bottom

    /// Invoked when the user clicks Resume on the Cancel Card. The pipeline
    /// owns the card's lifetime; this only forwards the command.
    public var onResumeCancelledRecording: (@MainActor () -> Void)?

    public var isAudioActive: Bool {
        visibility == .recording || visibility == .holdToRecord
    }

    public init(
        visibility: Visibility = .idle,
        visibilityMode: PillVisibility = .autoShow
    ) {
        self.visibility = visibility
        self.visibilityMode = visibilityMode
    }

    public func apply(
        visibility: Visibility,
        visibilityMode: PillVisibility? = nil
    ) {
        if let visibilityMode {
            self.visibilityMode = visibilityMode
        }
        self.visibility = visibility
    }

    public func setPillStyle(_ style: PillStyle) {
        guard style != pillStyle else { return }
        pillStyle = style
    }

    public func resumeCancelledRecording() {
        guard visibility == .cancelled else { return }
        onResumeCancelledRecording?()
    }

    public func setVisibilityMode(_ mode: PillVisibility) {
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

        if case .completed = sessionState {
            visibility = .done
            return
        }

        if case .capturing = sessionState {
            visibility = .recording
            return
        }

        if case .holdRecording = sessionState {
            visibility = .holdToRecord
            return
        }

        if case .transcribing = sessionState {
            visibility = compatibilityTranscribingVisibility(progress: preparationProgress)
            return
        }

        visibility = compatibilityIdleVisibility(progress: preparationProgress)
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
        case .autoShow:
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

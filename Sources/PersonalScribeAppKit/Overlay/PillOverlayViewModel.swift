import Combine
import SwiftUI
import Foundation
import PersonalScribeCore

@MainActor
public final class PillOverlayViewModel: ObservableObject {
    public typealias Visibility = PillVisibilityState

    @Published public private(set) var visibility: Visibility
    @Published public private(set) var pillStyle: PillStyle = .classic
    /// Latest session-driven visibility, shown unless the style is `.none`.
    private var sessionVisibility: Visibility
    @Published public private(set) var visibilityMode: PillVisibility
    @Published public var audioLevel: Double = 0
    @Published public private(set) var isHovered = false
    /// Side of the panel the pill content is pinned to (set by the
    /// presenter from the pill's `PillAnchor`).
    @Published var contentAlignment: Alignment = .bottom

    /// Invoked when the user clicks Resume on the Cancel Card. The pipeline
    /// owns the card's lifetime; this only forwards the command.
    public var onResumeCancelledRecording: (@MainActor () -> Void)?
    public var onMode: (@MainActor () -> Void)?
    public var onRecord: (@MainActor () -> Void)?
    public var onPause: (@MainActor () -> Void)?
    public var onResume: (@MainActor () -> Void)?
    public var onStop: (@MainActor () -> Void)?

    public var isAudioActive: Bool {
        visibility == .recording || visibility == .holdToRecord
    }

    public init(
        visibility: Visibility = .idle,
        visibilityMode: PillVisibility = .autoShow
    ) {
        self.visibility = visibility
        self.sessionVisibility = visibility
        self.visibilityMode = visibilityMode
    }

    public func apply(
        visibility: Visibility,
        visibilityMode: PillVisibility? = nil
    ) {
        if let visibilityMode {
            self.visibilityMode = visibilityMode
        }
        sessionVisibility = visibility
        self.visibility = pillStyle == .none ? .hidden : visibility
    }

    public func setPillStyle(_ style: PillStyle) {
        guard style != pillStyle else { return }
        pillStyle = style
        visibility = style == .none ? .hidden : sessionVisibility
    }

    public func setHovered(_ hovered: Bool) {
        guard hovered != isHovered else { return }
        isHovered = hovered
    }

    func performInteraction(
        _ action: PillInteractionAction,
        fallbackToggle: @MainActor () -> Void
    ) {
        switch action {
        case .mode:
            onMode?()
        case .record:
            if let onRecord { onRecord() } else { fallbackToggle() }
        case .pause:
            onPause?()
        case .resume:
            onResume?()
        case .stop:
            if let onStop { onStop() } else { fallbackToggle() }
        case .toggle:
            fallbackToggle()
        }
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

        if case .paused = sessionState {
            visibility = .paused(elapsedSeconds: 0)
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

import Combine
import Foundation
import PersonalScribeCore

@MainActor
public final class PillOverlayViewModel: ObservableObject {
    public typealias Visibility = PillVisibilityState

    @Published public private(set) var visibility: Visibility
    @Published public private(set) var visibilityMode: PillVisibility
    @Published public var audioLevel: Double = 0

    /// Window during which the Cancel Card is visible after a cancel.
    /// Spec §3: "4 seconds elapsed | Cancel Card is visible | Dismiss
    /// Cancel Card; return to .idle".
    public static let cancelCardDismissDelay: Duration = .seconds(4)

    /// Invoked when the user clicks Undo on the Cancel Card. Phase 3
    /// sets up the hook; Phase 5 wires it to restore the pasteboard
    /// snapshot captured at recording start. Called on the main actor
    /// before the card dismisses back to `.idle`.
    public var onUndoCancelledRecording: (@MainActor () -> Void)?

    private var cancelDismissTask: Task<Void, Never>?
    /// Override that suppresses incoming `apply(visibility:)` calls from
    /// the AppStore session-state mapping while `.cancelled` is
    /// "sticky". Without this, the session's normal
    /// `.capturing → .idle` transition on cancel would immediately
    /// clobber `.cancelled` before the user sees the Cancel Card.
    /// Phase 3 uses `isShowingCancelCard` to gate those updates; Phase 5
    /// inspects the same flag when deciding whether to restore
    /// clipboard on Undo.
    public var isShowingCancelCard: Bool {
        visibility == .cancelled
    }

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

    deinit {
        cancelDismissTask?.cancel()
    }

    public func apply(
        visibility: Visibility,
        visibilityMode: PillVisibility? = nil
    ) {
        if let visibilityMode {
            self.visibilityMode = visibilityMode
        }

        // Sticky Cancel Card: once `.cancelled` has been entered,
        // external session-driven visibility updates are held off until
        // the 4s auto-dismiss fires or the user clicks Undo. Prevents
        // the session's own `.capturing → .idle` cancel transition
        // from wiping the Cancel Card before the user can see it.
        if isShowingCancelCard && visibility != .cancelled && visibility != .idle {
            return
        }

        self.visibility = visibility
    }

    // MARK: - Cancel Card state (spec §2f + §3)

    /// Enter the `.cancelled` state and show the Cancel Card. Auto-
    /// dismisses back to `.idle` after `cancelCardDismissDelay`. Pass a
    /// custom `sleep` for tests that want to exercise the auto-dismiss
    /// path without real wall-clock waits.
    public func cancel(
        sleep: @escaping @Sendable (Duration) async throws -> Void = { try await Task.sleep(for: $0) }
    ) {
        cancelDismissTask?.cancel()
        visibility = .cancelled

        let delay = Self.cancelCardDismissDelay
        cancelDismissTask = Task { [weak self] in
            do {
                try await sleep(delay)
            } catch is CancellationError {
                return
            } catch {
                return
            }

            await MainActor.run {
                guard let self, self.visibility == .cancelled else { return }
                self.visibility = .idle
            }
        }
    }

    /// Invoked when the user clicks Undo. Cancels the auto-dismiss
    /// timer, fires `onUndoCancelledRecording`, and returns to `.idle`.
    public func undoCancel() {
        cancelDismissTask?.cancel()
        cancelDismissTask = nil
        if visibility == .cancelled {
            onUndoCancelledRecording?()
            visibility = .idle
        }
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

        if case .error(let seshatError) = sessionState {
            visibility = .error(message: Self.pillMessage(for: seshatError))
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

    static func pillMessage(for error: PersonalScribeError) -> String {
        switch error {
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

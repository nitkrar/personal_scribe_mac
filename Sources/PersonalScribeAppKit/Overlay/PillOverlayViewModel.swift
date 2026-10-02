import Combine
import SwiftUI
import Foundation
import PersonalScribeCore

@MainActor
public final class PillOverlayViewModel: ObservableObject {
    public typealias Visibility = PillVisibilityState

    @Published public private(set) var visibility: Visibility
    @Published public private(set) var visibilityMode: PillVisibility
    @Published public var audioLevel: Double = 0
    /// Side of the panel the pill content is pinned to (set by the
    /// presenter from the pill's `PillAnchor`).
    @Published var contentAlignment: Alignment = .bottom

    /// Invoked when the user clicks Resume on the Cancel Card: continue
    /// the cancelled recording (the pipeline kept its audio).
    public var onResumeCancelledRecording: (@MainActor () -> Void)?
    /// Invoked when the Cancel Card times out — Resume is no longer
    /// offered, so the kept audio can be discarded.
    public var onCancelCardExpired: (@MainActor () -> Void)?

    private var cancelDismissTask: Task<Void, Never>?
    /// Latest session-driven visibility received while the Cancel Card
    /// was up; shown when the card closes.
    private var heldVisibility: Visibility?
    /// Whether the Cancel Card owns presentation. Incoming session state
    /// is held until the card closes.
    public var isShowingCancelCard: Bool {
        visibility == .cancelled
    }

    public var isAudioActive: Bool {
        visibility == .recording || visibility == .holdToRecord
    }

    /// How long the Cancel Card stays up (the user's "Cancel card duration"
    /// setting, read at each cancel so changes apply immediately).
    private let cancelCardDuration: @MainActor () -> Duration

    public init(
        visibility: Visibility = .idle,
        visibilityMode: PillVisibility = .autoShow,
        cancelCardDuration: @escaping @MainActor () -> Duration = {
            .seconds(CancelCardDuration.resolve().seconds)
        }
    ) {
        self.visibility = visibility
        self.visibilityMode = visibilityMode
        self.cancelCardDuration = cancelCardDuration
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

        // Keep the Cancel Card visible until Resume or its configured
        // timeout, while retaining the latest session-driven state.
        if isShowingCancelCard && visibility != .cancelled {
            heldVisibility = visibility
            return
        }

        self.visibility = visibility
    }

    // MARK: - Cancel Card state (spec §2f + §3)

    /// Enter the `.cancelled` state and show the Cancel Card. Auto-
    /// dismisses after the configured `cancelCardDuration`. Pass a
    /// custom `sleep` for tests that want to exercise the auto-dismiss
    /// path without real wall-clock waits.
    public func cancel(
        sleep: @escaping @Sendable (Duration) async throws -> Void = { try await Task.sleep(for: $0) }
    ) {
        cancelDismissTask?.cancel()
        heldVisibility = nil
        visibility = .cancelled

        let delay = cancelCardDuration()
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
                self.onCancelCardExpired?()
                self.closeCancelCard()
            }
        }
    }

    /// Resume clicked: stop the auto-dismiss timer, hand off to the
    /// pipeline (`onResumeCancelledRecording`), and close the card.
    public func resumeCancelledRecording() {
        cancelDismissTask?.cancel()
        cancelDismissTask = nil
        if visibility == .cancelled {
            onResumeCancelledRecording?()
            closeCancelCard()
        }
    }

    private func closeCancelCard() {
        let next = heldVisibility ?? .idle
        heldVisibility = nil
        visibility = next
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

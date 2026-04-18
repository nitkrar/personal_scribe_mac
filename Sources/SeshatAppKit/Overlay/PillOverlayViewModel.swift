import Combine
import Foundation
import SeshatCore

/// Maps session + model-preparation state (and user-selected visibility
/// mode) to the concrete `Visibility` the overlay renders.
///
/// Reference: `plans/seshat_agent_bundle/03_Surfaces/PillOverlayWindow/architecture.png`.
/// Phase 2 Sprint 2 Lane B1 — three visibility modes
/// (`.alwaysOn` / `.autoShow` / `.hidden`) each shape what "idle at rest"
/// looks like.
@MainActor
public final class PillOverlayViewModel: ObservableObject {
    /// Concrete UI states the pill can render.
    public enum Visibility: Equatable, Sendable {
        case hidden
        case idle
        case downloading(fractionCompleted: Double)
        case loading
        case recording
        case transcribing
    }

    @Published public private(set) var visibility: Visibility
    @Published public private(set) var visibilityMode: PillVisibilityMode

    /// Latest audio-level sample (0…1). Updated by the controller in
    /// response to `SessionCoordinator.audioLevelStream()`. Used by the
    /// recording pill's `WaveformView`.
    @Published public var audioLevel: Double = 0

    /// Whether the audio-level stream is currently live (derived from
    /// `visibility == .recording`). Used by `WaveformView`'s
    /// `isActive` binding + decay coast-down.
    public var isAudioActive: Bool {
        visibility == .recording
    }

    // Cache the last inputs so `setVisibilityMode` can re-derive without
    // the caller re-passing them.
    private var lastSessionState: SessionState = .idle
    private var lastPreparationProgress: ModelDownloadProgress?

    public init(visibilityMode: PillVisibilityMode = .autoShow) {
        self.visibilityMode = visibilityMode
        // Seed to `.idle` so existing Sprint 1 tests that read
        // `visibility` before `apply(…)` keep passing. `.hidden` mode
        // and `.autoShow` mode both *render* as hidden at rest, but the
        // view model's seeded value stays `.idle` until real session
        // state arrives via `apply(sessionState:preparationProgress:)`.
        self.visibility = .idle
    }

    /// Combined mapping from session state + model preparation progress.
    /// Active recording always wins so the stop affordance stays visible
    /// (except when the user picked `.hidden` mode — that overrides
    /// everything by design; per PLAN_PHASES.md line 293 the invariant is
    /// still held because the menu bar is always visible in Phase 2).
    public func apply(
        sessionState: SessionState,
        preparationProgress: ModelDownloadProgress?
    ) {
        lastSessionState = sessionState
        lastPreparationProgress = preparationProgress
        visibility = computeVisibility(
            mode: visibilityMode,
            sessionState: sessionState,
            preparationProgress: preparationProgress
        )
    }

    /// User flipped the visibility mode via Settings / menu bar; re-derive
    /// the current visibility from the most recent session inputs.
    public func setVisibilityMode(_ mode: PillVisibilityMode) {
        visibilityMode = mode
        visibility = computeVisibility(
            mode: mode,
            sessionState: lastSessionState,
            preparationProgress: lastPreparationProgress
        )
    }

    // MARK: - Pure derivation

    private func computeVisibility(
        mode: PillVisibilityMode,
        sessionState: SessionState,
        preparationProgress: ModelDownloadProgress?
    ) -> Visibility {
        // Hidden mode wins unconditionally. See PLAN_PHASES.md line 293 —
        // the always-visible menu bar preserves the "at-least-one-surface"
        // invariant in Phase 2 (no menu-bar hide toggle exists).
        if mode == .hidden {
            return .hidden
        }

        // Session error state → hidden. Error UX is handled by the menu
        // bar (permission / mic error surfaces) rather than the pill.
        if case .error = sessionState {
            return .hidden
        }

        switch sessionState {
        case .idle:
            return idleVisibility(for: mode, progress: preparationProgress)
        case .recording:
            return .recording
        case .transcribing:
            return transcribingVisibility(for: preparationProgress)
        case .error:
            return .hidden
        }
    }

    private func idleVisibility(
        for mode: PillVisibilityMode,
        progress: ModelDownloadProgress?
    ) -> Visibility {
        if let progress {
            switch progress.phase {
            case .idle, .finished:
                break // fall through to mode-based default
            case .downloading:
                return .downloading(fractionCompleted: progress.fractionCompleted)
            case .loading:
                return .loading
            }
        }

        switch mode {
        case .alwaysOn:
            return .idle
        case .autoShow:
            return .hidden
        case .hidden:
            return .hidden // redundant — caught earlier
        }
    }

    private func transcribingVisibility(for progress: ModelDownloadProgress?) -> Visibility {
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

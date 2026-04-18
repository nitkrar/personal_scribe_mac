import Combine
import Foundation
import SeshatCore

/// Maps session + model-preparation state (and user-selected visibility
/// mode) to the concrete `Visibility` the overlay renders.
///
/// Reference: Sprint 2 dogfood redesign (2026-04-18) — WisprFlow-inspired
/// 4-state pill (`idle` / `recording` / `transcribing` / `done`) per
/// Claude's spec. `downloading` / `loading` are retained to cover the
/// model-download phase (orthogonal axis to the session state machine).
///
/// ## Visibility-rule override
/// During `.recording`, the pill is **always visible** regardless of the
/// user's `PillVisibilityMode`. The stop affordance must stay reachable
/// even when the user chose `.hidden` (menu bar + hotkey remain the
/// baseline paths; plan invariant from PLAN_PHASES.md line 293 — the
/// always-visible menu bar keeps "at least one surface visible" true
/// regardless of pill mode).
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
        /// Brief confirmation after a successful `transcribing → idle`
        /// transition (checkmark). Auto-clears after ~1 second to the
        /// mode's normal idle visibility.
        case done
    }

    @Published public private(set) var visibility: Visibility
    @Published public private(set) var visibilityMode: PillVisibilityMode

    /// Latest audio-level sample (0…1). Retained for potential future
    /// use (e.g. adaptive sine-wave amplitude). The Sprint 2 pill
    /// redesign uses a procedural `SineWaveView` instead of driving
    /// the waveform from audio level, so this value is currently not
    /// read by the pill view — but the publisher wiring is preserved
    /// so re-introducing audio-driven animation later is a local
    /// change.
    @Published public var audioLevel: Double = 0

    /// Whether the audio-level stream is currently live (derived from
    /// `visibility == .recording`). Retained for backward compatibility
    /// with callers that haven't migrated off the audio-driven model.
    public var isAudioActive: Bool {
        visibility == .recording
    }

    // Cache the last inputs so `setVisibilityMode` can re-derive without
    // the caller re-passing them.
    private var lastSessionState: SessionState = .idle
    private var lastPreparationProgress: ModelDownloadProgress?

    /// Live timer task that holds visibility at `.done` for ~1 second
    /// after a successful transcription before falling through to the
    /// mode's normal idle. Cancelled on any subsequent `apply(...)` so
    /// a new recording pre-empts the confirmation cleanly.
    private var doneConfirmationTask: Task<Void, Never>?

    /// How long to hold `.done` before returning to normal idle.
    static let doneConfirmationDuration: Duration = .milliseconds(1_000)

    public init(visibilityMode: PillVisibilityMode = .autoShow) {
        self.visibilityMode = visibilityMode
        self.visibility = .idle
    }

    /// Combined mapping from session state + model preparation progress.
    public func apply(
        sessionState: SessionState,
        preparationProgress: ModelDownloadProgress?
    ) {
        let priorSessionState = lastSessionState
        lastSessionState = sessionState
        lastPreparationProgress = preparationProgress

        // Cancel any pending .done timer; a new session event takes
        // precedence over the stale confirmation.
        doneConfirmationTask?.cancel()
        doneConfirmationTask = nil

        // Transcribing → idle signals a successful transcription
        // (failure would route through .error). Show .done briefly.
        if
            case .transcribing = priorSessionState,
            case .idle = sessionState
        {
            visibility = .done
            SeshatLogger(category: SeshatLogCategory.ui).info(
                "PillOverlayViewModel.apply — state=\(sessionState) (done confirmation) mode=\(visibilityMode) → visibility=done"
            )
            doneConfirmationTask = Task { @MainActor [weak self] in
                try? await Task.sleep(for: Self.doneConfirmationDuration)
                guard !Task.isCancelled, let self else { return }
                self.visibility = self.computeVisibility(
                    mode: self.visibilityMode,
                    sessionState: self.lastSessionState,
                    preparationProgress: self.lastPreparationProgress
                )
            }
            return
        }

        let newVisibility = computeVisibility(
            mode: visibilityMode,
            sessionState: sessionState,
            preparationProgress: preparationProgress
        )
        SeshatLogger(category: SeshatLogCategory.ui).info(
            "PillOverlayViewModel.apply — state=\(sessionState) progress=\(String(describing: preparationProgress)) mode=\(visibilityMode) → visibility=\(newVisibility)"
        )
        visibility = newVisibility
    }

    /// User flipped the visibility mode via Settings / menu bar; re-derive
    /// the current visibility from the most recent session inputs.
    public func setVisibilityMode(_ mode: PillVisibilityMode) {
        doneConfirmationTask?.cancel()
        doneConfirmationTask = nil
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
        // Recording overrides the visibility mode. The stop affordance
        // must stay reachable even in `.hidden` mode (per Claude's
        // Sprint 2 spec). Menu bar keeps the "at-least-one-surface"
        // invariant in Phase 2.
        if case .recording = sessionState {
            return .recording
        }

        // Session error state → hidden. Error UX lives in the menu
        // bar (permission / mic error surfaces) rather than the pill.
        if case .error = sessionState {
            return .hidden
        }

        // Otherwise, `.hidden` mode wins.
        if mode == .hidden {
            return .hidden
        }

        switch sessionState {
        case .idle:
            return idleVisibility(for: mode, progress: preparationProgress)
        case .recording:
            return .recording // unreachable — matched earlier
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

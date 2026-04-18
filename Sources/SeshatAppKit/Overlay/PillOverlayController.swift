import Combine
import Foundation
import SeshatCore

/// Wiring layer between `SessionCoordinator` publishers and the pill
/// overlay's view-model. The Composition layer constructs this once and
/// passes it to the SwiftUI scene.
///
/// ## Sprint 2 Lane B1 additions
/// * `visibilityMode` — seeds the view-model's user-selectable mode at
///   construction time. Defaults to `PillVisibilityMode.resolve(from:)`
///   so the stored UserDefaults value wins. The existing Sprint 1 call
///   site continues to compile (kept as default `.autoShow` via the
///   resolver).
/// * `audioLevelPublisher` — optional stream of `[0, 1]` RMS samples
///   driven by `SessionCoordinator.audioLevelStream()`. Consumed by the
///   recording pill's `WaveformView`. When absent, the waveform flatlines
///   (safe default for tests / older Composition wiring).
@MainActor
public final class PillOverlayController: ObservableObject {
    public let viewModel: PillOverlayViewModel
    private let presenter: PillOverlayPresenter
    private var cancellables: Set<AnyCancellable> = []

    /// Sprint 1 signature preserved. Uses the persisted visibility mode
    /// (defaults to `.autoShow` when the key is absent — PLAN_PHASES.md
    /// line 293).
    public convenience init(
        statePublisher: AnyPublisher<SessionState, Never>,
        preparationProgressPublisher: AnyPublisher<ModelDownloadProgress?, Never>,
        onTap: @escaping @MainActor () -> Void = {}
    ) {
        self.init(
            statePublisher: statePublisher,
            preparationProgressPublisher: preparationProgressPublisher,
            audioLevelPublisher: nil,
            visibilityMode: PillVisibilityMode.resolve(),
            onTap: onTap
        )
    }

    /// Full initializer including the audio-level publisher that Sprint 2
    /// Lane B1 threads into the recording pill's waveform.
    public init(
        statePublisher: AnyPublisher<SessionState, Never>,
        preparationProgressPublisher: AnyPublisher<ModelDownloadProgress?, Never>,
        audioLevelPublisher: AnyPublisher<Double, Never>?,
        visibilityMode: PillVisibilityMode = .autoShow,
        onTap: @escaping @MainActor () -> Void = {}
    ) {
        let viewModel = PillOverlayViewModel(visibilityMode: visibilityMode)
        self.viewModel = viewModel
        self.presenter = PillOverlayPresenter(model: viewModel, onTap: onTap)

        Publishers
            .CombineLatest(statePublisher, preparationProgressPublisher)
            .sink { [weak viewModel] state, progress in
                viewModel?.apply(sessionState: state, preparationProgress: progress)
            }
            .store(in: &cancellables)

        if let audioLevelPublisher {
            audioLevelPublisher
                .receive(on: DispatchQueue.main)
                .sink { [weak viewModel] level in
                    MainActor.assumeIsolated {
                        viewModel?.audioLevel = level
                    }
                }
                .store(in: &cancellables)
        }
    }

    /// Flip the visibility mode at runtime (e.g. from Settings UI in
    /// Phase 3). Persists the new value so subsequent launches see it.
    public func setVisibilityMode(
        _ mode: PillVisibilityMode,
        defaults: UserDefaults = .standard
    ) {
        viewModel.setVisibilityMode(mode)
        mode.persist(to: defaults)
    }
}

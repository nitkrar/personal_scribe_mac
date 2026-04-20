import Combine
import Foundation
import SeshatCore

@MainActor
public final class PillOverlayController: ObservableObject {
    public let viewModel: PillOverlayViewModel

    private let appStore: AppStore
    private let defaults: UserDefaults
    private let presenter: PillOverlayPresenter
    private var cancellables: Set<AnyCancellable> = []

    init(
        appStore: AppStore,
        audioLevelPublisher: AnyPublisher<Double, Never>? = nil,
        defaults: UserDefaults = .standard,
        onTap: @escaping @MainActor () -> Void = {},
        panelBuilder: any PillOverlayPanelBuilding = AppKitPillOverlayPanelBuilder()
    ) {
        self.appStore = appStore
        self.defaults = defaults

        let initialMode = PillVisibilityMode.resolve(from: defaults)
        let viewModel = PillOverlayViewModel(
            visibility: appStore.snapshot.pillVisibility,
            visibilityMode: initialMode
        )
        self.viewModel = viewModel
        self.presenter = PillOverlayPresenter(
            model: viewModel,
            onTap: onTap,
            panelBuilder: panelBuilder
        )

        applySnapshot(appStore.snapshot)

        appStore.objectWillChange.sink { [weak self] _ in
            DispatchQueue.main.async {
                guard let self else { return }
                MainActor.assumeIsolated {
                    self.applySnapshot(self.appStore.snapshot)
                }
            }
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

    public func setVisibilityMode(
        _ mode: PillVisibilityMode,
        defaults: UserDefaults = .standard
    ) {
        viewModel.setVisibilityMode(mode)
        mode.persist(to: defaults)
    }

    public func showClipboardOnlyNotice() {
        presenter.showClipboardOnlyNotice()
    }

    private func applySnapshot(_ snapshot: AppStoreSnapshot) {
        viewModel.apply(
            visibility: snapshot.pillVisibility,
            visibilityMode: PillVisibilityMode.resolve(from: defaults)
        )
    }
}

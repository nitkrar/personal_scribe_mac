import Combine
import Foundation
import SeshatCore

@MainActor
public final class PillOverlayController: ObservableObject {
    public let viewModel: PillOverlayViewModel
    private let presenter: PillOverlayPresenter
    private var cancellable: AnyCancellable?

    public init(
        statePublisher: AnyPublisher<SessionState, Never>,
        downloadProgressPublisher: AnyPublisher<ModelDownloadProgress?, Never>,
        onTap: @escaping @MainActor () -> Void = {}
    ) {
        let viewModel = PillOverlayViewModel()
        self.viewModel = viewModel
        self.presenter = PillOverlayPresenter(model: viewModel, onTap: onTap)
        self.cancellable = Publishers
            .CombineLatest(statePublisher, downloadProgressPublisher)
            .sink { [weak viewModel] state, progress in
                viewModel?.apply(sessionState: state, downloadProgress: progress)
            }
    }
}

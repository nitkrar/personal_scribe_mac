import Combine
import Foundation
import SeshatCore

@MainActor
public final class PillOverlayController: ObservableObject {
    public let viewModel: PillOverlayViewModel
    private let presenter: PillOverlayPresenter
    private var cancellable: AnyCancellable?

    public init(statePublisher: AnyPublisher<SessionState, Never>) {
        let viewModel = PillOverlayViewModel()
        self.viewModel = viewModel
        self.presenter = PillOverlayPresenter(model: viewModel)
        self.cancellable = statePublisher.sink { [weak viewModel] state in
            viewModel?.apply(sessionState: state)
        }
    }
}

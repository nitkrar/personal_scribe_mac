import Combine
import Foundation

@MainActor
protocol ToastPosting: AnyObject {
    func post(_ message: ToastBroadcaster.Message)
}

@MainActor
public final class ToastBroadcaster: ToastPosting {
    struct Message: Equatable, Sendable {
        let text: String
        let autoDismissAfter: TimeInterval

        init(
            text: String,
            autoDismissAfter: TimeInterval = 3.0
        ) {
            self.text = text
            self.autoDismissAfter = autoDismissAfter
        }
    }

    var publisher: AnyPublisher<Message, Never> {
        subject.eraseToAnyPublisher()
    }

    private let subject = PassthroughSubject<Message, Never>()

    func post(_ message: Message) {
        subject.send(message)
    }
}

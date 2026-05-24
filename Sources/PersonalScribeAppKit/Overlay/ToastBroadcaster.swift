import Combine
import Foundation

public struct ResponseCardMessage: Sendable, Equatable {
    public let text: String
    public let autoDismissAfter: TimeInterval?

    public init(
        text: String,
        autoDismissAfter: TimeInterval? = 3.0
    ) {
        self.text = text
        self.autoDismissAfter = autoDismissAfter
    }

    public static func success(
        _ text: String,
        autoDismissAfter: TimeInterval? = 2.0
    ) -> ResponseCardMessage {
        ResponseCardMessage(text: text, autoDismissAfter: autoDismissAfter)
    }

    public static func info(
        _ text: String,
        autoDismissAfter: TimeInterval? = 3.0
    ) -> ResponseCardMessage {
        ResponseCardMessage(text: text, autoDismissAfter: autoDismissAfter)
    }

    public static func error(
        _ text: String,
        autoDismissAfter: TimeInterval? = 3.0
    ) -> ResponseCardMessage {
        ResponseCardMessage(text: text, autoDismissAfter: autoDismissAfter)
    }
}

@MainActor
public final class ToastBroadcaster {
    private let subject = PassthroughSubject<ResponseCardMessage, Never>()

    public init() {}

    public var publisher: AnyPublisher<ResponseCardMessage, Never> {
        subject.eraseToAnyPublisher()
    }

    public func post(_ message: ResponseCardMessage) {
        subject.send(message)
    }
}

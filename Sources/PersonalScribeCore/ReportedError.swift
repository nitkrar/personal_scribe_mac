import Foundation

public struct ReportedError: Sendable, Equatable {
    public let mappedError: PersonalScribeError
    public let userMessage: String
    public let detail: String
    public let timestamp: Date
    public let category: String
    public let context: [String: String]
    public let autoDismissAfter: TimeInterval?

    public init(
        mappedError: PersonalScribeError,
        userMessage: String,
        detail: String,
        timestamp: Date,
        category: String,
        context: [String: String] = [:],
        autoDismissAfter: TimeInterval? = 4.0
    ) {
        self.mappedError = mappedError
        self.userMessage = userMessage
        self.detail = detail
        self.timestamp = timestamp
        self.category = category
        self.context = context
        self.autoDismissAfter = autoDismissAfter
    }

    public init?(event: DiagnosticsEvent) {
        guard let userFacing = event.userFacing else {
            return nil
        }

        switch userFacing {
        case .sessionError(let mapped, let messageOverride, let autoDismissAfter):
            self.init(
                mappedError: mapped,
                userMessage: messageOverride ?? Self.userMessage(for: mapped),
                detail: event.metadata["detail"] ?? event.message,
                timestamp: event.timestamp,
                category: event.category,
                context: event.metadata,
                autoDismissAfter: autoDismissAfter
            )
        }
    }

    public static let userMessageMaxLength = 80

    public static func userMessage(for error: PersonalScribeError) -> String {
        let description = error.errorDescription ?? "Something went wrong."
        guard let suggestion = error.recoverySuggestion else {
            return cap(description)
        }

        let combined = "\(description) \(suggestion)"
        if combined.count <= userMessageMaxLength {
            return combined
        }

        return cap(description)
    }

    private static func cap(_ message: String) -> String {
        guard message.count > userMessageMaxLength else {
            return message
        }

        let endIndex = message.index(message.startIndex, offsetBy: userMessageMaxLength - 1)
        return String(message[..<endIndex]) + "…"
    }
}

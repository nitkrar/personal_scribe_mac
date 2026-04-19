import Foundation

public enum ModelSelectionError: Error, Sendable, Equatable {
    case unknownVoiceModelID(String)
    case storedSelectionNoLongerRegistered(String)
}

extension ModelSelectionError: LocalizedError {
    public var errorDescription: String? {
        switch self {
        case .unknownVoiceModelID(let id):
            "Unknown voice model ID: \(id)"
        case .storedSelectionNoLongerRegistered(let id):
            "Stored voice model is no longer registered: \(id)"
        }
    }

    public var recoverySuggestion: String? {
        switch self {
        case .unknownVoiceModelID:
            "Choose one of the registered models and try again."
        case .storedSelectionNoLongerRegistered:
            "Reset the active model selection to a registered built-in descriptor."
        }
    }
}

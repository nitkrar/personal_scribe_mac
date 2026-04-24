import Foundation

public enum PersonalScribeError: Error, Sendable, Equatable {
    case micPermissionDenied
    case audioEngineFailure
    case resampleFailure
    case modelLoadFailure
    case transcriptionFailure
    case cancelled
    case invalidState
}

extension PersonalScribeError: LocalizedError {
    public var errorDescription: String? {
        switch self {
        case .micPermissionDenied:
            "Microphone permission was denied."
        case .audioEngineFailure:
            "Audio capture failed."
        case .resampleFailure:
            "Audio resampling failed."
        case .modelLoadFailure:
            "The transcription model could not be loaded."
        case .transcriptionFailure:
            "Transcription failed."
        case .cancelled:
            "The operation was cancelled."
        case .invalidState:
            "The session entered an invalid state."
        }
    }

    public var failureReason: String? {
        switch self {
        case .micPermissionDenied:
            "The app does not have access to the microphone."
        case .audioEngineFailure:
            "The capture pipeline could not start or remain active."
        case .resampleFailure:
            "The PCM buffer metadata was invalid or conversion failed."
        case .modelLoadFailure:
            "The speech model was unavailable or unreadable."
        case .transcriptionFailure:
            "The transcriber could not produce a result."
        case .cancelled:
            "The operation was stopped before it finished."
        case .invalidState:
            "A shared component detected an impossible transition or misuse."
        }
    }

    public var recoverySuggestion: String? {
        switch self {
        case .micPermissionDenied:
            "Allow microphone access in System Settings and try again."
        case .audioEngineFailure, .resampleFailure:
            "Try recording again."
        case .modelLoadFailure:
            "Check model availability and try again."
        case .transcriptionFailure:
            "Try transcribing the recording again."
        case .cancelled:
            "Retry the operation if you still need it."
        case .invalidState:
            "Reset the session and try again."
        }
    }
}

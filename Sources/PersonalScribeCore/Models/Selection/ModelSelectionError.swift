import Foundation

public enum ModelSelectionError: Error, Sendable, Equatable {
    case unknownVoiceModelID(String)
    case descriptorNotRegistered(id: String)
    case storedSelectionNoLongerRegistered(String)
    /// Raised by the disk-space precheck in `DefaultModelService`
    /// before a download is started. `required` is the model's
    /// `approximateSizeBytes` plus the staging buffer; `available`
    /// is the free bytes reported for the models-directory volume
    /// at the time of the check.
    case insufficientDiskSpace(required: Int64, available: Int64)
}

extension ModelSelectionError: LocalizedError {
    public var errorDescription: String? {
        switch self {
        case .unknownVoiceModelID(let id):
            "Unknown voice model ID: \(id)"
        case .descriptorNotRegistered(let id):
            "Model descriptor is not registered: \(id)"
        case .storedSelectionNoLongerRegistered(let id):
            "Stored voice model is no longer registered: \(id)"
        case .insufficientDiskSpace(let required, let available):
            Self.formatInsufficientDiskSpaceDescription(required: required, available: available)
        }
    }

    public var recoverySuggestion: String? {
        switch self {
        case .unknownVoiceModelID:
            "Choose one of the registered models and try again."
        case .descriptorNotRegistered:
            "Use a descriptor from the built-in model catalog before creating a transcriber."
        case .storedSelectionNoLongerRegistered:
            "Reset the active model selection to a registered built-in descriptor."
        case .insufficientDiskSpace:
            "Free up space on the volume holding your models directory and try again."
        }
    }

    private static func formatInsufficientDiskSpaceDescription(
        required: Int64,
        available: Int64
    ) -> String {
        let formatter = ByteCountFormatter()
        formatter.allowedUnits = [.useMB, .useGB]
        formatter.countStyle = .file
        let requiredStr = formatter.string(fromByteCount: required)
        let availableStr = formatter.string(fromByteCount: available)
        return "Not enough disk space for download. Needs \(requiredStr), \(availableStr) available."
    }
}

import Foundation

public enum TranscriptionEngine: Sendable, Equatable {
    case parakeetTDT
    // Reserve shape for future engines (parakeetCTC, whisper, etc.).
    // Do not implement them now.
}

public struct ModelDescriptor: Sendable, Equatable {
    public let id: String                  // "parakeet-tdt-0.6b-v2" — also the on-disk directory name
    public let displayName: String         // "Parakeet TDT 0.6B" — surfaces in future Settings UI
    public let repository: String          // HuggingFace repo, e.g. "FluidInference/parakeet-tdt-0.6b-v2-coreml"
    public let revision: String            // pinned commit SHA
    public let requiredRelativePaths: [String]  // artifacts inside the repo to fetch
    public let approximateSizeBytes: Int64 // for display and disk-space checks
    public let engine: TranscriptionEngine

    public init(
        id: String,
        displayName: String,
        repository: String,
        revision: String,
        requiredRelativePaths: [String],
        approximateSizeBytes: Int64,
        engine: TranscriptionEngine
    ) {
        self.id = id
        self.displayName = displayName
        self.repository = repository
        self.revision = revision
        self.requiredRelativePaths = requiredRelativePaths
        self.approximateSizeBytes = approximateSizeBytes
        self.engine = engine
    }

    public func resolveURL(for relativePath: String) -> URL {
        URL(
            string: "https://huggingface.co/\(repository)/resolve/\(revision)/\(relativePath)"
        )!
    }
}

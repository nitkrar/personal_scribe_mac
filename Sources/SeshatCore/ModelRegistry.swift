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

    public func resolveURL(for relativePath: String) -> URL {
        URL(
            string: "https://huggingface.co/\(repository)/resolve/\(revision)/\(relativePath)"
        )!
    }
}

public enum ModelRegistry {
    public static let parakeetTDT06Bv2 = ModelDescriptor(
        id: "parakeet-tdt-0.6b-v2",
        displayName: "Parakeet TDT 0.6B",
        repository: "FluidInference/parakeet-tdt-0.6b-v2-coreml",
        revision: "ee09c569f73759e6d44c9bd16766f477b2b36d39",
        requiredRelativePaths: [
            "Preprocessor.mlmodelc/coremldata.bin",
            "Encoder.mlmodelc/coremldata.bin",
            "Decoder.mlmodelc/coremldata.bin",
            "JointDecision.mlmodelc/coremldata.bin",
            "parakeet_vocab.json",
        ],
        approximateSizeBytes: 450_000_000,
        engine: .parakeetTDT
    )

    // Reserve slot. Do not populate until user asks.
    // public static let parakeetTDT110M = ...

    public static let all: [ModelDescriptor] = [parakeetTDT06Bv2]

    public static func descriptor(for id: String) -> ModelDescriptor? {
        all.first { $0.id == id }
    }

    public static let defaultModelId: String = parakeetTDT06Bv2.id
}

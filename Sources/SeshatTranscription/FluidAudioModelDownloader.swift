import Foundation
import SeshatCore

enum ParakeetArtifact {
    static let repository = "FluidInference/parakeet-tdt-0.6b-v2-coreml"
    static let modelDirectoryName = "parakeet-tdt-0.6b-v2"
    static let modelRevision = "ee09c569f73759e6d44c9bd16766f477b2b36d39"
    static let requiredRelativePaths: [String] = [
        "Preprocessor.mlmodelc/coremldata.bin",
        "Encoder.mlmodelc/coremldata.bin",
        "Decoder.mlmodelc/coremldata.bin",
        "JointDecision.mlmodelc/coremldata.bin",
        "parakeet_vocab.json",
    ]

    static func resolveURL(for relativePath: String) -> URL {
        URL(
            string: "https://huggingface.co/\(repository)/resolve/\(modelRevision)/\(relativePath)"
        )!
    }
}

private struct PrivateModelDownloader: ModelDownloading {
    func ensureModelAvailable(
        at directory: URL,
        progress: @escaping @Sendable (ModelDownloadProgress) -> Void
    ) async throws -> URL {
        _ = progress
        return directory
    }
}

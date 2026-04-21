import Foundation

/// UI-facing snapshot of a single voice model's download / readiness state.
///
/// `ModelDownloadProgress` (in `Protocols.swift`) is the low-level stream
/// element emitted during an active download. `ModelDownloadState` is the
/// flattened, per-descriptor projection that a `ModelService` publishes so
/// Settings surfaces (AIModelsTab) can render one chip per row without
/// subscribing to individual per-download streams.
///
/// The two types intentionally share a similar phase vocabulary; see
/// `DefaultModelService` for the mapping (`.downloading`/`.loading` map
/// directly, `.finished` → `.ready`, `.idle` is ignored — a download that
/// hasn't started leaves the model in `.notDownloaded`).
public struct ModelDownloadState: Sendable, Equatable {
    public let descriptorId: String
    public let phase: Phase
    public let fractionCompleted: Double

    public enum Phase: Sendable, Equatable {
        case notDownloaded
        case downloading
        case loading
        case ready
        case failed(message: String)
    }

    public init(
        descriptorId: String,
        phase: Phase,
        fractionCompleted: Double = 0
    ) {
        self.descriptorId = descriptorId
        self.phase = phase
        self.fractionCompleted = fractionCompleted
    }
}

import Foundation

public enum TranscriptionEngine: Sendable, Equatable {
    case parakeetTDT
    // Reserve shape for future engines (parakeetCTC, whisper, etc.).
    // Do not implement them now.
}

/// Published benchmark metrics for a registered model. Sourced from
/// the vendor's model card (e.g. HuggingFace Open ASR leaderboard).
/// All fields optional so ad-hoc descriptors constructed by tests for
/// unrelated purposes don't have to declare benchmarks — the popover
/// hides missing-metric rows rather than inventing numbers.
///
/// `averageWER` and `rtfx` are the inputs to computed-relative
/// rankings — the Settings info popover sorts all registered models
/// by these fields to assign a "Fastest / Fast / Slow" (for RTFx) or
/// "High / Medium / Low" (for WER) bucket. No fixed thresholds — each
/// rank falls out of the registry.
public struct ModelPerformance: Sendable, Equatable, Codable {
    /// Average Word Error Rate across the HuggingFace Open ASR
    /// leaderboard's eight test sets. Lower is more accurate.
    public let averageWER: Double?

    /// Real-time factor on the HuggingFace Open ASR leaderboard
    /// (seconds of audio processed per wall-clock second, batch size
    /// 128, A100). Higher is faster.
    public let rtfx: Double?

    /// Total parameter count for reference. Not used for ranking — a
    /// 110M CTC model can be faster AND less accurate than a 600M TDT
    /// model, so parameter count isn't a reliable proxy for either
    /// axis on its own.
    public let parameterCount: Int?

    public init(
        averageWER: Double? = nil,
        rtfx: Double? = nil,
        parameterCount: Int? = nil
    ) {
        self.averageWER = averageWER
        self.rtfx = rtfx
        self.parameterCount = parameterCount
    }
}

public struct ModelDescriptor: Sendable, Equatable {
    public let id: String                  // "parakeet-tdt-0.6b-v2" — also the on-disk directory name
    public let displayName: String         // "Parakeet TDT 0.6B" — surfaces in future Settings UI
    /// One-line inline description shown under `displayName` in the
    /// Settings → AI Models row. Keep ≤70 chars so it fits on one line
    /// at the default settings content width (620pt) without
    /// truncation. Empty is a hard error for registered models; tests
    /// pin this.
    public let shortDescription: String
    /// Human-readable architecture label shown in the info popover's
    /// "Architecture" row (e.g. "FastConformer-TDT", "Hybrid
    /// FastConformer-TDT-CTC"). Lives on the descriptor rather than
    /// the engine enum because the engine is an identifier, not a
    /// user-facing label.
    public let architecture: String
    public let repository: String          // HuggingFace repo, e.g. "FluidInference/parakeet-tdt-0.6b-v2-coreml"
    public let revision: String            // pinned commit SHA
    public let requiredRelativePaths: [String]  // artifacts inside the repo to fetch
    public let approximateSizeBytes: Int64 // for display and disk-space checks
    public let engine: TranscriptionEngine
    /// Published benchmarks (WER, RTFx, params). Defaults to an
    /// empty-field struct for ad-hoc test fixtures.
    public let performance: ModelPerformance

    public init(
        id: String,
        displayName: String,
        shortDescription: String,
        architecture: String,
        repository: String,
        revision: String,
        requiredRelativePaths: [String],
        approximateSizeBytes: Int64,
        engine: TranscriptionEngine,
        performance: ModelPerformance = ModelPerformance()
    ) {
        self.id = id
        self.displayName = displayName
        self.shortDescription = shortDescription
        self.architecture = architecture
        self.repository = repository
        self.revision = revision
        self.requiredRelativePaths = requiredRelativePaths
        self.approximateSizeBytes = approximateSizeBytes
        self.engine = engine
        self.performance = performance
    }

    public func resolveURL(for relativePath: String) -> URL {
        URL(
            string: "https://huggingface.co/\(repository)/resolve/\(revision)/\(relativePath)"
        )!
    }
}

import Foundation

public enum TranscriptionEngine: Sendable, Equatable {
    case parakeetTDT
    // Reserve shape for future engines (parakeetCTC, whisper, etc.).
    // Do not implement them now.
}

/// Relative rating for a model attribute (speed, accuracy). The scale
/// is explicitly "relative among the models we ship" — not an absolute
/// benchmark. Three levels keep the visual bar readable in the popover
/// and force authors to pick a meaningfully distinct bucket.
///
/// `rank` exposes a comparable integer so tests can assert ordering
/// ("CTC is faster than the 0.6B variants") without depending on raw
/// case order.
public enum RelativeRating: String, Sendable, Equatable, CaseIterable, Codable {
    case low
    case medium
    case high

    public var rank: Int {
        switch self {
        case .low: return 0
        case .medium: return 1
        case .high: return 2
        }
    }

    /// Human-readable label for the popover row.
    public var displayName: String {
        switch self {
        case .low: return "Low"
        case .medium: return "Medium"
        case .high: return "High"
        }
    }
}

public struct ModelDescriptor: Sendable, Equatable {
    public let id: String                  // "parakeet-tdt-0.6b-v2" — also the on-disk directory name
    public let displayName: String         // "Parakeet TDT 0.6B" — surfaces in future Settings UI
    /// One-line inline description shown under `displayName` in the
    /// Settings → AI Models row. Keep ≤70 chars so it fits on one line
    /// at the default settings content width (620pt) without
    /// truncation. Nil is a hard error — every registered model must
    /// declare copy; tests pin this.
    public let shortDescription: String
    public let repository: String          // HuggingFace repo, e.g. "FluidInference/parakeet-tdt-0.6b-v2-coreml"
    public let revision: String            // pinned commit SHA
    public let requiredRelativePaths: [String]  // artifacts inside the repo to fetch
    public let approximateSizeBytes: Int64 // for display and disk-space checks
    public let engine: TranscriptionEngine
    /// Relative speed rating among registered models; drives the info
    /// popover's visual bar. Optional so ad-hoc descriptors constructed
    /// by tests for unrelated purposes (e.g. exercising
    /// `isDownloaded`) don't have to declare one — the popover falls
    /// back to `.medium` / hides the row in that case.
    public let speedRating: RelativeRating?
    /// Relative accuracy rating. Same optionality rationale as
    /// `speedRating`.
    public let accuracyRating: RelativeRating?

    public init(
        id: String,
        displayName: String,
        shortDescription: String,
        repository: String,
        revision: String,
        requiredRelativePaths: [String],
        approximateSizeBytes: Int64,
        engine: TranscriptionEngine,
        speedRating: RelativeRating? = nil,
        accuracyRating: RelativeRating? = nil
    ) {
        self.id = id
        self.displayName = displayName
        self.shortDescription = shortDescription
        self.repository = repository
        self.revision = revision
        self.requiredRelativePaths = requiredRelativePaths
        self.approximateSizeBytes = approximateSizeBytes
        self.engine = engine
        self.speedRating = speedRating
        self.accuracyRating = accuracyRating
    }

    public func resolveURL(for relativePath: String) -> URL {
        URL(
            string: "https://huggingface.co/\(repository)/resolve/\(revision)/\(relativePath)"
        )!
    }
}

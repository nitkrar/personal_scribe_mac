import Foundation

/// Picks the first-launch default voice model based on the machine's
/// physical RAM. Below 10 GiB → `lightweight`; otherwise → `baseline`.
///
/// Ticket #016. Pure function — the caller supplies both candidates
/// (so the policy doesn't need to scan the registry) and the memory
/// probe as an `Int64` (so tests don't need a `ProcessInfo` seam).
public enum DefaultModelSelectionPolicy {
    /// Machines with physical memory **strictly below** this threshold
    /// get the lightweight pick. 10 GiB cleanly splits 8 GB Macs
    /// (below) from 16 GB+ Macs (above).
    public static let lowMemoryThresholdBytes: Int64 = 10 * 1024 * 1024 * 1024

    public static func recommendedDefault(
        physicalMemoryBytes: Int64,
        lightweight: ModelDescriptor,
        baseline: ModelDescriptor
    ) -> ModelDescriptor {
        physicalMemoryBytes < lowMemoryThresholdBytes ? lightweight : baseline
    }
}

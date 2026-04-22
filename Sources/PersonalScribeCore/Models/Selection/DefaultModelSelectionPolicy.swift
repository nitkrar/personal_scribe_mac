import Foundation

/// Picks the first-launch default voice model based on the machine's
/// physical RAM. Low-RAM machines (≤ 8 GB, i.e. below the 10 GiB
/// threshold) get the lightest registered model; everyone else gets
/// the `baselineDefault` passed in by the caller.
///
/// Ticket #016 (reframed): the catalog's registered models include a
/// lightweight variant (`parakeet-tdt-ctc-110m`, 110M params) for
/// lower-RAM Macs, but nothing routed low-RAM machines to it. This
/// policy closes that loop on first launch only; once the user has a
/// persisted selection (via Settings or even the policy's own first
/// run), the probe is never consulted again.
///
/// Pure function: no side effects, no `ProcessInfo` dependency — the
/// caller supplies `physicalMemoryBytes`. Live callers pass
/// `Int64(ProcessInfo.processInfo.physicalMemory)`; tests pass
/// arbitrary values.
public enum DefaultModelSelectionPolicy {
    /// Machines with physical memory **strictly below** this threshold
    /// get the lightweight pick. 10 GiB cleanly splits 8 GB Macs
    /// (below) from 16 GB+ Macs (above); 12 GB / 24 GB machines land
    /// above.
    public static let lowMemoryThresholdBytes: Int64 = 10 * 1024 * 1024 * 1024

    public static func recommendedDefault(
        physicalMemoryBytes: Int64,
        registeredModels: [ModelDescriptor],
        baselineDefault: ModelDescriptor
    ) -> ModelDescriptor {
        guard physicalMemoryBytes < lowMemoryThresholdBytes else {
            return baselineDefault
        }

        // Below threshold: find the registered model with the lowest
        // parameterCount that's strictly lighter than the baseline.
        // Tiebreaker: lower approximateSizeBytes. Models without a
        // declared parameterCount are ineligible — picking an
        // unmeasured model over a well-characterized baseline would
        // be guessing.
        guard let baselineParams = baselineDefault.performance.parameterCount else {
            return baselineDefault
        }

        let lighter = registeredModels
            .filter { descriptor in
                guard let params = descriptor.performance.parameterCount else {
                    return false
                }
                return params < baselineParams
            }
            .min { lhs, rhs in
                let lhsParams = lhs.performance.parameterCount ?? Int.max
                let rhsParams = rhs.performance.parameterCount ?? Int.max
                if lhsParams != rhsParams {
                    return lhsParams < rhsParams
                }
                return lhs.approximateSizeBytes < rhs.approximateSizeBytes
            }

        return lighter ?? baselineDefault
    }
}

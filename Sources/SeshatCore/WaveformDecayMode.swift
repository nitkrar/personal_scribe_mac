import Foundation

/// How the pill's waveform behaves when the audio-level stream ends.
///
/// Background (BACKLOG Phase 2 Sprint 1 TODO): `SessionCoordinator.stop()`
/// emits a final `0.0` and then terminates the `audioLevelStream()`. Under
/// `.immediate`, the waveform snaps flat at that moment — the Sprint 1
/// shipping behaviour. Under `.animated`, the UI layer interpolates from
/// the last-known level to `0.0` over 500 ms before snapping, giving the
/// stop transition a short coast-down.
///
/// This decay is strictly a presentation concern: `SeshatSession` /
/// `SeshatAudio` plumbing stays as-is.
///
/// Persisted under `UserDefaults["SeshatWaveformDecayMode"]`. Default is
/// `.immediate` (no behaviour change until a user explicitly opts in via
/// Phase 3 Settings UI).
public enum WaveformDecayMode: String, CaseIterable, Sendable, Equatable {
    case immediate
    case animated

    /// The default mode on first launch / absent key.
    public static let `default`: WaveformDecayMode = .immediate

    /// Duration (in seconds) of the linear-interpolation fade from the
    /// last-known level to zero. `.immediate` has duration `0`, which
    /// means the decay helper snaps to 0 for any non-zero `elapsed`.
    public var durationSeconds: Double {
        switch self {
        case .immediate: return 0.0
        case .animated: return 0.5
        }
    }

    public static let userDefaultsKey = "SeshatWaveformDecayMode"

    public static func resolve(from defaults: UserDefaults = .standard) -> WaveformDecayMode {
        guard
            let raw = defaults.string(forKey: userDefaultsKey),
            let mode = WaveformDecayMode(rawValue: raw)
        else {
            return .default
        }
        return mode
    }

    public func persist(to defaults: UserDefaults = .standard) {
        defaults.set(rawValue, forKey: Self.userDefaultsKey)
    }

    /// Pure linear-decay helper. Tests against this directly instead of
    /// sleeping for real time.
    ///
    /// * `startLevel` — the last-known normalised level (0…1) when the
    ///   stream terminated.
    /// * `elapsed` — time in seconds since termination. Clamped to
    ///   `[0, duration]` internally — callers never need to clamp.
    /// * `duration` — total decay window. `0` ≙ snap immediately.
    ///
    /// Returns the interpolated level. At `elapsed == 0` returns
    /// `startLevel`; at `elapsed >= duration` returns `0`.
    public static func linearLevel(
        startLevel: Double,
        elapsed: Double,
        duration: Double
    ) -> Double {
        guard duration > 0 else {
            return 0.0
        }

        let clampedElapsed = max(0.0, min(elapsed, duration))
        let fraction = clampedElapsed / duration
        // Linear: startLevel → 0 as fraction 0 → 1.
        return startLevel * (1.0 - fraction)
    }
}

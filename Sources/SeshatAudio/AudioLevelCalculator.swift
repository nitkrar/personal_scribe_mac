import Foundation

/// Stateless RMS + normalization helpers used by `AVAudioCaptureService` to
/// publish its 10 Hz audio-level stream. Broken out into a standalone type so
/// the math is unit-testable without spinning up an audio engine.
///
/// Conventions:
///   - Float PCM samples live in `[-1, 1]`. Linear RMS therefore also lives
///     in `[0, 1]` for nominal-level audio.
///   - `normalizedLevel` floors values below `silenceFloorRMS` (≈ -60 dBFS)
///     to `0` so the idle waveform doesn't jitter on room noise, and clips
///     above `peakCeilingRMS = 1.0` so overdriven buffers don't burst past
///     the UI's [0, 1] binding contract.
///
/// No smoothing is applied here — consumers that want a low-pass envelope
/// (e.g. the Phase 2 pill waveform) can add their own.
internal enum AudioLevelCalculator {
    /// Root-mean-square of a mono sample block. Empty input returns 0.
    static func rms(samples: [Float]) -> Float {
        guard !samples.isEmpty else { return 0.0 }
        var sumOfSquares: Float = 0
        for sample in samples {
            sumOfSquares += sample * sample
        }
        let mean = sumOfSquares / Float(samples.count)
        return mean.squareRoot()
    }

    /// Normalized `[0, 1]` level: linear RMS, floor at `silenceFloorRMS`,
    /// clip at `peakCeilingRMS`.
    static func normalizedLevel(samples: [Float]) -> Float {
        let raw = rms(samples: samples)
        if raw < silenceFloorRMS {
            return 0.0
        }
        if raw > peakCeilingRMS {
            return 1.0
        }
        return raw
    }

    /// -60 dBFS ≈ 0.001 linear. Below this, we treat audio as silence so the
    /// idle waveform sits flat when no one is speaking.
    static let silenceFloorRMS: Float = 0.001

    /// Linear RMS at or above 1.0 clips to 1.0 so overdriven input doesn't
    /// break the `[0, 1]` contract.
    static let peakCeilingRMS: Float = 1.0
}

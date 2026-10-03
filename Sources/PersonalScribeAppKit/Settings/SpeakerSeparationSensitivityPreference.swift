import Foundation
import PersonalScribeCore

/// User-facing preset that tunes the offline speaker diarizer's
/// merge-vs-split behavior. Higher sensitivity (`.relaxed`) splits
/// similar voices apart at the cost of occasionally over-splitting
/// one person; lower sensitivity (`.strict`) prefers stable speaker
/// labels at the cost of merging similar voices.
///
/// `.balanced` is the FluidAudio community-1 baseline and the default
/// for fresh installs.
///
/// Persisted under `UserDefaults` key `"SpeakerSeparationSensitivity"`
/// as a JSON-encoded string raw-value (`"relaxed"` / `"balanced"` /
/// `"strict"`). Mirrors `PreferenceKeys.speakerSeparationSensitivity`.
public enum SpeakerSeparationSensitivityPreference: StoredPreference {
    public static let setting = PreferenceKeys.speakerSeparationSensitivity
}

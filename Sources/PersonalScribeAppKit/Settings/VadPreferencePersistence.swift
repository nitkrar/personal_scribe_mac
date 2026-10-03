import Foundation
import PersonalScribeCore
import PersonalScribeVAD

/// Master toggle for VAD auto-stop (#046). `true` ships the feature; when
/// `false` the orchestrator skips VAD wiring and recording only stops via
/// manual hotkey / pill / Esc. Default `true` per locked scope.
public enum VadAutoStopEnabledPreference: StoredPreference {
    public static let setting = PreferenceKeys.vadAutoStopEnabled
}

/// Stage B opt-in (#046): enable the grace window + "…stopping,
/// speak to continue" ResponseCard before auto-stop fires.
public enum VadShowStoppingWarningPreference: StoredPreference {
    public static let setting = PreferenceKeys.vadShowStoppingWarning
}

/// Stage B opt-in (#046): enable the "Auto stopped. Update settings to
/// change." ResponseCard notification after VAD-triggered auto-stop.
public enum VadShowAutoStoppedNotificationPreference: StoredPreference {
    public static let setting = PreferenceKeys.vadShowAutoStoppedNotification
}

/// Silence duration (seconds) after which VAD auto-stop fires. Clamped
/// to `VadPreferences` min/max on read and write.
public enum VadSilenceThresholdPreference: StoredPreference {
    public static let setting = PreferenceKeys.vadSilenceThreshold
}

/// `VadPreferencesReading` implementation backed by UserDefaults. Snapshots
/// both preferences on each `current()` call — the orchestrator calls this
/// ONCE at session start, so a fresh read per session is correct and cheap.
///
/// Reads `UserDefaults.standard` directly rather than holding a stored
/// reference. `UserDefaults` is documented thread-safe but not `Sendable` in
/// Swift 6 — storing a reference would require `@unchecked Sendable` on the
/// reader. Avoiding the reference sidesteps the concurrency annotation and
/// keeps the reader cheap to construct (no init params).
public struct UserDefaultsVadPreferencesReader: VadPreferencesReading {
    public init() {}

    public func current() -> VadPreferences {
        VadPreferences(
            autoStopEnabled: VadAutoStopEnabledPreference.resolve(),
            silenceThresholdSeconds: VadSilenceThresholdPreference.resolve(),
            showStoppingWarning: VadShowStoppingWarningPreference.resolve(),
            showAutoStoppedNotification: VadShowAutoStoppedNotificationPreference.resolve()
        )
    }
}

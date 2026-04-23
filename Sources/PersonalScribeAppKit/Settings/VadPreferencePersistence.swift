import Foundation
import PersonalScribeCore
import PersonalScribeVAD

/// Master toggle for VAD auto-stop (#046). `true` ships the feature; when
/// `false` the orchestrator skips VAD wiring and recording only stops via
/// manual hotkey / pill / Esc. Default `true` per locked scope.
public enum VadAutoStopEnabledPreference {
    public static let userDefaultsKey = "VadAutoStopEnabled"
    public static let `default`: Bool = true

    public static func resolve(from defaults: UserDefaults = .standard) -> Bool {
        guard defaults.object(forKey: userDefaultsKey) != nil else {
            return `default`
        }
        return defaults.bool(forKey: userDefaultsKey)
    }

    public static func persist(_ value: Bool, to defaults: UserDefaults = .standard) {
        defaults.set(value, forKey: userDefaultsKey)
    }
}

/// Silence duration (seconds) after which VAD auto-stop fires. Clamped to
/// `VadPreferences.minSilenceThresholdSeconds ... maxSilenceThresholdSeconds`
/// (1.0–5.0s) at read/write time as defense in depth — the Settings slider
/// also constrains the live edit range. Default 2.5s.
public enum VadSilenceThresholdPreference {
    public static let userDefaultsKey = "VadSilenceDurationSeconds"
    public static let `default`: Double = 2.5

    public static func resolve(from defaults: UserDefaults = .standard) -> Double {
        guard defaults.object(forKey: userDefaultsKey) != nil else {
            return `default`
        }
        return clamp(defaults.double(forKey: userDefaultsKey))
    }

    public static func persist(_ value: Double, to defaults: UserDefaults = .standard) {
        defaults.set(clamp(value), forKey: userDefaultsKey)
    }

    private static func clamp(_ value: Double) -> Double {
        min(
            max(value, VadPreferences.minSilenceThresholdSeconds),
            VadPreferences.maxSilenceThresholdSeconds
        )
    }
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
            silenceThresholdSeconds: VadSilenceThresholdPreference.resolve()
        )
    }
}

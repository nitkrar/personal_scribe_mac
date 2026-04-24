import Foundation

/// Gates `AVAudioCaptureService`'s system-audio mute behavior. When
/// `true`, the service calls `SystemAudioMuter.muteIfNeeded()` before
/// the engine starts and `restoreIfNeeded()` on every capture-end path
/// (stop, start-failure, runtime error, consumer cancel). When `false`,
/// the muter is never touched — system audio behaves exactly as before.
///
/// Mutes the OS-level volume flag (the same one the F10 mute key
/// writes) via `NSAppleScript`, so the effect is route-independent and
/// covers media, alerts, and notifications without per-device
/// management. Intended to prevent speaker → mic bleed from polluting
/// the transcript when the user is recording with background audio
/// playing.
///
/// Persisted under `UserDefaults` key `"MuteOutputWhileRecording"`.
/// Default `false` — fresh installs behave exactly as they did before
/// the feature existed; users opt in. `object(forKey:)` probe
/// distinguishes unset from explicit false, matching
/// `AutoPasteEnabledPreference` / `ClipboardRestoreEnabledPreference`.
public enum MuteOutputWhileRecordingPreference {
    public static let userDefaultsKey = "MuteOutputWhileRecording"

    public static let `default`: Bool = false

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

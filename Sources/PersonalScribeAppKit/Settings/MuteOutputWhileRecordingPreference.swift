import Foundation
import PersonalScribeCore

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
/// Opt-in; default `false`.
public enum MuteOutputWhileRecordingPreference: StoredPreference {
    public static let setting = SettingKey<Bool>(key: "MuteOutputWhileRecording", default: false)
}

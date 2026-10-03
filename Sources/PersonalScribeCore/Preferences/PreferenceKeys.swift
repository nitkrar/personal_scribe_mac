import Foundation

/// Canonical key, default and sanitizer for every setting a recipe
/// `Parameter.setting(...)` can reference. The matching Settings
/// wrappers (`StoredPreference`) point here rather than redeclaring.
/// New keys must also be added to `all`, which saved modes decode against.
public enum PreferenceKeys {
    /// VAD silence threshold (seconds).
    public static let vadSilenceThreshold = SettingKey<TimeInterval>(
        key: "VadSilenceDurationSeconds",
        default: 5.0,
        sanitize: VadPreferences.clampedSilenceThreshold
    )

    /// VAD "show stopping warning" toggle.
    public static let vadShowStoppingWarning = SettingKey<Bool>(
        key: "VadShowStoppingWarning",
        default: false
    )

    /// VAD "show auto-stopped notification" toggle.
    public static let vadShowAutoStoppedNotification = SettingKey<Bool>(
        key: "VadShowAutoStoppedNotification",
        default: false
    )

    /// Restore clipboard after paste.
    public static let clipboardRestoreEnabled = SettingKey<Bool>(
        key: "ClipboardRestoreEnabled",
        default: false
    )

    /// VAD auto-stop master toggle.
    public static let vadAutoStopEnabled = SettingKey<Bool>(
        key: "VadAutoStopEnabled",
        default: true
    )

    /// Auto-paste (Cmd+V after clipboard write).
    public static let autoPasteEnabled = SettingKey<Bool>(
        key: "AutoPasteEnabled",
        default: true
    )

    /// "Clean up transcript"; off delivers the raw transcript.
    public static let transcriptCleanupEnabled = SettingKey<Bool>(
        key: "TranscriptCleanupEnabled",
        default: true
    )

    /// Streaming dictation live transcript card toggle.
    public static let streamingLiveCardEnabled = SettingKey<Bool>(
        key: "StreamingLiveCardEnabled",
        default: true
    )

    /// Streaming dictation live cursor streaming toggle. Schema/UI land
    /// in #056; runtime honor stays deferred to #033.
    public static let streamingLiveCursorEnabled = SettingKey<Bool>(
        key: "StreamingLiveCursorEnabled",
        default: false
    )

    /// Streaming dictation stop-time authoritative second-pass toggle.
    public static let streamingSecondPassEnabled = SettingKey<Bool>(
        key: "StreamingSecondPassEnabled",
        default: true
    )

    /// Streaming dictation end-of-utterance silence threshold in
    /// milliseconds. Shared global default for streaming adapters
    /// that use VAD to segment utterances inside an active session.
    public static let streamingEouSilenceThresholdMs = SettingKey<Int>(
        key: "StreamingEouSilenceThresholdMs",
        default: 1000
    )

    /// Speaker separation sensitivity preset for the offline diarizer.
    public static let speakerSeparationSensitivity = SettingKey<SpeakerSeparationSensitivity>(
        key: "SpeakerSeparationSensitivity",
        default: .balanced
    )

    /// Registered key for `key`, if its value type is `Value`.
    public static func registered<Value>(_ key: String, as _: Value.Type) -> SettingKey<Value>? {
        all.first { ($0 as? SettingKey<Value>)?.key == key } as? SettingKey<Value>
    }

    private static let all: [any Sendable] = [
        vadSilenceThreshold,
        vadShowStoppingWarning,
        vadShowAutoStoppedNotification,
        clipboardRestoreEnabled,
        vadAutoStopEnabled,
        autoPasteEnabled,
        transcriptCleanupEnabled,
        streamingLiveCardEnabled,
        streamingLiveCursorEnabled,
        streamingSecondPassEnabled,
        streamingEouSilenceThresholdMs,
        speakerSeparationSensitivity,
    ]
}

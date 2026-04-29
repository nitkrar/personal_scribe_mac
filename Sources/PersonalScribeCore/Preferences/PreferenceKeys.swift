import Foundation

/// Central registry of `SettingKey<Value>` declarations used by recipe
/// `Parameter<Value>.setting(...)` references (per L22 + #078.8).
///
/// Why a registry: recipes reference settings by key. Spreading those
/// keys across the codebase invites typos and orphaned constants. This
/// type is the single inventory — every setting a recipe parameter can
/// point at lives here, declared with its UserDefaults key + default
/// value. The values mirror the existing per-setting `Preference`
/// declarations in `PersonalScribeAppKit/Settings/`; tests pin that
/// mirroring (#078.8 `testRegistryIncludesVadSilenceThresholdKey`).
///
/// Caseless enum: namespacing only. Adding new keys = new static
/// constant on this enum + corresponding tests.
public enum PreferenceKeys {
    /// VAD silence threshold (seconds). Matches
    /// `VadSilenceThresholdPreference.userDefaultsKey` in PersonalScribeAppKit.
    /// Default mirrors `VadPreferences.default.silenceThresholdSeconds`.
    public static let vadSilenceThreshold = SettingKey<TimeInterval>(
        key: "VadSilenceDurationSeconds",
        default: 5.0
    )

    /// VAD "show stopping warning" toggle. Matches
    /// `VadShowStoppingWarningPreference.userDefaultsKey`.
    public static let vadShowStoppingWarning = SettingKey<Bool>(
        key: "VadShowStoppingWarning",
        default: false
    )

    /// VAD "show auto-stopped notification" toggle. Matches
    /// `VadShowAutoStoppedNotificationPreference.userDefaultsKey`.
    public static let vadShowAutoStoppedNotification = SettingKey<Bool>(
        key: "VadShowAutoStoppedNotification",
        default: false
    )

    /// Restore clipboard after paste. Matches
    /// `ClipboardRestoreEnabledPreference.userDefaultsKey`.
    public static let clipboardRestoreEnabled = SettingKey<Bool>(
        key: "ClipboardRestoreEnabled",
        default: true
    )

    /// VAD auto-stop master toggle. Matches
    /// `VadAutoStopEnabledPreference.userDefaultsKey` + `default`.
    public static let vadAutoStopEnabled = SettingKey<Bool>(
        key: "VadAutoStopEnabled",
        default: true
    )

    /// Auto-paste (Cmd+V after clipboard write). Matches
    /// `AutoPasteEnabledPreference.userDefaultsKey` + `default`.
    public static let autoPasteEnabled = SettingKey<Bool>(
        key: "AutoPasteEnabled",
        default: true
    )

    /// Speaker separation sensitivity preset for the offline diarizer.
    /// Matches `SpeakerSeparationSensitivityPreference.userDefaultsKey`
    /// + `default`. The FluidAudio adapter reads this at session start
    /// and translates the resolved case to an `OfflineDiarizerConfig`.
    public static let speakerSeparationSensitivity = SettingKey<SpeakerSeparationSensitivity>(
        key: "SpeakerSeparationSensitivity",
        default: .balanced
    )
}

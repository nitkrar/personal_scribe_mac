import Foundation

public enum RecordAudioEnabledPreference: StoredPreference {
    public static let setting = SettingKey<Bool>(key: "RecordAudioEnabled", default: true)
}

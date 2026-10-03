import Foundation
import PersonalScribeCore

public enum OfflineTranscriptionDiarizationPreference: StoredPreference {
    public static let setting = SettingKey<Bool>(key: "OfflineTranscriptionDiarizationEnabled", default: false)
}

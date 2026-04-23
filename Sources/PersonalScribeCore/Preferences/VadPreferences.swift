import Foundation

public struct VadPreferences: Sendable, Equatable, Codable {
    public var autoStopEnabled: Bool
    public var silenceThresholdSeconds: Double

    public init(autoStopEnabled: Bool, silenceThresholdSeconds: Double) {
        self.autoStopEnabled = autoStopEnabled
        self.silenceThresholdSeconds = Self.clamp(silenceThresholdSeconds)
    }

    public static let `default` = VadPreferences(
        autoStopEnabled: true,
        silenceThresholdSeconds: 2.5
    )

    public static let minSilenceThresholdSeconds: Double = 1.0
    public static let maxSilenceThresholdSeconds: Double = 5.0

    private static func clamp(_ seconds: Double) -> Double {
        min(max(seconds, minSilenceThresholdSeconds), maxSilenceThresholdSeconds)
    }
}

/// Reader protocol so the orchestrator can snapshot preferences at session
/// start without coupling to UserDefaults. Concrete UserDefaults-backed
/// implementation lives in PersonalScribeAppKit (composition layer).
public protocol VadPreferencesReading: Sendable {
    func current() -> VadPreferences
}

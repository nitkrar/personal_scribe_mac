import Foundation

public struct VadPreferences: Sendable, Equatable, Codable {
    public var autoStopEnabled: Bool
    public var silenceThresholdSeconds: Double
    /// Stage B opt-in (#046). When true, VAD `.speechEnded` triggers a
    /// 0.8s grace window before the auto-stop handler fires, surfaced via
    /// the ResponseCard. Default false.
    public var showStoppingWarning: Bool
    /// Stage B opt-in (#046). When true, auto-stop firing publishes a
    /// fire-token that the ResponseCard renders as a short notification
    /// with a link to Settings. Default false.
    public var showAutoStoppedNotification: Bool

    public init(
        autoStopEnabled: Bool,
        silenceThresholdSeconds: Double,
        showStoppingWarning: Bool = false,
        showAutoStoppedNotification: Bool = false
    ) {
        self.autoStopEnabled = autoStopEnabled
        self.silenceThresholdSeconds = Self.clamp(silenceThresholdSeconds)
        self.showStoppingWarning = showStoppingWarning
        self.showAutoStoppedNotification = showAutoStoppedNotification
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

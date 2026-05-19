import Foundation

/// Streaming-only recipe behavior toggles for #056.
///
/// Keeps live transcript UI, deferred live-cursor transport, and the
/// optional authoritative second pass out of `OutputSinkSpec` so the
/// final-delivery sink list stays focused on stop-time outputs.
public struct StreamingBehaviorSpec: Codable, Equatable, Sendable {
    public var liveCardEnabled: Parameter<Bool>
    public var liveCursorEnabled: Parameter<Bool>
    public var secondPassEnabled: Parameter<Bool>
    public var eouSilenceThresholdMs: Parameter<Int>

    public init(
        liveCardEnabled: Parameter<Bool>,
        liveCursorEnabled: Parameter<Bool>,
        secondPassEnabled: Parameter<Bool>,
        eouSilenceThresholdMs: Parameter<Int> = .setting(
            PreferenceKeys.streamingEouSilenceThresholdMs
        )
    ) {
        self.liveCardEnabled = liveCardEnabled
        self.liveCursorEnabled = liveCursorEnabled
        self.secondPassEnabled = secondPassEnabled
        self.eouSilenceThresholdMs = eouSilenceThresholdMs
    }

    public static let defaultSettings = StreamingBehaviorSpec(
        liveCardEnabled: .setting(PreferenceKeys.streamingLiveCardEnabled),
        liveCursorEnabled: .setting(PreferenceKeys.streamingLiveCursorEnabled),
        secondPassEnabled: .setting(PreferenceKeys.streamingSecondPassEnabled),
        eouSilenceThresholdMs: .setting(PreferenceKeys.streamingEouSilenceThresholdMs)
    )

    private enum CodingKeys: String, CodingKey {
        case liveCardEnabled
        case liveCursorEnabled
        case secondPassEnabled
        case eouSilenceThresholdMs
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.liveCardEnabled = try container.decode(Parameter<Bool>.self, forKey: .liveCardEnabled)
        self.liveCursorEnabled = try container.decode(Parameter<Bool>.self, forKey: .liveCursorEnabled)
        self.secondPassEnabled = try container.decode(Parameter<Bool>.self, forKey: .secondPassEnabled)
        self.eouSilenceThresholdMs = try container.decodeIfPresent(
            Parameter<Int>.self,
            forKey: .eouSilenceThresholdMs
        ) ?? .setting(PreferenceKeys.streamingEouSilenceThresholdMs)
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(liveCardEnabled, forKey: .liveCardEnabled)
        try container.encode(liveCursorEnabled, forKey: .liveCursorEnabled)
        try container.encode(secondPassEnabled, forKey: .secondPassEnabled)
        try container.encode(eouSilenceThresholdMs, forKey: .eouSilenceThresholdMs)
    }
}

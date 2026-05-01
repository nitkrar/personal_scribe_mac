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

    public init(
        liveCardEnabled: Parameter<Bool>,
        liveCursorEnabled: Parameter<Bool>,
        secondPassEnabled: Parameter<Bool>
    ) {
        self.liveCardEnabled = liveCardEnabled
        self.liveCursorEnabled = liveCursorEnabled
        self.secondPassEnabled = secondPassEnabled
    }

    public static let defaultSettings = StreamingBehaviorSpec(
        liveCardEnabled: .setting(PreferenceKeys.streamingLiveCardEnabled),
        liveCursorEnabled: .setting(PreferenceKeys.streamingLiveCursorEnabled),
        secondPassEnabled: .setting(PreferenceKeys.streamingSecondPassEnabled)
    )
}

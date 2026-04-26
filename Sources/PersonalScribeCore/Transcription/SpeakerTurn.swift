import Foundation

/// One contiguous span where the diarizer attributes the audio to
/// a single speaker. Mirrors the public surface of FluidAudio's
/// `TimedSpeakerSegment` reduced to the three fields #078 needs.
///
/// `start` / `end` are offsets relative to the input audio's start.
/// `speakerID` is whatever the diarizer emits (vendor-defined; for
/// pyannote+WeSpeaker it's `"speaker_0"`, `"speaker_1"`, …).
public struct SpeakerTurn: Sendable, Equatable {
    public let speakerID: String
    public let start: Duration
    public let end: Duration

    public init(speakerID: String, start: Duration, end: Duration) {
        self.speakerID = speakerID
        self.start = start
        self.end = end
    }
}

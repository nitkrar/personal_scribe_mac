public struct TranscriptionResult: Sendable, Equatable {
    public struct Segment: Sendable, Equatable {
        public let text: String
        public let start: Duration
        public let end: Duration

        public init(text: String, start: Duration, end: Duration) {
            self.text = text
            self.start = start
            self.end = end
        }
    }

    public let text: String
    public let segments: [Segment]
    public let audioDuration: Duration
    public let processingDuration: Duration

    public init(
        text: String,
        segments: [Segment] = [],
        audioDuration: Duration,
        processingDuration: Duration
    ) {
        self.text = text
        self.segments = segments
        self.audioDuration = audioDuration
        self.processingDuration = processingDuration
    }
}

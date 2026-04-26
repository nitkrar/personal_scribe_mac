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

    // MARK: - Optional adapter metadata (#078.3, L11)
    //
    // These fields are populated only by transcribers whose
    // `TranscriberCapabilities` advertise the corresponding flag.
    // Adapters that don't surface a metadata field leave it `nil`.
    // All existing call sites compile without changes — every new
    // field defaults to `nil`.

    /// Overall confidence in `[0, 1]`. `nil` when the adapter
    /// doesn't surface confidence (e.g. Qwen3 ASR).
    public let confidence: Float?

    /// Per-token timings. `nil` when the adapter doesn't surface
    /// token-level timings.
    public let tokenTimings: [TokenTiming]?

    /// Adapter-internal timing measurements. `nil` when the adapter
    /// doesn't expose them.
    public let performanceMetrics: TranscriberPerformanceMetrics?

    /// Custom-vocabulary terms the CTC layer flagged as detected
    /// in the audio. `nil` when the adapter doesn't accept a custom
    /// vocabulary.
    public let ctcDetectedTerms: [String]?

    /// Custom-vocabulary terms the CTC layer applied to the final
    /// transcript text. `nil` when the adapter doesn't accept a
    /// custom vocabulary.
    public let ctcAppliedTerms: [String]?

    public init(
        text: String,
        segments: [Segment] = [],
        audioDuration: Duration,
        processingDuration: Duration,
        confidence: Float? = nil,
        tokenTimings: [TokenTiming]? = nil,
        performanceMetrics: TranscriberPerformanceMetrics? = nil,
        ctcDetectedTerms: [String]? = nil,
        ctcAppliedTerms: [String]? = nil
    ) {
        self.text = text
        self.segments = segments
        self.audioDuration = audioDuration
        self.processingDuration = processingDuration
        self.confidence = confidence
        self.tokenTimings = tokenTimings
        self.performanceMetrics = performanceMetrics
        self.ctcDetectedTerms = ctcDetectedTerms
        self.ctcAppliedTerms = ctcAppliedTerms
    }
}

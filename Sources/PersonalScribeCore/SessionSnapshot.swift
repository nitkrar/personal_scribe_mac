import Foundation

public struct SessionSnapshot: Sendable, Equatable {
    public var sessionState: SessionState
    public var activeStage: PipelineStepID?
    public var transcriptProgress: TranscriptProgress?
    public var lastCompletedResult: TranscriptionResult?
    public var recordingDuration: Duration?
    public var modelDownloadProgress: ModelDownloadProgress?
    public var reportedError: ReportedError?
    /// True while a VAD auto-stop grace timer is pending (#046 Stage B).
    /// Cleared atomically when the grace resolves (fires, cancels, or errors).
    public var vadAutoStopGracePending: Bool
    /// Wall-clock deadline for the pending grace timer. Paired with
    /// `vadAutoStopGracePending`; nil whenever pending is false.
    public var vadAutoStopGraceDeadline: Date?
    /// Producer-owned identity assigned each time an auto-stop fires via
    /// the VAD path. Consumers cache last-seen locally and render the
    /// "Auto stopped" notification once per new token. Never set by
    /// manual-stop paths. Codex-recommended replacement for the broken
    /// consumer-clears Bool latch.
    public var vadAutoStopFireToken: UUID?

    public init(
        sessionState: SessionState = .idle,
        activeStage: PipelineStepID? = nil,
        transcriptProgress: TranscriptProgress? = nil,
        lastCompletedResult: TranscriptionResult? = nil,
        recordingDuration: Duration? = nil,
        modelDownloadProgress: ModelDownloadProgress? = nil,
        reportedError: ReportedError? = nil,
        vadAutoStopGracePending: Bool = false,
        vadAutoStopGraceDeadline: Date? = nil,
        vadAutoStopFireToken: UUID? = nil
    ) {
        self.sessionState = sessionState
        self.activeStage = activeStage
        self.transcriptProgress = transcriptProgress
        self.lastCompletedResult = lastCompletedResult
        self.recordingDuration = recordingDuration
        self.modelDownloadProgress = modelDownloadProgress
        self.reportedError = reportedError
        self.vadAutoStopGracePending = vadAutoStopGracePending
        self.vadAutoStopGraceDeadline = vadAutoStopGraceDeadline
        self.vadAutoStopFireToken = vadAutoStopFireToken
    }
}

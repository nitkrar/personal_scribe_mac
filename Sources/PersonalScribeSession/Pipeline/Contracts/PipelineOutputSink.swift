import PersonalScribeCore

public protocol PipelineOutputSink: Sendable {
    func deliverPartial(_ revision: TranscriptProgress) async throws
    func deliverFinal(_ result: TranscriptionResult) async throws
    func resetForNewSession() async
}

import SeshatCore

public protocol SessionPipelining: Sendable {
    func toggleCapture() async
    func prepareTranscriber() async throws
    func snapshot() -> PipelineSnapshot
    func snapshotStream() -> AsyncStream<PipelineSnapshot>
    func audioLevelStream() -> AsyncStream<Float>
    func modelDownloadProgress() -> AsyncStream<ModelDownloadProgress>
}

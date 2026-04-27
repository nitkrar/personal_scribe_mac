import Foundation
import PersonalScribeCore

public protocol ModelBoundProcessorProviding: Sendable {
    func transcriber(for descriptor: ModelDescriptor) throws -> any Transcriber
    func streamingTranscriber(for descriptor: ModelDescriptor) throws -> any StreamingTranscriber
    func diarizer(for descriptor: ModelDescriptor) throws -> any SpeakerDiarizer
    func isDownloaded(_ descriptor: ModelDescriptor) -> Bool
    func download(
        _ descriptor: ModelDescriptor,
        progress: @escaping @Sendable (ModelDownloadProgress) -> Void
    ) async throws
    func removeDownloadedFiles(_ descriptor: ModelDescriptor) throws

    /// Drop the cached adapter for `descriptor` so its loaded model
    /// state is released. The next call to `transcriber(for:)` /
    /// `streamingTranscriber(for:)` / `diarizer(for:)` rebuilds a
    /// fresh adapter and re-runs `prepare()` on it.
    ///
    /// Safe to call when no adapter exists for the descriptor — no-op.
    /// `ActiveModelService.setActive(_:)` calls this on the previously
    /// active descriptor for the same kind so a switch does not leak
    /// the prior model's CoreML weights into the app's resident set.
    func evict(_ descriptor: ModelDescriptor)
}

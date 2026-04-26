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
}

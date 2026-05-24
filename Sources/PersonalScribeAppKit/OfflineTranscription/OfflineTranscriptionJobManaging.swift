import Foundation
import PersonalScribeSession

protocol OfflineTranscriptionJobManaging: Sendable {
    func enqueueFile(url: URL, descriptorID: String, diarize: Bool) async -> UUID
    func reTranscribe(sourceFilename: String) async -> UUID
    func cancelJob(id: UUID) async
    func dequeueJob(id: UUID) async
    func snapshot() async -> [OfflineTranscriptionCoordinator.Job]
    func snapshotStream() async -> AsyncStream<[OfflineTranscriptionCoordinator.Job]>
}

extension OfflineTranscriptionCoordinator: OfflineTranscriptionJobManaging {}

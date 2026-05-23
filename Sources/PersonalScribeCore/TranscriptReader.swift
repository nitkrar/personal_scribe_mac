import Foundation

public protocol TranscriptReading: Sendable {
    func recent(limit: Int) async -> [TranscriptEntry]
    func search(query: String) async -> [TranscriptEntry]
    func all() async -> [TranscriptEntry]
}

public protocol TranscriptDeleting: Sendable {
    func delete(id: UUID) async throws
}

public protocol TranscriptUpdating: Sendable {
    func update(id: UUID, text: String) async throws
}

public protocol TranscriptAudioFilenameNullifying: Sendable {
    func nullifyAudioFilenames(_ filenames: [String]) async throws
}

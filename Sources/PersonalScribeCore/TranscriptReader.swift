import Foundation

public protocol TranscriptReading: Sendable {
    func recent(limit: Int) async -> [TranscriptEntry]
    func search(query: String) async -> [TranscriptEntry]
    func all() async -> [TranscriptEntry]
}

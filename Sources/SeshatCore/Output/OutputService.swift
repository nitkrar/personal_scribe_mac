@MainActor
public protocol OutputService: Sendable {
    func paste(text: String) async throws
    func copy(text: String) async throws
    func beginStream() -> any OutputStreamHandle
}

@MainActor
public protocol OutputStreamHandle: Sendable {
    func append(_ chunk: String)
    func finalize()
}

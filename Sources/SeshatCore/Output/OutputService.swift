@MainActor
public protocol OutputService: AnyObject, Sendable {
    func deliverBatch(text: String) async -> OutputResult
}

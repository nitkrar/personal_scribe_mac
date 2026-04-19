public protocol PostProcessingStage: Sendable {
    var name: String { get }
    func apply(_ text: String, context: PostProcessingContext) async throws -> String
}

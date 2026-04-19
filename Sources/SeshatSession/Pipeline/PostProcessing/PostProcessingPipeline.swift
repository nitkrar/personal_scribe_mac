public protocol PostProcessingPipeline: Sendable {
    func run(_ text: String, context: PostProcessingContext) async throws -> String
}

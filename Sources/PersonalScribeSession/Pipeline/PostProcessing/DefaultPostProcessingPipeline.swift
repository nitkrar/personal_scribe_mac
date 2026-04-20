public struct DefaultPostProcessingPipeline: PostProcessingPipeline {
    private let stages: [any PostProcessingStage]

    public init() {
        stages = [FillerRemovalStage(), BasicPunctuationStage()]
    }

    public init(stages: [any PostProcessingStage]) {
        self.stages = stages
    }

    public func run(_ text: String, context: PostProcessingContext) async throws -> String {
        var current = text
        for stage in stages {
            current = try await stage.apply(current, context: context)
        }
        return current
    }
}

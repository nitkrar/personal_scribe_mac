public protocol PipelineContextProviding: Sendable {
    func currentContext() -> PipelineContextSnapshot
}

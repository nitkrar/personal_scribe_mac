import PersonalScribeCore

struct PipelineStageFailure: Error, Sendable, Equatable {
    let stage: PipelineStageID
    let detail: String
    let mappedError: PersonalScribeError

    init(stage: PipelineStageID, detail: String, mappedError: PersonalScribeError) {
        self.stage = stage
        self.detail = detail
        self.mappedError = mappedError
    }
}

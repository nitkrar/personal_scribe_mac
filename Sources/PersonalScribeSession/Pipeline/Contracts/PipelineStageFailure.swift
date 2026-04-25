import PersonalScribeCore

struct PipelineStageFailure: Error, Sendable, Equatable {
    let stage: PipelineStepID
    let detail: String
    let mappedError: PersonalScribeError

    init(stage: PipelineStepID, detail: String, mappedError: PersonalScribeError) {
        self.stage = stage
        self.detail = detail
        self.mappedError = mappedError
    }
}

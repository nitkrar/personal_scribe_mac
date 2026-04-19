import SeshatCore

struct PipelineStageFailure: Error, Sendable, Equatable {
    let stage: PipelineStageID
    let detail: String
    let mappedError: SeshatError

    init(stage: PipelineStageID, detail: String, mappedError: SeshatError) {
        self.stage = stage
        self.detail = detail
        self.mappedError = mappedError
    }
}

import PersonalScribeCore

struct PipelineStageFailure: Error, Sendable, Equatable {
    let stage: PipelineStepID
    let detail: String
    let mappedError: PersonalScribeError
    let reportedError: ReportedError?

    init(
        stage: PipelineStepID,
        detail: String,
        mappedError: PersonalScribeError,
        reportedError: ReportedError? = nil
    ) {
        self.stage = stage
        self.detail = detail
        self.mappedError = mappedError
        self.reportedError = reportedError
    }
}

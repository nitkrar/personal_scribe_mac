import PersonalScribeCore

@MainActor
final class RecordingOutputService: OutputService, @unchecked Sendable {
    private(set) var deliveredTexts: [String] = []
    private(set) var deliveredSinks: [[BoundOutputSink]] = []
    var result: OutputResult

    init(result: OutputResult = .delivered(target: .frontmostApp, delivery: .paste)) {
        self.result = result
    }

    func deliverBatch(text: String, sinks: [BoundOutputSink]) async -> OutputResult {
        deliveredTexts.append(text)
        deliveredSinks.append(sinks)
        return result
    }
}

@MainActor
final class FailingOutputService: OutputService, @unchecked Sendable {
    private(set) var deliveredTexts: [String] = []
    private(set) var deliveredSinks: [[BoundOutputSink]] = []
    private let error: OutputError

    init(error: OutputError = .clipboardWriteFailed) {
        self.error = error
    }

    func deliverBatch(text: String, sinks: [BoundOutputSink]) async -> OutputResult {
        deliveredTexts.append(text)
        deliveredSinks.append(sinks)
        return .failed(error)
    }
}

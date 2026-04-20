import SeshatCore

@MainActor
final class RecordingOutputService: OutputService, @unchecked Sendable {
    private(set) var deliveredTexts: [String] = []
    var result: OutputResult

    init(result: OutputResult = .delivered(target: .frontmostApp, delivery: .paste)) {
        self.result = result
    }

    func deliverBatch(text: String) async -> OutputResult {
        deliveredTexts.append(text)
        return result
    }
}

@MainActor
final class FailingOutputService: OutputService, @unchecked Sendable {
    private(set) var deliveredTexts: [String] = []
    private let error: OutputError

    init(error: OutputError = .clipboardWriteFailed) {
        self.error = error
    }

    func deliverBatch(text: String) async -> OutputResult {
        deliveredTexts.append(text)
        return .failed(error)
    }
}

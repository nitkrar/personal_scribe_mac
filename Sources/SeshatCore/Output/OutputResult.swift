public enum OutputResult: Equatable, Sendable {
    case delivered(target: OutputTarget, delivery: OutputDelivery)
    case ignoredEmptyInput
    case failed(OutputError)
}

public enum OutputResult: Equatable, Sendable {
    case delivered(target: OutputTarget, delivery: OutputDelivery)
    /// ⌘V was posted into `appName` (#117).
    case pasted(appName: String)
    case ignoredEmptyInput
    case failed(OutputError)
}

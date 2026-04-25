public protocol AppStoreActiveModeProviding: Sendable {
    func currentActiveMode() -> WorkflowMode?
    func activeModeStream() -> AsyncStream<WorkflowMode?>
}

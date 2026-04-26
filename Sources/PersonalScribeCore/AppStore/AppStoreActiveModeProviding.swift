public protocol AppStoreActiveModeProviding: Sendable {
    func currentActiveMode() -> LegacyWorkflowMode?
    func activeModeStream() -> AsyncStream<LegacyWorkflowMode?>
}

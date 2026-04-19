public protocol AppStoreActiveModeProviding: Sendable {
    func currentActiveMode() -> ModeDescriptor?
    func activeModeStream() -> AsyncStream<ModeDescriptor?>
}

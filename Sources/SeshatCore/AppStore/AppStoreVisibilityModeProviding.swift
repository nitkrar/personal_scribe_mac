public protocol AppStoreVisibilityModeProviding: Sendable {
    func currentVisibilityMode() -> AppStoreVisibilityMode
    func visibilityModeStream() -> AsyncStream<AppStoreVisibilityMode>
}

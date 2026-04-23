public protocol AppStoreSessionProviding: Sendable {
    func snapshotStream() -> AsyncStream<SessionSnapshot>
}

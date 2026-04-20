import Foundation

public protocol AppStoreClock: Sendable {
    func now() -> Duration
    func sleep(for duration: Duration) async throws
}

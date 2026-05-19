import Foundation

public enum StreamingDiagnosticsSession {
    public struct Context: Sendable, Equatable {
        public let sessionID: String
        public let sessionStartedAt: ContinuousClock.Instant

        public init(
            sessionID: String = UUID().uuidString,
            sessionStartedAt: ContinuousClock.Instant = ContinuousClock().now
        ) {
            self.sessionID = sessionID
            self.sessionStartedAt = sessionStartedAt
        }

        public func elapsedMilliseconds(
            now: ContinuousClock.Instant = ContinuousClock().now
        ) -> Int64 {
            let duration = sessionStartedAt.duration(to: now)
            let components = duration.components
            let secondsMs = components.seconds * 1_000
            let attosecondsMs = components.attoseconds / 1_000_000_000_000_000
            return secondsMs + attosecondsMs
        }
    }

    @TaskLocal
    public static var current: Context?
}

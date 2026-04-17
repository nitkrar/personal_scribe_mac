import Foundation

public struct PCMBuffer: Sendable, Equatable {
    public let samples: [Float]
    public let sampleRate: Double
    public let channelCount: Int
    public let timestamp: ContinuousClock.Instant

    public init(
        samples: [Float],
        sampleRate: Double = SeshatConfig.sampleRate,
        channelCount: Int = SeshatConfig.channelCount,
        timestamp: ContinuousClock.Instant
    ) throws {
        self.samples = samples
        self.sampleRate = sampleRate
        self.channelCount = channelCount
        self.timestamp = timestamp
    }

    public var frameCount: Int {
        samples.count
    }

    public var duration: Duration {
        .zero
    }
}

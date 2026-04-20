import Foundation

public struct PCMBuffer: Sendable, Equatable {
    public let samples: [Float]
    public let sampleRate: Double
    public let channelCount: Int
    public let timestamp: ContinuousClock.Instant

    public init(
        samples: [Float],
        sampleRate: Double = AppConfig.sampleRate,
        channelCount: Int = AppConfig.channelCount,
        timestamp: ContinuousClock.Instant
    ) throws {
        guard sampleRate > 0, channelCount > 0, samples.count.isMultiple(of: channelCount) else {
            throw PersonalScribeError.resampleFailure
        }

        self.samples = samples
        self.sampleRate = sampleRate
        self.channelCount = channelCount
        self.timestamp = timestamp
    }

    public var frameCount: Int {
        samples.count / channelCount
    }

    public var duration: Duration {
        .seconds(Double(frameCount) / sampleRate)
    }
}

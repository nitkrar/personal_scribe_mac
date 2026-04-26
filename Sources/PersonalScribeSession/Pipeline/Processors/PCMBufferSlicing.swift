import Foundation
import PersonalScribeCore

enum PCMBufferSlicing {
    static func slice(
        _ buffer: PCMBuffer,
        from: Duration,
        to: Duration,
        sampleRate: Double
    ) throws -> PCMBuffer {
        guard sampleRate == buffer.sampleRate else {
            throw PersonalScribeError.resampleFailure
        }

        let frameRange = clampedFrameRange(
            from: from,
            to: to,
            sampleRate: sampleRate,
            frameCount: buffer.frameCount
        )
        let sampleRange = (frameRange.lowerBound * buffer.channelCount)..<(frameRange.upperBound * buffer.channelCount)
        let timestamp = buffer.timestamp.advanced(
            by: duration(forFrameCount: frameRange.lowerBound, sampleRate: sampleRate)
        )

        return try PCMBuffer(
            samples: Array(buffer.samples[sampleRange]),
            sampleRate: buffer.sampleRate,
            channelCount: buffer.channelCount,
            timestamp: timestamp
        )
    }
}

private extension PCMBufferSlicing {
    static func clampedFrameRange(
        from: Duration,
        to: Duration,
        sampleRate: Double,
        frameCount: Int
    ) -> Range<Int> {
        let rawStart = Int(floor(seconds(from) * sampleRate))
        let rawEnd = Int(ceil(seconds(to) * sampleRate))
        let lowerBound = min(max(rawStart, 0), frameCount)
        let upperBound = min(max(rawEnd, 0), frameCount)

        guard upperBound > lowerBound else {
            return lowerBound..<lowerBound
        }

        return lowerBound..<upperBound
    }

    static func seconds(_ duration: Duration) -> Double {
        let components = duration.components
        let attosecondsPerSecond = 1_000_000_000_000_000_000.0
        return Double(components.seconds) + (Double(components.attoseconds) / attosecondsPerSecond)
    }

    static func duration(forFrameCount frameCount: Int, sampleRate: Double) -> Duration {
        .seconds(Double(frameCount) / sampleRate)
    }
}

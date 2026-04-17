import XCTest
import SeshatCore
@testable import SeshatAudio

final class AudioResamplerTests: XCTestCase {
    func testResampleConvertsMono44100ToMono16000PCMBuffer() async throws {
        let resampler = try AudioResampler(inputSampleRate: 44_100)

        // 1 second of a 440 Hz sine @ 44.1kHz
        let frameCount = 44_100
        var samples = [Float](repeating: 0, count: frameCount)
        for i in 0..<frameCount {
            samples[i] = sin(2 * .pi * 440 * Float(i) / 44_100)
        }

        let timestamp = ContinuousClock.now
        let buffer = try await resampler.resample(monoSamples: samples, timestamp: timestamp)

        XCTAssertEqual(buffer.sampleRate, 16_000)
        XCTAssertEqual(buffer.channelCount, 1)
        // Resampled frame count should be ~16000 (1 second at 16kHz)
        XCTAssertTrue(abs(buffer.frameCount - 16_000) <= 8,
                      "frame count \(buffer.frameCount) not within 8 of 16000")
        XCTAssertEqual(buffer.timestamp, timestamp)

        // Signal energy should be non-zero (not just a flat zero buffer)
        let energy = buffer.samples.reduce(0) { $0 + abs($1) }
        XCTAssertGreaterThan(energy, 1.0)
    }

    func testResamplePassthroughAt16000() async throws {
        let resampler = try AudioResampler(inputSampleRate: 16_000)
        let samples: [Float] = Array(repeating: 0.25, count: 1_600)
        let ts = ContinuousClock.now
        let buffer = try await resampler.resample(monoSamples: samples, timestamp: ts)
        XCTAssertEqual(buffer.sampleRate, 16_000)
        XCTAssertEqual(buffer.channelCount, 1)
        XCTAssertEqual(buffer.frameCount, 1_600)
    }
}


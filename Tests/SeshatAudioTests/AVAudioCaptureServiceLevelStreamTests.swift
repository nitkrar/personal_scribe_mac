import Foundation
import XCTest
import SeshatCore
@testable import SeshatAudio

/// Unit tests for the additive 10 Hz RMS audio-level stream added in phase-2
/// step 2.9. The stream is published alongside the existing PCM stream so
/// SwiftUI surfaces (Sprint 2 pill rewrite, Phase 3 onboarding) can bind to a
/// live audio-level value without having to re-compute RMS themselves.
///
/// Cadence contract: emissions are derived from audio-buffer cadence (not a
/// wall-clock Timer). Target ~10 Hz means the service accumulates ≥ 100 ms of
/// audio before emitting a single RMS sample.
final class AVAudioCaptureServiceLevelStreamTests: XCTestCase {
    // MARK: - RMS math

    func testRMSOfConstantUnitSignalIsOne() {
        let samples = [Float](repeating: 1.0, count: 1_600)
        XCTAssertEqual(AudioLevelCalculator.rms(samples: samples), 1.0, accuracy: 1e-5)
    }

    func testRMSOfSilenceIsZero() {
        let samples = [Float](repeating: 0, count: 1_600)
        XCTAssertEqual(AudioLevelCalculator.rms(samples: samples), 0.0, accuracy: 1e-6)
    }

    func testRMSOfUnitAmplitudeSineIsOneOverRootTwo() {
        let sampleRate: Double = 16_000
        let frequency: Double = 440
        let frames = 16_000 // 1 second
        var samples = [Float](repeating: 0, count: frames)
        for i in 0..<frames {
            samples[i] = Float(sin(2 * .pi * frequency * Double(i) / sampleRate))
        }
        XCTAssertEqual(AudioLevelCalculator.rms(samples: samples), Float(1.0 / sqrt(2.0)), accuracy: 0.01)
    }

    func testNormalizedLevelFlooredBelowThreshold() {
        // A very quiet signal (RMS ≈ 0.0005) is below the -60 dBFS floor and
        // should clamp to 0 so the idle waveform doesn't jitter on noise.
        let samples = [Float](repeating: 0.0005, count: 1_600)
        XCTAssertEqual(AudioLevelCalculator.normalizedLevel(samples: samples), 0.0, accuracy: 1e-6)
    }

    func testNormalizedLevelClampedToOne() {
        // A signal louder than peak should clamp to 1.0 rather than overflow.
        let samples = [Float](repeating: 2.0, count: 1_600)
        XCTAssertEqual(AudioLevelCalculator.normalizedLevel(samples: samples), 1.0, accuracy: 1e-6)
    }

    func testNormalizedLevelIsMonotonicInAmplitude() {
        let quiet = [Float](repeating: 0.1, count: 1_600)
        let loud  = [Float](repeating: 0.5, count: 1_600)
        XCTAssertLessThan(
            AudioLevelCalculator.normalizedLevel(samples: quiet),
            AudioLevelCalculator.normalizedLevel(samples: loud)
        )
    }

    // MARK: - Level stream integration

    func testAudioLevelStreamEmitsSamplesAtRoughly10Hz() async throws {
        let box = ThreadSafeEngineBox()
        let service = AVAudioCaptureService(
            authorizationStatusProvider: { .authorized },
            engineDriver: .testStub(sampleRate: 16_000, channels: 1, box: box),
            resamplerFactory: { rate, logger in
                try AudioResampler(inputSampleRate: rate, logger: logger)
            }
        )

        let pcmStream = try await service.start()
        let levelStream = await service.audioLevelStream()

        // Emit 10 buffers of 1_600 frames each → 1.0 s of audio at 16 kHz.
        // Each buffer is exactly 100 ms, so we expect ~10 level samples.
        let samplesPerBuffer = 1_600
        let buffersToEmit = 10

        // Drive PCM stream drainage so the actor keeps handling tap samples.
        let drainTask = Task {
            var iterator = pcmStream.makeAsyncIterator()
            var count = 0
            while count < buffersToEmit {
                if try await iterator.next() == nil { break }
                count += 1
            }
        }

        for _ in 0..<buffersToEmit {
            let buffer = AudioTestSupport.makeFloatBuffer(
                sampleRate: 16_000,
                channels: 1,
                frames: samplesPerBuffer
            ) { _, _ in 0.5 }
            box.emit(buffer)
        }

        // Collect level samples with a small deadline guard.
        var collected: [Float] = []
        let deadline = ContinuousClock.now.advanced(by: .seconds(3))
        var iterator = levelStream.makeAsyncIterator()
        collected.reserveCapacity(buffersToEmit)
        while collected.count < buffersToEmit, ContinuousClock.now < deadline {
            guard let level = await iterator.next() else { break }
            collected.append(level)
        }

        _ = try? await drainTask.value
        await service.stop()

        // Drain any remaining buffered levels emitted before stop(); this
        // ensures the terminal finish() is observed and the stream is idle.
        while await iterator.next() != nil {
            // drain
        }

        // We should have between `buffersToEmit - 1` and `buffersToEmit + 1`
        // samples — exact count allowed to drift by one because of internal
        // accumulator rounding between 100 ms windows.
        XCTAssertGreaterThanOrEqual(collected.count, buffersToEmit - 1)
        XCTAssertLessThanOrEqual(collected.count, buffersToEmit + 1)

        // Every emitted level must be in [0, 1].
        for level in collected {
            XCTAssertGreaterThanOrEqual(level, 0.0)
            XCTAssertLessThanOrEqual(level, 1.0)
        }

        // A 0.5-amplitude constant signal has RMS 0.5; post-floor/clip the
        // normalized level should sit in a plausible mid range.
        let average = collected.reduce(0, +) / Float(max(collected.count, 1))
        XCTAssertGreaterThan(average, 0.2)
        XCTAssertLessThan(average, 1.0)
    }

    func testAudioLevelStreamFinishesWhenCaptureStops() async throws {
        let box = ThreadSafeEngineBox()
        let service = AVAudioCaptureService(
            authorizationStatusProvider: { .authorized },
            engineDriver: .testStub(sampleRate: 16_000, channels: 1, box: box),
            resamplerFactory: { rate, logger in
                try AudioResampler(inputSampleRate: rate, logger: logger)
            }
        )

        _ = try await service.start()
        let levelStream = await service.audioLevelStream()

        await service.stop()

        // After stop, the level stream must terminate within a short window
        // (no hanging continuation). Drain to the sentinel `nil`.
        var iterator = levelStream.makeAsyncIterator()
        let deadline = ContinuousClock.now.advanced(by: .seconds(1))
        while ContinuousClock.now < deadline {
            if await iterator.next() == nil {
                // stream finished as expected
                return
            }
        }
        XCTFail("Audio-level stream failed to finish within 1s of stop()")
    }

    func testAudioLevelStreamEmitsSilenceAsZero() async throws {
        let box = ThreadSafeEngineBox()
        let service = AVAudioCaptureService(
            authorizationStatusProvider: { .authorized },
            engineDriver: .testStub(sampleRate: 16_000, channels: 1, box: box),
            resamplerFactory: { rate, logger in
                try AudioResampler(inputSampleRate: rate, logger: logger)
            }
        )

        let pcmStream = try await service.start()
        let levelStream = await service.audioLevelStream()

        let drainTask = Task {
            var iterator = pcmStream.makeAsyncIterator()
            for _ in 0..<3 {
                if try await iterator.next() == nil { break }
            }
        }

        for _ in 0..<3 {
            let silence = AudioTestSupport.makeFloatBuffer(
                sampleRate: 16_000,
                channels: 1,
                frames: 1_600
            ) { _, _ in 0.0 }
            box.emit(silence)
        }

        var iterator = levelStream.makeAsyncIterator()
        let deadline = ContinuousClock.now.advanced(by: .seconds(2))
        var firstLevel: Float?
        while ContinuousClock.now < deadline {
            if let level = await iterator.next() {
                firstLevel = level
                break
            } else {
                break
            }
        }

        _ = try? await drainTask.value
        await service.stop()

        XCTAssertNotNil(firstLevel)
        XCTAssertEqual(firstLevel ?? 1.0, 0.0, accuracy: 1e-6)
    }
}

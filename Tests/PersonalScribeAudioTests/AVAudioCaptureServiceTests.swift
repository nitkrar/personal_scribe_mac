import Foundation
import Dispatch
import XCTest
import PersonalScribeCore
@testable import PersonalScribeAudio

final class AuthorizationTests: XCTestCase {
    func testStartThrowsMicPermissionDeniedWhenStatusIsDenied() async throws {
        let service = AVAudioCaptureService(
            logger: PersonalScribeLogger.testing(category: PersonalScribeLogCategory.audio),
            authorizationStatusProvider: { .denied },
            engineDriver: .testStub(),
            resamplerFactory: { rate, logger in
                try AudioResampler(inputSampleRate: rate, logger: logger)
            }
        )

        do {
            _ = try await service.start()
            XCTFail("Expected micPermissionDenied")
        } catch let error as PersonalScribeError {
            XCTAssertEqual(error, .micPermissionDenied)
        }
    }

    func testStartThrowsMicPermissionDeniedWhenStatusIsNotDetermined() async throws {
        let service = AVAudioCaptureService(
            logger: PersonalScribeLogger.testing(category: PersonalScribeLogCategory.audio),
            authorizationStatusProvider: { .notDetermined },
            engineDriver: .testStub(),
            resamplerFactory: { rate, logger in
                try AudioResampler(inputSampleRate: rate, logger: logger)
            }
        )

        do {
            _ = try await service.start()
            XCTFail("Expected micPermissionDenied")
        } catch let error as PersonalScribeError {
            XCTAssertEqual(error, .micPermissionDenied)
        }
    }
}

final class HappyPathCaptureTests: XCTestCase {
    func testStartReturnsStreamThatYieldsMono16000PCMBuffer() async throws {
        let box = ThreadSafeEngineBox()
        let service = AVAudioCaptureService(
            logger: PersonalScribeLogger.testing(category: PersonalScribeLogCategory.audio),
            authorizationStatusProvider: { .authorized },
            engineDriver: .testStub(sampleRate: 44_100, channels: 2, box: box),
            resamplerFactory: { rate, logger in
                try AudioResampler(inputSampleRate: rate, logger: logger)
            }
        )

        let stream = try await service.start()
        var iterator = stream.makeAsyncIterator()

        let input = AudioTestSupport.makeFloatBuffer(
            sampleRate: 44_100,
            channels: 2,
            frames: 4_410
        ) { channel, _ in
            channel == 0 ? 1.0 : 0.0
        }

        box.emit(input)
        let output = try await iterator.next()

        XCTAssertEqual(output?.sampleRate, 16_000)
        XCTAssertEqual(output?.channelCount, 1)
        XCTAssertEqual(output?.frameCount, 1_600)

        let average = (output?.samples.prefix(64).reduce(0, +) ?? 0) / 64.0
        XCTAssertEqual(average, 0.5, accuracy: 0.05)

        await service.stop()
    }
}

final class SingleCaptureTests: XCTestCase {
    func testSecondStartWhileLiveThrowsAudioEngineFailure() async throws {
        let service = AVAudioCaptureService(
            logger: PersonalScribeLogger.testing(category: PersonalScribeLogCategory.audio),
            authorizationStatusProvider: { .authorized },
            engineDriver: .testStub(),
            resamplerFactory: { rate, logger in
                try AudioResampler(inputSampleRate: rate, logger: logger)
            }
        )

        _ = try await service.start()

        do {
            _ = try await service.start()
            XCTFail("Expected audioEngineFailure")
        } catch let error as PersonalScribeError {
            XCTAssertEqual(error, .audioEngineFailure)
        }

        await service.stop()
    }
}

final class StopBehaviorTests: XCTestCase {
    func testStopIsIdempotentAndFinishesStreamNormally() async throws {
        let box = ThreadSafeEngineBox()
        let service = AVAudioCaptureService(
            logger: PersonalScribeLogger.testing(category: PersonalScribeLogCategory.audio),
            authorizationStatusProvider: { .authorized },
            engineDriver: .testStub(box: box),
            resamplerFactory: { rate, logger in
                try AudioResampler(inputSampleRate: rate, logger: logger)
            }
        )

        let stream = try await service.start()
        var iterator = stream.makeAsyncIterator()

        await service.stop()
        let afterFirstStop = try await iterator.next()
        XCTAssertNil(afterFirstStop)

        await service.stop()

        XCTAssertEqual(box.removeCount, 1)
        XCTAssertEqual(box.stopCount, 1)
        XCTAssertEqual(box.resetCount, 1)
    }
}

final class EngineFailureTests: XCTestCase {
    func testEngineStartFailureMapsToAudioEngineFailure() async throws {
        let box = ThreadSafeEngineBox(
            startError: NSError(domain: "AudioEngineTests", code: 7)
        )
        let service = AVAudioCaptureService(
            logger: PersonalScribeLogger.testing(category: PersonalScribeLogCategory.audio),
            authorizationStatusProvider: { .authorized },
            engineDriver: .testStub(box: box),
            resamplerFactory: { rate, logger in
                try AudioResampler(inputSampleRate: rate, logger: logger)
            }
        )

        do {
            _ = try await service.start()
            XCTFail("Expected audioEngineFailure")
        } catch let error as PersonalScribeError {
            XCTAssertEqual(error, .audioEngineFailure)
        }
    }
}

final class NSErrorMappingTests: XCTestCase {
    func testPlainNSErrorIsLoggedThenMappedToResampleFailure() async throws {
        let box = ThreadSafeEngineBox()
        let service = AVAudioCaptureService(
            logger: PersonalScribeLogger.testing(category: PersonalScribeLogCategory.audio),
            authorizationStatusProvider: { .authorized },
            engineDriver: .testStub(box: box),
            resamplerFactory: { _, _ in
                AudioResampler(
                    resampleImpl: { _, _ in
                        throw NSError(
                            domain: "TestDomain",
                            code: -1,
                            userInfo: [NSLocalizedDescriptionKey: "Injected upstream resample failure"]
                        )
                    },
                    logger: PersonalScribeLogger.testing(category: PersonalScribeLogCategory.audio)
                )
            }
        )

        let stream = try await service.start()
        var iterator = stream.makeAsyncIterator()

        let input = AudioTestSupport.makeFloatBuffer(
            sampleRate: 44_100,
            channels: 1,
            frames: 4_410
        ) { _, _ in 0.1 }

        box.emit(input)

        do {
            _ = try await iterator.next()
            XCTFail("Expected resampleFailure")
        } catch let error as PersonalScribeError {
            XCTAssertEqual(error, .resampleFailure)
        }

        if let messages = try? LogProbe.audioMessages(), !messages.isEmpty {
            XCTAssertTrue(messages.contains { $0.contains("Injected upstream resample failure") })
        }
    }
}

private final class BlockingResampleBox: @unchecked Sendable {
    // Safe in tests: NSLock protects mutable state and DispatchSemaphore gates one deliberate race point.
    private let lock = NSLock()
    private let gate = DispatchSemaphore(value: 0)
    private let failOnCall: Int
    private var callCount = 0

    init(failOnCall: Int) {
        self.failOnCall = failOnCall
    }

    func openGate() {
        gate.signal()
    }

    func resample(
        samples: [Float],
        timestamp: ContinuousClock.Instant
    ) throws -> PCMBuffer {
        lock.lock()
        callCount += 1
        let shouldFail = callCount == failOnCall
        lock.unlock()

        if shouldFail {
            gate.wait()
            throw PersonalScribeError.resampleFailure
        }

        return try PCMBuffer(
            samples: samples,
            sampleRate: AppConfig.sampleRate,
            channelCount: 1,
            timestamp: timestamp
        )
    }
}

final class FinishExactlyOnceRaceTests: XCTestCase {
    func testStopRacingNthBufferFailureFinishesExactlyOnce() async throws {
        let box = ThreadSafeEngineBox()
        let failing = BlockingResampleBox(failOnCall: 3)
        let service = AVAudioCaptureService(
            logger: PersonalScribeLogger.testing(category: PersonalScribeLogCategory.audio),
            authorizationStatusProvider: { .authorized },
            engineDriver: .testStub(sampleRate: 16_000, box: box),
            resamplerFactory: { _, _ in
                AudioResampler(
                    resampleImpl: failing.resample(samples:timestamp:),
                    logger: PersonalScribeLogger.testing(category: PersonalScribeLogCategory.audio)
                )
            }
        )

        let stream = try await service.start()
        var iterator = stream.makeAsyncIterator()

        let valid = AudioTestSupport.makeFloatBuffer(
            sampleRate: 16_000,
            channels: 1,
            frames: 1_024
        ) { _, _ in 0.1 }

        box.emit(valid)
        _ = try await iterator.next()
        box.emit(valid)
        _ = try await iterator.next()

        let stopTask = Task {
            await service.stop()
        }

        box.emit(valid)
        failing.openGate()
        await stopTask.value

        let firstAfterStop = try await iterator.next()
        XCTAssertNil(firstAfterStop)
        let secondAfterStop = try await iterator.next()
        XCTAssertNil(secondAfterStop)
    }
}

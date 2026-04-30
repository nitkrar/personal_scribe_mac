import Foundation
import XCTest
import PersonalScribeCore
@testable import PersonalScribeAudio

final class AVAudioCaptureServiceMuteTests: XCTestCase {
    func testStopRestoresOutputWhenStartingUnmuted() async throws {
        let recorder = MuterCallRecorder()
        let muter = SystemAudioMuter(
            read: { recorder.record(.read); return false },
            write: { recorder.record(.write($0)) }
        )
        let service = AVAudioCaptureService(
            logger: PersonalScribeLogger.testing(category: PersonalScribeLogCategory.audio),
            authorizationStatusProvider: { .authorized },
            engineDriver: .testStub(),
            resamplerFactory: { rate, logger in
                try AudioResampler(inputSampleRate: rate, logger: logger)
            },
            shouldMuteOutput: { true },
            systemAudioMuter: muter
        )

        _ = try await service.start()
        await service.stop()

        XCTAssertEqual(recorder.calls, [.read, .write(true), .write(false)])
    }

    func testStopPreservesAlreadyMutedState() async throws {
        let recorder = MuterCallRecorder()
        let muter = SystemAudioMuter(
            read: { true },
            write: { recorder.record(.write($0)) }
        )
        let service = AVAudioCaptureService(
            logger: PersonalScribeLogger.testing(category: PersonalScribeLogCategory.audio),
            authorizationStatusProvider: { .authorized },
            engineDriver: .testStub(),
            resamplerFactory: { rate, logger in
                try AudioResampler(inputSampleRate: rate, logger: logger)
            },
            shouldMuteOutput: { true },
            systemAudioMuter: muter
        )

        _ = try await service.start()
        await service.stop()

        XCTAssertEqual(recorder.calls, [.write(true), .write(true)])
    }

    func testRuntimeFailureStillRestoresMute() async throws {
        let recorder = MuterCallRecorder()
        let muter = SystemAudioMuter(
            read: { false },
            write: { recorder.record(.write($0)) }
        )
        let box = ThreadSafeEngineBox()
        let service = AVAudioCaptureService(
            logger: PersonalScribeLogger.testing(category: PersonalScribeLogCategory.audio),
            authorizationStatusProvider: { .authorized },
            engineDriver: .testStub(box: box),
            resamplerFactory: { _, _ in
                AudioResampler(
                    resampleImpl: { _, _ in
                    throw PersonalScribeError.resampleFailure
                    },
                    logger: PersonalScribeLogger.testing(category: PersonalScribeLogCategory.audio)
                )
            },
            shouldMuteOutput: { true },
            systemAudioMuter: muter
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
        } catch {
            // Expected — stream termination means finishWithError ran.
        }

        XCTAssertEqual(recorder.calls, [.write(true), .write(false)])
    }

    func testMuteDisabledSkipsMuterEntirely() async throws {
        let recorder = MuterCallRecorder()
        let muter = SystemAudioMuter(
            read: { recorder.record(.read); return false },
            write: { recorder.record(.write($0)) }
        )
        let service = AVAudioCaptureService(
            logger: PersonalScribeLogger.testing(category: PersonalScribeLogCategory.audio),
            authorizationStatusProvider: { .authorized },
            engineDriver: .testStub(),
            resamplerFactory: { rate, logger in
                try AudioResampler(inputSampleRate: rate, logger: logger)
            },
            shouldMuteOutput: { false },
            systemAudioMuter: muter
        )

        _ = try await service.start()
        await service.stop()

        XCTAssertTrue(recorder.calls.isEmpty)
    }
}

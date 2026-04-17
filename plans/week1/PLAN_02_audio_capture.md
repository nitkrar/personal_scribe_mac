# Plan 02: AVAudioEngine Capture + 16kHz Resampling

**Goal**: Ship production `AudioCapturing` conforming types in `PSAudio` that yield 16kHz mono Float32 `PCMBuffer` values from the microphone, with single-active-capture, idempotent stop, and exact-once termination.
**Architecture**: actor-wrapped `AVAudioEngine` input + `AVAudioConverter` resample chain; async stream of `PCMBuffer`; all errors mapped to `PSError`.
**Tech Stack**: Swift Concurrency, AVFoundation (`AVAudioEngine`, `AVAudioConverter`, `AVCaptureDevice`), XCTest.
**Depends on**: Plan 00 Section C.1, C.2, C.4, C.5 (contract); Plan 01 (scaffold).
**Plan 00 contract read**: Section C.1 (PCMBuffer), C.2 (AudioCapturing), C.4 (PSLogger), C.5 (PSConfig), D.1 (concurrency), D.6 (ownership).

## A. Reference implementation notes

### A.1 Apple APIs and why they matter here

- `AVAudioEngine.inputNode` is the only Week 1 production source.
- `installTap(onBus:bufferSize:format:block:)` is the buffer ingress point.
- `AVAudioConverter` owns sample-rate conversion to the `PSConfig` target format.
- `AVCaptureDevice.authorizationStatus(for: .audio)` is the only allowed permission check in this layer.
- `PSAudio` may check status; `PSAudio` must not prompt.

Relevant references:

- <https://developer.apple.com/documentation/avfaudio/avaudioengine>
- <https://developer.apple.com/documentation/avfaudio/avaudioconverter>
- <https://developer.apple.com/documentation/avfaudio/avaudiopcmbuffer>
- <https://developer.apple.com/documentation/avfoundation/avcapturedevice/1624584-authorizationstatus>

### A.2 Hard constraints to preserve from Plan 00

1. `PCMBuffer` is the only shared audio buffer type.
2. `AudioCapturing.start()` returns the single active capture stream.
3. A second live `start()` throws `PSError.audioEngineFailure`.
4. `stop()` is idempotent.
5. The stream finishes normally on `stop()`.
6. Runtime failures finish the stream with thrown `PSError`.
7. The dynamic error type is always `PSError`, never raw `NSError`.
8. Underlying concrete errors are logged before mapping.
9. Public concurrency remains Swift Concurrency only.
10. Plan 02 must not add VAD, prompt UI, device selection, or disk output.

### A.3 Design choices this plan pins

- `AVAudioCaptureService` is an actor and owns the engine adapter, resampler, continuation, and termination guard.
- `AudioResampler` is separately testable without a microphone and is the only `AVAudioPCMBuffer -> PCMBuffer` bridge.
- engine setup failures map to `PSError.audioEngineFailure`
- conversion failures map to `PSError.resampleFailure`
- explicit stop and runtime failure both route through one guarded finish helper

### A.4 Ambiguities and the plan’s resolution

#### Stereo-to-mono behavior

`AVAudioConverter` can handle format conversion, but channel-mix behavior is not a good thing to leave implicit in unit tests. This plan pins a deterministic policy:

- mono input: convert directly
- multi-channel input: average all channels into a temporary mono Float32 buffer
- then feed the mono buffer into `AVAudioConverter`

That still keeps `AVAudioConverter` as the resampling primitive while removing a test ambiguity.

`AVAudioEngine` is hard to fail deterministically in XCTest, so the plan uses internal seams for authorization, engine control, resampler injection, and failure logging. These stay inside `PSAudio`. Tap `bufferSize` is a private implementation detail; start with `1024`.

### A.5 Planned public PSAudio surface

```swift
import AVFoundation
import Foundation
import PSCore

public actor AudioResampler {
    public init(
        inputFormat: AVAudioFormat,
        logger: PSLogger = PSLogger(category: PSLogCategory.audio)
    ) throws

    public func resample(
        _ buffer: AVAudioPCMBuffer,
        timestamp: ContinuousClock.Instant
    ) throws -> PCMBuffer
}
```

```swift
import Foundation
import PSCore

public actor AVAudioCaptureService: AudioCapturing {
    public init(
        logger: PSLogger = PSLogger(category: PSLogCategory.audio)
    )

    public func start() async throws -> AsyncThrowingStream<PCMBuffer, Error>
    public func stop() async
}
```

### A.6 Internal seams required for TDD

Internal-only seam names to add:

- `SystemMicrophoneAuthorizationProvider`
- `DefaultAudioEngineClient`
- `AudioResampler: PCMResampling`
- `PSAudioFailureLogger`
- `MicrophoneAuthorizationProviding`
- `AudioEngineClient`
- `PCMResampling`
- `AudioFailureLogging`

### A.7 File ownership for Plan 02

Only these paths are in scope:

- `Sources/PSAudio/AudioResampler.swift`
- `Sources/PSAudio/AVAudioCaptureService.swift`
- `Tests/PSAudioTests/AudioResamplerScaffoldingTests.swift`
- `Tests/PSAudioTests/AudioResamplerTests.swift`
- `Tests/PSAudioTests/AVAudioCaptureServiceScaffoldingTests.swift`
- `Tests/PSAudioTests/AVAudioCaptureServiceTests.swift`

## B. Task breakdown

### B.0 Shared TDD loop

For every coding step:

1. add a failing test
2. run the smallest `swift test --filter ...` command
3. implement the minimum code to satisfy that test
4. rerun the same filter until green
5. commit with `git commit -m 'plan-02 step N: <desc>'`

### B.1 Shared test helpers

Use one helper file or the top of `AVAudioCaptureServiceTests.swift` for the support code below.

```swift
import AVFoundation
import Foundation
@testable import PSAudio
import PSCore
import XCTest

enum AudioTestSupport {
    static func makeFloatBuffer(
        sampleRate: Double,
        channels: AVAudioChannelCount,
        frames: AVAudioFrameCount,
        fill: (_ channel: Int, _ frame: Int) -> Float
    ) -> AVAudioPCMBuffer {
        let format = AVAudioFormat(
            commonFormat: .pcmFormatFloat32,
            sampleRate: sampleRate,
            channels: channels,
            interleaved: false
        )!

        let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frames)!
        buffer.frameLength = frames

        let channelData = buffer.floatChannelData!
        for channel in 0 ..< Int(channels) {
            for frame in 0 ..< Int(frames) {
                channelData[channel][frame] = fill(channel, frame)
            }
        }

        return buffer
    }

    static func makeSineBuffer(
        sampleRate: Double,
        channels: AVAudioChannelCount,
        frames: AVAudioFrameCount,
        frequency: Double = 440.0
    ) -> AVAudioPCMBuffer {
        makeFloatBuffer(
            sampleRate: sampleRate,
            channels: channels,
            frames: frames
        ) { _, frame in
            let time = Double(frame) / sampleRate
            return Float(sin(2.0 * .pi * frequency * time))
        }
    }
}

func XCTAssertPSError(
    _ error: any Error,
    equals expected: PSError,
    file: StaticString = #filePath,
    line: UInt = #line
) {
    guard let error = error as? PSError else {
        XCTFail("Expected PSError, got \\(type(of: error))", file: file, line: line)
        return
    }

    XCTAssertEqual(error, expected, file: file, line: line)
}

final class FakeMicrophoneAuthorizationProvider: MicrophoneAuthorizationProviding, @unchecked Sendable {
    private let status: AVAuthorizationStatus

    init(status: AVAuthorizationStatus) { self.status = status }
    func authorizationStatus() -> AVAuthorizationStatus { status }
}

final class FakeAudioEngineClient: AudioEngineClient, @unchecked Sendable {
    var inputFormat: AVAudioFormat
    var startError: Error?
    var removeTapCallCount = 0
    var stopCallCount = 0
    var resetCallCount = 0
    private var tapHandler: (@Sendable (AVAudioPCMBuffer, AVAudioTime?) -> Void)?

    init(
        inputFormat: AVAudioFormat = AVAudioFormat(
            commonFormat: .pcmFormatFloat32,
            sampleRate: 44_100,
            channels: 1,
            interleaved: false
        )!,
        startError: Error? = nil
    ) { self.inputFormat = inputFormat; self.startError = startError }

    func installTap(
        bufferSize: AVAudioFrameCount,
        handler: @escaping @Sendable (AVAudioPCMBuffer, AVAudioTime?) -> Void
    ) throws {
        _ = bufferSize; tapHandler = handler
    }

    func removeTap() {
        removeTapCallCount += 1; tapHandler = nil
    }

    func prepare() {}

    func start() throws {
        if let startError { throw startError }
    }

    func stop() { stopCallCount += 1 }

    func reset() { resetCallCount += 1 }

    func emit(buffer: AVAudioPCMBuffer, time: AVAudioTime? = nil) {
        tapHandler?(buffer, time)
    }
}

actor FailingResampler: PCMResampling {
    func resample(
        _ buffer: AVAudioPCMBuffer,
        timestamp: ContinuousClock.Instant
    ) async throws -> PCMBuffer {
        _ = buffer; _ = timestamp
        throw PSError.resampleFailure
    }
}

actor TestAudioFailureLogger: AudioFailureLogging {
    struct Entry: Sendable, Equatable {
        let message: String
        let hasError: Bool
    }

    private(set) var entries: [Entry] = []

    func error(_ message: String, error: (any Error)?) {
        entries.append(.init(message: message, hasError: error != nil))
    }
}
```

### B.2 Step 1. Scaffold `AudioResampler`

- Failing test: `AudioResamplerScaffoldingTests/testAudioResamplerSymbolCompiles`
- Run: `swift test --filter AudioResamplerScaffoldingTests/testAudioResamplerSymbolCompiles`
- Implement: add the public actor, fix the output format to 16kHz mono Float32, and create the converter in `init`.
- Commit: `git commit -m 'plan-02 step 1: scaffold audioresampler'`

### B.3 Step 2. Implement mono resampling

- Failing test:

```swift
import AVFoundation
@testable import PSAudio
import PSCore
import XCTest

final class AudioResamplerTests: XCTestCase {
    func testResampleConvertsMono44100ToMono16000PCMBuffer() async throws {
        let input = AudioTestSupport.makeSineBuffer(
            sampleRate: 44_100,
            channels: 1,
            frames: 4_410
        )
        let resampler = try AudioResampler(
            inputFormat: input.format,
            logger: PSLogger(category: PSLogCategory.audio)
        )
        let timestamp = ContinuousClock().now

        let output = try await resampler.resample(input, timestamp: timestamp)

        XCTAssertEqual(output.sampleRate, PSConfig.sampleRate)
        XCTAssertEqual(output.channelCount, PSConfig.channelCount)
        XCTAssertEqual(output.frameCount, 1_600)
        XCTAssertEqual(output.timestamp, timestamp)
        XCTAssertGreaterThan(output.samples.map(abs).max() ?? 0, 0.1)
    }
}
```

- Run: `swift test --filter AudioResamplerTests/testResampleConvertsMono44100ToMono16000PCMBuffer`
- Implement: allocate the output buffer, convert with `AVAudioConverter`, extract mono samples into `[Float]`, build `PCMBuffer`, and log-map failures to `PSError.resampleFailure`.
- Commit: `git commit -m 'plan-02 step 2: implement mono resampling'`

### B.4 Step 3. Add deterministic stereo down-mix

- Failing test:

```swift
import AVFoundation
@testable import PSAudio
import XCTest

final class AudioResamplerStereoTests: XCTestCase {
    func testResampleAveragesStereoInputBeforeResampling() async throws {
        let input = AudioTestSupport.makeFloatBuffer(
            sampleRate: 44_100,
            channels: 2,
            frames: 4_410
        ) { channel, _ in
            channel == 0 ? 1.0 : 0.0
        }

        let resampler = try AudioResampler(inputFormat: input.format)
        let output = try await resampler.resample(
            input,
            timestamp: ContinuousClock().now
        )

        XCTAssertEqual(output.sampleRate, 16_000)
        XCTAssertEqual(output.channelCount, 1)
        XCTAssertEqual(output.frameCount, 1_600)
        XCTAssertEqual(output.samples.prefix(128).reduce(0, +) / 128.0, 0.5, accuracy: 0.05)
    }
}
```

- Run: `swift test --filter AudioResamplerStereoTests/testResampleAveragesStereoInputBeforeResampling`
- Implement: add a private mono-normalization helper that averages all channels per frame into a mono Float32 buffer before conversion.
- Commit: `git commit -m 'plan-02 step 3: add stereo downmix before resampling'`

### B.5 Step 4. Scaffold `AVAudioCaptureService`

- Failing test: `AVAudioCaptureServiceScaffoldingTests/testAVAudioCaptureServiceSymbolCompiles`
- Run: `swift test --filter AVAudioCaptureServiceScaffoldingTests/testAVAudioCaptureServiceSymbolCompiles`
- Implement: add the public actor conforming to `AudioCapturing`, actor state for live stream / continuation / resampler / termination guard, and an internal injected-seam initializer.
- Commit: `git commit -m 'plan-02 step 4: scaffold avaudiocaptureservice'`

### B.6 Step 5. Authorization denied path

- Failing test:

```swift
import AVFoundation
@testable import PSAudio
import PSCore
import XCTest

final class AVAudioCaptureServiceAuthorizationTests: XCTestCase {
    func testStartThrowsMicPermissionDeniedWhenAuthorizationIsDenied() async throws {
        let service = AVAudioCaptureService(
            engineClient: FakeAudioEngineClient(),
            authorizationProvider: FakeMicrophoneAuthorizationProvider(status: .denied),
            resamplerFactory: { format, logger in
                try AudioResampler(inputFormat: format, logger: logger)
            },
            logger: PSLogger(category: PSLogCategory.audio),
            failureLogger: TestAudioFailureLogger()
        )

        do {
            _ = try await service.start()
            XCTFail("Expected micPermissionDenied")
        } catch {
            XCTAssertPSError(error, equals: .micPermissionDenied)
        }
    }
}
```

- Run: `swift test --filter AVAudioCaptureServiceAuthorizationTests/testStartThrowsMicPermissionDeniedWhenAuthorizationIsDenied`
- Implement: check auth before touching the engine and throw `PSError.micPermissionDenied` for any non-authorized status.
- Commit: `git commit -m 'plan-02 step 5: gate capture on mic authorization state'`

### B.7 Step 6. Happy-path capture yields `PCMBuffer`

- Failing test:

```swift
import AVFoundation
@testable import PSAudio
import PSCore
import XCTest

final class AVAudioCaptureServiceHappyPathTests: XCTestCase {
    func testStartReturnsStreamThatYieldsResampledPCMBuffer() async throws {
        let engine = FakeAudioEngineClient()
        let service = AVAudioCaptureService(
            engineClient: engine,
            authorizationProvider: FakeMicrophoneAuthorizationProvider(status: .authorized),
            resamplerFactory: { format, logger in
                try AudioResampler(inputFormat: format, logger: logger)
            },
            logger: PSLogger(category: PSLogCategory.audio),
            failureLogger: TestAudioFailureLogger()
        )

        let stream = try await service.start()
        var iterator = stream.makeAsyncIterator()

        engine.emit(
            buffer: AudioTestSupport.makeSineBuffer(
                sampleRate: 44_100,
                channels: 1,
                frames: 4_410
            )
        )

        let output = try await iterator.next()
        XCTAssertEqual(output?.sampleRate, 16_000)
        XCTAssertEqual(output?.channelCount, 1)
        XCTAssertEqual(output?.frameCount, 1_600)

        await service.stop()
    }
}
```

- Run: `swift test --filter AVAudioCaptureServiceHappyPathTests/testStartReturnsStreamThatYieldsResampledPCMBuffer`
- Implement: create the stream, retain its continuation, build the resampler from the engine input format, install the tap, and on each callback timestamp-resample-yield.
- Commit: `git commit -m 'plan-02 step 6: stream resampled pcmbuffers from tap'`

### B.8 Step 7. Single-active-capture enforcement

- Failing test:

```swift
import AVFoundation
@testable import PSAudio
import PSCore
import XCTest

final class AVAudioCaptureServiceSingleLiveStreamTests: XCTestCase {
    func testSecondStartWhileLiveThrowsAudioEngineFailure() async throws {
        let service = AVAudioCaptureService(
            engineClient: FakeAudioEngineClient(),
            authorizationProvider: FakeMicrophoneAuthorizationProvider(status: .authorized),
            resamplerFactory: { format, logger in
                try AudioResampler(inputFormat: format, logger: logger)
            },
            logger: PSLogger(category: PSLogCategory.audio),
            failureLogger: TestAudioFailureLogger()
        )

        _ = try await service.start()

        do {
            _ = try await service.start()
            XCTFail("Expected audioEngineFailure")
        } catch {
            XCTAssertPSError(error, equals: .audioEngineFailure)
        }

        await service.stop()
    }
}
```

- Run: `swift test --filter AVAudioCaptureServiceSingleLiveStreamTests/testSecondStartWhileLiveThrowsAudioEngineFailure`
- Implement: add actor-isolated `isCapturing` and throw `PSError.audioEngineFailure` on a second live `start()`.
- Commit: `git commit -m 'plan-02 step 7: enforce single active capture stream'`

### B.9 Step 8. Idempotent `stop()`

- Failing test:

```swift
import AVFoundation
@testable import PSAudio
import PSCore
import XCTest

final class AVAudioCaptureServiceStopTests: XCTestCase {
    func testStopIsIdempotent() async throws {
        let engine = FakeAudioEngineClient()
        let service = AVAudioCaptureService(
            engineClient: engine,
            authorizationProvider: FakeMicrophoneAuthorizationProvider(status: .authorized),
            resamplerFactory: { format, logger in
                try AudioResampler(inputFormat: format, logger: logger)
            },
            logger: PSLogger(category: PSLogCategory.audio),
            failureLogger: TestAudioFailureLogger()
        )

        _ = try await service.start()

        await service.stop()
        await service.stop()

        XCTAssertEqual(engine.removeTapCallCount, 1)
        XCTAssertEqual(engine.stopCallCount, 1)
        XCTAssertEqual(engine.resetCallCount, 1)
    }
}
```

- Run: `swift test --filter AVAudioCaptureServiceStopTests/testStopIsIdempotent`
- Implement: route stop through one private `finishIfNeeded` that removes the tap, stops and resets the engine, finishes the stream, and clears state once.
- Commit: `git commit -m 'plan-02 step 8: make stop idempotent'`

### B.10 Step 9. Stream finishes exactly once on `stop()`

- Failing test:

```swift
import AVFoundation
@testable import PSAudio
import PSCore
import XCTest

final class AVAudioCaptureServiceTerminationTests: XCTestCase {
    func testStopFinishesStreamExactlyOnce() async throws {
        let engine = FakeAudioEngineClient()
        let service = AVAudioCaptureService(
            engineClient: engine,
            authorizationProvider: FakeMicrophoneAuthorizationProvider(status: .authorized),
            resamplerFactory: { format, logger in
                try AudioResampler(inputFormat: format, logger: logger)
            },
            logger: PSLogger(category: PSLogCategory.audio),
            failureLogger: TestAudioFailureLogger()
        )

        let stream = try await service.start()
        var iterator = stream.makeAsyncIterator()

        await service.stop()
        XCTAssertNil(try await iterator.next())

        await service.stop()
        XCTAssertNil(try await iterator.next())
        XCTAssertEqual(engine.removeTapCallCount, 1)
    }
}
```

- Run: `swift test --filter AVAudioCaptureServiceTerminationTests/testStopFinishesStreamExactlyOnce`
- Implement: guard termination with a single actor flag and ignore stale callbacks after teardown.
- Commit: `git commit -m 'plan-02 step 9: finish capture stream once on stop'`

### B.11 Step 10. Engine failure mapping

- Failing test:

```swift
import AVFoundation
@testable import PSAudio
import PSCore
import XCTest

final class AVAudioCaptureServiceEngineFailureTests: XCTestCase {
    func testEngineStartFailureMapsToAudioEngineFailure() async throws {
        let logger = TestAudioFailureLogger()
        let service = AVAudioCaptureService(
            engineClient: FakeAudioEngineClient(
                startError: NSError(domain: "AudioEngineTests", code: 7)
            ),
            authorizationProvider: FakeMicrophoneAuthorizationProvider(status: .authorized),
            resamplerFactory: { format, log in
                try AudioResampler(inputFormat: format, logger: log)
            },
            logger: PSLogger(category: PSLogCategory.audio),
            failureLogger: logger
        )

        do {
            _ = try await service.start()
            XCTFail("Expected audioEngineFailure")
        } catch {
            XCTAssertPSError(error, equals: .audioEngineFailure)
        }
    }
}
```

- Run: `swift test --filter AVAudioCaptureServiceEngineFailureTests/testEngineStartFailureMapsToAudioEngineFailure`
- Implement: wrap engine prepare / tap install / start in `do-catch`, log the underlying error, tear down partial state, and throw `PSError.audioEngineFailure`.
- Commit: `git commit -m 'plan-02 step 10: map engine failures to pserror'`

### B.12 Step 11. Converter failure mapping

- Failing test:

```swift
import AVFoundation
@testable import PSAudio
import PSCore
import XCTest

final class AVAudioCaptureServiceResampleFailureTests: XCTestCase {
    func testResampleFailureTerminatesStreamWithPSError() async throws {
        let engine = FakeAudioEngineClient()
        let service = AVAudioCaptureService(
            engineClient: engine,
            authorizationProvider: FakeMicrophoneAuthorizationProvider(status: .authorized),
            resamplerFactory: { _, _ in FailingResampler() },
            logger: PSLogger(category: PSLogCategory.audio),
            failureLogger: TestAudioFailureLogger()
        )

        let stream = try await service.start()
        var iterator = stream.makeAsyncIterator()

        let buffer = AudioTestSupport.makeSineBuffer(
            sampleRate: 44_100,
            channels: 1,
            frames: 4_410
        )
        engine.emit(buffer: buffer)

        do {
            _ = try await iterator.next()
            XCTFail("Expected resampleFailure")
        } catch {
            XCTAssertPSError(error, equals: .resampleFailure)
        }
    }
}
```

- Run: `swift test --filter AVAudioCaptureServiceResampleFailureTests/testResampleFailureTerminatesStreamWithPSError`
- Implement: catch resampler errors in the tap callback, forward existing `PSError.resampleFailure`, otherwise log-map to it, and terminate through the shared finish helper.
- Commit: `git commit -m 'plan-02 step 11: map resampler failures to stream errors'`

### B.13 Step 12. Logger integration

- Failing test:

```swift
import AVFoundation
@testable import PSAudio
import PSCore
import XCTest

final class AudioFailureLoggingTests: XCTestCase {
    func testEngineFailureIsLoggedBeforeMapping() async throws {
        let logger = TestAudioFailureLogger()
        let service = AVAudioCaptureService(
            engineClient: FakeAudioEngineClient(
                startError: NSError(domain: "AudioEngineTests", code: 11)
            ),
            authorizationProvider: FakeMicrophoneAuthorizationProvider(status: .authorized),
            resamplerFactory: { format, log in
                try AudioResampler(inputFormat: format, logger: log)
            },
            logger: PSLogger(category: PSLogCategory.audio),
            failureLogger: logger
        )

        do {
            _ = try await service.start()
            XCTFail("Expected audioEngineFailure")
        } catch {
            XCTAssertPSError(error, equals: .audioEngineFailure)
        }

        XCTAssertEqual(await logger.entries.count, 1)
    }
}
```

- Run: `swift test --filter AudioFailureLoggingTests/testEngineFailureIsLoggedBeforeMapping`
- Implement: default the failure logger to `PSLogger.error`, keep log messages stable, and log before every public mapping path returns or throws.
- Commit: `git commit -m 'plan-02 step 12: log concrete audio failures before mapping'`

Mirror the same assertion style in the resampler tests if the converter seam is kept; do not add a second logging abstraction.

### B.14 Step 13. Manual verification protocol

- Purpose: verify the real microphone path without putting hardware or permission state into CI.
- Files: none required
- Commit: none required
- Checklist:
  1. grant microphone access through the Plan 04 flow
  2. instantiate `AVAudioCaptureService`
  3. call `start()`
  4. speak for 2-3 seconds
  5. confirm yielded `PCMBuffer` values show `sampleRate == 16_000`, `channelCount == 1`, and non-zero sample energy
  6. call `stop()`
  7. confirm the stream terminates once and the engine shuts down cleanly

Manual note:

- use any temporary local harness you want
- do not check in `print()`-based verification code

## C. Dependency table

| Group | Steps | Parallel? | Why |
| --- | --- | --- | --- |
| 1 | 1, 4 | Yes | Resampler and capture scaffolds are separate files. |
| 2 | 2, 3 | No | Stereo behavior builds on the mono conversion path. |
| 3 | 5, 6 | No | Happy-path capture assumes auth gating is already correct. |
| 4 | 7, 8, 9 | No | Single-live-stream, idempotent stop, and exact-once termination all share the same actor state. |
| 5 | 10, 11 | No | Runtime failure mapping depends on the teardown path from Steps 8-9. |
| 6 | 12 | Yes, after 10-11 | Logging assertions are easiest once all failure paths exist. |
| 7 | 13 | Yes | Manual verification is independent and not part of CI. |

Parallel-plan note:

- Plan 02 may run in parallel with Plan 00 implementation work because Section C of Plan 00 already fixed the signatures.
- Plan 02 must not wait on Plan 03 or Plan 04.

## D. Handoff signals

Plan 02 is complete when all of the following are true:

- `PSAudio` builds with production `AudioResampler` and `AVAudioCaptureService`.
- `AVAudioCaptureService` publicly conforms to `AudioCapturing`.
- `AudioResampler` returns only `PCMBuffer` values shaped to `PSConfig.sampleRate == 16_000` and `PSConfig.channelCount == 1`.
- `start()` throws `PSError.micPermissionDenied` immediately when authorization is not already granted.
- a second live `start()` throws `PSError.audioEngineFailure`
- `stop()` is idempotent
- `stop()` finishes the stream normally
- engine failures finish with thrown `PSError.audioEngineFailure`
- conversion failures finish with thrown `PSError.resampleFailure`
- all mapped failures log through `PSLogger(category: PSLogCategory.audio)` before mapping
- no Plan 02 production file depends on Plan 03 VAD or Plan 04 permission UI
- no Plan 02 file is created outside `Sources/PSAudio/` or `Tests/PSAudioTests/`

## E. Open questions

1. Is `1024` the right default tap `bufferSize`, or is `2048` measurably better on the target hardware?
2. Will any common microphone path report an input format that forces a fallback path beyond the planned Float32/non-interleaved conversion flow?
3. Does AirPods / Bluetooth input quality create enough native-format churn to justify a Phase 2 device-selection feature?
4. Is an internal converter-factory seam worth the extra code, or is a thin error-injection wrapper enough for deterministic resampler logging tests?

## F. Symbols added to `PSAudio`

Public:

- `AudioResampler`
- `AVAudioCaptureService`

Internal-only, if the test strategy above is followed:

- `MicrophoneAuthorizationProviding`
- `AudioEngineClient`
- `PCMResampling`
- `AudioFailureLogging`
- `SystemMicrophoneAuthorizationProvider`
- `DefaultAudioEngineClient`
- `PSAudioFailureLogger`

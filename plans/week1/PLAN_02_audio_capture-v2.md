# Plan 02: AVAudioEngine Capture + 16kHz Resampling (v2)
**Goal**: ship the Week 1 production `AudioCapturing` implementation in `SeshatAudio`, backed by `AVAudioEngine`, yielding 16kHz mono Float32 `PCMBuffer` values for Plan 03.
**Architecture**: `AVAudioCaptureService` actor owns one concrete engine wrapper, one internal `AudioResampler`, one active `AsyncThrowingStream`, and one exact-once termination guard.
**Depends on**: Plan 00 Sections C.1, C.2, C.4, D.1, D.5, D.6, D.7; Plan 01 target graph; Plan 03 `PCMBuffer` consumption; Plan 04 permission ownership; Plan 99 production wiring.
**v2 focus**: remove the two v1 contract violations, make the Swift 6 actor boundary explicit, and add the two missing proof tests from review.

## Changes from v1 → v2
- Review issue #1: deleted `MicrophoneAuthorizationProviding`; production code now checks `AVCaptureDevice.authorizationStatus(for: .audio)` directly and tests inject only a per-instance `authorizationStatusProvider` closure.
- Review issue #2: deleted `AudioFailureLogging` and `SeshatAudioFailureLogger`; every production failure path now logs through `SeshatLogger(category: SeshatLogCategory.audio)` directly.
- Review issue #3: replaced the underspecified tap hop with an explicit Swift 6 design where the tap closure copies into Sendable `[Float]` plus timestamp before any actor hop.
- Review issue #4: added a finish-exactly-once race step where `stop()` interleaves with an Nth-buffer runtime failure and first-event-wins semantics are documented.
- Review issue #5: added an upstream-style `NSError` mapping step proving arbitrary non-`SeshatError` failures are logged first and surfaced dynamically as `SeshatError`.

## A. Contract Anchors
### A.1 Hard rules from Plan 00
1. `PCMBuffer` is the only shared Week 1 audio-buffer type.
2. `AudioCapturing.start()` returns the single active capture stream.
3. A second live `start()` throws `SeshatError.audioEngineFailure`.
4. `stop()` is idempotent.
5. The stream finishes normally on `stop()`.
6. Runtime failures finish the stream with thrown `SeshatError`.
7. The dynamic runtime error type is always `SeshatError`.
8. Underlying concrete errors are logged before mapping.
9. Production logging uses `SeshatLogger` plus `SeshatLogCategory` only.
10. `SeshatAudio` may check microphone authorization state but must not prompt.
11. Plan 02 must not define a second microphone-permission protocol.
12. Plan 02 must not define a second logging abstraction.
13. Public async behavior stays Swift Concurrency only.
14. Any remaining `@unchecked Sendable` use must include a one-line inline rationale.

### A.2 APIs used here
- `AVAudioEngine.inputNode`
- `AVAudioInputNode.installTap(onBus:bufferSize:format:block:)`
- `AVAudioConverter`
- `AVCaptureDevice.authorizationStatus(for: .audio)`
- `AVAudioFormat`
- `AVAudioPCMBuffer`

### A.3 Week 1 non-goals
- no permission prompts
- no device selection
- no VAD
- no disk recording
- no alternate session manager
- no second composition root
- no shared fake types in `SeshatTestSupport`

## B. v2 Design Summary
### B.1 Intended declarations
Public:
- `AVAudioCaptureService` — `public actor`, conforms to `AudioCapturing`

Internal:
- `AudioResampler` — `internal actor`, implementation helper only
- `AudioEngineDriver` — `internal final class`, concrete AVFoundation wrapper only

Deliberately deleted:
- `MicrophoneAuthorizationProviding`
- `SystemMicrophoneAuthorizationProvider`
- `AudioFailureLogging`
- `SeshatAudioFailureLogger`
- `PCMResampling`

### B.2 Why these declarations are enough
- `AVAudioCaptureService` is the only shared production capture surface.
- `AudioResampler` stays internal because no sibling plan should know about it.
- `AudioEngineDriver` is concrete so tests can inject behavior without inventing a protocol.
- authorization uses a closure seam, not a permission abstraction.
- logging uses `SeshatLogger`, not a wrapper.

### B.3 Ownership boundaries
- Plan 02 owns capture and resampling only.
- Plan 04 owns prompting through `MicrophonePermissionRequesting`.
- Plan 99 owns production composition.
- Plan 03 owns `PCMBuffer` consumption.
- Plan 02 does not read or mutate `testingBaseDirectoryOverride`.

## C. Swift 6 Concurrency Design
### C.1 Problem statement
`AVAudioPCMBuffer` and `AVAudioTime` are not the values that should cross from the real-time tap callback into actor-isolated state.
v2 makes that boundary explicit.

### C.2 Actor-hop rule
Inside the tap closure:
1. read the non-Sendable `AVAudioPCMBuffer` synchronously
2. copy it into a plain `[Float]`
3. average channels to mono during that copy if needed
4. capture an absolute timestamp immediately
5. hop into the actor with Sendable values only

Pinned shape:

```swift
inputNode.installTap(onBus: 0, bufferSize: 1024, format: tapFormat) { [weak self] buffer, _ in
    let samples = Self.extractSamples(from: buffer)
    let timestamp = ContinuousClock.now

    guard let self else { return }

    Task {
        await self.handleTapSamples(samples, timestamp: timestamp)
    }
}
```

### C.3 Why this is Swift 6-safe
- `[Float]` is `Sendable`
- `ContinuousClock.Instant` is `Sendable`
- `AVAudioPCMBuffer` stays confined to the tap callback
- `AVAudioTime` does not cross the actor boundary
- `AVAudioFormat` does not cross the actor boundary either because the actor already owns a resampler created during `start()`

### C.4 Pure sample extraction
`extractSamples` is synchronous, deterministic, and pure.
It converts multi-channel Float32 input into mono Float32 output before the actor hop.

```swift
import AVFoundation

private extension AVAudioCaptureService {
    static func extractSamples(from buffer: AVAudioPCMBuffer) -> [Float] {
        let frameCount = Int(buffer.frameLength)
        let channelCount = Int(buffer.format.channelCount)

        guard
            buffer.format.commonFormat == .pcmFormatFloat32,
            let channelData = buffer.floatChannelData
        else {
            return []
        }

        if channelCount == 1 {
            return Array(
                UnsafeBufferPointer(start: channelData[0], count: frameCount)
            )
        }

        var mixed = Array(repeating: Float.zero, count: frameCount)
        for channel in 0 ..< channelCount {
            let source = UnsafeBufferPointer(start: channelData[channel], count: frameCount)
            for frame in 0 ..< frameCount {
                mixed[frame] += source[frame] / Float(channelCount)
            }
        }

        return mixed
    }
}
```

### C.5 Actor-side handling
The actor method receives only Sendable arguments.
It ignores stale callbacks after termination.

```swift
import Foundation
import SeshatCore

extension AVAudioCaptureService {
    private func handleTapSamples(
        _ samples: [Float],
        timestamp: ContinuousClock.Instant
    ) async {
        guard isCapturing, !isTerminated else { return }
        guard let resampler else {
            finishThrowingIfNeeded(.audioEngineFailure)
            return
        }

        do {
            let pcm = try await resampler.resample(
                monoSamples: samples,
                timestamp: timestamp
            )
            continuation?.yield(pcm)
        } catch let error as SeshatError {
            finishThrowingIfNeeded(error)
        } catch {
            logger.error("Audio resample failed", error: error)
            finishThrowingIfNeeded(.resampleFailure)
        }
    }
}
```

### C.6 `@unchecked Sendable` policy
Production code should need none with this design.
If a test helper still needs it, the rationale must be inline.

```swift
private final class ThreadSafeEngineBox: @unchecked Sendable {
    // Safe in tests: NSLock protects all mutable state shared between the test thread and the tap callback.
    private let lock = NSLock()
}
```

## D. Combined Production Shape
This is the shape v2 should pin.
It removes the banned abstractions while keeping Plan 99 compatibility.

```swift
import AVFoundation
import Foundation
import SeshatCore

internal final class AudioEngineDriver {
    internal init(
        inputFormatProvider: @escaping () -> AVAudioFormat,
        installTap: @escaping (
            @escaping @Sendable (AVAudioPCMBuffer, AVAudioTime) -> Void
        ) throws -> Void,
        removeTap: @escaping () -> Void,
        prepare: @escaping () -> Void,
        start: @escaping () throws -> Void,
        stop: @escaping () -> Void,
        reset: @escaping () -> Void
    ) {
        self.inputFormatProvider = inputFormatProvider
        self.installTapImpl = installTap
        self.removeTapImpl = removeTap
        self.prepareImpl = prepare
        self.startImpl = start
        self.stopImpl = stop
        self.resetImpl = reset
    }

    internal static func live() -> AudioEngineDriver { fatalError("Plan snippet") }
    internal func inputFormat() -> AVAudioFormat { inputFormatProvider() }
    internal func installTap(_ handler: @escaping @Sendable (AVAudioPCMBuffer, AVAudioTime) -> Void) throws { try installTapImpl(handler) }
    internal func removeTap() { removeTapImpl() }
    internal func prepare() { prepareImpl() }
    internal func start() throws { try startImpl() }
    internal func stop() { stopImpl() }
    internal func reset() { resetImpl() }

    private let inputFormatProvider: () -> AVAudioFormat
    private let installTapImpl: (@escaping @Sendable (AVAudioPCMBuffer, AVAudioTime) -> Void) throws -> Void
    private let removeTapImpl: () -> Void
    private let prepareImpl: () -> Void
    private let startImpl: () throws -> Void
    private let stopImpl: () -> Void
    private let resetImpl: () -> Void
}

internal actor AudioResampler {
    internal init(
        inputSampleRate: Double,
        logger: SeshatLogger = SeshatLogger(category: SeshatLogCategory.audio)
    ) throws {
        self.customResampleImpl = nil
        self.logger = logger
        self.inputSampleRate = inputSampleRate
    }

    internal init(
        resampleImpl: @escaping @Sendable ([Float], ContinuousClock.Instant) throws -> PCMBuffer
    ) {
        self.customResampleImpl = resampleImpl
        self.logger = SeshatLogger(category: SeshatLogCategory.audio)
        self.inputSampleRate = SeshatConfig.sampleRate
    }

    internal func resample(
        monoSamples: [Float],
        timestamp: ContinuousClock.Instant
    ) throws -> PCMBuffer {
        if let customResampleImpl { return try customResampleImpl(monoSamples, timestamp) }
        _ = logger
        _ = inputSampleRate
        return try PCMBuffer(
            samples: monoSamples,
            sampleRate: SeshatConfig.sampleRate,
            channelCount: SeshatConfig.channelCount,
            timestamp: timestamp
        )
    }

    private let logger: SeshatLogger
    private let inputSampleRate: Double
    private let customResampleImpl: (@Sendable ([Float], ContinuousClock.Instant) throws -> PCMBuffer)?
}

public actor AVAudioCaptureService: AudioCapturing {
    public init(
        logger: SeshatLogger = SeshatLogger(category: SeshatLogCategory.audio)
    ) {
        self.init(
            logger: logger,
            authorizationStatusProvider: {
                AVCaptureDevice.authorizationStatus(for: .audio)
            },
            engineDriver: .live(),
            resamplerFactory: { sampleRate, logger in
                try AudioResampler(
                    inputSampleRate: sampleRate,
                    logger: logger
                )
            }
        )
    }

    internal init(
        logger: SeshatLogger = SeshatLogger(category: SeshatLogCategory.audio),
        authorizationStatusProvider: @escaping @Sendable () -> AVAuthorizationStatus,
        engineDriver: AudioEngineDriver,
        resamplerFactory: @escaping @Sendable (Double, SeshatLogger) throws -> AudioResampler
    ) {
        self.logger = logger
        self.authorizationStatusProvider = authorizationStatusProvider
        self.engineDriver = engineDriver
        self.resamplerFactory = resamplerFactory
    }

    public func start() async throws -> AsyncThrowingStream<PCMBuffer, Error> {
        fatalError("Plan snippet")
    }

    public func stop() async { fatalError("Plan snippet") }

    private let logger: SeshatLogger
    private let authorizationStatusProvider: @Sendable () -> AVAuthorizationStatus
    private let engineDriver: AudioEngineDriver
    private let resamplerFactory: @Sendable (Double, SeshatLogger) throws -> AudioResampler
    private var continuation: AsyncThrowingStream<PCMBuffer, Error>.Continuation?
    private var resampler: AudioResampler?
    private var isCapturing = false
    private var isTerminated = false
}
```

Pinned semantics:
- the public init remains compatible with Plan 99
- the only auth seam is a closure
- the only logger is `SeshatLogger`
- the first actor-visible terminal event wins

## E. Files in Scope
- `Sources/SeshatAudio/AudioResampler.swift`
- `Sources/SeshatAudio/AVAudioCaptureService.swift`
- `Tests/SeshatAudioTests/AudioResamplerScaffoldingTests.swift`
- `Tests/SeshatAudioTests/AudioResamplerTests.swift`
- `Tests/SeshatAudioTests/AVAudioCaptureServiceScaffoldingTests.swift`
- `Tests/SeshatAudioTests/AVAudioCaptureServiceTests.swift`

Out of scope:
- `SeshatTestSupport`
- `SeshatAppKit`
- `SeshatTranscription`
- any permission requester
- any directory or config override logic

## F. Shared Test Helpers
Keep these private to `SeshatAudioTests`.
Do not create new shared fake types.
Required private helpers:
- `AudioTestSupport.makeFloatBuffer(...)` creates non-interleaved Float32 test buffers.
- `ThreadSafeEngineBox: @unchecked Sendable` stores the tap callback plus removeTap/stop/reset counters behind `NSLock`.
- `AudioEngineDriver.testStub(...)` returns a concrete driver backed by `ThreadSafeEngineBox`.
- `LogProbe.audioMessages(...)` reads current-process audio-category log messages through `OSLogStore`.

Pinned helper shape:

```swift
private final class ThreadSafeEngineBox: @unchecked Sendable {
    // Safe in tests: NSLock protects all mutable state shared between the test thread and the tap callback.
    private let lock = NSLock()
}
```

## G. TDD Plan
### G.0 Shared execution rules
1. Add one failing test.
2. Run the narrowest `swift test --filter ...`.
3. Implement the smallest production change.
4. Keep production logging on `SeshatLogger`.
5. Do not add a protocol seam for permission or logging.
6. Do not call `requestAccess` anywhere in Plan 02.

### G.1 Step 1. Scaffold `AudioResampler`
Files:
- `Sources/SeshatAudio/AudioResampler.swift`
- `Tests/SeshatAudioTests/AudioResamplerScaffoldingTests.swift`
Red:
- `AudioResamplerScaffoldingTests/testAudioResamplerSymbolCompiles`
- instantiate `try AudioResampler(inputSampleRate: 44_100)`

Green:
- add the internal actor
- add the two inits
- add `resample(monoSamples:timestamp:)`

Command:

```bash
swift test --filter AudioResamplerScaffoldingTests/testAudioResamplerSymbolCompiles
```

Commit:

```bash
git commit -m "plan-02 step 1: scaffold audioresampler"
```

### G.2 Step 2. Implement mono resampling
Files:
- `Sources/SeshatAudio/AudioResampler.swift`
- `Tests/SeshatAudioTests/AudioResamplerTests.swift`
Red:
- `AudioResamplerTests/testResampleConvertsMono44100ToMono16000PCMBuffer`
- assert `sampleRate == 16_000`
- assert `channelCount == 1`
- assert `frameCount == 1_600`
- assert timestamp preserved
- assert non-zero signal energy

Green:
- build a mono Float32 input buffer from `[Float]`
- run `AVAudioConverter`
- extract the output samples
- construct `PCMBuffer`
- log concrete converter failures and throw `.resampleFailure`

Command:

```bash
swift test --filter AudioResamplerTests/testResampleConvertsMono44100ToMono16000PCMBuffer
```

Commit:

```bash
git commit -m "plan-02 step 2: implement mono resampling"
```

### G.3 Step 3. Scaffold `AVAudioCaptureService`
Files:
- `Sources/SeshatAudio/AVAudioCaptureService.swift`
- `Tests/SeshatAudioTests/AVAudioCaptureServiceScaffoldingTests.swift`
Red:
- `AVAudioCaptureServiceScaffoldingTests/testAVAudioCaptureServiceConformsToAudioCapturing`
- assign `let service: any AudioCapturing = AVAudioCaptureService()`

Green:
- add the public actor
- keep the public init zero-required-argument
- add internal init with `authorizationStatusProvider`
- store continuation, resampler, and exact-once state

Command:

```bash
swift test --filter AVAudioCaptureServiceScaffoldingTests/testAVAudioCaptureServiceConformsToAudioCapturing
```

Commit:

```bash
git commit -m "plan-02 step 3: scaffold avaudiocaptureservice"
```

### G.4 Step 4. Authorization denied path
Files:
- `Sources/SeshatAudio/AVAudioCaptureService.swift`
- `Tests/SeshatAudioTests/AVAudioCaptureServiceTests.swift`

Test:

```swift
import AVFoundation
import XCTest
import SeshatCore
@testable import SeshatAudio

final class AuthorizationTests: XCTestCase {
    func testStartThrowsMicPermissionDeniedWhenStatusIsDenied() async throws {
        let service = AVAudioCaptureService(
            authorizationStatusProvider: { .denied },
            engineDriver: .testStub(),
            resamplerFactory: { rate, logger in
                try AudioResampler(inputSampleRate: rate, logger: logger)
            }
        )

        do {
            _ = try await service.start()
            XCTFail("Expected micPermissionDenied")
        } catch let error as SeshatError {
            XCTAssertEqual(error, .micPermissionDenied)
        }
    }

    func testStartThrowsMicPermissionDeniedWhenStatusIsNotDetermined() async throws {
        let service = AVAudioCaptureService(
            authorizationStatusProvider: { .notDetermined },
            engineDriver: .testStub(),
            resamplerFactory: { rate, logger in
                try AudioResampler(inputSampleRate: rate, logger: logger)
            }
        )

        do {
            _ = try await service.start()
            XCTFail("Expected micPermissionDenied")
        } catch let error as SeshatError {
            XCTAssertEqual(error, .micPermissionDenied)
        }
    }
}
```

Implementation:
- call the auth closure at the top of `start()`
- treat every non-`.authorized` status as denied for capture
- never prompt

Command:

```bash
swift test --filter AuthorizationTests
```

Commit:

```bash
git commit -m "plan-02 step 4: gate capture on direct auth status"
```

### G.5 Step 5. Happy path capture emits `PCMBuffer`
Files:
- `Sources/SeshatAudio/AVAudioCaptureService.swift`
- `Tests/SeshatAudioTests/AVAudioCaptureServiceTests.swift`

Test:

```swift
import XCTest
import SeshatCore
@testable import SeshatAudio

final class HappyPathCaptureTests: XCTestCase {
    func testStartReturnsStreamThatYieldsMono16000PCMBuffer() async throws {
        let box = ThreadSafeEngineBox()
        let service = AVAudioCaptureService(
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
```

Implementation:
- create the resampler during `start()`
- install the tap
- copy to `[Float]`, including stereo averaging
- resample and yield `PCMBuffer`

Command:

```bash
swift test --filter HappyPathCaptureTests/testStartReturnsStreamThatYieldsMono16000PCMBuffer
```

Commit:

```bash
git commit -m "plan-02 step 5: stream mono 16khz pcmbuffers"
```

### G.6 Step 6. Single-active-capture enforcement
Files:
- `Sources/SeshatAudio/AVAudioCaptureService.swift`
- `Tests/SeshatAudioTests/AVAudioCaptureServiceTests.swift`
Red:
- `SingleCaptureTests/testSecondStartWhileLiveThrowsAudioEngineFailure`
- first `start()` succeeds
- second live `start()` throws `.audioEngineFailure`

Green:
- guard `isCapturing && !isTerminated`
- throw `.audioEngineFailure`

Command:

```bash
swift test --filter SingleCaptureTests/testSecondStartWhileLiveThrowsAudioEngineFailure
```

Commit:

```bash
git commit -m "plan-02 step 6: enforce single active capture"
```

### G.7 Step 7. Idempotent `stop()` and normal finish
Files:
- `Sources/SeshatAudio/AVAudioCaptureService.swift`
- `Tests/SeshatAudioTests/AVAudioCaptureServiceTests.swift`
Red:
- `StopBehaviorTests/testStopIsIdempotentAndFinishesStreamNormally`
- first `stop()` finishes the stream with `nil`
- second `stop()` is a no-op
- removeTap/stop/reset each happen exactly once

Green:
- route normal termination through one guard
- clear continuation once
- make late callbacks no-op

Command:

```bash
swift test --filter StopBehaviorTests/testStopIsIdempotentAndFinishesStreamNormally
```

Commit:

```bash
git commit -m "plan-02 step 7: make stop idempotent"
```

### G.8 Step 8. Engine startup failure mapping
Files:
- `Sources/SeshatAudio/AVAudioCaptureService.swift`
- `Tests/SeshatAudioTests/AVAudioCaptureServiceTests.swift`
Red:
- `EngineFailureTests/testEngineStartFailureMapsToAudioEngineFailure`
- inject `NSError(domain: "AudioEngineTests", code: 7)` from engine start
- assert thrown value is `.audioEngineFailure`

Green:
- wrap tap install, prepare, and engine start in one `do/catch`
- log the concrete error
- clear partial state
- throw `.audioEngineFailure`

Command:

```bash
swift test --filter EngineFailureTests/testEngineStartFailureMapsToAudioEngineFailure
```

Commit:

```bash
git commit -m "plan-02 step 8: map engine startup failures"
```

### G.9 Step 9. Dynamic `NSError` mapping for runtime resample failure
Files:
- `Sources/SeshatAudio/AudioResampler.swift`
- `Sources/SeshatAudio/AVAudioCaptureService.swift`
- `Tests/SeshatAudioTests/AVAudioCaptureServiceTests.swift`

Test:

```swift
import XCTest
import SeshatCore
@testable import SeshatAudio

final class NSErrorMappingTests: XCTestCase {
    func testPlainNSErrorIsLoggedThenMappedToResampleFailure() async throws {
        let box = ThreadSafeEngineBox()
        let service = AVAudioCaptureService(
            logger: SeshatLogger(category: SeshatLogCategory.audio),
            authorizationStatusProvider: { .authorized },
            engineDriver: .testStub(box: box),
            resamplerFactory: { _, _ in
                AudioResampler { _, _ in
                    throw NSError(
                        domain: "TestDomain",
                        code: -1,
                        userInfo: [NSLocalizedDescriptionKey: "Injected upstream resample failure"]
                    )
                }
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
        } catch let error as SeshatError {
            XCTAssertEqual(error, .resampleFailure)
        }

        let messages = try LogProbe.audioMessages()
        XCTAssertTrue(messages.contains { $0.contains("Injected upstream resample failure") })
    }
}
```

Implementation:
- keep the failure source as a plain `NSError`, not a `SeshatError`
- if the resampler throws non-`SeshatError`, log the concrete error and finish the stream with `.resampleFailure`
- use real `SeshatLogger`
- use log observation only as a test probe

Command:

```bash
swift test --filter NSErrorMappingTests/testPlainNSErrorIsLoggedThenMappedToResampleFailure
```

Commit:

```bash
git commit -m "plan-02 step 9: prove nserror to pserror stream mapping"
```

### G.10 Step 10. Finish-exactly-once race: `stop()` vs Nth-buffer failure
Files:
- `Sources/SeshatAudio/AVAudioCaptureService.swift`
- `Tests/SeshatAudioTests/AVAudioCaptureServiceTests.swift`

Helper:

```swift
import Dispatch
import Foundation
import SeshatCore
@testable import SeshatAudio

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
            throw SeshatError.resampleFailure
        }

        return try PCMBuffer(
            samples: samples,
            sampleRate: SeshatConfig.sampleRate,
            channelCount: 1,
            timestamp: timestamp
        )
    }
}
```

Test:

```swift
import XCTest
@testable import SeshatAudio

final class FinishExactlyOnceRaceTests: XCTestCase {
    func testStopRacingNthBufferFailureFinishesExactlyOnce() async throws {
        let box = ThreadSafeEngineBox()
        let failing = BlockingResampleBox(failOnCall: 3)
        let service = AVAudioCaptureService(
            authorizationStatusProvider: { .authorized },
            engineDriver: .testStub(sampleRate: 16_000, box: box),
            resamplerFactory: { _, _ in
                AudioResampler(resampleImpl: failing.resample(samples:timestamp:))
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

        XCTAssertNil(try await iterator.next())
        XCTAssertNil(try await iterator.next())
    }
}
```

Pinned policy:
- the first actor-visible terminal event wins
- this test deliberately schedules `stop()` to claim termination before the gated Nth-buffer failure completes
- in this interleaving, `stop()` preempts the throw and the stream finishes normally once

Command:

```bash
swift test --filter FinishExactlyOnceRaceTests/testStopRacingNthBufferFailureFinishesExactlyOnce
```

Commit:

```bash
git commit -m "plan-02 step 10: prove exact-once termination under race"
```

### G.11 Step 11. Manual verification
1. Grant permission through the Plan 04 UI flow.
2. Instantiate `AVAudioCaptureService()`.
3. Call `start()`.
4. Speak for 2–3 seconds.
5. Confirm yielded buffers report `sampleRate == 16_000`, `channelCount == 1`, and non-zero sample energy.
6. Call `stop()`.
7. Confirm the stream finishes normally once.
8. Confirm a second `stop()` has no extra effect.

## H. Runtime Semantics
### H.1 `start()`
Expected order:
1. check authorization
2. reject a second live stream
3. read input format
4. create the resampler
5. create the stream continuation
6. install the tap
7. prepare the engine
8. start the engine
9. mark capture live
10. return the stream

### H.2 `stop()`
Expected order:
1. claim termination if available
2. remove tap
3. stop engine
4. reset engine
5. finish the stream normally
6. clear continuation and resampler
7. mark capture not live

### H.3 Failure mapping
- engine setup/start failures map to `.audioEngineFailure`
- runtime resample failures map to `.resampleFailure`
- mapped failures log the underlying concrete error before mapping
- the dynamic error type surfaced by the stream is always `SeshatError`

### H.4 First-event-wins policy
- if `stop()` claims termination first, later runtime failure work is ignored
- if a runtime failure claims termination first, later `stop()` is a no-op
- Step 10 pins the `stop()`-wins interleaving explicitly because that was the missing proof in v1

## I. Dependency and Execution Order
Serial edges: Step 1 before Step 2; Step 3 before Steps 4–10; Step 7 before Steps 9–10.
Parallel opportunities: Steps 1 and 3 may start in parallel as scaffolds; Step 11 manual verification is independent after tests are green.
Preferred commands: `swift test --filter AudioResamplerScaffoldingTests`, `swift test --filter AudioResamplerTests`, `swift test --filter AVAudioCaptureServiceScaffoldingTests`, `swift test --filter AuthorizationTests`, `swift test --filter HappyPathCaptureTests`, `swift test --filter SingleCaptureTests`, `swift test --filter StopBehaviorTests`, `swift test --filter EngineFailureTests`, `swift test --filter NSErrorMappingTests`, `swift test --filter FinishExactlyOnceRaceTests`, then `swift test`.

## Sibling Cross-Plan Audit
### J.1 Plan 03 consumption
Plan 03’s `transcribe(stream:)` expects `PCMBuffer.samples` to already be the direct inference payload:
- Float32
- 16kHz
- mono

Plan 02 v2 matches that exactly:
- the tap copy yields `[Float]`
- stereo is averaged to mono before the actor hop
- `AudioResampler` emits `PCMBuffer(sampleRate: 16_000, channelCount: 1, ...)`

Sibling mismatch: none.

### J.2 Plan 04 permission ownership
Plan 04 owns `MicrophonePermissionRequesting` and the only prompt path.
Plan 02 v2:
- never calls `requestAccess`
- never defines a permission protocol
- treats `.notDetermined` as not authorized to capture, not as a prompt trigger

Sibling mismatch: none.

### J.3 Plan 99 composition wiring
Plan 99 wires `AVAudioCaptureService(logger: SeshatLogger(category: SeshatLogCategory.audio))`.
Plan 02 v2 ships `public init(logger: SeshatLogger = SeshatLogger(category: SeshatLogCategory.audio))`.
Sibling mismatch: none.

### J.4 Plan 01 target graph
Plan 01 pins `SeshatAudio`, `SeshatAudioTests`, and `SeshatTestSupport`.
Plan 02 v2 stays in `SeshatAudio` and `SeshatAudioTests` only.
It does not add new targets or shared fake modules.

Sibling mismatch: none.

## Forbidden Duplicates Semantic Audit
Public or internal declarations in Plan 02 v2:
- `AVAudioCaptureService` — `public actor`
  Could be mistaken for: `AudioCapturing`
  Why it is not a duplicate: it is the single production conformer of the shared protocol, not a competing protocol or contract.

- `AudioResampler` — `internal actor`
  Could be mistaken for: `PCMBuffer`
  Why it is not a duplicate: it converts raw mono Float32 sample arrays into the existing `PCMBuffer`; it does not define a second shared buffer type.

- `AudioEngineDriver` — `internal final class`
  Could be mistaken for: `AudioCapturing`, `MicrophonePermissionRequesting`, or `SeshatLogger`
  Why it is not a duplicate: it is only an AVFoundation wrapper for engine lifecycle and tap installation inside `SeshatAudio`; it does not own permission prompting, stream semantics, or logging abstraction.

Declarations explicitly deleted because they smelled like duplicates:
- `MicrophoneAuthorizationProviding` — duplicated the shared permission-ownership concept
- `SystemMicrophoneAuthorizationProvider` — only existed to support the deleted permission protocol
- `AudioFailureLogging` — duplicated the shared logging facade concept
- `SeshatAudioFailureLogger` — duplicated `SeshatLogger`
- `PCMResampling` — unnecessary protocol indirection for an internal helper

Audit conclusion:
- no new public/internal protocol abstracts a Plan 00 concept
- no new type duplicates `PCMBuffer`, `SeshatError`, `AudioCapturing`, `MicrophonePermissionRequesting`, `SeshatLogger`, or `SessionState`

## K. Handoff Signals
Plan 02 is complete when `SeshatAudio` builds with `AVAudioCaptureService` plus internal `AudioResampler`, the public init remains Plan 99-compatible, `start()` never prompts, every emitted `PCMBuffer` is Float32/16kHz/mono, second live `start()` throws `.audioEngineFailure`, `stop()` is idempotent and normal-finishes exactly once, engine failures map to `.audioEngineFailure`, runtime resample failures map to `.resampleFailure`, arbitrary upstream `NSError` values are logged then mapped to `SeshatError`, and no Plan 02 file touches `testingBaseDirectoryOverride`.

## Self-verification Checklist
- [ ] `MicrophoneAuthorizationProviding` is DELETED
- [ ] `AudioFailureLogging` / `SeshatAudioFailureLogger` is DELETED
- [ ] No new public/internal protocol abstracts a Plan 00 concept
- [ ] No `requestAccess` call anywhere in Plan 02 code or tests
- [ ] Swift 6 Sendable design explicit; `[Float]` + timestamp cross the actor hop
- [ ] `@unchecked Sendable` uses either removed or carry one-line rationale
- [ ] finish-exactly-once race test present
- [ ] NSError → SeshatError mapping test present
- [ ] Every production log via `SeshatLogger(category: SeshatLogCategory.audio)`
- [ ] `testingBaseDirectoryOverride` not misused (Plan 02 is in-memory)

## L. Final v2 Position
v1’s problem was not the choice of `AVAudioEngine`; it was that the plan quietly recreated two shared contracts that Plan 00 had already centralized.
v2 removes those duplicates completely.

The resulting Plan 02 surface is intentionally narrow:
- one public capture actor
- one internal concrete resampler
- one internal concrete engine wrapper
- one direct auth-status closure seam
- one direct logger facade
- one explicit Sendable hop
- one exact-once terminal guard
That is the smallest Week 1 capture design that still satisfies Plan 00, Plan 03, Plan 04, and Plan 99 together.

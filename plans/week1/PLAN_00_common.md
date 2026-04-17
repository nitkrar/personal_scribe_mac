# Plan 00: Common Components & Shared Contracts
**Goal**: Define every shared module, type, protocol, and public API that Week 1 subsystems (plans 01–04) will consume. No other plan may redefine anything listed here.
**Architecture**: SPM multi-target, Swift Concurrency with actor-based session coordinator, constructor DI, `os.Logger` facade, 16kHz mono Float32 PCM pipeline.
**Tech Stack**: Swift 5.9+, SwiftUI, AppKit, AVFoundation, `os.Logger`, XCTest, FluidAudio (Plan 03)

## Scope
This plan prevents parallel Week 1 work from inventing duplicate shared concepts.

Week 1 consumers:
- Plan 01: SPM setup, targets, tests, `git init`
- Plan 02: mic capture + 16kHz mono Float32 resampling behind `AudioCapturing`
- Plan 03: FluidAudio/Parakeet wrapper behind `Transcribing`, wired into `SessionCoordinator`
- Plan 04: menu bar app observing `SessionCoordinator`

Week 1 non-goals:
- no hotkeys
- no paste injection
- no notes DB
- no settings storage beyond `PSConfig`
- no alternate UI state machines

## B. Module Layout (Authoritative)
### Target Graph
```text
                 ┌─────────────┐
                 │   PSCore    │
                 │types/protos │
                 │config/logger│
                 └──────┬──────┘
                        │
         ┌──────────────┼──────────────┐
         ▼              ▼              ▼
   ┌──────────┐   ┌──────────────┐  ┌──────────────┐
   │ PSAudio  │   │PSTranscription│  │ PSTestSupport│
   │ capture  │   │ FluidAudio   │  │ shared fakes │
   └────┬─────┘   └──────┬───────┘  └──────────────┘
        │                │
        └────────┬───────┘
                 ▼
           ┌────────────┐
           │ PSSession  │
           │ coordinator│
           └─────┬──────┘
                 ▼
           ┌────────────┐
           │  PSAppKit  │
           │ menu bar   │
           └────────────┘

PSCoreTests -> PSCore
PSAudioTests -> PSAudio + PSTestSupport
PSTranscriptionTests -> PSTranscription + PSTestSupport
PSSessionTests -> PSSession + PSTestSupport
```

### Targets
- `PSCore` — shared types, protocols, errors, config, logger facade. Only `Foundation` + `os`.
- `PSAudio` — AVFoundation capture + resampling. Depends on `PSCore`.
- `PSTranscription` — FluidAudio wrapper. Depends on `PSCore` + `FluidAudio`.
- `PSSession` — `SessionCoordinator` actor. Depends on `PSCore`, `PSAudio`, `PSTranscription`.
- `PSAppKit` — menu bar UI + bootstrap. Depends on `PSSession`.
- `PSTestSupport` — reusable test fakes. Depends on `PSCore` only.
- Test targets: `PSCoreTests`, `PSAudioTests`, `PSTranscriptionTests`, `PSSessionTests`. None depend on AppKit.

### Directory Layout
```text
Package.swift
Sources/
  PSCore/
    PCMBuffer.swift
    SessionState.swift
    TranscriptionResult.swift
    Errors.swift
    Config.swift
    Logger.swift
    Protocols.swift
  PSAudio/
    AVAudioCaptureService.swift
    AudioResampler.swift
  PSTranscription/
    FluidAudioTranscriber.swift
  PSSession/
    SessionCoordinator.swift
  PSAppKit/
    PersonalScribeApp.swift
    Composition/
      AppComposition.swift
  PSTestSupport/
    FakeAudioCapturing.swift
    FakeTranscriber.swift
Tests/
  PSCoreTests/
  PSAudioTests/
  PSTranscriptionTests/
  PSSessionTests/
```

Plan 03 verification note:
- assume a typical Parakeet SDK shape now
- verify exact FluidAudio API later
- pin an explicit version in `Package.swift`
- do not change the public `Transcribing` contract to match SDK naming

## C. Public API Surface (Authoritative Signatures)
### 1. Types (`PSCore`)
```swift
import Foundation

public struct PCMBuffer: Sendable {
    public let samples: [Float]
    public let sampleRate: Double
    public let channelCount: Int
    public let timestamp: ContinuousClock.Instant
    public init(
        samples: [Float],
        sampleRate: Double = PSConfig.sampleRate,
        channelCount: Int = PSConfig.channelCount,
        timestamp: ContinuousClock.Instant = ContinuousClock().now
    ) throws
    public var frameCount: Int { get }
    public var duration: Duration { get }
}

public enum SessionState: Sendable, Equatable {
    case idle
    case recording
    case transcribing
    case error(PSError)
}

public struct TranscriptionResult: Sendable {
    public struct Segment: Sendable {
        public let text: String
        public let start: Duration
        public let end: Duration
        public init(text: String, start: Duration, end: Duration)
    }
    public let text: String
    public let segments: [Segment]
    public let audioDuration: Duration
    public let processingDuration: Duration
    public init(
        text: String,
        segments: [Segment] = [],
        audioDuration: Duration,
        processingDuration: Duration
    )
}

public enum PSError: Error, Sendable {
    case micPermissionDenied(underlying: Error? = nil)
    case audioEngineFailure(underlying: Error? = nil)
    case resampleFailure(underlying: Error? = nil)
    case modelLoadFailure(underlying: Error? = nil)
    case transcriptionFailure(underlying: Error? = nil)
    case modelDownloadFailure(underlying: Error? = nil)
}

extension PSError: LocalizedError {
    public var errorDescription: String? { get }
    public var failureReason: String? { get }
    public var recoverySuggestion: String? { get }
}
```

Rules:
- `PCMBuffer` is the only shared audio buffer type.
- `SessionState` is the only Week 1 session state enum.
- `TranscriptionResult.segments` may be empty in v0.1.
- every public failure maps to `PSError`.

### 2. Protocols (`PSCore`)
```swift
import Foundation

public protocol AudioCapturing: Sendable {
    func start() async throws -> AsyncThrowingStream<PCMBuffer, Error>
    func stop() async
}

public protocol Transcribing: Sendable {
    func prepare() async throws
    func transcribe(_ audio: PCMBuffer) async throws -> TranscriptionResult
    func transcribe(stream: AsyncThrowingStream<PCMBuffer, Error>) async throws -> TranscriptionResult
}

public protocol SessionObserving: AnyObject, Sendable {
    func stateStream() -> AsyncStream<SessionState>
}
```

Rules:
- `AudioCapturing.start()` returns the stream.
- `stop()` finishes the stream.
- `transcribe(stream:)` is the authoritative Week 1 full-utterance path.
- UI observation should prefer `AsyncStream<SessionState>`.

### 3. Actor (`PSSession`)
```swift
import Foundation
import PSCore

public actor SessionCoordinator {
    public init(capture: any AudioCapturing, transcriber: any Transcribing, logger: PSLogger)
    public func toggle() async
    public func state() -> SessionState
    public func stateStream() -> AsyncStream<SessionState>
    public func lastResult() -> TranscriptionResult?
}
```

State machine:
```text
[idle] --toggle--> [recording] --toggle--> [transcribing] --success--> [idle]
   \                    \                         \
    \--error------------>\----error---------------> [error(PSError)] -> coordinator-owned recovery
```

Rules:
- `toggle()` from `.idle` starts recording.
- `toggle()` from `.recording` stops capture and starts transcription.
- `toggle()` from `.transcribing` is ignored in Week 1.
- this actor is the single source of truth for session state and `lastResult`.
- Plan 04 MUST observe `stateStream()` and MUST NOT create a second state enum or session manager.

### 4. Logging Facade (`PSCore`)
```swift
import Foundation
import os

public struct PSLogger: Sendable {
    public init(subsystem: String = "com.personalscribe", category: String)
    public func debug(
        _ msg: @autoclosure () -> String,
        file: StaticString = #fileID,
        line: UInt = #line
    )
    public func info(
        _ msg: @autoclosure () -> String,
        file: StaticString = #fileID,
        line: UInt = #line
    )
    public func error(
        _ msg: @autoclosure () -> String,
        error: Error? = nil,
        file: StaticString = #fileID,
        line: UInt = #line
    )
}

public enum PSLogCategory {
    public static let audio = "audio"
    public static let transcription = "transcription"
    public static let session = "session"
    public static let ui = "ui"
    public static let app = "app"
}
```

### 5. Config (`PSCore`)
```swift
import Foundation

public enum PSConfig {
    public static let sampleRate: Double = 16_000
    public static let channelCount: Int = 1
    public static let modelId: String = "parakeet-tdt-0.6b-v2"
    public static func appSupportDirectory() throws -> URL
    public static func modelsDirectory() throws -> URL
}
```

### 6. Composition Root (`PSAppKit`)
```swift
import Foundation
import PSSession

@MainActor
public enum AppComposition {
    public static func makeSessionCoordinator() -> SessionCoordinator
}
```

Rule:
- `AppComposition` is the only production composition site in Plans 01–04.

### 7. Test Doubles (`PSTestSupport`)
```swift
import Foundation
import PSCore

public actor FakeAudioCapturing: AudioCapturing {
    public init(buffers: [PCMBuffer] = [], error: Error? = nil, delayPerBuffer: Duration? = nil)
    public func start() async throws -> AsyncThrowingStream<PCMBuffer, Error>
    public func stop() async
}

public actor FakeTranscriber: Transcribing {
    public init(
        result: TranscriptionResult,
        prepareError: Error? = nil,
        transcribeError: Error? = nil,
        delay: Duration? = nil
    )
    public func prepare() async throws
    public func transcribe(_ audio: PCMBuffer) async throws -> TranscriptionResult
    public func transcribe(stream: AsyncThrowingStream<PCMBuffer, Error>) async throws -> TranscriptionResult
}
```

Rule:
- Plans 02–04 MUST use these fakes in tests rather than creating duplicates.

## D. Cross-Cutting Rules
- Concurrency: Swift Concurrency only in public APIs. No GCD queues, delegate APIs, or callback contracts.
- Sendability: no `@unchecked Sendable` without an inline safety comment.
- DI: constructor injection only. No singletons. No global mutable state.
- Errors: all public failures return `PSError`.
- Thread affinity: UI on `@MainActor`; engine types are actors or `Sendable` structs.
- Logging: never `print()` in production; always `PSLogger`.
- Core purity: `PSCore` imports only `Foundation` and `os`.
- Layering: `PSAppKit` does not talk directly to `PSAudio` or `PSTranscription`.
- Forbidden duplicates: Plans 01–04 MUST NOT define their own `PCMBuffer`, `SessionState`, logger wrapper, session state machine, or composition root.

Authoritative semantics:
- `PCMBuffer.duration = Double(samples.count) / (sampleRate * Double(channelCount))`
- `.error(lhs) == .error(rhs)` if the `PSError` case matches; underlying payload does not affect equality
- `PSError` localized descriptions should be stable enough for tests and UI

## E. Tasks
**Note**: All Plan 00 work happens AFTER Plan 01 Step 1 (`git init` + `Package.swift` scaffolding).

### Step 1. Scaffold `PSCore`
**File**: `/Users/nitinkum/Projects/nitkrar/whisper_flow/Sources/PSCore/PCMBuffer.swift`, `/Users/nitinkum/Projects/nitkrar/whisper_flow/Sources/PSCore/SessionState.swift`, `/Users/nitinkum/Projects/nitkrar/whisper_flow/Sources/PSCore/TranscriptionResult.swift`, `/Users/nitinkum/Projects/nitkrar/whisper_flow/Sources/PSCore/Errors.swift`, `/Users/nitinkum/Projects/nitkrar/whisper_flow/Sources/PSCore/Config.swift`, `/Users/nitinkum/Projects/nitkrar/whisper_flow/Sources/PSCore/Logger.swift`, `/Users/nitinkum/Projects/nitkrar/whisper_flow/Sources/PSCore/Protocols.swift`
### 1a. Write failing test
```swift
import XCTest
@testable import PSCore

final class PSCoreScaffoldingTests: XCTestCase {
    func testCoreSymbolsCompile() {
        _ = SessionState.idle
        _ = PSLogCategory.audio
        XCTAssertEqual(PSConfig.sampleRate, 16_000)
    }
}
```
### 1b. Run test to verify it fails
```bash
swift test --filter PSCoreScaffoldingTests/testCoreSymbolsCompile
```
### 1c. Write implementation
```swift
// Add compiling stubs using the authoritative signatures in this document.
```
### 1d. Run test to verify it passes
```bash
swift test --filter PSCoreScaffoldingTests/testCoreSymbolsCompile
```
### 1e. Commit
```bash
git commit -m "plan-00 step 1: scaffold pscore contracts"
```

### Step 2. Implement `PCMBuffer`
**File**: `/Users/nitinkum/Projects/nitkrar/whisper_flow/Sources/PSCore/PCMBuffer.swift`
### 2a. Write failing test
```swift
import XCTest
@testable import PSCore

final class PCMBufferTests: XCTestCase {
    func testDurationAndValidation() throws {
        let buffer = try PCMBuffer(samples: Array(repeating: 0, count: 16_000))
        XCTAssertEqual(buffer.frameCount, 16_000)
        XCTAssertEqual(buffer.duration, .seconds(1))
        XCTAssertThrowsError(try PCMBuffer(samples: [0], sampleRate: 0, channelCount: 1))
    }
}
```
### 2b. Run test to verify it fails
```bash
swift test --filter PCMBufferTests/testDurationAndValidation
```
### 2c. Write implementation
```swift
public struct PCMBuffer: Sendable {
    public let samples: [Float]
    public let sampleRate: Double
    public let channelCount: Int
    public let timestamp: ContinuousClock.Instant
    public init(samples: [Float], sampleRate: Double = PSConfig.sampleRate, channelCount: Int = PSConfig.channelCount, timestamp: ContinuousClock.Instant = ContinuousClock().now) throws {
        guard sampleRate > 0, channelCount > 0 else { throw PSError.resampleFailure() }
        self.samples = samples; self.sampleRate = sampleRate; self.channelCount = channelCount; self.timestamp = timestamp
    }
    public var frameCount: Int { samples.count / channelCount }
    public var duration: Duration { .seconds(Double(samples.count) / (sampleRate * Double(channelCount))) }
}
```
### 2d. Run test to verify it passes
```bash
swift test --filter PCMBufferTests/testDurationAndValidation
```
### 2e. Commit
```bash
git commit -m "plan-00 step 2: implement pcmbuffer"
```

### Step 3. Implement `SessionState` equality
**File**: `/Users/nitinkum/Projects/nitkrar/whisper_flow/Sources/PSCore/SessionState.swift`
### 3a. Write failing test
```swift
import XCTest
@testable import PSCore

final class SessionStateTests: XCTestCase {
    func testErrorEqualityIgnoresUnderlying() {
        enum Dummy: Error { case one, two }
        XCTAssertEqual(
            SessionState.error(.audioEngineFailure(underlying: Dummy.one)),
            SessionState.error(.audioEngineFailure(underlying: Dummy.two))
        )
    }
}
```
### 3b. Run test to verify it fails
```bash
swift test --filter SessionStateTests/testErrorEqualityIgnoresUnderlying
```
### 3c. Write implementation
```swift
public enum SessionState: Sendable, Equatable {
    case idle, recording, transcribing, error(PSError)
    // Implement custom Equatable so .error compares by PSError case, not underlying payload.
}
```
### 3d. Run test to verify it passes
```bash
swift test --filter SessionStateTests/testErrorEqualityIgnoresUnderlying
```
### 3e. Commit
```bash
git commit -m "plan-00 step 3: define sessionstate equality"
```

### Step 4. Implement `PSError`
**File**: `/Users/nitinkum/Projects/nitkrar/whisper_flow/Sources/PSCore/Errors.swift`
### 4a. Write failing test
```swift
import XCTest
@testable import PSCore

final class PSErrorTests: XCTestCase {
    func testLocalizedDescriptions() {
        XCTAssertEqual(PSError.micPermissionDenied().errorDescription, "Microphone permission was denied.")
        XCTAssertEqual(PSError.transcriptionFailure().errorDescription, "Transcription failed.")
    }
}
```
### 4b. Run test to verify it fails
```bash
swift test --filter PSErrorTests/testLocalizedDescriptions
```
### 4c. Write implementation
```swift
public enum PSError: Error, Sendable {
    case micPermissionDenied(underlying: Error? = nil)
    case audioEngineFailure(underlying: Error? = nil)
    case resampleFailure(underlying: Error? = nil)
    case modelLoadFailure(underlying: Error? = nil)
    case transcriptionFailure(underlying: Error? = nil)
    case modelDownloadFailure(underlying: Error? = nil)
}

extension PSError: LocalizedError {
    public var errorDescription: String? {
        switch self {
        case .micPermissionDenied: return "Microphone permission was denied."
        case .audioEngineFailure: return "Audio capture failed."
        case .resampleFailure: return "Audio resampling failed."
        case .modelLoadFailure: return "The transcription model could not be loaded."
        case .transcriptionFailure: return "Transcription failed."
        case .modelDownloadFailure: return "The transcription model could not be downloaded."
        }
    }
}
```
### 4d. Run test to verify it passes
```bash
swift test --filter PSErrorTests/testLocalizedDescriptions
```
### 4e. Commit
```bash
git commit -m "plan-00 step 4: implement pserror messages"
```

### Step 5. Implement `PSConfig`
**File**: `/Users/nitinkum/Projects/nitkrar/whisper_flow/Sources/PSCore/Config.swift`
### 5a. Write failing test
```swift
import XCTest
@testable import PSCore

final class PSConfigTests: XCTestCase {
    func testModelsDirectoryNestsUnderAppSupport() throws {
        let appSupport = try PSConfig.appSupportDirectory()
        let models = try PSConfig.modelsDirectory()
        XCTAssertEqual(models.deletingLastPathComponent(), appSupport)
        XCTAssertEqual(models.lastPathComponent, "models")
    }
}
```
### 5b. Run test to verify it fails
```bash
swift test --filter PSConfigTests/testModelsDirectoryNestsUnderAppSupport
```
### 5c. Write implementation
```swift
public enum PSConfig {
    public static let sampleRate: Double = 16_000
    public static let channelCount: Int = 1
    public static let modelId: String = "parakeet-tdt-0.6b-v2"
    public static func appSupportDirectory() throws -> URL
    public static func modelsDirectory() throws -> URL
}
// appSupportDirectory -> ~/Library/Application Support/PersonalScribe
// modelsDirectory -> appSupportDirectory()/models
```
### 5d. Run test to verify it passes
```bash
swift test --filter PSConfigTests/testModelsDirectoryNestsUnderAppSupport
```
### 5e. Commit
```bash
git commit -m "plan-00 step 5: implement psconfig directories"
```

### Step 6. Implement `PSLogger`
**File**: `/Users/nitinkum/Projects/nitkrar/whisper_flow/Sources/PSCore/Logger.swift`
### 6a. Write failing test
```swift
import XCTest
@testable import PSCore

final class PSLoggerTests: XCTestCase {
    func testLoggerFacadeCompiles() {
        let logger = PSLogger(category: PSLogCategory.session)
        logger.debug("debug"); logger.info("info"); logger.error("error")
        XCTAssertEqual(PSLogCategory.audio, "audio")
    }
}
```
### 6b. Run test to verify it fails
```bash
swift test --filter PSLoggerTests/testLoggerFacadeCompiles
```
### 6c. Write implementation
```swift
public struct PSLogger: Sendable { /* wraps os.Logger */ }
public enum PSLogCategory {
    public static let audio = "audio"
    public static let transcription = "transcription"
    public static let session = "session"
    public static let ui = "ui"
    public static let app = "app"
}
```
### 6d. Run test to verify it passes
```bash
swift test --filter PSLoggerTests/testLoggerFacadeCompiles
```
### 6e. Commit
```bash
git commit -m "plan-00 step 6: implement pslogger facade"
```

### Step 7. Declare protocols
**File**: `/Users/nitinkum/Projects/nitkrar/whisper_flow/Sources/PSCore/Protocols.swift`
### 7a. Write failing test
```swift
// No dedicated XCTest; compile verification comes from downstream tests.
```
### 7b. Run test to verify it fails
```bash
swift test --filter PSCoreScaffoldingTests/testCoreSymbolsCompile
```
### 7c. Write implementation
```swift
public protocol AudioCapturing: Sendable {
    func start() async throws -> AsyncThrowingStream<PCMBuffer, Error>
    func stop() async
}
public protocol Transcribing: Sendable {
    func prepare() async throws
    func transcribe(_ audio: PCMBuffer) async throws -> TranscriptionResult
    func transcribe(stream: AsyncThrowingStream<PCMBuffer, Error>) async throws -> TranscriptionResult
}
public protocol SessionObserving: AnyObject, Sendable {
    func stateStream() -> AsyncStream<SessionState>
}
```
### 7d. Run test to verify it passes
```bash
swift test --filter PSCoreScaffoldingTests/testCoreSymbolsCompile
```
### 7e. Commit
```bash
git commit -m "plan-00 step 7: declare shared protocols"
```

### Step 8. Add `PSTestSupport`
**File**: `/Users/nitinkum/Projects/nitkrar/whisper_flow/Sources/PSTestSupport/FakeAudioCapturing.swift`, `/Users/nitinkum/Projects/nitkrar/whisper_flow/Sources/PSTestSupport/FakeTranscriber.swift`
### 8a. Write failing test
```swift
import XCTest
import PSCore
@testable import PSTestSupport

final class FakeSupportTests: XCTestCase {
    func testFakeTranscriberReturnsPresetResult() async throws {
        let expected = TranscriptionResult(text: "hello", audioDuration: .seconds(1), processingDuration: .seconds(0.2))
        let fake = FakeTranscriber(result: expected)
        try await fake.prepare()
        let actual = try await fake.transcribe(try PCMBuffer(samples: Array(repeating: 0, count: 16_000)))
        XCTAssertEqual(actual.text, "hello")
    }
}
```
### 8b. Run test to verify it fails
```bash
swift test --filter FakeSupportTests/testFakeTranscriberReturnsPresetResult
```
### 8c. Write implementation
```swift
public actor FakeAudioCapturing: AudioCapturing { /* emits canned buffers then finishes */ }
public actor FakeTranscriber: Transcribing { /* returns preset result, optional delay/error */ }
```
### 8d. Run test to verify it passes
```bash
swift test --filter FakeSupportTests/testFakeTranscriberReturnsPresetResult
```
### 8e. Commit
```bash
git commit -m "plan-00 step 8: add reusable test fakes"
```

### Step 9. Add `SessionCoordinator`
**File**: `/Users/nitinkum/Projects/nitkrar/whisper_flow/Sources/PSSession/SessionCoordinator.swift`
### 9a. Write failing test
```swift
import XCTest
import PSCore
import PSTestSupport
@testable import PSSession

final class SessionCoordinatorTests: XCTestCase {
    func testToggleWalksIdleRecordingTranscribingIdle() async throws {
        let buffer = try PCMBuffer(samples: Array(repeating: 0, count: 16_000))
        let capture = FakeAudioCapturing(buffers: [buffer])
        let transcriber = FakeTranscriber(result: .init(text: "hello", audioDuration: .seconds(1), processingDuration: .seconds(0.2)))
        let coordinator = SessionCoordinator(capture: capture, transcriber: transcriber, logger: PSLogger(category: PSLogCategory.session))
        let stream = await coordinator.stateStream()
        var iterator = stream.makeAsyncIterator()
        await coordinator.toggle(); await coordinator.toggle()
        let observed = try await [iterator.next(), iterator.next(), iterator.next(), iterator.next()].compactMap { $0 }
        XCTAssertEqual(observed, [.idle, .recording, .transcribing, .idle])
    }
}
```
### 9b. Run test to verify it fails
```bash
swift test --filter SessionCoordinatorTests/testToggleWalksIdleRecordingTranscribingIdle
```
### 9c. Write implementation
```swift
public actor SessionCoordinator {
    // Holds current SessionState, last TranscriptionResult, and AsyncStream continuations.
    // toggle() owns the only valid Week 1 state transitions.
}
```
### 9d. Run test to verify it passes
```bash
swift test --filter SessionCoordinatorTests/testToggleWalksIdleRecordingTranscribingIdle
```
### 9e. Commit
```bash
git commit -m "plan-00 step 9: add session coordinator"
```

### Step 10. Add `AppComposition`
**File**: `/Users/nitinkum/Projects/nitkrar/whisper_flow/Sources/PSAppKit/Composition/AppComposition.swift`
### 10a. Write failing test
```swift
// No dedicated XCTest in Week 1 for the AppKit composition root.
```
### 10b. Run test to verify it fails
```bash
swift test --filter SessionCoordinatorTests/testToggleWalksIdleRecordingTranscribingIdle
```
### 10c. Write implementation
```swift
@MainActor
public enum AppComposition {
    public static func makeSessionCoordinator() -> SessionCoordinator
}
```
### 10d. Run test to verify it passes
```bash
swift test --filter SessionCoordinatorTests/testToggleWalksIdleRecordingTranscribingIdle
```
### 10e. Commit
```bash
git commit -m "plan-00 step 10: add app composition root"
```

## F. Dependency Table
| Group | Steps | Can Parallelize | Notes |
|---|---|---|---|
| 1 | 1 | — | After Plan 01 Step 1. |
| 2 | 2–6 | Yes | Pure value types, independent files. |
| 3 | 7 | No | Depends on types from Group 2. |
| 4 | 8 | No | Depends on protocols. |
| 5 | 9 | No | Depends on fakes + actor. |
| 6 | 10 | No | Final wiring. |

## G. Handoff Contract
- Plan 01 may consume target names, directory layout, and test target names. It MUST NOT rename targets or add a second shared core module.
- Plan 02 implements `AudioCapturing` only. It MUST NOT redefine `PCMBuffer`, `PSError`, `PSLogger`, or any session state enum.
- Plan 03 implements `Transcribing` only. It MUST NOT redefine `TranscriptionResult`, `PSError`, `SessionCoordinator`, or invent a second transcription DTO.
- Plan 04 consumes `SessionCoordinator.stateStream()` only. It MUST NOT create its own state enum, session manager, or production composition site.

Downstream consumable symbols:
- Plan 01: `PSCore`, `PSAudio`, `PSTranscription`, `PSSession`, `PSAppKit`, `PSTestSupport`, `PSCoreTests`, `PSAudioTests`, `PSTranscriptionTests`, `PSSessionTests`
- Plan 02: `PCMBuffer`, `PSError`, `PSLogger`, `PSLogCategory`, `PSConfig`, `AudioCapturing`
- Plan 03: `Transcribing`, `TranscriptionResult`, `PSError`, `PSLogger`, `PSConfig`, `SessionCoordinator`
- Plan 04: `SessionCoordinator`, `SessionState`, `TranscriptionResult`, `AppComposition`

## Open Questions Flagged
1. Plan 03 must verify the exact FluidAudio API and pin a specific version.
2. `SessionCoordinator` recovery policy after `.error` needs one decision: transient error state or sticky-until-next-toggle.
3. `PCMBuffer` validation currently maps invalid metadata to `PSError.resampleFailure`; implementation may choose a stricter internal helper, but public failure must still surface as `PSError`.
4. `SessionObserving` may be redundant in Week 1 because `SessionCoordinator` already exposes `stateStream()`; keep it unless a later plan explicitly revises the contract.
5. `AppComposition` will need temporary compile-safe placeholders until Plans 02 and 03 land, but no second composition path is allowed.

# Plan 00: Common Components & Shared Contracts (v2)

**Goal**: Define the single shared Week 1 contract surface so Plans 01–04 can build in parallel without inventing duplicate types, ownership paths, or bootstrapping behavior.
**Architecture**: Swift Package Manager multi-target app, actor-based session coordination, constructor DI, `os.Logger` facade, 16kHz mono Float32 PCM pipeline, full-utterance transcription for Week 1.
**Tech Stack**: Swift 6-ready APIs, SwiftUI + AppKit, AVFoundation, `os.Logger`, XCTest, FluidAudio/Parakeet via Plan 03.

## Changes from v1

- Issue #1 (Claude + Codex): `SeshatError` is now a payload-free `Sendable` enum; underlying concrete errors are logged before mapping, which removes the Swift 6 `Sendable` conflict and the invalid enum-associated-value defaults.
- Issue #2 (Claude + Codex): `SessionObserving` was deleted for Week 1; `SessionCoordinator.stateStream()` is the only public observation surface.
- Issue #3 (Claude + Codex): `AudioCapturing.start()` and `stop()` now have an explicit single-active-capture, idempotent-stop, finish-exactly-once contract in both Section C and Section D.
- Issue #4 (Claude + Codex): Week 1 transcription is now explicitly full-utterance replay; `SessionCoordinator` buffers during `.recording`, stops capture, then passes a finite replay stream into `transcribe(stream:)`.
- Issue #5 (Claude + Codex): Section D now has `Ownership Rules` covering one app-lifetime coordinator, directory creation semantics, model download ownership, mic permission ownership, and the single logger subsystem constant.
- Issue #6 (Claude + Codex): Step 7 and Step 10 now include real XCTest coverage for protocol conformance and composition-root singleton behavior.
- Issue #7 (Claude + Codex): Section F’s DAG is corrected; Steps 2 and 3 depend on Step 4, while Steps 5 and 6 remain independent.
- Issue #8 (Claude + Codex): the layering rule now explicitly chooses option B; `SeshatAppKit` is the executable composition root and may depend on `SeshatAudio` and `SeshatTranscription` only from `Composition/`.
- Issue #9 (Claude): `PCMBuffer.timestamp` no longer uses a non-literal default; callers must pass it explicitly.
- Issue #10 (Claude): Step 1 is split into one scaffold step per file and Step 9 is split into storage/stream, happy-path toggle, and replay/error plumbing.
- Issue #11 (Claude): the `SessionCoordinatorTests` snippet now subscribes first and consumes `stateStream()` with `for await ... prefix(4)` while driving `toggle()` concurrently.
- Issue #12 (Codex): stream signatures still use `AsyncThrowingStream<..., Error>` for compatibility, but the contract now states that any thrown runtime error is always a `SeshatError`, and the fakes are shaped to honor that.
- Suggestion (Claude): `PCMBuffer.duration` now documents the invariant that duration is derived from `frameCount / sampleRate`, so `channelCount` is not double-counted.
- Suggestion (Claude): `SeshatError.cancelled` and `SeshatError.invalidState` were added for coordinator-owned failure paths.
- Suggestion (Claude): `SeshatConfig` path tests and rules now use `standardizedFileURL` for comparisons.
- Suggestion (Codex): behavior expectations now explicitly cover initial-state delivery on `stateStream()`, `lastResult()`, and repeated toggles during `.transcribing`.
- Suggestion (Codex): the document now states explicitly that `AppComposition` lives in the app executable target, not a reusable library target.

## Changes in v2.1 (Claude post-review)

- Step 10 (`AppComposition` implementation) moved out of Plan 00 into a new Plan 99 (Week 1 Integration) that runs AFTER Plans 02 and 03 ship production `AVAudioCaptureService` and `FluidAudioTranscriber`. Plan 00 still defines the API surface in Section C.6; only the wiring is deferred. Rationale: Step 10 as originally written could not complete within Plan 00 because it depends on types that do not exist until Plans 02/03 land. Stub-now-wire-later was rejected because it creates dead code that must be deleted.
- `SeshatConfig` now exposes a test-only base-directory override so unit tests do not pollute `~/Library/Application Support/Seshat` on the developer's machine (Section C.5, D.6).
- `FakeAudioCapturing` stream-lifetime contract pinned: after preset buffers are exhausted the stream remains open and finishes only on `stop()` or runtime error (Section C.7).
- Step 1 scaffold ordering fixed: Step 1.5 (`SeshatConfig`) is sequenced before Steps 1.1–1.3 because `PCMBuffer.init` scaffolds reference `SeshatConfig.sampleRate` / `SeshatConfig.channelCount` as default values.
- `AppComposition.sessionCoordinator` declaration now carries an explicit comment noting that initialization happens in Plan 99, to prevent copy-paste as-is into a scaffold (Section C.6).

## A. Header

### Scope

This plan is authoritative for shared Week 1 components only. It exists to stop Plans 01–04 from making incompatible choices about:

- shared data types
- protocol signatures
- error mapping
- ownership boundaries
- composition-root behavior
- reusable test doubles

### Week 1 consumers

- Plan 01: SPM setup, target graph, source/test directories, executable wiring
- Plan 02: AVAudioEngine capture and 16kHz mono Float32 resampling behind `AudioCapturing`
- Plan 03: FluidAudio/Parakeet integration and model download behind `Transcribing`
- Plan 04: menu bar app bootstrap, mic permission flow, and UI observation of `SessionCoordinator`

### Week 1 non-goals

- no global hotkey yet
- no paste injection yet
- no notes database yet
- no settings persistence beyond `SeshatConfig`
- no alternate state machine
- no second composition root
- no streaming partial-transcript UI

### Authoritative intent

If a shared type or rule is in this document, downstream plans must consume it instead of redefining it. If a downstream plan needs a contract change, the plan must revise Plan 00 instead of silently forking behavior.

## B. Module layout

### Target graph

```text
                 ┌─────────────┐
                 │   SeshatCore    │
                 │ shared API  │
                 │ types/rules │
                 └──────┬──────┘
                        │
         ┌──────────────┼──────────────┐
         ▼              ▼              ▼
   ┌──────────┐   ┌───────────────┐  ┌──────────────┐
   │ SeshatAudio  │   │SeshatTranscription│  │ SeshatTestSupport│
   │ capture  │   │ model wrapper │  │ shared fakes │
   └────┬─────┘   └──────┬────────┘  └──────────────┘
        │                │
        └────────┬───────┘
                 ▼
           ┌────────────┐
           │ SeshatSession  │
           │ actor      │
           └─────┬──────┘
                 ▼
           ┌────────────┐
           │  SeshatAppKit  │  executable target
           │ bootstrap  │  composition root
           └────────────┘

SeshatCoreTests -> SeshatCore
SeshatAudioTests -> SeshatAudio + SeshatTestSupport
SeshatTranscriptionTests -> SeshatTranscription + SeshatTestSupport
SeshatSessionTests -> SeshatSession + SeshatTestSupport
SeshatAppKitTests -> SeshatAppKit + SeshatTestSupport
```

### Target responsibilities

- `SeshatCore`: shared value types, errors, config, logger facade, protocol contracts, permission protocol, model-download progress type. Imports only `Foundation` and `os`.
- `SeshatAudio`: production microphone capture, resampling, stream lifecycle management. Depends on `SeshatCore`.
- `SeshatTranscription`: production model preparation, download progress, and transcription replay consumption. Depends on `SeshatCore` and `FluidAudio`.
- `SeshatSession`: `SessionCoordinator` actor. Depends on `SeshatCore`, `SeshatAudio`, and `SeshatTranscription`.
- `SeshatAppKit`: app executable target. Owns bootstrapping, app-lifetime coordinator, and mic permission request flow. Depends on `SeshatCore`, `SeshatAudio`, `SeshatTranscription`, and `SeshatSession`, but direct imports of `SeshatAudio` and `SeshatTranscription` are allowed only under `Sources/SeshatAppKit/Composition/`.
- `SeshatTestSupport`: reusable fakes and helpers. Depends on `SeshatCore` only.

### Directory layout

```text
Package.swift
Sources/
  SeshatCore/
    PCMBuffer.swift
    SessionState.swift
    TranscriptionResult.swift
    Errors.swift
    Config.swift
    Logger.swift
    Protocols.swift
  SeshatAudio/
    AVAudioCaptureService.swift
    AudioResampler.swift
  SeshatTranscription/
    FluidAudioTranscriber.swift
  SeshatSession/
    SessionCoordinator.swift
  SeshatAppKit/
    SeshatApp.swift
    AppDelegate.swift
    Permissions/
      AppKitMicrophonePermissionRequester.swift
    Composition/
      AppComposition.swift
  SeshatTestSupport/
    FakeAudioCapturing.swift
    FakeTranscriber.swift
Tests/
  SeshatCoreTests/
  SeshatAudioTests/
  SeshatTranscriptionTests/
  SeshatSessionTests/
  SeshatAppKitTests/
```

### Layering decision

This document chooses option B from the review prompt.

- `SeshatAppKit` is the composition root.
- `SeshatAppKit` is therefore allowed to depend on `SeshatAudio` and `SeshatTranscription`.
- That allowance is narrow: only files under `Sources/SeshatAppKit/Composition/` may directly import those modules.
- All other `SeshatAppKit` files consume only `SeshatSession`, `SeshatCore`, and AppKit/SwiftUI APIs.

### Plan 03 verification note

- Plan 03 must verify the exact FluidAudio API surface before implementation.
- Plan 03 may adapt internally to upstream naming, but it must preserve the public `Transcribing` contract defined here.
- Plan 03 owns mapping upstream progress callbacks or notifications into `modelDownloadProgress()`.

## C. Public API surface

### C.1 Core types (`SeshatCore`)

```swift
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
    ) throws

    public var frameCount: Int { get }
    public var duration: Duration { get }
}

public enum SessionState: Sendable, Equatable {
    case idle
    case recording
    case transcribing
    case error(SeshatError)
}

public struct TranscriptionResult: Sendable, Equatable {
    public struct Segment: Sendable, Equatable {
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

public enum SeshatError: Error, Sendable, Equatable {
    case micPermissionDenied
    case audioEngineFailure
    case resampleFailure
    case modelLoadFailure
    case transcriptionFailure
    case modelDownloadFailure
    case cancelled
    case invalidState
}

extension SeshatError: LocalizedError {
    public var errorDescription: String? { get }
    public var failureReason: String? { get }
    public var recoverySuggestion: String? { get }
}

public struct ModelDownloadProgress: Sendable, Equatable {
    public enum Phase: Sendable, Equatable {
        case idle
        case downloading
        case finished
    }

    public let phase: Phase
    public let fractionCompleted: Double
    public let receivedBytes: Int64
    public let expectedBytes: Int64?

    public init(
        phase: Phase,
        fractionCompleted: Double,
        receivedBytes: Int64,
        expectedBytes: Int64?
    )
}
```

Authoritative rules:

- `PCMBuffer` is the only shared audio-buffer type in Week 1.
- `PCMBuffer.timestamp` must be supplied by the capture layer or the test creating the buffer. There is no default timestamp factory in the public initializer.
- `PCMBuffer.frameCount` is `samples.count / channelCount`.
- `PCMBuffer.duration` is `Double(frameCount) / sampleRate`; duration must not divide by `channelCount` a second time.
- `TranscriptionResult.segments` may be empty in Week 1.
- `SeshatError` is intentionally payload-free. Underlying concrete errors are logged before they are mapped to `SeshatError`.
- `SeshatError.cancelled` and `SeshatError.invalidState` are reserved for coordinator-owned and user-driven paths; they are not a license for downstream plans to invent new state machines.

### C.2 Core protocols (`SeshatCore`)

```swift
import Foundation

public protocol AudioCapturing: Sendable {
    func start() async throws -> AsyncThrowingStream<PCMBuffer, Error>
    func stop() async
}

public protocol Transcribing: Sendable {
    func prepare() async throws
    func modelDownloadProgress() -> AsyncStream<ModelDownloadProgress>
    func transcribe(_ audio: PCMBuffer) async throws -> TranscriptionResult
    func transcribe(stream: AsyncThrowingStream<PCMBuffer, Error>) async throws -> TranscriptionResult
}

public protocol MicrophonePermissionRequesting: Sendable {
    func requestAccess() async -> Bool
}
```

Authoritative rules:

- `AudioCapturing.start()` returns the single active capture stream.
- A second `start()` call while capture is already live throws `SeshatError.audioEngineFailure`.
- `AudioCapturing.stop()` is idempotent.
- The capture stream finishes normally on `stop()`.
- The capture stream finishes with a thrown `SeshatError` on runtime failure.
- The capture stream finishes exactly once.
- The dynamic runtime error type surfaced by `AudioCapturing.start()` streams is always `SeshatError`, even though the generic signature uses `Error`.
- `Transcribing.prepare()` is allowed to trigger a first-run model download.
- `Transcribing.modelDownloadProgress()` is the only shared Week 1 model-download progress stream.
- The dynamic runtime error type surfaced by `transcribe(stream:)` is always `SeshatError`.
- `transcribe(_ audio:)` exists for small unit tests and narrow helpers.
- `transcribe(stream:)` is the authoritative Week 1 production path.

### C.3 Session actor (`SeshatSession`)

```swift
import Foundation
import SeshatCore

public actor SessionCoordinator {
    public init(
        capture: any AudioCapturing,
        transcriber: any Transcribing,
        logger: SeshatLogger
    )

    public func toggle() async
    public func state() -> SessionState
    public func stateStream() -> AsyncStream<SessionState>
    public func lastResult() -> TranscriptionResult?
}
```

State machine:

```text
[idle]
  -- toggle -->
[recording]
  rule: coordinator subscribes to capture.start()
  rule: coordinator buffers each PCMBuffer locally
  -- toggle -->
[transcribing]
  rule: coordinator calls capture.stop()
  rule: coordinator seals recording buffer collection
  rule: coordinator creates a finite replay AsyncThrowingStream
  rule: coordinator passes replay stream to transcribe(stream:)
  -- success -->
[idle]

[idle] -------- failure --------> [error(SeshatError)]
[recording] --- failure --------> [error(SeshatError)]
[transcribing] - failure -------> [error(SeshatError)]
[error(SeshatError)] -- next toggle -> [idle] then immediate retry path is allowed
```

Authoritative rules:

- `toggle()` from `.idle` starts recording.
- `toggle()` from `.recording` stops capture, transitions to `.transcribing`, and starts full-utterance transcription from the buffered replay stream.
- `toggle()` from `.transcribing` does nothing except log an ignored-transition event.
- `toggle()` from `.error` first clears the error back to `.idle`, then re-enters the normal idle toggle path on the same call.
- `stateStream()` must yield the current state immediately to a new subscriber before yielding future transitions.
- `stateStream()` is the only UI-observation contract for Week 1.
- `lastResult()` returns the most recent successful transcription result and remains unchanged by ignored toggles.

### C.4 Logging facade (`SeshatCore`)

```swift
import Foundation
import os

public struct SeshatLogger: Sendable {
    public static let subsystem = "com.nitkrar.seshat"

    public init(category: String)

    public func debug(
        _ message: @autoclosure () -> String,
        file: StaticString = #fileID,
        line: UInt = #line
    )

    public func info(
        _ message: @autoclosure () -> String,
        file: StaticString = #fileID,
        line: UInt = #line
    )

    public func error(
        _ message: @autoclosure () -> String,
        error: (any Error)? = nil,
        file: StaticString = #fileID,
        line: UInt = #line
    )
}

public enum SeshatLogCategory {
    public static let audio = "audio"
    public static let transcription = "transcription"
    public static let session = "session"
    public static let ui = "ui"
    public static let app = "app"
}
```

Authoritative rules:

- `SeshatLogger.subsystem` is the single public subsystem constant.
- Production code must not hardcode `"com.nitkrar.seshat"` anywhere else.
- `SeshatLogger.error` may log an underlying concrete error, but public contracts still surface `SeshatError`.

### C.5 Config (`SeshatCore`)

```swift
import Foundation

public enum SeshatConfig {
    public static let sampleRate: Double = 16_000
    public static let channelCount: Int = 1
    public static let modelId: String = "parakeet-tdt-0.6b-v2"

    public static func appSupportDirectory() throws -> URL
    public static func modelsDirectory() throws -> URL

    /// Test-only override. When non-nil, `appSupportDirectory()` returns
    /// `<override>/Seshat` instead of the real `~/Library/Application Support/Seshat`.
    /// Tests MUST set this in `setUp()` (usually to `FileManager.default.temporaryDirectory`)
    /// and reset to `nil` in `tearDown()`. Production code MUST NOT set this value.
    public static var testingBaseDirectoryOverride: URL? { get set }
}
```

Authoritative rules:

- `appSupportDirectory()` returns `~/Library/Application Support/Seshat` in production, or `<testingBaseDirectoryOverride>/Seshat` when the override is set.
- `modelsDirectory()` returns `appSupportDirectory()/models`.
- Both functions create their directories if missing.
- Both functions return `standardizedFileURL`.
- First-call creation is thread-safe and may be performed lazily by whichever consumer needs the path first.
- `testingBaseDirectoryOverride` is intended for hermetic XCTest runs only. It is declared `nonisolated(unsafe)` and must be mutated only from a single test thread (XCTest's default). Production code paths must treat it as if it were immutable.

### C.6 Composition root (`SeshatAppKit`)

```swift
import Foundation
import SeshatCore
import SeshatAudio
import SeshatTranscription
import SeshatSession

@MainActor
public enum AppComposition {
    // NOTE: initializer body is provided by Plan 99 (Week 1 Integration), which
    // depends on production AVAudioCaptureService (Plan 02) and
    // FluidAudioTranscriber (Plan 03). Do NOT scaffold this as a bare declaration
    // in Plan 00; it will not compile without the production types wired in.
    public static let sessionCoordinator: SessionCoordinator

    public static func makeSessionCoordinator() -> SessionCoordinator
    public static func makeMicrophonePermissionRequester() -> any MicrophonePermissionRequesting
}
```

Authoritative rules:

- `AppComposition` lives in the app executable target.
- `AppComposition.sessionCoordinator` is the single production `SessionCoordinator` for the app lifetime.
- `makeSessionCoordinator()` returns `sessionCoordinator`.
- `AppComposition` is the only production composition site in Plans 01–04.
- `AppComposition` IMPLEMENTATION is deferred to Plan 99 (Week 1 Integration). Plan 00 defines only the API surface here; no file is created under `Sources/SeshatAppKit/Composition/` during Plan 00 execution.
- Plan 99 runs after Plans 02 and 03 complete; see Section E and Section G.

### C.7 Test doubles (`SeshatTestSupport`)

```swift
import Foundation
import SeshatCore

public actor FakeAudioCapturing: AudioCapturing {
    public init(
        buffers: [PCMBuffer] = [],
        error: SeshatError? = nil,
        delayPerBuffer: Duration? = nil
    )

    public func start() async throws -> AsyncThrowingStream<PCMBuffer, Error>
    public func stop() async
}

public actor FakeTranscriber: Transcribing {
    public init(
        result: TranscriptionResult,
        prepareError: SeshatError? = nil,
        transcribeError: SeshatError? = nil,
        delay: Duration? = nil
    )

    public func prepare() async throws
    public func modelDownloadProgress() -> AsyncStream<ModelDownloadProgress>
    public func transcribe(_ audio: PCMBuffer) async throws -> TranscriptionResult
    public func transcribe(stream: AsyncThrowingStream<PCMBuffer, Error>) async throws -> TranscriptionResult
}
```

Authoritative rules:

- `FakeAudioCapturing` must honor the same single-active-capture and finish-exactly-once contract as production capture.
- `FakeAudioCapturing` must throw only `SeshatError` dynamically.
- When preset buffers are exhausted before `stop()` is called, the stream stays OPEN (no further buffers yielded, no auto-finish). The stream finishes on `stop()` or when an error is programmed to fire. This matches production capture semantics, where an idle mic does not end the stream.
- If `error` is non-nil in the init, the stream yields preset buffers first, then throws `error` and finishes exactly once.
- `FakeTranscriber` must surface only `SeshatError` dynamically.
- Plans 02–04 must reuse these fakes instead of creating duplicate shared fakes.

## D. Cross-cutting rules

### D.1 Concurrency

- Public async APIs use Swift Concurrency only.
- No public GCD queues, delegate callbacks, or completion-handler contracts.
- No `@unchecked Sendable` unless the implementation includes a short inline safety comment explaining the exact synchronization boundary.
- `AudioCapturing` supports only one live stream at a time.
- `AudioCapturing.stop()` may be called more than once and must remain safe.
- Every capture stream must terminate exactly once.
- `SessionCoordinator.stateStream()` must yield the current state immediately on subscription.
- `SessionCoordinator` owns the replay-stream creation for Week 1; downstream plans must not bypass it with an alternate state machine.

### D.2 DI

- Constructor injection only for production engine types.
- No mutable global registries.
- `AppComposition.sessionCoordinator` is a composition-owned static constant, not a free-floating singleton service locator.
- Tests may directly instantiate `SessionCoordinator` with fakes.

### D.3 Errors

- All public runtime failures map to `SeshatError`.
- This includes dynamic stream failures from `AudioCapturing.start()` and `Transcribing.transcribe(stream:)`.
- Underlying concrete errors are logged, not stored in `SeshatError`.
- `SeshatError.invalidState` is reserved for impossible coordinator transitions or protocol misuse detected inside a shared component.
- `SeshatError.cancelled` is reserved for explicit user- or app-driven cancellation paths that are not transport failures.
- Localized descriptions should remain stable enough for UI and deterministic tests.

### D.4 Thread affinity

- AppKit and SwiftUI entry points stay on `@MainActor`.
- `SessionCoordinator` is an actor and owns its own synchronization.
- `SeshatCore` types stay `Sendable` value types.
- `SeshatLogger` is `Sendable` and may be passed across actors.

### D.5 Logging

- Production code never calls `print()`.
- Production code always uses `SeshatLogger`.
- Use `SeshatLogger.subsystem` instead of hardcoded subsystem strings.
- Categories are constrained to `SeshatLogCategory` constants in Week 1.
- Each public failure path should log the underlying concrete error before mapping to `SeshatError`.

### D.6 Ownership Rules (NEW)

- Exactly one `SessionCoordinator` exists for the app lifetime.
- Ownership of that coordinator belongs to `AppComposition.sessionCoordinator`.
- `AppComposition.makeSessionCoordinator()` is a convenience accessor, not a factory that creates new instances.
- `SeshatConfig.appSupportDirectory()` and `SeshatConfig.modelsDirectory()` create directories on first call if missing.
- Directory creation is thread-safe and idempotent.
- Model download ownership belongs to the transcription layer.
- Plan 03 may download during `prepare()`, but it must expose progress only through `modelDownloadProgress()`.
- Mic permission prompting belongs to app bootstrap and UI flow, not to `SeshatAudio`.
- Plan 04 must provide the production `MicrophonePermissionRequesting` implementation in `SeshatAppKit/Permissions/`.
- `SeshatAudio` may check authorization state internally if needed, but it must not show prompts or own the user-consent flow.
- `SeshatLogger.subsystem` is the only root subsystem constant for Week 1.
- `SeshatConfig.testingBaseDirectoryOverride` is owned by test code only. Production code must neither read nor mutate it. Plans 02–04 tests that touch `SeshatConfig.modelsDirectory()` MUST set this override in `setUp()` and reset it in `tearDown()`.
- `AppComposition` wiring is owned by Plan 99 (Week 1 Integration). Plans 01–04 must not create the `Sources/SeshatAppKit/Composition/AppComposition.swift` file; only Plan 99 does.

### D.7 Forbidden duplicates

- Do not define a second `PCMBuffer`.
- Do not define a second `SessionState`.
- Do not define a second public `SeshatError`.
- Do not define a second composition root.
- Do not define a second session manager or observer wrapper around `SessionCoordinator`.
- Do not define a second model-download progress DTO.
- Do not define a second microphone-permission protocol.
- Do not define ad hoc test fakes that overlap `FakeAudioCapturing` or `FakeTranscriber`.

## E. Tasks

**Execution rule**: all Plan 00 work starts only after Plan 01 Step 1 has created `git`, `Package.swift`, and the top-level SPM scaffold.

### Step 1. Scaffold `SeshatCore` one file at a time

Step 1 must stay granular enough for clean parallel scaffolding. Each substep is one file, one trivial compile test, one commit.

**Substep ordering**: 1.4 (`SeshatError`) and 1.5 (`SeshatConfig`) MUST land before 1.1 (`PCMBuffer`), 1.2 (`SessionState`), and 1.3 (`TranscriptionResult`). Those later scaffolds reference `SeshatError` (throw declarations) and `SeshatConfig.sampleRate` / `SeshatConfig.channelCount` (default parameter values). 1.6 and 1.7 are independent and may run anywhere in the sequence.

| Substep | File | Depends on | Failing test | Pass command | Commit |
|---|---|---|---|---|---|
| 1.4 | `Sources/SeshatCore/Errors.swift` | — | `SeshatErrorScaffoldingTests/testSeshatErrorSymbolCompiles` | `swift test --filter SeshatErrorScaffoldingTests/testSeshatErrorSymbolCompiles` | `git commit -m "plan-00 step 1.4: scaffold pserror"` |
| 1.5 | `Sources/SeshatCore/Config.swift` | — | `SeshatConfigScaffoldingTests/testSeshatConfigSymbolCompiles` | `swift test --filter SeshatConfigScaffoldingTests/testSeshatConfigSymbolCompiles` | `git commit -m "plan-00 step 1.5: scaffold psconfig"` |
| 1.6 | `Sources/SeshatCore/Logger.swift` | — | `SeshatLoggerScaffoldingTests/testSeshatLoggerSymbolCompiles` | `swift test --filter SeshatLoggerScaffoldingTests/testSeshatLoggerSymbolCompiles` | `git commit -m "plan-00 step 1.6: scaffold pslogger"` |
| 1.1 | `Sources/SeshatCore/PCMBuffer.swift` | 1.4, 1.5 | `PCMBufferScaffoldingTests/testPCMBufferSymbolCompiles` | `swift test --filter PCMBufferScaffoldingTests/testPCMBufferSymbolCompiles` | `git commit -m "plan-00 step 1.1: scaffold pcmbuffer"` |
| 1.2 | `Sources/SeshatCore/SessionState.swift` | 1.4 | `SessionStateScaffoldingTests/testSessionStateSymbolCompiles` | `swift test --filter SessionStateScaffoldingTests/testSessionStateSymbolCompiles` | `git commit -m "plan-00 step 1.2: scaffold sessionstate"` |
| 1.3 | `Sources/SeshatCore/TranscriptionResult.swift` | — | `TranscriptionResultScaffoldingTests/testTranscriptionResultSymbolCompiles` | `swift test --filter TranscriptionResultScaffoldingTests/testTranscriptionResultSymbolCompiles` | `git commit -m "plan-00 step 1.3: scaffold transcriptionresult"` |
| 1.7 | `Sources/SeshatCore/Protocols.swift` | 1.1, 1.3, 1.4 | `ProtocolScaffoldingTests/testProtocolSymbolsCompile` | `swift test --filter ProtocolScaffoldingTests/testProtocolSymbolsCompile` | `git commit -m "plan-00 step 1.7: scaffold shared protocols"` |

Shared scaffold rule:

- Each scaffold file contains only the declaration shape from Section C.
- No behavior is implemented during Step 1 beyond what is required to compile.
- Step 1.3 (`TranscriptionResult`) does not reference `SeshatError` or `SeshatConfig`, so it has no cross-substep dependency and may run anywhere.

### Step 2. Implement `PCMBuffer`

- File: `Sources/SeshatCore/PCMBuffer.swift`
- Failing test: `PCMBufferTests/testDurationAndValidation`
- Assertions: valid mono buffer reports `frameCount == 16_000`, `duration == .seconds(1)`, invalid metadata throws `SeshatError.resampleFailure`, and the caller must pass an explicit timestamp.
- Implementation: validate `sampleRate > 0`, `channelCount > 0`, and `samples.count.isMultiple(of: channelCount)`; compute duration from `frameCount / sampleRate`.
- Run: `swift test --filter PCMBufferTests/testDurationAndValidation`
- Commit: `git commit -m "plan-00 step 2: implement pcmbuffer"`

### Step 3. Implement `SessionState`

- File: `Sources/SeshatCore/SessionState.swift`
- Failing test: `SessionStateTests/testErrorEqualityUsesMappedSeshatErrorOnly`
- Assertions: `.error(.audioEngineFailure) == .error(.audioEngineFailure)` and does not equal `.error(.transcriptionFailure)`.
- Implementation: payload-free `SeshatError` makes synthesized `Equatable` sufficient.
- Run: `swift test --filter SessionStateTests/testErrorEqualityUsesMappedSeshatErrorOnly`
- Commit: `git commit -m "plan-00 step 3: implement sessionstate"`

### Step 4. Implement `SeshatError`

- File: `Sources/SeshatCore/Errors.swift`
- Failing test: `SeshatErrorTests/testLocalizedDescriptions`
- Assertions: stable `LocalizedError` strings for `micPermissionDenied`, `transcriptionFailure`, and `invalidState`.
- Implementation: keep the public enum payload-free, `Sendable`, and `Equatable`; log underlying concrete errors at call sites before mapping.
- Run: `swift test --filter SeshatErrorTests/testLocalizedDescriptions`
- Commit: `git commit -m "plan-00 step 4: implement pserror"`

### Step 5. Implement `SeshatConfig`

- File: `Sources/SeshatCore/Config.swift`
- Failing test: `SeshatConfigTests/testModelsDirectoryNestsUnderAppSupport`
- Assertions: `modelsDirectory()` nests under `appSupportDirectory()` and both compare with `standardizedFileURL`.
- Implementation: create missing directories on first call, return standardized URLs, and keep concurrent first access safe and idempotent.
- Run: `swift test --filter SeshatConfigTests/testModelsDirectoryNestsUnderAppSupport`
- Commit: `git commit -m "plan-00 step 5: implement psconfig"`

### Step 6. Implement `SeshatLogger`

- File: `Sources/SeshatCore/Logger.swift`
- Failing test: `SeshatLoggerTests/testLoggerFacadeCompilesAndUsesSharedSubsystem`
- Assertions: `SeshatLogger.subsystem == "com.nitkrar.seshat"` and `SeshatLogCategory.audio == "audio"`.
- Implementation: wrap `os.Logger`; never expose ad hoc subsystem strings.
- Run: `swift test --filter SeshatLoggerTests/testLoggerFacadeCompilesAndUsesSharedSubsystem`
- Commit: `git commit -m "plan-00 step 6: implement pslogger"`

### Step 7. Declare protocols and shared progress types

- File: `Sources/SeshatCore/Protocols.swift`
- Failing test: `ProtocolContractTests/testSharedProtocolsAcceptTrivialConformers`
- Purpose: catch signature drift with compile-time witness conformers for `AudioCapturing`, `Transcribing`, and `MicrophonePermissionRequesting`.

```swift
import XCTest
@testable import SeshatCore

private struct StubPermissionRequester: MicrophonePermissionRequesting {
    func requestAccess() async -> Bool { true }
}

private actor StubAudioCapturing: AudioCapturing {
    func start() async throws -> AsyncThrowingStream<PCMBuffer, Error> {
        AsyncThrowingStream { continuation in
            continuation.finish()
        }
    }

    func stop() async {}
}

private actor StubTranscribing: Transcribing {
    func prepare() async throws {}

    func modelDownloadProgress() -> AsyncStream<ModelDownloadProgress> {
        AsyncStream { continuation in
            continuation.yield(.init(phase: .idle, fractionCompleted: 0, receivedBytes: 0, expectedBytes: nil))
            continuation.finish()
        }
    }

    func transcribe(_ audio: PCMBuffer) async throws -> TranscriptionResult {
        TranscriptionResult(text: "", audioDuration: .zero, processingDuration: .zero)
    }

    func transcribe(stream: AsyncThrowingStream<PCMBuffer, Error>) async throws -> TranscriptionResult {
        TranscriptionResult(text: "", audioDuration: .zero, processingDuration: .zero)
    }
}

final class ProtocolContractTests: XCTestCase {
    func testSharedProtocolsAcceptTrivialConformers() async throws {
        let permission = StubPermissionRequester()
        let capture = StubAudioCapturing()
        let transcriber = StubTranscribing()

        XCTAssertTrue(await permission.requestAccess())
        _ = try await capture.start()
        try await transcriber.prepare()
        _ = transcriber.modelDownloadProgress()
    }
}
```

- Run: `swift test --filter ProtocolContractTests/testSharedProtocolsAcceptTrivialConformers`
- Implementation: declare the protocols exactly as specified in Section C.2.
- Commit: `git commit -m "plan-00 step 7: declare shared protocols"`

### Step 8. Add `SeshatTestSupport`

- Files: `Sources/SeshatTestSupport/FakeAudioCapturing.swift`, `Sources/SeshatTestSupport/FakeTranscriber.swift`
- Failing test: `FakeSupportTests/testFakeTranscriberReturnsPresetResult`
- Assertions: fake transcriber returns the preset `TranscriptionResult`; fake capture honors single-live-stream semantics and throws only `SeshatError` dynamically.
- Implementation details:
- `FakeAudioCapturing` tracks live-stream state and throws `SeshatError.audioEngineFailure` on a second `start()`.
- `stop()` is idempotent and finishes once.
- `FakeTranscriber.modelDownloadProgress()` may emit `.idle` then finish for Week 1 tests.
- Run: `swift test --filter FakeSupportTests/testFakeTranscriberReturnsPresetResult`
- Commit: `git commit -m "plan-00 step 8: add shared test fakes"`

### Step 9. Add `SessionCoordinator` in three slices

#### Step 9.1 State storage and observation

- File: `Sources/SeshatSession/SessionCoordinator.swift`
- Failing test: `SessionCoordinatorStateTests/testStateStreamDeliversInitialStateImmediately`
- Assertions: a fresh subscriber gets `.idle` immediately; `lastResult()` starts as `nil`.
- Implementation: store current state, store continuations, and yield current state immediately when a new stream is created.
- Run: `swift test --filter SessionCoordinatorStateTests/testStateStreamDeliversInitialStateImmediately`
- Commit: `git commit -m "plan-00 step 9.1: add session state storage"`

#### Step 9.2 Happy-path toggle

- File: `Sources/SeshatSession/SessionCoordinator.swift`
- Failing test: `SessionCoordinatorHappyPathTests/testToggleWalksIdleRecordingTranscribingIdle`
- Purpose: fix the invalid eager async-array pattern from v1 and make the replay-stream model explicit.

```swift
import XCTest
import SeshatCore
import SeshatTestSupport
@testable import SeshatSession

final class SessionCoordinatorHappyPathTests: XCTestCase {
    func testToggleWalksIdleRecordingTranscribingIdle() async throws {
        let buffer = try PCMBuffer(
            samples: Array(repeating: 0, count: 16_000),
            timestamp: ContinuousClock().now
        )
        let capture = FakeAudioCapturing(buffers: [buffer])
        let transcriber = FakeTranscriber(
            result: .init(
                text: "hello",
                audioDuration: .seconds(1),
                processingDuration: .seconds(0.2)
            )
        )
        let coordinator = SessionCoordinator(
            capture: capture,
            transcriber: transcriber,
            logger: SeshatLogger(category: SeshatLogCategory.session)
        )

        let stream = await coordinator.stateStream()
        let toggleTask = Task {
            await coordinator.toggle()
            await coordinator.toggle()
        }

        var observed: [SessionState] = []
        for await state in stream.prefix(4) {
            observed.append(state)
        }

        await toggleTask.value

        XCTAssertEqual(observed, [.idle, .recording, .transcribing, .idle])
        XCTAssertEqual(await coordinator.lastResult()?.text, "hello")
    }
}
```

- Implementation:
- `.idle` -> start capture and buffer `PCMBuffer` values.
- `.recording` -> `capture.stop()`, seal the buffer array, create a finite replay `AsyncThrowingStream`, call `transcribe(stream:)`, store `lastResult`, then return to `.idle`.
- Run: `swift test --filter SessionCoordinatorHappyPathTests/testToggleWalksIdleRecordingTranscribingIdle`
- Commit: `git commit -m "plan-00 step 9.2: add session toggle happy path"`

#### Step 9.3 Error recovery and ignored toggles

- File: `Sources/SeshatSession/SessionCoordinator.swift`
- Failing tests: `SessionCoordinatorErrorTests`
- Assertions:
- capture failure maps to `.error(.audioEngineFailure)`
- next toggle from `.error` clears and retries
- repeated toggle during `.transcribing` is ignored
- replay stream finishes exactly once
- `lastResult()` is not corrupted by ignored toggles
- Implementation: map every failure path to `SeshatError`, log ignored toggles, and keep replay-stream completion single-shot.
- Run: `swift test --filter SessionCoordinatorErrorTests`
- Commit: `git commit -m "plan-00 step 9.3: add session error handling"`

### Step 10. (Deferred to Plan 99 — Week 1 Integration)

`AppComposition` implementation is NOT part of Plan 00. Plan 00 defines only the API surface (Section C.6) and the ownership rules (Section D.6). The implementation requires production `AVAudioCaptureService` (Plan 02) and `FluidAudioTranscriber` (Plan 03), neither of which exists until those plans ship. Plans 01–04 MUST NOT create `Sources/SeshatAppKit/Composition/AppComposition.swift`.

**Plan 99 preview** (for reviewer context; authoritative spec lives in the Plan 99 document when written):

- File: `Sources/SeshatAppKit/Composition/AppComposition.swift`
- Depends on: Plans 00, 02, 03 (and Plan 04 for `AppKitMicrophonePermissionRequester`).
- Failing test: `AppCompositionTests/testMakeSessionCoordinatorReturnsSharedIdleActor`.
  ```swift
  import XCTest
  import SeshatCore
  @testable import SeshatAppKit

  @MainActor
  final class AppCompositionTests: XCTestCase {
      func testMakeSessionCoordinatorReturnsSharedIdleActor() async {
          let first = AppComposition.makeSessionCoordinator()
          let second = AppComposition.makeSessionCoordinator()
          XCTAssertTrue(first === second)
          XCTAssertEqual(await first.state(), .idle)
      }
  }
  ```
- Implementation (to be written in Plan 99):
  - `AppComposition.sessionCoordinator` initialized once with production `AVAudioCaptureService`, production `FluidAudioTranscriber`, and `SeshatLogger(category: SeshatLogCategory.session)`.
  - `makeSessionCoordinator()` returns the shared static actor.
  - `makeMicrophonePermissionRequester()` returns the `SeshatAppKit` production requester from `SeshatAppKit/Permissions/`.
- Commit (Plan 99): `git commit -m "plan-99 step 1: wire app composition root"`.

## F. Dependency table (corrected)

| Group | Steps | Can Parallelize | Notes |
|---|---|---|---|
| 1a | 1.4, 1.5, 1.6 | Yes | `SeshatError`, `SeshatConfig`, `SeshatLogger` scaffolds — no cross-dependencies. |
| 1b | 1.1, 1.2, 1.3, 1.7 | Yes, after 1a | 1.1 needs 1.4 + 1.5; 1.2 needs 1.4; 1.3 has no deps; 1.7 needs 1.1, 1.3, 1.4. |
| 2 | 4, 5, 6 | Yes | `SeshatError`, `SeshatConfig`, `SeshatLogger` implementations are independent once scaffolds exist. |
| 3 | 2, 3 | Yes | Step 2 (`PCMBuffer`) and Step 3 (`SessionState`) both depend on Step 4 (`SeshatError`). They do not need Step 5 or Step 6 to finish. |
| 4 | 7 | No | Protocols depend on the finalized core types and shared progress/error contracts. |
| 5 | 8 | No | Fakes depend on the protocol contracts from Step 7. |
| 6 | 9.1 | No | Coordinator storage and observation depend on core types and fakes. |
| 7 | 9.2 | No | Happy-path toggle depends on 9.1 state storage and Step 8 fakes. |
| 8 | 9.3 | No | Error handling and replay semantics build on 9.2. |

Step 10 is deferred to Plan 99 and is not part of Plan 00's execution graph.

Worker guidance:

- One worker can implement Steps 4, 5, and 6 in parallel.
- A second worker can prepare Step 2 after Step 4 lands.
- A third worker can prepare Step 3 after Step 4 lands.
- Coordinator work (9.1–9.3) is serial and owned by one worker.
- `AppComposition` wiring waits for Plan 99, which runs after Plans 02 and 03.

## G. Handoff Contract

- Plan 01 may consume the target names, executable/library split, directory layout, and test-target list. It must not rename targets or move `AppComposition` out of the app executable target.
- Plan 02 implements `AudioCapturing` only. It must not redefine `PCMBuffer`, `SeshatError`, `SeshatLogger`, `SeshatConfig`, or the mic-permission protocol. Its tests MUST use `SeshatConfig.testingBaseDirectoryOverride` when touching model/app-support paths.
- Plan 03 implements `Transcribing` only. It must not redefine `TranscriptionResult`, `ModelDownloadProgress`, `SeshatError`, or `SessionCoordinator`. Its tests MUST use `SeshatConfig.testingBaseDirectoryOverride` when touching model/app-support paths.
- Plan 04 defines `AppKitMicrophonePermissionRequester` in `SeshatAppKit/Permissions/` and the menu bar UI that observes `SessionCoordinator.stateStream()`. It must not create `AppComposition.swift` — that file is Plan 99's responsibility. Plan 04 must not create its own state enum, session manager, observer protocol, or second composition site.
- Plan 99 (Week 1 Integration) wires `AppComposition` with the production types shipped by Plans 02, 03, and 04. It runs LAST in Week 1.
- `SeshatAppKit` may import `SeshatAudio` and `SeshatTranscription` only inside `Sources/SeshatAppKit/Composition/` (i.e. only from the Plan 99 file).
- The production mic prompt lives in `SeshatAppKit/Permissions/`, not in `SeshatAudio`.

Downstream consumable symbols:

- Plan 01: `SeshatCore`, `SeshatAudio`, `SeshatTranscription`, `SeshatSession`, `SeshatAppKit`, `SeshatTestSupport`, `SeshatCoreTests`, `SeshatAudioTests`, `SeshatTranscriptionTests`, `SeshatSessionTests`, `SeshatAppKitTests`
- Plan 02: `PCMBuffer`, `SeshatError`, `SeshatLogger`, `SeshatLogCategory`, `SeshatConfig`, `AudioCapturing`
- Plan 03: `Transcribing`, `TranscriptionResult`, `ModelDownloadProgress`, `SeshatError`, `SeshatLogger`, `SeshatConfig`
- Plan 04: `SessionCoordinator`, `SessionState`, `TranscriptionResult`, `MicrophonePermissionRequesting`, `SeshatLogger`
- Plan 99: all of the above plus production `AVAudioCaptureService` (Plan 02), `FluidAudioTranscriber` (Plan 03), and `AppKitMicrophonePermissionRequester` (Plan 04).

## H. Open Questions (carry-over + new)

1. Plan 03 still must verify the exact FluidAudio API and pin a concrete dependency version in `Package.swift`.
2. The app-level UX for showing `modelDownloadProgress()` in Week 3 is still open; the shared DTO is fixed here, but not the UI surface.
3. The exact retry/backoff policy for model-download failures remains open; this plan only fixes the ownership and progress contract.
4. `SeshatError.invalidState` is included for shared safety, but Week 1 may end up never surfacing it to end users if all invalid transitions remain internal and logged.
5. The mic-permission requester contract is fixed, but the exact bootstrap timing in Plan 04 remains open: immediate request on launch versus request on first record attempt.

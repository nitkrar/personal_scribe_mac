# Plan 03: FluidAudio / Parakeet Transcription

**Goal**: Ship production `Transcribing` conformer (`FluidAudioTranscriber`) in `PSTranscription`, including model download + progress + full-utterance transcription. Record → console-log works end-to-end after Plan 02 + Plan 03 + Plan 00 Step 9.
**Architecture**: actor-wrapped FluidAudio client; URLSession-based model download with `ModelDownloadProgress` async stream; buffered full-utterance transcription via `transcribe(stream:)`.
**Tech Stack**: FluidAudio (SPM), CoreML, URLSession, Swift Concurrency, XCTest.
**Depends on**: Plan 00 Section C.1, C.2, C.4, C.5, D.6 (contract); Plan 01 (scaffold + FluidAudio pin).
**Plan 00 contract read**: Section C.1 (TranscriptionResult, ModelDownloadProgress), C.2 (Transcribing), D.6 (model download ownership), G (Plan 03 symbols).

## A. FluidAudio API verification step

### Step 1 findings to record before coding

The Plan 03 executor must re-run this verification against the live upstream tag immediately before implementation. The findings below were verified from the public `FluidAudio` repo at tag `v0.13.6`.

| Item | Verified finding | Plan 03 consequence |
|---|---|---|
| Swift Package URL | `https://github.com/FluidInference/FluidAudio.git` | Use this exact URL in `Package.swift`. |
| Package pin | `exact: "0.13.6"` | Pin exact, not `from:` and not `main`. |
| Product name | `.product(name: "FluidAudio", package: "FluidAudio")` | Only `PSTranscription` depends on the package product. |
| Package floor | `macOS(.v14)`, `iOS(.v17)` | Week 1 currently implies macOS 14 unless a different tag is chosen. |
| English model enum | `AsrModelVersion.v2` | Use `.v2` for Week 1. |
| Model loader | `AsrModels.load(from:version: .v2)` and `AsrModels.downloadAndLoad(version: .v2)` | Use `load(from:)`, not `downloadAndLoad`, so PersonalScribe owns storage and progress. |
| Manager type | `AsrManager(config: .default)` | One actor-owned manager instance is sufficient. |
| Float32 inference | `try await asrManager.transcribe(samples, source: .microphone)` | `PCMBuffer.samples` can be passed directly. |
| Result type | `ASRResult` with `text`, `duration`, `processingTime`, optional `tokenTimings` | Map text and durations directly; Week 1 can keep `segments` empty. |
| SDK download behavior | Upstream downloads from Hugging Face by default using `URLSession` and `ModelRegistry` | Bypass it. Plan 00 assigns download ownership to the transcription layer. |
| Required staged assets | `Preprocessor.mlmodelc`, `Encoder.mlmodelc`, `Decoder.mlmodelc`, `JointDecision.mlmodelc`, `parakeet_vocab.json` | The downloader must stage exactly these under the app-owned model directory. |
| Upstream v2 repo slug | `FluidInference/parakeet-tdt-0.6b-v2-coreml` | Use Hugging Face API + resolve endpoints. |
| Upstream local folder name | `parakeet-tdt-0.6b-v2` | This matches `PSConfig.modelId`; no suffix rewrite is needed on this tag. |

### Step 1 conclusions

1. `FluidAudio` already supports auto-download, but using it would violate Plan 00 Section D.6 because the shared download lifecycle would live in the SDK instead of `PSTranscription`.
2. Plan 03 therefore owns download, validation, staging, atomic move, and progress streaming.
3. After download, Plan 03 uses the SDK only for model loading and inference.
4. Upstream exposes token timings, not a stable word-segment API matching `TranscriptionResult.Segment`.
5. Plan 00 explicitly allows `TranscriptionResult.segments` to be empty in Week 1, so that is the conservative mapping.

### Step 1 executor checklist

Re-run this immediately before coding:

1. Open upstream `Package.swift`; confirm URL, product, platforms, and the tag to pin.
2. Open upstream `README.md`; confirm `AsrManager` and `AsrModels` usage is unchanged.
3. Open upstream `Documentation/ASR/ManualModelLoading.md`; confirm the required staged asset names are unchanged.
4. Confirm `.v2` is still the English-only model.
5. Confirm `AsrManager` still exposes the `[Float]` transcription overload.
6. Confirm `AsrModels.load(from:version:)` still accepts a staged repo directory.
7. Confirm the local folder name for `Repo.parakeetV2` is still `parakeet-tdt-0.6b-v2`.
8. If any item drifts, stop and update this plan before implementation starts.

### Shared contract anchor

Plan 03 implements this exact protocol from `PSCore` and must not redefine it:

```swift
import Foundation

public protocol Transcribing: Sendable {
    func prepare() async throws
    func modelDownloadProgress() -> AsyncStream<ModelDownloadProgress>
    func transcribe(_ audio: PCMBuffer) async throws -> TranscriptionResult
    func transcribe(stream: AsyncThrowingStream<PCMBuffer, Error>) async throws -> TranscriptionResult
}
```

### Planned public production type

```swift
import Foundation
import PSCore

public actor FluidAudioTranscriber: Transcribing {
    public init()
    public func prepare() async throws
    public func modelDownloadProgress() -> AsyncStream<ModelDownloadProgress>
    public func transcribe(_ audio: PCMBuffer) async throws -> TranscriptionResult
    public func transcribe(stream: AsyncThrowingStream<PCMBuffer, Error>) async throws -> TranscriptionResult
}
```

### Internal seams for TDD only

These stay `internal` to `PSTranscription`.

```swift
import Foundation
import PSCore

protocol ModelDownloading: Sendable {
    func ensureModelAvailable(
        at directory: URL,
        progress: @escaping @Sendable (ModelDownloadProgress) -> Void
    ) async throws -> URL
}

protocol FluidAudioInferencing: Sendable {
    func loadModel(from directory: URL) async throws
    func transcribe(samples: [Float]) async throws -> FluidAudioInferenceResult
}

struct FluidAudioInferenceResult: Sendable, Equatable {
    let text: String
    let processingDuration: Duration
}
```

### Week 1 storage, download, and integrity decisions

Model root:

```text
PSConfig.modelsDirectory()/parakeet-tdt-0.6b-v2/
```

Expected contents:

```text
parakeet-tdt-0.6b-v2/
├── Preprocessor.mlmodelc/
├── Encoder.mlmodelc/
├── Decoder.mlmodelc/
├── JointDecision.mlmodelc/
└── parakeet_vocab.json
```

Download strategy:

1. Use Hugging Face listing endpoint:
   `https://huggingface.co/api/models/FluidInference/parakeet-tdt-0.6b-v2-coreml/tree/main`
2. Download required files from:
   `https://huggingface.co/FluidInference/parakeet-tdt-0.6b-v2-coreml/resolve/main/<path>`
3. Use `URLSessionDownloadTask` for file transfers.
4. Download into a staging directory under `PSConfig.modelsDirectory()`.
5. Validate the staged structure.
6. Atomically move the completed directory into final location.

Week 1 integrity policy:

1. Required top-level entries must exist.
2. Every required file must be non-zero size.
3. `parakeet_vocab.json` must start with `{` or `[` after leading whitespace.
4. Each `.mlmodelc` directory must contain `coremldata.bin`.
5. Corruption triggers one cleanup-and-retry cycle.
6. Second failure throws `PSError.modelDownloadFailure`.

## B. Task breakdown

### Step 1. Verify FluidAudio API and pin version in `Package.swift`

**Goal**: lock the dependency before any production code lands.

Files: `Package.swift`

**Work**

1. Add the exact package pin.
2. Add `.product(name: "FluidAudio", package: "FluidAudio")` to `PSTranscription` only.
3. Resolve and build.

**Package snippet**

```swift
// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "PersonalScribe",
    platforms: [
        .macOS(.v14),
    ],
    dependencies: [
        .package(
            url: "https://github.com/FluidInference/FluidAudio.git",
            exact: "0.13.6"
        ),
    ],
    targets: [
        .target(
            name: "PSTranscription",
            dependencies: [
                "PSCore",
                .product(name: "FluidAudio", package: "FluidAudio"),
            ]
        ),
    ]
)
```

Run: `swift package resolve` and `swift build`. Commit: `git commit -m "plan-03 step 1: pin fluidaudio dependency"`.

---

### Step 2. Scaffold `FluidAudioTranscriber` and compile

**Goal**: create the production type with the exact shared surface and nothing extra.

Files: `Sources/PSTranscription/FluidAudioTranscriber.swift`, `Tests/PSTranscriptionTests/FluidAudioTranscriberCompileTests.swift`

**Red**

Add a compile witness that requires `FluidAudioTranscriber` to satisfy `Transcribing`.

**Green**

Add the actor, public init, and placeholder method bodies.

**Compile witness test**

```swift
import XCTest
import PSCore
@testable import PSTranscription

final class FluidAudioTranscriberCompileTests: XCTestCase {
    func testFluidAudioTranscriberConformsToTranscribing() {
        let transcriber: any Transcribing = FluidAudioTranscriber()
        XCTAssertNotNil(transcriber)
    }
}
```

Run: `swift test --filter FluidAudioTranscriberCompileTests`. Commit: `git commit -m "plan-03 step 2: scaffold fluidaudio transcriber"`.

---

### Step 3. Add model path helpers and test fixture setup

**Goal**: make model storage deterministic and hermetic in tests.

Files: `Sources/PSTranscription/FluidAudioTranscriber.swift`, `Tests/PSTranscriptionTests/Support/PSTranscriptionFilesystemTestCase.swift`, `Tests/PSTranscriptionTests/ModelPathTests.swift`

**Helpers**

1. `modelRootDirectory(base:)`
2. `stagingDirectory(base:)`
3. `modelsExist(in:)`
4. `requiredModelPaths(in:)`

**Fixture**

Every test touching `PSConfig.modelsDirectory()` must set `PSConfig.testingBaseDirectoryOverride` in `setUp()` and reset it in `tearDown()`.

**Fixture snippet**

```swift
import XCTest
import PSCore

class PSTranscriptionFilesystemTestCase: XCTestCase {
    var testRoot: URL!

    override func setUp() async throws {
        try await super.setUp()
        testRoot = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: testRoot, withIntermediateDirectories: true)
        PSConfig.testingBaseDirectoryOverride = testRoot
    }

    override func tearDown() async throws {
        PSConfig.testingBaseDirectoryOverride = nil
        try? FileManager.default.removeItem(at: testRoot)
        try await super.tearDown()
    }
}
```

**Path test**

```swift
import XCTest
import PSCore
@testable import PSTranscription

final class ModelPathTests: PSTranscriptionFilesystemTestCase {
    func testModelRootLivesUnderTestingOverride() throws {
        let modelsDirectory = try PSConfig.modelsDirectory()
        let modelRoot = FluidAudioTranscriber.modelRootDirectory(base: modelsDirectory)

        XCTAssertTrue(modelRoot.path.hasPrefix(modelsDirectory.path))
        XCTAssertEqual(modelRoot.lastPathComponent, PSConfig.modelId)
    }
}
```

Run: `swift test --filter ModelPathTests`. Commit: `git commit -m "plan-03 step 3: add model path helpers"`.

---

### Step 4. Implement the download progress state machine

**Goal**: own the shared progress lifecycle: `idle → downloading → finished`.

Files: `Sources/PSTranscription/URLSessionModelDownloader.swift`, `Sources/PSTranscription/FluidAudioTranscriber.swift`, `Tests/PSTranscriptionTests/ModelDownloadProgressTests.swift`

**Design**

1. `FluidAudioTranscriber` owns the current progress snapshot.
2. `modelDownloadProgress()` yields the current snapshot immediately on subscription.
3. `prepare()` publishes `.downloading` snapshots during a live transfer.
4. Successful completion publishes `.finished`.
5. No other public API exposes download state.

**Progress test**

```swift
import XCTest
import PSCore
@testable import PSTranscription

final class ModelDownloadProgressTests: PSTranscriptionFilesystemTestCase {
    func testPrepareEmitsIdleDownloadingFinished() async throws {
        let downloader = StubModelDownloader(
            scriptedProgress: [
                .init(phase: .downloading, fractionCompleted: 0.25, receivedBytes: 25, expectedBytes: 100),
                .init(phase: .downloading, fractionCompleted: 1.00, receivedBytes: 100, expectedBytes: 100),
            ]
        )
        let transcriber = FluidAudioTranscriber(
            downloader: downloader,
            inference: StubInferenceClient()
        )

        let task = Task { await collect(stream: transcriber.modelDownloadProgress(), limit: 4) }
        try await transcriber.prepare()
        let snapshots = await task.value

        XCTAssertEqual(snapshots.first?.phase, .idle)
        XCTAssertTrue(snapshots.contains(where: { $0.phase == .downloading }))
        XCTAssertEqual(snapshots.last?.phase, .finished)
    }

    private func collect(
        stream: AsyncStream<ModelDownloadProgress>,
        limit: Int
    ) async -> [ModelDownloadProgress] {
        var result: [ModelDownloadProgress] = []
        for await value in stream {
            result.append(value)
            if result.count == limit { break }
        }
        return result
    }
}
```

Run: `swift test --filter ModelDownloadProgressTests`. Commit: `git commit -m "plan-03 step 4: add model download progress state machine"`.

---

### Step 5. Map download failures to `PSError.modelDownloadFailure`

**Goal**: preserve the shared error surface and log before mapping.

Files: `Sources/PSTranscription/URLSessionModelDownloader.swift`, `Sources/PSTranscription/FluidAudioTranscriber.swift`, `Tests/PSTranscriptionTests/ModelDownloadFailureTests.swift`

**Behavior**

1. Any `URLSession`, file-system, listing, or staging failure logs via `PSLogger(category: .transcription)`.
2. The public throw from `prepare()` is always `PSError.modelDownloadFailure`.

**Failure test**

```swift
import XCTest
import PSCore
@testable import PSTranscription

final class ModelDownloadFailureTests: PSTranscriptionFilesystemTestCase {
    func testPrepareMapsDownloadFailureToSharedError() async {
        let transcriber = FluidAudioTranscriber(
            downloader: StubModelDownloader(error: URLError(.notConnectedToInternet)),
            inference: StubInferenceClient()
        )

        do {
            try await transcriber.prepare()
            XCTFail("Expected prepare() to throw")
        } catch let error as PSError {
            XCTAssertEqual(error, .modelDownloadFailure)
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }
}
```

Run: `swift test --filter ModelDownloadFailureTests`. Commit: `git commit -m "plan-03 step 5: map model download failures"`.

---

### Step 6. Add integrity validation and corruption retry

**Goal**: reject broken downloads before `AsrModels.load`.

Files: `Sources/PSTranscription/ModelIntegrityValidator.swift`, `Sources/PSTranscription/URLSessionModelDownloader.swift`, `Tests/PSTranscriptionTests/ModelIntegrityTests.swift`

**Week 1 validation rules**

1. The five required top-level entries exist.
2. `parakeet_vocab.json` is non-empty and begins with `{` or `[`.
3. Each `.mlmodelc` directory contains `coremldata.bin`.
4. `coremldata.bin` is non-zero size.
5. Validation failure cleans staging and retries once.
6. The second failure maps to `PSError.modelDownloadFailure`.

**Integrity test**

```swift
import XCTest
import PSCore
@testable import PSTranscription

final class ModelIntegrityTests: PSTranscriptionFilesystemTestCase {
    func testCorruptDownloadRetriesOnceThenSucceeds() async throws {
        let downloader = RetryingStubModelDownloader(firstResult: .corrupt, secondResult: .valid)
        let transcriber = FluidAudioTranscriber(
            downloader: downloader,
            inference: StubInferenceClient()
        )

        try await transcriber.prepare()
        XCTAssertEqual(await downloader.attemptCount, 2)
    }

    func testCorruptDownloadTwiceThrowsModelDownloadFailure() async {
        let downloader = RetryingStubModelDownloader(firstResult: .corrupt, secondResult: .corrupt)
        let transcriber = FluidAudioTranscriber(
            downloader: downloader,
            inference: StubInferenceClient()
        )

        do {
            try await transcriber.prepare()
            XCTFail("Expected prepare() to throw")
        } catch let error as PSError {
            XCTAssertEqual(error, .modelDownloadFailure)
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }
}
```

Run: `swift test --filter ModelIntegrityTests`. Commit: `git commit -m "plan-03 step 6: add model integrity validation"`.

---

### Step 7. Make `prepare()` idempotent and coalesced

**Goal**: second and concurrent calls should not redownload or reload the model.

Files: `Sources/PSTranscription/FluidAudioTranscriber.swift`, `Tests/PSTranscriptionTests/PrepareIdempotenceTests.swift`

**Design**

1. Track `hasPreparedModel`.
2. Track one in-flight `prepareTask`.
3. First caller creates the task.
4. Later callers await the same task.
5. Success sets `hasPreparedModel = true`.
6. Failure clears `prepareTask`.

**Idempotence test**

```swift
import XCTest
import PSCore
@testable import PSTranscription

final class PrepareIdempotenceTests: PSTranscriptionFilesystemTestCase {
    func testPrepareIsNoOpAfterSuccessfulFirstLoad() async throws {
        let downloader = StubModelDownloader()
        let inference = StubInferenceClient()
        let transcriber = FluidAudioTranscriber(
            downloader: downloader,
            inference: inference
        )

        try await transcriber.prepare()
        try await transcriber.prepare()

        XCTAssertEqual(await downloader.ensureCallCount, 1)
        XCTAssertEqual(await inference.loadCallCount, 1)
    }
}
```

Run: `swift test --filter PrepareIdempotenceTests`. Commit: `git commit -m "plan-03 step 7: make prepare idempotent"`.

---

### Step 8. Implement `transcribe(_ audio:)`

**Goal**: perform one single-shot transcription from a `PCMBuffer`.

Files: `Sources/PSTranscription/FluidAudioInferenceClient.swift`, `Sources/PSTranscription/FluidAudioTranscriber.swift`, `Tests/PSTranscriptionTests/SingleBufferTranscriptionTests.swift`

**Production call path**

```swift
import FluidAudio

let models = try await AsrModels.load(from: modelDirectory, version: .v2)
let manager = AsrManager(config: .default)
try await manager.loadModels(models)
let result = try await manager.transcribe(samples, source: .microphone)
```

**Week 1 mapping**

1. `text` ← `ASRResult.text`
2. `segments` ← `[]`
3. `audioDuration` ← `PCMBuffer.duration`
4. `processingDuration` ← upstream `processingTime`

**Transcription test**

```swift
import XCTest
import PSCore
@testable import PSTranscription

final class SingleBufferTranscriptionTests: XCTestCase {
    func testTranscribeMapsCannedInferenceResult() async throws {
        let audio = try PCMBuffer(
            samples: Array(repeating: 0.1, count: 16_000),
            timestamp: .now
        )
        let transcriber = FluidAudioTranscriber(
            downloader: StubModelDownloader(),
            inference: StubInferenceClient(
                result: FluidAudioInferenceResult(
                    text: "hello world",
                    processingDuration: .milliseconds(120)
                )
            )
        )

        let result = try await transcriber.transcribe(audio)

        XCTAssertEqual(result.text, "hello world")
        XCTAssertEqual(result.segments, [])
        XCTAssertEqual(result.audioDuration, audio.duration)
        XCTAssertEqual(result.processingDuration, .milliseconds(120))
    }
}
```

Run: `swift test --filter SingleBufferTranscriptionTests`. Commit: `git commit -m "plan-03 step 8: add single-buffer transcription"`.

---

### Step 9. Implement `transcribe(stream:)` as buffered full-utterance replay

**Goal**: drain a finite stream and perform exactly one transcription call.

Files: `Sources/PSTranscription/FluidAudioTranscriber.swift`, `Tests/PSTranscriptionTests/StreamTranscriptionTests.swift`

**Rules**

1. Drain the entire finite replay stream.
2. Preserve order.
3. Concatenate samples into one `PCMBuffer`.
4. Timestamp comes from the first buffer.
5. Sample rate and channel count must match across all buffers.
6. Call `transcribe(_:)` exactly once.

**Stream test**

```swift
import XCTest
import PSCore
@testable import PSTranscription

final class StreamTranscriptionTests: XCTestCase {
    func testTranscribeStreamConcatenatesThenRunsSingleInference() async throws {
        let first = try PCMBuffer(
            samples: Array(repeating: 0.1, count: 8_000),
            timestamp: .now
        )
        let second = try PCMBuffer(
            samples: Array(repeating: 0.2, count: 8_000),
            timestamp: .now
        )
        let stream = AsyncThrowingStream<PCMBuffer, Error> { continuation in
            continuation.yield(first)
            continuation.yield(second)
            continuation.finish()
        }

        let inference = StubInferenceClient(
            result: FluidAudioInferenceResult(
                text: "hello world",
                processingDuration: .milliseconds(80)
            )
        )
        let transcriber = FluidAudioTranscriber(
            downloader: StubModelDownloader(),
            inference: inference
        )

        let result = try await transcriber.transcribe(stream: stream)

        XCTAssertEqual(result.text, "hello world")
        XCTAssertEqual(await inference.transcribeCallCount, 1)
        XCTAssertEqual(await inference.lastReceivedSampleCount, 16_000)
    }
}
```

Run: `swift test --filter StreamTranscriptionTests`. Commit: `git commit -m "plan-03 step 9: add buffered stream transcription"`.

---

### Step 10. Map stream failures to `PSError.transcriptionFailure`

**Goal**: preserve Plan 00’s dynamic error rule for the replay-stream path.

Files: `Sources/PSTranscription/FluidAudioTranscriber.swift`, `Tests/PSTranscriptionTests/StreamErrorMappingTests.swift`

**Behavior**

1. Catch any error thrown while draining the stream.
2. Log the underlying error.
3. Throw `PSError.transcriptionFailure`.

**Error test**

```swift
import XCTest
import PSCore
@testable import PSTranscription

final class StreamErrorMappingTests: XCTestCase {
    func testStreamFailureMapsToSharedTranscriptionFailure() async {
        enum StubError: Error { case boom }

        let stream = AsyncThrowingStream<PCMBuffer, Error> { continuation in
            continuation.finish(throwing: StubError.boom)
        }
        let transcriber = FluidAudioTranscriber(
            downloader: StubModelDownloader(),
            inference: StubInferenceClient()
        )

        do {
            _ = try await transcriber.transcribe(stream: stream)
            XCTFail("Expected transcribe(stream:) to throw")
        } catch let error as PSError {
            XCTAssertEqual(error, .transcriptionFailure)
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }
}
```

Run: `swift test --filter StreamErrorMappingTests`. Commit: `git commit -m "plan-03 step 10: map stream errors to shared error"`.

---

### Step 11. Add logging coverage for all failure paths

**Goal**: every public failure path logs before mapping.

Files: `Sources/PSTranscription/FluidAudioTranscriber.swift`, `Sources/PSTranscription/URLSessionModelDownloader.swift`, `Tests/PSTranscriptionTests/LoggingTests.swift`

**Paths to cover**

1. download failure
2. integrity failure
3. model load failure
4. inference failure
5. replay stream failure

**Testing approach**

Keep the production initializer public and small:

```swift
public init()
```

Add one internal initializer for tests that accepts:

1. stub downloader
2. stub inference client
3. shared logger
4. test log sink closure

**Logging test**

```swift
import XCTest
import PSCore
@testable import PSTranscription

final class LoggingTests: XCTestCase {
    func testInferenceFailureIsLoggedBeforeMapping() async {
        let recorder = LogRecorder()
        let transcriber = FluidAudioTranscriber(
            downloader: StubModelDownloader(),
            inference: StubInferenceClient(error: StubInferenceError.failed),
            logSink: { message in
                Task { await recorder.record(message) }
            }
        )
        let audio = try! PCMBuffer(
            samples: Array(repeating: 0.1, count: 16_000),
            timestamp: .now
        )

        do {
            _ = try await transcriber.transcribe(audio)
            XCTFail("Expected transcription to fail")
        } catch let error as PSError {
            XCTAssertEqual(error, .transcriptionFailure)
        } catch {
            XCTFail("Unexpected error: \(error)")
        }

        let messages = await recorder.messages
        XCTAssertEqual(messages.count, 1)
        XCTAssertTrue(messages[0].contains("failed"))
    }
}

actor LogRecorder {
    private(set) var messages: [String] = []
    func record(_ message: String) { messages.append(message) }
}
```

Run: `swift test --filter LoggingTests`. Commit: `git commit -m "plan-03 step 11: add transcription failure logging"`.

---

### Step 12. Add manual verification runbook

**Goal**: document the real end-to-end validation path without putting the first-run download in CI.

Files: `Tests/PSTranscriptionTests/ManualTranscriptionVerification.md`

**Runbook contents**

1. macOS 14+ / Apple Silicon prerequisite
2. delete any prior model under `~/Library/Application Support/PersonalScribe/models/parakeet-tdt-0.6b-v2`
3. run the manual verification entry point
4. observe progress `idle → downloading → finished`
5. transcribe a WAV of “hello world”
6. confirm the final text contains `hello world`
7. confirm the final model directory contains the five required assets
8. confirm there is no `print()` path and failures are logged

**Runbook skeleton**

```markdown
# Manual Transcription Verification

## Goal
Verify that `FluidAudioTranscriber` downloads the Parakeet v2 model on first run and transcribes a short WAV end-to-end.

## Preconditions
- Apple Silicon
- macOS 14+
- Working network connection
- `PSConfig.testingBaseDirectoryOverride == nil`

## Procedure
1. Remove any prior model under `~/Library/Application Support/PersonalScribe/models/parakeet-tdt-0.6b-v2`.
2. Trigger `prepare()`.
3. Confirm progress `idle → downloading → finished`.
4. Feed a 16 kHz mono WAV speaking "hello world".
5. Confirm `TranscriptionResult.text` contains `hello world`.
6. Confirm the model directory contains the expected assets.
```

Commit: `git commit -m "plan-03 step 12: add manual transcription verification runbook"`.

## C. Dependency table

### Ordered execution

| Step | Depends on | Why |
|---|---|---|
| 1 | Plan 01 scaffold | Dependency pin must land first. |
| 2 | 1 | The production type must exist before behavior tests can compile. |
| 3 | 2 | Downloader tests depend on path helpers and hermetic storage. |
| 4 | 3 | Progress is the base `prepare()` behavior. |
| 5 | 4 | Error mapping depends on downloader flow existing. |
| 6 | 5 | Integrity validation extends the downloader path. |
| 7 | 6 | Idempotence stabilizes all later calls. |
| 8 | 7 | Single-buffer inference depends on stable prepare/load. |
| 9 | 8 | Replay-stream path delegates to single-buffer path. |
| 10 | 9 | Stream failure mapping depends on replay collection existing. |
| 11 | 5, 8, 9, 10 | Logging assertions need real failure paths to exist. |
| 12 | 8, 9, 10, 11 | Runbook is most accurate after behavior is final. |

### Safe parallelization

| Parallel group | Steps | Notes |
|---|---|---|
| A | 1, 2, 3 | Scaffold and storage shape. |
| B | 4, 5, 6, 7 | Downloader and prepare semantics. |
| C | 8, 9, 10, 11 | Inference, replay stream, logging. |
| D | 12 | Manual docs only. |

### Minimum command cadence

```bash
swift test --filter FluidAudioTranscriberCompileTests
swift test --filter ModelPathTests
swift test --filter ModelDownloadProgressTests
swift test --filter ModelDownloadFailureTests
swift test --filter ModelIntegrityTests
swift test --filter PrepareIdempotenceTests
swift test --filter SingleBufferTranscriptionTests
swift test --filter StreamTranscriptionTests
swift test --filter StreamErrorMappingTests
swift test --filter LoggingTests
swift test
```

## D. Handoff signals

After Plan 03 lands, all of the following must be true:

1. `PSTranscription` builds with `FluidAudio` pinned to `https://github.com/FluidInference/FluidAudio.git` at `0.13.6`.
2. `FluidAudioTranscriber` is the only production `Transcribing` conformer added by this plan.
3. The model lives under `PSConfig.modelsDirectory()/parakeet-tdt-0.6b-v2/`.
4. `prepare()` may download on first run and is idempotent thereafter.
5. `modelDownloadProgress()` is the only shared progress stream.
6. `transcribe(_:)` performs single-shot inference on one `PCMBuffer`.
7. `transcribe(stream:)` drains a finite replay stream, concatenates, and transcribes once.
8. Download failures log and map to `PSError.modelDownloadFailure`.
9. CoreML / model-load failures log and map to `PSError.modelLoadFailure`.
10. Inference failures and replay-stream failures log and map to `PSError.transcriptionFailure`.
11. No production code uses `print()`.
12. Tests touching `modelsDirectory()` always use `PSConfig.testingBaseDirectoryOverride`.
13. `FakeTranscriber` from `PSTestSupport` remains the coordinator-level default fake for non-transcription tests.
14. `Tests/PSTranscriptionTests/ManualTranscriptionVerification.md` exists and documents the real “hello world” path.
15. Plan 99 can instantiate `FluidAudioTranscriber()` directly in `AppComposition`.

## Open questions

1. `FluidAudio` tag `0.13.6` declares `macOS(.v14)`. If PersonalScribe needs macOS 13 support, the dependency/version choice must be revisited before coding.
2. Week 1 integrity is structure + file size + simple header checks + real model load. A later hardening step can add SHA-256 manifest validation if a stable upstream manifest source is chosen.
3. The downloader uses Hugging Face directly in Week 1. If a mirror or private registry becomes necessary, the base URL should be made overridable behind an internal seam.

# Plan 03 v2: FluidAudio / Parakeet Transcription
**Goal**: Ship the production `Transcribing` conformer (`FluidAudioTranscriber`) in `SeshatTranscription`, including app-owned model download, progress streaming, and full-utterance transcription that fits Plan 00's replay contract.
**Architecture**: actor-wrapped FluidAudio integration; app-owned `URLSession` downloader under `SeshatConfig.modelsDirectory()`; one `AsyncStream<ModelDownloadProgress>` surface; replay-stream buffering in `transcribe(stream:)`.
**Tech Stack**: FluidAudio `0.13.6`, CoreML, URLSession, Swift Concurrency, XCTest.
**Depends on**: Plan 00 Section C.1, C.2, C.4, C.5, D.6, G; Plan 01 SPM scaffold; Plan 02 `PCMBuffer` producer; Plan 99 integration wiring.
**Plan 00 contract read**: Section C.1 (`TranscriptionResult`, `ModelDownloadProgress`), C.2 (`Transcribing`), C.4 (`SeshatLogger`), C.5 (`SeshatConfig`), D.6 (download ownership), G (Plan 03 consumable symbols).
## Scope Guardrails
- No streaming partial transcripts in Week 1.
- No whisper.cpp fallback path.
- No transcript post-processing, punctuation repair, or filler-word cleanup.
- No VAD integration or segmentation work.
- No UI implementation in this plan; only the `modelDownloadProgress()` surface that Plan 04/99 may consume.
- No new public shared DTOs, wrappers, or duplicate protocols beyond the shared Plan 00 contract.
## Changes from v1 → v2
- Added a dedicated red/green step for CoreML / `loadModels` failures mapping to `SeshatError.modelLoadFailure`, including pre-mapping error logging.
- Replaced all Hugging Face `main` download references with a pinned-revision design and a blocking `TODO(plan-03-impl)` placeholder because this authoring environment cannot query the API.
- Added an explicit fresh-instance no-network test that seeds `SeshatConfig.testingBaseDirectoryOverride` with staged model files and proves `prepare()` makes zero download calls.
- Made `ModelDownloadProgress` semantics explicit: immediate `.idle`, monotonic progress, nil `expectedBytes` handling, throttled updates, and exactly one terminal `.finished`.
## A. Upstream Verification And Pinning
### A.1 Findings to record before coding
The executor must re-run this verification immediately before implementation. The FluidAudio findings below were verified for tag `v0.13.6`. The Hugging Face artifact revision could not be queried from this authoring environment because external webpage access is filtered here; v2 therefore carries an explicit implementation-time TODO instead of silently using `main`.
| Item | Verified finding | Plan 03 consequence |
|---|---|---|
| Swift Package URL | `https://github.com/FluidInference/FluidAudio.git` | Use this exact URL in `Package.swift`. |
| Package pin | `exact: "0.13.6"` | Plan 01 placeholder must be replaced with this exact pin. |
| Product name | `.product(name: "FluidAudio", package: "FluidAudio")` | Matches Plan 01's placeholder shape. |
| Package floor | `macOS(.v14)`, `iOS(.v17)` | Week 1 remains macOS 14+. |
| English model enum | `AsrModelVersion.v2` | Use `.v2` for Week 1. |
| Model loader | `AsrModels.load(from:version: .v2)` | Use `load(from:)`, not SDK-managed auto-download. |
| Manager type | `AsrManager(config: .default)` | One actor-owned manager instance is sufficient. |
| Float32 inference | `try await asrManager.transcribe(samples, source: .microphone)` | `PCMBuffer.samples` passes through directly. |
| Result type | `ASRResult(text:duration:processingTime:tokenTimings:)` | Map `text` and `processingTime`; keep `segments == []` in Week 1. |
| Required staged assets | `Preprocessor.mlmodelc`, `Encoder.mlmodelc`, `Decoder.mlmodelc`, `JointDecision.mlmodelc`, `parakeet_vocab.json` | Presence checks and staging layout must match exactly. |
| Upstream v2 repo slug | `FluidInference/parakeet-tdt-0.6b-v2-coreml` | Use this slug for artifact URLs. |
| Upstream local folder name | `parakeet-tdt-0.6b-v2` | Matches `SeshatConfig.modelId`. |
| Hugging Face model revision | `TODO(plan-03-impl): query https://huggingface.co/api/models/FluidInference/parakeet-tdt-0.6b-v2-coreml and record the 40-char sha before first download` | All artifact URLs and tests must use `resolve/<sha>/...`, never `resolve/main/...`. |
### A.2 Conclusions
1. `FluidAudio` already supports auto-download, but using `downloadAndLoad` would violate Plan 00 Section D.6 because the download lifecycle would live in the SDK instead of `SeshatTranscription`.
2. Plan 03 therefore owns discovery, URL construction, download, progress, validation, cleanup, and atomic staging.
3. After files are staged locally, Plan 03 uses `AsrModels.load(from:version:)`, `AsrManager.loadModels(_:)`, and `transcribe(_:source:)`.
4. Upstream exposes token timings but not a stable shared `Segment` mapping; Week 1 keeps `segments == []`.
5. Artifact revision pinning must be treated with the same discipline as the Swift package pin. `main` is forbidden in the downloader.
### A.3 Executor checklist
1. Open upstream `Package.swift`; confirm repository URL, product name, platform floor, and exact version `0.13.6`.
2. Open upstream `README.md`; confirm `AsrManager` and `AsrModels.load(from:version:)` usage remains valid.
3. Confirm the required staged asset names remain unchanged.
4. Confirm `.v2` is still the correct English model selection.
5. Confirm `AsrManager` still exposes the `[Float]` transcription overload.
6. Query `https://huggingface.co/api/models/FluidInference/parakeet-tdt-0.6b-v2-coreml`.
7. Record the current 40-character `sha` for the `main` branch in this plan and in the downloader constant.
8. Replace the placeholder `modelRevision` constant before the first implementation commit that can hit the network.
9. If any item drifts, stop and revise this plan before coding.
## B. Contract Anchors And Planned Surface
### B.1 Shared contract anchor
Plan 03 implements the shared Plan 00 protocol exactly and must not redefine it:
```swift
import Foundation
public protocol Transcribing: Sendable {
    func prepare() async throws
    func modelDownloadProgress() -> AsyncStream<ModelDownloadProgress>
    func transcribe(_ audio: PCMBuffer) async throws -> TranscriptionResult
    func transcribe(stream: AsyncThrowingStream<PCMBuffer, Error>) async throws -> TranscriptionResult
}
```
### B.2 Planned public production type
`FluidAudioTranscriber` is the only new public production type in this plan. The public initializer must accept a logger with a default so Plan 99 can construct it as written.
```swift
import Foundation
import SeshatCore
public actor FluidAudioTranscriber: Transcribing {
    public init(
        logger: SeshatLogger = SeshatLogger(category: SeshatLogCategory.transcription)
    )
    public func prepare() async throws
    public func modelDownloadProgress() -> AsyncStream<ModelDownloadProgress>
    public func transcribe(_ audio: PCMBuffer) async throws -> TranscriptionResult
    public func transcribe(stream: AsyncThrowingStream<PCMBuffer, Error>) async throws -> TranscriptionResult
}
```
### B.3 Internal seams for TDD only
These are the only `internal` Plan 03 type declarations. Concrete downloader and validation helpers stay `private` file-scoped so they do not expand the shared or module-level surface.
```swift
import Foundation
import SeshatCore
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
### B.4 Public API surface notes
1. `modelDownloadProgress()` always yields the current snapshot immediately to a new subscriber.
2. The first snapshot after `FluidAudioTranscriber` construction is `.idle` with `fractionCompleted: 0`, `receivedBytes: 0`, `expectedBytes: nil`.
3. Within one download session, `fractionCompleted` is monotonic non-decreasing.
4. During an active download, `.downloading` snapshots are emitted at least once every approximately 500 ms when progress is advancing.
5. `expectedBytes == nil` is both allowed and required when the server omits `Content-Length`.
6. The terminal snapshot for a successful session is exactly one `.finished`.
7. `.finished` is not followed by an automatic `.idle` reset event.
8. `prepare()` may publish only `.idle` then `.finished` on the already-downloaded path.
9. `transcribe(stream:)` is the authoritative Week 1 production entry point; `transcribe(_:)` exists for unit tests and narrow helpers.
### B.5 Storage, download, and integrity decisions
Model root:
```text
SeshatConfig.modelsDirectory()/parakeet-tdt-0.6b-v2/
```
Expected contents:
```text
parakeet-tdt-0.6b-v2/
├── Preprocessor.mlmodelc/
│   └── coremldata.bin
├── Encoder.mlmodelc/
│   └── coremldata.bin
├── Decoder.mlmodelc/
│   └── coremldata.bin
├── JointDecision.mlmodelc/
│   └── coremldata.bin
└── parakeet_vocab.json
```
Pinned artifact URL shape:
```text
https://huggingface.co/FluidInference/parakeet-tdt-0.6b-v2-coreml/resolve/<modelRevision>/<path>
```
Downloader constant shape:
```swift
import Foundation
private enum ParakeetArtifact {
    static let repository = "FluidInference/parakeet-tdt-0.6b-v2-coreml"
    static let modelDirectoryName = "parakeet-tdt-0.6b-v2"
    static let modelRevision = "TODO(plan-03-impl): replace-with-40-char-huggingface-sha"
    static let requiredRelativePaths: [String] = [
        "Preprocessor.mlmodelc/coremldata.bin",
        "Encoder.mlmodelc/coremldata.bin",
        "Decoder.mlmodelc/coremldata.bin",
        "JointDecision.mlmodelc/coremldata.bin",
        "parakeet_vocab.json",
    ]
    static func resolveURL(for relativePath: String) -> URL {
        URL(
            string: "https://huggingface.co/\(repository)/resolve/\(modelRevision)/\(relativePath)"
        )!
    }
}
```
Week 1 presence check:
1. `Preprocessor.mlmodelc/coremldata.bin` exists.
2. `Encoder.mlmodelc/coremldata.bin` exists.
3. `Decoder.mlmodelc/coremldata.bin` exists.
4. `JointDecision.mlmodelc/coremldata.bin` exists.
5. `parakeet_vocab.json` exists.
Week 1 integrity rules:
1. Each `coremldata.bin` file is non-zero length on the real download path.
2. `parakeet_vocab.json` is non-empty and begins with `{` or `[` after leading whitespace.
3. Validation failure removes staging and retries once.
4. A second failure logs and maps to `SeshatError.modelDownloadFailure`.
## C. Forbidden Duplicates Semantic Audit
This section lists every `public` and `internal` declaration Plan 03 is allowed to add and explains why none duplicates a Plan 00 concept.
| Declaration | Access | Could be mistaken for | Why it is not a duplicate |
|---|---|---|---|
| `FluidAudioTranscriber` | `public actor` | `Transcribing` | It conforms to `Transcribing`; it does not redefine the protocol or invent a second shared abstraction. |
| `ModelDownloading` | `internal protocol` | `Transcribing` or a second shared download API | It is a Plan 03-only seam for model artifact ownership, which Plan 00 Section D.6 assigns to the transcription layer. |
| `FluidAudioInferencing` | `internal protocol` | `Transcribing` or `TranscriptionResult` | It wraps upstream FluidAudio loading/inference details for testability and does not expose the shared replay contract. |
| `FluidAudioInferenceResult` | `internal struct` | `TranscriptionResult` | It is a narrow adapter DTO for upstream inference output before mapping into the shared `TranscriptionResult`. |
Explicit non-duplicates:
1. Plan 03 must not define a second `Transcribing`.
2. Plan 03 must not define a second `SeshatError`.
3. Plan 03 must not define a second `SeshatLogger` or a wrapper logger type.
4. Plan 03 must not define a second `TranscriptionResult`.
5. Plan 03 must not define a second `ModelDownloadProgress`.
6. Plan 03 must not define a second `SeshatConfig`.
7. Concrete downloader and validation helpers may exist only as `private` implementation details, not new module-level `internal` surface.
## D. Sibling Cross-Plan Audit
### D.1 Plan 02 replay input compatibility
Plan 02 yields `PCMBuffer(samples: [Float], sampleRate: 16_000, channelCount: 1, timestamp: ...)`. Plan 03's `transcribe(stream:)` must therefore:
1. Drain the finite replay stream in order.
2. Concatenate `buffer.samples` in arrival order with no re-chunking.
3. Preserve `sampleRate == 16_000` and `channelCount == 1` from the first buffer.
4. Carry the first buffer's `timestamp` into the synthesized aggregate buffer.
5. Reject any later buffer whose `sampleRate` or `channelCount` differs; log and map to `SeshatError.transcriptionFailure`.
Plan 00's replay model remains aligned:
1. `SessionCoordinator` collects buffers while state is `.recording`.
2. On toggle, it calls `capture.stop()`.
3. It builds one finite replay `AsyncThrowingStream<PCMBuffer, Error>`.
4. It passes that replay stream into `transcribe(stream:)`.
### D.2 Plan 01 SPM placeholder alignment
Plan 01 leaves a commented placeholder for Plan 03 to replace. v2 confirms the replacement is:
```swift
.package(
    url: "https://github.com/FluidInference/FluidAudio.git",
    exact: "0.13.6"
)
```
and
```swift
.product(name: "FluidAudio", package: "FluidAudio")
```
That matches the placeholder's intended package/product shape.
### D.3 Plan 04 / Plan 99 progress-consumption alignment
Plan 04 does not explicitly consume `modelDownloadProgress()`, but the shared shape from Plan 00 already matches what any later UI observer would need:
```swift
func modelDownloadProgress() -> AsyncStream<ModelDownloadProgress>
```
That is consumable by either:
1. a future `MenuBarSceneModel` task that iterates the stream, or
2. Plan 99 integration glue that forwards the stream into UI state.
Because `ModelDownloadProgress` is payload-complete for Week 1 and v2 now defines `.idle` / `.downloading` / `.finished` semantics explicitly, there is no API mismatch here.
### D.4 Plan 99 initializer compatibility
Plan 99 constructs:
```swift
let transcriber = FluidAudioTranscriber(
    logger: SeshatLogger(category: SeshatLogCategory.transcription)
)
```
v1 exposed `public init()` only. v2 fixes that by requiring:
```swift
public init(
    logger: SeshatLogger = SeshatLogger(category: SeshatLogCategory.transcription)
)
```
That removes the only concrete sibling mismatch found during review.
## E. Task Breakdown
### E.0 Shared TDD loop
For every coding step:
1. Add or unskip the failing test first.
2. Run the smallest `swift test --filter ...` command that proves the failure.
3. Implement the minimum code to satisfy the test.
4. Re-run the same filter until green.
5. Commit with `git commit -m "plan-03 step N: <desc>"`.
### Step 1. Verify upstream API, pin FluidAudio, and record the model revision
**Goal**: replace Plan 01's placeholder with the exact Swift package pin and add the model artifact revision constant gate before any downloader code lands.
Files:
- `Package.swift`
- `Sources/SeshatTranscription/FluidAudioTranscriber.swift` or `Sources/SeshatTranscription/FluidAudioModelDownloader.swift`
- `plans/week1/PLAN_03_transcription-v2.md` if the executor resolves the placeholder SHA during implementation
Work:
1. Replace Plan 01's commented dependency placeholder with `exact: "0.13.6"`.
2. Add `.product(name: "FluidAudio", package: "FluidAudio")` to `SeshatTranscription` only.
3. Add the downloader constant `static let modelRevision`.
4. If the Hugging Face API is reachable, replace the TODO placeholder with the real 40-character SHA before any live download code lands.
5. If the API is still blocked, stop and resolve that before allowing a real first-run download. Do not ship `main`.
Manifest snippet:
```swift
// swift-tools-version: 6.0
import PackageDescription
let package = Package(
    name: "Seshat",
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
            name: "SeshatTranscription",
            dependencies: [
                "SeshatCore",
                .product(name: "FluidAudio", package: "FluidAudio"),
            ]
        ),
    ]
)
```
Run: `swift package resolve` then `swift build`. Commit: `git commit -m "plan-03 step 1: pin fluidaudio dependency"`.
### Step 2. Scaffold `FluidAudioTranscriber` with the correct public init
**Goal**: create the production actor with the exact shared surface plus the logger-bearing initializer Plan 99 expects.
Files:
- `Sources/SeshatTranscription/FluidAudioTranscriber.swift`
- `Tests/SeshatTranscriptionTests/FluidAudioTranscriberCompileTests.swift`
Compile witness:
```swift
import XCTest
import SeshatCore
@testable import SeshatTranscription
final class FluidAudioTranscriberCompileTests: XCTestCase {
    func testFluidAudioTranscriberConformsToTranscribing() {
        let transcriber: any Transcribing = FluidAudioTranscriber(
            logger: SeshatLogger(category: SeshatLogCategory.transcription)
        )
        XCTAssertNotNil(transcriber)
    }
}
```
Actor scaffold:
```swift
import Foundation
import SeshatCore
public actor FluidAudioTranscriber: Transcribing {
    private let downloader: any ModelDownloading
    private let inference: any FluidAudioInferencing
    private let logger: SeshatLogger
    private let logSink: (@Sendable (_ level: String, _ message: String) -> Void)?
    public init(
        logger: SeshatLogger = SeshatLogger(category: SeshatLogCategory.transcription)
    ) {
        self.downloader = PrivateModelDownloader()
        self.inference = PrivateFluidAudioInferenceClient()
        self.logger = logger
        self.logSink = nil
    }
    init(
        downloader: any ModelDownloading,
        inference: any FluidAudioInferencing,
        logger: SeshatLogger = SeshatLogger(category: SeshatLogCategory.transcription),
        logSink: (@Sendable (_ level: String, _ message: String) -> Void)? = nil
    ) {
        self.downloader = downloader
        self.inference = inference
        self.logger = logger
        self.logSink = logSink
    }
    public func prepare() async throws { fatalError("step 5+") }
    public func modelDownloadProgress() -> AsyncStream<ModelDownloadProgress> { fatalError("step 5+") }
    public func transcribe(_ audio: PCMBuffer) async throws -> TranscriptionResult { fatalError("step 11+") }
    public func transcribe(stream: AsyncThrowingStream<PCMBuffer, Error>) async throws -> TranscriptionResult { fatalError("step 12+") }
}
```
Run: `swift test --filter FluidAudioTranscriberCompileTests`. Commit: `git commit -m "plan-03 step 2: scaffold fluidaudio transcriber"`.
### Step 3. Add hermetic path helpers and filesystem test fixtures
**Goal**: make model storage deterministic and require `SeshatConfig.testingBaseDirectoryOverride` in every filesystem-touching test.
Files:
- `Sources/SeshatTranscription/FluidAudioTranscriber.swift`
- `Tests/SeshatTranscriptionTests/Support/SeshatTranscriptionFilesystemTestCase.swift`
- `Tests/SeshatTranscriptionTests/ModelPathTests.swift`
Helpers:
1. `modelRootDirectory(base:)`
2. `stagingDirectory(base:)`
3. `requiredModelPaths(in:)`
4. `modelsExist(in:)`
Fixture snippet:
```swift
import XCTest
import SeshatCore
class SeshatTranscriptionFilesystemTestCase: XCTestCase {
    var testRoot: URL!
    override func setUp() async throws {
        try await super.setUp()
        testRoot = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(
            at: testRoot,
            withIntermediateDirectories: true
        )
        SeshatConfig.testingBaseDirectoryOverride = testRoot
    }
    override func tearDown() async throws {
        SeshatConfig.testingBaseDirectoryOverride = nil
        try? FileManager.default.removeItem(at: testRoot)
        try await super.tearDown()
    }
}
```
Path test:
```swift
import XCTest
import SeshatCore
@testable import SeshatTranscription
final class ModelPathTests: SeshatTranscriptionFilesystemTestCase {
    func testModelRootLivesUnderTestingOverride() throws {
        let modelsDirectory = try SeshatConfig.modelsDirectory()
        let modelRoot = FluidAudioTranscriber.modelRootDirectory(base: modelsDirectory)
        XCTAssertTrue(modelRoot.path.hasPrefix(modelsDirectory.path))
        XCTAssertEqual(modelRoot.lastPathComponent, SeshatConfig.modelId)
    }
    func testModelsExistRequiresExactFiveExpectedPaths() throws {
        let modelsDirectory = try SeshatConfig.modelsDirectory()
        let modelRoot = FluidAudioTranscriber.modelRootDirectory(base: modelsDirectory)
        try FileManager.default.createDirectory(at: modelRoot, withIntermediateDirectories: true)
        XCTAssertFalse(FluidAudioTranscriber.modelsExist(in: modelRoot))
    }
}
```
Run: `swift test --filter ModelPathTests`. Commit: `git commit -m "plan-03 step 3: add model path helpers"`.
### Step 4. Build pinned-revision download URL construction
**Goal**: make the downloader use the pinned revision constant and prove no request uses `main`.
Files:
- `Sources/SeshatTranscription/FluidAudioModelDownloader.swift`
- `Tests/SeshatTranscriptionTests/ModelDownloadTests.swift`
Pinned revision test:
```swift
import Foundation
import XCTest
@testable import SeshatTranscription
final class ModelDownloadTests: XCTestCase {
    func testDownloaderUsesPinnedRevision() {
        let urls = ParakeetArtifact.requiredRelativePaths.map(ParakeetArtifact.resolveURL(for:))
        XCTAssertFalse(urls.isEmpty)
        for url in urls {
            XCTAssertTrue(url.absoluteString.contains("/resolve/\(ParakeetArtifact.modelRevision)/"))
            XCTAssertFalse(url.absoluteString.contains("/resolve/main/"))
        }
    }
}
```
Constant requirement:
```swift
private enum ParakeetArtifact {
    static let repository = "FluidInference/parakeet-tdt-0.6b-v2-coreml"
    static let modelRevision = "TODO(plan-03-impl): replace-with-40-char-huggingface-sha"
    static let requiredRelativePaths: [String] = [
        "Preprocessor.mlmodelc/coremldata.bin",
        "Encoder.mlmodelc/coremldata.bin",
        "Decoder.mlmodelc/coremldata.bin",
        "JointDecision.mlmodelc/coremldata.bin",
        "parakeet_vocab.json",
    ]
}
```
Run: `swift test --filter ModelDownloadTests`. Commit: `git commit -m "plan-03 step 4: pin model artifact revision"`.
### Step 5. Implement the download progress state machine
**Goal**: own the single shared `ModelDownloadProgress` stream and encode the v2 semantics explicitly.
Files:
- `Sources/SeshatTranscription/FluidAudioTranscriber.swift`
- `Sources/SeshatTranscription/FluidAudioModelDownloader.swift`
- `Tests/SeshatTranscriptionTests/ModelDownloadProgressTests.swift`
Design:
1. `FluidAudioTranscriber` stores the current snapshot.
2. `modelDownloadProgress()` yields that snapshot immediately on subscription.
3. The initial snapshot is `.idle`.
4. During a live transfer, updates are monotonic.
5. Progress events are throttled to at least one every ~500 ms while bytes advance.
6. The success terminal state is exactly one `.finished`.
Progress tests:
```swift
import XCTest
import SeshatCore
@testable import SeshatTranscription
final class ModelDownloadProgressTests: SeshatTranscriptionFilesystemTestCase {
    func testPrepareEmitsIdleDownloadingFinishedExactlyOnce() async throws {
        let downloader = StubModelDownloader(
            scriptedProgress: [
                .init(phase: .downloading, fractionCompleted: 0.25, receivedBytes: 25, expectedBytes: 100),
                .init(phase: .downloading, fractionCompleted: 0.75, receivedBytes: 75, expectedBytes: 100),
                .init(phase: .downloading, fractionCompleted: 1.00, receivedBytes: 100, expectedBytes: 100),
            ]
        )
        let transcriber = FluidAudioTranscriber(
            downloader: downloader,
            inference: StubInferenceClient()
        )
        let task = Task { await collect(stream: transcriber.modelDownloadProgress(), limit: 5) }
        try await transcriber.prepare()
        let snapshots = await task.value
        XCTAssertEqual(snapshots.first, .init(phase: .idle, fractionCompleted: 0, receivedBytes: 0, expectedBytes: nil))
        XCTAssertEqual(snapshots.last?.phase, .finished)
        XCTAssertEqual(snapshots.filter { $0.phase == .finished }.count, 1)
        XCTAssertEqual(snapshots.map(\.fractionCompleted), snapshots.map(\.fractionCompleted).sorted())
    }
    func testDownloadProgressAllowsNilExpectedBytesWhenContentLengthMissing() async throws {
        let downloader = StubModelDownloader(
            scriptedProgress: [
                .init(phase: .downloading, fractionCompleted: 0.10, receivedBytes: 1_024, expectedBytes: nil),
                .init(phase: .downloading, fractionCompleted: 0.40, receivedBytes: 4_096, expectedBytes: nil),
            ]
        )
        let transcriber = FluidAudioTranscriber(
            downloader: downloader,
            inference: StubInferenceClient()
        )
        let task = Task { await collect(stream: transcriber.modelDownloadProgress(), limit: 4) }
        try await transcriber.prepare()
        let snapshots = await task.value
        XCTAssertTrue(snapshots.contains(where: { $0.phase == .downloading && $0.expectedBytes == nil }))
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
Run: `swift test --filter ModelDownloadProgressTests`. Commit: `git commit -m "plan-03 step 5: add model download progress state machine"`.
### Step 6. Map download failures to `SeshatError.modelDownloadFailure`
**Goal**: preserve the shared error surface for listing, network, file-system, or staging failures.
Files:
- `Sources/SeshatTranscription/FluidAudioTranscriber.swift`
- `Sources/SeshatTranscription/FluidAudioModelDownloader.swift`
- `Tests/SeshatTranscriptionTests/ModelDownloadFailureTests.swift`
Failure test:
```swift
import XCTest
import SeshatCore
@testable import SeshatTranscription
final class ModelDownloadFailureTests: SeshatTranscriptionFilesystemTestCase {
    func testPrepareMapsDownloadFailureToSharedError() async {
        let transcriber = FluidAudioTranscriber(
            downloader: StubModelDownloader(error: URLError(.notConnectedToInternet)),
            inference: StubInferenceClient()
        )
        do {
            try await transcriber.prepare()
            XCTFail("Expected prepare() to throw")
        } catch let error as SeshatError {
            XCTAssertEqual(error, .modelDownloadFailure)
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }
}
```
Implementation note:
1. Any `URLSession`, file-system, listing, or staging failure logs through `SeshatLogger(category: SeshatLogCategory.transcription)`.
2. The public throw from `prepare()` is always `SeshatError.modelDownloadFailure`.
Run: `swift test --filter ModelDownloadFailureTests`. Commit: `git commit -m "plan-03 step 6: map model download failures"`.
### Step 7. Map CoreML / model load failures to `SeshatError.modelLoadFailure`
**Goal**: add the missing red/green slice the review identified for `loadModels` failures.
Files:
- `Sources/SeshatTranscription/FluidAudioTranscriber.swift`
- `Sources/SeshatTranscription/FluidAudioInferenceClient.swift`
- `Tests/SeshatTranscriptionTests/FluidAudioTranscriberTests.swift`
Required setup:
1. Seed `SeshatConfig.testingBaseDirectoryOverride`.
2. Create the final model directory with the exact five presence-check files so the download path is skipped.
3. Stub `FluidAudioInferencing.loadModel(from:)` to throw:
```swift
NSError(
    domain: "CoreMLFake",
    code: -1,
    userInfo: [NSLocalizedDescriptionKey: "Compile failed"]
)
```
4. Observe logging via the internal `logSink` closure. The recorded message must contain `"Compile failed"` at `.error` level before the error is mapped.
5. If direct observation of the production logger becomes impossible, keep the log expectation documented in the step and verify it manually in addition to the test.
Failing test:
```swift
import Foundation
import XCTest
import SeshatCore
@testable import SeshatTranscription
final class FluidAudioTranscriberTests: SeshatTranscriptionFilesystemTestCase {
    func testPrepareThrowsModelLoadFailureWhenFluidAudioLoadThrows() async throws {
        let modelsDirectory = try SeshatConfig.modelsDirectory()
        let modelRoot = FluidAudioTranscriber.modelRootDirectory(base: modelsDirectory)
        for directory in [
            "Preprocessor.mlmodelc",
            "Encoder.mlmodelc",
            "Decoder.mlmodelc",
            "JointDecision.mlmodelc",
        ] {
            try FileManager.default.createDirectory(
                at: modelRoot.appendingPathComponent(directory, isDirectory: true),
                withIntermediateDirectories: true
            )
            try Data([1]).write(
                to: modelRoot.appendingPathComponent("\(directory)/coremldata.bin")
            )
        }
        try Data("{}".utf8).write(to: modelRoot.appendingPathComponent("parakeet_vocab.json"))
        let recorder = LogRecorder()
        let transcriber = FluidAudioTranscriber(
            downloader: StubModelDownloader(),
            inference: StubInferenceClient(
                loadError: NSError(
                    domain: "CoreMLFake",
                    code: -1,
                    userInfo: [NSLocalizedDescriptionKey: "Compile failed"]
                )
            ),
            logger: SeshatLogger(category: SeshatLogCategory.transcription),
            logSink: { level, message in
                Task { await recorder.record(level: level, message: message) }
            }
        )
        await XCTAssertThrowsError(try await transcriber.prepare()) { error in
            XCTAssertEqual(error as? SeshatError, .modelLoadFailure)
        }
        let records = await recorder.records
        XCTAssertTrue(records.contains { $0.level == "error" && $0.message.contains("Compile failed") })
    }
}
actor LogRecorder {
    private(set) var records: [(level: String, message: String)] = []
    func record(level: String, message: String) {
        records.append((level, message))
    }
}
```
Implementation note:
```swift
do {
    try await inference.loadModel(from: modelDirectory)
} catch {
    logger.error("FluidAudio model load failed: \(error.localizedDescription)")
    logSink?("error", "FluidAudio model load failed: \(error.localizedDescription)")
    throw SeshatError.modelLoadFailure
}
```
Run: `swift test --filter FluidAudioTranscriberTests/testPrepareThrowsModelLoadFailureWhenFluidAudioLoadThrows`. Commit: `git commit -m "plan-03 step 7: map model load failure to SeshatError"`.
### Step 8. Add integrity validation and corruption retry
**Goal**: reject broken downloads before calling `AsrModels.load(from:)`.
Files:
- `Sources/SeshatTranscription/FluidAudioModelDownloader.swift`
- `Tests/SeshatTranscriptionTests/ModelIntegrityTests.swift`
Week 1 validation rules:
1. The five required top-level paths exist.
2. `parakeet_vocab.json` is non-empty and begins with `{` or `[`.
3. Each `.mlmodelc` directory contains `coremldata.bin`.
4. Each `coremldata.bin` is non-zero size on the real download path.
5. Validation failure removes staging and retries once.
6. A second failure logs and maps to `SeshatError.modelDownloadFailure`.
Integrity tests:
```swift
import XCTest
import SeshatCore
@testable import SeshatTranscription
final class ModelIntegrityTests: SeshatTranscriptionFilesystemTestCase {
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
        } catch let error as SeshatError {
            XCTAssertEqual(error, .modelDownloadFailure)
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }
}
```
Run: `swift test --filter ModelIntegrityTests`. Commit: `git commit -m "plan-03 step 8: add model integrity validation"`.
### Step 9. Add the no-network already-downloaded test
**Goal**: prove that a fresh transcriber skips the network entirely when the model directory is already populated under `SeshatConfig.testingBaseDirectoryOverride`.
Files:
- `Sources/SeshatTranscription/FluidAudioTranscriber.swift`
- `Tests/SeshatTranscriptionTests/FluidAudioTranscriberAlreadyDownloadedTests.swift`
Required setup:
1. Set `SeshatConfig.testingBaseDirectoryOverride = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)`.
2. Create `<testingBaseDirectoryOverride>/Seshat/models/parakeet-tdt-0.6b-v2/`.
3. Create these placeholder files:
   - `Preprocessor.mlmodelc/coremldata.bin`
   - `Encoder.mlmodelc/coremldata.bin`
   - `Decoder.mlmodelc/coremldata.bin`
   - `JointDecision.mlmodelc/coremldata.bin`
   - `parakeet_vocab.json`
4. Use a `RecordingURLSession` fake that records every request and throws if called.
5. Stub `FluidAudioInferencing.loadModel(from:)` to no-op so the fake placeholders are never truly compiled.
6. In `tearDown()`, reset `testingBaseDirectoryOverride = nil` and remove the temp dir.
Fresh-instance no-network test:
```swift
import Foundation
import XCTest
import SeshatCore
@testable import SeshatTranscription
final class FluidAudioTranscriberAlreadyDownloadedTests: XCTestCase {
    private var testRoot: URL!
    override func setUp() async throws {
        try await super.setUp()
        testRoot = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: testRoot, withIntermediateDirectories: true)
        SeshatConfig.testingBaseDirectoryOverride = testRoot
        let modelRoot = testRoot
            .appendingPathComponent("Seshat", isDirectory: true)
            .appendingPathComponent("models", isDirectory: true)
            .appendingPathComponent("parakeet-tdt-0.6b-v2", isDirectory: true)
        for directory in [
            "Preprocessor.mlmodelc",
            "Encoder.mlmodelc",
            "Decoder.mlmodelc",
            "JointDecision.mlmodelc",
        ] {
            try FileManager.default.createDirectory(
                at: modelRoot.appendingPathComponent(directory, isDirectory: true),
                withIntermediateDirectories: true
            )
            try Data([1]).write(
                to: modelRoot.appendingPathComponent("\(directory)/coremldata.bin")
            )
        }
        try Data("{}".utf8).write(to: modelRoot.appendingPathComponent("parakeet_vocab.json"))
    }
    override func tearDown() async throws {
        SeshatConfig.testingBaseDirectoryOverride = nil
        try? FileManager.default.removeItem(at: testRoot)
        try await super.tearDown()
    }
    func testPrepareSkipsDownloadWhenModelAlreadyOnDisk() async throws {
        let recordingSession = RecordingURLSession()
        let downloader = StubModelDownloader(recordingSession: recordingSession)
        let transcriber = FluidAudioTranscriber(
            downloader: downloader,
            inference: StubInferenceClient(loadError: nil)
        )
        try await transcriber.prepare()
        XCTAssertTrue(await recordingSession.requests.isEmpty)
    }
}
actor RecordingURLSession {
    private(set) var requests: [URLRequest] = []
    func record(_ request: URLRequest) throws {
        requests.append(request)
        throw URLError(.cannotConnectToHost)
    }
}
```
Run: `swift test --filter FluidAudioTranscriberAlreadyDownloadedTests/testPrepareSkipsDownloadWhenModelAlreadyOnDisk`. Commit: `git commit -m "plan-03 step 9: prove already-downloaded path skips network"`.
### Step 10. Make `prepare()` idempotent and coalesced
**Goal**: second and concurrent calls should not redownload or reload the model.
Files:
- `Sources/SeshatTranscription/FluidAudioTranscriber.swift`
- `Tests/SeshatTranscriptionTests/PrepareIdempotenceTests.swift`
Design:
1. Track `hasPreparedModel`.
2. Track one in-flight `prepareTask`.
3. The first caller creates the task.
4. Later callers await the same task.
5. Success sets `hasPreparedModel = true`.
6. Failure clears `prepareTask`.
Idempotence tests:
```swift
import XCTest
import SeshatCore
@testable import SeshatTranscription
final class PrepareIdempotenceTests: SeshatTranscriptionFilesystemTestCase {
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
    func testConcurrentPrepareCallsShareOneTask() async throws {
        let downloader = StubModelDownloader()
        let inference = StubInferenceClient()
        let transcriber = FluidAudioTranscriber(
            downloader: downloader,
            inference: inference
        )
        async let first: Void = transcriber.prepare()
        async let second: Void = transcriber.prepare()
        _ = try await (first, second)
        XCTAssertEqual(await downloader.ensureCallCount, 1)
        XCTAssertEqual(await inference.loadCallCount, 1)
    }
}
```
Run: `swift test --filter PrepareIdempotenceTests`. Commit: `git commit -m "plan-03 step 10: make prepare idempotent"`.
### Step 11. Implement `transcribe(_ audio:)`
**Goal**: perform one single-shot transcription from one `PCMBuffer`.
Files:
- `Sources/SeshatTranscription/FluidAudioInferenceClient.swift`
- `Sources/SeshatTranscription/FluidAudioTranscriber.swift`
- `Tests/SeshatTranscriptionTests/SingleBufferTranscriptionTests.swift`
Production call path:
```swift
import FluidAudio
let models = try await AsrModels.load(from: modelDirectory, version: .v2)
let manager = AsrManager(config: .default)
try await manager.loadModels(models)
let result = try await manager.transcribe(samples, source: .microphone)
```
Week 1 mapping:
1. `text` ← `ASRResult.text`
2. `segments` ← `[]`
3. `audioDuration` ← `PCMBuffer.duration`
4. `processingDuration` ← upstream `processingTime`
Transcription test:
```swift
import XCTest
import SeshatCore
@testable import SeshatTranscription
final class SingleBufferTranscriptionTests: XCTestCase {
    func testTranscribeMapsCannedInferenceResult() async throws {
        let audio = try PCMBuffer(
            samples: Array(repeating: 0.1, count: 16_000),
            sampleRate: 16_000,
            channelCount: 1,
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
Run: `swift test --filter SingleBufferTranscriptionTests`. Commit: `git commit -m "plan-03 step 11: add single-buffer transcription"`.
### Step 12. Implement `transcribe(stream:)` as buffered full-utterance replay
**Goal**: drain one finite replay stream, concatenate samples in order, and call `transcribe(_:)` exactly once.
Files:
- `Sources/SeshatTranscription/FluidAudioTranscriber.swift`
- `Tests/SeshatTranscriptionTests/StreamTranscriptionTests.swift`
Rules:
1. Drain the entire finite replay stream.
2. Preserve arrival order.
3. Concatenate `PCMBuffer.samples` into one `[Float]`.
4. Use the first buffer's `timestamp`.
5. Require matching `sampleRate` and `channelCount` across all buffers.
6. Call `transcribe(_:)` exactly once.
Replay-stream test:
```swift
import XCTest
import SeshatCore
@testable import SeshatTranscription
final class StreamTranscriptionTests: XCTestCase {
    func testTranscribeStreamConcatenatesThenRunsSingleInference() async throws {
        let first = try PCMBuffer(
            samples: Array(repeating: 0.1, count: 8_000),
            sampleRate: 16_000,
            channelCount: 1,
            timestamp: .now
        )
        let second = try PCMBuffer(
            samples: Array(repeating: 0.2, count: 8_000),
            sampleRate: 16_000,
            channelCount: 1,
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
        XCTAssertEqual(await inference.lastFirstSample, 0.1)
        XCTAssertEqual(await inference.lastLastSample, 0.2)
    }
}
```
Run: `swift test --filter StreamTranscriptionTests`. Commit: `git commit -m "plan-03 step 12: add buffered stream transcription"`.
### Step 13. Map replay-stream failures to `SeshatError.transcriptionFailure`
**Goal**: prove the dynamic runtime error from `transcribe(stream:)` is always `SeshatError`, even when the upstream stream throws `NSError`.
Files:
- `Sources/SeshatTranscription/FluidAudioTranscriber.swift`
- `Tests/SeshatTranscriptionTests/StreamErrorMappingTests.swift`
Behavior:
1. Catch any error thrown while draining the stream.
2. Log the underlying error before mapping.
3. Throw `SeshatError.transcriptionFailure`.
Error test:
```swift
import Foundation
import XCTest
import SeshatCore
@testable import SeshatTranscription
final class StreamErrorMappingTests: XCTestCase {
    func testStreamNSErrorIsMappedToSharedTranscriptionFailure() async {
        let upstream = NSError(
            domain: "ReplayFake",
            code: 7,
            userInfo: [NSLocalizedDescriptionKey: "Replay stream blew up"]
        )
        let stream = AsyncThrowingStream<PCMBuffer, Error> { continuation in
            continuation.finish(throwing: upstream)
        }
        let transcriber = FluidAudioTranscriber(
            downloader: StubModelDownloader(),
            inference: StubInferenceClient()
        )
        do {
            _ = try await transcriber.transcribe(stream: stream)
            XCTFail("Expected transcribe(stream:) to throw")
        } catch let error as SeshatError {
            XCTAssertEqual(error, .transcriptionFailure)
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }
}
```
Run: `swift test --filter StreamErrorMappingTests`. Commit: `git commit -m "plan-03 step 13: map stream errors to shared error"`.
### Step 14. Add logging coverage for inference-path failures
**Goal**: keep explicit logging assertions for the remaining public failure path not already covered by Steps 6, 7, and 13.
Files:
- `Sources/SeshatTranscription/FluidAudioTranscriber.swift`
- `Tests/SeshatTranscriptionTests/LoggingTests.swift`
This step covers:
1. Inference failure during `transcribe(_:)`.
Logging test:
```swift
import XCTest
import SeshatCore
@testable import SeshatTranscription
final class LoggingTests: XCTestCase {
    func testInferenceFailureIsLoggedBeforeMapping() async throws {
        let recorder = LogRecorder()
        let transcriber = FluidAudioTranscriber(
            downloader: StubModelDownloader(),
            inference: StubInferenceClient(transcribeError: StubInferenceError.failed),
            logger: SeshatLogger(category: SeshatLogCategory.transcription),
            logSink: { level, message in
                Task { await recorder.record(level: level, message: message) }
            }
        )
        let audio = try PCMBuffer(
            samples: Array(repeating: 0.1, count: 16_000),
            sampleRate: 16_000,
            channelCount: 1,
            timestamp: .now
        )
        do {
            _ = try await transcriber.transcribe(audio)
            XCTFail("Expected transcription to fail")
        } catch let error as SeshatError {
            XCTAssertEqual(error, .transcriptionFailure)
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
        let records = await recorder.records
        XCTAssertTrue(records.contains { $0.level == "error" && $0.message.contains("failed") })
    }
}
enum StubInferenceError: Error {
    case failed
}
actor LogRecorder {
    private(set) var records: [(level: String, message: String)] = []
    func record(level: String, message: String) {
        records.append((level, message))
    }
}
```
Run: `swift test --filter LoggingTests`. Commit: `git commit -m "plan-03 step 14: add transcription failure logging"`.
### Step 15. Add the manual verification runbook
**Goal**: document the real end-to-end path without putting the first-run model download in CI.
Files:
- `Tests/SeshatTranscriptionTests/ManualTranscriptionVerification.md`
Runbook contents:
1. Apple Silicon / macOS 14+ prerequisite.
2. Delete any prior model under `~/Library/Application Support/Seshat/models/parakeet-tdt-0.6b-v2`.
3. Confirm the downloader constant is not left at `TODO(plan-03-impl)`.
4. Trigger `prepare()`.
5. Observe progress `idle → downloading → finished`.
6. Transcribe a 16 kHz mono WAV of `"hello world"`.
7. Confirm final text contains `hello world`.
8. Confirm the final model directory contains the five expected assets.
9. Confirm no production `print()` path and failures are logged through `SeshatLogger`.
Runbook skeleton:
```markdown
# Manual Transcription Verification
## Goal
Verify that `FluidAudioTranscriber` downloads the pinned Parakeet v2 model on first run and transcribes a short WAV end-to-end.
## Preconditions
- Apple Silicon
- macOS 14+
- Working network connection
- `SeshatConfig.testingBaseDirectoryOverride == nil`
- `ParakeetArtifact.modelRevision` replaced with a real 40-character SHA
## Procedure
1. Remove any prior model under `~/Library/Application Support/Seshat/models/parakeet-tdt-0.6b-v2`.
2. Trigger `prepare()`.
3. Confirm progress `idle → downloading → finished`.
4. Feed a 16 kHz mono WAV speaking "hello world".
5. Confirm `TranscriptionResult.text` contains `hello world`.
6. Confirm the model directory contains the expected assets.
7. Confirm failures log through `SeshatLogger(category: SeshatLogCategory.transcription)`.
```
Commit: `git commit -m "plan-03 step 15: add manual transcription verification runbook"`.
## F. Dependency Table
### F.1 Ordered execution
| Step | Depends on | Why |
|---|---|---|
| 1 | Plan 01 scaffold | The dependency pin and revision gate land first. |
| 2 | 1 | The production actor must exist before behavior tests compile. |
| 3 | 2 | Downloader and prepare tests depend on deterministic paths and fixture setup. |
| 4 | 3 | URL pinning depends on the artifact constants and path helpers. |
| 5 | 4 | Progress streaming depends on the downloader path existing. |
| 6 | 5 | Download failure mapping depends on the prepare/download flow. |
| 7 | 3, 6 | The model-load-failure slice needs the no-download presence path and mapped prepare flow. |
| 8 | 6 | Integrity validation extends the downloader path. |
| 9 | 3, 7 | The no-network test uses the final path helpers and the real prepare fast-path. |
| 10 | 6, 7, 8, 9 | Idempotence should stabilize only after both download and load behavior are known. |
| 11 | 10 | Single-buffer inference depends on stable prepare/load semantics. |
| 12 | 11 | Replay-stream behavior delegates to single-buffer transcription. |
| 13 | 12 | Stream failure mapping depends on replay collection existing. |
| 14 | 7, 11, 13 | Logging assertions rely on real failure paths. |
| 15 | 11, 12, 13, 14 | Runbook is most accurate after behavior is final. |
### F.2 Safe parallelization
| Parallel group | Steps | Notes |
|---|---|---|
| A | 1, 2, 3 | Package pin, actor scaffold, and test fixture setup. |
| B | 4, 5, 6 | Downloader constants, progress state machine, and download failure mapping. |
| C | 7, 8, 9, 10 | Prepare/load semantics. Keep file ownership coordinated. |
| D | 11, 12, 13, 14 | Inference, replay stream, error mapping, and logging. |
| E | 15 | Manual docs only. |
### F.3 Minimum command cadence
```bash
swift test --filter FluidAudioTranscriberCompileTests
swift test --filter ModelPathTests
swift test --filter ModelDownloadTests
swift test --filter ModelDownloadProgressTests
swift test --filter ModelDownloadFailureTests
swift test --filter FluidAudioTranscriberTests/testPrepareThrowsModelLoadFailureWhenFluidAudioLoadThrows
swift test --filter ModelIntegrityTests
swift test --filter FluidAudioTranscriberAlreadyDownloadedTests/testPrepareSkipsDownloadWhenModelAlreadyOnDisk
swift test --filter PrepareIdempotenceTests
swift test --filter SingleBufferTranscriptionTests
swift test --filter StreamTranscriptionTests
swift test --filter StreamErrorMappingTests
swift test --filter LoggingTests
swift test
```
## G. Handoff Signals
After Plan 03 lands, all of the following must be true:
1. `SeshatTranscription` builds with `FluidAudio` pinned to `https://github.com/FluidInference/FluidAudio.git` at `0.13.6`.
2. `FluidAudioTranscriber` is the only production `Transcribing` conformer added by this plan.
3. The public initializer is `FluidAudioTranscriber(logger: SeshatLogger = ...)`, so Plan 99 can instantiate it directly.
4. The model lives under `SeshatConfig.modelsDirectory()/parakeet-tdt-0.6b-v2/`.
5. Download URLs are built with a pinned Hugging Face revision constant, never `main`.
6. If the revision could not be resolved during authoring, the implementation still contains a blocking `TODO(plan-03-impl)` gate that must be resolved before first real download.
7. `prepare()` may download on first run, skips the network when the required files already exist, and is idempotent thereafter.
8. `modelDownloadProgress()` is the only shared progress stream.
9. The first progress event is `.idle`, progress is monotonic within a session, and the success terminal event is exactly one `.finished`.
10. `transcribe(_:)` performs single-shot inference on one `PCMBuffer`.
11. `transcribe(stream:)` drains a finite replay stream, concatenates buffers in order, and transcribes exactly once.
12. Download failures log and map to `SeshatError.modelDownloadFailure`.
13. CoreML / model-load failures log and map to `SeshatError.modelLoadFailure`.
14. Inference failures and replay-stream failures log and map to `SeshatError.transcriptionFailure`.
15. No production code uses `print()`.
16. Tests touching `modelsDirectory()` always use `SeshatConfig.testingBaseDirectoryOverride`.
17. `FakeTranscriber` from `SeshatTestSupport` remains the default fake for coordinator-level tests outside `SeshatTranscription`.
18. `Tests/SeshatTranscriptionTests/ManualTranscriptionVerification.md` exists and documents the real `"hello world"` path.
## H. Self-verification Checklist
- [ ] No Plan 00 Section C symbol redefined
- [ ] No logging wrapper; all logs via `SeshatLogger(category: SeshatLogCategory.transcription)`
- [ ] `modelLoadFailure` has a red/green step
- [ ] Model download URLs use a pinned HuggingFace revision (or TODO with verification step)
- [ ] No-network 'already downloaded' test present
- [ ] `ModelDownloadProgress` semantics explicit
- [ ] `testingBaseDirectoryOverride` used in every FS-touching test
- [ ] `transcribe(stream:)` follows Plan 00 replay-stream contract
- [ ] Dynamic stream error always `SeshatError` (test proves it with upstream `NSError` stub)
## I. Open Questions
1. `FluidAudio` tag `0.13.6` declares `macOS(.v14)`. If Seshat needs macOS 13 support, the dependency/version choice must be revisited before coding.
2. The authoring environment for this v2 document cannot query the Hugging Face API, so the executor must resolve and record the real artifact SHA before implementation of the live download path.
3. Week 1 integrity uses structure checks, non-zero file checks, simple vocab-header checks, and real model load. A later hardening pass can add SHA-256 manifest validation if upstream exposes a stable artifact manifest.
4. Plan 04 currently does not choose a specific progress UI. The shared DTO is now explicit enough for that future decision without further Plan 03 changes.

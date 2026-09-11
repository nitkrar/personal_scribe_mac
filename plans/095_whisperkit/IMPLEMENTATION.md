# #095 — Whisper via WhisperKit — IMPLEMENTATION

Status: drafting (claude-atlas/slate, 2026-05-17). Companion to `DESIGN.md` (revision 2). Adversarial review of revision 1 captured at `REVIEW-consolidated.md`.

Pre-flight: read `DESIGN.md` first. This document is a step-by-step rollout plan; it assumes the locked decisions D1–D11.

## Stage map

| Stage | Outcome | Effort | Exit gate |
|---|---|---|---|
| A.0 | WhisperKit API confirmation (narrow spike) | 0.1d | `whisperkit-api-notes.md` posted with confirmed tokenizer-folder behavior + package pin |
| A | Core types + descriptors + chip-gating land | 0.5d | `swift build` green; catalog tests pass; pre-existing tests still pass |
| B | Adapter + manager seam + pre-stage download + multi-result merge | 1–1.5d | adapter compiles; stub-manager tests pass; ModelBoundProcessorProvider routes `.whisperKit` |
| C | Adapter tests, catalog tests, chip-gating tests, Sendable boundary test | 0.75d | `swift test --filter "WhisperKit\|BuiltInModelCatalog\|ChipFamily"` green |
| D | Manual verification dogfood pass per descriptor | 0.5d | All MV-WHISPERKIT-1..5 + OFFLINE + CHIP-GATE + NON-ENGLISH entries checked off |
| E | BACKLOG.md body update + close-out | 0.1d | #095 status → done; commit + push |

Total: **2.9–3.5d**. No blockers; #078 + #091 + #025 all out of scope per DESIGN §8.

## Stage A.0 — WhisperKit API confirmation (narrow spike)

**Goal:** confirm the two open questions DESIGN.md flagged in §6.1: where WhisperKit looks for `tokenizer.json` when `modelFolder` is set, and whether `v1.0.0` of `argmaxinc/argmax-oss-swift` is the right pin.

**Steps:**
1. Clone WhisperKit at the tag we plan to pin (likely `v1.0.0` as of audit date 2026-05-17). Verify against the audit reference commit `984ab42f6d6824f17630109537829af26ca47fd6`. If divergent, re-audit the four DESIGN §2.1 facts before progressing.
2. Read `WhisperKit.loadTokenizerIfNeeded()` (WhisperKit.swift:462-480) + `ModelUtilities.tokenizerNameForVariant(...)` (ModelUtilities.swift:17-76,175-203). Trace the exact local-folder search order when `modelFolder` is set.
3. Document one of two outcomes in `whisperkit-api-notes.md`:
   - **(a) Local-search hits our pre-stage path** — adapter just stages tokenizer into `<modelsRoot>/<repoFolderName>/tokenizer/` and `WhisperKitConfig(modelFolder:)` is enough. Adapter code is simpler.
   - **(b) Search doesn't see our path** — adapter post-stages tokenizer into whatever subdir WhisperKit expects after download completes (~10 LOC `fileManager.copyItem` step). Same `requiredRelativePaths`, same `removeDownloadedFiles` cleanup.
4. Lock the package pin in `whisperkit-api-notes.md`. If `v1.0.0` is stale, pick the new latest stable.

**Exit:** `plans/095_whisperkit/whisperkit-api-notes.md` lands with confirmed tokenizer mechanism + locked SPM pin. No code yet.

**Risk:** if upstream API diverges materially from the 2026-05-17 audit (e.g. a breaking 1.x release), Stage A.0 expands to re-audit DESIGN §2.1 — file as a blocker and re-run review.

## Stage A — Core types + descriptors + chip-gating

## Stage A — Core types + descriptors + chip-gating (**descriptors stay `isEnabled: false`**)

Order matters: each step compiles + passes existing tests before next step starts. No half-finished compile state.

**Critical safety property (rev3 C2):** Stage A introduces all new types and the 5 Whisper descriptors but keeps them `isEnabled: false`. The engine routing in `ModelBoundProcessorProvider` is NOT touched in Stage A — no `case .whisperKit` branch, no `fatalError` stub. The `.whisperKit` enum case exists but no descriptor uses it yet (since Stage A descriptors have engine `.whisperKit` but `isEnabled: false` filters them from `enabledModels`, and chip-gating filters turbo-632mb additionally). Stage B's final step (B.5) does TWO things atomically in one commit: wire the adapter into `ModelBoundProcessorProvider` AND flip `isEnabled: true` on the 5 descriptors. No intermediate state where a user can activate a Whisper row and crash.

**Why this is the right shape (vs rev2's intermediate `fatalError`):** rev2 enabled the descriptors in Stage A while leaving a `fatalError` in the provider for Stage B. That meant if the user activated a Whisper row during dev iteration (or if `resolveInitialActiveIDs` recovered to one across an app restart), the app crashed. Rev3 keeps descriptors hidden until the real adapter exists.

### A.1 — Add `TranscriptionEngine.whisperKit` case

**Files:**
- `Sources/PersonalScribeCore/Models/Selection/ModelDescriptor.swift` (or wherever the enum lives — verify, it's in the same file as `ModelDescriptor` per audit) — add `case whisperKit`.
- `Sources/PersonalScribeCore/Models/Selection/TranscriptionEngine+Kind.swift` — add `case .whisperKit: return .asr`.
- `Sources/PersonalScribeCore/Models/Selection/TranscriptionEngine+Codable.swift` — add `case whisperKit = "whisperKit"`.

**Compiler-forced fallout — handle without stubbing the provider (rev3 C2):**
- `Sources/PersonalScribeSession/Models/Selection/ModelBoundProcessorProvider.swift:21-57` — exhaustive switch will fail compile. **Do NOT add a `fatalError` stub.** Instead, add `case .whisperKit:` returning `AdapterRecord(descriptorID:, transcriber: NoOpDisabledTranscriber(descriptor: descriptor))` where `NoOpDisabledTranscriber` is an internal type that throws `PersonalScribeError.modelLoadFailure` on `prepare()` / `transcribe()` with a clear log message ("WhisperKit adapter not yet wired — Stage B will replace this"). The throw is the safety net if a Whisper descriptor leaks past Stage A's `isEnabled: false` somehow (it shouldn't, but defense-in-depth). Stage B.5 deletes `NoOpDisabledTranscriber` and replaces this branch with the real `WhisperKitTranscriberAdapter`.

  Place `NoOpDisabledTranscriber` next to `AdapterRecord` in the same file (internal, ~15 LOC). Removed at B.5.

**Tests (extend, not new):**
- `Tests/PersonalScribeCoreTests/Models/TranscriptionEngineKindTests.swift` — pin `.whisperKit.kind == .asr`.

**Exit:** `swift build` + `swift test --filter "TranscriptionEngine"` green. NO Whisper descriptors enabled yet → no user-reachable path to `NoOpDisabledTranscriber`.

### A.2 — Add `ChipFamily` + chip detection

**Files (NEW):**
- `Sources/PersonalScribeCore/Platform/ChipFamily.swift`:
  ```swift
  public enum ChipFamily: Sendable, Equatable, CaseIterable {
      case m1
      case m2OrLater

      public static func current() -> ChipFamily {
          // sysctlbyname("machdep.cpu.brand_string", ...) → substring match
          // "M1" → .m1; everything else (M2, M3, M4, future) → .m2OrLater
      }
  }
  ```
- `Tests/PersonalScribeCoreTests/Platform/ChipFamilyTests.swift`:
  - Pin that `current()` returns a non-optional value on the dev machine.
  - Test the substring-matching helper with a few canned brand strings (`"Apple M1"`, `"Apple M1 Pro"`, `"Apple M2"`, `"Apple M3 Max"`, `"Apple M4"`) — confirm each maps correctly.

**Why CaseIterable:** future-proofs for AI Models tab UI if we ever want a chip picker.

**Exit:** `swift test --filter "ChipFamily"` green; `swift build` green.

### A.3 — Add `tokenizerSource` + `requiredChipFamily` fields to `ModelDescriptor`

**Files:**
- `Sources/PersonalScribeCore/Models/Selection/ModelDescriptor.swift`:
  ```swift
  public let tokenizerSource: String?       // e.g. "openai/whisper-tiny" — nil for non-Whisper descriptors
  public let requiredChipFamily: ChipFamily?  // nil = all Apple Silicon; .m2OrLater = M1 hidden
  ```
- Update `init(...)` with optional params + defaults `nil`. Backward-compat: every existing FluidAudio descriptor still compiles unchanged.

**Tests:**
- `Tests/PersonalScribeCoreTests/Models/ModelDescriptorTests.swift` — pin that existing FluidAudio descriptors get `nil` for both new fields (i.e. defaults preserve current behavior).

**Exit:** `swift build` green; pre-existing catalog tests still pass (Parakeet/Qwen/Diarizer/Streaming descriptors).

### A.4 — Add centralized chip-gating predicate to `ActiveModelService` (rev3 C3)

**Files:**
- `Sources/PersonalScribeSession/Models/Selection/ActiveModelService.swift`:
  1. Add constructor param `chipFamily: () -> ChipFamily = ChipFamily.current` (testability seam).
  2. Add helper `func canActivate(_ descriptor: ModelDescriptor) -> Bool` that returns `descriptor.isEnabled && chipFamilyAllows(descriptor)` where the chip predicate is `descriptor.requiredChipFamily == nil || descriptor.requiredChipFamily == chipFamily() || (descriptor.requiredChipFamily == .m2OrLater && chipFamily() == .m2OrLater)`.
  3. Apply `canActivate` at FOUR call sites (per rev3 C3):
     - `enabledModels(kind:)` — replace existing `descriptor.isEnabled` filter with `canActivate(descriptor)`.
     - `activeDescriptor(for:)` — wrap the return so a persisted-but-no-longer-activatable descriptor returns nil (or falls back to default — pick at impl time; nil + caller-side default is simplest).
     - `setActive(_:)` — guard at entry; if `!canActivate(descriptor)` throw or log + early-return (pick a clear error path that doesn't silently swallow).
     - `resolveInitialActiveIDs(...)` — when iterating persisted IDs to recover, skip any whose descriptor fails `canActivate`; fall through to the existing default-recovery path.

**Tests (`Tests/PersonalScribeSessionTests/Models/Selection/ActiveModelServiceTests.swift` extension):**
- `testCanActivateAcceptsNilChipRequirement` — descriptor with `requiredChipFamily: nil` + chip stub `.m1` → `canActivate == true`.
- `testCanActivateRejectsM2RequirementOnM1` — descriptor `.m2OrLater` + chip stub `.m1` → `canActivate == false`.
- `testCanActivateAcceptsM2RequirementOnM2` — descriptor `.m2OrLater` + chip stub `.m2OrLater` → `canActivate == true`.
- `testEnabledModelsHidesUnsupportedDescriptor` — registered descriptor `.m2OrLater`, chip stub `.m1` → not in `enabledModels(kind: .asr)`.
- `testSetActiveRejectsUnsupportedDescriptor` — chip stub `.m1`, attempt `setActive(turbo632MbDescriptor)` → reject (assert via thrown error OR an unchanged `activeDescriptor` post-call; pick the path A.4 step 3 picked).
- `testActiveDescriptorReturnsNilWhenChipMismatch` — chip stub `.m1`, persist a turbo descriptor as active (via test-only seam), call `activeDescriptor(for: .asr)` → nil.
- `testResolveInitialActiveIDsFallsBackOnChipMismatch` — chip stub `.m1`, persisted active ID = turbo descriptor's id → resolved initial state matches default-asr descriptor, not turbo.

**Risk:** the `setActive` error-path choice (throw vs silent reject vs log-and-no-op) affects callers — `AIModelsTab` activation closure (AIModelsTab.swift:69-70) calls `service.setActive(descriptor)` without error handling. Picking "log + no-op + post-condition: active descriptor unchanged" keeps the existing API surface; alternative "throw" would break compile at the call site. Lock the choice at impl time and document in A.4's commit message.

**Exit:** `swift test --filter "ActiveModelService"` green; pre-existing tests still pass (the new filter is no-op for FluidAudio descriptors which have `requiredChipFamily: nil`).

### A.5 — Add 5 WhisperKit descriptors to `BuiltInModelCatalog` (`isEnabled: false`)

**Files:**
- `Sources/PersonalScribeCore/Models/Selection/BuiltInModelCatalog.swift` — add the 5 descriptors per DESIGN D7 table. For each:
  - `id` (vendor-bound, `whisperkit-*` prefix per rev3), `displayName` (with "(WhisperKit)" suffix), `repoFolderName` (must match HF bundle name exactly), `tokenizerSource`, `shortDescription`, `architecture: "Whisper (WhisperKit runtime)"`, `repository: "argmaxinc/whisperkit-coreml"`, `revision: "main"` (decorative per DESIGN §2.3), `approximateSizeBytes` (per HF tree audit), `engine: .whisperKit`, `madeBy: "OpenAI · Argmax"`, `worksWith` (English-only or "Multilingual (~99 languages)"), `goodFor`, `license: "MIT (WhisperKit) + Apache 2.0 (Whisper weights)"`, `requiredChipFamily: nil` (or `.m2OrLater` for `whisperkit-large-v3-turbo-632mb`).
  - **`isEnabled: false`** — per rev3 C2, all 5 descriptors stay hidden until Stage B.5 flips them in the same commit that wires the real adapter.
  - `requiredRelativePaths`: bundle's mlmodelc `coremldata.bin` files + `config.json` + `generation_config.json` + `tokenizer/tokenizer.json` + `tokenizer/vocab.json` (or whatever Stage A.0 confirms).
  - Append all 5 to `registeredModels`.

**Tests:**
- `Tests/PersonalScribeCoreTests/Models/BuiltInModelCatalogTests.swift` extension per DESIGN D11:
  - Per descriptor: `engine == .whisperKit`, `kind == .asr`, non-empty `shortDescription`, non-empty `repoFolderName`, non-empty `tokenizerSource`, non-empty `requiredRelativePaths`.
  - **In Stage A**, also assert: `isEnabled == false` for all 5 (proves the safety property — these descriptors should not surface in `enabledModels` before Stage B.5).
  - **Exact size pin** within ±5%:
    - `whisperkit-tiny`: 73..81 MB
    - `whisperkit-small-216mb`: 205..227 MB
    - `whisperkit-small-en-217mb`: 206..228 MB
    - `whisperkit-large-v3-626mb`: 595..657 MB
    - `whisperkit-large-v3-turbo-632mb`: 600..664 MB
  - Exact `repoFolderName` string pin per descriptor (catches typos).
  - Exact `tokenizerSource` pin per descriptor.
  - `requiredChipFamily` pin: turbo-632mb → `.m2OrLater`; the other four → `nil`.

**Note on the `isEnabled: false` test:** Stage B.5 flips these to `true` AND deletes the test assertion (or modifies it to assert `isEnabled == true`). The temporary assertion is the tripwire that catches an accidental "enabled the descriptors but forgot to wire the adapter" merge.

**Exit:** `swift test --filter "BuiltInModelCatalog"` green. AI Models tab still hides all 5 rows (visual confirmation in dev build optional).

## Stage B — Adapter implementation

### B.1 — Add SPM dependency

**Files:**
- `Package.swift`:
  ```swift
  .package(url: "https://github.com/argmaxinc/argmax-oss-swift.git", exact: "1.0.0"),  // or whatever Stage A.0 locked
  ```
  ```swift
  .target(
      name: "PersonalScribeTranscription",
      dependencies: [
          "PersonalScribeCore",
          .product(name: "FluidAudio", package: "FluidAudio"),
          .product(name: "WhisperKit", package: "argmax-oss-swift"),  // NEW
      ],
      ...
  )
  ```

**Exit:** `swift package resolve` succeeds; `swift build` succeeds (adapter still stubbed from A.1). New SPM checkout appears at `.build/checkouts/argmax-oss-swift/`.

### B.2 — Define `WhisperKitManaging` protocol + result types (rev3 D4 download→copy shape)

**Files (NEW):**
- `Sources/PersonalScribeTranscription/Adapters/WhisperKitTranscriberAdapter.swift` — top-level types only for this step:
  ```swift
  protocol WhisperKitManaging: Sendable {
      /// Downloads a single HF repo bundle into the staging directory via `HubApi.snapshot`,
      /// then moves the resulting files from `<staging>/models/<repoID>/...` into `destination`.
      /// Cleans up staging on success.
      func downloadAndStage(
          repoID: String,
          relativePaths: [String]?,    // nil = all files
          stagingDirectory: URL,
          destination: URL,
          progressHandler: @escaping @Sendable (Progress) -> Void
      ) async throws

      func loadModel(
          modelName: String,
          modelFolder: URL
      ) async throws

      func transcribe(audioSamples: [Float]) async throws -> [WhisperKitManagerResult]

      func cleanup() async
  }

  struct WhisperKitManagerResult: Sendable, Equatable {
      let text: String
      // No tokenTimings / confidence / performanceMetrics for v1 per D6.
  }
  ```

**Why pure-Swift types only:** D3 Sendable-boundary contract — no WhisperKit reference types in the protocol.

**Why `downloadAndStage` (one method) vs separate `downloadBundle` + `downloadTokenizer`:** the download→copy mechanic is the same for both; the only difference is which repo + which destination. Keeping it as one method simplifies the stub manager in tests (record call args including destination, not infer-by-method-name).

**Exit:** `swift build` green.

### B.3 — Implement actor `WhisperKitTranscriberAdapter`

**Files (extend):**
- `Sources/PersonalScribeTranscription/Adapters/WhisperKitTranscriberAdapter.swift`:
  - `public actor WhisperKitTranscriberAdapter: Transcriber`
  - `public nonisolated let capabilities = TranscriberCapabilities()` (all four false per D6)
  - `private let descriptor: ModelDescriptor`
  - `private let storageLocator: any StorageLocator`
  - `private let manager: any WhisperKitManaging`
  - `private let progressBroadcaster = FluidAudioDownloadProgressBroadcaster()`
  - `private var hasPreparedModel = false`
  - `private var prepareTask: Task<Void, Error>?`
  - Init: descriptor + storageLocator + optional `manager:` (defaults to `LiveWhisperKitManager()`).
  - `public func prepare()` — idempotent + in-flight task dedup (parity with Parakeet). Calls `downloadIfNeeded()` then `manager.loadModel(modelName: descriptor.repoFolderName, modelFolder: <leafURL>)`.
  - `public func downloadIfNeeded()` — runs two `downloadAndStage` calls:
    1. Bundle: `repoID: descriptor.repository ("argmaxinc/whisperkit-coreml")`, `relativePaths: <bundle-relative paths>`, `destination: <modelsRoot>/<repoFolderName>/`.
    2. Tokenizer: `repoID: descriptor.tokenizerSource`, `relativePaths: nil` (all files), `destination: <modelsRoot>/<repoFolderName>/tokenizer/`.
    Aggregates progress via broadcaster, weighted by descriptor's `approximateSizeBytes` split (bundle vs tokenizer).
    Both calls share the same staging root `<modelsRoot>/.staging/<descriptorID>/`; manager cleans staging on success. On any failure, adapter calls a `cleanupPartialDownload()` helper that removes both the destination dir AND the staging root.
  - `public nonisolated func modelDownloadProgress()` — returns `progressBroadcaster.stream()`.
  - `public func cleanup()` — cancel in-flight prepare, reset state, call manager cleanup, emit `.idle`.
  - `public func transcribe(_ audio: PCMBuffer) async throws -> TranscriptionResult`:
    ```swift
    try await prepare()
    let startedAt = ContinuousClock.now
    let results: [WhisperKitManagerResult]
    do {
        results = try await manager.transcribe(audioSamples: audio.samples)
    } catch {
        throw PersonalScribeError.transcriptionFailure
    }
    let measuredTotal = startedAt.duration(to: ContinuousClock.now)
    let mergedText = results.map(\.text).joined(separator: " ")
    return TranscriptionResult(
        text: mergedText,
        audioDuration: audio.duration,
        processingDuration: measuredTotal,
        confidence: nil,
        tokenTimings: nil,
        performanceMetrics: nil,
        ctcDetectedTerms: nil,
        ctcAppliedTerms: nil
    )
    ```

**Exit:** `swift build` green. Adapter compiles end-to-end. ModelBoundProcessorProvider's `NoOpDisabledTranscriber` from A.1 still in place.

### B.4 — Wire `LiveWhisperKitManager` (rev3 D4 — download→copy two-step)

**Files (extend):**
- Same file. `internal actor LiveWhisperKitManager: WhisperKitManaging`:
  - `downloadAndStage(repoID:relativePaths:stagingDirectory:destination:progressHandler:)`:
    1. Create staging dir if absent.
    2. Call `HubApi.snapshot(from: HubApiWrapper.Repo(id: repoID), matching: relativePaths, downloadBase: stagingDirectory, progressHandler: progressHandler)`. Files land at `<stagingDirectory>/models/<repoID>/...` (HF cache layout).
    3. Compute the actual snapshot leaf via `HubApi.localRepoLocation(...)` or by reading the documented layout (`<stagingDirectory>/models/<repoID>/`).
    4. Ensure destination's parent exists. `FileManager.moveItem(at: <snapshotLeaf>, to: destination)`. If `moveItem` fails (e.g., cross-volume), fall back to `copyItem` + `removeItem`, log warning.
    5. Clean up the staging root recursively (best-effort; log warning if cleanup fails but return success since model is usable).
  - `loadModel(modelName:modelFolder:)`: constructs `WhisperKitConfig` with **both** `modelFolder` AND `tokenizerFolder` per Stage A.0's locked finding:
    ```swift
    WhisperKitConfig(
        model: modelName,
        modelFolder: modelFolder.path,
        tokenizerFolder: modelFolder.appendingPathComponent("tokenizer"),
        download: false
    )
    ```
    Then instantiate `WhisperKit(config)`. Hold the instance internally. **Note**: `loadModel`'s signature in B.2 currently takes only `modelName` + `modelFolder`. Extend it here to also take the tokenizer folder URL — or compute the tokenizer subdir inside `loadModel` since the convention is fixed (`<modelFolder>/tokenizer`). Computing inside is simpler — keeps the protocol shape unchanged.
  - `transcribe(audioSamples:)`: calls `whisperKit.transcribe(audioArray: audioSamples)` → maps each returned `WhisperKit.TranscriptionResult.text` into our `WhisperKitManagerResult(text:)`. No WhisperKit reference types escape.
  - `cleanup()`: releases the `WhisperKit` instance.

**Exit:** `swift build` green.

### B.5 — Wire adapter into `ModelBoundProcessorProvider` AND flip descriptors to `isEnabled: true` (rev3 C2 atomic step)

**Files (TWO changes in ONE commit — atomicity matters):**
1. `Sources/PersonalScribeSession/Models/Selection/ModelBoundProcessorProvider.swift` — replace the `NoOpDisabledTranscriber` branch from A.1 with the real adapter:
  ```swift
  case .whisperKit:
      return AdapterRecord(
          descriptorID: descriptor.id,
          transcriber: WhisperKitTranscriberAdapter(
              descriptor: descriptor,
              storageLocator: storageLocator
          )
      )
  ```
  Delete the `NoOpDisabledTranscriber` internal type from this file.
2. `Sources/PersonalScribeCore/Models/Selection/BuiltInModelCatalog.swift` — flip `isEnabled: false` → `isEnabled: true` on all 5 WhisperKit descriptors added in A.5.
3. `Tests/PersonalScribeCoreTests/Models/BuiltInModelCatalogTests.swift` — update the `isEnabled` assertion from `== false` to `== true` for the 5 descriptors. The `whisperkit-large-v3-turbo-632mb` descriptor remains hidden on M1 via the chip-gating predicate from A.4 — descriptor-level `isEnabled` is true but the runtime predicate filters it.

**Why one commit, not three:** mid-merge the descriptors-enabled state plus an unwired provider would crash on activation. Atomic flip eliminates the window. Reviewer/dogfood-tester can roll this commit back to A.5 state safely (descriptors return to hidden).

**Tests:**
- `Tests/PersonalScribeSessionTests/Models/Selection/ModelBoundProcessorProviderTests.swift` extension — `.whisperKit` descriptor resolves to a `transcriber:`-populated `AdapterRecord` (matching existing Parakeet/Qwen pattern). This is the engine-routing test; does NOT exercise the live adapter (which is in Stage C).

**Exit:** `swift build` green. `swift test --filter "ModelBoundProcessorProvider"` green. AI Models tab now shows 5 WhisperKit rows (4 on M1) — visual confirmation in dev build optional; full Manual verification at Stage D.

## Stage C — Tests (real coverage, no mock-theater)

### C.1 — Adapter unit tests

**Files (NEW):**
- `Tests/PersonalScribeTranscriptionTests/Adapters/WhisperKitTranscriberAdapterTests.swift`:
  - `testPrepareIsIdempotent` — call `prepare()` twice; assert manager.loadModel called once.
  - `testPrepareDeduplicatesConcurrentCalls` — launch two `prepare()` Tasks concurrently; assert one load.
  - `testPrepareFailureClearsState` — stub manager throws on loadModel; assert subsequent `prepare()` re-attempts.
  - `testDownloadIfNeededDownloadsBundleAndTokenizer` — stub records both `downloadAndStage` calls; assert order = bundle first (repoID=`argmaxinc/whisperkit-coreml`, destination=`<modelsRoot>/<repoFolderName>/`), then tokenizer (repoID=descriptor.tokenizerSource, destination=`<modelsRoot>/<repoFolderName>/tokenizer/`).
  - `testDownloadIfNeededCleansUpOnTokenizerFailure` — bundle download succeeds, tokenizer throws → adapter calls `cleanupPartialDownload()`; assert post-condition: `<modelsRoot>/<repoFolderName>/` does not exist; staging root does not exist.
  - `testDownloadIfNeededFailureThrowsModelLoadFailure` — stub throws; assert `.modelLoadFailure` propagated; `.idle` emitted on progress stream.
  - **`testTranscribeMergesMultiResultArray`** (load-bearing per C2 in review) — stub returns `[{text: "hello"}, {text: "world"}]`; assert adapter returns single `TranscriptionResult` with `text == "hello world"`, `audioDuration` matching input.
  - `testTranscribeEmptyArrayReturnsEmptyText` — stub returns `[]`; assert `text == ""`, no crash.
  - `testTranscribeFailureThrowsTranscriptionFailure` — stub throws; assert `.transcriptionFailure`.
  - `testCleanupReleasesManager` — stub records cleanup; assert called.
  - **`testTranscribeReturnIsValueOnly`** (Sendable-boundary, per rev2 C8) — call `transcribe`; walk the returned `TranscriptionResult` via `Mirror`; assert no field is a class reference (every value is `String` / `Duration` / `Float` / `[TokenTiming]?` / `TranscriberPerformanceMetrics?` — all value types). Tripwire for a future contributor adding a WhisperKit ref-type to the result.

**Dropped from rev2 (per rev3 C4):** `testUnknownDescriptorThrows` (`unknownVoiceModelID`). The adapter is descriptor-driven, not enum-keyed. Catalog-contract tests in A.5 cover the equivalent surface (every `.whisperKit` descriptor has the fields the adapter consumes).

### C.2 — Sendable boundary test

**Files (extend C.1):**
- `testTranscribeReturnTypeIsValueOnly` — compile-time check via `_ = result as? AnyObject` (returns nil for value types). If a future contributor adds a reference type to `TranscriptionResult`, this test fails. Same pattern as a `Sendable` static check.
- Alternative: `Mirror`-based runtime check that every field of the returned `TranscriptionResult` is `String`/`Duration`/`Float`/`[TokenTiming]` (all value types). More verbose but catches more.

Pick at impl time — runtime Mirror check is more defensive.

### C.3 — Catalog tests (per DESIGN D11)

Already specified in Stage A.5. No new test files; extension of existing.

### C.4 — Chip-gating tests

Already specified in Stage A.4. No new test files; extension of existing.

### C.5 — Engine routing test

Already specified in Stage B.5. No new test files; extension of existing.

**Exit for Stage C:** `swift test` runs the full suite + new tests green. No regressions in existing Parakeet/Qwen/Streaming/Diarizer tests.

## Stage D — Manual verification

Per the project's manual-verification discipline (CLAUDE.md `Flexible TDD`): runtime verification on real hardware before claiming the feature works.

**Files (extend):**
- `Tests/ManualVerifications/ManualAIModelsVerification.md`:
  - `MV-WHISPERKIT-1: whisperkit-tiny download + activate + transcribe`:
    1. Open Settings → AI Models tab.
    2. Locate "Whisper Tiny (WhisperKit)" row under "Voice models" section.
    3. Click Download → confirm progress chip advances → completes.
    4. Confirm bundle dir exists at `<modelsRoot>/openai_whisper-tiny/` with `AudioEncoder.mlmodelc/`, `TextDecoder.mlmodelc/`, `MelSpectrogram.mlmodelc/`, `config.json`, `generation_config.json`, AND `tokenizer/tokenizer.json` (or wherever Stage A.0 locked).
    5. Click Activate → confirm green chip.
    6. Trigger recording (hotkey or pill). Speak: "Hello, this is a test of Whisper tiny."
    7. Confirm transcript appears in Transcriptions tab matching expectation (auto-detect should resolve to English).
    8. Click Delete → confirm bundle dir AND tokenizer dir both gone.
  - `MV-WHISPERKIT-2..5`: same shape for `whisperkit-small-216mb` / `whisperkit-small-en-217mb` / `whisperkit-large-v3-626mb` / `whisperkit-large-v3-turbo-632mb` (last one only on M2+).
  - **`MV-WHISPERKIT-OFFLINE`** (per rev3 C5): download `whisperkit-tiny` with network on. Disable Wi-Fi + Ethernet. Trigger a recording. Confirm transcript appears without any network fetch. Re-enable network. Proves D5 (pre-staged tokenizer) actually works.
  - `MV-WHISPERKIT-CHIP-GATE`: on M1 hardware:
    1. Open Settings → AI Models tab.
    2. Confirm "Whisper Large v3 Turbo (WhisperKit, 632MB)" is NOT in the list.
    3. Confirm the other four WhisperKit rows ARE in the list.
    4. Bonus: with that descriptor previously persisted-active (e.g., copy UserDefaults plist from M2 dev machine), restart app → confirm fall-back to default, no crash.
  - `MV-WHISPERKIT-NON-ENGLISH`:
    1. Activate `whisperkit-large-v3-626mb`.
    2. Speak 10s in Japanese (or any non-European language).
    3. Confirm transcript is in the target language (auto-detect picks the right one).

**Exit:** all MV entries checked off in a single dogfood pass (or multiple passes if iteration needed). Note any deviations from expected behavior.

## Stage E — Close-out

### E.1 — BACKLOG.md update

**Files:**
- `BACKLOG.md` — #095 body update:
  - Status flip: `open` → `done`.
  - Add commit references (`<sha1>`, `<sha2>`, ...) for the Stage A/B/C/E commits.
  - Remove "Tier 1 — no candidates" and "Tier 2 — Whisper via WhisperKit (the actual scope)" — collapse into a "Shipped" summary line.
  - Keep Tier 3 reference notes intact (future).

**Don't commit per backlog conventions** unless user explicitly asks.

### E.2 — Commit + push

Per CLAUDE.md commit conventions: `phase-N step #095:` tag. Probably 2-3 commits:
- `phase-4 step #095.A: TranscriptionEngine.whisperKit + ChipFamily + descriptor fields + 5 catalog entries`
- `phase-4 step #095.B: WhisperKitTranscriberAdapter (pre-stage download + multi-result merge + Sendable-safe)`
- `phase-4 step #095.C: tests (adapter + catalog + chip-gating + Sendable boundary)`
- `phase-4 step #095.E: BACKLOG #095 done + manual-verification entries`

Push to trunk at end-of-phase.

## Risk + escalation

If any of these surface mid-implementation, **pause and re-circulate to review** rather than improvising:
- Stage A.0's tokenizer-folder discovery diverges from DESIGN's two assumed shapes.
- WhisperKit's `transcribe(audioArray:)` returns something other than `[TranscriptionResult]` at the pinned version.
- Tokenizer download hits an auth/rate limit that breaks first-run UX (HF anonymous downloads should work but worth confirming).
- Chip-gating test reveals a missing chip family (e.g. M1 Ultra reports differently).
- Multi-result merge breaks on long-form audio (>30s) in dogfood — adapter may need windowing-aware concat.

Each is a discovery worth a follow-up review pass, not a same-session improvisation.

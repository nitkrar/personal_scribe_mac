# #101 — WhisperKit streaming adapter (hermes brief)

**Bucket**: REBUILD #6 (WhisperKit streaming adapter)
**Author**: claude-atlas
**Target agent**: `codex-hermes` via agent-broker
**Trunk HEAD at dispatch**: `d08307c`
**Baseline (canonical path, no filter)**: `1473 tests, 0 failed, 1 skipped`
**Reference commits** (pre-reset, on tag `bookmark-before-reset-2026-05-20`): `5a0df9e` (initial streaming adapter + tracker + artifact store + tests) + `30afc64` (special-token strip + overlap merge follow-up)
**Mode**: serial single-agent — atlas dispatches hermes via agent-broker; squashes at end.

This brief follows the **shared-adapter design pattern** established by #100. **Do NOT add a `.whisperKitStreaming` engine case or separate streaming descriptors.** WhisperKit's `.mlmodelc` artifacts work for both batch and streaming; one descriptor satisfies both kinds via capabilities, and one merged adapter actor owns the shared runtime resource.

---

## TL;DR

Add WhisperKit streaming alongside whisper.cpp streaming + parakeet streaming. **Follows the same shape as #100's unified `WhisperCppAdapter`**: one `WhisperKitAdapter` actor conforming to both `Transcriber` AND `StreamingTranscriber`, single underlying WhisperKit instance, both decode entry points share the same `audioEncoder` / `textDecoder` / `featureExtractor` / `segmentSeeker` / `tokenizer` graph. Streaming emits `.partial(text:)` for unconfirmed-tail updates and `.endOfUtterance(text:)` once per state change that brings new confirmed segments (text = the confirmed delta). No separate VAD/EoU layer — WhisperKit's internal confirmed/unconfirmed split is the boundary.

Catalog: extend `.whisperKit.capabilities` to `[.asr, .streamingASR]`. No new engine case. No new descriptors. The existing 5 WhisperKit descriptors satisfy both kinds.

Force second-pass to whisper.cpp's rule extends to WhisperKit too: when streaming descriptor's engine is `.whisperKit` AND second-pass enabled, RecipeBuilder forces second-pass to the same descriptor (free reuse of the same WhisperKit instance).

---

## §Brief diff vs current trunk (post-#100)

Three things to know about state at dispatch (verified with grep, not memory):

1. **#100 just landed** (`bc27776`). Trunk has:
   - `TranscriptionEngine.capabilities: Set<ModelKind>` (singular `kind` removed)
   - `.whisperCpp.capabilities = [.asr, .streamingASR]` — dual-capability via shared adapter pattern
   - `WhisperCppAdapter` actor at `Sources/PersonalScribeTranscription/Adapters/WhisperCppAdapter.swift` conforming to both `Transcriber` AND `StreamingTranscriber`
   - `ModelBoundProcessorProvider.AdapterRecord` factory `.whisperCpp` case constructs ONE adapter, populates BOTH `transcriber:` AND `streamingTranscriber:` with same instance
   - `RecipeBuilder.buildStreamingSecondPassTranscriber` force-rule: when streaming descriptor engine is `.whisperCpp`, second-pass uses same descriptor
   - `ActiveModelService.setActive(_ descriptor:, forKind kind:)` per-section, NOT fan-out

   **#101 mirrors this exact pattern for `.whisperKit`.** Read `Sources/PersonalScribeTranscription/Adapters/WhisperCppAdapter.swift` as the canonical reference for the actor shape, and the #100 commit (`bc27776`) for the catalog/provider/RecipeBuilder hooks. This is NOT the pre-reset shape (which used a `.whisperKitStreaming` engine case + separate streaming descriptors). The pre-reset commits are useful ONLY for the streaming-specific internals (ledger, audio processor, EoU synthesis logic) — NOT for the catalog/engine/adapter-instance structure.

2. **WhisperKit batch adapter exists** at `Sources/PersonalScribeTranscription/Adapters/WhisperKitTranscriberAdapter.swift` as `public actor WhisperKitTranscriberAdapter: Transcriber`. This file will be **deleted and replaced** by a new merged `WhisperKitAdapter.swift` (mirror of `WhisperCppAdapter.swift`'s structure).

3. **`.whisperKit.capabilities` is currently `[.asr]`** at `Sources/PersonalScribeCore/Models/Selection/TranscriptionEngine+Kind.swift:13-14`. #101 extends to `[.asr, .streamingASR]`.

---

## What you're building

`Sources/PersonalScribeTranscription/Adapters/WhisperKitAdapter.swift` — `public actor` conforming to both `Transcriber` AND `StreamingTranscriber`. Composes:

- **Batch entry point** — `transcribe(audio:)` runs WhisperKit's one-shot transcription on a finite buffer. Same shape as today's `WhisperKitTranscriberAdapter.transcribe(audio:)`.
- **Streaming entry point** — `transcribe(stream:)` drives WhisperKit's `AudioStreamTranscriber` against a buffer-fed `AudioProcessing` implementation; emits `.partial(text:)` for unconfirmed-tail revisions and `.endOfUtterance(text:)` once per state change that brings new confirmed segments (text = the confirmed delta only).
- **Shared runtime resource** — a single `WhisperKit` instance (held inside an internal `LiveWhisperKitManager` actor / `@unchecked Sendable` class) provides `audioEncoder`, `textDecoder`, `featureExtractor`, `segmentSeeker`, `tokenizer` to both entry points. Batch + streaming never overlap in time within a session (streaming ends before second-pass starts), so explicit serialization isn't strictly needed for correctness, but the wrapping manager keeps the construction symmetric with `WhisperCppAdapter`.
- **`WhisperKitStreamingLedger`** — new sibling file at `Sources/PersonalScribeTranscription/Adapters/WhisperKitStreamingLedger.swift`. Pure value-type struct, no I/O. Consumes `WhisperKitStreamingState` snapshots (confirmed + unconfirmed segments) and decides whether the state change produces a `.partial`, an `.endOfUtterance`, or nothing. Includes the special-token strip + segment overlap merge logic from `30afc64`.

## Streaming event semantics (read this carefully — corrected per codex audit)

WhisperKit's `AudioStreamTranscriber` maintains an internal `confirmedSegments` vs `unconfirmedSegments` split. Each decode promotes all but the last `requiredSegmentsForConfirmation` segments into `confirmedSegments`. WhisperKit then advances its internal `lastConfirmedSegmentEndSeconds` and clips future decodes to start after that frontier — so already-confirmed audio is never re-decoded. This is structurally different from whisper.cpp (which re-decoded overlapping windows from session start and forced us to build an external `WhisperCppStableSegmentTracker`).

`confirmedSegments` is a **stable-prefix confirmation boundary**, NOT a true "utterance ended" signal. It fires whenever segment count exceeds `requiredSegmentsForConfirmation`, regardless of silence or sentence boundary. We treat each such transition as an `.endOfUtterance(text:)` event carrying ONLY the delta of newly confirmed segments since the previous emission — this matches the existing `StreamingTranscriber` event contract and lets `LiveCursorOutput.deliverPartial` paste confirmed text without any orchestrator changes.

Event mapping on each `stateChangeCallback` snapshot:
- **`.endOfUtterance(text:)`** — when `newState.confirmedSegments.last?.end > lastEmittedConfirmedEnd`. Text is the delta: `joinedText(confirmed.filter { $0.end > lastEmittedConfirmedEnd })`. Update `lastEmittedConfirmedEnd` after emit.
- **`.partial(text:)`** — when `unconfirmedSegments` text changed since last emit (and there's no confirmed-delta to emit on the same snapshot). Text is the joined unconfirmed text; never includes confirmed segments.
- **No event** — when neither side changed.

The confirmed-delta-only emit is the load-bearing constraint. Pasting `currentText` or raw unconfirmed text would reintroduce whisper.cpp's duplicate-lane revision flicker via the cursor. Pasting only the confirmed delta is safe because WhisperKit's clipping guarantees those segments won't be revised.

`stateChangeCallback` fires on Argmax's internal queue (it's `@Sendable (oldState, newState) -> Void`). Bridge it into the adapter actor via `Task { await self?.record(snapshot) }`. **Watch for the AsyncStream subscription-race trap** (project memory `feedback_asyncstream_race_flakes_not_benign.md`): if you wrap state delivery through any continuation/broadcaster pattern, register before yield, and finish continuations on deinit.

`AudioStreamTranscriber`'s `useVAD` parameter is an internal decode-gating optimization (skip decode on silent buffers), NOT an EoU contract. Default value (`true`) is fine; set it if/as the implementation needs.

### Live cursor — stays ON for WhisperKit

The whisper.cpp gate landed in `11c0f99` (force `liveCursorEnabled=false` when streaming engine is `.whisperCpp`) does NOT extend to WhisperKit. Confirmed-delta-only emission means the dedup bug class that hit whisper.cpp cannot recur here — WhisperKit clips already-confirmed audio out of future decodes, so a confirmed segment is never re-emitted with different text. Live cursor for WhisperKit streaming remains user-controllable via the existing Settings toggle.

## Special-token strip + overlap merge (from `30afc64`)

WhisperKit segments occasionally contain raw Whisper special tokens like `<|0.00|>` or `<|notimestamps|>` in the segment text. The ledger MUST strip them before joining via regex `<\|[^|]*\|>`.

WhisperKit can also emit duplicate segments when decoding rewinds — the ledger MUST dedupe by merging segments whose timestamps overlap, keeping the longer text or word-overlap-joining via the `mergeOverlappingText` helper from `30afc64`.

Both behaviors live in the ledger's `joinedText([TranscriptionSegment])` overload. Pre-reset implementation is correct; cherry-pick the logic faithfully.

## Catalog + capability surface

**No new engine case. No new descriptors.** Just one change to existing infrastructure:

`Sources/PersonalScribeCore/Models/Selection/TranscriptionEngine+Kind.swift`:
```swift
case .whisperKit:
    return [.asr, .streamingASR]   // ← was [.asr]
```

That's it for the catalog. The existing 5 WhisperKit descriptors (`whisperkit-small-216mb`, `whisperkit-small-en-217mb`, etc. — find via grep) automatically appear in BOTH `.asr` AND `.streamingASR` picker sections. User picks "Whisper Small (WhisperKit)" from the streaming-mode picker → activates it as their `.streamingASR` model (per-section setActive from #100). Same model, same `.mlmodelc` files, same disk artifacts.

## Force second-pass extension

`Sources/PersonalScribeSession/WorkflowMode/RecipeBuilder.swift`, `buildStreamingSecondPassTranscriber`:

```swift
if case .streamingTranscriber(let streamingTranscriber) = streamingProcessor,
   let streamingDescriptor = streamingTranscriber.descriptor,
   streamingDescriptor.engine == .whisperCpp || streamingDescriptor.engine == .whisperKit {  // ← add .whisperKit
    return try processorProvider.transcriber(for: streamingDescriptor)
}
```

When streaming descriptor's engine is `.whisperKit` AND second-pass enabled, RecipeBuilder forces second-pass to the same descriptor. Same UX guarantee as whisper.cpp: no accidental mixing of WhisperKit streaming with parakeet TDT batch. Parakeet-streaming + WhisperKit-batch (or any other batch model) stays composable because the rule is conditioned on streaming engine, not on second-pass engine.

## Provider wiring

`Sources/PersonalScribeSession/Models/Selection/ModelBoundProcessorProvider.swift`:

```swift
case .whisperKit:
    let adapter = WhisperKitAdapter(
        descriptor: descriptor,
        storageLocator: storageLocator,
        logger: logger
    )
    return AdapterRecord(
        descriptorID: descriptor.id,
        transcriber: adapter,
        streamingTranscriber: adapter
    )
```

Same shape as #100's `.whisperCpp` case. ONE adapter instance, BOTH slots populated.

## Lifecycle / idle release

Per req-0050: `WhisperKitAdapter` MUST implement `releaseIdleResources()`. Mirror the shape from `WhisperCppAdapter`:
- 30s delayed unload
- Generation-counter cancellation guard
- Emit `adapter_idle_release` info log on transition
- Both `transcribe(audio:)` and `transcribe(stream:)` entry points reset the timer
- `prepare()` cancels any pending idle-release before loading

The shared `WhisperKit` instance is what gets unloaded. Argmax's `WhisperKit.unloadModels()` frees the CoreML models.

## Audio processor seam

WhisperKit's `AudioStreamTranscriber` expects an `AudioProcessor` conforming to Argmax's protocol. The pre-reset adapter introduced `BufferFedWhisperKitAudioProcessor` at `Sources/PersonalScribeTranscription/Adapters/BufferFedWhisperKitAudioProcessor.swift` — a custom processor that accepts `[Float]` samples via `append(samples:)` rather than reading from a microphone. Lift this file from `5a0df9e` mostly unchanged. Hook it into the streaming entry point: each incoming `PCMBuffer` from `transcribe(stream:)` → `processor.append(samples: buffer.samples)`.

## Artifact handling

The pre-reset shipped a separate `WhisperKitArtifactStore.swift`. **Don't ship that as a separate file.** Instead, lift the artifact logic INTO `WhisperKitAdapter.swift` (or keep a minimal struct inside the same file if needed). This is the same call atlas+user made for `WhisperCppAdapter` — `WhisperCppArtifactStore` was kept as a shared helper because BOTH batch and streaming needed it; for WhisperKit, ONE merged adapter means one user. Don't add a layer for ceremony.

Today's `WhisperKitTranscriberAdapter.swift` already has download / model-folder resolution code. Move that into the merged `WhisperKitAdapter.swift` along with the new streaming entry point.

## Observability

Per `INSTRUMENTATION_PRINCIPLES.md`:
- `streaming_adapter_summary` info log at session end. Match the shape from `FluidAudioStreamingTranscriberAdapter` + `WhisperCppAdapter`'s streaming summary: `descriptorID=… bufferCount=… partialCount=… eouCount=… outcome=… finalTextEmpty=… audioDurationMs=…`
- `streaming_eou_emitted` info log per EoU (sparse; ≤5/session)
- `adapter_idle_release` info log on idle-release transitions
- **NO per-buffer / per-decode info logs.** Per-stateChange callback fires often — that's debug-only territory, defer to #096.

## Concurrency / Sendable

- `public actor WhisperKitAdapter` — matches `WhisperCppAdapter` shape
- `nonisolated func transcribe(stream:)` returns `AsyncThrowingStream` directly; work runs in a spawned Task
- `nonisolated func transcribe(audio:)` same pattern for batch
- `WhisperKitStreamingLedger` is a value-type `struct` (Sendable), lives in stack frame of `executeTranscription`
- `LiveWhisperKitManager` (actor OR `@unchecked Sendable` final class with internal queue): the WhisperKit instance + audio processor + transcriber task live here
- `@preconcurrency import WhisperKit` to suppress Sendable warnings from Argmax's types — same as pre-reset

---

## Project guardrails

- Read `~/Projects/nitkrar/personal_scribe/CLAUDE.md`, `~/Projects/nitkrar/CLAUDE.md`, `~/Projects/nitkrar/personal_scribe/AGENTS.md`, `docs/INSTRUMENTATION_PRINCIPLES.md`, `Sources/PersonalScribeTranscription/Adapters/WhisperCppAdapter.swift` (the structural reference) before touching code.
- **Rigid TDD** for the ledger + state machine: failing test first, then minimal code.
- **Flexible TDD** for the live WhisperKit wrapper (C-interop-adjacent). Keep the protocol seam (`WhisperKitStreamingManaging` or equivalent) so tests drive the adapter against a stub.
- **Commit tag**: `phase-1 step 101.N: <test names>`. Squash to ONE final commit by atlas before push.
- **No `swift test` from worktree** (Santa quirk). `swift build --build-tests` per chunk. Atlas runs `swift test` from canonical path at end.
- File staging: name files explicitly to `git add` (never `-A`).
- Trunk-only.
- **Do NOT stage `BACKLOG.md` or `plans/REBUILD_BACKLOG.md`** — atlas owns those at squash time.

## Pre-flight grep (run first; surface CONCERNS if any claim doesn't match trunk)

```bash
# Confirm WhisperKit batch adapter exists at expected path
ls Sources/PersonalScribeTranscription/Adapters/WhisperKitTranscriberAdapter.swift

# Confirm capability set is on TranscriptionEngine post-#100
grep -nE "capabilities" Sources/PersonalScribeCore/Models/Selection/TranscriptionEngine+Kind.swift

# Confirm WhisperCppAdapter is the structural reference
ls Sources/PersonalScribeTranscription/Adapters/WhisperCppAdapter.swift

# Confirm provider's .whisperCpp case populates BOTH slots
grep -nB2 -A12 "case .whisperCpp:" Sources/PersonalScribeSession/Models/Selection/ModelBoundProcessorProvider.swift

# Confirm RecipeBuilder's force-second-pass rule exists for .whisperCpp
grep -nB1 -A8 "engine == .whisperCpp" Sources/PersonalScribeSession/WorkflowMode/RecipeBuilder.swift

# Pre-reset reference commits (READ-ONLY via tag; do NOT cherry-pick)
git show 5a0df9e --stat | grep -E "WhisperKit"
git show 30afc64 --stat | grep -E "WhisperKit"
```

Any mismatch → surface as CONCERNS before implementing.

---

## Implementation checklist (4 chunks)

### Chunk 1: `WhisperKitStreamingLedger.swift` + tests

Goal: pure value-type ledger that decides the next event (`.partial`, `.endOfUtterance`, or none) from `WhisperKitStreamingState` snapshots. No I/O.

- [ ] New file `Sources/PersonalScribeTranscription/Adapters/WhisperKitStreamingLedger.swift`
- [ ] `struct WhisperKitStreamingState: Sendable, Equatable { confirmedSegments: [TranscriptionSegment]; unconfirmedSegments: [TranscriptionSegment] }` (use Argmax's `TranscriptionSegment` type via `@preconcurrency import WhisperKit`)
- [ ] `struct WhisperKitStreamingLedger` (Sendable):
  - [ ] `mutating func consume(_ state: WhisperKitStreamingState) -> [StreamingTranscriptionEvent]` — returns `.partial(text:)` and `.endOfUtterance(text:)` events per locked design
  - [ ] `func finalText(fallbackState:) -> String` — for session-end finalized event
  - [ ] Internal trackers: `lastCommittedSegmentEndSeconds: Float`, `committedUtterances: [String]`, `currentPartialText: String`, `lastEmittedPartialText: String`
- [ ] Special-token strip (`<\|[^|]*\|>` regex) inside `sanitizePiece(_:)` per `30afc64`
- [ ] Overlap merge (`TimedText` struct + `mergeOverlappingText(base:next:)`) per `30afc64`
- [ ] `joinedText([TranscriptionSegment])` overload runs sanitize + overlap-merge
- [ ] Tests in `Tests/PersonalScribeTranscriptionTests/Adapters/WhisperKitStreamingLedgerTests.swift`:
  - [ ] `testConsumeEmitsPartialForUnconfirmedSegments`
  - [ ] `testConsumeEmitsEndOfUtteranceWhenNewConfirmedSegmentsAppear`
  - [ ] `testConsumeAdvancesWatermarkSoNextCallDoesNotReEmit`
  - [ ] `testJoinedTextStripsSpecialTokensFromSegments` (from `30afc64`)
  - [ ] `testPartialEventEmittedAfterStrippingHasNoSpecialTokens` (from `30afc64`)
  - [ ] `testEndOfUtteranceTextHasNoSpecialTokens` (from `30afc64`)
  - [ ] `testOverlappingSegmentsAreMergedIntoOneTimedText` — synthesize 2 segments with overlapping start/end; assert the merged output has the longer text once
  - [ ] `testFinalTextFallsBackToFallbackStateWhenLedgerEmpty`
- [ ] `swift build --build-tests` green
- [ ] Commit: `phase-1 step 101.1: WhisperKitStreamingLedger (testConsumeEmitsPartial..., testConsumeEmitsEndOfUtterance..., testJoinedTextStripsSpecialTokens..., ...)`

### Chunk 2: `BufferFedWhisperKitAudioProcessor.swift`

Goal: lift the custom audio processor from `5a0df9e` mostly unchanged. Implements Argmax's `AudioProcessor` protocol with an `append(samples: [Float])` entry point so our `PCMBuffer` stream can feed WhisperKit.

- [ ] New file `Sources/PersonalScribeTranscription/Adapters/BufferFedWhisperKitAudioProcessor.swift`
- [ ] Mirror the pre-reset implementation. **Do not change buffer-sizing logic or threading model** — pre-reset values are empirically tuned for Argmax's expectations.
- [ ] If Argmax's `AudioProcessor` API has changed since pre-reset (`5a0df9e` was 2026-05-19), adapt method signatures but keep the buffer-feeding semantics
- [ ] No new tests for this file directly — it's covered indirectly by Chunk 3's adapter tests via stub `WhisperKitStreamingManaging`
- [ ] `swift build --build-tests` green
- [ ] Commit: `phase-1 step 101.2: BufferFedWhisperKitAudioProcessor (no new tests; covered by Chunk 3 stub-driven adapter tests)`

### Chunk 3: `WhisperKitAdapter.swift` — merged adapter (replaces batch + adds streaming)

Goal: ONE actor conforming to both `Transcriber` and `StreamingTranscriber`, single underlying WhisperKit instance.

- [ ] New file `Sources/PersonalScribeTranscription/Adapters/WhisperKitAdapter.swift`
- [ ] Delete `Sources/PersonalScribeTranscription/Adapters/WhisperKitTranscriberAdapter.swift` (batch logic migrates into the new file)
- [ ] `public actor WhisperKitAdapter: Transcriber, StreamingTranscriber`
- [ ] `protocol WhisperKitStreamingManaging: Sendable` — stub seam for tests. Exposes:
  - [ ] `func loadModel(modelName:modelFolder:tokenizerFolder:) async throws`
  - [ ] `func start() async throws`
  - [ ] `func appendAudioSamples(_:) async throws -> [WhisperKitStreamingState]`
  - [ ] `func finish() async throws -> [WhisperKitStreamingState]`
  - [ ] `func cleanup() async`
  - [ ] Batch-side: `func transcribe(audioSamples:languageHint:) async throws -> WhisperKitManagerResult` (or merge into one protocol; your judgment)
- [ ] `LiveWhisperKitManager` implements the protocol, holds the `WhisperKit` instance + `BufferFedWhisperKitAudioProcessor` + `AudioStreamTranscriber` for streaming
- [ ] Single `prepare()` loads the WhisperKit instance; idempotent across both call paths
- [ ] Single `cleanup()` unloads
- [ ] `releaseIdleResources()` per req-0050: 30s delayed cleanup, generation-counter cancellation, `adapter_idle_release` info log
- [ ] `downloadIfNeeded()` + `modelDownloadProgress()` mirror today's `WhisperKitTranscriberAdapter` shape
- [ ] **Batch entry point** `transcribe(audio:)` — preserves today's `WhisperKitTranscriberAdapter.transcribe(audio:)` behavior verbatim (same params, same output shape)
- [ ] **Streaming entry point** `transcribe(stream:)` — for-await over `PCMBuffer`, feeds `audioProcessor.append(samples:)`, polls `manager.appendAudioSamples` → `ledger.consume(state)` → emit events. On stream end: `manager.finish()` → emit final ledger output as `.finalized(...)`
- [ ] `AudioStreamTranscriber` constructed with `requiredSegmentsForConfirmation: 2`, `stateChangeCallback: { [weak self] old, new in Task { await self?.record(snapshot) } }`. `useVAD` left at default (`true`) — decode-gating optimization only, not part of the EoU contract.
- [ ] Watch for AsyncStream subscription-race trap (memory `feedback_asyncstream_race_flakes_not_benign.md`): if you wrap stateChangeCallback through any broadcaster, register-before-yield + finish-on-deinit
- [ ] Cancellation handling: `try Task.checkCancellation()` in loop; `CancellationError` finishes stream without throw
- [ ] `streaming_adapter_summary` info log at session end
- [ ] Tests in `Tests/PersonalScribeTranscriptionTests/Adapters/WhisperKitAdapterTests.swift`:
  - [ ] **Migrate** existing `WhisperKitTranscriberAdapterTests` here verbatim — batch behavior must not regress
  - [ ] `testPrepareIdempotentAcrossBatchAndStreamingCallSites`
  - [ ] `testTranscribeStreamEmitsPartialsFromUnconfirmedSegments`
  - [ ] `testTranscribeStreamEmitsEndOfUtteranceFromConfirmedWatermark`
  - [ ] `testTranscribeStreamFinalizedYieldsLedgerFullTextAtEnd`
  - [ ] `testCancellationStopsStreamWithoutThrow`
  - [ ] `testBatchAndStreamingShareSameUnderlyingWhisperKitInstance` — assert stub `loadModel` call count == 1 after running both batch + streaming sequentially against the same adapter instance
  - [ ] `testReleaseIdleResourcesUnloadsAfterDelay`
  - [ ] `testReleaseIdleResourcesIsCancelledIfNewSessionStartsBeforeDelay`
  - [ ] `testStreamingAdapterSummaryLogIncludesExpectedFields`
- [ ] `swift build --build-tests` green
- [ ] Commit: `phase-1 step 101.3: WhisperKitAdapter unified (Transcriber + StreamingTranscriber, single WhisperKit instance) — drops WhisperKitTranscriberAdapter`

### Chunk 4: Catalog capability + provider wiring + RecipeBuilder force-rule extension + tests

Goal: hook the merged adapter into the engine taxonomy, provider routing, and RecipeBuilder's force-second-pass rule. Existing 5 WhisperKit descriptors automatically gain streaming capability.

- [ ] `Sources/PersonalScribeCore/Models/Selection/TranscriptionEngine+Kind.swift`: `.whisperKit` capabilities → `[.asr, .streamingASR]`
- [ ] `Sources/PersonalScribeSession/Models/Selection/ModelBoundProcessorProvider.swift`: `.whisperKit` AdapterRecord factory constructs ONE `WhisperKitAdapter`, populates BOTH `transcriber:` AND `streamingTranscriber:` with same instance. Mirror the `.whisperCpp` case.
- [ ] `Sources/PersonalScribeSession/WorkflowMode/RecipeBuilder.swift`: extend the force-second-pass conditional. Change `streamingDescriptor.engine == .whisperCpp` to `streamingDescriptor.engine == .whisperCpp || streamingDescriptor.engine == .whisperKit`.
- [ ] Update `TranscriptionEngineCapabilitiesTests` (`Tests/PersonalScribeCoreTests/Models/Selection/TranscriptionEngineCapabilitiesTests.swift`): change `testWhisperKitHasASRCapability` to `testWhisperKitHasBatchAndStreamingCapabilities` asserting `[.asr, .streamingASR]`
- [ ] Update `BuiltInModelCatalogTests`: any test asserting WhisperKit descriptors appear only in `.asr` lookups should now assert they ALSO appear in `.streamingASR` lookups
- [ ] Update `ModelBoundProcessorProviderTests`: add `testWhisperKitDescriptorResolvesSameInstanceAsBothBatchAndStreaming` mirroring the WhisperCpp version
- [ ] Update `RecipeBuilderTests`: add `testStreamingSecondPassForcesWhisperKitWhenStreamingIsWhisperKit` mirroring the WhisperCpp version (assert second-pass matches streaming descriptor AND active-`.asr` descriptor is NOT requested)
- [ ] `swift build --build-tests` green
- [ ] Commit: `phase-1 step 101.4: WhisperKit dual-capability + provider + force-second-pass (testWhisperKitHasBatchAndStreamingCapabilities, testWhisperKitDescriptorResolvesSameInstanceAsBothBatchAndStreaming, testStreamingSecondPassForcesWhisperKitWhenStreamingIsWhisperKit)`

### Chunk 5: Pre-DONE verification

- [ ] `swift test --filter WhisperKitStreamingLedgerTests` (8 tests)
- [ ] `swift test --filter WhisperKitAdapterTests` (~12 tests including migrated batch tests)
- [ ] `swift test --filter TranscriptionEngineCapabilitiesTests` (7 tests, one updated)
- [ ] `swift test --filter ModelBoundProcessorProviderTests`
- [ ] `swift test --filter RecipeBuilderTests`
- [ ] `swift test (full)` from canonical path — expect 1473 + ~15-20 net new tests = ~1488-1493/0/1. Zero new failures.
- [ ] No commit for this chunk — verification only

---

## DONE message (per AGENTS.md)

```
DONE | req-NNNN | commit=<last-intermediate-sha>
Subject: phase-1 step 101.1..101.4: WhisperKit unified adapter + streaming (4 sub-commits, atlas will squash)
Tests:
  - swift build --build-tests
  - swift test --filter WhisperKitStreamingLedgerTests
  - swift test --filter WhisperKitAdapterTests
  - swift test --filter TranscriptionEngineCapabilitiesTests
  - swift test --filter ModelBoundProcessorProviderTests
  - swift test --filter RecipeBuilderTests
  - swift test (full)
Full suite: <count>/0 failed/1 skipped (delta vs baseline 1473/0/1: +<N> new tests)
Launch gate: not applicable on this machine (Santa reapproval owned by user; full-suite swift test is the operative gate per AGENTS.md exception)
Manual verification: not applicable (atlas will dogfood after install)
Notes: BACKLOG.md + plans/REBUILD_BACKLOG.md NOT touched. Atlas owns at squash time.
```

---

## What atlas does on receipt

1. `git log --oneline <first-101-commit>..HEAD`
2. `swift test` from canonical path
3. 5x flake-check loop
4. Spawn `10x-engineer:code-reviewer`
5. (Optional) ad-hoc-codex second-opinion review for the ledger logic (per memory `feedback_construct_fresh_test_inputs.md` — independent test input synthesis catches what 10x misses on tracker-style code)
6. Squash to one `feat: WhisperKit streaming adapter + unified WhisperKitAdapter #101` commit
7. Move `plans/REBUILD_BACKLOG.md` row #6 to Done
8. Stop before push

---

## If you hit a blocker

- Surface via `BLOCKER` / `CONCERNS` tag in the side room.
- **Do NOT add a `.whisperKitStreaming` engine case.** The shared-adapter pattern is locked.
- **Do NOT split WhisperKit descriptors** into batch + streaming variants. Existing 5 descriptors satisfy both.
- **Do NOT bolt a separate VAD/EoU layer onto WhisperKit streaming.** The `.endOfUtterance` event comes from WhisperKit's internal confirmation watermark (delta of newly confirmed segments). `AudioStreamTranscriber.useVAD` is just an internal decode-gating optimization and is unrelated to the EoU contract.
- **Do NOT re-introduce `WhisperKitArtifactStore` as a separate file.** Lift the artifact logic into `WhisperKitAdapter.swift`.
- Don't run `swift test` from worktree.

## References for in-flight grep

```bash
# The structural reference for the merged-adapter pattern:
cat Sources/PersonalScribeTranscription/Adapters/WhisperCppAdapter.swift

# Current WhisperKit batch adapter (to be replaced):
cat Sources/PersonalScribeTranscription/Adapters/WhisperKitTranscriberAdapter.swift

# Pre-reset streaming logic (READ-ONLY for ledger + audio processor structure):
git show 5a0df9e -- Sources/PersonalScribeTranscription/Adapters/WhisperKitStreamingTranscriberAdapter.swift
git show 5a0df9e -- Sources/PersonalScribeTranscription/Adapters/BufferFedWhisperKitAudioProcessor.swift
git show 30afc64 -- Sources/PersonalScribeTranscription/Adapters/WhisperKitStreamingTranscriberAdapter.swift

# Streaming protocol contract:
cat Sources/PersonalScribeCore/Transcription/StreamingTranscriber.swift

# Existing summary log shape (template for streaming_adapter_summary):
grep -B2 -A2 "streaming_adapter_summary" Sources/PersonalScribeTranscription/Adapters/WhisperCppAdapter.swift

# Provider dispatch (mirror .whisperCpp case for .whisperKit):
sed -n '40,80p' Sources/PersonalScribeSession/Models/Selection/ModelBoundProcessorProvider.swift

# RecipeBuilder force-rule (extend conditional):
grep -nB2 -A10 "engine == .whisperCpp" Sources/PersonalScribeSession/WorkflowMode/RecipeBuilder.swift
```

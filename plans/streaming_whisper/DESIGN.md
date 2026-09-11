# Streaming Whisper for Live Dictation — DESIGN (parent)

Status: design-only parent. Children are runtime-specific:
- `WHISPERKIT_DESIGN.md` — WhisperKit `AudioStreamTranscriber` adapter.
- `WHISPERCPP_DESIGN.md` — whisper.cpp adapter with adapter-owned stability tracker.

This plan supersedes the earlier "streaming deferred" notes in:

- `plans/095_whisperkit/DESIGN.md`
- `plans/098_whispercpp/DESIGN.md`

for streaming only. The shipped batch surfaces from #095 and #098 stay unchanged.

## Pending edits — req-0028 WhisperKit review

Current trunk still contains only this parent plan; the referenced `WHISPERKIT_DESIGN.md` child file is not present yet. The WhisperKit-specific Phase 1 notes below are therefore tightened here to capture the verified `argmax-oss-swift 1.0.0` constraints: the buffer-fed bridge cannot rely on upstream `AudioProcessor.processBuffer(_:)` because that symbol is not public outside WhisperKit, the first confirmation window should stay at 2 segments until dogfood proves 1 is safe, `.partial` must be derived from the unstable segment suffix rather than `currentText`, and v1 finalization should continue to flow through the existing `streamingSecondPassTranscriber` path instead of adding a batch decode inside the streaming adapter.

## Sibling work — IN PROGRESS (do not duplicate)

The FluidAudio streaming adapter is being repaired in a parallel session:

- Plan: `plans/056_streaming_dictation/FOLLOWUP_vad_boundary.md`
- Tracking: req-0026 (codex-hermes, in-flight)

What that work delivers that this plan **inherits, must not duplicate**:

1. **Live-cursor instrumentation infrastructure.** The FluidAudio fix lands event-driven logs at adapter / orchestrator / sink layers with a shared shape (`session=<uuid> utterance=<n> ms_since_session_start=<monotonic>`). WhisperKit + whisper.cpp adapters use the same shape; do NOT add a parallel `StreamingTimings` struct or a separate logging scheme.
2. **EOU silence threshold as a global setting.** `StreamingEouSilenceThresholdMs` (default 1000) is added in Settings → General by the FluidAudio fix and is intended to apply to any adapter that uses VAD-driven EOU. WhisperKit's `useVAD = false` recommendation in the child plan doesn't consume this; whisper.cpp should consume it through the existing `VadBoundaryStreamingTranscriber` seam so the shared threshold controls when stabilized text flushes as `.endOfUtterance`.
3. **No-reset multi-utterance discipline.** The FluidAudio fix establishes that adapters preserve cumulative state across utterances and derive deltas. Whisper adapters that emit incremental confirmed segments don't need this exact pattern, but the principle (the adapter handles the multi-utterance contract entirely, no upstream `reset()` between utterances) stays.

What that work does NOT cover and is open scope here:

- New `.streamingASR` runtimes (WhisperKit + whisper.cpp adapters).
- Model-catalog descriptors for streaming variants.
- Real-runtime adapter tests for the new adapters.
- Default `.streamingASR` seeding for fresh installs (one-line fix in `ActiveModelService`).

Ground truth inputs for this design:

- Product semantics and current streaming contract: `plans/056_streaming_dictation/DESIGN.md`
- Current bug and latency findings on the FluidAudio path (req-0021): `plans/investigations/2026-05-19-056-eou-second-utterance-latency-codex.md`
- Adversarial alternatives pass (req-0022): `plans/investigations/2026-05-19-056-vad-reset-eou-adversarial-codex.md`

## 1. Goal

Ship streaming dictation with feature-parity adapters for two additional runtimes:

1. WhisperKit via `AudioStreamTranscriber`
2. whisper.cpp via the pinned `WhisperFramework` XCFramework

Both new runtimes must conform to the existing `StreamingTranscriber` surface so:

- `SessionPipelineOrchestrator.consumeLiveStreamingEvent(...)` keeps its current logic
- `LiveCursorOutput.deliverPartial(...)` keeps its current append-only chunk delivery logic
- the second-pass batch finalizer remains the existing `streamingSecondPassTranscriber` path

## 2. Non-negotiable invariants

The design is load-bearing only if these stay true:

- `StreamingTranscriber` remains buffer-fed. Ninimma capture stays the single owner of the microphone.
- `StreamingTranscriptionEvent` remains the contract:
  - `.partial(text:)`
  - `.endOfUtterance(text:)`
  - `.finalized(result:)`
- `StreamingTranscriptAccumulator` remains valid because adapters emit:
  - `.partial` as the unstable trailing text only
  - `.endOfUtterance` as new append-only stable chunk text only
  - `.finalized` as full-session final text
- `consumeLiveStreamingEvent(...)` and `LiveCursorOutput` require zero semantic changes for new runtimes.
- FluidAudio streaming remains the default path until Phase 3 data says otherwise.
- No upstream forks.
- No new model downloads unless a runtime absolutely forces them.
- No speculative `workflow-modes.json` schema widening in v1.

## 3. Verified current state

### 3.1 The live streaming seam is already the right shape

The repo already has the correct top-level live-stream architecture:

- `StreamingTranscriber` consumes `AsyncThrowingStream<PCMBuffer, Error>`
- `SessionPipelineOrchestrator.consumeCaptureStream(...)` fans each live `PCMBuffer` to:
  - `bufferedAudio`
  - the live streaming input continuation
  - optional VAD auto-stop
- `consumeLiveStreamingEvent(...)` updates the StreamCard on `.partial` and `.endOfUtterance`
- `LiveCursorOutput` only appends on `.endOfUtterance`
- `runBoundStreamingTranscription(...)` already resolves:
  - streaming final fallback
  - optional authoritative second pass

That means this ticket is not a streaming-architecture rewrite. It is an adapter-layer expansion only.

### 3.2 Model-selection axis already exists

No new mode field for runtime choice is needed:

- `ModelKind.streamingASR` already exists.
- `ProcessorSpec.streamingTranscriber(kind:descriptorID:)` already persists a per-mode pin.
- `ActiveModelService` already keeps a separate active slot for `.streamingASR`.
- `ModeDetailView` already switches its picker to `.streamingASR` when `realtimeOn == true`.

What is missing today is more than one useful `.streamingASR` runtime.

### 3.3 Fresh installs do not currently seed `.streamingASR`

`ActiveModelService` seeds `.asr` only. This works in the current repo state because there's only one streaming runtime. For a selector-based rollout that promises "default to FluidAudio," explicit seeding is required.

Phase 1 of the rollout (see §6) adds this seed.

## 4. Head-to-head runtime matrix

| Runtime | Latency hypothesis | Accuracy / product fit | Multi-utterance story | Adapter complexity | Dependency risk |
| --- | --- | --- | --- | --- | --- |
| FluidAudio Parakeet EOU (current, being repaired in `FOLLOWUP_vad_boundary.md`) | ~1s VAD silence + decode overhead post-fix | Strong English live dictation fit | VAD-boundary delta-derived per fix | Already shipped + repaired | Current upstream EOU latch was the original problem |
| WhisperKit streaming | `~1.1s–1.8s` floor on Apple Silicon (`AudioStreamTranscriber` waits for `>1s` unread audio, polls every `100ms`) | Best multilingual fit; same on-disk assets as batch WhisperKit | Native confirmed/unconfirmed segment model | Medium | Low; same dependency already shipped for batch |
| whisper.cpp streaming | Dogfood-only unknown at design time; `tiny`/`small-q5_1` are plausible and `large-v3-turbo-q5_0` is the risky outlier | Good multilingual/offline fit; more tunable than WhisperKit | Adapter-owned stability tracker plus shared VAD-boundary EOU flush | High | Medium; no new dependency, but custom glue |

Observations:

- WhisperKit is the lower-scope streaming addition because it already ships a real streaming state machine.
- whisper.cpp is the higher-control path, taking on a custom sliding-window algorithm.
- Neither new runtime should replace FluidAudio by assumption.
- Phase 3 data decides default-runtime policy later.

## 5. Model catalog impact

### 5.1 Recommended v1 streaming catalog

Do not mirror every batch Whisper descriptor into streaming on day one.

Recommended rollout:

- Phase 1 (WhisperKit): `whisperkit-streaming-small-216mb`
- Phase 2 (whisper.cpp): `whispercpp-streaming-tiny`, `whispercpp-streaming-small-q5_1`

Deferred: larger WhisperKit rows, `whispercpp-large-v3-turbo-q5_0`.

Reason: selector ships useful choices, not every imaginable row. Larger rows are most likely to miss live-latency expectations.

### 5.2 Artifact reuse

No new downloads.

- WhisperKit streaming reuses `openai_whisper-small_216MB`.
- whisper.cpp streaming reuses `whispercpp-tiny` / `whispercpp-small-q5_1`.

Aliasing rule: whisper.cpp artifact reuse is descriptor-shape reuse, not magic runtime detection. A streaming descriptor that wants to share on-disk bits with a batch descriptor must intentionally keep the same `repoFolderName` and `requiredRelativePaths`; the extracted `WhisperCppArtifactStore` should remain a thin wrapper around that existing batch-adapter logic so shared rows stay in sync on ready/delete state.

## 6. Mode-config impact

### 6.1 `processors.descriptorID` is sufficient

No new mode field needed to select the streaming engine. The descriptor already identifies both runtime and model.

### 6.2 `streamingBehavior` stays unchanged in v1

Do not widen `StreamingBehaviorSpec` for:

- decode cadence
- confirmation window
- internal VAD tuning

Those remain adapter constants in v1.

Reason: no evidence yet that users need per-mode control. Widening here would be speculative. The repo already has a clean place to add a coarse preset later if dogfood demands it.

`StreamingEouSilenceThresholdMs` (global setting, added by FluidAudio fix) is consumed only by adapters that use VAD-driven EOU detection. WhisperKit doesn't (uses LocalAgreement). whisper.cpp should: it needs the existing `VadBoundaryStreamingTranscriber` seam so the shared threshold decides when newly stabilized text flushes as `.endOfUtterance`, while the adapter-owned stability tracker stays responsible for partial-vs-stable text.

## 7. Test strategy

### 7.1 Real-runtime adapter tests are mandatory

The req-0021 bug happened because current tests stubbed exactly the wrong thing.

Therefore:

- adapter-level streaming tests for WhisperKit and whisper.cpp must run the real runtime
- they must consume real audio fixtures
- they must not use fake managers for the core event-translation contract

### 7.2 Fixture location

Add:

- `Tests/PersonalScribeTranscriptionTests/Fixtures/Streaming/en-two-utterances-16k.wav`
- `Tests/PersonalScribeTranscriptionTests/Fixtures/Streaming/en-single-utterance-16k.wav`
- optional Phase-2 multilingual fixture: `Tests/PersonalScribeTranscriptionTests/Fixtures/Streaming/ja-two-utterances-16k.wav`

Add test-target resources in `Package.swift` for this fixture directory.

### 7.3 Skip policy

Real-runtime tests skip when required model artifacts are not already present locally. They must not auto-download in test bodies. Keeps tests real without making them network-dependent.

### 7.4 Required cases — common across both adapters

Per-child plans add their own runtime-specific cases. Both adapters must cover at minimum:

- two-utterance clip emits two ordered stable chunks
- `.partial` never replays confirmed text
- graceful stop emits exactly one terminal `.finalized`
- immediate cancel emits no terminal final

### 7.5 Orchestrator-level tests

- unchanged live cursor ordering assertions still pass with real-runtime smoke coverage from each new adapter
- second-pass fallback semantics stay unchanged

### 7.6 Manual verification

Add runbook entries in:

- `Tests/ManualVerifications/ManualSettingsVerification.md`
- `Tests/ManualVerifications/ManualTranscriptionVerification.md`
- `Tests/ManualVerifications/ManualModesVerification.md`

Required manual checks:

- switch `.streamingASR` between FluidAudio, WhisperKit, and whisper.cpp without touching `.asr`
- live cursor appends one chunk at a time with no duplication
- stop-time authoritative final still comes from second pass when enabled
- pinned mode using Whisper streaming behaves differently from the global default streaming selector

## 8. Phased rollout

### Phase 1 — WhisperKit streaming behind selector, default still FluidAudio

Purpose:

- ship the lower-scope Whisper streaming path first
- keep current product default unchanged

Details in `WHISPERKIT_DESIGN.md`.

#### WhisperKit constraints validated against current trunk

- `WhisperKitConfig` really does accept an injected `audioProcessor`, but the pinned `argmax-oss-swift 1.0.0` checkout does **not** expose `AudioProcessor.processBuffer(_:)` as a public API. Phase 1 therefore needs a Ninimma-owned `AudioProcessing` implementation, or an `AudioProcessor` subclass with its own public ingest method, instead of relying on a direct call into upstream `processBuffer(_:)`. `AudioStreamTranscriber.startStreamTranscription()` still performs `AudioProcessor.requestRecordPermission()` and calls `startRecordingLive`, so the injected processor must no-op capture start/stop while Ninimma remains the microphone owner.
- Start with `useVAD = false`, but keep `requiredSegmentsForConfirmation = 2` for v1. Disabling WhisperKit VAD keeps it off the shared VAD-driven EOU threshold path and avoids double-gating capture, while `2` matches the upstream `AudioStreamTranscriber` default and the shipped examples. Dropping to `1` should be a later dogfood tuning step only if it clearly improves latency without over-emitting stable text.
- Translate WhisperKit state changes from `confirmedSegments` + `unconfirmedSegments`, not from `currentText`. `currentText` is whole-progress text and upstream CLI code still carries a TODO to strip repeats. The adapter ledger should treat `confirmedSegments` as an append-only high-water-marked prefix and emit `.endOfUtterance` only for newly confirmed segments; revisions inside the unconfirmed suffix are expected and should surface only as `.partial`.
- Keep v1 finalization out of the streaming adapter. `runBoundStreamingTranscription(...)` already resolves the streaming fallback result and then optionally runs the authoritative batch second pass, so the streaming adapter should finish with at most the streamed `.finalized(...)` view of the session. If the streaming path and the bound `.asr` second pass both use WhisperKit, release the streaming runtime before the second pass to avoid double-loading CoreML weights in the same stop path.
- `WhisperKitArtifactStore` is still a clean extraction, but it should stay disk-only. Share the existing model-directory, staging, download, and artifact-validation helpers from `WhisperKitTranscriberAdapter`; leave `WhisperKitConfig` creation and runtime-manager wiring in the batch and streaming adapters themselves.

Files-touched estimate:

- `Package.swift`
- `Sources/PersonalScribeCore/Models/Selection/ModelDescriptor.swift`
- `Sources/PersonalScribeCore/Models/Selection/TranscriptionEngine+Kind.swift`
- `Sources/PersonalScribeCore/Models/Selection/TranscriptionEngine+Codable.swift`
- `Sources/PersonalScribeCore/Models/Selection/BuiltInModelCatalog.swift`
- `Sources/PersonalScribeSession/Models/Selection/ModelBoundProcessorProvider.swift`
- `Sources/PersonalScribeSession/Models/Selection/ActiveModelService.swift`
- `Sources/PersonalScribeSession/Pipeline/Orchestrator/SessionPipelineOrchestrator.swift`
- `Sources/PersonalScribeTranscription/Adapters/WhisperKitArtifactStore.swift` (new — shared with batch)
- `Sources/PersonalScribeTranscription/Adapters/BufferFedWhisperKitAudioProcessor.swift` (new)
- `Sources/PersonalScribeTranscription/Adapters/WhisperKitStreamingTranscriberAdapter.swift` (new)
- `Sources/PersonalScribeTranscription/Adapters/WhisperKitTranscriberAdapter.swift` (refactor to share artifact helper)
- `Sources/PersonalScribeAppKit/Settings/AIModelsTab.swift`
- `Sources/PersonalScribeAppKit/Settings/ModelInfoPopoverPresenter.swift`
- `Tests/PersonalScribeCoreTests/...` for engine/catalog coverage
- `Tests/PersonalScribeSessionTests/Models/Selection/...`
- `Tests/PersonalScribeTranscriptionTests/Adapters/WhisperKitStreamingTranscriberAdapterTests.swift`
- `Tests/PersonalScribeTranscriptionTests/Fixtures/Streaming/...`
- `Tests/ManualVerifications/ManualSettingsVerification.md`
- `Tests/ManualVerifications/ManualTranscriptionVerification.md`
- `Tests/ManualVerifications/ManualModesVerification.md`

Backward-compat risk:

- sibling shared-artifact descriptors can show stale ready/delete state if alias refresh is missed
- WhisperKit stable-chunk mapping can under-emit or over-emit if it keys off `currentText` or text diffs instead of a confirmed-segment high-water mark
- streaming + batch WhisperKit can double-load memory if post-stop cleanup before second pass is missed

Rollback triggers:

- dogfood shows duplicate or missing stable chunks
- EOU latency is clearly worse than current FluidAudio with no correctness win
- memory spikes are unacceptable in streaming + second-pass sessions

### Phase 2 — whisper.cpp streaming plus A/B dogfood

Purpose:

- add the higher-control Whisper runtime
- compare it against FluidAudio and WhisperKit with real metrics

#### Pending edits — req-0027 whisper.cpp review

This parent plan previously pointed Phase 2 at `WHISPERCPP_DESIGN.md`, but no such child file exists on current trunk. The subsections below are therefore the canonical whisper.cpp design until or unless Phase 2 is split into its own document.

#### §8.2 C API shape

Use the pinned `WhisperFramework` XCFramework already wired by `WhisperCppTranscriberAdapter`. Current trunk proves the batch adapter can load a context with `whisper_init_from_file_with_params`, run `whisper_full`, and read segments with `whisper_full_n_segments` plus `whisper_full_get_segment_t0/t1/text` (`Sources/PersonalScribeTranscription/Adapters/WhisperCppTranscriberAdapter.swift:687-750`; `.build/artifacts/personal_scribe/WhisperFramework/whisper.xcframework/macos-arm64_x86_64/whisper.framework/Versions/A/Headers/whisper.h:45-46,460-463,603-651`). `whisper_new_segment_callback` exists on the pinned header, but it still reports per-pass segments rather than durable segment IDs, so treat it as optional progress plumbing rather than the core stability contract.

#### §8.4 Decode loop + concurrency

Keep one `whisper_context` on one dedicated serial queue. Current trunk already does this in `LiveWhisperCppManager`, and the pinned header explicitly forbids concurrent use of the same context (`Sources/PersonalScribeTranscription/Adapters/WhisperCppTranscriberAdapter.swift:603-678`; `.build/artifacts/personal_scribe/WhisperFramework/whisper.xcframework/macos-arm64_x86_64/whisper.framework/Versions/A/Headers/whisper.h:45-46,600-621`).

Start with adapter-private dogfood constants:

- cadence `500ms`
- rolling decode window `8s`
- overlap `250ms`
- confirmation `2` consecutive passes

These are starting values only, not product promises. Current trunk has no in-repo whisper.cpp streaming benchmark data, and non-enabled kinds intentionally ship without benchmark metadata today (`Tests/PersonalScribeCoreTests/Models/Selection/BuiltInModelCatalogTests.swift:58-64`). Tuning stays in adapter code/tests unless Phase 2 dogfood proves a stable preset is needed.

#### §8.5 Stable segment tracker + EOU boundary

Do NOT key segment identity on exact `(t0, t1, normalizedText)`. The pinned API exposes segment timestamps/text but no stable segment ID (`.build/artifacts/personal_scribe/WhisperFramework/whisper.xcframework/macos-arm64_x86_64/whisper.framework/Versions/A/Headers/whisper.h:630-651`), and the rolling window re-decodes overlapping audio, so exact timestamp equality is too brittle.

Tracker rule:

- compare trailing segments in order
- normalize whitespace before matching text
- require approximate time overlap or bounded drift rather than exact `t0` / `t1`
- promote a segment to stable only after it survives `2` consecutive passes
- once stable text is emitted, future passes may extend after it but never retract or replay it

EOU rule:

- `WhisperCppStreamingTranscriberAdapter` should conform to `VadBoundaryStreamingTranscriber`
- use the shared `VadBoundarySessionFactory` plus `StreamingEouSilenceThresholdMs` to decide when the newly stabilized prefix flushes as `.endOfUtterance`
- keep the stability tracker responsible only for unstable-vs-stable text; do not invent a whisper.cpp-specific silence preference or reset the whole adapter between utterances

This matches the existing streaming seam (`Sources/PersonalScribeCore/Transcription/StreamingVadBoundary.swift:18-29`; `Sources/PersonalScribeSession/Pipeline/Orchestrator/SessionPipelineOrchestrator.swift:1318-1329`).

#### §8.6 Finalization

On stream end, run one last decode over the remaining rolling window, flush any still-unemitted stable chunk, then emit exactly one terminal `.finalized` result with the full fallback transcript. That aligns with the current event contract and leaves `runBoundStreamingTranscription(...)` free to replace the streaming fallback with the existing batch second pass if one is configured (`Sources/PersonalScribeCore/Transcription/StreamingTranscriptionEvent.swift:18-21`; `Sources/PersonalScribeSession/Pipeline/Orchestrator/StreamingTranscriptAccumulator.swift:9-46`; `Sources/PersonalScribeSession/Pipeline/Orchestrator/SessionPipelineOrchestrator.swift:817-844`). The streaming adapter must not duplicate the second-pass batch path.

#### §8.8 Latency expectations

Treat concrete whisper.cpp latency ranges as unproven until Phase 2 dogfood lands. The repo has no in-tree whisper.cpp streaming benchmark; the best local spike evidence only says the historical "x3" claim is CPU-only and not representative of `large-v3-turbo`, while real-user reports are mixed-to-negative on CoreML/ANE for the larger models (`plans/098_whispercpp/SPIKE-pool-claude.md:125-145,190-200`). Phase 2 should assume only the ordinal risk ranking is known today: `tiny` is the safest latency bet, `small-q5_1` is the balanced candidate, and `large-v3-turbo-q5_0` remains deferred because its live-latency story is not grounded yet.

Files-touched estimate:

- `Sources/PersonalScribeCore/Models/Selection/ModelDescriptor.swift`
- `Sources/PersonalScribeCore/Models/Selection/TranscriptionEngine+Kind.swift`
- `Sources/PersonalScribeCore/Models/Selection/TranscriptionEngine+Codable.swift`
- `Sources/PersonalScribeCore/Models/Selection/BuiltInModelCatalog.swift`
- `Sources/PersonalScribeSession/Models/Selection/ModelBoundProcessorProvider.swift`
- `Sources/PersonalScribeSession/Pipeline/Orchestrator/SessionPipelineOrchestrator.swift`
- `Sources/PersonalScribeTranscription/Adapters/WhisperCppArtifactStore.swift` (new)
- `Sources/PersonalScribeTranscription/Adapters/WhisperCppStableSegmentTracker.swift` (new)
- `Sources/PersonalScribeTranscription/Adapters/WhisperCppStreamingTranscriberAdapter.swift` (new)
- `Sources/PersonalScribeTranscription/Adapters/WhisperCppTranscriberAdapter.swift` (refactor to share artifact helper)
- `Sources/PersonalScribeAppKit/Settings/AIModelsTab.swift`
- `Sources/PersonalScribeAppKit/Settings/ModelInfoPopoverPresenter.swift`
- `Tests/PersonalScribeTranscriptionTests/Adapters/WhisperCppStreamingTranscriberAdapterTests.swift`
- `Tests/PersonalScribeTranscriptionTests/Fixtures/Streaming/...`
- `Tests/ManualVerifications/ManualSettingsVerification.md`
- `Tests/ManualVerifications/ManualTranscriptionVerification.md`
- `Tests/ManualVerifications/ManualModesVerification.md`

Backward-compat risk:

- the stability tracker can double-emit or starve emission if identity matching is wrong
- quantized larger models may fail the live-latency bar even if correctness is acceptable

Rollback triggers:

- chunk duplication or chunk starvation in dogfood
- CPU/RSS cost is materially worse than WhisperKit with no product gain
- the tuning surface starts pushing toward a speculative schema change

### Phase 3 — decide default / keep-all-three / deprecate FluidAudio streaming

Purpose:

- make a product decision only after metrics and dogfood

Decision inputs:

- live-cursor instrumentation data from the FluidAudio fix + each new adapter
- Phase-1 WhisperKit dogfood
- Phase-2 whisper.cpp dogfood
- memory/cpu cost
- multilingual usefulness

Possible outcomes:

1. Keep all three and leave FluidAudio as default
2. Keep all three and switch default to WhisperKit
3. Keep all three and switch default to whisper.cpp
4. Deprecate FluidAudio streaming only if both correctness and latency are convincingly covered elsewhere

Files touched if deprecating FluidAudio:

- `Sources/PersonalScribeCore/Models/Selection/BuiltInModelCatalog.swift`
- `Sources/PersonalScribeSession/Models/Selection/ModelBoundProcessorProvider.swift`
- `Sources/PersonalScribeSession/Models/Selection/ActiveModelService.swift`
- `Sources/PersonalScribeCore/WorkflowMode/...` migration / validation paths if pinned ids are removed
- `Sources/PersonalScribeAppKit/...` copy and selector defaults
- `Tests/ManualVerifications/...`

Backward-compat risk:

- existing pinned modes can reference removed streaming descriptor ids

Rollback triggers:

- migration cannot preserve existing custom modes safely
- dogfood still shows a real niche where FluidAudio is the best path

## 9. Final recommendation

Ship in the following order:

1. WhisperKit streaming behind the existing `.streamingASR` selector, default still FluidAudio (`WHISPERKIT_DESIGN.md`)
2. whisper.cpp streaming and A/B dogfood (`WHISPERCPP_DESIGN.md`)
3. Phase 3 default/deprecation decision only after data

This is the smallest plan that:

- keeps the live streaming contract intact
- avoids speculative mode/schema churn
- uses the already-shipped Whisper runtimes
- respects req-0021 / req-0022 / `FOLLOWUP_vad_boundary.md` as the current source of truth on the FluidAudio path
- lets the product default be driven by measured latency and dogfood rather than by ideology

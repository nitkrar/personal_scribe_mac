# Layer 7 — Pipeline

## Critical discipline
> **Do NOT diverge from this plan. Silent divergence is the cardinal sin. To deviate, surface the proposed divergence in a commit-message comment AND in the hand-off report; wait for main-session confirmation. Paraphrasing the contract is divergence. Renaming a protocol the plan specifies is divergence. Choosing a different storage format than the plan specifies is divergence.**

## Why this layer exists
`SessionCoordinator` currently owns almost the entire session lifecycle inline: it starts capture, buffers audio, republishes audio levels, guards minimum duration, runs batch transcription, calls `PostProcessor.clean(_:)`, appends to SQLite, caches the last result, and exposes state/result streams from one actor. Output is not actually part of that lifecycle; `MenuBarSceneModel` waits for `.idle`, pulls `lastResult()`, and auto-pastes afterward. That split makes the end-to-end flow incomplete, pushes output timing into UI code, and leaves no insertion point for mode-aware post-processing.

This layer centralizes the lifecycle into a single orchestrator with discrete stages: capture, transcription, post-processing, persistence, and output. It keeps the current `SessionState` surface for UI compatibility, but introduces a richer pipeline snapshot so partial transcripts, mode context, and typed stage failures have one authoritative home. The task-local locked decisions override the stale finalize-only wording in `plans/CENTRAL_LAYERS_PROMPT.md:334-339`: partial transcript carriage is in scope now, while post-processing itself still runs only at transcript completion until a later partial-safe stage slice exists.

## Observed current spread
| File | Line(s) | What lives there |
|---|---|---|
| `Sources/SeshatSession/SessionCoordinator.swift` | 6-38 | Stored dependencies, cached state/result, inline `PostProcessor`, buffered audio, audio-level fan-out state |
| `Sources/SeshatSession/SessionCoordinator.swift` | 40-52 | Public `toggle()` entry point and retry-from-error behavior |
| `Sources/SeshatSession/SessionCoordinator.swift` | 54-112 | `state()`, `stateStream()`, `audioLevelStream()`, `audioLevel()`, `lastResult()`, `prepareTranscriber()`, `modelDownloadProgress()` |
| `Sources/SeshatSession/SessionCoordinator.swift` | 138-218 | Inline capture start/stop, duration guard, replay transcription, `postProcessor.clean(raw.text)`, `mostRecentResult`, publish-to-idle |
| `Sources/SeshatSession/SessionCoordinator.swift` | 220-241 | SQLite persistence side effect with log-and-swallow failure handling |
| `Sources/SeshatSession/SessionCoordinator.swift` | 250-290 | Capture consumption, replay stream construction, error mapping, detached background prepare |
| `Sources/SeshatCore/PostProcessor.swift` | 3-78 | Hardcoded two-step cleanup (`removeFillers` then `applyBasicPunctuation`) with no mode/model context |
| `Sources/SeshatCore/Protocols.swift` | 31-36 | `Transcribing` exposes only final-result APIs; no partial transcript contract |
| `Sources/SeshatCore/TranscriptionResult.swift` | 1-29 | Final result shape only; no revision/partial carrier |
| `Sources/SeshatCore/ModeDescriptor.swift` | 3-21 | Mode metadata already carries `aiModelID` and `systemPrompt`, but nothing in the session lifecycle reads them |
| `Sources/SeshatCore/Errors.swift` | 3-79 | Shared error enum has no stage-specific failure case |
| `Sources/SeshatTranscription/FluidAudioTranscriber.swift` | 153-191 | Streaming input is buffered to one aggregate buffer before any final result is returned |
| `Sources/SeshatAppKit/MenuBar/MenuBarSceneModel.swift` | 13-18 | Direct `SessionCoordinator` dependency plus ad-hoc paste/output dependencies |
| `Sources/SeshatAppKit/MenuBar/MenuBarSceneModel.swift` | 56-97 | State/result/progress observation built around `stateStream()`, `lastResult()`, and `modelDownloadProgress()` |
| `Sources/SeshatAppKit/MenuBar/MenuBarSceneModel.swift` | 99-144 | Record-button toggle path and auto-paste-on-idle hook |
| `Sources/SeshatAppKit/Overlay/PillOverlayController.swift` | 81-101 | Pill wiring combines state + preparation progress only; no transcript partial channel |
| `Sources/SeshatAppKit/Overlay/PillOverlayViewModel.swift` | 41-63, 82-150 | Pill state/visibility model has no transcript text or revision surface |
| `Sources/SeshatAppKit/Hotkeys/GlobalHotkeyMonitor.swift` | 29-76, 221-292 | Double-tap hotkey eventually calls a generic trigger closure that toggles `SessionCoordinator` in composition |
| `Sources/SeshatAppKit/Composition/AppComposition.swift` | 10-25, 48-88 | Shared `SessionCoordinator` construction plus hotkey/startup entry wiring |
| `Sources/SeshatAppKit/Composition/SeshatAppMain.swift` | 75-110 | Scene-model and pill wiring, plus the pill-tap toggle entry point |
| `Sources/SeshatAppKit/Paste/PasteInjector.swift` | 143-183 | Batch-only output implementation lives outside the session lifecycle |

## Proposed API / contracts
All Stage 1 files for this layer land only under new directories:

- `Sources/SeshatSession/Pipeline/Contracts/*`
- `Sources/SeshatSession/Pipeline/PostProcessing/*`
- `Sources/SeshatSession/Pipeline/Orchestrator/*`
- `Tests/SeshatSessionTests/Pipeline/*`

The public contract intentionally keeps `SessionState` unchanged so Layer 4 and current SwiftUI surfaces do not need a second state-model migration at the same time.

### Types (enums, structs)
- `PipelineStageID`
  - Cases: `.capture`, `.transcription`, `.postProcessing`, `.persistence`, `.output`
  - Purpose: internal/external stage visibility without changing `SessionState`
- `TranscriptProgress`
  - Fields: `revision: Int`, `text: String`, `isFinal: Bool`, `sourceStage: PipelineStageID`
  - Purpose: carries raw partials, raw final text, and post-processed final text through one stream
- `PipelineContextSnapshot`
  - Fields: `activeMode: ModeDescriptor?`, `activeAIModelID: String?`, `systemPrompt: String?`, `streamingOutputEnabled: Bool`
  - Purpose: the exact mode/model context captured at transcript-completion time
- `PipelineSnapshot`
  - Fields: `sessionState: SessionState`, `activeStage: PipelineStageID?`, `transcriptProgress: TranscriptProgress?`, `lastCompletedResult: TranscriptionResult?`, `recordingDuration: Duration?`, `context: PipelineContextSnapshot`
  - Purpose: single source of truth for UI/state-store subscribers
- `PostProcessingContext`
  - Fields: `recordingDuration: Duration`, `activeMode: ModeDescriptor?`, `activeAIModelID: String?`, `systemPrompt: String?`, `segments: [TranscriptionResult.Segment]`, `asrConfidence: Double?`
  - Purpose: feeds post-processing with the mode/model metadata the current code ignores

### Protocols
- `SessionPipelining: Sendable`
  - `toggleCapture() async`
  - `prepareTranscriber() async throws`
  - `snapshot() -> PipelineSnapshot`
  - `snapshotStream() -> AsyncStream<PipelineSnapshot>`
  - `audioLevelStream() -> AsyncStream<Float>`
  - `modelDownloadProgress() -> AsyncStream<ModelDownloadProgress>`
- `PostProcessingStage: Sendable`
  - `var name: String { get }`
  - `func apply(_ text: String, context: PostProcessingContext) async throws -> String`
- `PostProcessingPipeline: Sendable`
  - `func run(_ text: String, context: PostProcessingContext) async throws -> String`
- `PipelineOutputSink: Sendable`
  - `func deliverPartial(_ revision: TranscriptProgress) async throws`
  - `func deliverFinal(_ result: TranscriptionResult) async throws`
  - `func resetForNewSession() async`
- `PipelineContextProviding: Sendable`
  - `func currentContext() -> PipelineContextSnapshot`

### Errors
- Final shared contract: extend `SeshatError` with `pipelineStageFailed(stage: PipelineStageID, detail: String)`
- Keep `SeshatError` `Equatable`; the associated detail must therefore be a stable string summary, not a raw boxed `Error`
- Because Stage 1 may not edit existing files, Stage 1 can stage this behind an internal `PipelineStageFailure` type under `Sources/SeshatSession/Pipeline/Contracts/*`; Step 2.1 folds that into the public `SeshatError` surface before any app consumer swap
- Output routing that intentionally falls back to clipboard-only is not a failure; actual thrown post-processing, persistence, or output errors must surface through typed error handling instead of `logger.error(...); return`

## Proposed live implementation
`SessionPipelineOrchestrator` lands in `Sources/SeshatSession/Pipeline/Orchestrator/` as a `public actor`. It wraps the existing `AudioCapturing`, `Transcribing`, optional `SQLiteTranscriptStore`, `SeshatLogger`, a `PostProcessingPipeline`, a `PipelineOutputSink`, and a `PipelineContextProviding`. The actor owns exactly one active run at a time and republishes immutable `PipelineSnapshot` values via `AsyncStream` the same way the current coordinator republishes `SessionState`.

Internally, the orchestrator keeps discrete stages even though the public `sessionState` stays coarse for UI compatibility. `sessionState == .recording` means the actor is in `.capture`; `sessionState == .transcribing` covers `.transcription`, `.postProcessing`, `.persistence`, and `.output`; `sessionState == .idle` means the run has fully completed; `sessionState == .error` means a typed failure aborted the run. That preserves the current menu bar and pill state mapping while still giving Layer 4 and future telemetry a richer stage stream.

Partial transcript carriage is part of the contract now. The current `Transcribing` implementation remains batch-only, so the live Stage 1 orchestrator emits no true partial revisions from `FluidAudioTranscriber` yet. It still publishes one raw-final `TranscriptProgress` before post-processing and one final-post-processed `TranscriptProgress` after post-processing, and it routes both through the same snapshot/output path future streaming transcribers will use. That keeps the pipeline streaming-aware without falsely claiming streaming-safe post-processing today.

The default post-processing chain is `FillerRemovalStage` followed by `BasicPunctuationStage`, preserving current behavior from `Sources/SeshatCore/PostProcessor.swift:29-76`. The protocol is `async throws`, not synchronous, because this task’s locked decisions require mode/system-prompt/AI-model-aware post-processing at transcript completion. Current default stages remain pure and cheap; the async shape is there so later model-backed polish does not force a second protocol break.

Persistence is part of the orchestrated run rather than a fire-and-forget side effect. The new actor appends to `SQLiteTranscriptStore` after post-processing and before final output. Stage 1 keeps those failures on an internal typed path because it cannot edit `Sources/SeshatCore/Errors.swift`; Step 2.1 promotes that path into `.error(.pipelineStageFailed(stage: .persistence, ...))` and the equivalent post-processing/output variants. The only non-error output path is an explicit routing decision such as clipboard-only fallback.

`prepareTranscriber()` and `modelDownloadProgress()` stay as orchestrator passthroughs in this layer so the current startup/preparation behavior survives the swap. That is a compatibility bridge, not a second owner of model-selection state.

## Migration of existing call sites
Implementers must replace every `<fill-in>` line placeholder below with actual produced `file:line` anchors in the hand-off report.

### Stage 1 — Build in parallel
Stage 1 can run in parallel with Layer 1, Layer 2, Layer 3, Layer 4, Layer 5, Layer 6, Layer 8, and Layer 9 Stage 1 work because it touches only new subdirectories under `Sources/SeshatSession/Pipeline/*` and `Tests/SeshatSessionTests/Pipeline/*`.

#### Step 1.1 — Define pipeline contracts and snapshot types
| Change | Before | After |
|---|---|---|
| Session contract | `SessionCoordinator` exposes split `state()`, `stateStream()`, `lastResult()`, `audioLevelStream()`, `modelDownloadProgress()` APIs from one inline actor | New `SessionPipelining` contract exposes a single `PipelineSnapshot` stream plus audio-level/model-progress passthroughs; existing consumers remain untouched in Stage 1 |
| Transcript progress | No partial/final revision carrier exists | `TranscriptProgress` and `PipelineSnapshot` carry partials, raw-final text, and post-processed final text |

Dependencies:
- Parallel with: Layer 1, Layer 2, Layer 3, Layer 4, Layer 5, Layer 6, Layer 8, Layer 9 Stage 1
- Requires: none

Implementation clauses:
- `L7.S1.1.1` Add new public contracts only under `Sources/SeshatSession/Pipeline/Contracts/*` and `Tests/SeshatSessionTests/Pipeline/Contracts/*`; do not edit `Sources/SeshatSession/SessionCoordinator.swift` yet.
- `L7.S1.1.2` `PipelineSnapshot` must include `sessionState`, `activeStage`, `transcriptProgress`, `lastCompletedResult`, `recordingDuration`, and `context`.
- `L7.S1.1.3` `TranscriptProgress` must be revision-based and must not require any SQLite schema change.
- `L7.S1.1.4` `SessionPipelining` must keep `SessionState` as the outward session-state contract for UI compatibility.

Validation checklist:
- [ ] `Sources/SeshatSession/Pipeline/Contracts/PipelineSnapshot.swift:<fill-in>` contains the single-snapshot surface replacing the split reads in `Sources/SeshatSession/SessionCoordinator.swift:54-112`, matching `L7.S1.1.2-L7.S1.1.4`.
- [ ] `Sources/SeshatSession/Pipeline/Contracts/TranscriptProgress.swift:<fill-in>` introduces revision-based transcript carriage without touching `Sources/SeshatCore/TranscriptionResult.swift:1-29`, matching `L7.S1.1.2-L7.S1.1.3`.
- [ ] `Sources/SeshatSession/Pipeline/Contracts/SessionPipelining.swift:<fill-in>` exposes the toggle/prepare/stream contract while leaving existing AppKit consumers untouched, matching `L7.S1.1.1-L7.S1.1.4`.
- [ ] No files outside the new Stage 1 directories are modified in this step, matching `L7.S1.1.1`.

#### Step 1.2 — Extract post-processing into pluggable stages
| Change | Before | After |
|---|---|---|
| Cleanup pipeline | `PostProcessor.clean(_:)` hardcodes filler removal then punctuation in `SeshatCore` | New `PostProcessingPipeline` composes `FillerRemovalStage` and `BasicPunctuationStage` under `SeshatSession/Pipeline/PostProcessing/*` |
| Mode/model context | Cleanup ignores `ModeDescriptor.systemPrompt` and `aiModelID` entirely | `PostProcessingContext` captures recording duration, mode metadata, system prompt, active AI model, and segments at finalize time |

Dependencies:
- Parallel with: Layer 1, Layer 2, Layer 3, Layer 4, Layer 5, Layer 6, Layer 8, Layer 9 Stage 1
- Requires: Step 1.1

Implementation clauses:
- `L7.S1.2.1` Land `PostProcessingStage`, `PostProcessingPipeline`, and default stage files only under `Sources/SeshatSession/Pipeline/PostProcessing/*`; `Sources/SeshatCore/PostProcessor.swift` stays untouched in Stage 1.
- `L7.S1.2.2` Port current behavior exactly: `FillerRemovalStage` then `BasicPunctuationStage`, preserving the semantics characterized by `Tests/SeshatCoreTests/PostProcessorTests.swift:7-40`.
- `L7.S1.2.3` `PostProcessingContext` must include `recordingDuration`, `activeMode`, `activeAIModelID`, `systemPrompt`, `segments`, and optional `asrConfidence`.
- `L7.S1.2.4` Stage APIs are `async throws`; current default stages remain deterministic/pure internally, but the contract must already support model-aware post-processing.

Validation checklist:
- [ ] `Sources/SeshatSession/Pipeline/PostProcessing/DefaultPostProcessingPipeline.swift:<fill-in>` wires `FillerRemovalStage` before `BasicPunctuationStage`, replacing the hardcoded order in `Sources/SeshatCore/PostProcessor.swift:29-31`, matching `L7.S1.2.1-L7.S1.2.2`.
- [ ] `Sources/SeshatSession/Pipeline/PostProcessing/PostProcessingContext.swift:<fill-in>` captures the mode/model metadata that currently exists only in `Sources/SeshatCore/ModeDescriptor.swift:3-21`, matching `L7.S1.2.3`.
- [ ] `Tests/SeshatSessionTests/Pipeline/PostProcessing/PostProcessingPipelineTests.swift:<fill-in>` ports the assertions from `Tests/SeshatCoreTests/PostProcessorTests.swift:7-40` before any Stage 3 deletion, matching `L7.S1.2.2`.
- [ ] `Sources/SeshatSession/Pipeline/PostProcessing/PostProcessingStage.swift:<fill-in>` is `async throws`, not synchronous, matching `L7.S1.2.4`.

#### Step 1.3 — Implement the live orchestrator and stage adapters
| Change | Before | After |
|---|---|---|
| Lifecycle ownership | `SessionCoordinator` mixes capture/transcription/post-processing/persistence inline and output still lives in the menu bar | New `SessionPipelineOrchestrator` actor owns capture, transcription, post-processing, persistence, and output as discrete stages |
| Failure handling | SQLite persistence failure logs and returns; stage-specific failure is not represented in `SeshatError` | Stage 1 introduces a typed stage-failure path inside the new layer, and Step 2.1 promotes it into `SeshatError.pipelineStageFailed(stage:detail:)` before any app consumer swap |

Dependencies:
- Parallel with: Layer 1, Layer 2, Layer 3, Layer 4, Layer 5, Layer 6, Layer 8, Layer 9 Stage 1
- Requires: Step 1.1, Step 1.2

Implementation clauses:
- `L7.S1.3.1` Add `SessionPipelineOrchestrator` under `Sources/SeshatSession/Pipeline/Orchestrator/*` using existing `AudioCapturing`, `Transcribing`, optional `SQLiteTranscriptStore`, `PipelineOutputSink`, `PipelineContextProviding`, and `SeshatLogger`.
- `L7.S1.3.2` Internal stage order is `capture -> transcription -> postProcessing -> persistence -> output`; outward `SessionState` remains `.recording` for capture and `.transcribing` for all downstream stages.
- `L7.S1.3.3` The orchestrator must publish `TranscriptProgress` revisions even though current batch ASR emits no true partials yet; raw-final and post-processed-final revisions both flow through the same snapshot stream.
- `L7.S1.3.4` No silent failures: persistence, post-processing, and output errors must surface via an internal typed failure path in Stage 1 and map onto `SeshatError` no later than Step 2.1; log-and-continue is forbidden.
- `L7.S1.3.5` `prepareTranscriber()` and `modelDownloadProgress()` remain orchestrator passthroughs in this layer.

Validation checklist:
- [ ] `Sources/SeshatSession/Pipeline/Orchestrator/SessionPipelineOrchestrator.swift:<fill-in>` replaces the responsibilities currently concentrated in `Sources/SeshatSession/SessionCoordinator.swift:138-290`, matching `L7.S1.3.1-L7.S1.3.5`.
- [ ] `Sources/SeshatSession/Pipeline/Contracts/PipelineStageFailure.swift:<fill-in>` or its equivalent new-file staging type captures stage-specific failures without editing `Sources/SeshatCore/Errors.swift:3-79` in Stage 1, matching `L7.S1.3.4`.
- [ ] `Tests/SeshatSessionTests/Pipeline/SessionPipelineOrchestratorTests.swift:<fill-in>` preserves the behavior covered by `Tests/SeshatSessionTests/SessionCoordinatorHappyPathTests.swift:7-47`, `Tests/SeshatSessionTests/SessionCoordinatorErrorTests.swift:7-183`, `Tests/SeshatSessionTests/SessionCoordinatorPreparationTests.swift:7-49`, `Tests/SeshatSessionTests/SessionCoordinatorAudioLevelTests.swift:12-126`, and `Tests/SeshatSessionTests/SessionCoordinatorTranscriptStoreTests.swift:7-41`, matching `L7.S1.3.2-L7.S1.3.5`.
- [ ] No Stage 1 file edits any current consumer in `Sources/SeshatAppKit/*` or the legacy coordinator file, matching `L7.S1.3.1`.

### Stage 2 — Swap
Each Stage 2 step gets its own commit. No Stage 3 deletion begins until every step below is complete and there are no remaining app-code calls to the legacy `SessionCoordinator`.

#### Step 2.1 — Swap startup preparation to the new orchestrator
| Change | Before | After |
|---|---|---|
| Shared app composition | `AppComposition` constructs and shares `SessionCoordinator` only | `AppComposition` constructs and shares the new orchestrator alongside the still-present legacy coordinator during the swap |
| Startup preparation | `AppStartupCoordinator` calls `coordinator.prepareTranscriber()` | `AppStartupCoordinator` calls `pipeline.prepareTranscriber()` |

Dependencies:
- Parallel with: none; this is the first swap step
- Requires: Step 1.3

Implementation clauses:
- `L7.S2.1.1` Add the new shared orchestrator factory/singleton in `AppComposition` without deleting the legacy coordinator yet.
- `L7.S2.1.2` Move the startup prepare path first so the app already has a live orchestrator before UI consumers migrate.
- `L7.S2.1.3` Fold the staged pipeline failure into `SeshatError.pipelineStageFailed(stage:detail:)` and wire `LocalizedError` messaging before any app consumer swap.
- `L7.S2.1.4` Replace shared-composition tests with shared-orchestrator assertions in the same commit.

Validation checklist:
- [ ] `Sources/SeshatAppKit/Composition/AppComposition.swift:<fill-in>` adds a shared orchestrator path without deleting the legacy coordinator prematurely, replacing the current single-owner setup in `Sources/SeshatAppKit/Composition/AppComposition.swift:10-25`, matching `L7.S2.1.1`.
- [ ] `Sources/SeshatAppKit/Composition/AppComposition.swift:<fill-in>` and `Sources/SeshatAppKit/Composition/AppStartupCoordinator.swift:<fill-in>` route startup preparation through `prepareTranscriber()` on the new contract instead of `Sources/SeshatAppKit/Composition/AppComposition.swift:73-85`, matching `L7.S2.1.2`.
- [ ] `Sources/SeshatCore/Errors.swift:<fill-in>` adds `pipelineStageFailed(stage:detail:)` and localized messaging, replacing the gap in `Sources/SeshatCore/Errors.swift:3-79`, matching `L7.S2.1.3`.
- [ ] `Tests/SeshatAppKitTests/AppCompositionTests.swift:<fill-in>` and `Tests/SeshatAppKitTests/AppEntryPointTests.swift:<fill-in>` assert shared orchestrator composition instead of the legacy `SessionCoordinator` check in `Tests/SeshatAppKitTests/AppCompositionTests.swift:8-15`, matching `L7.S2.1.4`.

#### Step 2.2 — Swap `MenuBarSceneModel`
| Change | Before | After |
|---|---|---|
| Observation model | `MenuBarSceneModel` listens to `stateStream()`, pulls `lastResult()`, and reads `modelDownloadProgress()` from `SessionCoordinator` | `MenuBarSceneModel` listens to `snapshotStream()` and reads `lastCompletedResult` from `PipelineSnapshot`; model progress stays a passthrough on the new contract |
| Output side effect | `autoPasteTranscriptIfNeeded(_:)` pastes from UI code on idle transition | Output is already completed inside the pipeline; the menu bar only reflects the finished result |
| Toggle path | Record button calls `coordinator.toggle()` | Record button calls `pipeline.toggleCapture()` |

Dependencies:
- Parallel with: Step 2.3 after Step 2.1 if desired
- Requires: Step 2.1

Implementation clauses:
- `L7.S2.2.1` Replace the concrete `SessionCoordinator` dependency with `any SessionPipelining`.
- `L7.S2.2.2` `lastResultText` must be derived from `PipelineSnapshot.lastCompletedResult`, not a post-idle pull.
- `L7.S2.2.3` Delete `pasteInjector`, `lastAutoPastedTranscript`, and `autoPasteTranscriptIfNeeded` from `MenuBarSceneModel`; output is pipeline-owned now.
- `L7.S2.2.4` Keep the microphone permission flow unchanged; only the session-lifecycle dependency changes in this step.

Validation checklist:
- [ ] `Sources/SeshatAppKit/MenuBar/MenuBarSceneModel.swift:<fill-in>` observes `snapshotStream()` instead of `Sources/SeshatAppKit/MenuBar/MenuBarSceneModel.swift:56-97`, matching `L7.S2.2.1-L7.S2.2.2`.
- [ ] `Sources/SeshatAppKit/MenuBar/MenuBarSceneModel.swift:<fill-in>` removes the ad-hoc output hook currently living at `Sources/SeshatAppKit/MenuBar/MenuBarSceneModel.swift:135-144`, matching `L7.S2.2.3`.
- [ ] `Tests/SeshatAppKitTests/MenuBarSceneModelTests.swift:<fill-in>` rewrites the result/output assertions from `Tests/SeshatAppKitTests/MenuBarSceneModelTests.swift:242-383` around pipeline-owned output rather than scene-model-owned paste calls, matching `L7.S2.2.2-L7.S2.2.3`.
- [ ] The permission-request tests in `Tests/SeshatAppKitTests/MenuBarSceneModelTests.swift:<fill-in>` still preserve the behavior covered by `Sources/SeshatAppKit/MenuBar/MenuBarSceneModel.swift:99-117`, matching `L7.S2.2.4`.

#### Step 2.3 — Swap the pill overlay to direct pipeline snapshots
| Change | Before | After |
|---|---|---|
| Pill data source | `PillOverlayController` combines scene-model state + prep progress; `PillOverlayViewModel` has no transcript text path | `PillOverlayController` subscribes directly to pipeline snapshots and audio levels; `PillOverlayViewModel` adds a read-only transcript/revision surface for partials and final text |
| Toggle entry | Pill tap in `SeshatAppMain` calls `coordinator.toggle()` | Pill tap calls `pipeline.toggleCapture()` in the same swap |

Dependencies:
- Parallel with: Step 2.2 after Step 2.1 if desired
- Requires: Step 2.1

Implementation clauses:
- `L7.S2.3.1` Add transcript-progress plumbing to `PillOverlayViewModel` and `PillOverlayController`; partial transcript display must no longer depend on `MenuBarSceneModel`.
- `L7.S2.3.2` Keep the existing visibility derivation from `SessionState` and model-preparation progress; transcript display is additive.
- `L7.S2.3.3` Preserve direct audio-level streaming from the session pipeline so the current recording waveform behavior does not regress.
- `L7.S2.3.4` Swap the pill-tap entry path in `SeshatAppMain` in the same commit so the pill is fully pipeline-driven.

Validation checklist:
- [ ] `Sources/SeshatAppKit/Overlay/PillOverlayController.swift:<fill-in>` no longer depends on the scene-model-only combine path in `Sources/SeshatAppKit/Overlay/PillOverlayController.swift:81-101`, matching `L7.S2.3.1-L7.S2.3.3`.
- [ ] `Sources/SeshatAppKit/Overlay/PillOverlayViewModel.swift:<fill-in>` adds transcript-progress storage without regressing the visibility logic currently covered by `Sources/SeshatAppKit/Overlay/PillOverlayViewModel.swift:82-150`, matching `L7.S2.3.1-L7.S2.3.2`.
- [ ] `Sources/SeshatAppKit/Composition/SeshatAppMain.swift:<fill-in>` routes the pill-tap toggle through the new contract instead of `Sources/SeshatAppKit/Composition/SeshatAppMain.swift:99-105`, matching `L7.S2.3.4`.
- [ ] `Tests/SeshatSessionTests/SessionCoordinatorAudioLevelTests.swift:<migrated-fill-in>` or its renamed pipeline equivalent still proves the audio-level fan-out previously covered by `Tests/SeshatSessionTests/SessionCoordinatorAudioLevelTests.swift:12-126`, matching `L7.S2.3.3`.

#### Step 2.4 — Swap hotkey and other composition entry points
| Change | Before | After |
|---|---|---|
| Double-tap hotkey path | `AppComposition.makeGlobalHotkeyMonitor` wraps `coordinator.toggle()` inside `onTrigger` | `AppComposition.makeGlobalHotkeyMonitor` wraps `pipeline.toggleCapture()` |
| Remaining direct session entry points | App composition and entry-point tests still refer to the legacy coordinator type | All app-code toggle entry points target the new pipeline contract |

Dependencies:
- Parallel with: none; this should land after Step 2.2 and Step 2.3 so the main UI is already on the new contract
- Requires: Step 2.2, Step 2.3

Implementation clauses:
- `L7.S2.4.1` Replace every remaining app-code `SessionCoordinator.toggle()` call site with `SessionPipelining.toggleCapture()`.
- `L7.S2.4.2` Preserve all hotkey timing, tap-count, and emergency-quit semantics; only the trigger target changes.
- `L7.S2.4.3` Entry-point/composition tests must compile against the new contract in the same commit.

Validation checklist:
- [ ] `Sources/SeshatAppKit/Composition/AppComposition.swift:<fill-in>` removes the direct hotkey trigger path currently at `Sources/SeshatAppKit/Composition/AppComposition.swift:48-60`, matching `L7.S2.4.1`.
- [ ] `Tests/SeshatAppKitTests/GlobalHotkeyMonitorTests.swift:<fill-in>` still preserves the behavior covered by `Tests/SeshatAppKitTests/GlobalHotkeyMonitorTests.swift:43-177`, matching `L7.S2.4.2`.
- [ ] `Sources/SeshatAppKit/Composition/SeshatAppMain.swift:<fill-in>` and `Tests/SeshatAppKitTests/AppEntryPointTests.swift:<fill-in>` no longer expose the legacy coordinator as the app-entry session dependency, replacing `Tests/SeshatAppKitTests/AppEntryPointTests.swift:9-30`, matching `L7.S2.4.3`.
- [ ] A repo-wide search after this step finds no remaining app-code calls to `SessionCoordinator.toggle()` or `SessionCoordinator.prepareTranscriber()`, matching `L7.S2.4.1-L7.S2.4.3`.

### Stage 3 — Delete
Stage 3 runs only in the repo-wide deletion pass after every Stage 2 consumer is on the new contract and main session confirms there are no remaining app-code references to the legacy implementation.

#### Step 3.1 — Delete the legacy inline coordinator lifecycle
| Change | Before | After |
|---|---|---|
| Canonical session owner | Old `SessionCoordinator.swift` is the live implementation | Legacy inline implementation is deleted; the new orchestrator becomes the single canonical session owner |

Dependencies:
- Parallel with: none
- Requires: Step 2.1, Step 2.2, Step 2.3, Step 2.4

Implementation clauses:
- `L7.S3.1.1` Delete the legacy inline lifecycle in `Sources/SeshatSession/SessionCoordinator.swift:6-290`.
- `L7.S3.1.2` Leave exactly one canonical session orchestrator type at the end of this step; no shadow legacy actor remains compiled.
- `L7.S3.1.3` Rename or move the new orchestrator into the canonical session-owner path only in this deletion step.

Validation checklist:
- [ ] The produced canonical session-owner file `Sources/SeshatSession/SessionCoordinator.swift:<fill-in>` no longer contains the inline responsibilities previously living at `Sources/SeshatSession/SessionCoordinator.swift:6-290`, matching `L7.S3.1.1-L7.S3.1.3`.
- [ ] No second live orchestrator type remains in `Sources/SeshatSession/Pipeline/Orchestrator/*` after the move/rename, matching `L7.S3.1.2-L7.S3.1.3`.
- [ ] The migrated session tests now point at the canonical new implementation rather than the deleted legacy actor, matching `L7.S3.1.2`.

#### Step 3.2 — Delete the ad-hoc `PostProcessor` surface
| Change | Before | After |
|---|---|---|
| Cleanup API | `SeshatCore/PostProcessor.swift` owns cleanup logic and tests | Cleanup logic and tests live only under the new pipeline post-processing directories |

Dependencies:
- Parallel with: none
- Requires: Step 1.2, Step 3.1

Implementation clauses:
- `L7.S3.2.1` Delete `Sources/SeshatCore/PostProcessor.swift`.
- `L7.S3.2.2` Delete or fully migrate `Tests/SeshatCoreTests/PostProcessorTests.swift` only after stronger equivalent coverage exists under `Tests/SeshatSessionTests/Pipeline/PostProcessing/*`.
- `L7.S3.2.3` Remove any remaining `PostProcessor()` or `.clean(_:)` references from the repo.

Validation checklist:
- [ ] `Sources/SeshatCore/PostProcessor.swift` is deleted, replacing the old surface at `Sources/SeshatCore/PostProcessor.swift:1-78`, matching `L7.S3.2.1`.
- [ ] `Tests/SeshatSessionTests/Pipeline/PostProcessing/*.swift:<fill-in>` cover every behavior previously asserted by `Tests/SeshatCoreTests/PostProcessorTests.swift:7-40`, matching `L7.S3.2.2`.
- [ ] Repo search finds no remaining `PostProcessor(` or `.clean(` session cleanup call sites, matching `L7.S3.2.3`.

#### Step 3.3 — Delete the menu-bar/output glue that existed outside the pipeline
| Change | Before | After |
|---|---|---|
| Output ownership | `MenuBarSceneModel` auto-pastes after idle and `SeshatAppMain` injects paste behavior into it | Output delivery is owned only by the pipeline; the menu bar only reflects results |

Dependencies:
- Parallel with: none
- Requires: Step 2.2, Step 3.1

Implementation clauses:
- `L7.S3.3.1` Delete `pasteInjector`, `lastAutoPastedTranscript`, and `autoPasteTranscriptIfNeeded` from `MenuBarSceneModel`.
- `L7.S3.3.2` Delete the scene-model paste-injection plumbing from `SeshatAppMain`.
- `L7.S3.3.3` Do not delete `PasteInjector.swift` here unless Layer 5 separately proves it is dead; this step deletes the ad-hoc hook, not the output implementation.

Validation checklist:
- [ ] `Sources/SeshatAppKit/MenuBar/MenuBarSceneModel.swift:<fill-in>` no longer contains the glue currently living at `Sources/SeshatAppKit/MenuBar/MenuBarSceneModel.swift:16-18,26,34,46,135-144`, matching `L7.S3.3.1`.
- [ ] `Sources/SeshatAppKit/Composition/SeshatAppMain.swift:<fill-in>` no longer passes paste behavior into the menu-bar scene model as it does at `Sources/SeshatAppKit/Composition/SeshatAppMain.swift:75-83`, matching `L7.S3.3.2`.
- [ ] `Sources/SeshatAppKit/Paste/PasteInjector.swift` still exists unless Layer 5 Stage 3 explicitly deletes it, matching `L7.S3.3.3`.

## Test strategy
- Unit tests:
  - `Tests/SeshatSessionTests/Pipeline/Contracts/PipelineContractTests.swift` for `PipelineSnapshot`, `TranscriptProgress`, and `SessionPipelining` contract shape
  - `Tests/SeshatSessionTests/Pipeline/PostProcessing/PostProcessingPipelineTests.swift` to port the exact semantics from `Tests/SeshatCoreTests/PostProcessorTests.swift:7-40`
  - `Tests/SeshatSessionTests/Pipeline/SessionPipelineOrchestratorTests.swift` to preserve the current happy-path/error/audio-level/persistence/background-prepare guarantees from `Tests/SeshatSessionTests/SessionCoordinatorHappyPathTests.swift:7-47`, `Tests/SeshatSessionTests/SessionCoordinatorErrorTests.swift:7-183`, `Tests/SeshatSessionTests/SessionCoordinatorAudioLevelTests.swift:12-126`, `Tests/SeshatSessionTests/SessionCoordinatorTranscriptStoreTests.swift:7-41`, and `Tests/SeshatSessionTests/SessionCoordinatorPreparationTests.swift:7-49`
  - `Tests/SeshatSessionTests/Pipeline/SessionPipelinePartialTranscriptTests.swift` for revision ordering, raw-final then post-processed-final publication, and output-sink partial delivery contract
- Integration tests:
  - Update `Tests/SeshatAppKitTests/MenuBarSceneModelTests.swift` so result propagation and exactly-once output expectations move from scene-model paste hooks to pipeline snapshot/output assertions
  - Update `Tests/SeshatAppKitTests/AppCompositionTests.swift` and `Tests/SeshatAppKitTests/AppEntryPointTests.swift` for shared-orchestrator composition
  - Update `Tests/SeshatAppKitTests/GlobalHotkeyMonitorTests.swift` to prove the trigger target changed without changing hotkey semantics
  - Add/extend pill tests in `Tests/SeshatAppKitTests/PillOverlayViewModelTests.swift` or `Tests/SeshatAppKitTests/PillOverlayPresenterTests.swift` for partial transcript display plus unchanged visibility behavior
- Fakes for the new protocols:
  - Reuse `Sources/SeshatTestSupport/FakeAudioCapturing.swift` and `Sources/SeshatTestSupport/FakeTranscriber.swift`
  - Add a `ScriptedPipelineOutputSink` fake for batch/partial delivery assertions
  - Add a `StubPipelineContextProvider` fake that can drive dictation vs custom-mode context without waiting for Layer 6
- Regression guards the layer must preserve:
  - The post-processing semantics currently proven by `Tests/SeshatCoreTests/PostProcessorTests.swift:7-40`
  - The idle → recording → transcribing → idle happy path from `Tests/SeshatSessionTests/SessionCoordinatorHappyPathTests.swift:7-47`
  - The too-short, retry-after-error, transcribing-toggle-ignore, and stop-preserves-error cases in `Tests/SeshatSessionTests/SessionCoordinatorErrorTests.swift:7-183`
  - Background prepare not blocking stop in `Tests/SeshatSessionTests/SessionCoordinatorPreparationTests.swift:7-49`
  - Audio-level republishing in `Tests/SeshatSessionTests/SessionCoordinatorAudioLevelTests.swift:12-126`
  - Transcript persistence coverage in `Tests/SeshatSessionTests/SessionCoordinatorTranscriptStoreTests.swift:7-41`
- Manual verification:
  - Add a checklist entry to `Tests/SeshatAppKitTests/ManualPillOverlayVerification.md` for partial-transcript rendering once the pill consumes pipeline snapshots directly
  - Add a checklist entry to `Tests/SeshatAppKitTests/ManualHotkeyVerification.md` confirming the double-tap hotkey still starts/stops recording after the trigger target swap

## Open design questions (surface — do not resolve)
- [QUESTION] What is the exact associated-value shape of `SeshatError.pipelineStageFailed`? Constraint: it must preserve `Equatable`, be user-displayable, and still carry enough detail for hand-off/debugging.
- [QUESTION] If post-processing, persistence, or output fails after a raw final transcript already exists, should `PipelineSnapshot.lastCompletedResult` retain that raw transcript for manual copy fallback while the session surfaces `.error`, or should final results appear only after the full stage chain succeeds?

## Validation checklist (implementer ticks box-by-box)
- [ ] Every step hand-off replaces `<fill-in>` with actual produced `file:line` anchors.
- [ ] Stage 1 touches only `Sources/SeshatSession/Pipeline/*` and `Tests/SeshatSessionTests/Pipeline/*`.
- [ ] No Stage 1 step edits any file listed in `Observed current spread`.
- [ ] The pipeline contract carries partial transcript revisions before any live streaming transcriber lands.
- [ ] `SeshatError.pipelineStageFailed` remains `Equatable` and is wired into `LocalizedError`.
- [ ] No silent persistence/output/post-processing failures remain; every such path maps to typed error handling.
- [ ] No files outside "Observed current spread" modified (unless in the explicit Stage 1 new-directory list or the current stage's direct swap-site list).
- [ ] No `Color(hex:` outside `Theme/*`.
- [ ] No direct `UserDefaults.standard.*` — typed resolvers only.
- [ ] No `type` / `kind` / `intent` column added to SQLite.
- [ ] `swift build --build-tests` green (main session).
- [ ] All acceptance tests named in this plan pass.

## Backlog tickets authored
- None. Layer 5 already owns the streaming-output delivery-mechanism backlog ticket; do not duplicate it here.

## Inter-layer dependencies
- **Requires**: Layer 5 for the canonical live output service behind `PipelineOutputSink` once streaming or batch output is fully centralized; Layer 6 for non-dictation active-mode/model context once multiple mode variants are live.
- **Blocks**: Layer 4 because the app-wide store needs a single pipeline snapshot stream instead of scraping `SessionCoordinator.stateStream()`, `lastResult()`, and menu-bar-owned output state separately.

## Commit style
`trunk: layer 7.N: <verb-led subject>`. Test + fix in same commit.

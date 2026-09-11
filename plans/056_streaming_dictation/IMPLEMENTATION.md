# #056 — Streaming dictation: IMPLEMENTATION

References `BACKLOG.md` #056, `plans/056_streaming_dictation/DESIGN.md`, and `#033`.

This is the executable plan for the **pre-#033 slice** of streaming dictation. It intentionally ships **UX-only live streaming** first:

- capture-time live transcript in a new `StreamCard`
- optional authoritative second pass at stop
- existing stop-time clipboard / paste output path fed from the chosen final result

It does **not** implement live cursor streaming. `#033` still owns the transport decision and the first real consumer of `PipelineOutputSink.deliverPartial(...)`.

The implementation lands in **one commit executed in one go**. Staging here is for reasoning and coding order, not for partial user-visible ships.

**Path verification:** every `Sources/` / `Tests/` citation in this doc was grep-verified at write-time.

---

## Scope for this commit

### In scope

- Add recipe/schema support for streaming-specific behavior.
- Change streaming recipes from stop-time replay to **capture-time** streaming.
- Add a new `StreamCard` overlay for live transcript.
- Hand off from `StreamCard` to `ResponseCard` on stop / error / finalization.
- Support optional authoritative second pass for streaming sessions.
- Keep `MenuBarSceneModel` stop-time output delivery as the only clipboard / paste path.
- Add global defaults + per-mode overrides for:
  - live transcript card
  - authoritative second pass
- Add global-only `StreamCard` overflow preference.

### Explicitly out of scope

- live cursor transport
- exposing a live-cursor toggle in the UI
- wiring `PipelineOutputSink.deliverPartial(...)` to any production consumer
- clipboard-churn behavior during recording
- pre-recording clipboard-restore semantics for live cursor mode
- audio spooling / temp-file capture

Those all stay with `#033` or a separate infra ticket.

---

## Build / test contract

- Follow the repo’s TDD rule: add the failing tests for each logic/state-machine slice **before** the fix.
- Intermediate states may not compile cleanly; that is acceptable. The commit is assembled end-to-end, then built/tested once at close from the canonical repo path.
- Closeout verification:
  - `swift test`
  - update manual runbooks before claiming the feature shipped

Recommended manual runbooks to update:

- `Tests/ManualVerifications/ManualModesVerification.md`
- `Tests/ManualVerifications/ManualSettingsVerification.md`
- `Tests/ManualVerifications/ManualPillOverlayVerification.md`
- `Tests/ManualVerifications/ManualTranscriptionVerification.md`

---

## Stage A — Core schema and defaults

### Tests first

Add failing coverage in:

- `Tests/PersonalScribeCoreTests/WorkflowMode/SpecCodableTests.swift`
- `Tests/PersonalScribeCoreTests/WorkflowMode/WorkflowModeTests.swift`
- `Tests/PersonalScribeCoreTests/WorkflowMode/WorkflowModeValidatorTests.swift`
- `Tests/PersonalScribeSessionTests/WorkflowMode/RecipeBuilderTests.swift`
- `Tests/PersonalScribeCoreTests/Preferences/SettingKeyTests.swift`

Pin these behaviors:

- streaming recipes decode a missing `streamingBehavior` by synthesizing `.setting(...)` references to the new global defaults
- batch recipes reject persisted `streamingBehavior`
- `Preset.streamingDictation` seeds streaming behavior and forces VAD off
- `RecipeBuilder` resolves streaming behavior booleans from defaults / overrides
- second-pass finalizer binding is optional and does not fail recipe build when no active `ModelKind.asr` descriptor exists

### Code changes

**Core recipe types**

- Add `StreamingBehaviorSpec` under `Sources/PersonalScribeCore/WorkflowMode/`.
- Add `streamingBehavior: StreamingBehaviorSpec?` to [WorkflowMode.swift](/Users/nitinkum/Projects/nitkrar/personal_scribe/Sources/PersonalScribeCore/WorkflowMode/WorkflowMode.swift).
- Extend Codable with:
  - `nil` required for batch recipes
  - decode fallback for pre-#056 streaming documents

**Resolved/bound types**

- Add `BoundStreamingBehavior` to `Sources/PersonalScribeSession/WorkflowMode/BoundRecipe.swift`.
- Extend `BoundRecipe` with:
  - `streamingBehavior: BoundStreamingBehavior?`
  - `streamingSecondPassTranscriber: (any Transcriber)?`

The second field is the session-frozen authoritative finalizer snapshot for streaming recipes. It is `nil` when second pass is off or no active `ModelKind.asr` descriptor exists at session start.

**Preferences**

- Add new `SettingKey<Bool>` entries in [PreferenceKeys.swift](/Users/nitinkum/Projects/nitkrar/personal_scribe/Sources/PersonalScribeCore/Preferences/PreferenceKeys.swift):
  - `streamingLiveCardEnabled`
  - `streamingLiveCursorEnabled`
  - `streamingSecondPassEnabled`
- Add new AppKit preference types under `Sources/PersonalScribeAppKit/Settings/`:
  - `StreamingLiveCardEnabledPreference`
  - `StreamingLiveCursorEnabledPreference`
  - `StreamingSecondPassEnabledPreference`
  - `StreamingCardOverflowModePreference`

Only the first three mirror into `PreferenceKeys`; overflow mode is global UI state, not a recipe parameter.

**Preset / validation / builder**

- Update [Preset.swift](/Users/nitinkum/Projects/nitkrar/personal_scribe/Sources/PersonalScribeCore/WorkflowMode/Preset.swift):
  - `streamingDictation` seeds `streamingBehavior`
  - VAD default becomes `.override(false)`
- Update [WorkflowModeValidator.swift](/Users/nitinkum/Projects/nitkrar/personal_scribe/Sources/PersonalScribeCore/WorkflowMode/WorkflowModeValidator.swift):
  - `.streaming` requires non-nil `streamingBehavior`
  - `.batch` requires nil `streamingBehavior`
- Update [RecipeBuilder.swift](/Users/nitinkum/Projects/nitkrar/personal_scribe/Sources/PersonalScribeSession/WorkflowMode/RecipeBuilder.swift):
  - resolve `streamingBehavior`
  - optionally snapshot the active descriptor for `ModelKind.asr` into `streamingSecondPassTranscriber`

---

## Stage B — Mode mutators and settings surfaces

### Tests first

Add failing coverage in:

- `Tests/PersonalScribeAppKitTests/UnifiedWindow/Tabs/ModeRecipeMutatorsTests.swift`
- `Tests/PersonalScribeAppKitTests/UnifiedWindow/Tabs/ModeDetailViewModelTests.swift`
- `Tests/PersonalScribeAppKitTests/Settings/GeneralTabViewModelTests.swift`
- `Tests/PersonalScribeAppKitTests/Settings/GeneralTabViewModelStyleTests.swift`

Pin these behaviors:

- `withRealtime(true)` synthesizes `streamingBehavior`
- `withRealtime(false)` clears `streamingBehavior`
- live transcript card, live cursor streaming, and second-pass parameters round-trip through the registry
- global streaming defaults persist correctly
- `StreamCard` overflow preference persists correctly

### Code changes

**Mode mutators + view-model**

- Update [ModeRecipeMutators.swift](/Users/nitinkum/Projects/nitkrar/personal_scribe/Sources/PersonalScribeAppKit/UnifiedWindow/Tabs/Modes/ModeRecipeMutators.swift):
  - `withRealtime(_:)` seeds / clears `streamingBehavior`
  - add mutators for:
    - `withLiveTranscriptCard(parameter:)`
    - `withLiveCursorStreaming(parameter:)`
    - `withAuthoritativeSecondPass(parameter:)`
- Update [ModeDetailViewModel.swift](/Users/nitinkum/Projects/nitkrar/personal_scribe/Sources/PersonalScribeAppKit/UnifiedWindow/Tabs/Modes/ModeDetailViewModel.swift) with read/write accessors for those parameters.

**Mode detail UI**

- Update [ModeDetailView.swift](/Users/nitinkum/Projects/nitkrar/personal_scribe/Sources/PersonalScribeAppKit/UnifiedWindow/Tabs/Modes/ModeDetailView.swift):
  - keep the `Realtime` toggle
  - when realtime is on, show three parameter rows:
    - `Live transcript card`
    - `Live cursor streaming`
    - `Authoritative second pass`
  - revise copy so “Realtime” clearly means “live on-screen transcript,” not cursor typing

**General settings UI**

- Update [GeneralTab.swift](/Users/nitinkum/Projects/nitkrar/personal_scribe/Sources/PersonalScribeAppKit/Settings/GeneralTab.swift) and `GeneralTabViewModel`:
  - add a new `Streaming dictation` card with global defaults for:
    - live transcript card
    - live cursor streaming
    - authoritative second pass
    - overflow mode
  - persist the live-cursor default now even though runtime honor lands with `#033`

---

## Stage C — Capture-time streaming path

### Tests first

Add failing coverage in:

- `Tests/PersonalScribeSessionTests/Pipeline/SessionPipelineOrchestratorTests.swift`
- `Tests/PersonalScribeSessionTests/Pipeline/Orchestrator/RecipeDrivenOrchestratorTests.swift`

Pin these behaviors:

- streaming recipes publish `transcriptProgress` **during capture**, not only after stop
- `liveCardEnabled = false` suppresses snapshot transcript publication but still accumulates text internally
- end-of-utterance commits advance the rolling transcript
- missing `.finalized` falls back to the accumulator’s terminal text
- a mid-stream transcriber failure does not discard buffered audio
- stop / cancel / error tear down the per-session streaming resources cleanly

### Code changes

**New accumulator**

- Add a small orchestrator-owned accumulator under `Sources/PersonalScribeSession/Pipeline/Orchestrator/`, for example:
  - `StreamingTranscriptAccumulator.swift`

Responsibilities:

- track committed utterances
- track current in-progress utterance
- produce rolling session-tail text
- record terminal streaming final when one arrives
- keep enough committed-utterance state for `#033` to derive discrete EOU chunks later, without introducing a separate queued cursor buffer in `#056`

**Replace replay-only streaming**

- Rework [SessionPipelineOrchestrator.swift](/Users/nitinkum/Projects/nitkrar/personal_scribe/Sources/PersonalScribeSession/Pipeline/Orchestrator/SessionPipelineOrchestrator.swift):
  - create a per-session `AsyncThrowingStream<PCMBuffer, Error>` feed for streaming recipes
  - start consuming the `StreamingTranscriber` event stream when recording starts
  - in `consumeCaptureStream(...)`, tee each `PCMBuffer` to:
    - `bufferedAudio`
    - VAD
    - live streaming feed
  - make the orchestrator own the per-session input continuation, consumer task, and accumulator
  - on every termination path (stop, cancel, capture error, live-stream error), finish the input stream, cancel/await the consumer task, and clear the per-session streaming refs
  - extract returned stream values outside `Task` bodies before `for await` loops so the task captures the stream value, not the adapter through the for-await header

**Important rule**

- `SessionSnapshot.transcriptProgress` is updated from the accumulator only when `streamingBehavior.liveCardEnabled == true`
- `PipelineOutputSink.deliverPartial(...)` stays dormant in this commit

Do **not** route `StreamCard` through `deliverPartial(...)`. The UI already observes `SessionSnapshot`.

**Delete the old stop-time replay assumption**

- `runBoundStreamingTranscription(replayBuffers:)` should either disappear or become a narrow stop-time finalization helper only. It must no longer be the primary path for streaming recipes.

---

## Stage D — Optional authoritative second pass

### Tests first

Add failing coverage in:

- `Tests/PersonalScribeSessionTests/WorkflowMode/RecipeBuilderTests.swift`
- `Tests/PersonalScribeSessionTests/Pipeline/SessionPipelineOrchestratorTests.swift`

Pin these behaviors:

- second pass uses the session-frozen batch transcriber snapshot, not the live active-model selection at stop
- second pass off uses the streaming final chain
- second pass unavailable uses the streaming final chain
- second pass failure or blank output uses the streaming final chain and still completes the session
- history / `lastCompletedResult` carry the authoritative chosen final

### Code changes

**Session-start binding**

- In [RecipeBuilder.swift](/Users/nitinkum/Projects/nitkrar/personal_scribe/Sources/PersonalScribeSession/WorkflowMode/RecipeBuilder.swift), when building a streaming recipe:
  - if `secondPassEnabled == true`, attempt to resolve the active descriptor for `ModelKind.asr` and build a plain `Transcriber`
  - if unavailable, store `nil` and continue

**Stop-time selection**

- In [SessionPipelineOrchestrator.swift](/Users/nitinkum/Projects/nitkrar/personal_scribe/Sources/PersonalScribeSession/Pipeline/Orchestrator/SessionPipelineOrchestrator.swift):
  - streaming session always resolves a fallback chain:
    - streaming adapter `.finalized` result first
    - accumulator terminal text second
  - if `streamingSecondPassTranscriber != nil`, run the batch pass over the buffered audio and treat that result as authoritative only if it returns non-blank text
  - if batch finalization throws or returns empty / whitespace-only text, log + fall back to the streaming final chain

**Keep the rest of the pipeline linear**

After the final text is chosen, reuse the existing sequence:

1. post-processing
2. persistence
3. completed snapshot / `lastCompletedResult`
4. stop-time output delivery through `MenuBarSceneModel`

That keeps clipboard/history behavior centralized and avoids a parallel delivery path.

---

## Stage E — Overlay split and handoff

### Tests first

Add failing coverage in:

- `Tests/PersonalScribeAppKitTests/PillOverlayPresenterTests.swift`
- `Tests/PersonalScribeAppKitTests/Overlay/RecordingStatusCardDriverTests.swift`
- `Tests/PersonalScribeCoreTests/AppStore/AppStoreTests.swift`

Pin these behaviors:

- `StreamCard` shows while a streaming session is recording and transcript progress exists
- `ResponseCard` preempts `StreamCard`
- stopping a streaming session hides `StreamCard` and shows `Finalizing…`
- streaming-session errors replace `StreamCard` with `ResponseCard`
- reanchoring the pill reanchors both card surfaces

### Code changes

**New card**

- Add `StreamCard` beside [ResponseCard.swift](/Users/nitinkum/Projects/nitkrar/personal_scribe/Sources/PersonalScribeAppKit/Overlay/ResponseCard.swift):
  - builder protocol
  - presenter protocol
  - `NSPanel` implementation
  - single-line SwiftUI view

Recommended shape for this commit:

- width-only growth relative to `ResponseCard`
- single line
- rolling-tail text
- overflow mode read from `StreamingCardOverflowModePreference`

**Presenter ownership**

- Update [PillOverlayPresenter.swift](/Users/nitinkum/Projects/nitkrar/personal_scribe/Sources/PersonalScribeAppKit/Overlay/PillOverlayPresenter.swift):
  - own both card presenters
  - reanchor both on pill resize
  - hide `StreamCard` whenever `ResponseCard` becomes active

**Controller routing**

- Update [PillOverlayController.swift](/Users/nitinkum/Projects/nitkrar/personal_scribe/Sources/PersonalScribeAppKit/Overlay/PillOverlayController.swift):
  - add `applyStreamCardState(...)`
  - show/update from `snapshot.session.transcriptProgress`
  - only while `sessionState` is `.capturing` or `.holdRecording`

**Finalizing message**

- Extend [RecordingStatusCardDriver.swift](/Users/nitinkum/Projects/nitkrar/personal_scribe/Sources/PersonalScribeAppKit/Overlay/RecordingStatusCardDriver.swift) with a streaming-session finalization branch:
  - when the session is a streaming session
  - and state is `.transcribing`
  - and no higher-priority error / VAD / model-download message is active
  - return `StatusCardContent(text: "Finalizing…")`

To make that pure and stable, add a small session-owned flag on `SessionSnapshot` such as `isStreamingSession`, set at session start from the bound recipe and cleared at reset.

This avoids deriving card behavior from `snapshot.activeMode`, which can drift independently of the in-flight session.

---

## Stage F — Glue, copy cleanup, and non-goals enforcement

### Tests first

- Add/adjust only the tests needed to pin the pre-#033 cut line.

### Code changes

- Keep `CoordinatorPipelineOutputSink.deliverPartial(...)` as a no-op in [SessionCoordinator.swift](/Users/nitinkum/Projects/nitkrar/personal_scribe/Sources/PersonalScribeSession/SessionCoordinator.swift).
- Keep `PipelineContextSnapshot.streamingOutputEnabled` false for now.
- Persist and surface `bound.streamingBehavior?.liveCursorEnabled`, but treat it as runtime-inert in this commit. `#033` owns the first production branch that honors it.
- Leave [MenuBarSceneModel.swift](/Users/nitinkum/Projects/nitkrar/personal_scribe/Sources/PersonalScribeAppKit/MenuBar/MenuBarSceneModel.swift) as the sole stop-time output caller.
- Update any stale user-facing strings that still imply:
  - pill transcript text
  - live cursor typing
  - stop-time replay masquerading as “realtime”

The key invariant is: **no hidden partial-delivery consumer ships under #056**.

---

## Manual verification to add before claiming shipped

### Modes / Settings

- Creating `Streaming Dictation` from the preset popover seeds:
  - realtime on
  - live transcript card on
  - authoritative second pass on
  - VAD auto-stop off
- Global streaming defaults change newly-created streaming modes and any existing mode still using `.setting(...)`.
- Per-mode override on `Live transcript card` and `Authoritative second pass` wins over the global default.
- `StreamCard` overflow preference changes rendering without resizing height.

### Recording / overlay

- During a streaming recording, `StreamCard` appears and updates continuously with sub-EOU partials.
- If `Live transcript card` is off, no `StreamCard` appears.
- On stop, `StreamCard` disappears and `ResponseCard` shows `Finalizing…`.
- If the session errors mid-stream, `StreamCard` disappears and the error renders on `ResponseCard`.

### Finalization / output

- `second pass = off` stores/copies the streaming final.
- `second pass = on` stores/copies the batch authoritative final when available.
- If second pass fails, the session still completes using the streaming final.
- Existing stop-time auto-paste behavior still works when enabled.

---

## Post-#056 follow-up: #033

After this commit lands, `#033` picks up:

- real `PipelineOutputSink.deliverPartial(...)` consumer
- transport choice: incremental typing vs. clipboard-paste chunks
- live-cursor toggle UI
- undo grouping / pacing / Unicode semantics
- live-mode clipboard restore anchor and churn behavior

That follow-up should be additive to this implementation, not a rewrite.

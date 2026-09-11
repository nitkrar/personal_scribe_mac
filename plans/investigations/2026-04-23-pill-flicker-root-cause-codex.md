# Pill flicker root cause — Codex

## 1. Reproduction reasoning

The minimum code path is a normal successful stop from an already-live session:

- `SessionCoordinator.toggle()` routes `.recording` and `.holdRecording` through `performToggle()` (`Sources/PersonalScribeSession/SessionCoordinator.swift:98-105`).
- `performToggle()` uses two delivery paths for pipeline state: it awaits `pipeline.toggleCapture()` and then immediately calls `refreshFromPipelineSnapshot()`, while a background Task is also consuming `pipeline.snapshotStream()` (`Sources/PersonalScribeSession/SessionCoordinator.swift:242-261`, `336-349`).
- On the stop happy path, `SessionPipelineOrchestrator.stopRecordingAndRunPipeline()` publishes `.transcribing` repeatedly before one final `.idle` (`Sources/PersonalScribeSession/Pipeline/Orchestrator/SessionPipelineOrchestrator.swift:328-402`).

That is enough to reproduce the visible bug if the direct refresh applies the final `.idle` before the stream observer drains one older buffered `.transcribing` snapshot.

Existing tests almost cover this but stop too early:

- `Tests/PersonalScribeSessionTests/SessionCoordinatorHappyPathTests.swift:7-46` only collects the first four states, so it would miss a stale tail after the first `.idle`.
- `Tests/PersonalScribeCoreTests/AppStore/AppStoreTests.swift:221-297` only drives a clean fake session stream; it does not exercise the real coordinator relay that has the race.

The missing regression test is coordinator-level. The exact behavior to pin is:

`testStopPathDoesNotRepublishTranscribingAfterFinalIdle`

It should force the snapshot-stream observer to lag behind `refreshFromPipelineSnapshot()` and assert that the coordinator never emits `.transcribing` after the terminal `.idle` on a successful stop.

## 2. Root cause

The flicker is not produced by the pipeline itself or by the overlay layer independently. It is produced by an ordering race in `SessionCoordinator`.

Concrete chain:

1. `SessionPipelineOrchestrator.stopRecordingAndRunPipeline()` republishes `sessionState = .transcribing` at every stop-path stage transition:
   - enter transcription: `Sources/PersonalScribeSession/Pipeline/Orchestrator/SessionPipelineOrchestrator.swift:328-332`
   - raw transcript progress: `Sources/PersonalScribeSession/Pipeline/Orchestrator/SessionPipelineOrchestrator.swift:342-348`
   - post-processing stage: `Sources/PersonalScribeSession/Pipeline/Orchestrator/SessionPipelineOrchestrator.swift:367-372`
   - persistence stage: `Sources/PersonalScribeSession/Pipeline/Orchestrator/SessionPipelineOrchestrator.swift:383-388`
   - output stage: `Sources/PersonalScribeSession/Pipeline/Orchestrator/SessionPipelineOrchestrator.swift:392-397`
   - final success idle: `Sources/PersonalScribeSession/Pipeline/Orchestrator/SessionPipelineOrchestrator.swift:401-408`

2. The orchestrator exposes those snapshots both as a latest-value pull (`snapshot()`) and as a stream that yields every publish:
   - stream setup: `Sources/PersonalScribeSession/Pipeline/Orchestrator/SessionPipelineOrchestrator.swift:122-137`
   - per-publish stream yield: `Sources/PersonalScribeSession/Pipeline/Orchestrator/SessionPipelineOrchestrator.swift:170-175`

3. `SessionCoordinator` consumes the same pipeline state through two unsynchronized paths:
   - direct post-call refresh: `Sources/PersonalScribeSession/SessionCoordinator.swift:242-261`
   - background stream observer: `Sources/PersonalScribeSession/SessionCoordinator.swift:336-349`

4. `applyPipelineSnapshot(_:)` only compares `currentState` to `snapshot.sessionState`; it does not track freshness or revision:
   - `Sources/PersonalScribeSession/SessionCoordinator.swift:375-379`

5. Because there is no freshness token, the direct refresh can apply the newest terminal `.idle` first, while the observer path still has an older buffered `.transcribing` snapshot to deliver later. When that stale `.transcribing` finally arrives, `currentState` is already `.idle`, so the coordinator republishes `.transcribing`, and then later republishes `.idle` again when the final snapshot arrives from the observer path.

That gives the coordinator/AppStore sequence:

`.transcribing → .idle → .transcribing → .idle`

The overlay symptom follows directly from `AppStore.handleSessionStateChange(_:)`:

- every `.transcribing → .idle` edge sets `pillVisibility = .done` and schedules the done dwell (`Sources/PersonalScribeCore/AppStore/AppStore.swift:138-145`);
- any non-terminal state cancels the dwell and re-derives the pill from the current session state (`Sources/PersonalScribeCore/AppStore/AppStore.swift:155-157`, `230-277`);
- a re-derived transcribing state maps back to `.transcribing` (`Sources/PersonalScribeCore/AppStore/AppStore.swift:323-325`, `372-387`).

So the visible pill sequence becomes:

`.transcribing → .done → .transcribing → .done`

That matches the captured bug exactly.

Smallest robust fix:

- add a monotonic snapshot revision to `PipelineSnapshot` and increment it inside `SessionPipelineOrchestrator.publish(...)`;
- store the latest applied revision in `SessionCoordinator`;
- ignore any snapshot in `applyPipelineSnapshot(_:)` whose revision is older than the newest one already applied.

That preserves the current "API returns with state already refreshed" behavior from `refreshFromPipelineSnapshot()` without letting older stream elements overtake the latest snapshot. The simpler but riskier alternative is deleting the post-call refresh and choosing one delivery path.

## 3. Alternative explanations considered and ruled out

Pipeline bug: ruled out. The happy-path stop code never publishes `.idle → .transcribing → .idle`; it publishes repeated `.transcribing` and then one `.idle` (`Sources/PersonalScribeSession/Pipeline/Orchestrator/SessionPipelineOrchestrator.swift:328-402`).

AppStore timer race: ruled out. Once `snapshot.sessionState` is `.idle`, `rederivePillVisibility()` can only produce idle/hidden/loading/downloading, not `.transcribing` (`Sources/PersonalScribeCore/AppStore/AppStore.swift:248-277`, `310-387`).

Overlay-local bounce: ruled out. Production overlay wiring applies the store-derived `snapshot.pillVisibility` directly (`Sources/PersonalScribeAppKit/Overlay/PillOverlayController.swift:143-152`). The older `apply(sessionState:preparationProgress:)` compatibility mapper is not the production path (`Sources/PersonalScribeAppKit/Overlay/PillOverlayViewModel.swift:117-149`).

## 4. Blast radius

Definitely affected:

- toggle happy path stop
- hold-release happy path

Both use the same `stopRecordingAndRunPipeline()` multi-`.transcribing` stop path and the same coordinator refresh race.

Likely affected with a different visible terminal pill:

- transcription failure
- post-processing failure
- bare-orchestrator persistence failure
- bare-orchestrator output failure

Those paths also emit one or more `.transcribing` snapshots before a terminal `.error`, so the same race can surface as `.error → .transcribing → .error`.

Not affected:

- cancel from recording / hold (`discardActiveCapture()` publishes direct `.idle`: `Sources/PersonalScribeSession/Pipeline/Orchestrator/SessionPipelineOrchestrator.swift:235-253`)
- too-short stop paths (direct `.error(.recordingTooShort)`: `Sources/PersonalScribeSession/Pipeline/Orchestrator/SessionPipelineOrchestrator.swift:319-325`)
- capture failures that terminate directly in `.error` without a transcribing→terminal edge (`Sources/PersonalScribeSession/Pipeline/Orchestrator/SessionPipelineOrchestrator.swift:491-509`)

## 5. Confidence

High.

The exact symptom requires a stale `.transcribing` after a terminal state. The pipeline itself does not create that order, the AppStore cannot synthesize `.transcribing` from idle, and `SessionCoordinator` is the only layer that combines an ordered stream with a separate latest-snapshot refresh and no freshness check.

Extra data that would raise confidence from "code-proof" to "runtime-trace-proof":

- a temporary log in `SessionCoordinator.publish(_:)` that prints session state plus a snapshot revision / active stage
- a regression test that deliberately makes the observer lag behind `refreshFromPipelineSnapshot()`

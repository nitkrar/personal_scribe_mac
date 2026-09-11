# Pipeline flow audit — Codex

This audit distinguishes two layers:

- `SessionPipelineOrchestrator` publishes `PipelineSnapshot.sessionState` at the mutation sites below.
- `SessionCoordinator` republishes only when `currentState != snapshot.sessionState` (`Sources/PersonalScribeSession/SessionCoordinator.swift:375-379`), but it also performs a direct latest-snapshot refresh after each public action (`Sources/PersonalScribeSession/SessionCoordinator.swift:242-261`) while a background Task is consuming `snapshotStream()` (`Sources/PersonalScribeSession/SessionCoordinator.swift:336-349`).

That distinction matters because the raw orchestrator publishes are ordered and explicit, while the coordinator/AppStore relay can reorder stale stop-path snapshots unless freshness is tracked.

## 1. Toggle start

Entry: `coordinator.toggle()` or `startIfIdle()` from `.idle` (`Sources/PersonalScribeSession/SessionCoordinator.swift:98-115`).

| Step | State published | Activity during | Source file:line |
| --- | --- | --- | --- |
| 1 | `.recording` | `toggleCapture()` routes `.idle` into `startRecording()` after capture start, output reset, and background prepare kick-off | `Sources/PersonalScribeSession/Pipeline/Orchestrator/SessionPipelineOrchestrator.swift:73-76`, `185-228`, especially `215-221` |

Terminal state: `.recording`.

Coverage:

- `Tests/PersonalScribeSessionTests/SessionCoordinatorHoldPathTests.swift:7-17`
- start is also exercised inside `Tests/PersonalScribeSessionTests/SessionCoordinatorHappyPathTests.swift:7-46`

## 2. Toggle stop (happy path)

Entry: `coordinator.toggle()` from `.recording` (`Sources/PersonalScribeSession/SessionCoordinator.swift:98-105`, `242-245`).

| Step | State published | Activity during | Source file:line |
| --- | --- | --- | --- |
| 1 | `.transcribing` | stop accepted a >=1s capture and entered transcription | `Sources/PersonalScribeSession/Pipeline/Orchestrator/SessionPipelineOrchestrator.swift:301-332` |
| 2 | `.transcribing` | raw transcription result stored in `transcriptProgress` | `Sources/PersonalScribeSession/Pipeline/Orchestrator/SessionPipelineOrchestrator.swift:334-348` |
| 3 | `.transcribing` | post-processing finished; cleaned progress published | `Sources/PersonalScribeSession/Pipeline/Orchestrator/SessionPipelineOrchestrator.swift:352-372` |
| 4 | `.transcribing` | persistence stage entered | `Sources/PersonalScribeSession/Pipeline/Orchestrator/SessionPipelineOrchestrator.swift:376-388` |
| 5 | `.transcribing` | output stage entered | `Sources/PersonalScribeSession/Pipeline/Orchestrator/SessionPipelineOrchestrator.swift:392-397` |
| 6 | `.idle` | final result stored; activeStage cleared | `Sources/PersonalScribeSession/Pipeline/Orchestrator/SessionPipelineOrchestrator.swift:399-408` |

Ordered coordinator/AppStore sequence should collapse to:

`.recording → .transcribing → .idle`

But this is the load-bearing race flow. Because the coordinator also calls `refreshFromPipelineSnapshot()` after stop (`Sources/PersonalScribeSession/SessionCoordinator.swift:242-261`), an older buffered `.transcribing` can arrive after step 6 through the stream observer (`Sources/PersonalScribeSession/SessionCoordinator.swift:336-349`). That can surface at the AppStore as:

`.recording → .transcribing → .idle → .transcribing → .idle`

Coverage:

- `Tests/PersonalScribeSessionTests/Pipeline/SessionPipelineOrchestratorTests.swift:20-109`
- `Tests/PersonalScribeSessionTests/SessionCoordinatorHappyPathTests.swift:7-46`

Coverage gap:

- no coordinator-level test proves there is no stale `.transcribing` after the first final `.idle`

## 3. Toggle stop (too short)

Entry: `coordinator.toggle()` from `.recording` with `< 1s` buffered audio.

| Step | State published | Activity during | Source file:line |
| --- | --- | --- | --- |
| 1 | `.error(.recordingTooShort)` | stop-path duration guard fails before any transcription call | `Sources/PersonalScribeSession/Pipeline/Orchestrator/SessionPipelineOrchestrator.swift:316-325` |

Terminal state: `.error(.recordingTooShort)`.

Coverage:

- `Tests/PersonalScribeSessionTests/Pipeline/SessionPipelineOrchestratorTests.swift:157-199`
- `Tests/PersonalScribeSessionTests/SessionCoordinatorErrorTests.swift:50-97`

## 4. Hold start

Entry: `startHoldIfIdle()` from `.idle` (`Sources/PersonalScribeSession/SessionCoordinator.swift:117-127`, `248-251`).

| Step | State published | Activity during | Source file:line |
| --- | --- | --- | --- |
| 1 | `.holdRecording` | hold path publishes eagerly before awaiting `capture.start()` | `Sources/PersonalScribeSession/Pipeline/Orchestrator/SessionPipelineOrchestrator.swift:256-299`, especially `270-276` |

Terminal state: `.holdRecording`.

Coverage:

- `Tests/PersonalScribeSessionTests/Pipeline/SessionPipelineOrchestratorTests.swift:657-684`
- `Tests/PersonalScribeSessionTests/SessionCoordinatorHoldPathTests.swift:120-130`

## 5. Hold release (happy path)

Entry: `stopIfActive()` from `.holdRecording` (`Sources/PersonalScribeSession/SessionCoordinator.swift:138-150`).

| Step | State published | Activity during | Source file:line |
| --- | --- | --- | --- |
| 1 | `.transcribing` | hold capture stopped; pipeline entered transcription | `Sources/PersonalScribeSession/Pipeline/Orchestrator/SessionPipelineOrchestrator.swift:301-332` |
| 2 | `.transcribing` | raw transcription result published | `Sources/PersonalScribeSession/Pipeline/Orchestrator/SessionPipelineOrchestrator.swift:334-348` |
| 3 | `.transcribing` | cleaned post-processing result published | `Sources/PersonalScribeSession/Pipeline/Orchestrator/SessionPipelineOrchestrator.swift:352-372` |
| 4 | `.transcribing` | persistence stage entered | `Sources/PersonalScribeSession/Pipeline/Orchestrator/SessionPipelineOrchestrator.swift:376-388` |
| 5 | `.transcribing` | output stage entered | `Sources/PersonalScribeSession/Pipeline/Orchestrator/SessionPipelineOrchestrator.swift:392-397` |
| 6 | `.idle` | final success snapshot | `Sources/PersonalScribeSession/Pipeline/Orchestrator/SessionPipelineOrchestrator.swift:399-408` |

Ordered coordinator/AppStore sequence should collapse to:

`.holdRecording → .transcribing → .idle`

It has the same stale-state race as flow 2 because it uses the same stop pipeline and the same coordinator refresh path.

Coverage:

- `Tests/PersonalScribeSessionTests/Pipeline/SessionPipelineOrchestratorTests.swift:611-649`
- `Tests/PersonalScribeSessionTests/SessionCoordinatorHoldPathTests.swift:160-171`

Coverage gap:

- no coordinator-level test proves there is no stale `.transcribing` after final `.idle`

## 6. Hold release (too short)

Entry: `stopIfActive()` from `.holdRecording` with `< 1s` buffered audio.

| Step | State published | Activity during | Source file:line |
| --- | --- | --- | --- |
| 1 | `.error(.recordingTooShort)` | same duration guard as toggle-stop too-short | `Sources/PersonalScribeSession/Pipeline/Orchestrator/SessionPipelineOrchestrator.swift:316-325` |

Terminal state: `.error(.recordingTooShort)`.

Coverage:

- no direct orchestrator or coordinator test pins the hold-path too-short sequence

## 7. Cancel from recording

Entry: `cancelIfActive()` from `.recording` (`Sources/PersonalScribeSession/SessionCoordinator.swift:153-163`, `254-256`).

| Step | State published | Activity during | Source file:line |
| --- | --- | --- | --- |
| 1 | `.idle` | `discardActiveCapture()` stops capture, drops buffers, clears stage/progress, skips transcription and output | `Sources/PersonalScribeSession/Pipeline/Orchestrator/SessionPipelineOrchestrator.swift:231-253` |

Full-session ordered sequence:

`.idle → .recording → .idle`

Coverage:

- `Tests/PersonalScribeSessionTests/Pipeline/SessionPipelineOrchestratorTests.swift:691-735`
- `Tests/PersonalScribeSessionTests/Pipeline/SessionPipelineOrchestratorTests.swift:791-825`
- `Tests/PersonalScribeSessionTests/SessionCoordinatorHoldPathTests.swift:202-215`

Coverage gap:

- no coordinator `stateStream()` test pins the exact `.idle → .recording → .idle` sequence

## 8. Cancel from hold

Entry: `cancelIfActive()` from `.holdRecording`.

| Step | State published | Activity during | Source file:line |
| --- | --- | --- | --- |
| 1 | `.idle` | same discard path as flow 7 | `Sources/PersonalScribeSession/Pipeline/Orchestrator/SessionPipelineOrchestrator.swift:231-253` |

Full-session ordered sequence:

`.idle → .holdRecording → .idle`

Coverage:

- `Tests/PersonalScribeSessionTests/Pipeline/SessionPipelineOrchestratorTests.swift:741-774`
- `Tests/PersonalScribeSessionTests/SessionCoordinatorHoldPathTests.swift:217-229`

Coverage gap:

- no coordinator `stateStream()` test pins the exact `.idle → .holdRecording → .idle` sequence

## 9. Capture failure

Interpretation used here: capture stream throws after recording has already started, which is what `FakeAudioCapturing(error:)` exercises.

| Step | State published | Activity during | Source file:line |
| --- | --- | --- | --- |
| 1 | `.recording` | normal start publish | `Sources/PersonalScribeSession/Pipeline/Orchestrator/SessionPipelineOrchestrator.swift:215-221` |
| 2 | `.error(.audioEngineFailure)` | live capture stream throws; `consumeCaptureStream` maps it through `handleStageFailure` | `Sources/PersonalScribeSession/Pipeline/Orchestrator/SessionPipelineOrchestrator.swift:491-509` |

Terminal state: `.error(.audioEngineFailure)`.

Coverage:

- `Tests/PersonalScribeSessionTests/Pipeline/SessionPipelineOrchestratorTests.swift:111-155`
- `Tests/PersonalScribeSessionTests/SessionCoordinatorErrorTests.swift:7-48`
- stop-after-failure preservation is also pinned by `Tests/PersonalScribeSessionTests/SessionCoordinatorErrorTests.swift:147-180`

## 10. Transcription failure

Entry: stop path reaches `runTranscription(...)`, and the transcriber throws.

| Step | State published | Activity during | Source file:line |
| --- | --- | --- | --- |
| 1 | `.transcribing` | entered transcription | `Sources/PersonalScribeSession/Pipeline/Orchestrator/SessionPipelineOrchestrator.swift:328-332` |
| 2 | `.error(.transcriptionFailure)` | `runTranscription` maps the throw to stage `.transcription`; stop path catches and publishes error | `Sources/PersonalScribeSession/Pipeline/Orchestrator/SessionPipelineOrchestrator.swift:409-423`, `504-509` |

Terminal state: `.error(.transcriptionFailure)`.

Coverage:

- no direct session test pins this flow

## 11. Post-processing failure

Entry: transcription succeeds, `runPostProcessing(...)` throws.

| Step | State published | Activity during | Source file:line |
| --- | --- | --- | --- |
| 1 | `.transcribing` | entered transcription | `Sources/PersonalScribeSession/Pipeline/Orchestrator/SessionPipelineOrchestrator.swift:328-332` |
| 2 | `.transcribing` | raw transcription result published | `Sources/PersonalScribeSession/Pipeline/Orchestrator/SessionPipelineOrchestrator.swift:334-348` |
| 3 | `.error(.transcriptionFailure)` | `runPostProcessing` maps the throw to stage `.postProcessing`; stop path catches and publishes error | `Sources/PersonalScribeSession/Pipeline/Orchestrator/SessionPipelineOrchestrator.swift:409-434`, `504-509` |

Terminal state: `.error(.transcriptionFailure)`.

Coverage:

- `Tests/PersonalScribeSessionTests/Pipeline/SessionPipelineOrchestratorTests.swift:514-540`

Coverage gap:

- no coordinator-level test

## 12. Persistence failure

There are two different answers depending on which layer you audit.

Bare orchestrator with a throwing `persistenceHandler`:

| Step | State published | Activity during | Source file:line |
| --- | --- | --- | --- |
| 1 | `.transcribing` | entered transcription | `Sources/PersonalScribeSession/Pipeline/Orchestrator/SessionPipelineOrchestrator.swift:328-332` |
| 2 | `.transcribing` | raw transcription result published | `Sources/PersonalScribeSession/Pipeline/Orchestrator/SessionPipelineOrchestrator.swift:334-348` |
| 3 | `.transcribing` | post-processing result published | `Sources/PersonalScribeSession/Pipeline/Orchestrator/SessionPipelineOrchestrator.swift:352-372` |
| 4 | `.transcribing` | persistence stage entered | `Sources/PersonalScribeSession/Pipeline/Orchestrator/SessionPipelineOrchestrator.swift:376-388` |
| 5 | `.error(.transcriptionFailure)` | `persist(...)` maps the throw to stage `.persistence`; stop path catches and publishes error | `Sources/PersonalScribeSession/Pipeline/Orchestrator/SessionPipelineOrchestrator.swift:409-466`, `504-509` |

Production `SessionCoordinator` wiring with a `TranscriptRepository` is different:

- `makePersistenceHandler(...)` catches repository append errors, logs them, and does not rethrow (`Sources/PersonalScribeSession/SessionCoordinator.swift:319-334`).
- So the production coordinator does not publish a persistence-failure error state; it continues to the same `.transcribing → .idle` terminal sequence as the happy path.

Coverage:

- bare-orchestrator failure path: `Tests/PersonalScribeSessionTests/Pipeline/SessionPipelineOrchestratorTests.swift:542-574`
- production coordinator failing-store path: no direct test

## 13. Output failure

Again, the answer differs by layer.

Bare orchestrator with a throwing output sink:

| Step | State published | Activity during | Source file:line |
| --- | --- | --- | --- |
| 1 | `.transcribing` | entered transcription | `Sources/PersonalScribeSession/Pipeline/Orchestrator/SessionPipelineOrchestrator.swift:328-332` |
| 2 | `.transcribing` | raw transcription result published | `Sources/PersonalScribeSession/Pipeline/Orchestrator/SessionPipelineOrchestrator.swift:334-348` |
| 3 | `.transcribing` | post-processing result published | `Sources/PersonalScribeSession/Pipeline/Orchestrator/SessionPipelineOrchestrator.swift:352-372` |
| 4 | `.transcribing` | persistence stage entered | `Sources/PersonalScribeSession/Pipeline/Orchestrator/SessionPipelineOrchestrator.swift:376-388` |
| 5 | `.transcribing` | output stage entered | `Sources/PersonalScribeSession/Pipeline/Orchestrator/SessionPipelineOrchestrator.swift:392-397` |
| 6 | `.error(.transcriptionFailure)` | `deliverPartialIfEnabled(...)` or `deliverFinal(...)` maps the throw to stage `.output`; stop path catches and publishes error | `Sources/PersonalScribeSession/Pipeline/Orchestrator/SessionPipelineOrchestrator.swift:409-446`, `469-474`, `504-509` |

Production `SessionCoordinator` wiring is a no-op here:

- `CoordinatorPipelineOutputSink` has empty `deliverPartial`, `deliverFinal`, and `resetForNewSession` implementations (`Sources/PersonalScribeSession/SessionCoordinator.swift:620-625`).
- So a paste/clipboard failure is not a session-pipeline failure flow in this layer today.

Coverage:

- bare-orchestrator failure path: `Tests/PersonalScribeSessionTests/Pipeline/SessionPipelineOrchestratorTests.swift:576-603`
- production coordinator output-failure path: unreachable with current sink

## 14. Model-download overlay overlaps

The session-state stream does not gain a new state for download/loading. The active flow still publishes the same `SessionState` values as flows 1, 2, 4, or 5.

What changes is AppStore-derived pill visibility:

| Step | State published | Activity during | Source file:line |
| --- | --- | --- | --- |
| 1 | `.recording` or `.holdRecording` | session remains an active recording session; AppStore still prioritizes recording / hold over progress | `Sources/PersonalScribeCore/AppStore/AppStore.swift:315-321` |
| 2 | `.transcribing` | session enters transcribing normally | `Sources/PersonalScribeSession/Pipeline/Orchestrator/SessionPipelineOrchestrator.swift:328-332` |
| 3 | `.idle` or `.error(...)` | terminal state depends on the underlying flow | `Sources/PersonalScribeSession/Pipeline/Orchestrator/SessionPipelineOrchestrator.swift:401-408`, `504-509` |

Overlay behavior during that unchanged state stream:

- `AppStore.derivePillVisibility(...)` maps `.transcribing + downloading/loading` to `.downloading(...)` / `.loading` instead of `.transcribing` (`Sources/PersonalScribeCore/AppStore/AppStore.swift:323-325`, `372-385`).
- The recording-status card is separately derived from `SessionState + ModelDownloadProgress` and only appears during `.recording`, `.holdRecording`, or `.transcribing` while progress is active (`Sources/PersonalScribeAppKit/Overlay/RecordingStatusCardDriver.swift:13-53`, `Sources/PersonalScribeAppKit/Overlay/PillOverlayController.swift:149-170`).

Coverage:

- recording-progress precedence: `Tests/PersonalScribeCoreTests/AppStore/AppStoreTests.swift:6-56`
- recording/transcribing response-card strings: `Tests/PersonalScribeAppKitTests/Overlay/RecordingStatusCardDriverTests.swift:5-120`

Coverage gap:

- no `AppStore` test pins `.transcribing + downloading/loading` mapping directly

## Summary

Duplicate consecutive publishes:

- The orchestrator deliberately republishes `.transcribing` without an intervening session-state change on flows 2, 5, 11, 12 (bare orchestrator), and 13 (bare orchestrator). Those duplicate publishes are carrying stage/progress changes, not a separate session-state machine transition.

Publishes of `.idle` from non-terminal code paths:

- None in the 14 audited flows.
- Outside this list, retrying from `.error` does publish an intermediate `.idle` before starting again (`Sources/PersonalScribeSession/Pipeline/Orchestrator/SessionPipelineOrchestrator.swift:82-88`, `97-103`).

Terminal `.idle` predecessor check:

- Success flows 2 and 5 reach final `.idle` from `.transcribing`.
- Cancel flows 7 and 8 reach final `.idle` through the direct discard path.
- No audited flow reaches final `.idle` from an unexpected predecessor.

Flows that can make `AppStore.handleSessionStateChange` derive stale `.done` or `.error`:

- Flow 2 and flow 5 definitely can: the coordinator combines a latest-snapshot refresh with a lagging snapshot-stream observer and does not track snapshot freshness (`Sources/PersonalScribeSession/SessionCoordinator.swift:242-261`, `336-379`).
- The same mechanism can also stale-flip the terminal pill on flows 11, 12 (bare orchestrator), and 13 (bare orchestrator), but those would show as `.error → .transcribing → .error` rather than `.done → .transcribing → .done`.

Missing test coverage by flow:

- Flow 2: missing coordinator regression test for "no stale `.transcribing` after first final `.idle`".
- Flow 5: same missing coordinator regression test on the hold path.
- Flow 6: no direct hold-too-short sequence test.
- Flow 10: no direct transcription-failure sequence test.
- Flow 12: no coordinator test for failing `TranscriptRepository.append`; production wiring swallows the error.
- Flow 13: no production coordinator test because the current output sink cannot fail.
- Flow 14: no direct `AppStore` test for `.transcribing + downloading/loading`.

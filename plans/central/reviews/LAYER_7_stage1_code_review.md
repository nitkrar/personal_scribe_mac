# Layer 7 Stage 1 Code Review

## Verdict
Changes required. Stage 1 lands the planned contract surface under the new pipeline-only directories and does not migrate existing app consumers yet, but the persistence path currently violates its own dependency invariant: a successful run can hold a non-nil `SQLiteTranscriptStore` and still skip SQLite entirely because `persist(_:)` consults only `persistenceHandler`. I also found a smaller snapshot-fidelity issue around live `recordingDuration` publication that should be addressed before Stage 2 starts depending on `PipelineSnapshot` as the authoritative live surface.

## Summary Counts
| Severity | Count |
| --- | ---: |
| Blocker | 1 |
| Major | 0 |
| Minor | 1 |
| Nit | 0 |

## Plan Fidelity
| Type | Present | Matches plan | Notes |
| --- | --- | --- | --- |
| `PipelineStageID` | Yes | Yes | Cases match `.capture/.transcription/.postProcessing/.persistence/.output` in `Sources/SeshatSession/Pipeline/Contracts/PipelineStageID.swift:1-7`. |
| `TranscriptProgress` | Yes | Yes | Fields and initializer match the plan in `Sources/SeshatSession/Pipeline/Contracts/TranscriptProgress.swift:1-18`. |
| `PipelineContextSnapshot` | Yes | Yes | Fields match the plan in `Sources/SeshatSession/Pipeline/Contracts/PipelineContextSnapshot.swift:3-19`. |
| `PipelineSnapshot` | Yes | Yes | Surface matches the plan in `Sources/SeshatSession/Pipeline/Contracts/PipelineSnapshot.swift:3-25`; see Finding 2 for a publication gap, not a type-shape gap. |
| `PostProcessingContext` | Yes | Yes | Fields match the plan in `Sources/SeshatSession/Pipeline/PostProcessing/PostProcessingContext.swift:3-26`. |
| `SessionPipelining` | Yes | No | Surface is present in `Sources/SeshatSession/Pipeline/Contracts/SessionPipelining.swift:3-10`, but it now requires `Actor` in addition to `Sendable`. That is coherent with Swift 6 isolation, but it is a contract deviation from the plan text. |
| `PostProcessingStage` | Yes | Yes | Matches `name` plus `apply(_:context:)` in `Sources/SeshatSession/Pipeline/PostProcessing/PostProcessingStage.swift:1-4`. |
| `PostProcessingPipeline` | Yes | Yes | Matches `run(_:context:)` in `Sources/SeshatSession/Pipeline/PostProcessing/PostProcessingPipeline.swift:1-3`. |
| `PipelineOutputSink` | Yes | Yes | Matches `deliverPartial`, `deliverFinal`, and `resetForNewSession` in `Sources/SeshatSession/Pipeline/Contracts/PipelineOutputSink.swift:3-6`. |
| `PipelineContextProviding` | Yes | Yes | Matches the synchronous `currentContext()` surface in `Sources/SeshatSession/Pipeline/Contracts/PipelineContextProviding.swift:1-3`. |
| `DefaultPostProcessingPipeline` | Yes | Yes | Default stage order is `FillerRemovalStage()` then `BasicPunctuationStage()` in `Sources/SeshatSession/Pipeline/PostProcessing/DefaultPostProcessingPipeline.swift:1-18`. |
| `FillerRemovalStage` + `BasicPunctuationStage` | Yes | Yes | Both exist and preserve the old `PostProcessor.clean(_:)` behavior from `Sources/SeshatCore/PostProcessor.swift:29-76`; see `Sources/SeshatSession/Pipeline/PostProcessing/FillerRemovalStage.swift:3-54` and `Sources/SeshatSession/Pipeline/PostProcessing/BasicPunctuationStage.swift:3-23`. |
| `SessionPipelineOrchestrator` | Yes | Yes | Present as a `public actor` in `Sources/SeshatSession/Pipeline/Orchestrator/SessionPipelineOrchestrator.swift:4-475`; its staged sequence is exercised in `Tests/SeshatSessionTests/Pipeline/SessionPipelineOrchestratorTests.swift:20-106`. |

Stage 1 also implements the plan-approved internal bridge error type `PipelineStageFailure` in `Sources/SeshatSession/Pipeline/Contracts/PipelineStageFailure.swift:3-13`.

## Correctness Findings
1. Persistence invariant can disable SQLite append on a successful run

Severity: Blocker

Title: Persistence can be silently disabled when `transcriptStore` is present but `persistenceHandler` is `nil`

Location: `Sources/SeshatSession/Pipeline/Orchestrator/SessionPipelineOrchestrator.swift:12,25-75,347-364`; `Tests/SeshatSessionTests/Pipeline/SessionPipelineOrchestratorTests.swift:385-407,509-535`

Observation: `persist(_:)` writes only through `persistenceHandler`, not `transcriptStore`.

```swift
private func persist(_ result: TranscriptionResult) async throws {
    guard let persistenceHandler else {
        return
    }
```

The designated initializer stores `transcriptStore` and `persistenceHandler` independently:

```swift
self.transcriptStore = transcriptStore
self.persistenceHandler = persistenceHandler
```

The failing SQLite test constructs the actor through the internal initializer helper at `Tests/SeshatSessionTests/Pipeline/SessionPipelineOrchestratorTests.swift:509-535`, passes `transcriptStore: store`, and leaves `persistenceHandler` at its default `nil`. That leaves the actor in a split-brain configuration where SQLite exists as a dependency, but the only code path that can actually append is disabled.

Impact: A transcription can complete all the way to `.idle` with a non-nil `lastCompletedResult`, yet no `TranscriptEntry` ever reaches SQLite. The current red test is one proof point, but the broader issue is the invariant leak inside `SessionPipelineOrchestrator` itself: any in-module caller that reaches the designated initializer with `transcriptStore != nil` and `persistenceHandler == nil` gets silent data loss.

Recommendation: Collapse persistence wiring to one source of truth. The clean fix is to remove the stored `transcriptStore`/designated-init parameter entirely, keep only `persistenceHandler` as the actor's executable dependency, and have the public initializer synthesize that closure from `SQLiteTranscriptStore`. If the designated initializer must remain for tests, it should still derive an effective handler from `transcriptStore` whenever the caller passes `nil`, and tests should cover both the injected-failure path and the real-`SQLiteTranscriptStore` path.

### Root cause
The root cause is not SQLite and not the `persist(_:)` stage sequencing. The root cause is that `SessionPipelineOrchestrator` models persistence twice, once as a stored dependency (`transcriptStore`) and again as the executable dependency (`persistenceHandler`), but only the public initializer keeps those two values in sync. The designated initializer accepts an impossible state, and `persist(_:)` trusts only the closure. The failing test simply reaches that invalid state through `@testable` access.

### Proposed fix
Preferred fix:

1. Delete the stored `transcriptStore` property from `SessionPipelineOrchestrator`.
2. Keep the public initializer that accepts `transcriptStore` and convert it immediately into a `persistenceHandler`.
3. Keep a single internal initializer that accepts `persistenceHandler` only for failure injection tests.
4. Add a regression test that constructs the actor through the public `transcriptStore` initializer and proves `SQLiteTranscriptStore.count()` reaches `1`.

Minimal safe fix if the initializer shape must stay as-is:

1. Compute `effectivePersistenceHandler = persistenceHandler ?? transcriptStore.map { store in { entry in try await store.append(entry) } }` inside the designated initializer.
2. Store only `effectivePersistenceHandler` on the actor.
3. Retain the current persistence-failure injection test by passing an explicit failing closure.

2. Live `recordingDuration` updates never reach `snapshotStream()` subscribers

Severity: Minor

Title: `recordingDuration` is mutated off the published snapshot path during capture

Location: `Sources/SeshatSession/Pipeline/Orchestrator/SessionPipelineOrchestrator.swift:148-154,182-188,389-394`; `Tests/SeshatSessionTests/Pipeline/SessionPipelineOrchestratorTests.swift:20-106,278-353`

Observation: `snapshotContinuations` are driven only by `publish(_:)` at `Sources/SeshatSession/Pipeline/Orchestrator/SessionPipelineOrchestrator.swift:148-154`, but `consumeCaptureStream(_:)` updates `currentSnapshot.recordingDuration` directly:

```swift
for try await buffer in stream {
    bufferedAudio.append(buffer)
    currentSnapshot.recordingDuration = (currentSnapshot.recordingDuration ?? .zero) + buffer.duration
}
```

The start-recording publish sets `.zero` once at `Sources/SeshatSession/Pipeline/Orchestrator/SessionPipelineOrchestrator.swift:182-188`, after which no additional snapshot is emitted until a later stage transition.

Impact: `snapshot()` callers can read the up-to-date duration, but `snapshotStream()` subscribers see stale duration while capture is live. That weakens the plan's "single source of truth for UI/state-store subscribers" guarantee in `PipelineSnapshot`, and it is currently untested.

Recommendation: Either emit snapshot updates when duration changes, or explicitly narrow the contract and document that `recordingDuration` is only meaningful at stage boundaries/finalization. In either case, add a regression test for the chosen behavior.

## Swift 6 Concurrency
The snapshot/value surface is in good shape for Swift 6. `PipelineStageID`, `TranscriptProgress`, `PipelineContextSnapshot`, `PipelineSnapshot`, and `PostProcessingContext` are explicitly `Sendable`, and their stored types are already `Sendable` in core (`Sources/SeshatCore/ModeDescriptor.swift:3-23`, `Sources/SeshatCore/SessionState.swift:1-6`, `Sources/SeshatCore/TranscriptionResult.swift:1-30`). I did not see a raw actor data race in `SessionPipelineOrchestrator`; its mutable state remains actor-isolated in `Sources/SeshatSession/Pipeline/Orchestrator/SessionPipelineOrchestrator.swift:14-23`.

`SessionPipelining` now requires actor conformers in `Sources/SeshatSession/Pipeline/Contracts/SessionPipelining.swift:3-10`, and the contract test follows that shape with `StubPipeline` as an actor in `Tests/SeshatSessionTests/Pipeline/Contracts/PipelineContractTests.swift:93-136`. That deviation from the plan is reasonable under Swift 6, because the synchronous `snapshot()` and `snapshotStream()` requirements are actor-isolated in the live implementation. The plan and future hand-offs should be updated to reflect that shipped contract.

`prepareTranscriberInBackground()` uses `Task.detached` in `Sources/SeshatSession/Pipeline/Orchestrator/SessionPipelineOrchestrator.swift:455-468`, but the current concrete transcribers are actors (`Sources/SeshatTranscription/FluidAudioTranscriber.swift:12-21`, `Sources/SeshatTranscription/Models/Selection/ModelAwareFluidAudioTranscriber.swift:5-16`), so calls remain serialized. The residual risk here is stale-state publication, not unsafe memory access.

## Stage-1 Scope Check
Pass. The Stage 1 commit `f395327` adds only new files under `Sources/SeshatSession/Pipeline/*` and `Tests/SeshatSessionTests/Pipeline/*`, which matches the plan's parallel-build scope. Current trunk still retains the legacy inline lifecycle in `Sources/SeshatSession/SessionCoordinator.swift:5-242`, including capture, transcription, post-processing, and SQLite persistence, and current references to `SessionPipelineOrchestrator` are confined to the new pipeline files and tests. I did not find evidence that Stage 1 migrated the existing `SessionCoordinator`.

## Test Coverage Gaps
The biggest coverage hole is the initializer invariant behind Finding 1. `testSuccessfulTranscriptionAppendsEntryToSQLiteStore` at `Tests/SeshatSessionTests/Pipeline/SessionPipelineOrchestratorTests.swift:385-415` intends to exercise real SQLite, but the shared helper at `Tests/SeshatSessionTests/Pipeline/SessionPipelineOrchestratorTests.swift:509-535` always routes through the internal initializer. There is no regression that explicitly exercises the public `transcriptStore` initializer path in `Sources/SeshatSession/Pipeline/Orchestrator/SessionPipelineOrchestrator.swift:25-52`.

The suite also lacks a production-like batch-only success-path test after the backlog deferral. The happy-path and output-failure tests that drive partial delivery both enable streaming output (`Tests/SeshatSessionTests/Pipeline/SessionPipelineOrchestratorTests.swift:20-106,479-507`), but `plans/backlog/pipeline-streaming-defer.md:8-18` says Stage 2 production code must keep `streamingOutputEnabled == false` and never call `deliverPartial(_:)`. Add a success-path test that proves snapshots still carry transcript progress while the sink receives only `deliverFinal(_:)`.

Finally, there is no test asserting the intended semantics of live `recordingDuration` on `snapshotStream()`. The suite covers final snapshot sequencing (`Tests/SeshatSessionTests/Pipeline/SessionPipelineOrchestratorTests.swift:20-106`) and audio-level fan-out (`Tests/SeshatSessionTests/Pipeline/SessionPipelineOrchestratorTests.swift:278-353`), but not incremental duration publication during capture.

## Cross-Layer Concerns
The dormant streaming surface is real in Stage 1. `PipelineOutputSink` defines `deliverPartial(_:)` in `Sources/SeshatSession/Pipeline/Contracts/PipelineOutputSink.swift:3-6`, `PipelineContextSnapshot` carries `streamingOutputEnabled` in `Sources/SeshatSession/Pipeline/Contracts/PipelineContextSnapshot.swift:3-19`, and the orchestrator gates live partial delivery in `Sources/SeshatSession/Pipeline/Orchestrator/SessionPipelineOrchestrator.swift:335-345`. Per `plans/backlog/pipeline-streaming-defer.md:8-18`, Stage 2 production composition must keep that flag false and treat the existing true-flag tests as isolation-only coverage, not as permission to wire incremental output yet.

Layer 5 ↔ Layer 7 ownership is still the main structural boundary to watch. Stage 1 ships a Layer 7-local `PipelineOutputSink` abstraction and calls it directly from `deliverPartialIfEnabled(_:)` and `deliverFinal(_:)` in `Sources/SeshatSession/Pipeline/Orchestrator/SessionPipelineOrchestrator.swift:335-372`. That is acceptable for the parallel-build slice, but Stage 2 should adapt Layer 5's `OutputService` (`Sources/SeshatCore/Output/OutputService.swift:1-5`) into this seam rather than letting Layer 7 become a second output-policy owner.

The Layer 6 boundary needs similar discipline. `PipelineContextSnapshot` duplicates `activeMode`, `activeAIModelID`, and `systemPrompt` in `Sources/SeshatSession/Pipeline/Contracts/PipelineContextSnapshot.swift:3-19`, even though `ModeDescriptor` already carries the AI fields in `Sources/SeshatCore/ModeDescriptor.swift:3-23` and Layer 6 owns active-model selection through `ActiveModelDescriptor` in `Sources/SeshatCore/Models/Selection/ActiveModelDescriptor.swift:3-13`. `PipelineContextProviding` should stay a projection layer over existing model-selection state, not a new owner.

## Code Quality / Complexity
`SessionPipelineOrchestrator` is currently 472 LoC (`Sources/SeshatSession/Pipeline/Orchestrator/SessionPipelineOrchestrator.swift:4-475`) and combines at least six responsibilities: capture lifecycle, snapshot publication, audio-level multiplexing, transcript revisioning, post-processing, and persistence/output side effects. The size alone is manageable for Stage 1, but the important signal is the redundant state it already carries.

The clearest complexity smell is the duplicated persistence wiring in `transcriptStore` plus `persistenceHandler` (`Sources/SeshatSession/Pipeline/Orchestrator/SessionPipelineOrchestrator.swift:7,12,25-75,347-364`), which directly caused Finding 1. The second duplication is `activeContext` plus `currentSnapshot.context` (`Sources/SeshatSession/Pipeline/Orchestrator/SessionPipelineOrchestrator.swift:14-15,167-188,240-246,299-306`); that one is still coherent, but it increases drift risk as more Stage 2 consumers start reading snapshots directly.

Before Stage 2 broadens adoption, I would keep the external API stable and trim internal complexity by extracting at least one smaller seam: either a persistence/output effect runner or a snapshot-publishing helper that owns stage transitions and context propagation. That reduces the chance of another invariant split while app consumers are being migrated.

## Summary
- Stage 1 mostly matches the plan: the contract types, default post-processing chain, and public actor orchestrator all exist under the new pipeline-only directories.
- Changes are still required before Stage 2 because the persistence path accepts `transcriptStore != nil` with no executable handler, which causes silent SQLite skip on a successful run.
- `SessionPipelining` now ships as an actor-only protocol under Swift 6; the plan and future hand-offs should reflect that explicit contract change.
- `PipelineSnapshot.recordingDuration` is not yet a fully live stream surface because capture-time updates bypass `publish(_:)`.
- Keep the streaming surface dormant in production Stage 2 wiring: `streamingOutputEnabled` should stay `false`, and production sinks should see only `deliverFinal(_:)` until the separate stream-build slice lands.
- Bridge Layer 5 output and Layer 6 model-selection into Layer 7 via thin adapters; do not let Stage 2 create new output or model-selection owners inside the pipeline layer.

# Layer 6 Stage 2 Code Review

> Written by main-session Claude after 3 consecutive worktree-review-agent dispatches died silently without commits. Review is based on direct code inspection of `a3a0ba8` + `e299b2e`.

## Verdict

APPROVED-WITH-NITS.

Finding counts: Critical 0 / Major 0 / Minor 2 / Nit 1.

## Scope reviewed

- Primary commit: `a3a0ba8` — `trunk: step model-selection.2 — Layer 6 Stage 2 consumer swap (descriptor-driven version selection)`
- Follow-up test fix: `e299b2e` — `trunk: layer 6 stage 2 — fix MenuBarSceneModel preparation-progress test regression`
- Inputs read in full: `plans/central/LAYER_6_model_selection.md`, `plans/central/reviews/LAYER_6_stage1_code_review.md`, `Sources/SeshatSession/SessionCoordinator.swift`, `Sources/SeshatAppKit/Composition/AppComposition.swift`, `Sources/SeshatTranscription/FluidAudioInferenceClient.swift`, `Sources/SeshatTranscription/FluidAudioTranscriber.swift`, `Tests/SeshatSessionTests/Models/Selection/SessionCoordinatorModelSelectionTests.swift`, `Tests/SeshatTranscriptionTests/Models/Selection/FluidAudioTranscriberRuntimeVariantTests.swift`.

## Plan fidelity

- ✅ `FluidAudioInferenceClient.loadModel` no longer hardcodes `.v2` — it now accepts a `FluidAudioRuntimeVariant` derived from the active descriptor (`Sources/SeshatTranscription/FluidAudioInferenceClient.swift:15`).
- ✅ `SessionCoordinator` has a second public `init(capture:modelService:transcriberProvider:logger:transcriptStore:)` that resolves descriptors per-recording. The legacy `init(capture:transcriber:logger:transcriptStore:)` stays for gradual migration / tests.
- ✅ `AppComposition` constructs `DefaultModelService` + `ModelBoundTranscriberProvider` and injects them into `SessionCoordinator`.
- ✅ v3 placeholder `revision = "main"` in `BuiltInModelCatalog` is unchanged. `defaultActiveDescriptor` stays on v2.

## Correctness

- ✅ `recordingSessionTranscriber` (line 22) snapshots the chosen transcriber at recording-start and pins it through stop/transcribe, so a mid-session descriptor change doesn't silently swap engines. Cleared to `nil` on idle-transition (line 201). This is the correctness guarantee the plan calls for.
- ✅ `observeDownloadProgress` cancels the previous observation task before starting a new one, so progress streams don't multiply.
- ✅ `SessionDownloadProgressBroadcaster` (line 399) is a separate internal class; broadcaster state doesn't leak across recordings.

## Swift 6 concurrency

- `SessionCoordinator.activeVoiceModel()` hops to `MainActor.run { modelService.activeDescriptor.voiceModel }` (line 368). `DefaultModelService` is `@MainActor`; this is the right bridge from the session actor.
- `downloadProgressObservationTask` captures a non-isolated `broadcaster` reference (value-typed handle to a class). Read: safe.
- No new `@unchecked Sendable` abuse observed.

## Stage 2 scope

- Only 4 source files + 2 new test files + 1 test-support shim changed. Proportional to the Stage 2 migration spec.
- No Layer 6 Stage 1 files modified.
- `e299b2e` narrowly updates `MenuBarSceneModelTests.testStartObservingTracksPreparationProgressLifecycle` so the test drives `coordinator.prepareTranscriber()` before emitting progress — required because Stage 2 changed progress routing from direct-transcriber passthrough to a coordinator-owned rebroadcast. Justifiable test change, not test-drift.

## Cross-layer concerns

- `SessionCoordinator` public API grew: new init, new `modelDownloadProgress()` signature. Existing callers that only use the fixed-transcriber init are backward-compatible.
- No stepping on Layer 2 (storage), Layer 1 (permissions), Layer 4 (AppStore) territory.
- Downstream Layer 7 (pipeline orchestrator) still uses `FluidAudioTranscriber` in tests via `TranscriptionTestSupport` — unaffected because the test support helper exposes a minimal stub.

## Findings

### MINOR #1 — `preconditionFailure` on misconfigured internal paths

`Sources/SeshatSession/SessionCoordinator.swift:365` and `:377` crash the process with `preconditionFailure` when `modelService` or `transcriberProvider` is nil on the model-service path. These are internal invariants (the init enforces both are non-nil when the model-service constructor is used), but a crash is harsh for a case that represents a programmer error caught at init time.

Suggested: throw `SeshatError.invalidState` or a new typed error, bubbling up through `startRecording()` / `stopRecordingAndTranscribe()`. This lets test harnesses and telemetry capture the failure without taking down the app.

Not a blocker — the current invariant is correct; this is defensive hardening.

### MINOR #2 — 4 overlapping transcriber-resolution methods

`resolvedTranscriberForPreparation()`, `resolveRecordingSessionTranscriber()`, `transcriberForStopPath()`, and `resolvedActiveTranscriber()` (lines 320-361) all encode the same "use fixed if present, else resolve via modelService+provider" pattern with slightly different cache / observe behavior.

Suggested refactor: collapse to 2 methods — `primaryTranscriber(useCache: Bool)` plus an explicit `observeDownloadProgress` step at call sites. Reduces the surface for future bugs where cache invalidation drifts between the 4 sites.

Not a blocker — the current code works; this is clarity / future-proofing.

### NIT — `SessionCoordinatorModelSelectionTests` naming

The new test file at `Tests/SeshatSessionTests/Models/Selection/SessionCoordinatorModelSelectionTests.swift` covers per-recording transcriber pinning and active-descriptor change propagation. Name is fine but sits in `Tests/SeshatSessionTests/Models/Selection/` alongside model-selection-specific tests — fine for discoverability; some might argue this belongs under `Tests/SeshatSessionTests/` directly. Stylistic; ignore.

## Test coverage

- ✅ New recording pinned to starting descriptor (`SessionCoordinatorModelSelectionTests`).
- ✅ Next recording picks up a new active descriptor.
- ✅ Non-v2 descriptors route to the correct runtime variant (`FluidAudioTranscriberRuntimeVariantTests`).
- Missing but NOT blocking: no test for "what happens when the resolver sees an unknown descriptor". Layer 6 Stage 1 already covered `descriptorNotRegistered` for `ModelBoundTranscriberProvider.download(_:)`; Stage 2 consumers rely on that. Not a new gap from Stage 2.

## Summary

Layer 6 Stage 2 migrates `SessionCoordinator` + `AppComposition` + `FluidAudioInferenceClient` to the descriptor-driven world cleanly, preserves the backward-compatible `init(capture:transcriber:)` for legacy callers, and pins per-recording transcriber selection correctly. Only nits on a harsh crash path and overlapping internal helpers; both can be filed as follow-ups rather than blockers.

Verdict: APPROVED-WITH-NITS. Stage 2 is production-ready.

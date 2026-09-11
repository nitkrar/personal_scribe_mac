VERDICT: NEEDS_REVISION

## Summary Assessment

The plan is mostly faithful to DESIGN v2 and L1–L27, with phases sequenced sensibly and TDD discipline present. However, four issues block approval: (1) Phase F orchestrator-vs-migration ordering is wrong — migration runs at startup but the orchestrator rewrite (Phase G) lands *after* it, leaving an interim build period where new migration code writes recipes a still-old orchestrator never reads; (2) #078.16 is a 30-min mega-step disguised as one entry; (3) Open Question #2 (Processor associated-type vs sum type) is a load-bearing shape decision the plan punts to "default" instead of locking; (4) the audio-slice helper is naive about `PCMBuffer` shape — no test pins channel count / sample-rate provenance, which directly underwrites the L26 contract.

## L-lock compliance audit

- **L1** ✓ — #078.10 deletes `voiceModelID/aiModelID/systemPrompt`; recipes refer by Kind only.
- **L2** ✓ — #078.6 explicitly removes stored `kind`, adds computed `TranscriptionEngine.kind`, and pins both encode-omits and decode-ignores tests.
- **L3** ✓ — #078.1 extracts `ModelLifecycle`.
- **L4** ✓ — Phase D produces 4 distinct adapter classes; #078.17 explicitly inlines `FluidAudioRuntimeVariant` as parakeet-internal and deletes the cross-family file.
- **L6** ✓ — `[ModelKind: descriptorID]` preserved (no rework of `ActiveModelService`).
- **L7** ✓ — Engine→adapter dispatch lives in `ModelBoundProcessorProvider` (#078.15).
- **L8** ✓ — Adapters stay FluidAudio-specific.
- **L9** ✓ — Three protocols, never unified (Phase A keeps them distinct).
- **L10** ✓ — `SpeakerDiarizer` with `.update(provisional, finalized) / .terminal` event shape (#078.5); offline adapter is degenerate-streaming (#078.20).
- **L11** ✓ — `TranscriberCapabilities` (4 fields) + optional metadata on `TranscriptionResult` (#078.2 + #078.3).
- **L12** ✓ — Diarize-then-transcribe-per-turn fusion (#078.23).
- **L13** ✓ — `Transcriber: ModelLifecycle`, `StreamingTranscriber: ModelLifecycle`, `SpeakerDiarizer: ModelLifecycle`.
- **L14** ✓ — Recipes drive composition; #078.28 removes mode-specific branches.
- **L15** ⚠ — `WorkflowModeValidator` (#078.12) is pure-function central, but the design says rules fire at "save / build / session start" — only #078.25 (load) and #078.27 (build) are wired. Session-start re-validation isn't in any step.
- **L17** ⚠ — Hybrid γ availability rule never appears in #078.32 — the bridge writes piece-inclusion, but the `availability` half (e.g. voice-ID enrolled + ready) isn't represented anywhere. Out of #078 scope (no voice-ID lands), but the plan should say so explicitly.
- **L18** ✓ — VAD is recipe piece-inclusion (#078.26).
- **L19** ✓ — `Parameter<T>` cascade (#078.8); `ParameterResolver` is the single resolution point.
- **L20** ✓ — Three role-specific spec types; no umbrella `Piece` (#078.9).
- **L21** ✓ — `WorkflowModeRegistry` distinct from `ActiveModelService` (#078.24).
- **L22** ✓ — `Parameter<Value>` enum, Codable `{source,key}|{source,value}`, eager (#078.8).
- **L23** ✓ — `ProcessorSpec` cases reference Kinds; #078.9 even pins a test for "no `descriptorID` field."
- **L24** ✓ — `switch descriptor.engine` only in `ModelBoundProcessorProvider` (#078.15).
- **L25** ✓ — #078.27 has `testMidBuildSetActiveOnServiceDoesNotAffectAlreadyBoundRecipe`; #078.28 has `testMidSessionActiveModelChangeDoesNotAffectRunningSession`.
- **L26** ✓ — Phase E test list covers gaps, overlap-end-to-end, provisional-ignored, per-turn-isolation. Strong.
- **L27** ✓ — #078.26 migration + #078.32 bridge; legacy keys preserved.

## Critical issues (must fix before implementation starts)

1. **Phase F runs migration *before* Phase G installs the orchestrator that consumes recipes — the migration writes a `workflow-modes.json` document that the still-old orchestrator never reads.** Step #078.25 creates `workflow-modes.json` and #078.26 mutates it. But `SessionPipelineOrchestrator` only becomes recipe-driven at #078.28, and `ServiceBackedActiveModeProvider` is only deleted at #078.29. Between F-close and G-close, recipes exist on disk but no runtime consumes them — and worse, `swift build` is broken outside the core target across Phases B–F per the #078.10 "Note." Fix: move #078.25's *first-launch document creation* into a no-op-if-orchestrator-not-ready guard, or sequence Phase G before Phase F (build the orchestrator skeleton against an empty `WorkflowModeRegistry`, *then* migrate). At minimum, document explicitly that "between F-close and G-close, no session can run" and gate the build accordingly. The current plan implies F-close has a passing test filter — but `swift build` is broken across the whole tree, so even targeted test runs will fail to compile dependents.

2. **#078.16 is a 30-minute mega-step.** "Update all callsites of `ModelBoundTranscriberProviding`" touches `AppComposition.swift`, `SessionPipelineOrchestrator.swift`, `SessionCoordinator.swift`, plus *every test fake under `Tests/PersonalScribeSessionTests/`*. The grep earlier shows `ModelBoundTranscriberProvider` referenced in inference clients, the orchestrator, and at least one composition root. This is plausibly 8–15 files. Fix: split into #078.16a (production callsites) and #078.16b (test fakes), or list the exact files in advance with a per-file checkbox.

3. **Open question #2 (Processor associated-type vs sum-type erasure) is not a punt — it determines #078.21 + #078.28 shape.** The plan says "Default unless told otherwise: sum type." But #078.21 is currently written with `associatedtype Output`, contradicting the default. Either (a) lock the sum type in DESIGN v2 amendment + rewrite #078.21 to `enum ProcessorOutput { ... }`, or (b) keep associated-type and lock the orchestrator-side dispatch shape at #078.28. Leaving this as "default" means the Phase E processor commits to one shape and Phase G discovers the mismatch. Fix: decide before #078.21 lands. This is exactly the L9 trap (don't unify protocols) reframed at the output layer.

4. **`PCMBufferSlicing` (#078.22) tests don't pin channel-count / sample-rate semantics, which is the load-bearing contract for L26 overlap-end-to-end correctness.** Test names listed: `testSliceReturnsSampleAccurateRange`, `testSliceClampsToBufferBounds`, `testSliceOfZeroDurationReturnsEmptyBuffer`. Missing: behavior with stereo input (existing `PCMBuffer` check needed), behavior when start/end durations don't land on sample boundaries (round which way?), behavior when input buffer's sampleRate ≠ FluidAudio's expected 16kHz. If overlap zones are sliced wrong by one buffer-frame, the second turn's transcribe gets garbage — exactly the silent-loss failure mode L26 tries to prevent. Fix: add `testSliceWithStereoBufferPreservesChannels` (or document mono-only invariant), `testSliceWithFractionalSampleStartUsesNearestSampleBoundary`, and pin sample-rate provenance.

## Suggestions (nice to have, not blockers)

1. **Phase D close runtime gate is too weak** — "regression check Parakeet still works." That tests #078.17 only. #078.18/19/20 ship adapters with **no runtime verification** until #078.33/34. If the Qwen/streaming/diarization adapters compile but crash at runtime due to FluidAudio API misunderstanding, you discover it 14 steps later. Suggest: add a unit-level smoke test per adapter using a stub FluidAudio manager (the manager classes are concrete — fake-able only via DI). Or accept the late-binding and label it explicitly.

2. **#078.31's commit-tag claim "compiler-driven — but tested" is contradictory.** A compiler-driven rename has no behavioral test target. The claimed `testAIModelsTabSectionsByEngineDerivedKind` would pass before the rename too (since `descriptor.kind` and `descriptor.engine.kind` return the same value when both fields exist). The test only has bite if it runs after `descriptor.kind` is deleted in #078.6. Verify dependency ordering: #078.31 lists `Depends on: #078.30, #078.6` — good. But the test name should signal post-deletion behavior. Suggest renaming to `testSectionsRouteByEngineComputedKindAfterStoredKindRemoval` or similar.

3. **`AppStoreActiveModeProviding` resolution unclear** (#078.29 says "either deleted or re-pointed"). This is a small but real interface decision. Punt-by-disjunction. Lock to one before Phase G starts.

4. **Phase G close's `swift build --build-tests green across all targets` is the *only* time the plan asserts whole-tree build greenness.** Phases A–F cumulatively break the build outside core/session — that's ~5 phases of broken trunk if landed serially. This is acceptable for a feature-branch workflow; main session should confirm whether trunk-only is still policy here per `git_workflow.md`.

5. **#078.34 mentions a "smoke-test script" for streaming pipeline** but doesn't name where it lives. New target? Examples/ folder? Specify or move to an explicit subtask.

## Verified claims

- `ModelDescriptor.kind` is the stored field at `Sources/PersonalScribeCore/Models/Selection/ModelDescriptor.swift:109`, and the catalog passes it explicitly — #078.6's deletion target is correct.
- `AIModelsTab.swift:36` uses `descriptor.kind` (stored) — matches #078.31's claim.
- `SessionPipelineOrchestrator.swift:627` snapshots `vadPreferences?.current()` — L25's named precedent is real; #078.28's claim matches.
- `OfflineDiarizerManager` does not conform to `Diarizer` (cross-checked via review-2) — #078.20's "wraps directly, NOT via the protocol" stance matches.
- `ModelBoundTranscriberProvider.swift:5` declares the rename target; `ModelAwareFluidAudioTranscriber` exists at `Sources/PersonalScribeTranscription/Models/Selection/ModelAwareFluidAudioTranscriber.swift:6` — #078.15/#078.17 rename targets verified.
- `FluidAudioRuntimeVariant` cross-family file exists at `Sources/PersonalScribeTranscription/Models/Selection/FluidAudioRuntimeVariant.swift:5` and is referenced by both `FluidAudioInferenceClient.swift` and `ModelAwareFluidAudioInferenceClient.swift` — #078.17's deletion list is incomplete (it lists `ModelAwareFluidAudioInferenceClient.swift` but not `FluidAudioInferenceClient.swift`, which also imports the runtime-variant enum). Spot-check: confirm whether `FluidAudioInferenceClient` is also deleted or just edited to drop the parameter.
- `WorkflowMode.swift` legacy shape (`voiceModelID/aiModelID/systemPrompt`) matches what #078.10 claims to delete.
- `PreferenceMigrator.currentMigrationVersion = 1` — #078.26's bump to `2` is correct.
- Test dir `Tests/PersonalScribeCoreTests/WorkflowModeTests.swift` exists; #078.10 says "rewrite" — accurate.
- `enabledModels(kind:)` filter in `AIModelsTab` already iterates `ModelKind.allCases.filter(\.isEnabled)` — flipping `streamingASR` and `diarization` to `true` (#078.30) automatically surfaces those sections, consistent with the plan's claim.

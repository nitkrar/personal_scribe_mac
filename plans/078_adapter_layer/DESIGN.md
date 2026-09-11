# #078 — Adapter layer for non-Parakeet model families: DESIGN (v2)

Locked design for ticket #078. This document is authoritative for implementation; subsequent implementation plans execute against it.

**v2** addresses 4 critical issues from `078-design-review-1.md` (NEEDS_REVISION). Specifically: corrected the diarizer adapter scope (offline-only for #078), explicit descriptor-binding timing, recipe-builder VAD migration path, and audio-slicing contract for the diarize-then-transcribe-per-turn fusion.

## Status

- Brief: `BRIEF.md`
- Decisions log: `CHECKLIST.md` (vocabulary, L1–L26 locks, evidence trail)
- Plan options: `plan-option-codex.md`, `plan-option-claude.md`
- Round-1 review: `078-design-review-1.md` (NEEDS_REVISION; addressed in this v2)
- Synthesis: this file
- Implementation plan: TBD (separate ticket)

## Authoritative architecture reference

**`plan-option-codex.md`** is the locked architectural sketch. All file/type names, module locations, signatures, and composition rules from that document apply unless this synthesis overrides them.

The 20 L-locks from `CHECKLIST.md` remain in force. This synthesis adds new locks (L21–L24) that emerged from comparing plan options.

## Synthesis decisions

Both plan options were L-lock compliant. Codex committed where Claude hedged; Codex won 6/6 on material disagreements.

| # | Decision | Resolution |
|---|---|---|
| 1 | `TranscriberCapabilities` field count | **4 fields** (Codex). `providesSpeakerTurns` is wrong here — speaker turns are `SpeakerDiarizer` output, not `Transcriber` capability. Fields: `providesTokenTimings`, `providesConfidence`, `providesPerformanceMetrics`, `providesCustomVocabulary`. |
| 2 | Diarizer adapter count | **One adapter for #078: `FluidAudioOfflineDiarizerAdapter`** (wraps `OfflineDiarizerManager` directly, NOT via FluidAudio's `Diarizer` protocol — the offline manager doesn't conform). Adapter is a degenerate streaming case: emits one terminal update with all turns at end. LSEEND/Sortformer adapter (the real `Diarizer`-protocol-conforming kind) lands in a separate streaming-diarization ticket (#058 or sooner). Test offline diarization quality before considering an LSEEND swap. |
| 3 | `Parameter<T>` resolution timing | **Eager at piece-construction.** Resolved value baked at pipeline-build time. Predictable. Lazy invites mid-session surprises. |
| 4 | Recipe → model reference | **By Kind.** Recipes reference `ProcessorSpec.transcriber(kind: .asr)`; runtime resolves via `ActiveModelService.activeDescriptor(for: kind)`. Recipes survive model swaps. |
| 5 | Recipe storage | **Single document.** `workflow-modes.json` with `schemaVersion + activeModeID + customModes[]`. Atomic migration. |
| 6 | Provider naming | **`ModelBoundProcessorProvider`.** Preserves existing semantic; "Engine" is misleading (engine is an enum). Open to revisiting during implementation if a better name emerges. |

## New locks from synthesis

- **L21** — **`WorkflowModeRegistry` is a distinct service** from `ActiveModelService`. WorkflowModeRegistry owns active-mode state + custom modes + validation + migration. ActiveModelService owns active-per-kind descriptor. Resolves the CHECKLIST deferred item "Active mode vs Active model service split."
- **L22** — **`Parameter<Value>` is `enum { case setting(SettingKey<Value>), case override(Value) }`**. Codable as `{source, key}` or `{source, value}`. `ParameterResolver` is the single resolution point; eager at piece-construction.
- **L23** — **Recipes reference Kinds, not descriptor IDs.** `ProcessorSpec` cases name a Kind; runtime late-binds to the active descriptor for that Kind via `ActiveModelService`.
- **L24** — **`ModelBoundProcessorProvider` is the only type that switches on `descriptor.engine`.** Engine→adapter dispatch happens nowhere else.
- **L25** — **Descriptor binding is eager-at-pipeline-build.** `ActiveModelService.activeDescriptor(for: kind)` resolves once when `RecipeBuilder` constructs a pipeline at session start; the bound descriptor cannot change for the duration of the session. Mid-session `ActiveModelService.setActive` does NOT affect the in-flight session — takes effect on the next session. Mirrors the existing `VadPreferences` snapshot-once pattern (`SessionPipelineOrchestrator.swift:627`). UX consequence: Modes UI must not claim "active immediately" for mid-session swaps.
- **L26** — **`DiarizedTurnTranscriptionProcessor` audio-slicing contract**:
  - **Inter-turn gaps** (audio between turns where diarizer reports no speaker) → drop, no ASR call. Diarizer is the authority on "who was speaking."
  - **Overlap regions** (two turns share a time range) → ASR each turn end-to-end including the overlap zone. Two labeled transcripts emitted; overlap zone may produce partial/garbled text. Garbled-but-captured > silent loss. Optional `[multiple speakers]` marker on overlap regions is a cosmetic refinement, not a contract requirement.
  - **Provisional → finalized**: only finalized turns trigger ASR. Streaming-with-diarization is **segment-at-a-time** output, not realtime typing — text appears once a turn finalizes. UI may surface a non-text "speaker_X talking…" indicator during the wait. Realtime typing-as-you-speak with speaker labels is out of scope for #078 (would require a Ninimma-owned editor surface, not paste-to-other-app).
- **L27** — **VAD migration uses Settings-toggle-becomes-recipe-builder pattern (synthesis decision #3a).** Settings UI's "Auto-stop after silence" toggle reads/writes the active recipe's `CaptureController` list via `WorkflowModeRegistry`. Visually unchanged for the user. Underneath: legacy `VadAutoStopEnabled` preference is migrated once at first launch (preserves user's prior choice into recipe shape), the toggle then mutates recipes directly. When Modes editor ships (post-#078), the toggle becomes redundant and can be removed.

## What was explicitly rejected from Claude's plan

(Listed so subsequent sessions don't re-introduce these.)

- ❌ `providesSpeakerTurns` capability on `Transcriber` — category error.
- ❌ Two diarizer adapters (`OfflineDiarizerAdapter` + `LSEENDDiarizerAdapter`) — LSEEND batch-mode subsumes the offline manager.
- ❌ Lazy parameter resolution — eager wins.
- ❌ Multi-file `recipes/` directory storage — single document wins.
- ❌ `EngineProvider` name — misleading.
- ❌ Implicit recipe → descriptor coupling — explicit Kind reference required.

## Implementation sequence (rough; detailed in separate ticket)

1. **Pre-req**: parallel session's rename batch lands.
2. **Core protocols + types** in `PersonalScribeCore/Transcription/`: `ModelLifecycle`, `Transcriber`, `StreamingTranscriber`, `SpeakerDiarizer`, `TranscriberCapabilities`, `TranscriptionResult` field extensions.
3. **Mode types** in `PersonalScribeCore/WorkflowMode/`: `WorkflowMode`, `Recipe`, `ProcessorSpec` / `CaptureControllerSpec` / `OutputSinkSpec`, `Parameter<T>`, `WorkflowModeDocument`, `WorkflowModeValidator`.
4. **Provider** in `PersonalScribeSession/Models/Selection/`: rename `ModelBoundTranscriberProvider → ModelBoundProcessorProvider`, add typed accessors (`transcriber(for:)`, `streamingTranscriber(for:)`, `diarizer(for:)`), shared per-descriptor cache + lifecycle plumbing.
5. **Adapters** in `PersonalScribeTranscription/Adapters/`: four classes — `FluidAudioParakeetTranscriberAdapter`, `FluidAudioQwenTranscriberAdapter`, `FluidAudioStreamingTranscriberAdapter`, `FluidAudioOfflineDiarizerAdapter` (wraps `OfflineDiarizerManager` directly; degenerate-streaming-case implementation of `SpeakerDiarizer`). LSEEND adapter deferred to a separate ticket.
6. **Fusion processor** `DiarizedTurnTranscriptionProcessor` in `PersonalScribeSession/Pipeline/Processors/`. Diarize-then-transcribe-per-turn for batch and streaming.
7. **Registry** `WorkflowModeRegistry` in `PersonalScribeSession/WorkflowMode/`: load/save, validation, migration runner.
8. **Migration** in `PreferenceMigrator`: `VadAutoStopEnabled` migrates per L27 (one-shot read at first launch into recipe; Settings toggle then mutates recipes directly). `AutoPasteEnabled`, `ClipboardRestoreEnabled` migrate to recipe shape similarly (toggle wires to recipe via `WorkflowModeRegistry`). `MuteOutputWhileRecording`, `BackgroundLaunchPreference` remain global settings (orthogonal to recipe pieces).
9. **Orchestrator** — `SessionPipelineOrchestrator` becomes recipe-driven (no mode-specific branching).
10. **UI** — AI Models tab unfilters streamingASR + diarization rows (`ModelKind.isEnabled` flips). Modes tab editor for custom recipes is a separate UX ticket.

Each step opens with red tests (`swift test --filter`), test-first per Ninimma testing discipline.

## Out of scope / followups

- **LSEEND streaming diarization adapter** — separate ticket. `FluidAudioLSEENDDiarizerAdapter` (true `Diarizer`-protocol-conforming kind) lands when streaming diarization product use case requires it (#058 or sooner). Test offline diarization quality first; if pyannote+WeSpeaker is sufficient, defer LSEEND indefinitely.
- **Backend-agnostic abstraction** — deferred until a second SDK appears (per L8).
- **`Parameter<T>` schema versioning / migration** — deferred per CHECKLIST Hole 3 (pre-second-user, accept silent drift risk).
- **Modes UI editor for custom recipes** — separate UX ticket; architecture supports it, editor view + flow are out of #078 scope. Manus design brief in flight.
- **Realtime typing of diarized output** — out of scope per L26 (provisional revisions can't be retracted in paste-to-other-app outputs). Requires a Ninimma-owned editor surface to enable.

## Evidence backing the design

- `plans/investigations/2026-04-25-078-fluidaudio-fusion-codex.md` — no fused diarization+ASR ships; ASR exposes token-not-word timings (drives L12).
- `plans/investigations/2026-04-25-078-asr-output-shapes-codex.md` — three ASR managers, three different output shapes; common subset only "transcript text" (drives L9, L11).
- `plans/investigations/2026-04-25-078-streaming-diarization-codex.md` — LSEEND/Sortformer ship streaming diarization with update-oriented `Diarizer` protocol (drives L10, synthesis decision #2).

---

Implementation plan to be drafted in a separate session against this design.

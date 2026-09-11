# #078 — Adapter layer for non-Parakeet model families: BRIEF for plan options

You are proposing a complete implementation plan for ticket #078. One agent = one plan option. Two agents (Codex + Claude general-purpose) work from this same brief; their two plans get synthesized in the main session.

## Problem statement (user's framing, verbatim)

> We want to support Qwen downloader for ASR, then support EoU and diarization features from FluidAudio.

## Goal beyond the literal feature

A single coherent backbone for ASR + streaming ASR + diarization. Avoid:

- Scattered logic (mode-specific branches duplicated across the codebase)
- Multiple ways to represent the same concept (engine vs kind, etc.)
- Polymorphic abstractions that paper over genuinely different shapes

Optimize for:

- Deep, simple modules (lots of behavior behind small interfaces)
- Composability (modes are recipes; pieces are reusable role-specific protocols)
- Fail-loud over fail-silent (capability declarations, validity rules, parameter cascade)

## Note on in-flight renames

A parallel session is currently running mechanical renames in worktrees: `Transcribing → Transcriber`, `AudioCapturing → AudioCapturer`, `ModeDescriptor → WorkflowMode`, `OutputMode → PipelineShape`, `PillVisibilityMode → PillVisibility`, `BackgroundModePreference → BackgroundLaunchPreference`, `PipelineStageID → PipelineStepID`, `SessionState.recording → .capturing`, possibly `Note → Transcript`. **The brief uses target names verbatim.** Existing code may still show old names when you grep — that's expected. Reference target names in your plan; do not propose plans against the old names.

## Required reading (in order)

1. **`plans/078_adapter_layer/CHECKLIST.md`** — vocabulary table + L-locks + open questions + deferred items. **Every L-lock is non-negotiable**; if you believe a lock should change, call it out at the top of your plan with the lock number and the trade-off you're proposing. Vocabulary terms are verbatim — no synonyms.
2. The three codex investigation reports (evidence backing the locks):
   - `plans/investigations/2026-04-25-078-fluidaudio-fusion-codex.md` — no fused diarization+ASR pattern ships; ASR exposes token timings only.
   - `plans/investigations/2026-04-25-078-asr-output-shapes-codex.md` — three managers, three different output shapes.
   - `plans/investigations/2026-04-25-078-streaming-diarization-codex.md` — streaming diarization already ships (LSEEND, Sortformer); update-oriented `Diarizer` protocol.
3. Existing relevant code (browse, don't quote at length):
   - `Sources/PersonalScribeCore/Models/Selection/` — descriptors, engine, kind, catalog
   - `Sources/PersonalScribeCore/Protocols.swift` — current `Transcribing` protocol
   - `Sources/PersonalScribeTranscription/` — current adapter (Parakeet only)
   - `Sources/PersonalScribeSession/Pipeline/Orchestrator/SessionPipelineOrchestrator.swift` — pipeline driver
   - `Sources/PersonalScribeSession/Models/Selection/ModelBoundTranscriberProvider.swift` — current provider

## What you're proposing — answer all 8 open questions concretely

Q1, Q3, Q5, Q6, Q7 are **interdependent** — propose them as a coherent system, cross-referencing where relevant. Don't answer as if they're independent.

For each Q: give concrete file/type names, signatures, structures. Not "we should consider X" hedging. If you cannot answer concretely, write *"no concrete answer — needs main-session decision"* and explain why in ≤2 sentences.

### Q1. Concrete protocol method signatures
Three protocols: `Transcriber`, `StreamingTranscriber`, `SpeakerDiarizer`. Plus shared `ModelLifecycle`. For each, propose method signatures (async/throws shape, return type vs stream-of-events), error propagation, and module location.

### Q2. Where fusion logic lives (diarize-then-transcribe-per-turn)
Pick one: **(a)** recipe-specific class; **(b)** shared composable piece referenced by recipes; **(c)** orchestrator with mode-driven branching. L14 leans (b). State your pick + concrete file structure. (Names like `DiarizingTranscriberCoordinator` are illustrative — propose your own.)

### Q3. Provider API surface
Type-narrowing accessors: `transcriber(for:)`, `streamingTranscriber(for:)`, `diarizer(for:)`. Propose exact signatures + the **shared cache + lifecycle plumbing underneath** (type-narrowing must not produce divergent code paths). Include: how the provider routes a descriptor to the right adapter (engine→adapter dispatch).

### Q4. Recipe serialization format
Built-in modes hardcoded; user-defined modes serialize where (JSON file in `AppConfig.baseDirectory()`? UserDefaults? SQLite?), schema versioning, validation-on-load behavior.

### Q5. `TranscriberCapabilities` field set
Concrete struct definition. At minimum: `providesTokenTimings`, `providesConfidence`, `providesPerformanceMetrics`, `providesCustomVocabulary`. Add fields only if justified by an existing or imminent feature. Specify how each adapter declares its capabilities (static const? init param? computed?).

### Q6. `Parameter<T>` exact shape
Codable shape, resolution timing (eager at piece-construction vs lazy on access), SwiftUI binding integration, how the Modes UI distinguishes "from global" vs "overridden for this mode" at render time.

### Q7. Validity-rule enforcement
Where rules live (per-piece declared? central registry? type-system?), when checked (recipe save / pipeline build / session start / all), failure UX.

### Q8. Migration plan for legacy global toggles
Concrete migration for `VadAutoStopEnabled = false` users → their default mode loses `VadController`. Identify other global feature toggles in the same boat (`PasteEnabledPreference`, etc.). Migration runs at app launch? On first mode-system access?

## Output format

Write your plan to:
- Codex: `plans/078_adapter_layer/plan-option-codex.md`
- Claude general-purpose: `plans/078_adapter_layer/plan-option-claude.md`

**Use these exact section headers:**

```
# #078 plan option — <author>

## Lock acknowledgements
List every L-lock. For each: ✓ respected, or ⚠ proposing change with trade-off.

## Architecture sketch (≤300 words)
The shape — what types live where, how data flows, key seams.

## File / type list (≤300 words)
Tabular: filename | role | ≤1-line summary. New + modified files only.

## Migration impact (≤200 words)
Existing code that changes shape. Existing user state needing migration.

## Test seam shape (≤200 words)
What gets tested, how. Which test doubles exist; which are added.

## Open questions remaining (≤200 words)
Anything you cannot answer concretely. Mark "needs main-session decision" rather than hedging.
```

**Hard cap: 1200 words total.** Do not pad. If a section can be done in 50 words, do it in 50 words. Trim before submitting.

## Anti-patterns — do NOT do these

- **Don't unify the three output protocols** under one polymorphic protocol. L9 + agent 2 evidence rules this out.
- **Don't pre-generalize past FluidAudio.** L8. Adapters can be FluidAudio-specific; future SDK is a separate refactor.
- **Don't bundle lifecycle with output shape.** L13. `ModelLifecycle` is its own protocol.
- **Don't invent synonyms** for vocabulary terms in the CHECKLIST table. Use locked terms verbatim.
- **Don't propose word-timing-based ASR-then-align fusion.** L12 + agent 1 evidence: ASR's public API exposes token timings, not word timings.
- **Don't pad to fill perceived expectations.** A 600-word complete plan beats a 1200-word waffly plan.
- **Don't violate any L-lock** without explicitly calling it out in "Lock acknowledgements" with the trade-off.
- **Don't include full code listings.** Type signatures + struct field lists are fine. Method bodies, full implementations are out of scope.
- **Don't restate the brief.** Reference by section number (Q1, L9, etc.).
- **Don't speculate on user intent or future tickets.** Stay scoped to #078 + the locks.

## Verification — what makes a plan "approved"

A plan option is approved if:

1. Every L-lock is in the acknowledgements section, ✓ or ⚠ flagged.
2. Every open question Q1–Q8 has a concrete answer (no "we should consider").
3. File/type names use the locked vocabulary (Mode, Engine, Kind, Adapter, Processor, Capture controller, Output sink, Recipe — never bare "stage" or "module").
4. Migration impact is enumerated, not glossed.
5. Word count ≤1200.
6. Cross-referenced where Q1/Q3/Q5/Q6/Q7 interact (these are coupled).

A plan option fails if any of the above is missing. Main session will reject and request revision (one round, max).

## Synthesis after both plans land

Main session reads both, diffs against the L-locks, surfaces material disagreements as discussion items, picks per-question winners or a hybrid. The synthesis output becomes the final design that the implementation plan (separate ticket / step) will execute against.

---

End of brief. Begin your plan option.

VERDICT: APPROVED

## Summary Assessment

All four round-1 critical issues are concretely addressed in DESIGN v2 and CHECKLIST L25–L27. Synthesis decision #2 honestly reframes the diarizer scope as "wraps `OfflineDiarizerManager` directly, NOT via FluidAudio's `Diarizer` protocol"; L25 mirrors the existing `vadPreferences` snapshot-once pattern; L26 enumerates gap/overlap/provisional cases; L27 preserves user state via a one-shot migration plus Settings-toggle-as-recipe-builder. The revisions don't introduce new structural problems.

## Round 1 issue resolution status

**C1 — `OfflineDiarizerManager` doesn't conform to `Diarizer`** — addressed. Synthesis row 2 now reads "wraps `OfflineDiarizerManager` directly, NOT via FluidAudio's `Diarizer` protocol — the offline manager doesn't conform"; the rejected-claims list adds "Two diarizer adapters … LSEEND batch-mode subsumes the offline manager"; the implementation sequence step 5 names `FluidAudioOfflineDiarizerAdapter` (singular, "wraps `OfflineDiarizerManager` directly; degenerate-streaming-case implementation of `SpeakerDiarizer`"); LSEEND adapter is explicitly deferred under "Out of scope / followups." File list and scope are now consistent. Verified `OfflineDiarizerManager.swift:7` declares `public final class OfflineDiarizerManager {` with no protocol conformance — the design's premise matches reality.

**C2 — Descriptor binding timing** — addressed. New L25 (CHECKLIST.md and DESIGN synthesis section) states descriptor binding is eager-at-pipeline-build, mid-session `setActive` is a no-op for the in-flight session, and explicitly invokes the existing `VadPreferences` snapshot-once pattern as precedent. Verified line 627 in `SessionPipelineOrchestrator.swift` reads `let vadPrefs = vadPreferences?.current()` with comment "Snapshot preferences + provider + handler ONCE at session start … Mid-session preference flips do not rescue the current recording (documented UX)" — L25's claimed precedent is real. The UX consequence is also flagged (Modes UI must not claim "active immediately").

**C3 — VAD migration loses user state** — addressed. New L27 specifies (a) one-shot migration at first launch reads legacy `VadAutoStopEnabled`, `AutoPasteEnabled`, `ClipboardRestoreEnabled` into recipe shape, preserving each user's prior choice, and (b) the existing Settings toggle is rewired to mutate the active recipe via `WorkflowModeRegistry`, "visually unchanged for the user." This satisfies the round-1 fix of preserving the user-visible UX path. `MuteOutputWhileRecording` and `BackgroundLaunchPreference` are explicitly named as remaining global (orthogonal to recipe pieces), closing suggestion #4 from round 1.

**C4 — Audio-slicing contract** — addressed. New L26 enumerates all three classes I flagged: gaps drop (no ASR call), overlap regions ASR each turn end-to-end with optional cosmetic `[multiple speakers]` marker (garbled-but-captured > silent loss), provisional turns wait for finalize. Realtime typing is explicitly out of scope with rationale (paste-to-other-app can't retract revisions; would require Ninimma-owned editor surface).

## New issues (if any)

None blocking. Two minor observations the design implicitly resolves but doesn't restate, listed under Suggestions for future-reader clarity.

## Suggestions (nice to have, not blockers)

1. L25 + L19 interaction is consistent (both eager) but the design could explicitly state that `Parameter<T>` resolution and `ActiveModelService.activeDescriptor(for:)` lookup happen at the *same* moment — `RecipeBuilder` constructs the pipeline at session start, both bind. Currently L22 says "eager at piece-construction" and L25 says "eager-at-pipeline-build" — same moment in practice, but a sentence equating the two would prevent a future implementer from drifting them apart.

2. L27's coupling of Settings UI → `WorkflowModeRegistry` is a deliberate trade-off but the design doesn't address one corner case: if the user has multiple custom modes (post-Modes-editor), which one does the legacy Settings toggle mutate? The design says "the active recipe's `CaptureController` list," which is sensible, but is worth documenting now so the implementer doesn't have to re-decide. Round-1 hybrid γ (L17) intent is preserved — global settings still control *availability* (e.g., voice-ID); L27 only forwards Setting → active recipe for the migration-bridge toggles. No conflict.

3. Out-of-scope list could explicitly note: "User can edit Dictation recipe pieces only via Settings UI bridge (L27); `WorkflowModeRegistry` recipe-editor is the post-#078 follow-up." This avoids the implementer wondering "where does the user re-enable VAD on Dictation if they migrate with `false`?" — answer: flip the existing toggle, which now writes to recipe.

## Verified Claims

- `OfflineDiarizerManager.swift:7` is `public final class OfflineDiarizerManager {` with no protocol — confirms DESIGN v2 synthesis row 2 is technically correct.
- `SessionPipelineOrchestrator.swift:618-629` snapshots `vadPreferences?.current()` and `onAutoStopRequested` once at session start, matches L25's named precedent.
- `ActiveModelService.swift:155-161` `setActive` calls `onSetActive` hook (today wired to `prepareTranscriber`); L25's claim that mid-session swap currently has implicit effect on the next session via this hook is consistent with the new lock — L25 makes the contract explicit rather than implicit.
- File list (DESIGN implementation sequence) names exactly four adapters in step 5 (`FluidAudioParakeetTranscriberAdapter`, `FluidAudioQwenTranscriberAdapter`, `FluidAudioStreamingTranscriberAdapter`, `FluidAudioOfflineDiarizerAdapter`); matches the singular-diarizer scope from synthesis decision #2.
- "Out of scope / followups" lists `FluidAudioLSEENDDiarizerAdapter` as a separate ticket — closes the round-1 ambiguity between "one adapter that does everything" vs. "explicit single-scope adapter with deferred sibling."
- L26's three sub-cases (inter-turn gaps, overlap, provisional) match the three concerns from round-1 critical issue #4 verbatim, each with a directional decision.
- L27 explicitly migrates `VadAutoStopEnabled`, `AutoPasteEnabled`, `ClipboardRestoreEnabled` into recipe shape and keeps `MuteOutputWhileRecording`, `BackgroundLaunchPreference` global — covers all four legacy toggles I flagged in round 1 suggestion #4.

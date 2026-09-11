VERDICT: NEEDS_REVISION

## Summary Assessment

The architecture is largely sound — three output protocols + Diarizer-shaped streaming + recipe-by-Kind composition all hold up against the FluidAudio source. However, two material claims are wrong (OfflineDiarizerManager does NOT conform to `Diarizer`; eager param resolution + recipe-by-Kind interact in ways the design does not address), and the legacy migration plan loses real user state silently for the Vad-off cohort.

## Critical Issues (must fix before implementation)

1. **Synthesis decision #2 / L10 overstate the unification — `OfflineDiarizerManager` is NOT `Diarizer`.**
   - Evidence: `.build/checkouts/FluidAudio/Sources/FluidAudio/Diarizer/Offline/Core/OfflineDiarizerManager.swift:7` declares `public final class OfflineDiarizerManager {` (no protocol). Only `LSEENDDiarizer` (`.../LS-EEND/LSEENDDiarizer.swift:9`) and `SortformerDiarizer` conform to `Diarizer`. `DiarizerTimeline.swift:9-115` is the protocol.
   - Why it breaks: investigation report `2026-04-25-078-fluidaudio-fusion-codex.md` and #024.10 catalog rows still pin `OfflineDiarizerManager` (`TranscriptionEngine.diarization` says "Different manager class (`OfflineDiarizerManager`)" — `TranscriptionEngine.swift:13-16`). DESIGN says "LSEEND covers batch+streaming via update-oriented `Diarizer` protocol" — true for LSEEND/Sortformer. But the plan also lists `FluidAudioSpeakerDiarizerAdapter` as the *single* diarizer adapter for the descriptor whose engine is currently `.diarization` (= the pyannote/WeSpeaker offline manager). Either we rev the catalog descriptor + engine to point at LSEEND models, or we admit there are still two diarizer paths.
   - Fix: explicitly close the loop. Either (a) rename `TranscriptionEngine.diarization` → `.lseendDiarization` and replace the offline-manager descriptor in the catalog, or (b) keep two adapters — one for `OfflineDiarizerManager`, one for LSEEND-as-`Diarizer`. The current design wording implies one adapter suffices because LSEEND batch-mode "subsumes" the offline manager — that's a *future* deletion, not a present fact. Resolve before implementation, not "during."

2. **Eager parameter resolution (L22 / synthesis #3) collides with recipe-by-Kind (L23) for mid-session active-model swaps.**
   - Evidence: `ActiveModelService.setActive(_:)` (`ActiveModelService.swift:155-163`) fires `onSetActive` which today calls `SessionCoordinator.prepareTranscriber()`. Nothing in DESIGN forbids the user from changing the active descriptor for a Kind during a session. With eager resolution, the recipe binds `transcriber(kind: .asr)` → descriptor X at piece-construction; the user then activates descriptor Y mid-recording from the AI Models tab; the in-flight pipeline keeps using X.
   - Why it breaks: the eager-vs-lazy debate in the synthesis table treats this as a *parameter* resolution choice ("global setting changes mid-session") but the active *descriptor* is not a `Parameter<T>` — it's resolved through `ActiveModelService.activeDescriptor(for: kind)` at piece construction (codex sketch §3, "runtime resolution is `ActiveModelService.activeDescriptor(for: kind)` followed by `ModelBoundProcessorProvider`"). The DESIGN never states *when* this lookup happens. If it's eager (consistent with L22), mid-session swaps silently no-op; if lazy, the swap takes effect mid-stream and tears down the streaming session.
   - Fix: state explicitly that descriptor lookup is eager-at-pipeline-build, and that `ActiveModelService.setActive` does NOT affect an in-flight session (matches the existing `vadPreferences` snapshot-once pattern in `SessionPipelineOrchestrator.consumeCaptureStream`, line 627). Document the UX consequence in CHECKLIST. Or: lock that mid-session active-swap is forbidden in UI.

3. **`VadAutoStopEnabled = false` migration loses the user's setting silently.**
   - Evidence: codex plan migration §1 — "`VadAutoStopEnabled == false` removes `VadController` from Dictation." Today, `Settings → Auto-stop after silence` is a global toggle the user sees in one place. After migration, the user's Dictation recipe simply lacks `VadController`. There is no UI surface in #078 (Modes editor is "out of scope") that would let the user re-enable VAD for Dictation. The Settings toggle either disappears (codex plan: "the toggle either disappears or becomes a meta-default for new modes" — undecided) or stays orphaned.
   - Why it breaks: a fresh-install user post-update who had `VadAutoStopEnabled=false` and now wants to flip it back has no path. Per memory `feedback_bundle_pref_alignment.md`: "the 'default' is a lie and fresh installs land in an unreachable state."
   - Fix: until the Modes editor ships, keep the global Settings toggle as a *recipe builder* that mutates the active mode's processor list (read on app launch, write back via WorkflowModeRegistry). Or: defer the L18 migration entirely until #078's UI follow-up ticket lands. Pre-dogfood disposability does not apply — VAD-off is a deliberate user choice, not transient state.

4. **`DiarizedTurnTranscriptionProcessor` audio-slicing contract is undefined for the gap/overlap regions.**
   - Evidence: codex sketch §3 — "buffers source audio, and sends finalized turns to a batch `Transcriber`." `DiarizerTimelineUpdate.finalizedSegments` is per-speaker turns; FluidAudio's diarizer emits provisional segments that *revise* before finalization (investigation report part B). Two classes of gaps the design does not address:
     - Inter-turn audio that diarizer marks as silence — does it get fed to ASR or dropped?
     - Overlap regions (two speakers simultaneously) — `DiarizerTimeline` permits multi-speaker frames; per-turn dispatch implies serial single-speaker processing.
   - Why it breaks: silent-drop of overlap audio = lost transcript; serial dispatch with per-turn ASR re-init = thrashed decoder state, latency spike. Neither is acceptable behavior; both are silent today.
   - Fix: in DESIGN, write a one-paragraph contract for `DiarizedTurnTranscriptionProcessor`: how segment-to-PCMBuffer slicing handles (a) gaps, (b) overlap, (c) provisional-then-revised turns (does the processor emit a transcript revision when a finalized turn shifts boundary?). At minimum, list the cases as "deferred follow-up" so they don't get silently chosen during implementation.

## Suggestions (nice to have, not blockers)

1. **Validity-rule storage location is unspecified.** Codex sketch says "each spec declares `validityRules`" but never shows the type. Is it a closure (loses Codable), an enum (limits expressiveness), or a registry-based key (decouples but spreads logic)? Pick one before implementation.

2. **`activeModeID: String?` in WorkflowModeDocument creates a partial-failure ambiguity** — if the active ID references a custom mode that fails validation on load, what happens? Codex says "fall back to Dictation"; DESIGN should lock this and lock that the *invalid mode is preserved on disk* (don't silently drop a mode the user might fix on next app launch).

3. **`Parameter<Value>` Codable shape `{source, key}` vs `{source, value}`** — when `Value` is a generic and `key` is a `SettingKey<Value>` (per L22), the Codable synthesis needs explicit handling. `SettingKey` doesn't exist in the codebase yet (`grep` found only `Preference<Value>` at `PersonalScribeCore/Preferences/Preference.swift:4`). Implementation step #3 must list adding `SettingKey` to `PreferenceKeys`.

4. **DESIGN never names the rename status of `BackgroundLaunchPreference` and `MuteOutputWhileRecording`** as global-only post-migration. Codex plan does (migration §3); copy that into DESIGN's L18 consequence so future readers don't misread #078 as moving them into recipes.

## Verified Claims

- Three FluidAudio ASR managers have three different output shapes — confirmed via investigation report and `AsrTypes.swift:41-49` (Parakeet rich) vs. `Qwen3AsrManager.swift:122-129` (String) vs. `StreamingEouAsrManager.swift:381-413` (callback + finish String).
- `Diarizer` protocol unifies streaming + batch via `processComplete` + `addAudio`/`process` — confirmed at `DiarizerTimeline.swift:9-115`.
- `ActiveModelService` already supports per-Kind lookup — `activeDescriptor(for: kind)` at `ActiveModelService.swift:148-151`.
- Renames from BRIEF (`Transcribing→Transcriber`, `AudioCapturing→AudioCapturer`, `ModeDescriptor→WorkflowMode`) have already landed in source (`Protocols.swift:5,31`, `WorkflowMode.swift:3`).
- `VadPreferences` snapshot-once pattern exists at `SessionPipelineOrchestrator.swift:627` (basis for proposing the mid-session-immutability fix in critical issue #2).
- L1/L6 (canonical descriptor + per-kind active map) consistent with current `ActiveModelService` shape.

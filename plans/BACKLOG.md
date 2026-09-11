# Ninimma — Backlog

Active work items. Closed items live in [`BACKLOG_ARCHIVE.md`](./BACKLOG_ARCHIVE.md). Phase/roadmap context in [`ROADMAP.md`](./ROADMAP.md). Central-layers refactor plans stay at [`central/`](./central/).

## Schema

- `type:` bug / feature / refactor
- `priority:` P0 (critical / dogfood blocker) / P1 (schedule actively) / P2 (work in flow) / P3 (wishlist)
- `status:` open / in-progress / blocked / parked / done
- `stage:` design / impl / review / followup *(optional)*
- `phase:` 1 / 2 / 3 / 4 *(optional)*
- `area:` freeform tags

Each ticket has an `*Updated YYYY-MM-DD*` line under the tag row. Bump on meaningful change (status/stage/priority flip, material body edit, new changelog entry). Don't bump for typo fixes.

**IDs:** sequential from `#001`. Never reused. Legacy references kept per-ticket under `**Legacy:**`.

---

## In flight

| Ticket | Owner | Started | Last update | Notes |
|---|---|---|---|---|
| #026 | parallel Claude session | 2026-04-21 | 2026-04-21 | plan → `plans/storage-database-layer.md`; prompt at `/tmp/storage-layer-plan-prompt.md` |
| #001 | main session | 2026-04-21 | 2026-04-21 | source landed; awaiting runtime verify (MV-HK-8..11) on DMG build |

Rules: add a row when you dispatch / start work; bump `Last update` on heartbeat or commit; delete row when ticket lands or reverts to `open`. Any row with `Last update` > 3 days = "is this alive?" check.

---

## Legacy-ID cross-reference

Quick lookup when an old commit or doc cites a legacy ID.

### From `ui-dogfood-bugs-2026-04-21.md`
- #3 → #005 · #5 → #001 · #7 → #004 · #10 → #034 · #11 → #035 · #12 → #002 · #13 → #007 · #15 → #006 · #17 → #011 · #18 → #008 · #19 → #028

### From `ui-mockup-gaps.md` (open items)
- Transcriptions mode-pill (row) → #032
- Unified-shell + D-follow-up mic footer → #008 (sidebar) / #037 (title-bar accessory)
- Settings→General D-follow-up: PillStyle wiring → #029 · pasteEnabled wiring → #030

### From `PLAN_PHASES.md`
- Step 1.1b (signposts) → #012 · Step 1.4b (drag-tap test C) → #010
- Phase 3.B (Notes) → #013 · 3.C (Onboarding) → #015 · 3.D (SQLite) → #026 · 3.F (2nd model) → #016 · 3.G (hotkey customization) → #017 · 3.H (clipboard clobber) → #018 · 3.I (triple-⌥ quit) → #019
- Phase 4 (Intent) → #020 · (Command Mode cards) → #021 · (Ask Ninimma) → #022 · (Action Dispatcher) → #023

### From other backlog docs
- `backlog/phase-8-cancel-recording.md` → #002 · `backlog/issue-6-pill-panel-focus.md` → #003 · `backlog/transcript-trigger-context.md` → #027 · `backlog/model-download-ux-bug-research.md` Stage B → #009 + #024 + #025 + #036 + #038 · `backlog/streaming-output-delivery-mechanism.md` + `backlog/pipeline-streaming-defer.md` → #033 *(merged)*

### From `plans/central/`
- All layer Stage-2/3 validation work → #031

---

## Bugs

### #001 — Hold-to-record leaks `÷÷÷÷` then drops transcript

`bug` · `P0` · `in-progress` · `stage: review` · `area: hotkey, pill`
*Updated 2026-04-21*

Holding `opt + /` types `÷` into the frontmost app for the duration of the hold, then does not paste the transcription. Source landed across five commits; runtime verification (MV-HK-8..11) pending on a DMG build.

**Blocks:** #028
**Legacy:** `ui-dogfood-bugs-2026-04-21.md` #5

**Changelog**
- 2026-04-21 `fd9d47a` — HotkeyEvent adapter scaffold (no-op refactor)
- 2026-04-21 `ce6ba19` — standalone HotkeyEventTap + `CGEvent.tapCreate` swallows matching keyDown + auto-repeat + keyUp
- 2026-04-21 `4d5bf7f` + `4114614` — replaced symmetric `coordinator.toggle()` on hold with explicit `startIfIdle` / `stopIfRecording`
- 2026-04-21 `231df70` — pill `collectionBehavior` updated for full-screen-app visibility

---

### #002 — Esc during recording acts like Stop, not Cancel

`bug` · `P0` · `blocked` · `stage: design` · `area: session, pill`
*Updated 2026-04-21*

Esc transcribes + pastes + offers Undo instead of true-discarding. Blocked on decision: spec-literal (Esc and ✕ both discard) vs. split semantics (Esc soft, ✕ hard). Requires `SessionCoordinator.cancelRecording()` threaded through `SessionPipelining` + `SessionPipelineOrchestrator`.

**Legacy:** `ui-dogfood-bugs-2026-04-21.md` #12 + `backlog/phase-8-cancel-recording.md`

---

### #003 — Pill panel steals focus on click

`bug` · `P0` · `open` · `area: pill, output`
*Updated 2026-04-21*

Clicking the pill promotes Ninimma to frontmost, breaking the auto-paste target. Fix: `.nonactivatingPanel` + `canBecomeKey/Main` = false (per Wispr Flow reverse-engineering). Existing AX-probe workaround (#1 fix) stays as belt-and-suspenders.

**Legacy:** `backlog/issue-6-pill-panel-focus.md`

---

### #004 — Pill theme / window tint consolidation not reflected in build

`bug` · `P0` · `open` · `area: theming`
*Updated 2026-04-21*

Build still exposes pill appearance and window tint as independent settings (or the unified setting doesn't propagate). Needs commit-log audit before code changes to confirm what actually landed.

**Legacy:** `ui-dogfood-bugs-2026-04-21.md` #7

---

### #005 — Launch-at-Login toggle doesn't prompt for permission

`bug` · `P1` · `open` · `area: settings, permissions`
*Updated 2026-04-21*

Toggling ON silently flips state but never prompts or requests Login Items permission. Verify `SMAppService` / helper invocation is actually firing.

**Legacy:** `ui-dogfood-bugs-2026-04-21.md` #3

---

### #006 — Base-directory control is clunky; "Open in Finder" opens parent

`bug` · `P1` · `open` · `area: settings`
*Updated 2026-04-21*

Full "Base directory" label plus oversized buttons stack onto a second line. `NSWorkspace.open` URL resolves to `~/Library/Application Support/` (parent) instead of `.../personal_scribe/`.

**Legacy:** `ui-dogfood-bugs-2026-04-21.md` #15

---

### #007 — Model labels ("Parakeet TDT", "Parakeet CTC") are opaque

`bug` · `P2` · `open` · `area: settings, models`
*Updated 2026-04-21*

Size alone doesn't explain the difference. Add one-line description or info popover per row; tighten row density so multiple models fit without scrolling.

**Legacy:** `ui-dogfood-bugs-2026-04-21.md` #13

---

### #008 — Sidebar mic footer is inert

`bug` · `P1` · `open` · `stage: design` · `area: ui, sidebar, audio`
*Updated 2026-04-21*

Small "Microphone" label does nothing on click/hover. Decide intent: mic-picker popover / route to Settings → input device / status readout only / remove. Pick one and wire (or strip). Absorbs the mockup-gap "hard-codes `Text(\"Microphone\")`" finding.

**Legacy:** `ui-dogfood-bugs-2026-04-21.md` #18 + `ui-mockup-gaps.md` unified-window-shell

---

### #009 — FluidAudio model-download progress not surfaced (Stage B)

`bug` · `P0` · `open` · `phase: 3` · `area: models, session`
*Updated 2026-04-21*

Wire `DownloadUtils.ProgressHandler` end-to-end into `AsrModels.load(from:version:progressHandler:)` at both call sites. Map FluidAudio phases (`.listing` / `.downloading` / `.compiling`) to `ModelDownloadProgress`. Delete `PrivateModelDownloader` + the stub-permissive `modelArtifactsAreValid` validator. Gate `.recording` publication on "model ready" to close the session-start race.

Stage A already landed (`c0d6712` + `1a3b3b4`): `DefaultModelService` forwards progress; `AIModelsTab` renders per-model chips.

**Legacy:** `backlog/model-download-ux-bug-research.md` Recommended-Path items 1 + 3

---

### #010 — Drag-suppresses-tap end-to-end test (Test C)

`bug` · `P2` · `open` · `area: pill, testing`
*Updated 2026-04-21*

`mouseDown` → simulated 10pt drag (multiple `mouseDragged` events crossing the 4pt threshold) → `mouseUp`. Assert `onTap` does NOT fire; `onMouseDragged` does. Tests A + B landed (`1cb665c`). State-machine drag test at `PillOverlayPresenterTests.swift:17-34` already exists; this covers the end-to-end hosting-view path.

**Legacy:** `PLAN_PHASES.md` Step 1.4b

---

## Features

### #011 — Per-row delete on transcription history

`feature` · `P1` · `open` · `area: ui, storage`
*Updated 2026-04-21*

Inline trash icon on hover (or swipe action). Must propagate through the transcript store, not just the view-model cache.

**Depends on:** #026 (clean repository delete path)
**Legacy:** `ui-dogfood-bugs-2026-04-21.md` #17

---

### #012 — OSSignposter instrumentation for launch-freeze RCA

`feature` · `P3` · `open` · `area: session, observability`
*Updated 2026-04-21*

Wrap `prepareTranscriber()`, `performPrepare()`, `inference.loadModel` with signposts. Measure cold-launch prepare latency objectively so regressions aren't diagnosed by anecdote.

**Legacy:** `PLAN_PHASES.md` Step 1.1b

---

### #013 — NotesWindow

`feature` · `P1` · `open` · `phase: 3` · `area: ui, storage`
*Updated 2026-04-21*

Sidebar + editor + context panel. Auto-ingest transcripts. Manual edit. Tagging (→ #014). FTS5 search. Policy: notes = transcripts (single table; no `type` column).

**Depends on:** #026, Phase 3.A Modes (landed)
**Legacy:** `PLAN_PHASES.md` Phase 3.B

---

### #014 — Tags on transcripts/notes

`feature` · `P1` · `open` · `phase: 3` · `area: storage, ui`
*Updated 2026-04-21*

Either TEXT column + index, or `tags` + `transcript_tags` relation. Schema choice belongs to the storage-layer plan (#026). Part of #013 Notes scope.

**Depends on:** #026, #013

---

### #015 — OnboardingWindow

`feature` · `P2` · `open` · `phase: 3` · `area: ui, permissions`
*Updated 2026-04-21*

First-run permission flow with optional Accessibility step.

**Legacy:** `PLAN_PHASES.md` Phase 3.C

---

### #016 — Second model descriptor (parakeet-tdt-110m)

`feature` · `P2` · `open` · `phase: 3` · `area: models`
*Updated 2026-04-21*

For lower-RAM devices. Registry supports multi-variant already; just needs the second entry + validation. AIModelsTab UI already descriptor-driven.

**Legacy:** `PLAN_PHASES.md` Phase 3.F

---

### #017 — Hotkey customization in Settings (collision detection)

`feature` · `P2` · `open` · `phase: 3` · `area: settings, hotkey`
*Updated 2026-04-21*

Shortcuts subsection exists (demoted from standalone tab via `a21e7b6`). Needs recorder UI wired to `HotkeyPreference`, collision detection against system shortcuts, conflict warnings.

**Legacy:** `PLAN_PHASES.md` Phase 3.G

---

### #018 — Clipboard clobber timing (configurable paste-restore delay)

`feature` · `P3` · `open` · `phase: 3` · `area: output, settings`
*Updated 2026-04-21*

Default 0.5s. Surface in Settings → Advanced.

**Legacy:** `PLAN_PHASES.md` Phase 3.H (UX-audit BUG-07)

---

### #019 — Triple-tap ⌥ emergency quit

`feature` · `P3` · `open` · `phase: 3` · `area: hotkey`
*Updated 2026-04-21*

Reuses permission-detection plumbing from Phase 1.9.

**Legacy:** `PLAN_PHASES.md` Phase 3.I + BACKLOG P3 #7

---

### #020 — IntentClassifier (NLEmbedding → llama.cpp escalation)

`feature` · `P2` · `parked` · `phase: 4` · `area: session, models`
*Updated 2026-04-21*

Stub protocol exists from Phase 2. Full impl deferred until Phase 3 ships and dogfood exposes intent-style flow needs.

**Legacy:** `PLAN_PHASES.md` Phase 4

---

### #021 — Command Mode pill response cards

`feature` · `P2` · `parked` · `phase: 4` · `area: pill, session`
*Updated 2026-04-21*

Query answer / action confirmation / dictation variants.

**Depends on:** #020
**Legacy:** `PLAN_PHASES.md` Phase 4

---

### #022 — "Ask Ninimma" query flow

`feature` · `P3` · `parked` · `phase: 4` · `area: ui, storage`
*Updated 2026-04-21*

FTS5 + embedding lookup over transcripts/notes. Needs embeddings schema (migration on storage layer).

**Depends on:** #020, #013
**Legacy:** `PLAN_PHASES.md` Phase 4

---

### #023 — Action Dispatcher (NSWorkspace + app-specific APIs)

`feature` · `P3` · `parked` · `phase: 4` · `area: session`
*Updated 2026-04-21*

**Legacy:** `PLAN_PHASES.md` Phase 4

---

### #024 — Model Stage B: per-row delete button

`feature` · `P2` · `open` · `phase: 3` · `area: models, settings`
*Updated 2026-04-21*

`ModelRow` delete action → `ModelBoundTranscriberProvider.removeDownloadedFiles(_:)`. Confirmation sheet required. Refuse delete of active model with explanation. Surface per-model disk usage.

**Legacy:** `backlog/model-download-ux-bug-research.md` Stage B

---

### #025 — Model Stage B: disk-space precheck

`feature` · `P2` · `open` · `phase: 3` · `area: models`
*Updated 2026-04-21*

Read `ModelDescriptor.approximateSizeBytes` at Download click. Compare against `FileManager.attributesOfFileSystem[.systemFreeSize]`. Confirmation sheet if free space < 2× download size.

**Legacy:** `backlog/model-download-ux-bug-research.md` Stage B

---

## Refactors

### #026 — Central storage / database layer

`refactor` · `P1` · `in-progress` · `stage: design` · `phase: 3` · `area: storage`
*Updated 2026-04-21*

Single `AppDatabase` owning GRDB connection pool + `DatabaseMigrator` + repositories (`TranscriptRepository` first). Absorbs old Phase 3.D single-table swap. Metrics DB merge/separate is an open question for the plan.

Plan deliverable at `plans/storage-database-layer.md` (parallel session dispatched 2026-04-21). Prompt at `/tmp/storage-layer-plan-prompt.md`.

**Blocks:** #011, #013, #014, #022, #027
**Legacy:** `PLAN_PHASES.md` Phase 3.D

---

### #027 — TranscriptEntry needs `modeId` + `trigger`

`refactor` · `P2` · `parked` · `stage: design` · `phase: 4` · `area: storage, session`
*Updated 2026-04-21*

Schema evolution driven by Command Mode. `ModeDescriptor` soft-delete/tombstone for reference integrity. Trigger field may be dropped if pure signal-noise.

**Depends on:** #026, #021
**Legacy:** `backlog/transcript-trigger-context.md`

---

### #028 — Central KeyEventRouter consolidation (5a-v2)

`refactor` · `P1` · `open` · `stage: design` · `area: hotkey`
*Updated 2026-04-21*

One router owning `CGEventTap` + `NSEvent` local-monitor pair; migrate `GlobalHotkeyMonitor`, `EscapeKeyMonitor`, `HotkeyRecorder`, and ad-hoc `addLocalMonitorForEvents` callers. ~3-5 commits. Do NOT bundle with #001's bug fix.

**Depends on:** #001 shipping first
**Legacy:** `ui-dogfood-bugs-2026-04-21.md` #19

---

### #029 — Wire `PillStyle` preference to overlay rendering

`refactor` · `P2` · `open` · `area: pill, theming`
*Updated 2026-04-21*

Preference + Settings picker landed (`ee4d7ca`); the overlay still always renders Classic visuals. When Mini: smaller compact pill. When None: overlay hidden regardless of `PillVisibilityMode`. Requires reconciling with `PillVisibilityMode` semantics.

**Legacy:** `ui-mockup-gaps.md` Settings→General deferred follow-up

---

### #030 — Wire `pasteEnabled` master toggle to OutputService

`refactor` · `P2` · `open` · `area: output, settings`
*Updated 2026-04-21*

Preference + Settings toggle landed (`41c3f6c`); when disabled, should suppress both paste AND clipboard write.

**Legacy:** `ui-mockup-gaps.md` Settings→General deferred follow-up

---

### #031 — Central-layers refactor: validate remaining Stage 2/3 work

`refactor` · `P2` · `open` · `stage: review` · `area: architecture`
*Updated 2026-04-21*

`plans/central/INDEX.md` (2026-04-20) states Stage 3 executed; overall refactor likely complete with residual bugs possible. Remaining per INDEX: L1/L4 Stage 2 follow-ups, L5 inventory pending, L8 consumer wiring not landed on trunk (no Home-tab use). ~20 `[QUESTION]` rows blocked on Stage 2 precursors. Stale `PROGRESS.md` already deleted as part of this migration.

Acceptance: audit confirms each layer's Stage 2 complete OR a ticket filed for remaining work; 4 known test failures on trunk (L1/L4/L7 Stage 2) either fixed or ticketed.

**Legacy:** `plans/central/INDEX.md` + (deleted) `PROGRESS.md`

---

## Parked

### #032 — Mode pill on transcript rows

`feature` · `P3` · `parked` · `stage: design` · `area: ui`
*Updated 2026-04-21*

Mockup shows "Dictation Mode" / "Command Mode" pill on each row's trailing edge. Requires schema change (#027).

**Depends on:** #027 (and implicitly #021)
**Legacy:** `ui-mockup-gaps.md` Transcriptions row

---

### #033 — Streaming output transport decision

`refactor` · `P3` · `parked` · `stage: design` · `area: output, session`
*Updated 2026-04-21*

`OutputService.beginStream()` API landed (L5 Stage 1); `PipelineOutputSink.deliverPartial` dormant (L7 Stage 1). Transport choice gated on review: `CGEvent` incremental typing vs. chunked pasteboard + synthetic ⌘V. No production consumer permitted until decision. Undo grouping, rate limit, EOU semantics, Unicode fidelity all open.

**Legacy:** `backlog/streaming-output-delivery-mechanism.md` + `backlog/pipeline-streaming-defer.md` *(merged — same decision from two layer seats)*

---

### #034 — Waveform decay tuning

`feature` · `P3` · `parked` · `area: pill`
*Updated 2026-04-21*

Tune falloff on the pill waveform so bars don't snap to zero.

**Legacy:** `ui-dogfood-bugs-2026-04-21.md` #10

---

### #035 — Hold-hotkey mode bar visuals

`feature` · `P3` · `parked` · `area: pill, hotkey`
*Updated 2026-04-21*

Spacing / contrast / motion pass. Capture specifics when picked up.

**Legacy:** `ui-dogfood-bugs-2026-04-21.md` #11

---

### #036 — FluidAudio revision-pin follow-up

`feature` · `P3` · `parked` · `area: models`
*Updated 2026-04-21*

`ModelDescriptor.revision` currently decorative; FluidAudio `ModelRegistry.resolveModel` hard-codes `resolve/main/`. Reinstate when FluidAudio exposes a `revision:` parameter (upstream ask).

**Legacy:** `backlog/model-download-ux-bug-research.md` Stage B

---

### #037 — Mic device title-bar accessory

`feature` · `P3` · `parked` · `area: ui, audio`
*Updated 2026-04-21*

Unified-window chrome readout — "MacBook Pro Microphone (Default)". Overlaps with `AudioInputDeviceProviding` wiring for #008; pick up after that lands.

**Depends on:** #008 decision
**Legacy:** `ui-mockup-gaps.md` Settings→General deferred follow-up

---

### #038 — AI-models Stage B: "AI models" settings section

`feature` · `P3` · `parked` · `phase: 4` · `area: settings`
*Updated 2026-04-21*

Second `SettingsSection` below Voice models; seeds once Phase 4 lands an LLM downloader. `ModelRow` presenter already engine-agnostic.

**Depends on:** #020
**Legacy:** `backlog/model-download-ux-bug-research.md` Stage B

---

### #039 — Whisper.cpp streaming dedup tracker

`bug` · `P3` · `open` · `stage: design` · `area: transcription, streaming`
*Updated 2026-05-25*

`WhisperCppStableSegmentTracker.merge()` produces parallel confirmation lanes when whisper.cpp re-decodes overlapping audio with jittered word boundaries. Same segment text appears under two slightly different normalized forms, both cross the `confirmationThreshold` independently, both flush. Manifests as duplicated phrases in the live card during whisper.cpp streaming dictation.

**Cosmetic only:** live cursor EoU paste is gated off for whisper.cpp via `11c0f99` (RecipeBuilder force) and stop-time second-pass uses a batch decode that doesn't go through this tracker. So the bug never reaches the user's text field. The visible damage is confined to the live card visualization during recording.

**Design options** (from codex audit req-0066, hermes verdict on file):
1. Frozen prefix + canonical tail — split tracker into `frozenPrefix` (settled text) + `mutableTail` (latest decode wins). Easier mental model, risk on freeze-boundary heuristic.
2. Overlap-run confirmations — keep confirmation model but use time-overlap as segment identity (instead of exact normalized text). Lowest runtime cost, highest algorithmic complexity.
3. Decouple preview from authoritative per-EoU redraw — bypass tracker for preview entirely; on `.speechEnded`, run fresh whisper.cpp decode over post-boundary audio. Cleanest design, extra CPU + ~100-300ms EoU latency.

Hermes recommendation: option 3 unless EoU latency is unacceptable.

**Deferred:** revisit when product UX requires clean live card during whisper.cpp speech. Two earlier attempts at "replace-on-ingest" hit hermes review blockers (long-utterance truncation past 8.25s window; empty-decode wipes); those approaches are off the table.

**Reference:** `Sources/PersonalScribeTranscription/Adapters/WhisperCppStableSegmentTracker.swift` (trunk version, post-revert).

---

### #040 — WhisperKit streaming dogfood verification

`feature` · `P2` · `open` · `stage: verify` · `area: transcription, streaming, dogfood`
*Updated 2026-05-25*

#101 landed via `dd100ee` + `322a4da`. Source + tests green (1496/0/1) but no DMG-built dogfood exercise yet. Built app at `/Applications/Ninimma.app` is on `11c0f99` (one commit behind #101).

**Verification checklist:**
- Rebuild + sign + reinstall DMG.
- Switch active streaming model to a WhisperKit descriptor in AI Models tab.
- Run streaming dictation: confirm `.endOfUtterance` chunks paste cleanly via live cursor into focused app (confirmed-delta-only emission means no parallel-lane duplicates).
- Confirm live card updates with unconfirmed-tail `.partial` events during speech, then committed segments on confirmation.
- Run stop-time second pass: confirm force-rule reuses the same WhisperKit instance (no second download/load).
- Regression: switch back to Parakeet streaming and confirm it still works as before the #100/#101 catalog changes.
- Regression: switch back to whisper.cpp streaming and confirm the live-cursor gate still suppresses EoU paste.

**Reference:** plans/101_whisperkit_streaming/HERMES_BRIEF.md; CODEX_RESEARCH.md.

---

### #041 — Delete `AppEntryPointTests.testPersonalScribeAppMainBuildsSceneModelFromComposition` skip

`refactor` · `P3` · `open` · `stage: impl` · `area: tests`
*Updated 2026-05-25*

Test skipped since 2026-04-20 because `@StateObject` lifetime isn't retained in unit-test context. `MenuBarFlowIntegrationTests.testRecordStopTranscribeIdleFlowPublishesLatestResult` already covers the composition end-to-end without depending on `@StateObject` lifetime, so the skipped test is redundant.

**Action:** delete the test (not unskip, not refactor). Full suite expected to drop from 1496 pass / 1 skip → 1495 pass / 0 skip.

---

### #042 — Memory idle-release verified (informational, no action)

`feature` · `P3` · `done` · `area: lifecycle`
*Updated 2026-05-25*

Idle release working as designed (req-0050, `1c23cfa`). Verified empirically 2026-05-24 night: batch session 60→300→90 MB (93% reclaim), streaming session 90→723→333 MB (62% reclaim). Streaming residual is dominated by Parakeet TDT 0.6B used as second-pass batch (~600 MB peak). If lower streaming residual is needed, switching active batch ASR from Parakeet TDT 0.6B to Whisper Small WhisperKit (216 MB) cuts peak by ~400 MB. Current setting intentional per quality preference.

**No action.** Keep as ticket so the empirical numbers don't get lost.

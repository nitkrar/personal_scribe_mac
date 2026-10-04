# Ninimma — Backlog

Canonical active-work registry, GitHub-issues-style. Closed items live in [`BACKLOG_ARCHIVE.md`](./BACKLOG_ARCHIVE.md). Phase/roadmap context in [`plans/ROADMAP.md`](./plans/ROADMAP.md). Pre-migration feature notes lived in `plans/_legacy/`, now deleted; the `**Legacy:**` pointers below resolve with `git show 8755ff7:<path>`.

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

**Session naming.** The **main** Claude session running in the user's terminal picks a short single-word identifier (nature words work well — `heron`, `cobalt`, `slate`, `olive`, `rust`) the first time it touches this file and uses it consistently. Subagents dispatched from a main session **inherit its name** — they do NOT claim their own. Only a parallel main session (e.g. a second terminal) picks a distinct name. Don't use `main session` / `parallel session` / `user` as owners — too ambiguous when >1 session is live.

**Claiming a ticket.** When a session starts active work, add a row with today's date in both `Started` and `Last update`, and flip the ticket body status to `in-progress`. Delete the row when the ticket lands or reverts to `open`.

**Updating.** Bump `Last update` on heartbeat, commit, or meaningful status change. Any row with `Last update` > 3 days old = "is this alive?" check — matches the `.codex-heartbeat/` contract.

**Edit only your own rows.** A session may only edit in-flight rows where `Owner` matches its own session name, plus the shared convention text in this section. To change another session's row, ping the user instead.

**Dead-session cleanup.** If every row owned by a given session has `Last update` > 24h old, treat that session as dead. Any other session may delete those orphaned rows when it next touches the file. If a deleted row's ticket body was `in-progress`, flip the ticket body status back to `open` — a fresh session can re-claim. Don't guess at what the dead session accomplished; the commit log is ground truth.

**Blocked on user.** Prefix the Notes cell with `**[needs user]**` so items needing your attention scan first in the table.

**When to commit the backlog file.** Default: **do NOT stage or commit `BACKLOG.md`** unless the user explicitly asks (e.g. "also commit the backlog", "stage the backlog edits"). Ticket-body edits, in-flight-row changes, and `status` flips all accumulate as uncommitted local edits — that's expected and fine. When a session stages code/test changes alongside a ticket landing, **omit `BACKLOG.md` from the `git add` list** unless the user called it out. The user will batch backlog commits when they decide the scheduled drift is worth capturing.

---

## Legacy-ID cross-reference

Quick lookup when an old commit or doc cites a legacy ID.

### From `ui-dogfood-bugs-2026-04-21.md`
- #3 → #005 · #5 → #001 · #7 → #004 · #10 → #034 · #11 → #035 · #12 → #002 · #13 → #007 · #15 → #006 · #17 → #011 · #18 → #008 · #19 → #028

### From `ui-mockup-gaps.md` (open items)
- Transcriptions mode-pill (row) → #032
- Unified-shell + D-follow-up mic footer → #008 (sidebar) / #037 (title-bar accessory)
- Settings→General D-follow-up: PillStyle wiring → #102 (was #029) · pasteEnabled wiring → #030

### From `PLAN_PHASES.md`
- Step 1.1b (signposts) → #012 · Step 1.4b (drag-tap test C) → #010
- Phase 3.B (Notes) → #013 · 3.C (Onboarding) → #015 · 3.D (SQLite) → #026 · 3.F (2nd model) → #016 · 3.G (hotkey customization) → #017 · 3.H (clipboard clobber) → #018 · 3.I (triple-⌥ quit) → #019
- Phase 4 (Intent) → #020 · (Command Mode cards) → #021 · (Ask Ninimma) → #022 · (Action Dispatcher) → #023

### From other backlog docs
- `backlog/phase-8-cancel-recording.md` → #002 · `backlog/issue-6-pill-panel-focus.md` → #003 · `backlog/transcript-trigger-context.md` → #027 · `backlog/model-download-ux-bug-research.md` Stage B → #009 + #024 + #025 + #036 + #038 · `backlog/streaming-output-delivery-mechanism.md` + `backlog/pipeline-streaming-defer.md` → #033 *(merged)*

### From `plans/central/`
- All layer Stage-2/3 validation work → #031

### From `plans/BACKLOG.md` (stale copy, removed 2026-10-02)
- #039 → #104 · #040 → #105 · #041 → #106 · #042 → #107 *(archived)*. The archive's own #039–#042 are different, older tickets.
- In the archive's `REBUILD_BACKLOG.md` section, "#101" is the WhisperKit streaming adapter, not active #101.

---

## Bugs

Done bugs archived 2026-04-30 → see [`BACKLOG_ARCHIVE.md`](./BACKLOG_ARCHIVE.md) "Archived 2026-04-30: 9 bugs closed" for #002, #007, #039, #042, #071, #072, #073, #075, #077.

### #110 — Bluetooth microphones: device switches mid-recording

`bug` · `P3` · `done` · `area: audio, capture`
*Updated 2026-10-04*

Recording follows input device switches (headset connecting, disconnecting, profile/sample-rate changes) and the next recording starts cleanly; the mic footer follows device changes; exactly silent input shows a "No audio from the microphone" warning. Known limitation: about half a second is lost per switch. Bluetooth hands-free quality drop is not addressed (no built-in-mic preference). Verified with AirPods both directions in one recording; runbook in `ManualAudioCaptureVerification.md`.

---

### #104 — Whisper.cpp streaming dedup tracker

`bug` · `P3` · `open` · `stage: design` · `area: transcription, streaming`
*Updated 2026-10-02*

`WhisperCppStableSegmentTracker.merge()` produces parallel confirmation lanes when whisper.cpp re-decodes overlapping audio with jittered word boundaries. Same segment text appears under two slightly different normalized forms, both cross the `confirmationThreshold` independently, both flush. Manifests as duplicated phrases in the live card during whisper.cpp streaming dictation.

**Cosmetic only:** live cursor EoU paste is gated off for whisper.cpp via `11c0f99` (RecipeBuilder force) and stop-time second-pass uses a batch decode that doesn't go through this tracker. So the bug never reaches the user's text field. The visible damage is confined to the live card visualization during recording.

**Design options** (from codex audit req-0066, hermes verdict on file):
1. Frozen prefix + canonical tail — split tracker into `frozenPrefix` (settled text) + `mutableTail` (latest decode wins). Easier mental model, risk on freeze-boundary heuristic.
2. Overlap-run confirmations — keep confirmation model but use time-overlap as segment identity (instead of exact normalized text). Lowest runtime cost, highest algorithmic complexity.
3. Decouple preview from authoritative per-EoU redraw — bypass tracker for preview entirely; on `.speechEnded`, run fresh whisper.cpp decode over post-boundary audio. Cleanest design, extra CPU + ~100-300ms EoU latency.

Hermes recommendation: option 3 unless EoU latency is unacceptable.

**Deferred:** revisit when product UX requires clean live card during whisper.cpp speech. Two earlier attempts at "replace-on-ingest" hit hermes review blockers (long-utterance truncation past 8.25s window; empty-decode wipes); those approaches are off the table.

**Reference:** `Sources/PersonalScribeTranscription/Adapters/WhisperCppStableSegmentTracker.swift` (trunk version, post-revert).

**Reproduced 2026-10-02** (whispercpp-tiny, two `say` clips, 12 runs; output byte-identical across runs and pacing — deterministic, not jitter). Rerun: `WhisperCppStreamingDuplicationBenchmarkTests` (opt-in, env `NINIMMA_WHISPERCPP_BENCH_WAV` / `_TEXT` / `_OUT` / `_RUNS` / `_PACE` / `_MODEL`; clips + per-decode timelines were in `/tmp/ws104/`).

**Root cause** (`WhisperCppStableSegmentTracker.merge()`):
- Segment identity is exact normalized text (`segmentsMatch`). When whisper.cpp re-segments the same audio across window shifts ("Okay, so … the logs." 0–3000 ms vs "Okay so … every server," 0–4720 ms), the new shape is a separate lane, reaches the confirmation threshold on its own, and the already-confirmed old shape is carried forward (`existingIndex == merged.count → merged.append`). Both flush on the next EoU → duplicated phrase in the EoU chunk, live card, and streaming final text.
- `dropCommittedPrefixOverlap` only checks flushed text, not confirmed-but-unflushed segments.
- Live card has a second duplication path: after an EoU, a re-decode that renders the same audio differently ("So I bought" vs "by Bought") fails the normalized-prefix overlap check and the whole tail returns as a partial for ~4 s.

**Related defects in the same tracker** (same fix should cover them):
- Lost speech: segments that slide out of the 8.25 s window before reaching 2 confirmations are dropped (~15 s missing from one clip); a confirmed segment is also dropped when `existingIndex != merged.count`.
- Flicker: the partial is only the unconfirmed tail, so confirmed-unflushed text disappears from the card until the EoU.
- Bogus timestamps: some segments end 30 s after they start (e.g. 36510–66510 ms), defeating any time-overlap check.

Scope: live card + streaming final text for whisper.cpp only; paste uses the batch second pass (not tested). Only `tiny` tested. Suggests design option 2 (time-overlap identity) or 3 (bypass tracker) above.

**Legacy:** `plans/BACKLOG.md` #039 (ID already used in `BACKLOG_ARCHIVE.md`; renumbered 2026-10-02)

---

## Features

Done features archived 2026-05-01 → see [`BACKLOG_ARCHIVE.md`](./BACKLOG_ARCHIVE.md) "Archived 2026-05-01: 12 done features + refactors closed" for #011, #013, #015, #016, #017, #024, #046, #078, #089, #092 (and refactors #028, #090).

### #012 — OSSignposter instrumentation for launch-freeze RCA

`feature` · `P3` · `open` · `area: session, observability`
*Updated 2026-10-02*

**Shipped so far:** `b2c8357` — `SessionCoordinator.prepareTranscriber()` has an outer `OSSignposter` interval that measures end-to-end preparation; the former inner `performPrepare()` / `loadModel` spans did not survive the adapter refactor and remain to be restored if per-stage timing is still required.

Wrap `prepareTranscriber()`, `performPrepare()`, `inference.loadModel` with signposts. Measure cold-launch prepare latency objectively so regressions aren't diagnosed by anecdote.

**Legacy:** `PLAN_PHASES.md` Step 1.1b

---

### #014 — Tags on transcripts/notes

`feature` · `P1` · `open` · `phase: 3` · `area: storage, ui`
*Updated 2026-04-21*

Either TEXT column + index, or `tags` + `transcript_tags` relation. Schema choice belongs to the storage-layer plan (#026). Part of #013 Notes scope.

**Depends on:** #026, #013

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

### #045 — Personal dictionary (2-stage)

`feature` · `P2` · `open` · `phase: 3` · `area: post-processing, memory-learning`
*Updated 2026-10-02*

**Shipped so far:** `c82af27`, `00f5f9b` — post-processing is a composed `PostProcessingStage` pipeline and the session path runs it; `PersonalDictionaryStage`, dictionary persistence, and decoder-level biasing remain unimplemented.

Central to the Memory/Learning competitive pitch (`COMPETITIVE.md`). **Stage A:** refactor `PostProcessor` to a chain-of-stages; add `PersonalDictionaryStage` applied first. Data: `DictionaryEntry { term, alternatives: [String], createdAt, source }`; JSON at `<AppConfig.baseDirectory()>/dictionary.json`. Case-insensitive word-boundary replacement, first match wins per region; no regex. No UI — manual file edit until Phase 3 Settings. Soft cap ~40 entries / 60-char alternatives. **Stage B:** decoder-level biasing via Parakeet CTC custom-vocab head + correction-learning loop from NotesWindow edit UI — `CollectionDifference`-based edit tracking + Levenshtein filter; top-30 decayed-frequency terms feed the CTC vocab.

**Depends on:** #013 (NotesWindow edit UI — Stage B only)
**Legacy:** `plans/_legacy/BACKLOG_pre_migration.md` → "Personal dictionary — ship in two stages"

---

### #047 — Auto-pause playback during recording (2-stage)

`feature` · `P3` · `open` · `area: audio, output, dictation`
*Updated 2026-04-22*

**Stage A:** on `SessionCoordinator.start()`, read UserDefaults `AutoPausePlayback` (default `true`). If enabled, send `MPRemoteCommandCenter.shared().pauseCommand` — system-wide pause for active media app. No auto-resume. No Settings UI until Stage B. **Stage B (with Phase 3 Settings):** toggle bound to the same UserDefaults key + optional opt-in auto-resume after session ends. **Meeting-mode caveat:** disable auto-pause when meeting mode is active (dual-track needs system audio playing).

**Legacy:** `plans/_legacy/BACKLOG_pre_migration.md` → "Auto-pause playback during recording"

---

### #048 — Active window context capture (2-stage)

`feature` · `P2` · `open` · `phase: 3` · `area: session, storage`
*Updated 2026-04-22*

Substrate for future smart-routing + mode rules. **Stage A:** new `RecordingContext { bundleIdentifier, appName, capturedAt }` in `PersonalScribeCore`. Optional `context` field on `TranscriptEntry` (schema additive — Codable optional handles back-compat). At hotkey-press, read `NSWorkspace.shared.frontmostApplication` via a `FrontmostAppProviding` protocol (mirrors `PasteInjector`'s capture-before-Ninimma-focus pattern). Pass through `SessionCoordinator.start()`. No UI, persist metadata only. Unknown context = valid `nil`. **Stage B:** opt-in window title (AX — already have permission) + browser URL (per-browser scripting). Privacy-sensitive — never Stage A.

**Blocks:** #057 (app-context mode-selection rules consume this substrate)
**Legacy:** `plans/_legacy/BACKLOG_pre_migration.md` → "Active window context capture — ship in two stages"

---

### #059 — Dual-track recording (mic + system audio)

`feature` · `P2` · `open` · `phase: 4` · `area: audio, meeting`
*Updated 2026-04-22*

`ScreenCaptureKit` audio tap (macOS 13+). Mic track = "me" trivially; diarize only the system-audio track. Precondition for meeting mode. Fundamental change from today's mic-only capture (which mixes speaker leakage into a single stream).

**Blocks:** #061
**Legacy:** `plans/_legacy/BACKLOG_pre_migration.md` → "Dual-track recording"

---

### #060 — Voice identification + cross-session speaker DB (absorbs #049)

`feature` · `P2` · `open` · `area: session, dictation, meeting`
*Updated 2026-04-22*

**Absorbed #049 (me-vs-other speaker verification) on 2026-04-22.** One ticket for all voiceprint-based speaker identification, whether the user is tagging "me" or any named other speaker. The N=1 case (just "me" enrolled) is functionally identical to the N>1 case — same plumbing. Design rationale + Q&A lives in [`plans/speaker-diarization-design.md`](./plans/speaker-diarization-design.md).

**Stage A (minimum):** voiceprint DB at `<AppConfig.baseDirectory()>/speakers.json` storing N entries of `{ name, embedding, enrolledAt, source }`. No dedicated "Enroll my voice" ceremony — after any recording where diarization finds > 1 cluster (or duration exceeds a threshold), show a post-stop prompt *"Tag speakers for this recording?"*. Each cluster renders as a short audio snippet; user types a name or skips. On save, voiceprint is persisted. Subsequent recordings: seed Pyannote's `DiarizerManager` via `initializeKnownSpeakers(allStored)` — matched clusters auto-label by name, unmatched → `speaker 2` / `speaker 3` etc. User can retroactively rename any cluster (including unmatched ones — saves a new voiceprint). Solo-speaker recordings don't prompt.

**Stage B (dogfood-gated):** Settings UI for DB management (rename / delete / merge speakers), threshold tuning, low-confidence warnings, optional auto-label-me heuristic after N frequent solo-speaker recordings.

**Open unknowns** *(carry into implementation planning)*: Pyannote pipeline size + peak RAM (measure `FluidInference/speaker-diarization-coreml` once); whether `speakerThreshold: 0.65` is appropriate; prompt-noise tuning (duration + cluster-count thresholds); solo-dictation auto-label heuristic for Stage B; clustering-anchor false-positive behavior when a new voice is close to an enrolled one.

**Supersedes:** #049.
**Blocks:** #061.
**Legacy:** `plans/_legacy/BACKLOG_pre_migration.md` → "Me-vs-other speaker verification" + "Cross-session speaker recognition"
**Design:** [`plans/speaker-diarization-design.md`](./plans/speaker-diarization-design.md)

---

### #051 — Lifetime + historical time-saved analytics

`feature` · `P3` · `open` · `area: metrics, ui`
*Updated 2026-10-02*

**Shipped so far:** `75f529f`, `76742a5` — Home consumes `MetricsReading` for rolling-seven-day rollups and recent transcripts; lifetime totals, per-mode breakdowns, and historical trends remain unimplemented.

Partial coverage exists via Home rollups (`SQLiteMetricsService` rolling-7-day windows — landed in #026). Remaining scope: expose lifetime totals, per-mode breakdowns, historical trends. Home for this UI: new Stats view, or extend Transcriptions tab with a summary strip.

**Legacy:** `plans/_legacy/BACKLOG_pre_migration.md` → "Time-saved analytics"

---

### #052 — Voice tags / micro-prompts

`feature` · `P3` · `open` · `area: session, dictation`
*Updated 2026-04-22*

Prefix a recording with a short tag word ("reminder", "email Alice", "todo") that drives downstream routing or labeling. Overlaps conceptually with #057 (app-context mode-selection rules) — investigate whether voice tags subsume, complement, or compete with context rules before scoping implementation.

**Legacy:** `plans/_legacy/BACKLOG_pre_migration.md` → "Voice tags, micro-prompts"

---

### #057 — App-context rules for mode selection

`feature` · `P2` · `open` · `area: dictation, session`
*Updated 2026-04-22*

Frontmost-app rules: `Notes/Word/Pages → long-form`, `Slack/iMessage → quick`. Not FluidAudio-specific. Needs both the context substrate and the streaming mode to be meaningful.

**Depends on:** #048 (context capture substrate), #056 (streaming mode)
**Legacy:** `plans/_legacy/BACKLOG_pre_migration.md` → "App-context rules for mode selection"

---

### #064 — Landing page / website

`feature` · `P3` · `open` · `area: distribution, pre-launch`
*Updated 2026-04-22*

Pre-public-launch marketing page. Single page: pitch from `PROPOSAL.md` + screenshots + download link + privacy stance. Static hosting; no backend.

**Legacy:** `plans/_legacy/BACKLOG_pre_migration.md` → "Future (not yet scoped)"

---

### #065 — Homebrew distribution

`feature` · `P3` · `open` · `area: distribution, packaging, pre-launch`
*Updated 2026-04-22*

Homebrew cask formula so `brew install --cask ninimma` works. Handles DMG download + `/Applications/` install. Coordinates with first-run permission prompts; document the TCC ad-hoc-path quirk so `brew`-installed + DMG-installed copies don't collide.

**Legacy:** `plans/_legacy/BACKLOG_pre_migration.md` → "Future (not yet scoped)"

---

### #066 — Accessibility audit

`feature` · `P2` · `open` · `area: a11y, pre-launch`
*Updated 2026-04-22*

Full VoiceOver pass: menu-bar interactions, pill states (recording / hold-to-record / transcribing), Settings tabs, Transcriptions tab, Notes window. Keyboard navigation for non-pointer users. Contrast checks against `Palette` tokens under warm / neutral / dark tints.

**Legacy:** `plans/_legacy/BACKLOG_pre_migration.md` → "Future (not yet scoped)"

---

### #067 — Data-at-rest encryption (SQLCipher)

`feature` · `P3` · `open` · `area: storage, security`
*Updated 2026-04-22*

Migrate `transcripts.sqlite` to SQLCipher-backed encrypted DB. Key via Keychain. Needs GRDB-SQLCipher integration (replaces GRDB system-SQLite linkage). Useful for shared-machine users / stronger than current `0600` perms. Requires migration path on upgrade.

**Depends on:** #026 (done — single DB owner in place)
**Legacy:** `plans/_legacy/BACKLOG_pre_migration.md` → "Future (not yet scoped)"

---

### #068 — In-pill mode switcher (quick UX)

`feature` · `P2` · `Stage A done · Stage B pending` · `phase: 3` · `area: pill, ui, modes`
*Updated 2026-10-02*

**Shipped so far:** `15e73ec` — the menu-bar Mode submenu lists modes, marks the active one, and switches the next session; the in-pill picker remains unimplemented.

Switch the active mode directly from the pill overlay (or the menu-bar status item) instead of having to open Settings → Modes tab. Today mode switching is a multi-click journey through the unified window; this ticket makes it a one-click flip next to where the user is already looking.

**Status (2026-04-24)** — Stage A shipped (menu-bar submenu). Stage B (pill bottom-row icon) deferred until a second mode lands; with `ModeRegistry.all = [dictation]` today the menu-bar submenu is one-item scaffolding that auto-lights-up when modes infra grows.

**Locked design decisions (2026-04-24 session):**
- **Where**: menu-bar "Mode" submenu (Stage A) + pill bottom-row icon → click opens picker (Stage B). Click-only — no hover chip, no long-press.
- **Modes listed**: all wired modes including user-defined; unwired modes hidden until they have distinct behavior.
- **When it applies**: immediately (next session starts in new mode). Mid-recording flip out of scope.
- **Keyboard chord**: dropped. Discoverability problem (no way to surface the cycle direction) outweighed the speed win.

**Stage A — DONE** (`bf28dd3`, 2026-04-24): menu-bar "Mode" submenu. Mirrors `StatusItemMenuModel` Microphone-submenu pattern via a new `.modeSubmenu` `Item` + `ModeSubmenuChild`. Lists `ModeRegistry.all`, checkmark on the active mode, selection routes through `modelService.setActive(modelService.descriptor(for: mode))` — same closure shape as the existing `UnifiedWindowController` ModesTab path. Snapshot observer rebuilds the menu on `activeMode` change → checkmark + parent title update automatically. Tests: 2 new in `StatusItemMenuModelSubmenuTests` + 9 existing mic-submenu tests + 20 baseline `StatusItemMenuModelTests` all pass. Runtime click-through not yet manually verified.

**Stage B — PENDING**: pill bottom-row mode icon → click opens picker. Real architectural cost; explicitly NOT minimal.
- Pill geometry today is single-row HStacks at fixed dimensional bands (`PillOverlayView.swift:40-78`, `size(for:)` at L96-119). Adding a row changes the height bands and breaks the `PillOverlayPresenter` per-state panel-resize tween (#044).
- Sub-region clicks inside the pill don't fire SwiftUI gestures — `ClickThroughHostingView.mouseDown` overrides without `super`. Needs AppKit hit-testing for the new icon region (see memory `project_pill_hit_testing`).
- Click target needs to open a picker against a non-activating `NSPanel` — popover plumbing not currently wired anywhere on the pill.
- Per-state visibility (does the icon show during recording / downloading / error?) is a design call.

**Stage B preconditions:** (a) ≥ 2 wired modes exist (otherwise Stage B is shipping complex infra to point at a list-of-one); (b) decision on whether the icon shows in active-recording states or only in idle.

**Depends on:** none for Stage A (ModesTab + `ModeDescriptor` already live). Stage B effectively blocked on additional modes infra landing.
**Legacy:** none — net-new ticket from 2026-04-22 UX session.

---

### #069 — Persist audio recordings on disk

`feature` · `P2` · `open` · `phase: 3` · `area: audio, storage, session`
*Updated 2026-10-02*

**Shipped so far:** `ffadbca` — the orchestrator writes WAV sidecars, the database stores `audio_filename`, transcript deletion cascades to audio, and Advanced settings plus `RecordingRetentionSweeper` implement enable/retention controls. The proposed disk-usage readout and Delete All Recordings action remain unimplemented.

Today audio lives only in `SessionCoordinator.bufferedAudio: [PCMBuffer]` in memory and is dropped after transcription. The `recordings/` directory name is aspirational — `AppConfig.swift:71` literally comments "Reserved for future recordings/ feature." This ticket fills that gap.

**Why now:** unlocks re-transcription with upgraded voice models, audio replay from the Transcriptions tab, retroactive diarization (re-run #058 / #060 on past recordings), and export. Today all of those require re-capturing the audio.

**Stage A (minimum):** on `SessionCoordinator` stop, write the in-memory buffer as `.wav` (16 kHz mono 16-bit — native capture format, no encoding step) to `<AppConfig.recordingsDirectory()>/<UUID>.wav`. Add an optional `audioFilePath: String?` column to the `transcripts` table via a new migration registered in `TranscriptsMigrator`; the column stores the relative filename, not a full path (base directory is resolved at read time). `TranscriptRepository.append(_:)` writes the path alongside the entry in one transaction. UI: none — metadata-only for now. Feature gate: `RecordAudioEnabled` UserDefaults default `true`; off means fire-and-forget capture (today's behavior).

**Stage B (dogfood-gated):** retention policy — configurable default (suggest 30 days) via a background sweeper that deletes `.wav` files older than N days and nulls the corresponding `audioFilePath` column. Settings UI under Advanced → "Audio recordings" section: toggle, retention slider, current disk-usage readout, "Delete all recordings" button. Compression (`.m4a` or `.caf` via `AVAudioFile` encoding) only if uncompressed disk usage proves painful — `.wav` at 2 MB/minute means a 1-hour meeting is 120 MB; 30-day retention at 10 min/day is ~600 MB. Measure real usage first.

**Open questions:**
- Format: start `.wav` (no encoding, simplest) or jump straight to compressed? Recommend `.wav` for MVP.
- Retention default: 30 days / 90 days / never? Lean 30 days with Settings slider.
- **Retention shape — open discussion (2026-04-30):** "cap at last N recordings" (e.g. 1 or 3) raised as a possible alternative or complement to days-based retention; rationale would be that for the re-transcribe-after-error use case only the most recent recording matters. No concrete proposal — revisit during Stage B scoping alongside the days-based default question above.
- Disk-space guardrail: warn or hard-stop when recordings dir exceeds X GB?
- Transcript deletion (#011) — should it cascade to the audio file?
- Filesystem permissions: mirror the DB's `0600`.

**Depends on:** #026 (schema migration via `TranscriptsMigrator` — done).
**Unlocks:** #058 retroactive diarization, #060 retroactive voice-ID re-tagging, "replay audio" UI in Transcriptions tab, "re-transcribe" action after upgrading the voice model, **#094 "re-transcribe last recording" UX (combined with #094's file-source pipeline path)**.
**Legacy:** `Sources/PersonalScribeCore/Storage/AppConfig.swift:71` comment — "Reserved for future recordings/ feature" has been reserved since Phase 1.

---

### #070 — Recording pause/resume (pill affordance)

`feature` · `P2` · `open` · `area: session, pill, audio`
*Updated 2026-10-02*

**Shipped so far:** `481cbad` — Esc cancellation retains the captured buffers briefly and the Cancel Card can resume them; a direct pill pause/play affordance and first-class paused state remain unimplemented.

Replace pill ✕ with a pause/play toggle on pill-click-initiated recordings. Pausing retains the captured audio buffer; resume continues appending; final stop (click pill, or a stop affordance in paused state) transcribes the whole buffer. Esc remains the sole discard path (per #002) once this ships — ✕ goes away entirely.

**Scope:**
- New session state `.paused` alongside `.recording` / `.transcribing`; buffer retention across pause boundaries.
- `SessionCoordinator.pauseRecording() async` + `resumeRecording() async`; `SessionPipelining.pauseCapture()` / `resumeCapture()`.
- Audio capture actor: stop emitting samples without tearing down `AVAudioEngine` input (keep tap installed, pause buffering) OR stop the engine and re-prime on resume — evaluate latency/correctness of each.
- Pill UI: pause/play icon in place of ✕; visual indicator for paused state (dimmed equalizer bars? frozen waveform?); recording-duration timer pauses.

**Open questions:**
- Timeout: auto-transcribe after N minutes paused, or hold indefinitely?
- Interaction with VAD auto-stop (#046) — does VAD trigger auto-pause, auto-stop, or do nothing while paused?
- Menu-bar "Stop" path while paused — transcribe or discard?
- Paused state needs a stop-and-transcribe affordance distinct from resume — pill-click, long-press, secondary button?

**Out of scope:** hold-to-record flow — that path uses a separate pill with no Esc/✕/pause affordance; release always stops + transcribes.

**Depends on:** #002 (locks `✕ = true-discard` semantics first; #070 then reclaims that slot for pause/play and removes the ✕).
**Legacy:** 2026-04-22 brainstorm (after #002 spec-literal lock).

---

### #093 — Grouped Transcriptions list + bulk delete

`feature` · `P2` · `open` · `area: ui, storage`
*Updated 2026-10-02*

**Shipped so far:** `601bb37`, `a7a7955` — the Transcriptions tab groups rows into date buckets; selection mode, group checkboxes, bulk deletion, and type grouping remain unimplemented.

Transcriptions tab today is a flat scrolling list with per-row delete (`#011` done). Two additions:

1. **Grouping** — sectioned list with sticky-ish headers:
   - **By date** (default): Today / Yesterday / This week / Earlier — derived from `TranscriptEntry.timestamp`. Ships against today's schema.
   - **By type** (meeting / dictation / note): blocked on `#027` (`modeId` + `trigger` on `TranscriptEntry`). Until that lands, the type grouping has no source-of-truth field — picker hides "By type" or shows it disabled with a tooltip.

2. **Bulk delete** — opt-in selection mode toggled by a global header button:
   - Header shows `[ Bulk delete ]` button. Tap → enters select mode: reveals a checkbox in every row + every group header.
   - Group-header checkbox is tri-state (none / some / all selected within that group). Toggling it selects/deselects every row in the group.
   - Row checkboxes select individually; per-row trash icon (#011 affordance) hides while in select mode.
   - Header button flips label → `[ Delete N selected ]` (or similar) once any row is selected; tap = confirm + delete.
   - Exit select mode: explicit `Cancel` affordance, OR auto-exit after the delete completes.

**Scope (date grouping path — shippable today):**
- `TranscriptionsTabViewModel`: derive `[(GroupHeader, [TranscriptEntry])]` from the existing entry list. Group bucketing pure-fn, unit-testable.
- New VM state: `selectionMode: Bool`, `selectedIDs: Set<UUID>`. `enterSelectionMode()` / `cancelSelectionMode()` / `toggleRow(id:)` / `toggleGroup(headerID:)` / `deleteSelected()` (calls `TranscriptRepository.delete(id:)` per ID; reload-on-success mirrors existing delete pattern).
- `TranscriptionsTab` SwiftUI: section headers, conditional checkboxes, header button label state machine.
- `TranscriptRepository.delete(ids:)` batched variant — optional optimization; per-ID loop is fine for v1 (typical bulk = ≤ tens of rows).
- Tests: VM unit tests for group derivation, tri-state header logic, selection toggle, delete-selected reload. Manual-verification entries `MV-BULK-1..N` in `ManualTranscriptionsVerification.md`.

**Scope (type grouping path — blocked):**
- Lift after `#027` lands `modeId` + `trigger` on `TranscriptEntry`. Bucketing fn extends to read those fields; picker enables "By type".

**Open questions:**
- Confirmation step before delete (alert with row count) — yes/no? Worth pinning since bulk-delete is a higher-blast-radius action than per-row.
- Search-active behavior: if the user has filtered by query, does "Delete N selected" delete only matched rows (current view) or all selected across the unfiltered list?
- Group-by picker location — header next to the bulk-delete button, or in a dropdown menu?

**Depends on:**
- `#011` (done) — `TranscriptRepository.delete(id:)` + reload pattern.
- `#027` (parked, phase 4) — required for the "by type" grouping option only; date grouping does not depend on it.

**Legacy:** none — net-new.

---

### #094 — Offline file transcription (tab + menu-bar shortcut)

`feature` · `P2` · `open` · `stage: followup` · `area: ui, transcription, dictation, diarization, menu-bar`
*Updated 2026-10-02*

**Shipped so far:** `e683ea3` — the Offline tab, serial file queue, persisted preferences, row-level re-transcribe, and menu-bar Retranscribe Last Recording are implemented; the listed Stage B import, progress, playback, and bulk workflows remain open.

Stage A landed as `bef41f7` on 2026-05-24 (single squashed commit; full
`swift test` clean at 1422/0/1, +41 over baseline). User launched the
bundle locally after Santa reapproval. Manual verification entries
`MV-OFFLINE-1..9` queued in
`Tests/ManualVerifications/ManualOfflineTranscriptionVerification.md`
— per project TDD rules, SwiftUI work earns the "shipped" label only
after MV runs complete.

**Stage A landed**
- Unified-window **Offline** tab with persisted batch-ASR model +
  diarization preferences, drag-drop + Browse rooted at
  `<AppConfig.recordingsDirectory()>`, serial queueing, cancel/dequeue,
  and completed-job transcript inspection.
- File-source offline transcription path built on the shared session
  adapters rather than a separate local pipeline.
- Status-item **Retranscribe Last Recording** action that re-runs the
  most recent persisted recording, copies the new transcript to the
  clipboard, and surfaces toast feedback.
- `Transcriptions` row-level re-transcribe affordance with visible press
  feedback and per-source busy state while a matching job is in flight.
- Transcript-history refresh on offline append / retranscribe
  completion, so new rows appear without reopening the window.

**Implementation note**
- Phase-1 step `2.1` through `2.9.1` landed as 10 intermediate req-0051
  commits, squashed by atlas into `bef41f7`. Two reviewer findings
  (10x-engineer + pool-codex-1) folded into the same commit before
  squash.
- `BACKLOG.md` remains intentionally unstaged during agent work; atlas
  batches the backlog commit separately.

**Stage B / residual scope**
- Broader import ergonomics beyond the current local-audio flow
  (additional formats, richer picker/import affordances, automation).
- Deeper long-file progress / queue inspection / retry UX.
- Playback / compare tooling in History for persisted recordings and
  retranscribed variants.
- Folder-watch / bulk-import workflows.
- ~~Durable queue~~ — done in `fbeede3`: queue saved to `db/offline-jobs.json`; queued and interrupted jobs re-run at launch.
- Any future offline recipes that go beyond the current fixed
  retranscribe path plus the tab-level model + diarization knobs.

**Depends on:**
- None blocking shipped Stage A.
- #069 for the persisted-recording retranscribe surfaces.

**Unblocks:** ad-hoc transcription of saved recordings, retranscribe
recovery after a bad live result, and future replay / compare affordances
on transcript rows.

**Legacy:** none — net-new.

---

### #102 — Pill redesign: separate click targets, hover detail

`feature` · `P2` · `open` · `area: pill, overlay, settings`
*Updated 2026-10-04*

**Shipped so far:** cards choose above/below placement, the pill grows away from a nearby edge, the live pill has a three-strand waveform, Light appearance renders the whole pill coherently, and Style is wired (Classic, Mini at 0.75×, None never shows the pill). Pill visibility is an "Auto-hide pill" toggle, disabled under Style None.

1. **Separate click targets.** The whole pill is one tap target that toggles recording; the × and stop are drawn but not separate buttons. Make cancel, stop and the body distinct targets. Prerequisite for 2.
2. **Minimal while recording, more on hover.** Show a design preview before building. Mini may shrink further (around 50%) as part of this.
3. **Style preview cards are stale.** Settings → Recording window → Style previews draw a single-line equalizer instead of the three-strand waveform.

Not doing: vertical or circular shapes at side edges; the pill stays horizontal.

---

### #088 — Narrow FluidAudio model download to runtime-needed files

`refactor` · `P2` · `open` · `area: transcription, models, downloads`
*Updated 2026-04-29 (Filed 2026-04-28)*

`DownloadUtils.downloadRepo` (FluidAudio) over-pulls when a repo's
subPath contains sibling directories or duplicate model formats.
Concrete case: Qwen3-ASR int8 lands ~2.9 GB on disk for an int8
runtime that only needs ~1.25 GB. The bloat:

- `qwen3_asr_audio_encoder.mlmodelc` (v1, ~369MB) + `.mlpackage` (~368MB)
  alongside the v2 the runtime actually loads (~370MB compiled).
- `qwen3_asr_decoder_stateful.mlpackage` (~577MB) alongside the
  `.mlmodelc` we use (~578MB).

**Audit-confirmed scope (2026-04-29, during #090 descriptor pinning
dogfood)**: the same over-pull pattern affects more than just Qwen.
Streaming Parakeet (`parakeet-eou-streaming/<chunk>`) downloads a
`parakeet_eou_preprocessor.mlmodelc` that runtime doesn't load, plus
a stray `streaming_encoder_metadata.json` in the 320ms variant.
Qwen3 f32 + int8 each have v1 encoders + `.mlpackage` siblings
alongside the v2 runtime artifacts. Whoever picks #088 up should
plan the wrapper to clean BOTH families, not Qwen-only.

**Root cause** (FluidAudio bug): the listing recursion
(`DownloadUtils.swift:321-355`) admits any directory whose path
starts with the subPath, then admits any nested file matching
`isMetadata` — `.json` / `.model` / `.bin` extensions — regardless
of whether the parent directory was named in the pattern list.
`.mlmodelc` and `.mlpackage` directories contain `weights.bin` and
`coremldata.bin` files; the carve-out scoops them up.

**Why ours-not-FluidAudio.** We already bypassed FluidAudio's
higher-level `Qwen3AsrModels.download` (which silently dropped the
`to:` argument) by calling `DownloadUtils.downloadRepo` directly
from `LiveFluidAudioQwenManager`. We're already one step from
"replace the only FluidAudio download call with our own."

**Scope.** A shared narrower wrapper used by every adapter, not a
Qwen-only special case. Per-adapter forks would re-introduce the
duplication we just collapsed in #078 (the shared
`FluidAudioDownloadProgressBroadcaster` consolidation, `848c095`).

Approach (sketch):
- New `FluidAudioDirectDownloader` in `PersonalScribeTranscription`
  using FluidAudio's public lower-level API:
  `DownloadUtils.downloadSubdirectory(_ repo:subdirectory:to:)`
  (line 521 of `DownloadUtils.swift`) per `.mlmodelc` directory the
  descriptor's `requiredRelativePaths` declares, plus a small
  URLSession fetch helper for top-level metadata files (vocab.json,
  embeddings.bin) via `ModelRegistry.resolveModel(remotePath:filePath:)`.
- Adapter manager protocols' `downloadIfNeeded(...)` route through
  this wrapper instead of `DownloadUtils.downloadRepo`. All four
  adapters change in lockstep — no Qwen-specific path.
- Descriptor's `requiredRelativePaths` becomes the contract; the
  wrapper enforces it. Drift between descriptor and FluidAudio's
  `requiredModelsFull` enums is now visible at our layer.

**Tradeoff.** We own the download path, including future FluidAudio
release tracking. If FluidAudio adds a required file we don't list,
runtime fails. Mitigation: pin the FluidAudio version + add a smoke
test that loads each registered model from its descriptor's required
paths.

**Alternative.** File upstream issue + PR against FluidAudio to
tighten `downloadRepo`'s metadata carve-out (constrain to depth-1
under subPath, AND require pattern-list match for nested
directories). Cleaner architecturally but slower + we don't control
release cadence.

P2 because the bloat is one-time per model activation (not
per-session) and the user can manually clean unused files. Bumps to
P1 if dogfood disk pressure becomes an issue or if a model variant
bloats >2× its declared size and breaks the disk-space precheck.

**Legacy:** session-generated 2026-04-28 from Qwen int8 download
inspection (#078 follow-up).

---

### #074 — State-ownership audit across app

`refactor` · `P0` · `in-progress` · `area: architecture`
*Updated 2026-10-04*

State ownership kept fragmenting: the same concept lived in several places coupled to different state machines. The audit's fixes are listed by `git log --grep '#074'`; manual checks are the `MV-HOME-1`, `MV-PILL-RESUME-*`, `MV-PILL-STYLE-*`, `MV-SI-LAUNCH-1`, `MV-SI-MIC-1`, `MV-OFFLINE-QUEUE-1` and "Change base directory" runbook entries.

**Open:** session and mode-registry validation accept any enabled model kind, while the Modes screen, menu and per-mode hotkeys require an active, downloaded model. Since the download cache now refreshes after preparation, the two agree in practice; tightening validation is optional.

**Not doing:** remembering window frame, last tab or menu-bar icon visibility across launches; collapsing the four-layer permission-status copy (no observed bug).

---

## Parked

### #049 — Me-vs-other speaker verification *(superseded by #060)*

`feature` · `P3` · `parked` · `area: session, dictation, meeting`
*Updated 2026-04-22*

**Superseded by #060 on 2026-04-22.** Scope — single-voiceprint enrollment for "me" + binary me/other labeling — collapsed into #060 as the N=1 case of a generalized voiceprint DB. Same plumbing for 1 voiceprint vs N; no reason to split the work. See [`plans/speaker-diarization-design.md`](./plans/speaker-diarization-design.md) for the Q&A that drove the merge.

ID retained for traceability (IDs never reused). No scheduled work — new voice-ID work goes on #060.

**Supersedes:** —
**Superseded by:** #060
**Legacy:** `plans/_legacy/BACKLOG_pre_migration.md` → "Me-vs-other speaker verification — ship in two stages"

---

### #032 — Mode pill on transcript rows

`feature` · `P3` · `parked` · `stage: design` · `area: ui`
*Updated 2026-04-21*

Mockup shows "Dictation Mode" / "Command Mode" pill on each row's trailing edge. Requires schema change (#027).

**Depends on:** #027 (and implicitly #021)
**Legacy:** `ui-mockup-gaps.md` Transcriptions row

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

### #050 — Correction tracking / auto-learning

`feature` · `P3` · `parked` · `phase: 4` · `area: memory-learning, notes`
*Updated 2026-04-22*

Diff user-edited transcript vs original via `CollectionDifference`; pair removals with nearby insertions; filter by Levenshtein distance. Feeds #045 Stage B dictionary frequency ranking (top-30 decayed-frequency terms → CTC vocab bias). Requires NotesWindow edit UI to observe edits.

**Depends on:** #013 (NotesWindow edit UI), #045 Stage A
**Legacy:** `plans/_legacy/BACKLOG_pre_migration.md` → "Correction tracking / auto-learning"

---

### #054 — Smart auto-archive

`feature` · `P3` · `parked` · `phase: 3` · `area: notes, storage`
*Updated 2026-04-22*

Auto-archive transcripts older than N days or shorter than M chars; hide from primary Transcriptions view, keep searchable via FTS. Specific policy (N / M / archive criteria) TBD — parked until dogfood reveals what becomes cruft.

**Legacy:** `plans/_legacy/BACKLOG_pre_migration.md` → "Smart auto-archive"

---

### #053 — Transcript cleanup: dictionary → disfluency tagger → number rules; LLM rewrite opt-in

`feature` · `P2` · `parked` · `area: post-processing, memory-learning`
*Updated 2026-10-03*

**Shipped so far:** `c82af27`, `00f5f9b`, `6fd7768`, `aeddfb6` — the stage pipeline runs vocal-filler removal (um/uh/er/ah/hmm only) and basic punctuation while preserving diarized line boundaries.

Replaces the original 7-stage string-rule chain. Whisper and Parakeet already emit punctuation and capitalization, and regex can't tell filler "like" from the verb (`aeddfb6` removed that after it broke saved transcripts).

**Every dictation (must be fast on any Mac, never adds words):**
1. **Personal dictionary** — #045.
2. **Disfluency tagger** — small token classifier (BERT-size) that marks fillers, stutters and false starts for deletion. Tens of ms regardless of length; can only delete, so it can't change meaning. Untested: needs a spike to find a model and run it on the saved recordings.
3. **Inverse text normalization** — grammar rules for numbers, money, percentages, dates, times ("twenty five percent" → "25%"). No LLM: in the benchmark below only one model formatted numbers, and it was the one that rewrote sentences.

**Cleanup setting:** global "Clean up transcript" toggle (General → Transcribe output) with per-mode Default/On/Off override shipped (`705dc18`). An AI rewrite level needs its own setting when the LLM step lands.

**Opt-in per mode:** LLM rewrite (e.g. "make this an email"), default Qwen3.5-2B Q4 (~1.3 GB resident; keep warm while the mode is active or pay the load on every recording).

**LLM sizing:** Qwen3.5-2B (thinking off) is the smallest model that cleans without rewriting; sub-1B models fail the instruction. ~0.5 s per 100 words on M5 Max, ~5–8× slower on base M1/M2 — too slow for every dictation. Models in `~/Projects/nitkrar/models/bench-small/`. Apple Foundation Models requires Apple Intelligence enabled, so optional backend at most.

**Depends on:** #045 Stage A (the chain architecture must exist first)
---

### #058 — Speaker diarization (LS-EEND, up to 10 speakers)

`feature` · `P3` · `parked` · `phase: 4` · `area: meeting, audio`
*Updated 2026-10-02*

**Shipped so far:** `db28a84`, `6e7f06d` — an offline FluidAudio VBx diarizer adapter and per-mode speaker-separation sensitivity are wired; the ticket's LS-EEND streaming implementation and up-to-10-speaker contract remain unimplemented.

FluidAudio LS-EEND: 10 speakers max, 100ms streaming updates, single model. Sortformer optional (4 speakers, stronger identity, NVIDIA Open Model License — licensing trade-off). Building block for #061 Meeting mode.

**Blocks:** #061
**Legacy:** `plans/_legacy/BACKLOG_pre_migration.md` → "Speaker diarization (LS-EEND default)"

---

### #061 — Meeting mode

`feature` · `P3` · `parked` · `phase: 4` · `area: meeting, dictation`
*Updated 2026-04-22*

Zoom/Teams/Webex auto-detect + dual-track capture + diarization + cross-session speaker names. Composes #058 + #059 + #060 into a product-facing feature. Dual-track (#059) splits me from remote-audio cheaply; LS-EEND (#058) splits the remote-audio side into unnamed clusters; #060's voiceprint DB names them.

**Depends on:** #058, #059, #060
**Legacy:** `plans/_legacy/BACKLOG_pre_migration.md` → "Meeting mode"
**Design:** [`plans/speaker-diarization-design.md`](./plans/speaker-diarization-design.md)

---

### #062 — TTS for assistant speaking back (Kokoro + PocketTTS)

`feature` · `P3` · `parked` · `phase: 4` · `area: assistant, audio`
*Updated 2026-04-22*

Kokoro 82M parallel (SSML, pronunciation control) + PocketTTS streaming with voice cloning. English-only initially. Enables voice-out for Ask Ninimma (#022) and Action Dispatcher (#023) confirmations.

**Depends on:** #022 OR #023 (a consumer)
**Legacy:** `plans/_legacy/BACKLOG_pre_migration.md` → "TTS for assistant speaking back"

---

### #063 — MCP server exposing transcripts

`feature` · `P3` · `parked` · `phase: 4` · `area: assistant, storage`
*Updated 2026-04-22*

Wishlist — build only on actual demand. Stage A shape: standalone stdio binary (~200–300 LOC SPM executable target) reading `transcripts.sqlite` via `TranscriptRepository`, exposing read-only tools `search_transcripts` / `list_recent_transcripts` / `get_transcript`. No in-app HTTP server unless Stage A proves insufficient. Privacy caveat at opt-in time (transcripts contain sensitive speech).

**Legacy:** `plans/_legacy/BACKLOG_pre_migration.md` → "MCP server exposing transcripts"

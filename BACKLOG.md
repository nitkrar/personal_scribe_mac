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

### #114 — Deleting an offline transcript logs a false "file removal failed"

`bug` · `P3` · `done` · `area: history, offline`
*Updated 2026-10-06* · Follow up after #102.

**Done 2026-10-06 (102.142):** delete skips absolute paths (the user's own files) and recordings another transcript still references.

Offline transcripts store an absolute source path, but `TranscriptRepository.delete` joins it onto the recordings directory, so the removal targets a path that doesn't exist and logs a failure. Delete should use the stored path as-is when it's absolute (and must never delete the user's original source file — check what an offline transcript owns before fixing).

---

### #115 — Finished offline jobs never leave the Offline list

`bug` · `P3` · `done` · `area: offline`
*Updated 2026-10-06* · Follow up after #102.

**Done 2026-10-06 (102.143):** "Clear finished" in the Offline queue header removes completed, failed and cancelled jobs.

Completed jobs stay in `offline-jobs.json` and the Offline tab forever, with no way to remove them. Completed jobs should leave the queue (their result is in History), or the tab needs a remove/clear action.

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

`feature` · `P2` · `parked` · `phase: 3` · `area: post-processing, memory-learning, settings`
*Updated 2026-10-06*

**Shipped so far:** `c82af27`, `00f5f9b` — post-processing is a composed `PostProcessingStage` pipeline and the session path runs it; `PersonalDictionaryStage`, dictionary persistence, and decoder-level biasing remain unimplemented.

Central to the Memory/Learning competitive pitch (`COMPETITIVE.md`). **Stage A:** refactor `PostProcessor` to a chain-of-stages; add `PersonalDictionaryStage` applied first. Data: `DictionaryEntry { term, alternatives: [String], createdAt, source }`; JSON at `<AppConfig.baseDirectory()>/dictionary.json`. Case-insensitive word-boundary replacement, first match wins per region; no regex. Soft cap ~40 entries / 60-char alternatives. **Stage B:** decoder-level biasing via Parakeet CTC custom-vocab head + correction-learning loop from NotesWindow edit UI — `CollectionDifference`-based edit tracking + Levenshtein filter; top-30 decayed-frequency terms feed the CTC vocab.

**Screen (Stage A):** a "Vocabulary" item in the main-window sidebar. One input at the top, "New word or replacement": Return adds it as a word (spelling to keep, e.g. a name or acronym); typing in the "Replace with…" field and pressing ⌘Return adds a replacement (heard → written). The entries are listed below, newest first, as `word` or `heard → written`, each editable in place and deletable; a search field appears once the list is long. When the list is empty, a dismissible tip reads "Add your first word: people's names, company names, acronyms or jargon so they're transcribed correctly." Not part of onboarding. Reference: Superwhisper's Vocabulary page.

**Steering spike (2026-10-06, TTS audio, spike code deleted):** Parakeet CTC rescoring took term hits 20–25 → 42–45/45 but rewrote 8–9/21 control sentences (`code→Codex`, `model→Codex`) and only fixes near-spellings; needs the separate 113 MB `parakeet-ctc-110m` model and `CtcModels.loadDirect` (other loaders delete-and-redownload on failure). WhisperKit prompt: 25 → 42/45, clean, but decode time ×3 and prompt capped at ~111 tokens (~15–20 terms). whisper.cpp prompt: 18 → 38/45, no cost. Qwen3 / Parakeet EOU: no hook. Parakeet adapter claims `providesCustomVocabulary` but nothing feeds it. Parked by user.

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

`feature` · `P2` · `done` · `area: pill, ui, modes`
*Updated 2026-10-05*

Stage A shipped (`bf28dd3`): the menu-bar Mode submenu switches the next session. Stage B (mode button on the pill) folded into #102.

---

### #069 — Persist audio recordings on disk

`feature` · `P2` · `done` · `phase: 3` · `area: audio, storage, session`
*Updated 2026-10-06*

**Closed 2026-10-06:** recording, delete cascade, toggle and retention cover the need; the disk-usage readout and "Delete all recordings" are dropped.

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

`feature` · `P2` · `superseded` · `area: session, pill, audio`
*Updated 2026-10-05*

Folded into #102 (pause/resume design agreed 2026-10-05).

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

`feature` · `P2` · `done` · `stage: followup` · `area: ui, transcription, dictation, diarization, menu-bar`
*Updated 2026-10-06*

**Closed 2026-10-06:** the Offline tab, queue, re-transcribe and Clear finished cover the need; the Stage B wishlist is dropped until something concrete comes up.

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

### #102 — Pill redesign

`feature` · `P2` · `done` · `phase: 3` · `area: pill, overlay, session, settings`
*Updated 2026-10-05*

The one ticket for the floating pill. Absorbs #070 (pause), #068 Stage B (in-pill mode switcher) and #035. Agreed mockups: [`plans/backlog/pill-redesign-mockups.png`](plans/backlog/pill-redesign-mockups.png) (Mini + Classic, dark and light). Shipped in 102.82–102.104; all MV-PILL checks passed 2026-10-05.

**One pill, two styles.** Every state has one layout shared by both styles. A style sets only (1) its sizes and (2) whether controls show only on hover. Mini: small, controls on hover. Classic: larger, controls always shown.

**Clicks (both styles):** each button is its own target: mode, record, pause/resume, stop. Clicking the middle area toggles recording (idle → start, recording → stop); it does nothing while paused. Dragging moves the pill. Esc cancels (Cancel card with Resume, which resumes recording).

**States**
- Idle at rest: the quill (Mini mockup 40×16; Classic 80×28).
- Idle hover: mode button and record button, just wide enough for the two with a little padding (Mini mockup 66×30), "Start recording" tooltip. Mode opens a menu of modes; the choice applies to the next recording. Classic gets this too, at Classic size. The mode button shows only when there is more than one mode to choose from; otherwise idle hover keeps the same size with the record button alone, centred.
- Recording: pause · waveform · stop. Mini shows the waveform only at rest (110×20) and the buttons on hover (170×30); Classic always shows them (220×36).
- Paused: resume · "Paused · 0:23" · stop.
- Transcribing: a small spinner at the recording size, so the pill doesn't grow or shrink after stop.
- No "done" check in either style: after transcribing the pill returns straight to idle.

**Pause**
- Pause stops capture and transcribes the piece since the last start/resume; the text is held. Any number of pause/resume cycles.
- Resume starts a fresh capture; it's transcribed at the next pause or stop.
- Stop (pill, menu toggle, hotkey) joins all pieces in order, pastes, and saves one History entry.
- Auto-stop on silence is off while paused.
- A recording left paused finishes on its own after a timeout (default 5 min, Settings slider next to the Cancel card duration), or at once on quit or mode switch: it saves to History and copies to the clipboard (no paste), with a "Saved to History" notice.

**Also:** Settings → Style previews draw the new pills.

**Not doing:** cancel button on the pill (Esc only). A round style is a separate ticket (#113).

---

### #088 — Narrow FluidAudio model download to runtime-needed files

`refactor` · `P2` · `done` · `area: transcription, models, downloads`
*Updated 2026-10-06*

**Closed 2026-10-06 (102.147):** fixed upstream in FluidAudio #826 and shipped in 0.17.5; required and non-required `.mlmodelc`/`.mlpackage` bundles are now matched whole. Existing installs keep their leftover duplicates until the model is deleted and downloaded again.

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

`refactor` · `P0` · `done` · `area: architecture`
*Updated 2026-10-05* · All manual checks passed; closed.

State ownership kept fragmenting: the same concept lived in several places coupled to different state machines. The audit's fixes are listed by `git log --grep '#074'`; manual checks are the `MV-HOME-1`, `MV-PILL-RESUME-*`, `MV-PILL-STYLE-*`, `MV-SI-LAUNCH-1`, `MV-SI-MIC-1`, `MV-OFFLINE-QUEUE-1` and "Change base directory" runbook entries.

**Open:** session and mode-registry validation accept any enabled model kind, while the Modes screen, menu and per-mode hotkeys require an active, downloaded model. Since the download cache now refreshes after preparation, the two agree in practice; tightening validation is optional.

**Not doing:** remembering window frame, last tab or menu-bar icon visibility across launches; collapsing the four-layer permission-status copy (no observed bug).

---

## Parked

### #104 — Whisper.cpp streaming dedup tracker

`bug` · `P3` · `parked` · `stage: design` · `area: transcription, streaming`
*Updated 2026-10-06*

**Parked 2026-10-06:** the user dictates with WhisperKit and Parakeet, not whisper.cpp. What it costs: on whisper.cpp, paste-on-pause stays off (gate in `RecipeBuilder`), and the live card stutters briefly at a pause. The card shows one line of about 12 words. Decodes run every 0.5 s over the last 8.25 s of audio. If whisper.cpp needs full support, build design option 3: one decode per pause gives one clean chunk, then lift the paste gate.

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

`feature` · `P3` · `superseded` · `area: pill, hotkey`
*Updated 2026-10-05*

Folded into #102.

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

### #112 — Onboarding inside the main window

`feature` · `P2` · `done` · `phase: 3` · `area: onboarding, unified-window`
*Updated 2026-10-06*

**Closed 2026-10-06:** built in 102.116–102.134.

Replaces the separate onboarding window (#015) with setup inside the main window; the sidebar stays usable and menu-bar items are never gated. Mockups: `plans/backlog/onboarding-home/` B* (V-* is the Vocabulary page for #045).

**Steps:** Permissions (microphone, accessibility; live status, open System Settings) → Mic test (device picker, live level) → Model (recommended model preselected, download progress, "Show all models") → Try the shortcut (⌥/, practice field, pill appears, success state) → Done (Home with a one-time "You're set up" banner). Back/Continue and "Skip setup" on every step; a "Get started N/5" sidebar row while setup is open. No vocabulary step.

**Decisions:** Microphone is the only required setup permission. `OnboardingCompleted` flips when microphone access is granted, so setup opens at launch only while microphone access is missing; an already-open setup runs to the end. Skip closes setup. If microphone access is still missing, setup reopens next launch; once granted, it stays closed and unsatisfied optional steps such as Accessibility and Try it become pending items in Home's "Get started" card. Without Accessibility, transcript delivery falls back to the clipboard. Dictation pastes into Ninimma itself only when an editable, non-secure text field has focus, so the practice field works through the normal paste path.

---

### #116 — Home refresh

`feature` · `P2` · `done` · `phase: 3` · `area: home, unified-window`
*Updated 2026-10-05*

Mockups: `plans/backlog/onboarding-home/` H-*. Stats card in mockup order (words per minute, words, recordings, time saved as "3h 42m"; recordings sits in the mockup's Apps used slot until #117) with a range picker (Last 7 days / Last 30 days / All time, default All time). Below it a compact "Get started" list of pending setup items only (customize your shortcut, create a mode; each done automatically or by clicking its circle, then removed; × dismisses the card for good; #112 adds skipped setup steps here), then the 3 most recent transcripts. No "What's new". All data already exists.

---

### #117 — "Apps used" stat

`feature` · `P3` · `done` · `area: home, history, persistence`
*Updated 2026-10-06*

Save where each transcript went (new optional column) and show an "Apps used" tile on Home. Taken from Superwhisper's Home; decide on build whether it replaces Recordings or is added.

Decided 2026-10-05:
- Store the app's display name at paste time, not the bundle ID; uninstalled apps keep their saved name.
- Tie it to a successful paste. Live transcripts are inserted as "Clipboard" (the clipboard copy always happens) and updated to the app name after a successful paste; the update also posts a metrics refresh.
- Offline file transcripts store "File". Rows from before the column show "Unknown" (NULL).
- Nothing is excluded: Ninimma itself and browsers count by app name.

Built 2026-10-06: `destination_app` column (v7); the tile replaces Recordings (mockup slot) and counts distinct app names, not "Clipboard"/"File"/NULL. No per-transcript display yet, so "Unknown" isn't shown anywhere.

**Depends on:** #116

---

### #118 — Pill skips brief in-between states

`feature` · `P3` · `parked` · `area: pill, overlay`
*Updated 2026-10-05*

Loading ("Warming up model…"), transcribing and downloading often last well under 0.3s, so the pill flashes them for a frame or two; launch model preload does this every launch. Wishlist: the pill presenter shows these three only once they've lasted about 0.3s, otherwise it goes straight to the next state. Recording, hold-to-record, paused, cancelled, idle and hide stay instant. One timer in the presenter, not per-state logic.

Related: the pill's `error` state is never produced; a failed session drops straight to idle (`AppStore.derivePillVisibility`).

---

### #113 — Orb pill style (round, Siri-like)

`feature` · `P3` · `open` · `area: pill, overlay`
*Updated 2026-10-05*

A third pill style on top of #102's one-layout model: at rest the pill is a small circle. Idle shows the quill; recording shows a round pulsing waveform instead of the three-strand one. On hover, paused and transcribing it grows into the Mini capsule (same buttons and click rules) and shrinks back to the circle afterwards. Adds a rest shape (capsule or circle) to what a style sets. Needs mockups before building.

**Depends on:** #102

---

### #111 — Optional cloud models via your own API key

`feature` · `P3` · `parked` · `area: transcription, post-processing, settings`
*Updated 2026-10-05*

Local models stay the default; no built-in cloud models. Later, let the user add a cloud provider (voice or LLM) with their own API key, from a preset list or a custom OpenAI-compatible endpoint. Audio or text leaves the Mac only for modes that pick one of these models, and the Models list marks them as cloud.

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

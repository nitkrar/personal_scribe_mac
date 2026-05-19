# Ninimma — Backlog

Canonical active-work registry, GitHub-issues-style. Lives at repo root as of 2026-04-22 (previously `plans/BACKLOG.md`). Closed items live in [`BACKLOG_ARCHIVE.md`](./BACKLOG_ARCHIVE.md). Phase/roadmap context in [`plans/ROADMAP.md`](./plans/ROADMAP.md). Central-layers refactor plans stay at [`plans/central/`](./plans/central/). Pre-migration feature notes + Phase 1/2 closures archived at [`plans/_legacy/BACKLOG_pre_migration.md`](./plans/_legacy/BACKLOG_pre_migration.md).

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
| #056 | slate | 2026-05-01 | 2026-05-02 | **[needs user]** Code complete + race + chain bugs fixed in `80f9bf0`. Awaiting rebuild + retest. EOU silent-paint inconsistency open — `.finalized`-backfill UX call pending. |

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

Done bugs archived 2026-04-30 → see [`BACKLOG_ARCHIVE.md`](./BACKLOG_ARCHIVE.md) "Archived 2026-04-30: 9 bugs closed" for #002, #007, #039, #042, #071, #072, #073, #075, #077.

### #010 — Drag-suppresses-tap end-to-end test (Test C)

`bug` · `P2` · `open` · `area: pill, testing`
*Updated 2026-04-21*

`mouseDown` → simulated 10pt drag (multiple `mouseDragged` events crossing the 4pt threshold) → `mouseUp`. Assert `onTap` does NOT fire; `onMouseDragged` does. Tests A + B landed (`1cb665c`). State-machine drag test at `PillOverlayPresenterTests.swift:17-34` already exists; this covers the end-to-end hosting-view path.

**Legacy:** `PLAN_PHASES.md` Step 1.4b

---

## Features

Done features archived 2026-05-01 → see [`BACKLOG_ARCHIVE.md`](./BACKLOG_ARCHIVE.md) "Archived 2026-05-01: 12 done features + refactors closed" for #011, #013, #015, #016, #017, #024, #046, #078, #089, #092 (and refactors #028, #090). Multilingual ASR sweep 2026-05-18 → see "Archived 2026-05-18" for #095 (WhisperKit) and #098 (whisper.cpp), plus refactor #091 (per-model language hint).

### #012 — OSSignposter instrumentation for launch-freeze RCA

`feature` · `P3` · `open` · `area: session, observability`
*Updated 2026-04-21*

Wrap `prepareTranscriber()`, `performPrepare()`, `inference.loadModel` with signposts. Measure cold-launch prepare latency objectively so regressions aren't diagnosed by anecdote.

**Legacy:** `PLAN_PHASES.md` Step 1.1b

---

### #014 — Tags on transcripts/notes

`feature` · `P1` · `open` · `phase: 3` · `area: storage, ui`
*Updated 2026-04-21*

Either TEXT column + index, or `tags` + `transcript_tags` relation. Schema choice belongs to the storage-layer plan (#026). Part of #013 Notes scope.

**Depends on:** #026, #013

---

### #018 — Clipboard clobber timing (configurable paste-restore delay)

`feature` · `P3` · `open` · `phase: 3` · `area: output, settings`
*Updated 2026-04-21*

Default 0.5s. Surface in Settings → Advanced.

**Legacy:** `PLAN_PHASES.md` Phase 3.H (UX-audit BUG-07)

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

### #025 — Model Stage B: disk-space precheck

`feature` · `P2` · `open` · `phase: 3` · `area: models`
*Updated 2026-04-21*

Read `ModelDescriptor.approximateSizeBytes` at Download click. Compare against `FileManager.attributesOfFileSystem[.systemFreeSize]`. Confirmation sheet if free space < 2× download size.

**Legacy:** `backlog/model-download-ux-bug-research.md` Stage B

---

### #045 — Personal dictionary (2-stage)

`feature` · `P2` · `open` · `phase: 3` · `area: post-processing, memory-learning`
*Updated 2026-04-22*

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
*Updated 2026-04-22*

Partial coverage exists via Home rollups (`SQLiteMetricsService` rolling-7-day windows — landed in #026). Remaining scope: expose lifetime totals, per-mode breakdowns, historical trends. Home for this UI: new Stats view, or extend Transcriptions tab with a summary strip.

**Legacy:** `plans/_legacy/BACKLOG_pre_migration.md` → "Time-saved analytics"

---

### #052 — Voice tags / micro-prompts

`feature` · `P3` · `open` · `area: session, dictation`
*Updated 2026-04-22*

Prefix a recording with a short tag word ("reminder", "email Alice", "todo") that drives downstream routing or labeling. Overlaps conceptually with #057 (app-context mode-selection rules) — investigate whether voice tags subsume, complement, or compete with context rules before scoping implementation.

**Legacy:** `plans/_legacy/BACKLOG_pre_migration.md` → "Voice tags, micro-prompts"

---

### #056 — Streaming dictation mode (StreamCard + EOU cursor stream + optional second pass)

`feature` · `P2` · `in-progress` · `phase: 4` · `area: dictation, session`
*Updated 2026-05-02*

V1 remains a user-created custom mode / preset (not a built-in mode). English-only. Precondition for #057 (app-context rules).

**Design:** [`plans/056_streaming_dictation/DESIGN.md`](./plans/056_streaming_dictation/DESIGN.md)
**Implementation:** [`plans/056_streaming_dictation/IMPLEMENTATION.md`](./plans/056_streaming_dictation/IMPLEMENTATION.md)

**Locked design (2026-04-30):**
- Split surfaces:
  - `StreamCard` = live transcript only, controlled by the session pipeline.
  - existing `ResponseCard` = short operational/status messages only (`Finalizing…`, `Copied to clipboard`, `Clipboard restored`, transport fallback / errors).
- `StreamCard` shows the rolling session tail. Make it wider than the current ResponseCard, but keep it single-line. No editing.
- Live cursor streaming is a separate setting (global default + per-mode override). Cursor delivery is append-only and emits end-of-utterance chunks only.
- If live cursor streaming is on, there is never an extra stop-time cursor write.
- Second pass is optional (global default + per-mode override). When enabled, it is authoritative for history + clipboard only; it never rewrites external apps. If second pass fails, fall back to the streaming model's final text.
- If second pass is off, persist/copy the streaming model's own final text.
- Restore-clipboard in live mode restores the pre-recording clipboard snapshot.
- Existing final auto-paste path still applies only when live cursor streaming is off.

**Status (2026-05-02):** all 6 IMPLEMENTATION stages plus the post-implementation hardening commits have landed on trunk. Live cursor transport (#033) is wired through `LiveCursorOutput`. Code is complete; **runtime verification in progress on the user's other laptop**. Stale dogfood lines from earlier rounds removed — the prior body claimed "no live partial surface wired" which is no longer true post-`41c2024`/`51fb4a8`/`46e2ed8`.

**Scope notes:**
- `Streaming Dictation` is a custom-mode preset (#089 covers per-mode hotkeys / mode selection).
- StreamCard surface, second-pass authoritative final, and cursor-stream transport are all live.
- Shared audio spooling / temp-file capture is out of scope for #056 and should land as shared infrastructure for all modes (separate ticket if dogfood demands).

**Known stale UI** (slated for #033 cleanup, not blocking): `ModeDetailView.swift:130` + `GeneralTab.swift:341` still display *"Live cursor transport is not active in this build."* — pre-#033 wording.

**Depends on:** #033 (✅ done) — wired the live cursor transport.

**Legacy:** `plans/_legacy/BACKLOG_pre_migration.md` → "Streaming dictation mode"

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
*Updated 2026-04-24*

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
*Updated 2026-05-19*

Today audio no longer disappears after transcription. Stage A shipped persisted `.wav` recordings under `<base>/recordings/`, stores the relative filename on the transcript row, cascades transcript deletes to audio-file deletes, and runs a launch + daily retention sweep against stale recordings.

**Why now:** unlocks re-transcription with upgraded voice models, audio replay from the Transcriptions tab, retroactive diarization (re-run #058 / #060 on past recordings), and export. Today all of those require re-capturing the audio.

**Stage A (shipped on trunk):** landed in `4c0e09a`, `f2d2bb9`, `4cf2ade`, `a31cff0`, `571f0ea`, `ac6b49d`, and `3ed36d3`. That work split the DB into `<base>/db/transcripts.sqlite`, added nullable `audio_filename`, wrote 16 kHz mono `.wav` sidecars with transcript-first failure handling, cascaded transcript deletes to sidecar deletes, shipped the Advanced → `Recordings` toggle + retention picker (`Save audio recordings`, default on; `Keep recordings for`, default 7 days), and added the launch + 24-hour retention sweeper that deletes stale `.wav` files and nulls matching `audio_filename` values.

**Residual Stage B:** user-facing consumers of the persisted audio: replay from the Transcriptions tab, re-transcribe/export flows, and any dogfood follow-up on disk-usage surfacing, bulk deletion (`Delete all recordings`), compression, or alternative retention shapes.

**Open questions:**
- **Retention shape — open discussion (2026-05-19):** "cap at last N recordings" (e.g. 1 or 3) remains open as a possible alternative or complement to the shipped days-based retention control.
- Disk-space guardrail: warn or hard-stop when recordings dir exceeds X GB?
- Compression: stay with shipped `.wav`, or add `.m4a` / `.caf` once real dogfood disk-usage data justifies the extra complexity?
- Replay / re-transcribe UX: Transcriptions row affordances, last-recording shortcut integration (#094), and export surface still need product shaping.

**Depends on:** #026 (schema migration via `TranscriptsMigrator` — done).
**Unlocks:** #058 retroactive diarization, #060 retroactive voice-ID re-tagging, "replay audio" UI in Transcriptions tab, "re-transcribe" action after upgrading the voice model, **#094 "re-transcribe last recording" UX (combined with #094's file-source pipeline path)**.
**Legacy:** `Sources/PersonalScribeCore/Storage/AppConfig.swift:71` comment — "Reserved for future recordings/ feature" has been reserved since Phase 1.

---

### #070 — Recording pause/resume (pill affordance)

`feature` · `P2` · `open` · `area: session, pill, audio`
*Updated 2026-04-22*

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
*Updated 2026-04-30*

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

`feature` · `P2` · `open` · `area: ui, transcription, dictation, diarization, menu-bar`
*Updated 2026-04-30*

Two entry points for offline transcription of audio files.

**1. Right-pane tab** (rich entry):
- **Batch ASR model picker** — selector for the transcriber descriptor used for the run.
- **Speaker detection toggle** — binary on/off; on = wraps in `.diarizedTurns`, off = bare `.transcriber`. (Replaces the prior "dictation vs. meeting mode picker" idea — knobs, not modes; keeps the tab out of the WorkflowMode abstraction entirely.)
- **File area** — click opens file picker defaulting to `<AppConfig.recordingsDirectory()>` (so users can re-transcribe their own past recordings without browsing); drag-drop also accepted. `.wav` for v1.
- **Selected-files table** — 2 columns: filename + realtime progress. Multi-file accepted; processed **serially** (one in flight at a time, others queued — this reconciles "Light queue UI" + "minimal one-at-a-time concurrency"). Cancel mid-run for the in-progress file; queued files dequeueable.

**2. Menu-bar item — "Retranscribe last recording"**:
- Single click. No picker, no preview, no inline UI.
- Always re-runs against the most recently persisted recording from #069.
- **Hardcoded dictation-only recipe** (fixed default transcriber descriptor, no diarization). Streaming-active-mode wrinkle resolved by ignoring active mode entirely.
- **Out-of-band**: does NOT mutate active mode, active model, or the menu-bar's currently-displayed chord/mode. Active-mode state machine never sees this action.
- Users wanting batch + diarized re-transcription go through the tab.

**Defaults (first launch / persistence):**
- Tab batch-ASR model picker — first launch matches the user's current `activeModel`, then persists independently within the tab.
- Speaker detection toggle — first launch off, thereafter persists last state.

**Scope:**
- **File-source audio adapter** — finite file-read stream emitting PCM frames at the rate the pipeline expects, replacing `AudioCaptureActor`'s live mic stream. Reuse existing transcriber + diarizer adapters (#078 protocols are source-agnostic).
- Format conversion via `AVAudioFile`: read source, downmix to mono, resample to 16 kHz.
- Right-pane tab SwiftUI: model picker + diarization toggle + drop zone + queue table + per-file progress.
- Menu-bar item wired to a fixed dictation recipe + `<recordingsDirectory>/most-recent` lookup.

**Open questions:**
- Format breadth — start with `.wav` (matches what #069 will write) + `.m4a` (Voice Memos export)? Others on demand.
- Long files — stream frames in, don't load whole file. Cancel button mid-run.
- Live-capture interaction — block file transcription during an active session, queue it, or allow concurrently? Concurrent needs careful model-load management.
- Tab placement — alongside Transcriptions / Modes / AI Models. Pick during design.

**Connected work — "re-transcribe last recording":**
- Falls out of #094 (menu-bar item) + #069 (persisted recording). No new pipeline work.
- User's "cap at last N" retention shape captured as an open discussion on #069.

**Depends on:**
- None blocking the tab — the file-source adapter is the new piece; transcriber + diarizer protocols (#078) are already source-agnostic.
- Menu-bar "Retranscribe last recording" item: #069 (persist audio recordings).

**Unblocks:** error-recovery when pipeline fails post-capture, ad-hoc transcription of imported audio (Voice Memos, meeting MP3s).

**Legacy:** none — net-new.

---


### #096 — Diagnostics system consolidation

`refactor` · `P2` · `open` · `area: diagnostics, observability, errors, settings`
*Filed 2026-04-30*

Today's diagnostics is split across two adjacent mechanisms:

- `Sources/PersonalScribeCore/Logger.swift` — `PersonalScribeLogger` wraps `os.Logger` for `debug / info / error` (~100 call sites in Sources/).
- `Sources/PersonalScribeCore/SessionErrorReporter.swift` — structured session failures → `logs/errors.log` + `ReportedError` for the response-card path (added in `30381cf` / #092.5).

That split is workable for the immediate error-display fix but is the wrong long-term shape — there's one event-emission concept being expressed twice. This ticket consolidates both into a single `DiagnosticsReporter` with one shared event model, optional `userFacing` payload that gates UI surfacing without coupling logging to UI, and adds Advanced-settings controls for verbose disk capture + a live diagnostics overlay panel.

**Locked architectural decisions** (see design doc):

- D1: One diagnostics system, one event model. No "logger vs reporter" split.
- D2: `userFacing` is optional metadata on the event. **Not** a parallel `errorWithUserReport(...)` API.
- D3: Diagnostics layer never imports AppKit. Session/UI layer converts `userFacing` payload to `SessionSnapshot.reportedError`. ResponseCard remains one consumer of that snapshot field.
- D4: Error-level events always persist to `logs/errors.log` regardless of verbosity setting. Settings widen capture, never disable error logging.
- D5: Advanced settings own `Diagnostic Logging` (`Errors Only` default / `Verbose`) + `Show Live Diagnostics Overlay` (off; only available when Verbose).
- D6: `Diagnostics*` types live in `PersonalScribeCore`. Live overlay UI lives in `PersonalScribeAppKit`, consumes the in-memory ring buffer through public Core API.
- D7: `DiagnosticsReporter` is constructed in `AppComposition` with sinks injected. Tests inject reporter with `InMemoryTestSink`. No `Diagnostics.shared` singleton.

**Sinks** (all behind one fan-out reporter):

- `OSLogSink` — replaces direct `PersonalScribeLogger` writes.
- `ErrorFileSink` — `logs/errors.log` (always-on).
- `VerboseFileSink` — `logs/diagnostics.log` (Verbose only). Errors NOT duplicated.
- `RingBufferSink` — bounded (~200 events), feeds the live overlay.
- `InMemoryTestSink` — unbounded + ordered; test-only, asserts emitted events.

**PII redaction** at sink boundary via `PIIRedactor`:

- Always-safe metadata keys: `level`, `category`, `mappedError`, `stage`, `mode`, `descriptorID`, `pipelineShape`, `errorType`.
- Always-redacted metadata keys: `transcript`, `path`, `deviceName`, `windowTitle`, `appName`, `audioFile`, `userMessage`. Value → `<redacted>`; key preserved for grep.
- Value-pattern: regex `/Users/[^/]+` → `/Users/<redacted>`.
- `underlyingError` rendered as `String(describing: type(of: error))` + case name; never `String(describing: error)`.

**Rollout** (Stage A–G; each stage leaves repo buildable):

- A. Core diagnostics primitives (event/level/sinks/reporter/PIIRedactor).
- B. Cut over `PersonalScribeLogger` — recommendation: retire after migration, mechanical rename of ~100 sites, delete `Logger.swift`. (Codex's plan currently keeps a permanent facade — pick before B starts.)
- C. Session failure path migrated to emit through `DiagnosticsReporter` with `userFacing: .sessionError(...)`.
- D. Non-session blind spots (`MenuBarSceneModel` auto-paste, `SessionCoordinator` persistence, orchestrator prewarm) emit via reporter; no `userFacing`.
- E. Advanced-settings UI: `DiagnosticLoggingMode` enum + `showLiveDiagnosticsOverlay` bool. AppComposition wires sinks based on mode.
- F. Live diagnostics overlay (`LiveDiagnosticsOverlayController/Presenter/View`) — separate floating panel, ResponseCard styling, persistent + scrollable + filterable + copy button. Read-only; no paste, no link actions.
- G. Cleanup + docs + manual verification runbook (`MV-DIAG-1..5`).

**Plans on disk** (read these first before implementation):

- `plans/diagnostics-system-design.md` — locked decisions D1–D7 + Q1–Q4 + PII section.
- `plans/diagnostics-system-implementation.md` — Stage A–G rollout, file lists, test expectations, exit criteria.
- `plans/diagnostics-system-review.md` — concrete edits Codex should fold into both docs before starting (PII section, two-file model, retire-vs-facade, DI wiring example).

**Effort estimate**: L (>1.5d) for full A–G; M (~1d) for Stage A alone.

**Depends on**: nothing blocking. #092.5 (`30381cf`) is the precondition that proves the snapshot-driven UI seam works; this ticket consolidates the diagnostics backend the response-card seam already depends on.

**Unblocks**: live debug overlay during dogfooding (currently no on-screen visibility into recent events); structured telemetry layer if ever needed; cleaner extension point for new categories without pollination across two systems.

**Legacy:** none — net-new. Picks up where #092.5 left off.

---

## Refactors


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

`refactor` · `P0` · `open` · `area: architecture`
*Filed 2026-04-24*

State ownership keeps fragmenting during ostensibly-simple tasks: the same concept lives in multiple places coupled to different state machines. Recurring pattern, not tied to any single class.

**Examples:**
- **Consolidated (good precedent):** session + capture pipeline (see `plans/central/`). One coordinator, one state machine.
- **Previously fragmented (unified as part of #072):** clipboard snapshotting split across `PasteboardSnapshotService` (session-lifecycle) and `ClipboardBatchOutput.savedItems` (output-pipeline). Landed as one consolidated `PasteboardSnapshotService` with durable `.cancelUndo` slot + transient handles.

Audit scope intentionally left open. Walk state concepts, not classes. Details filled in during the audit — not now.

---

### #027 — TranscriptEntry needs `modeId` + `trigger`

`refactor` · `P2` · `done` · `phase: 4` · `area: storage, session`
*Updated 2026-05-01*

Schema evolution to record which mode produced each transcript. Drives the row pill mockup (#032) and downstream filtering once Command Mode (#021) lands. Unparked 2026-04-30 — multiple modes now exist via the #089 editor, so `modeId` has information value even before #021. **Shipped 2026-05-01** in `156f43b` (squashed from `deb807f` + 2 follow-ups, pushed to trunk; 1126 tests / 1 skipped / 0 failures). Trigger field intentionally deferred per locked design.

**Codex follow-up baked into the squash:** `bindRecipeForNextSession(_:)` is mutated mid-flight by `SessionCoordinator` (eager pre-bind of the next session's recipe). The first cut read `boundRecipe?.recipeID` directly in `persist()` — a rebind landing during transcription would have rewritten the modeId. Same race on `runBoundProcessing`, `resolvedVadPreferencesForSession`, `currentBoundRecipe()`. Fix: introduce `activeSessionRecipe: BoundRecipe?` snapshotted at session start, retained through `.completed`, cleared on cancel/discard. Regression: `testCurrentBoundRecipeStaysSessionFrozenDespiteMidTranscriptionRebind`.

**Locked design (2026-04-30 grooming session):**

1. Add `preset: Preset` field to `WorkflowMode`. Codable additive — `decodeIfPresent` with `.dictation` fallback for pre-#027 documents. `Preset.materialize(name:)` sets it at creation time.
2. Change `WorkflowMode.id` format from `custom-{UUID}` to `{cleanName}-{suffix}` (suffix = short random / hash). One-time migration of existing `customModes` re-mints ids. `cleanName` = user-facing name at creation, stripped to id-safe chars.
3. Add `modeId: String` to `TranscriptEntry`. Captured at commit time from `registry.currentMode.id`.
4. #032 row-badge rendering paths:
   - **Live mode:** `customModes.first(where: { $0.id == modeId })?.preset.displayName` → "Notes" / "Meeting" / "Dictation" / "Streaming Dictation".
   - **Deleted mode:** `modeId.split(separator: "-").first.map(String.init)` → e.g. "Meeting" for `Meeting-7a3f1c`. Robust to backend file edits — dumb split, no schema dependency.
5. **No tombstone contract.** Mode deletion stays physical. The id-suffix scheme provides graceful fallback for orphaned transcript references — no GC strategy, no file growth, no naming-conflict tax.
6. **L-14 skip-gaps logic dissolves.** Any name reuse is fine because the suffix guarantees id uniqueness regardless of name collisions.

**Trigger field — decision deferred to unpark.** Brainstorm proposed `.hotkeyTap / .hotkeyHold / .menuBarClick / .pillClick`. May be dropped if no Command Mode use case requires it.

**Rejected approaches (2026-04-30 conversation):**
- `WorkflowMode` soft-delete / tombstone (legacy doc's original direction). File-growth + naming-conflict-on-reuse tax with no payoff once preset family is stored as a field.
- Encoding preset family in the id prefix (e.g. `notes-Meeting-{suffix}`). Field-based lookup on `WorkflowMode.preset` is more resilient — id parsing only used as fallback for orphaned references.
- Denormalising a `modeName` snapshot onto `TranscriptEntry`. Unnecessary once `WorkflowMode.preset` is a field and id encodes the name.

**Backward compatibility — per legacy doc + 2026-04-21 user direction:** existing `transcripts.jsonl` rows can be wiped (dogfood-era data) or backfilled to a sentinel. Pick at impl time.

**Depends on:** #026 (SQLite migration; sequencing decides whether the JSONL change is throwaway or first-schema-in-the-new-store), #021 (Command Mode — first consumer that drives distinct `modeId` values).

**Legacy:** `plans/_legacy/backlog/transcript-trigger-context.md` (2026-04-21 brainstorm; "Mode reference" section's tombstone direction superseded by the 2026-04-30 lock above).

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

### #033 — Streaming output transport decision

`refactor` · `P2` · `done` · `area: output, session`
*Updated 2026-05-02*

Live cursor stream transport for #056's streaming dictation. The live seam is `PipelineOutputSink.deliverPartial(_:)` (`Sources/PersonalScribeSession/Pipeline/Contracts/PipelineOutputSink.swift`); pre-#033 it had no production consumer.

**Decisions locked 2026-05-01** (Claude × Codex debate at [`plans/investigations/2026-05-01-033-transport-debate.md`](./plans/investigations/2026-05-01-033-transport-debate.md)):

| Sub-decision | Choice |
|---|---|
| Transport | clipboard chunk + synthetic `⌘V` |
| Undo grouping | per-EOU |
| Restore policy | save once at session start, restore once at session end (only when sink wrote a chunk) |
| Cursorless target | silent — last-EOU on clipboard, no UI affordance |
| Per-mode gate | paired — gate live partial on `liveCursorEnabled`; suppress stop-time `.frontmostPaste` when on |
| API shape | new `LiveCursorOutput` alongside `ClipboardBatchOutput` |
| Lifecycle hook | extend `PipelineOutputSink` with `endSession()` (default no-op) |

**Commits**
- `2a6e91f` — initial cohesive implementation (transport, paired gate, lifecycle hook, 19 tests).
- `46e2ed8` — Codex review follow-up: snapshot eagerly at session start (anchors locked Q1 wording, not first-chunk timing); `didWriteChunkThisSession` flag so non-streaming sessions don't over-restore; `endSession()` runs **before** `publish(.completed)` / `handleStageFailure` / short-exit publish (closes the ordering hole where menu-bar idle-transition observers could race the snapshot restore); `awaitLiveStreamingEventTaskShutdown` gains graceful-vs-immediate split (stop drains naturally, cancel cancels immediately); `waitForTaskCompletion` replaced with polling-loop + actor tracker (the previous `withTaskGroup` shape had a latent hang — `cancelAll()` doesn't unwind `await task.value` for `Task<Void, Never>`); 5 additional regression tests.
- `80f9bf0` — race + recipe-clear fix from dogfood errors at 2026-05-02 00:22:23.777Z (per `plans/investigations/2026-05-02-033-runtime-bugs-codex.md`). `startRecording()` gains `startRecordingInFlight` re-entry guard (preserves the prepare-before-publish invariant; closes the duplicate-`capture.start()` race that produced the `audioEngineFailure` errors). Catch-time `activeSessionRecipe = nil` removed from both `startRecording` and `startHoldRecording` — root cause of the downstream `runBoundProcessing → invalidState` chain (call B's catch nulled call A's recipe). `LiveCursorOutput.deliverPartial` now logs when `pasteShortcutPoster()` returns `false` (silent live-paint loss path Codex flagged). 1 new race regression test.

**Implementation surfaces:**
- `PipelineOutputSink.endSession()` — default no-op extension; called on success / cancel / error / short-exit / discard. Exists for session-scoped sinks like `LiveCursorOutput`.
- `LiveCursorOutput` (`Sources/PersonalScribeAppKit/Output/LiveCursorOutput.swift`) — captures pre-recording clipboard at `resetForNewSession` (session start); on `deliverPartial` writes the EOU chunk + posts `⌘V` (gated by AX trust + PID externality probe shared with `ClipboardBatchOutput`); on `endSession` restores the snapshot **only when at least one chunk wrote** this session (else discards — preserves user's mid-session clipboard for non-streaming sessions where the orchestrator still calls the sink lifecycle).
- `SessionPipelineOrchestrator.consumeLiveStreamingEvent` — capture-time `outputSink.deliverPartial(_:)` call gated on `bound.streamingBehavior?.liveCursorEnabled` (EOU events only, per #056 DESIGN's append-only contract).
- `RecipeBuilder` — paired Q4 gate filters `.frontmostPaste` from the bound recipe when `liveCursorEnabled == true` (avoids double-paste at session end).
- `SessionCoordinator` — accepts an injected `outputSink:` (falls back to no-op `CoordinatorPipelineOutputSink` for tests).
- `AppComposition` — constructs `LiveCursorOutput` and passes it to `SessionCoordinator`.

**Tests** (24 new across 4 files):
- `SessionPipelineOrchestratorTests`: live cursor delivery on EOU only (exact ordered equality, not `.contains`), suppression when disabled, ignores `.partial` events, `endSession` fires on each of {completed, shortExit, cancel, error}, `endSession` runs before `publish(.completed)`.
- `MenuBarSceneModelTests`: end-to-end ordering — menu-bar `deliverBatch` waits for pipeline `endSession` to complete.
- `RecipeBuilderTests`: `.frontmostPaste` filtered when live cursor on; preserved when off.
- `LiveCursorOutputTests`: writes chunk + posts paste, overwrites prior chunk, skips paste when AX untrusted or focus is in self, ignores blank text, `endSession` restores when chunk wrote, `endSession` discards (preserves mid-session clipboard) when no chunk wrote, `resetForNewSession` captures session-start snapshot before first chunk arrives.

Full suite at close: **1190 tests / 1 skipped / 0 failures** (post-`80f9bf0`).

**Known stale UI to clean up before next dogfood**
- `Sources/PersonalScribeAppKit/UnifiedWindow/Tabs/Modes/ModeDetailView.swift:130` and `Sources/PersonalScribeAppKit/Settings/GeneralTab.swift:341` still ship the caption *"Saved now for streaming recipes. Live cursor transport is not active in this build."* That text was added under #056 when transport was pending #033; now stale. Risk: users won't enable the toggle thinking it's a no-op. One-line removal in each file (or rewrite to reflect actual gating: AX trust + active streaming-ASR model + `liveCursorEnabled`).

**Out of scope (filed if dogfood demands):**
- Cumulative-during-cursorless clipboard (deliberately last-EOU only — second-pass authoritative final at session end is the safety net).
- ResponseCard "click into a text field" notice during cursorless period.
- Hybrid transport (CGEvent for short chunks, paste for long).

**Runtime verification:** in progress 2026-05-02 on the user's other laptop. First dogfood pass surfaced two errors (race + invalidState chain) — fixed in `80f9bf0`. EOU silent-paint inconsistency observed across tests 1-4: per Codex audit the cause is **EOU-only delivery + stop-before-EOU emission** (not a CGEvent paste race — app-side serialization is sound); `.finalized` event at stream-end intentionally doesn't backfill, so short utterances or VAD-pre-empted sessions paste nothing live. Decision pending: ship `.finalized`-backfill (Option B from the debate file) so single-utterance recordings paste at session end, or accept the locked "EOU chunks only" semantics. Reopen ticket if regression observed after rebuild on `80f9bf0`+.

**Legacy:** `backlog/streaming-output-delivery-mechanism.md` + `backlog/pipeline-streaming-defer.md` *(merged — same decision from two layer seats)*

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

### #055 — Full clipboard save/restore (all pasteboard types)

`feature` · `P3` · `parked` · `area: output`
*Updated 2026-04-22*

Extend the Phase 5 Cancel Card Undo path from `.string`-only to all `NSPasteboard` types (RTF, images, file URLs, custom UTIs). Needed when a user dictates into a context where they had non-string clipboard contents and then discards via Cancel Card.

**Legacy:** `plans/_legacy/BACKLOG_pre_migration.md` → "Full clipboard save/restore (all pasteboard types)"

---

### #053 — 7-stage post-processing pipeline

`feature` · `P2` · `parked` · `area: post-processing, memory-learning`
*Updated 2026-04-22*

Extend #045 Stage A's chain-of-stages architecture with named stages that add new transformation behavior: ITN → punctuation → filler removal → personal dictionary → capitalization → disfluency repair → formatter. Each stage is additive output cleanup, not a restructuring of existing logic. ITN (Inverse Text Normalization) subsumes FluidAudio `CustomPronunciation.md` path.

**Depends on:** #045 Stage A (the chain architecture must exist first)
**Legacy:** `plans/_legacy/BACKLOG_pre_migration.md` → "7-stage post-processing pipeline"

---

### #058 — Speaker diarization (LS-EEND, up to 10 speakers)

`feature` · `P3` · `parked` · `phase: 4` · `area: meeting, audio`
*Updated 2026-04-22*

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

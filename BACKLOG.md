# Seshat — Backlog

## Status

**Phase 1 gate met.** Record → transcribe → paste → persist loop is shipped and dogfooded. Transcript history lands in `~/Library/Application Support/Seshat/recordings/transcripts.jsonl`. Phase 2 = unified architecture + visual identity (see `plans/PLAN_PHASES.md` and `plans/seshat_agent_bundle/`).

## Completed Explorations

| Task | Output Files | Key Findings |
|---|---|---|
| Deep-dive mariov96/scribe | `explorations/scribe_claude.md`, `explorations/scribe_codex.md` | Learning/memory patterns, correction tracking via in-app editor |
| Deep-dive open-wispr | `explorations/openwispr_claude.md`, `explorations/openwispr_codex.md` | SPM build structure, menu bar states, Homebrew distribution |
| Deep-dive VoiceInk | `explorations/voiceink_claude.md`, `explorations/voiceink_codex.md` | Uses FluidAudio/Parakeet, Power Mode, mature app patterns |
| Memory/learning feasibility | `explorations/memory_learning_research.md`, `explorations/memory_learning_codex.md` | NLEmbedding sufficient for personal-scale; dictionary + rules handle most "smart" features |

## Phase 1 — closures

Plan at `plans/PLAN_PHASES.md`. All 15 planned steps + 1.14 reconciliation + 1.15 dogfood landed.

| BACKLOG ID | Closure source | Note |
|---|---|---|
| P0 #1 (app unresponsive at launch) | Steps 1.1 + 1.1b + 1.3a | `Task.detached` in `1cb665c`; signposts instrument prepare path (commit `0969f59` round-out). Cold-launch `prepareTranscriber` measured 730-750ms (gate target < 5s). |
| P0 #2 (download hijacks recording pill) | Commit `1cb665c` | Pre-landed by Codex in `Sources/SeshatAppKit/Overlay/PillOverlayViewModel.swift:26-36` (recording state wins). |
| P0 #5 (pill + menu bar clicks dead) | `1cb665c` + Steps 1.3, 1.3b, 1.4b | Pill: `DraggablePanel.mouseDown/mouseUp`. Menu bar: AppStartupCoordinator extraction removed blocking work from `SeshatAppMain.init` — `Task.yield()` theory was wrong; vestigial wrapper removed in Phase 1 round-out. User runtime-verified on dogfood build (~17 session interactions, no misses). |
| P1 #3 (every rebuild re-downloads 400MB) | Commit `1cb665c` | Pre-landed in `Sources/SeshatTranscription/FluidAudioTranscriber.swift:220-251` (only staging dir wiped on failure). |
| P1 #8 (idle pill draggable) | Commit `1cb665c` | Pre-landed — single `DraggablePanel` reused across all visibility states. |
| P1 #4 (idle dot visual) | Deferred → Phase 2 | Bundle v3 mockup prescribes the new visual per `plans/seshat_agent_bundle/01_Foundations/assets/logo_animation_states.png` and `.../PillOverlayWindow/architecture.png` (Mode 1). |
| P1 #9 (recording pill too big) | Deferred → Phase 2 | Mockup prescribes 180×34 per `.../PillOverlayWindow/command_mode_states.png`. |
| P2 #6 (pulsing-dots animation) | Deferred → Phase 2 | Mockup prescribes animated waveform per `.../PillOverlayWindow/recording_states.png` + `logo_animation_states.png` ("Listening"/"Transcribing" tiles). |
| P3 #7 (LSUIElement emergency quit) | Deferred → Phase 3 | No mockup coverage; gated behind Shortcuts tab in `settings_modes.png`. |

## Phase 1 — new infra shipped (beyond BACKLOG closures)

Beyond the bug-list closures above, Phase 1 also landed:

- **`ModelRegistry` + configurable base dir** (steps 1.5 + 1.6 + 1.7). `SESHAT_BASE_DIR` env var and `SeshatBaseDirectoryPath` UserDefaults redirect the entire state tree; `ModelDescriptor` replaces hardcoded `ParakeetArtifact`. Unblocks multi-model / user-visible storage in Phase 3+.
- **Input Monitoring permission detection** (step 1.9). `IOHIDCheckAccess(kIOHIDRequestTypeListenEvent)` in `SeshatCore/PermissionStatus.swift`; `GlobalHotkeyMonitor` logs a contextual warning if `NSEvent.addGlobalMonitorForEvents` returns nil. Backend only — visible UX lands in Phase 2 NSMenu.
- **`TranscriptStore` actor** (step 1.11 + 1.12). JSONL persistence at `<base>/recordings/transcripts.jsonl` + 500-entry in-memory ring. `SessionCoordinator` writes through on every successful transcription. MenuBarSceneModel is NOT a store observer per bundle v3 BUG-06; NotesWindow in Phase 3 will be the read surface.
- **Build info caption** (step 1.13). `Seshat x.y.z · <git-sha>` footer in the menu bar popover. `package-dev-app.sh` writes HEAD SHA into `Info.plist` at package time.

## Phase 1 — dogfood log (2026-04-18)

Build: `0969f59` (Phase 1 round-out). DMG installed to `/Applications/Seshat.app`.

| Observation | Classification | Next step |
|---|---|---|
| Cold-launch `prepareTranscriber` signpost: 730-750ms first run, ~450ms subsequent | Gate #7 pass — under 5s target | Numbers logged in `Tests/SeshatTranscriptionTests/ManualTranscriptionVerification.md` |
| 17 transcriptions in single session, `transcripts.jsonl` line count matches | Gate #2 pass — ≥10 required | — |
| `log stream` shows zero error-level messages during session | Gate #3 pass | — |
| ~17 menu-bar-ish interactions with no click misses reported | Gate #4 pass (implicit) | — |
| Build caption renders `Seshat 0.1.0 · <sha>` in popover footer | — | — |
| Mic permission re-prompted on install to `/Applications` | Expected (TCC ad-hoc path quirk — each install path has its own TCC record) | No fix; documented in memory |
| Accessibility permission prompt fires at **first paste attempt**, not before recording | Friction — interrupts the first usage flow | **Phase 2:** move the Accessibility prompt to first-record (or an onboarding step before the first session). Consistent with Phase 2 NSMenu + onboarding surface. |

## Phase 2 deferred (tracked, not scheduled)

Items already called out in Phase 2 scope:
- New visual identity (theme, logo, waveform) per `plans/seshat_agent_bundle/`.
- NSMenu popover rebuild (visible Input Monitoring + Mic permission states).
- Pill redesign (idle dot, 180×34 recording, animated waveform).
- Onboarding window + early Accessibility permission request.
- Settings window (modes, base directory picker).

## Deferred to Phase 3+ (not forgotten)

- Personal dictionary + prompt injection
- Correction tracking / auto-learning
- Time-saved analytics
- Voice tags, micro-prompts
- VAD auto-stop tuning, configurable timeout
- 7-stage post-processing pipeline
- Smart auto-archive
- Full clipboard save/restore (all pasteboard types)
- Active window context capture
- SQLite note storage via GRDB.swift with FTS5 search (imports from existing JSONL — Phase 3)

## Future (not yet scoped)

- [ ] Landing page / website (before public launch)
- [ ] Homebrew distribution
- [ ] Accessibility audit
- [ ] Data-at-rest encryption (SQLCipher)
- [ ] whisper.cpp integration for non-English
- [ ] LLM assistant features

## Project Files Index

| File | Purpose |
|---|---|
| `PROPOSAL.md` | Direction and architecture (v3, post-engine-switch) |
| `DECISIONS.md` | Decision log + hypotheses + rejected alternatives |
| `COMPETITIVE.md` | Competitive landscape comparison |
| `BACKLOG.md` | This file |
| `REVIEW.md` | Technical architecture review |
| `ASSISTANT_FEASIBILITY_REVIEW.md` | ML feasibility review (Claude) |
| `CODEX_ML_REVIEW.md` | ML feasibility second opinion (Codex) |
| `REVIEW_SYNTHESIS.md` | Consolidated findings from 6 reviewers |
| `explorations/` | Deep-dive outputs (8 files) |

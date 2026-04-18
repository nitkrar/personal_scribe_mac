# Seshat — Backlog

## Status: Ready to Build

Explorations complete. Engine decision made (Parakeet via FluidAudio). Phase 1 scope slashed to 3 weeks.

## Completed Explorations

| Task | Output Files | Key Findings |
|---|---|---|
| Deep-dive mariov96/scribe | `explorations/scribe_claude.md`, `explorations/scribe_codex.md` | Learning/memory patterns, correction tracking via in-app editor |
| Deep-dive open-wispr | `explorations/openwispr_claude.md`, `explorations/openwispr_codex.md` | SPM build structure, menu bar states, Homebrew distribution |
| Deep-dive VoiceInk | `explorations/voiceink_claude.md`, `explorations/voiceink_codex.md` | Uses FluidAudio/Parakeet, Power Mode, mature app patterns |
| Memory/learning feasibility | `explorations/memory_learning_research.md`, `explorations/memory_learning_codex.md` | NLEmbedding sufficient for personal-scale; dictionary + rules handle most "smart" features |

## Current Sprint: Phase 1 (Week 1-3)

Target: **By May 5 2026, using Seshat for daily dictation.**

**Week 1 — Record and transcribe:**
- [ ] SPM project setup
- [ ] FluidAudio/Parakeet integration (pin version)
- [ ] AVAudioEngine capture + 16kHz resampling
- [ ] Basic transcription: record → log to console
- [ ] Menu bar app with record/stop button

**Week 2 — Inject and clean:**
- [x] Global hotkey (double-tap right-option, NSEvent.addGlobalMonitorForEvents) — shipped
- [x] Clipboard paste injection (save string, paste, restore string, Accessibility permission prompt) — shipped
- [x] Post-processing: filler removal + basic punctuation — shipped
- [x] Minimal floating pill overlay (recording + transcribing + downloading states) — shipped but **has open bugs, see Known Issues**

### Week 2 Known Issues (end of 2026-04-18)

| # | Severity | Issue | Proposed fix |
|---|---|---|---|
| 1 | P0 | App unresponsive at launch — prewarm + model download blocks UI | Remove `AppComposition.prewarmTranscription()`, revert to lazy download on first record |
| 2 | P0 | Download progress hijacks recording pill — `.downloading` branch returns early in `PillOverlayViewModel.apply`, never reaches `.recording` | Change priority so active `.recording` / `.transcribing` session state overrides `.downloading`, OR show a combined state |
| 3 | P1 | Every rebuild appears to re-download the 400MB model | `FluidAudioTranscriber.ensureValidDownloadedModel:235` wipes the final model directory on any download failure; only wipe the staging dir |
| 4 | P1 | Idle dot visual doesn't match spec — 10pt circle inside 220x44 panel looks empty | Shrink NSPanel to ~20x20 when `visibility == .idle`, or delete the idle dot and rely on menu bar + hotkey entry points only |
| 5 | P2 | Pill click doesn't toggle (fix in `aa73013` awaiting runtime verification) | Confirm `canBecomeKey = true` fix works after #1–#4 land |
| 6 | P2 | Pulsing-dots listening animation looks "not nice" | Replace with single breathing red circle (Option C — simpler, Wispr-style) |
| 7 | P3 | LSUIElement apps don't appear in Force Quit dialog | Add emergency-quit via triple-tap ⌥ once hotkey customization is in Settings |

### Week 2 next-session starter

Recommended ordering when you resume:
1. Commit a revert of prewarm (fixes P0 #1 + P0 #2 in one shot)
2. Fix model-redownload root cause (P1 #3) — don't destroy final dir on retry
3. Manually verify pill click (P2 #5) and animation (P2 #6) — decide option C vs B
4. Smooth out the idle dot or drop it (P1 #4)

**Week 3 — Save and search:**
- [ ] SQLite note storage via GRDB.swift
- [ ] Simple note list view with FTS5 search
- [ ] Model download on first run + progress indicator
- [ ] Bug fixing, dogfooding, README

## Deferred to Phase 2+ (not forgotten)

- Personal dictionary + prompt injection
- Correction tracking / auto-learning
- Time-saved analytics
- Voice tags, micro-prompts
- VAD auto-stop tuning, configurable timeout
- 7-stage post-processing pipeline
- Smart auto-archive
- Model pre-warming
- Progressive permissions (start simpler)
- Settings window, speed/accuracy slider
- Full clipboard save/restore (all pasteboard types)
- Active window context capture

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

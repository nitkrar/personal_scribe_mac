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
- [ ] Global hotkey (toggle mode, NSEvent.addGlobalMonitorForEvents)
- [ ] Clipboard paste injection (save string, paste, restore string)
- [ ] Post-processing: filler removal + basic punctuation
- [ ] Minimal floating pill overlay (recording indicator)

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

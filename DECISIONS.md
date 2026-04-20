# Ninimma — Decision Log

## Confirmed Decisions

| # | Decision | Choice | Why | Date |
|---|---|---|---|---|
| 1 | App name | Ninimma | Not taken, communicates personal+private+scribe | 2026-04-15 |
| 2 | License | MIT | Max adoption, can relicense while sole author | 2026-04-15 |
| 3 | STT engine | Parakeet-TDT 0.6B v2 via FluidAudio (primary), whisper.cpp fallback for unsupported languages | 1.69% WER, ~80ms latency, ~66MB RAM, Silero VAD built-in, CC-BY-4.0, powers VoiceInk | 2026-04-16 |
| 4 | LLM backend | llama.cpp (primary) + Apple Foundation Models (future upgrade path) | llama.cpp works now on macOS 14+; Apple FM requires macOS 26+ and is unshipped | 2026-04-16 |
| 5 | Intelligence | Tiered: rules → embeddings → LLM | Most features don't need LLM; reviewers confirmed | 2026-04-16 |
| 6 | Default RAM | 16GB (full), 8GB (lite: dictation+notes+NLEmbedding) | Parakeet at 66MB means 8GB gets NLEmbedding (zero-cost) too | 2026-04-16 |
| 7 | Intel support | No | Neural Engine required; Intel too slow for real-time | 2026-04-16 |
| 8 | Target user | Knowledge workers writing in English | Highest volume, most forgiving accuracy | 2026-04-16 |
| 11 | Command vs dictation | Separate hotkeys | Auto-detect from speech will fail and destroy trust | 2026-04-16 |
| 12 | Permissions | Progressive (Mic first, others on demand) | 3 upfront permissions lose ~50% of users | 2026-04-16 |
| 13 | Model bundling | Download on first run (not bundled) | Keeps app small; models downloaded in background | 2026-04-16 |
| 14 | Memory/learning | Dictionary + string ops (no fine-tuning) | Portable, instant, lossless, survives model updates | 2026-04-16 |
| 22 | VAD | Silero-VAD via FluidAudio (bundled) | FluidAudio includes Silero VAD — no separate integration needed | 2026-04-16 |
| 23 | Embedding default | Apple NLEmbedding (Tier 2) | Zero RAM cost, built into macOS, sufficient for personal-scale data | 2026-04-16 |

## Hypotheses to Validate

These are directional choices, not locked decisions. Will validate through dogfooding.

| # | Hypothesis | Current Choice | Validate By |
|---|---|---|---|
| 9 | Toggle mode is better than push-to-talk as default | Toggle + VAD auto-stop | Week 2 dogfooding |
| 10 | Save everything is better than context-aware saving for v0.1 | Save all transcriptions, add context-awareness in v0.2 | Week 3 — does it create a junk drawer? |
| 15 | 2-stage post-processing is sufficient for v0.1 | Filler removal + basic punctuation only | Week 2-3 dogfooding |
| 16 | Simple string clipboard is sufficient for v0.1 | Save/restore string only; full pasteboard types in v0.2 | Week 2 — test across apps |
| 17 | Model pre-warming can wait until v0.2 | Skip for now; Parakeet is fast enough cold? | Week 1 — measure cold start latency |
| 19 | Raw text storage is sufficient (no formatted_text column) | Single text column for v0.1 | Week 3 — do we need correction tracking? |
| 20 | Time-saved analytics is a retention hook | Deferred to v0.3 | After 2 weeks of daily use |
| 21 | Magic byte model validation is necessary | Planned for first-run download | Week 3 implementation |

## Open Questions

| # | Question | Depends On | Status |
|---|---|---|---|
| 1 | FluidAudio API stability and release cadence | GitHub activity, VoiceInk usage | Needs monitoring |
| 2 | Apple FM context window size — 2K or 4K tokens? | Apple docs / macOS 26 beta | Future concern (v0.4+) |
| 3 | Parakeet EOU 120M for true streaming — viable? | FluidAudio roadmap | Future exploration |
| 4 | Homebrew distribution vs DMG-only for v0.1 | open-wispr exploration | Deferred to Phase 4 |

## Rejected Alternatives

| What | Why rejected |
|---|---|
| WhisperKit as STT engine | Parakeet-TDT 0.6B v2 has better WER (1.69% vs ~3%), 3-6x faster, ~66MB vs 500MB-6GB RAM |
| TranscriptionEngine protocol (swap engines) | Different APIs, model formats; adds complexity for no v0.1 payoff |
| Push-to-talk as default | Uncomfortable >30s; excludes long dictation |
| Auto-detect command vs dictation from speech | Small model intent classification will produce trust-destroying false positives |
| 4GB minimum RAM | Fiction; even tiny Whisper + macOS leaves nothing |
| Intel Mac support | No Neural Engine = 5-10x slower; not viable |
| Electron/Tauri | 80-150MB RAM overhead; no native API access |
| GPLv3 license | Limits commercial adoption; MIT matches dependencies |
| Apple FM as primary LLM | Requires macOS 26+ (unshipped); llama.cpp works today |
| EmbeddingGemma as default Tier 2 | NLEmbedding is zero-cost and built into macOS; upgrade only if quality insufficient |
| Ship models bundled with app | Bloats download; models should download on first run |

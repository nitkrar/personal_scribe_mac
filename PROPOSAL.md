# Ninimma — Your Private Voice Brain for Mac

## Vision

A native macOS app that combines local voice dictation, personal note-taking, and an AI assistant that learns from you over time. Everything runs on-device. Nothing leaves your Mac. Free and open source.

**One-liner:** Dictate anywhere, capture everything, ask your notes — 100% local, 100% private.

**Target user:** Knowledge workers who write in English — people composing emails, Slack messages, documents, and notes throughout the day.

**Dogfooding target:** By May 5 2026, using Ninimma for daily dictation.

---

## What Makes This Different?

Existing apps solve one piece of the puzzle. Ninimma brings all three together:

```
┌──────────────────────────────────────────────────────────────┐
│                      Ninimma                         │
│                                                              │
│   ┌─────────────┐   ┌──────────────┐   ┌────────────────┐  │
│   │  DICTATION   │   │    NOTES     │   │   ASSISTANT    │  │
│   │              │   │              │   │                │  │
│   │ Speak → text │   │ Searchable   │   │ "What did I    │  │
│   │ in any app   │   │ saved        │   │  say about X?" │  │
│   │              │   │ transcripts  │   │                │  │
│   │ Filler       │   │ FTS5 search  │   │ Learns your    │  │
│   │ removal,     │   │ Tags, dates  │   │ vocabulary &   │  │
│   │ cleanup      │   │              │   │ patterns       │  │
│   └─────────────┘   └──────────────┘   └────────────────┘  │
│                                                              │
│          All on-device  ·  All private  ·  All free          │
└──────────────────────────────────────────────────────────────┘
```

The competitive landscape (Wispr Flow, Scribe, VoiceInk, open-wispr) is tracked in `COMPETITIVE.md`.

---

## The Three Pillars

### Pillar 1: Dictation (Speak Anywhere)

The foundation — press a key, speak, get clean text in any app. **This must be excellent before anything else matters.**

**v0.1:**
- Toggle mode (tap to start, tap to stop) via global hotkey
- On-device transcription via Parakeet-TDT 0.6B v2 (FluidAudio SDK, CoreML)
- VAD via Silero (bundled in FluidAudio) — auto-stop after silence
- Text cleanup: filler removal + basic punctuation (2-stage, not 7)
- Text insertion via clipboard+paste (save string, paste, restore string)
- Menu bar app with record/stop button
- Floating pill overlay (recording indicator only)

**v0.2:**
- Push-to-talk option (hold key)
- whisper.cpp fallback for non-English languages
- Continuous dictation for long-form capture
- 7-stage post-processing pipeline (hallucination filter, backtrack, numbers, dictionary, grammar)
- Model pre-warming on app launch and wake from sleep
- Audio start/stop sounds

### Pillar 2: Notes (Capture What Matters)

Every transcription is saved. Search later.

**v0.1:**
- SQLite via GRDB.swift — save every transcription automatically
- Simple note list view with FTS5 full-text search
- Quick actions: copy, delete

**v0.2:**
- Context-aware saving (micro-prompt for injections, auto-save for Note Mode)
- Voice tag prefix ("Note: ...") for explicit save intent
- Smart auto-archive (entries under 10 words)
- Export: markdown, plain text
- Active window context capture (app name + window title)

**v0.3:**
- Dedicated "Note Mode" overlay for longer dictations
- Note templates, folder organization
- Audio bookmarks with playback

### Pillar 3: Memory + Assistant (Learn & Help)

A layered intelligence system. Most features use dictionaries, embeddings, and rules — NOT an LLM. The LLM is reserved for genuinely generative tasks.

**v0.2 — Memory (no LLM needed, works on all hardware):**
- Manual personal dictionary (word pairs)
- Correction tracking via in-app editor
- Time-saved analytics (words dictated vs 40 WPM typing baseline)

**v0.3 — Smart Memory (no LLM needed):**
- Auto-learning from corrections (after 3 consistent fixes)
- Embedding-based note search via Apple `NLEmbedding` (zero dependency, built into macOS)
- Cross-note linking via embedding nearest-neighbor

**v0.4 — Assistant (LLM required, 16GB+):**
- Separate assistant hotkey
- Fuzzy voice commands ("summarize today's notes", "find notes about X")
- LLM backend: llama.cpp with Llama 3.2 3B or Phi-3.5 Mini (Q4) — primary
- Apple Foundation Models (macOS 26+) — future upgrade path when available
- Optional "bring your own API key" for cloud LLM

---

## Technical Architecture

```
┌───────────────────────────────────────────────────────────────────┐
│                      Ninimma App                          │
│                    (Native Swift/SwiftUI)                          │
├────────────┬──────────────┬──────────────┬───────────────────────┤
│  UI Layer  │ Audio Layer  │  Injection   │  Intelligence Layer   │
│            │              │  Layer       │  (tiered)             │
│ MenuBarExtra│ AVAudioEngine│ NSPasteboard │                       │
│ NSPanel    │ AVAudioConv. │ + save/      │ ┌─ Tier 1: Rules ──┐ │
│ Note       │ Silero-VAD   │ restore      │ │ Dictionary,       │ │
│ Browser    │ (FluidAudio) │ CGEvent      │ │ string replace,   │ │
│ SwiftUI    │ 16kHz mono   │ Cmd+V paste  │ │ frequency stats   │ │
│            │ PCM buffers  │              │ └───────────────────┘ │
│            │              │              │ ┌─ Tier 2: Embed. ─┐ │
│            │              │              │ │ NLEmbedding       │ │
│            │              │              │ │ (built-in, 0 RAM) │ │
│            │              │              │ │ Semantic search   │ │
│            │              │              │ └───────────────────┘ │
│            │              │              │ ┌─ Tier 3: LLM ───┐ │
│            │              │              │ │ llama.cpp         │ │
│            │              │              │ │ (primary, 3B Q4)  │ │
│            │              │              │ │ Apple FM (future) │ │
│            │              │              │ └───────────────────┘ │
├────────────┴──────────────┴──────────────┴───────────────────────┤
│                    Transcription Engine                            │
│                                                                   │
│  ┌────────────────────────┐  ┌──────────────────────────────────┐ │
│  │ Parakeet-TDT 0.6B v2   │  │  Post-Processing Pipeline       │ │
│  │ (FluidAudio SDK)       │  │                                  │ │
│  │                        │  │  Phase 1 (v0.1):                 │ │
│  │ CoreML + Neural Engine │  │  1. Filler word removal           │ │
│  │ ~66 MB RAM             │  │  2. Basic punctuation             │ │
│  │ ~80ms latency          │  │                                  │ │
│  │ 1.69% WER (LS Clean)  │  │  Phase 2 (v0.2+):               │ │
│  │                        │  │  + Hallucination filtering        │ │
│  │ Silero VAD built-in    │  │  + Backtrack correction           │ │
│  │                        │  │  + Number formatting              │ │
│  │ CC-BY-4.0 license      │  │  + Personal dictionary apply     │ │
│  └────────────────────────┘  │  + NSSpellChecker grammar        │ │
│                               └──────────────────────────────────┘ │
│  ┌────────────────────────┐                                       │
│  │ whisper.cpp (fallback)  │  For non-English languages (v0.2+)  │
│  │ GGML models            │                                       │
│  └────────────────────────┘                                       │
├───────────────────────────────────────────────────────────────────┤
│                       Storage Layer                               │
│                                                                   │
│  ┌──────────────┐ ┌───────────────┐ ┌───────────────────────┐   │
│  │ Notes DB     │ │ Memory Store  │ │ Models                │   │
│  │ (SQLite/GRDB)│ │ (SQLite)      │ │                       │   │
│  │              │ │               │ │ Parakeet CoreML        │   │
│  │ transcripts  │ │ dictionary    │ │ (~66 MB, downloaded)  │   │
│  │ tags         │ │ corrections   │ │                       │   │
│  │ app context  │ │ frequency     │ │ whisper.cpp GGML      │   │
│  │ embeddings   │ │ stats         │ │ (v0.2+, downloaded)   │   │
│  │ FTS5 index   │ │               │ │                       │   │
│  └──────────────┘ └───────────────┘ │ LLM (v0.4+, optional)│   │
│                                      │                       │   │
│                                      │ ~/Library/App         │   │
│                                      │ Support/              │   │
│                                      │ personal_scribe/│   │
│                                      └───────────────────────┘   │
└───────────────────────────────────────────────────────────────────┘
```

### Intelligence Layer Design

**Most "smart" features don't need an LLM.** Build intelligence in layers:

| Tier | What | RAM Cost | Used For |
|---|---|---|---|
| **Tier 1: Rules** | Dictionary, regex, string ops, NSSpellChecker, frequency heuristics | ~0 | Filler removal, corrections, pattern detection, vocabulary |
| **Tier 2: Embeddings** | Apple `NLEmbedding` (built-in, zero download, zero RAM) | ~0 | Semantic note search, cross-note linking, "find similar" |
| **Tier 3: LLM** | llama.cpp Llama 3.2 3B Q4 (primary) / Apple FM (future upgrade) | ~2-3 GB | Summarization, grammar rewriting, style transformation |

Tier 3 is **only loaded on demand** and only available on 16GB+ machines.

### Technology Stack

| Component | Technology | Rationale |
|---|---|---|
| **Language** | Swift 5.9+ | Native macOS, first-class API access |
| **UI Framework** | SwiftUI + AppKit bridging | Modern declarative UI, NSPanel for overlay |
| **STT Engine** | Parakeet-TDT 0.6B v2 via FluidAudio (SPM) | 1.69% WER, ~80ms latency, ~66MB RAM, CoreML, Silero VAD built-in |
| **STT Fallback** | whisper.cpp (v0.2+) | Non-English languages, GGML models |
| **Audio Capture** | AVAudioEngine | Real-time mic access, low latency |
| **Audio Resampling** | AVAudioConverter | Hardware sample rate → 16kHz mono |
| **VAD** | Silero-VAD (built into FluidAudio) | Voice activity detection for toggle mode auto-stop |
| **Global Hotkey** | NSEvent.addGlobalMonitorForEvents | Toggle mode hotkey |
| **Text Injection** | NSPasteboard + CGEvent | Save/restore string + Cmd+V paste |
| **Notes Storage** | SQLite via GRDB.swift | FTS5 full-text search, structured queries, migrations |
| **Embeddings** | Apple NLEmbedding (v0.3) | Zero-dependency semantic search, built into macOS |
| **LLM (v0.4)** | llama.cpp (primary) / Apple Foundation Models (future) | On-device text processing, summarization |
| **Distribution** | Developer ID + Homebrew | Notarized direct download, `brew install` |

### Data Storage

```
~/Library/Application Support/personal_scribe/
├── models/
│   ├── parakeet-tdt-0.6b-v2/            (CoreML, downloaded on first run)
│   ├── whisper-ggml/                     (v0.2+, downloaded on demand)
│   └── llm/                              (v0.4+, optional)
├── personal_scribe.sqlite        (notes + memory, single DB)
│   ├── table: notes                      (text, timestamps)
│   ├── table: dictionary                 (v0.2+, learned words)
│   ├── table: embeddings                 (v0.3+, note vectors)
│   └── FTS5 index on notes.content
└── config.json                           (user preferences)
```

---

## Hardware Tiers

With Parakeet at ~66MB RAM (vs Whisper's 500MB-6GB), 8GB machines get much more capability.

| Tier | RAM | STT Model | Intelligence | Experience |
|---|---|---|---|---|
| **Lite** | 8GB Apple Silicon | Parakeet-TDT 0.6B v2 (~66MB) | Tier 1 + 2 (rules + NLEmbedding) | Dictation + notes + dictionary + semantic search. NLEmbedding is zero-cost. |
| **Default** | 16GB Apple Silicon | Parakeet-TDT 0.6B v2 (~66MB) | Tier 1 + 2 + 3 | Full experience — + LLM text processing |
| **Premium** | 24GB+ Apple Silicon | Parakeet + whisper.cpp large | Tier 1 + 2 + 3 (loaded) | Multi-language + LLM simultaneous |

- **8GB machines:** With Parakeet at 66MB, there's plenty of room for NLEmbedding (zero-cost) and notes. LLM features still deferred to 16GB+.
- **Intel Macs:** Not officially supported. No Neural Engine = no CoreML acceleration.

---

## Known Technical Risks & Mitigations

### Critical

| Risk | Mitigation |
|---|---|
| **Dictation quality must be excellent** — users compare against Apple dictation | 80% of Phase 1 time on transcription + post-processing + injection |
| **Clipboard clobbering** — destroys user's copied content | Save/restore cycle; start simple (string only), expand in v0.2 |

### High

| Risk | Mitigation |
|---|---|
| **Bluetooth/AirPods audio degradation** — HFP mode switching | Preferred microphone setting; test with AirPods, USB mics |
| **FluidAudio API stability** — 1,500 stars, powers 20+ apps including VoiceInk, but check release cadence | Pin exact version; monitor upstream |
| **Post-processing quality bar** — filler removal, punctuation are hard | Start with 2 stages; iterate with dogfooding |

### Medium

| Risk | Mitigation |
|---|---|
| **Small LLM quality** — 3B models produce 60-70% of GPT-4 quality | "AI-generated — please verify" labels; optional BYOK |
| **Code signing/notarization** — first-time complexity | Budget time; ship unsandboxed + notarized |

---

## Development Phases

### Phase 1: Working Dictation (Week 1-3)

**Goal:** By end of week 3, using Ninimma for daily dictation.

**Week 1 — Record and transcribe:**
- [ ] SPM project setup
- [ ] FluidAudio/Parakeet integration (pin version)
- [ ] AVAudioEngine capture + 16kHz resampling
- [ ] Basic transcription: record → log to console
- [ ] Menu bar app with record/stop button

**Week 2 — Inject and clean:**
- [ ] Global hotkey (toggle mode, NSEvent.addGlobalMonitorForEvents)
- [ ] Clipboard paste injection (save string, paste, restore string)
- [ ] Post-processing: filler removal + basic punctuation (2 stages only)
- [ ] Minimal floating pill overlay (recording indicator)

**Week 3 — Save and search:**
- [ ] SQLite note storage via GRDB.swift (save every transcription)
- [ ] Simple note list view with FTS5 search
- [ ] Model download on first run + progress indicator
- [ ] Bug fixing, dogfooding, README

### Phase 2: Polish Dictation + Notes Intelligence (Week 4-6)

- [ ] Push-to-talk option
- [ ] Clipboard save/restore for ALL pasteboard types + UCKeyTranslate + TransientType
- [ ] Full post-processing pipeline (7 stages)
- [ ] Context-aware saving (micro-prompt, voice tags)
- [ ] Active window context capture
- [ ] Audio start/stop sounds
- [ ] Model pre-warming on launch + wake
- [ ] Settings window (hotkey config, behavior toggles)
- [ ] Crash reporting integration

### Phase 3: Memory + Dictionary (Week 7-9)

- [ ] Manual personal dictionary
- [ ] In-app correction UI (feeds back to dictionary)
- [ ] Auto-learning from corrections (3 consistent fixes)
- [ ] NLEmbedding integration for semantic note search
- [ ] Cross-note linking
- [ ] Time-saved analytics
- [ ] Smart auto-archive

### Phase 4: Assistant + LLM (Week 10+)

- [ ] Separate assistant hotkey
- [ ] llama.cpp integration
- [ ] Fuzzy voice commands
- [ ] Note summarization
- [ ] whisper.cpp fallback for non-English
- [ ] Distribution: notarization, Homebrew, landing page
- [ ] Apple Foundation Models integration (when available)

---

## Decisions Made

| # | Decision | Choice | Status |
|---|---|---|---|
| 1 | App Name | Ninimma | Confirmed |
| 2 | License | MIT | Confirmed |
| 3 | STT Engine | Parakeet-TDT 0.6B v2 via FluidAudio; whisper.cpp fallback | Confirmed |
| 4 | LLM backend | llama.cpp (primary) / Apple FM (future upgrade) | Confirmed |
| 5 | Intelligence | Tiered: rules → embeddings → LLM | Confirmed |
| 6 | Default RAM | 16GB full, 8GB lite (dictation + notes + NLEmbedding) | Confirmed |
| 7 | Intel support | No | Confirmed |
| 8 | Target user | Knowledge workers writing in English | Confirmed |
| 9 | Dictation mode | Toggle default + VAD auto-stop | Hypothesis to validate |
| 10 | Note saving | Save everything in v0.1; context-aware later | Hypothesis to validate |
| 11 | Command vs dictation | Separate hotkeys | Confirmed |
| 12 | Permissions | Progressive (Mic first) | Confirmed |
| 13 | Model bundling | Download on first run (not bundled) | Confirmed |
| 14 | Embedding search | Apple NLEmbedding (zero-cost, built-in) | Confirmed |
| 15 | Post-processing | 2 stages v0.1 (filler + punctuation), expand later | Hypothesis to validate |
| 16 | Clipboard handling | Simple string save/restore v0.1, full types v0.2 | Hypothesis to validate |
| 17 | Model pre-warming | Deferred to v0.2 | Hypothesis to validate |
| 18 | Note storage | Save all transcriptions; raw text only for v0.1 | Hypothesis to validate |
| 19 | Analytics | Deferred to v0.3 | Hypothesis to validate |
| 20 | Model validation | Magic byte check after download | Hypothesis to validate |
| 21 | VAD | Silero via FluidAudio (bundled) | Confirmed |

---

## Open-Source References

| Project | What to Study | License |
|---|---|---|
| [VoiceInk](https://github.com/Beingpax/VoiceInk) | Power Mode, uses FluidAudio/Parakeet, mature app | GPLv3 (study only) |
| [FluidAudio](https://github.com/FluidInference/FluidAudio) | Swift SDK for Parakeet, SPM, CoreML, Silero VAD | CC-BY-4.0 |
| [open-wispr](https://github.com/human37/open-wispr) | SPM build, menu bar states, Homebrew distribution | MIT (can adapt) |
| [whisper.cpp](https://github.com/ggerganov/whisper.cpp) | XCFramework, fallback engine for non-English | MIT |

---

## Minimum System Requirements

| Requirement | Value |
|---|---|
| **macOS** | 14.0 Sonoma+ |
| **Processor** | Apple Silicon (M1+) |
| **RAM** | 8GB minimum |
| **Disk** | ~100MB (app + Parakeet model) |

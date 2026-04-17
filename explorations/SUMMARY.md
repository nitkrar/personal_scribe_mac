# Exploration Summary — Key Takeaways for PersonalScribe

Consolidated findings from 4 deep-dives (Claude agents). Codex agent outputs pending in `*_codex.md` files.

---

## 1. mariov96/scribe — Learning System Is Vapor, But Plugin Arch Is Real

**Source:** `scribe_claude.md`

**The learning/memory system is entirely aspirational.** Detailed design docs describe voice profiles, correction tracking, and personalized LLM prompts — but the actual code is regex-based text cleanup (filler removal, "new paragraph" → `\n\n`, number conversion). No NLP pipeline, no fine-tuning, no LLM in transcription path. A Gemini API wrapper exists but isn't wired in.

**What IS well-implemented:**

| Component | How It Works | Adopt? |
|---|---|---|
| **Plugin system** | `BasePlugin` ABC + `CommandDefinition` dataclass with `{placeholder}` templates compiled to regex with named capture groups. `PluginRegistry` handles lifecycle. | Yes — adapt pattern to Swift protocols |
| **Command matching** | Strict regex on templates, not fuzzy/intent. Gap: no fuzzy matching. | Improve with fuzzy matching |
| **Analytics** | Time-saved-vs-typing (40 WPM baseline), productivity multiplier, session JSON persistence | Yes — "time saved" is a retention metric |
| **Window context** | Captures active window (handle, title, app name) before each recording | Yes — essential for context-aware notes |
| **Hold vs toggle** | State machine with recording_mode config | Yes — same pattern needed |
| **Raw vs formatted text** | Keeps both for correction tracking | Yes — needed for dictionary learning |

**Big takeaway:** PersonalScribe has the opportunity to actually implement what Scribe only designed. The learning system architecture in Scribe's docs is a useful design reference, but we'd be the first to ship it working.

---

## 2. open-wispr — Clean Foundation, Some Pitfalls to Avoid

**Source:** `openwispr_claude.md`

**Architecture:** Pure SPM project (no Xcode project), zero external Swift dependencies. Two-target structure: `OpenWisprLib` (testable) + `open-wispr` (CLI executable). whisper.cpp is a **system dependency via Homebrew** — invoked as a subprocess via `Process()`, not linked as a library.

**Patterns to adopt:**

| Pattern | Details | Notes |
|---|---|---|
| **Text injection** | Clipboard save/restore + synthetic Cmd+V | Uses `UCKeyTranslate` for non-QWERTY keyboard layouts — important |
| **Audio capture** | `AVAudioEngine` + `AVAudioConverter` to resample any hardware rate → 16kHz mono | Standard approach, well-implemented |
| **Menu bar states** | 7 states (idle/recording/transcribing/downloading/waiting/copied/error) | All icons drawn programmatically as template images |
| **App bundle wrapper** | `scripts/bundle-app.sh` creates `.app` with Info.plist | Essential for macOS permissions |
| **GGML validation** | Checks magic bytes after model download | Catches proxy error pages posing as model files |
| **FlexBool config** | Accepts `true`, `"yes"`, `1` in JSON config | Nice UX touch |

**Pitfalls to avoid:**

| Issue | Details |
|---|---|
| **Subprocess whisper.cpp** | Shells out via `Process()` — adds latency, loses streaming control. Link directly instead. |
| **0.1s clipboard restore delay** | Too short — race condition with clipboard managers. VoiceInk uses 2s. |
| **30fps menu bar animations** | Wasteful. 10-15fps is sufficient. |
| **No download resumption** | Multi-hundred-MB model downloads can't resume on failure. |
| **No config file watching** | Changes require manual menu reload. |

---

## 3. VoiceInk — The Gold Standard for Patterns (GPLv3, Study Only)

**Source:** `voiceink_claude.md`

The most mature reference. 117 releases, 4,600 stars. **Study patterns only — GPLv3 means no code copying.**

**Critical patterns to learn from:**

| Pattern | Details | Priority |
|---|---|---|
| **10-stage post-processing** | Transcribe → filter hallucinations → trim → format paragraphs → word replace → detect triggers → AI enhance → save → paste → auto-send | HIGH — we need hallucination filtering |
| **Clipboard save/restore** | Preserves ALL pasteboard types (not just strings) + `org.nspasteboard.TransientType` + 2s restore delay (configurable) | HIGH — better than open-wispr |
| **Power Mode** | Priority matching: URL > App > Default. AppleScript-based browser URL detection for 11 browsers. | MEDIUM — v0.2 feature |
| **Dual engine** | `TranscriptionModel` protocol + `ModelProvider` enum + `TranscriptionSession` protocol. Streaming with batch fallback. Audio chunk buffering during prep. | MEDIUM — if we ever add whisper.cpp |
| **Model pre-warming** | Pre-loads model on app launch AND wake from sleep | HIGH — reduces first-dictation latency |
| **NSPanel overlay** | `NSPanel` subclass with `nonActivatingPanel`, `WindowAccessor` NSViewRepresentable for SwiftUI-AppKit bridge | HIGH — needed for our overlay |
| **Hallucination filter** | Filters known Whisper hallucinations from output | HIGH — real problem in production |
| **Media pause/resume** | `MediaRemoteAdapter` pauses music during recording, resumes after | NICE — good UX touch |
| **Screen OCR** | `ScreenCaptureKit` + Vision framework for context | LOW — privacy-sensitive, defer |

**Architecture patterns:**
- `@main struct App` with `@NSApplicationDelegateAdaptor`
- Activation policy switching for dock icon hide/show
- Session state persisted to UserDefaults for crash recovery
- Guard flag to prevent notification loops during programmatic settings changes

---

## 4. Memory/Learning Feasibility — Dictionary Beats ML, Every Time

**Source:** `memory_learning_research.md`

**The single most important finding:** Every shipping dictation app uses the same approach — **dictionary + prompt injection + post-processing replacement + manual UI.** No production app relies on ML-based correction detection or model fine-tuning for personalization.

**Whisper prompt injection works:**
- `initial_prompt` (224 token limit) provides **15-25% relative improvement** for domain terms
- Spelling guides and natural-sentence prompts are most effective
- WhisperKit exposes via `promptTokens: [Int]?` in `DecodingOptions`
- Multi-pass prompting (rough transcribe → LLM builds prompt → re-transcribe) yields best results but doubles latency

**Correction detection — three viable approaches:**

| Approach | Reliability | Complexity | Privacy |
|---|---|---|---|
| **Accessibility API** (`AXValueChanged` observer) | High | High | Invasive — monitors other apps' text fields |
| **In-app editor diff** (Swift `CollectionDifference`) | High | Low | Clean — only monitors our own UI |
| **Clipboard monitoring** | Low | Low | Clean but unreliable |

**Recommendation:** In-app editor diff for v0.1 (user corrects in note browser → auto-learns). Accessibility API for v0.2 if demand exists.

**Embedding options for note search:**

| Model | Size | Speed | Notes |
|---|---|---|---|
| **Apple NLEmbedding** | Built-in (0 download) | Fast | 512-dim word embeddings, sufficient for personal dictionary |
| **all-MiniLM-L6-v2** | 22MB | ~14K sentences/sec | Best quality-to-size ratio |
| **EmbeddingGemma-300M** | ~200MB | 33.5 emb/sec on M1 Max | High quality but slower |

**Recommendation:** Start with Apple's built-in `NLEmbedding` (zero dependency), upgrade to MiniLM if quality insufficient.

**Apple Foundation Models for personalization:**
- LoRA adapters are **impractical** for per-user vocabulary (expensive, version-locked, Apple recommends against)
- Guided generation (`@Generable`) is useful for structured post-processing
- Tool calling enables on-device access to personal dictionary
- Best use: post-transcription cleanup with dictionary injected as context

**Python-to-Swift portability:** Everything translates directly:
- `faster-whisper` → WhisperKit
- `difflib` → `CollectionDifference`
- `sentence_transformers` → `NLEmbedding`
- `sqlite3` → GRDB.swift
- JSON dictionary → SQLite dictionary

---

## Architecture Decisions Confirmed by Explorations

| Decision | Confirmed By | Evidence |
|---|---|---|
| Dictionary-based learning, not ML | memory research | Every shipping app uses this approach |
| Whisper prompt injection for vocabulary | memory research | 15-25% improvement, WhisperKit supports it |
| In-app correction UI for v0.1 | memory research + scribe | Most reliable, least invasive |
| Tiered intelligence (rules → embeddings → LLM) | all explorations | Scribe uses rules only; VoiceInk uses rules + cloud LLM; nobody uses local LLM yet |
| NLEmbedding before external embedding model | memory research | Zero dependency, built into macOS |
| Clipboard save/restore with ALL types + TransientType + 2s delay | VoiceInk + open-wispr | VoiceInk's approach is more robust than open-wispr's |
| Hallucination filtering in post-processing | VoiceInk | Real production problem; needs a filter stage |
| Model pre-warming on launch + wake | VoiceInk | Reduces first-dictation latency |
| Analytics with time-saved metric | scribe | Retention hook; validated pattern |
| Active window context capture | scribe | Needed for context-aware notes |

## New Items for Proposal/Backlog

1. **Add hallucination filtering** to post-processing pipeline (VoiceInk finding)
2. **Add model pre-warming** on app launch and wake from sleep (VoiceInk)
3. **Use `UCKeyTranslate`** for keyboard layout-aware Cmd+V simulation (open-wispr)
4. **Preserve all pasteboard types** in clipboard save/restore, not just strings (VoiceInk)
5. **Use 2-second clipboard restore delay**, configurable (VoiceInk vs open-wispr's 0.1s)
6. **Start with `NLEmbedding`** for semantic search before external models (memory research)
7. **Add time-saved analytics** as retention metric from v0.1 (scribe)
8. **Capture active window context** (app name, title) with each transcription (scribe)
9. **Keep raw + formatted text** in notes DB for correction tracking (scribe)
10. **GGML/CoreML magic byte validation** after model download (open-wispr)

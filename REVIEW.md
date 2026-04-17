# Adversarial Technical Review: Seshat Proposal

**Reviewer role:** Senior Systems Architect
**Date:** 2026-04-15
**Verdict:** The proposal describes an ambitious product with a compelling thesis, but contains several under-examined technical risks ranging from annoying to potentially architecture-breaking. The following review covers each area in detail.

---

## 1. Architecture Risks: The Protocol-Based WhisperKit-to-whisper.cpp Swap

**Risk: HIGH**

The proposal treats the WhisperKit-to-whisper.cpp swap as a simple protocol conformance exercise. This significantly underestimates the API surface differences between the two engines.

### What actually breaks

**Different concurrency models.** WhisperKit is pure Swift async/await. whisper.cpp's Swift bindings (whether via SwiftWhisper, whisper.spm, or a raw XCFramework) use C callback/delegate patterns. Your `TranscriptionEngine` protocol will need to paper over this fundamental difference. If the protocol is defined with `async` methods (which it should be, since WhisperKit requires it), the whisper.cpp backend will need wrapper code to bridge callbacks into Swift structured concurrency. This is doable but adds complexity and potential for subtle bugs around cancellation and error propagation.

**Different model formats.** WhisperKit uses CoreML `.mlmodelc` bundles downloaded from `argmaxinc/whisperkit-coreml` on HuggingFace. whisper.cpp uses GGML `.bin` files. These are completely different model files. Your model download manager, storage paths, and model selection UI all need to be engine-aware. The proposal's data storage diagram shows `ggml-base.en.bin` — this is a whisper.cpp model format, not a WhisperKit model. If you ship with WhisperKit in v0.1, you ship with CoreML models. This is a documentation error that hints at confused thinking about the swap.

**Different output types.** WhisperKit returns `TranscriptionResult` (recently changed from struct to class, breaking value semantics). whisper.cpp returns segments via callbacks with different timestamp formats, token probability structures, and language detection results. Your protocol's return type will be a custom type that both engines must map into, and you will lose engine-specific information in the mapping.

**Different configuration surfaces.** WhisperKit uses `DecodingOptions` with fields like `usePrefillPrompt`, `usePrefillCache`, `temperatureIncrementOnFallback`. whisper.cpp has its own `whisper_full_params` struct with different knobs (`n_threads`, `offset_ms`, `translate`, `no_context`, `single_segment`). Many useful parameters from one engine have no equivalent in the other. Your protocol either exposes the lowest common denominator (losing useful features) or carries engine-specific configuration bags (defeating the point of the abstraction).

**Different compute backends.** WhisperKit runs on the Neural Engine via CoreML, which is significantly more power-efficient for an always-on menu bar app. whisper.cpp runs on CPU + Metal. Swapping engines will change your app's battery and thermal profile. Users who upgrade from v0.1 to v0.2 will notice their laptop running hotter.

**WhisperKit's API is pre-1.0 and unstable.** The API has broken between versions 0.7, 0.8, and 0.9. `TranscriptionResult` changed from struct to class. Argmax recommends exact version pinning. Building a protocol abstraction on top of a shifting API means you'll be chasing upstream changes. This is especially painful because the abstraction is the foundation of your architecture.

### Recommendation

Do not plan for the swap. Pick one engine and commit to it. If you pick WhisperKit, accept that you are coupled to Apple platforms and CoreML. If you pick whisper.cpp, accept the callback-based API and write a Swift async wrapper around it once. The protocol abstraction will either be so thin it adds no value, or so thick it becomes its own maintenance burden.

---

## 2. Performance Concerns

### SQLite FTS5 at 100k entries

**Risk: LOW**

This is actually one of the well-considered choices in the proposal. SQLite FTS5 handles 100k rows with ease — benchmarks show sub-millisecond query times at this scale, orders of magnitude faster than `LIKE '%term%'` scans. FTS5 uses an inverted index with LSM-tree-style segment merging. For a notes database, this is appropriate and will not be a bottleneck.

The real concern at 100k entries is not query speed but database size if you are storing audio references and full transcription text with metadata. At an average of 500 bytes per note, 100k entries is roughly 50MB of text, plus the FTS index (typically 2-3x the text size). This is well within SQLite's comfort zone. Watch for write contention if you are simultaneously writing new transcriptions and running full-text searches from the UI thread, but GRDB.swift's WAL mode handles this cleanly.

### RAM ceiling: Whisper + LLM simultaneously on 8GB

**Risk: CRITICAL**

The proposal lists 4GB minimum RAM and 8GB recommended, then plans to run Whisper and a local LLM simultaneously. Let's do the math:

| Component | Model | Memory |
|---|---|---|
| macOS overhead | — | ~2.5-3 GB |
| whisper.cpp / WhisperKit | base.en | ~400-500 MB |
| llama.cpp | Phi-3 Mini Q4 (3.8B) | ~2.5-3 GB |
| App itself (UI, SQLite, audio buffers) | — | ~100-200 MB |
| **Total** | | **~5.5-6.7 GB** |

On an 8GB machine, this leaves 1.3-2.5 GB of headroom — which sounds workable until you consider:

1. **Other apps are running.** A browser with a few tabs consumes 1-2 GB easily. Slack, another 500MB. The user is dictating *into* something.
2. **Metal/GPU memory sharing.** Apple Silicon's unified memory means GPU workloads (your own and the window compositor's) compete for the same pool. Only ~75% of unified memory is available for GPU tasks by default.
3. **whisper.cpp memory spikes.** whisper.cpp has a known issue where it consumes unusually large amounts of system memory when processing longer audio segments.
4. **LLM context window memory.** The KV cache for even a small LLM grows with context length. A 3.8B model with 4096 context can add hundreds of MB of KV cache on top of the model weights.

If the user runs the "summarize today's notes" command while the system is actively transcribing, both engines must be loaded simultaneously. On an 8GB machine with a browser open, this will cause heavy swap usage, making the LLM response excruciatingly slow and the transcription latency unacceptable.

**The 4GB "minimum" claim is misleading.** Even the tiny Whisper model alone requires ~377MB, plus macOS overhead, plus the app. The user has essentially zero room for anything else. The app would be functionally unusable at 4GB.

### Recommendation

Set minimum at 8GB, recommended at 16GB. Consider lazy-loading the LLM (load on demand, unload after use) rather than keeping it resident. Implement memory pressure monitoring via `os_proc_available_memory()` and degrade gracefully (refuse to load LLM, drop to tiny model).

---

## 3. Audio Pipeline

### AVAudioEngine edge cases

**Risk: HIGH**

The proposal treats audio capture as a solved problem ("AVAudioEngine — Real-time mic access, low latency"). It is not.

**AirPods and Bluetooth microphones.** This is a well-documented, long-standing disaster. When a Bluetooth device's microphone is activated on macOS, the entire audio subsystem switches from A2DP (high-quality stereo output) to HFP (low-quality mono bidirectional). This means:
- The user's music/audio quality drops to telephone-grade while dictating.
- The mic input itself is only 16kHz mono (which is actually what Whisper wants, but the audio quality is worse than the built-in Mac mic).
- Switching back to A2DP after dictation ends is unreliable. Multiple developers report macOS failing to auto-switch back, especially when other apps (Zoom, Discord) are also registered for audio.
- AVAudioEngine provides no API to declare "output-only intent" on macOS, so simply initializing the engine can trigger the HFP switch even if you only want input.

The Mic Drop team (a professional audio app) concluded that the most reliable solution for Bluetooth was to **ignore Bluetooth entirely** and force users to use built-in microphones.

**Mic already in use by Zoom/Teams/FaceTime.** macOS allows multiple processes to access the microphone simultaneously (unlike iOS). However, the behavior is inconsistent:
- Some apps configure exclusive audio sessions.
- Sample rates may conflict — Zoom may set the device to 48kHz while you need 16kHz, and AVAudioConverter has to handle the resampling.
- If the user is on a Zoom call and tries to dictate, they get their Zoom audio mixed into the transcription, or worse, the dictation audio bleeds into the Zoom call.

**Sample rate mismatches.** The proposal mentions "AVAudioConverter — Hardware sample rate -> 16kHz mono" but does not address that the hardware sample rate can change dynamically when devices are plugged in/out or Bluetooth switches profiles. You must observe `AVAudioEngine.configurationChangeNotification` and handle mid-stream reconfiguration, which may require stopping and restarting the engine (dropping audio in the process).

**Race conditions on engine restart.** Stopping AVAudioEngine, detaching nodes, updating the audio session, and restarting triggers what appears to be a race condition in Apple's own framework. Multiple developers report crashes during reconfiguration, especially when toggling voice processing.

### Recommendation

Budget significant time for audio edge cases. Test with: AirPods Pro, AirPods Max, generic Bluetooth headsets, USB microphones, Zoom running simultaneously, and the Mac's built-in mic. Consider offering a "preferred microphone" setting that lets users lock input to a specific device. Add defensive code around engine reconfiguration with retry logic and graceful degradation (show "mic unavailable" rather than crashing).

---

## 4. Text Injection

### Clipboard clobbering

**Risk: HIGH**

The proposal acknowledges "clipboard+paste" as the injection method and calls it "industry standard." It is the industry standard — and it is universally hated by power users. Here are the specific failure modes:

**Clipboard contents destroyed.** The user copies a URL, speaks a dictation, and the URL is gone. The proposal does not mention clipboard save/restore. Even if you implement save/restore (save clipboard contents, write transcription, simulate Cmd+V, restore original contents), there is a race condition window where:
1. You save the clipboard.
2. You write the transcription to the clipboard.
3. Another app (clipboard manager, Paste, Maccy, CopyClip) polls `changeCount`, sees the change, and records the transcription as a new clipboard entry.
4. You simulate Cmd+V.
5. You restore the original clipboard contents.
6. The clipboard manager now has a phantom entry (the transcription) in its history.

Clipboard managers poll `changeCount` because macOS provides no push-based clipboard change notification. The typical polling interval is 0.5-1 second. If your save/write/paste/restore cycle completes within one polling cycle, the manager might miss it. If it doesn't, you've polluted the clipboard history.

**NSPasteboard.org conventions exist** for marking transient data (`org.nspasteboard.TransientType`) and sourcing (`org.nspasteboard.source`), but most clipboard managers don't honor them, and the proposal doesn't mention them.

**Electron apps intercept Cmd+V differently.** Electron apps require explicit `Menu.setApplicationMenu()` configuration to support Cmd+V. Some Electron apps (especially custom internal tools) have broken paste handling. Your CGEvent-simulated Cmd+V may be swallowed silently.

**Terminal emulators.** In Terminal.app, Cmd+V pastes. In iTerm2, Cmd+V pastes. But inside vim/neovim running in a terminal, Cmd+V inserts literal text at the cursor, which in normal mode means executing whatever characters happen to be in the transcription as vim commands. The user must be in insert mode. In tmux, clipboard integration is separately broken and requires `reattach-to-user-namespace` or equivalent workarounds.

**Password managers.** If the user has a password manager (1Password, Bitwarden) that monitors the clipboard, the transcription text will appear in their "recently copied" list and may be flagged as a potential password.

**Rich text destinations.** When you write plain text to NSPasteboard and paste into a rich text editor (Pages, Mail, Notes), the text inherits the destination's formatting at the cursor. This is usually fine. But if the previous clipboard contents were rich text (an image, formatted text from a webpage), your save/restore cycle needs to handle all pasteboard types, not just `NSPasteboardTypeString`.

### Alternative approaches not considered

- **Accessibility API (AXUIElement).** You can use `AXUIElementSetAttributeValue` to set the `AXValue` or `AXSelectedText` attribute of the focused text field directly, bypassing the clipboard entirely. This works for native macOS apps but fails for Electron, web views, and apps that don't properly expose accessibility attributes. It requires the same Accessibility permission you already need for CGEventTap.
- **CGEventKeyDown character injection.** Post individual key events for each character. Slow, but doesn't touch the clipboard. Breaks with input methods, dead keys, and non-ASCII characters.

### Recommendation

Implement clipboard save/restore with `org.nspasteboard.TransientType` marking. Add a setting for injection method (clipboard+paste vs. accessibility API vs. character injection). Document known incompatibilities. Budget time for testing with at least: Safari, Chrome, VS Code, Terminal, iTerm2, Slack, Discord, Microsoft Word, Apple Notes, and Obsidian.

---

## 5. The Memory/Learning System

### "Auto-learn from corrections"

**Risk: HIGH**

The proposal states: "Personal Dictionary — auto-learns from your corrections. You fix 'kubernetes' once, it never misspells it again." and "Correction memory — remembers your preferences ('I always say gonna but mean going to')."

**How do you detect a correction?** The proposal provides no mechanism for this. The fundamental problem: once text is injected via clipboard+paste, you have no connection to the destination text field. You cannot observe what the user does with the text afterward. You don't know if they:
- Edited a word (correction)
- Deleted the entire transcription (rejection)
- Added text before/after (continuation)
- Left the transcription untouched (acceptance)

To detect corrections, you would need to:
1. Monitor the target text field via Accessibility API after injection — which is invasive, unreliable across apps, and a privacy concern.
2. Compare the next transcription with the previous one and infer corrections — which is guesswork.
3. Provide an in-app correction UI where the user explicitly marks corrections — which is the only reliable approach but adds friction.

**The "gonna" -> "going to" example is deceptively hard.** This implies the system is doing speech-to-intent mapping, not just word substitution. "Gonna" is a phonetic artifact — Whisper already handles this in most cases via its language model. If Whisper outputs "gonna", it's because the language model probability favored it. Overriding this with a user dictionary means you're second-guessing the model's output with a simple find-and-replace, which will produce false positives ("I'm gonna use the gonna pattern" becomes "I'm going to use the going to pattern").

**What if the learning system learns wrong patterns?** There is no mention of:
- Undo/rollback for learned corrections
- Confidence thresholds for applying learned patterns
- Conflict resolution when two learned patterns overlap
- A UI for reviewing and managing the learned dictionary
- Decay/expiry for patterns that were learned from a one-time context

**Without a correction detection mechanism, this entire pillar is vaporware.** The proposal should either specify the correction detection approach or defer the learning system to a later phase with an explicit design spike.

### Recommendation

For v0.1, implement only a manual personal dictionary: the user explicitly adds word pairs (misspelled -> correct). Defer "auto-learn from corrections" to a later phase and do a design spike on correction detection first. If you pursue auto-learning, require explicit user confirmation for each learned pattern.

---

## 6. Local LLM Feasibility

### Can Phi-3 or Gemma-2B do useful work?

**Risk: MEDIUM**

The proposal plans to use Phi-3 Mini (3.8B) or Gemma 2B for summarization, text editing commands ("make this more formal"), and note search/Q&A.

**Summarization.** Both models can produce basic extractive and abstractive summaries. Phi-3 is stronger here due to its 128K context window — it can ingest an entire day's notes in one pass. Gemma 2B's 8K context window limits it to roughly 6,000 words per pass, which is insufficient for "summarize today's notes" if the user dictates extensively. However, the quality of either model's summaries is meaningfully worse than GPT-4-class models. Expect serviceable but sometimes incoherent or hallucinated summaries.

**Text editing commands.** "Make this more formal" or "fix grammar" are instruction-following tasks. Phi-3 Mini performs reasonably on these due to its high-quality training data. Gemma 2B often struggles with subtle style transformations. Both will occasionally "improve" text by introducing errors or changing meaning.

**Note search/Q&A.** "What did I say about project X last week?" requires retrieval-augmented generation. The LLM cannot search your SQLite database on its own — you need to run a search query, retrieve relevant notes, inject them into the prompt, and ask the LLM to synthesize an answer. This is an RAG pipeline, which the proposal does not describe. Without RAG infrastructure, the LLM has no access to your notes and cannot answer questions about them.

**"Translate to Spanish."** Small models produce poor translations compared to purpose-built translation models or cloud APIs. This feature will generate user complaints.

### Latency

On Apple Silicon, a 3.8B Q4 model via llama.cpp produces roughly 20-40 tokens/second on M1/M2 and 50-100+ tokens/second on M3/M4. A 200-word summary takes 5-15 seconds to generate. This is acceptable for async operations but too slow for real-time "fix this text" workflows. The user highlights text, speaks "make this more formal", and then waits 10 seconds staring at a spinner. This is a UX problem.

### Recommendation

Be honest with users about quality limitations. Implement RAG for note queries (this is a significant engineering effort that is not budgeted in the timeline). Consider offering an optional cloud LLM integration for users who want higher quality and are willing to trade privacy. At minimum, add a disclaimer that local LLM results may be imperfect.

---

## 7. Missing Technical Concerns

### App Sandboxing

**Risk: HIGH**

The proposal does not mention sandboxing. This is a critical architectural decision.

Seshat requires:
- **Microphone access** (works in sandbox with entitlement)
- **Accessibility permission** for CGEvent posting (requires the app to be in System Settings > Privacy > Accessibility — works outside sandbox, complex inside)
- **Input Monitoring** for CGEventTap (requires System Settings > Privacy > Input Monitoring)
- **File system access** for `~/Library/Application Support/` (works in sandbox with standard entitlement)

CGEventTap and accessibility-based text injection are fundamentally at odds with sandboxing. Most dictation apps ship unsandboxed and notarized. The proposal should explicitly state it will ship unsandboxed and explain why.

If you do sandbox the app, Sparkle auto-update becomes significantly more complex: you need XPC services, mach-lookup entitlements, and careful code signing of Sparkle's helper binaries. Peter Steinberger's detailed 2025 writeup describes this as "solving a puzzle where the pieces keep changing shape."

### Code Signing and Notarization

**Risk: MEDIUM**

The proposal mentions "Developer ID + Homebrew" distribution but does not discuss:
- Hardened Runtime requirements (required for notarization)
- Library Validation interactions with Sparkle
- The notarization pipeline (upload to Apple, wait for approval, staple ticket)
- CI/CD for notarized builds
- The need to re-sign Sparkle's XPC services and helper apps with your Developer ID

This is not a trivial checklist item. First-time macOS developers routinely spend days debugging code signing and notarization issues.

### Crash Reporting

**Risk: MEDIUM**

Not mentioned at all. For an app that runs continuously as a menu bar utility, crash reporting is essential. Options include:
- PLCrashReporter (self-hosted)
- Sentry (cloud, has a generous free tier)
- Apple's built-in crash reports (unreliable for getting user reports)

Without crash reporting, you will have no visibility into real-world failures.

### Migration and Data Integrity

**Risk: MEDIUM**

The proposal uses a single SQLite database for notes, dictionary, patterns, and memory. There is no mention of:
- Database schema migrations when the app updates
- Backup/restore of the database
- Corruption recovery (SQLite is robust but not immune, especially during hard crashes while writing)
- Data export beyond "markdown, plain text" (what about importing?)

GRDB.swift provides migration infrastructure, but you need to plan for it from day one.

### Accessibility (for users with disabilities)

**Risk: LOW**

Ironic for an accessibility-permission-requiring app: the proposal does not mention VoiceOver support, keyboard navigation, or any accessibility features for the app's own UI.

### Intel Support

**Risk: MEDIUM**

The proposal says "Apple Silicon recommended; Intel supported (slower)." However:
- WhisperKit uses CoreML with Neural Engine optimizations that do not exist on Intel Macs.
- llama.cpp without Metal (Intel Macs have AMD GPUs) will be extremely slow for LLM inference.
- The "slower" qualifier is a massive understatement. On Intel, the base Whisper model may take 5-10x longer to transcribe than on Apple Silicon, making real-time dictation impossible.

The proposal should either commit to Intel support and specify the degraded experience, or drop it and set Apple Silicon as a requirement.

### Privacy and Data at Rest

**Risk: LOW**

The proposal emphasizes privacy ("nothing leaves your Mac") but does not mention encryption at rest. The SQLite database in `~/Library/Application Support/` is readable by any process running as the user. If the user dictates sensitive information (passwords, medical details, financial data), it is stored in plaintext. Consider offering FileVault-awareness or SQLCipher encryption.

### Model Download Security

**Risk: MEDIUM**

The proposal plans in-app model downloads but does not mention:
- Checksum verification of downloaded models
- TLS certificate pinning for download sources
- Handling of corrupted or tampered model files
- Download resumption for large files (the large-v3 model is ~3GB)

---

## 8. Dependency Risks

### WhisperKit (argmaxinc/WhisperKit)

**Risk: MEDIUM**

- Pre-1.0 API with breaking changes between minor versions (0.7 -> 0.8 -> 0.9).
- `TranscriptionResult` recently changed from struct to class, breaking value semantics.
- Active development but API instability means you'll need to pin versions and adapt to upstream changes.
- The Pro SDK tier suggests the company may eventually gate advanced features behind a paid license.
- MIT licensed, which is compatible.

### GRDB.swift

**Risk: LOW**

Actively maintained (v7.10.0 released February 2026). Supports Swift 6, expanding to cross-platform. The maintainer (Gwendal Roue) is a single individual — bus factor of 1, but the library is mature enough that forks could sustain it. MIT licensed.

Recent bugfix specifically addressed a crash related to FTS5 and async task cancellation — directly relevant to your use case.

### KeyboardShortcuts (sindresorhus)

**Risk: LOW**

Sindre Sorhus maintains a large portfolio of macOS open-source libraries and has a strong track record. The library is mature and focused. MIT licensed. Low risk of abandonment.

### Sparkle

**Risk: LOW**

Industry standard for macOS auto-update. Actively maintained, well-documented. The complexity is in integration (especially sandboxing), not in the framework itself.

### llama.cpp

**Risk: LOW-MEDIUM**

Extremely active development — so active that the API changes frequently. The C API is relatively stable, but the Swift bindings, build system, and model format have changed multiple times. You'll need to track upstream closely. For v0.3+, this is manageable if you pin to a specific commit/release.

### CGEventTap / NSPasteboard (system frameworks)

**Risk: LOW**

Apple's own frameworks. Stable, but Apple has been tightening security restrictions around CGEventTap and accessibility permissions with each macOS release. A future macOS version could require additional permissions or break existing behavior.

### LaunchAtLogin (sindresorhus)

**Risk: LOW**

Same maintainer as KeyboardShortcuts. Mature, focused, MIT licensed.

---

## Summary Risk Matrix

| Area | Risk Level | Key Issue |
|---|---|---|
| WhisperKit -> whisper.cpp swap | HIGH | Different concurrency models, model formats, output types, and config surfaces make the abstraction leaky and expensive |
| SQLite FTS5 at scale | LOW | FTS5 handles 100k rows with sub-millisecond queries |
| RAM: Whisper + LLM on 8GB | CRITICAL | Math doesn't work with real-world workloads; 4GB minimum is fiction |
| AVAudioEngine + Bluetooth | HIGH | AirPods/BT mic switching is a known OS-level bug with no clean workaround |
| Clipboard-based text injection | HIGH | Clobbers clipboard, race conditions with clipboard managers, breaks in vim/terminal/some Electron apps |
| Auto-learn from corrections | HIGH | No mechanism specified for detecting corrections; entire learning pillar is underspecified |
| Local LLM quality | MEDIUM | Phi-3/Gemma-2B produce serviceable but unreliable results; RAG pipeline for note Q&A is unbudgeted |
| Sandboxing | HIGH | Not mentioned; CGEventTap is incompatible with sandboxing; affects Sparkle integration |
| Code signing / notarization | MEDIUM | Not planned in detail; routinely takes days to debug |
| Crash reporting | MEDIUM | Not mentioned; essential for always-on menu bar app |
| Intel support claim | MEDIUM | Performance on Intel makes real-time dictation infeasible |
| WhisperKit API stability | MEDIUM | Pre-1.0, breaking changes between minor versions |
| 8-week timeline | HIGH | Phases 1-4 in 8 weeks is extremely aggressive for a solo developer dealing with audio edge cases, accessibility permissions, and LLM integration |

---

## Top 3 Recommendations

1. **Kill the engine swap.** Pick WhisperKit or whisper.cpp and commit. The protocol abstraction is not worth the engineering cost for an app at this stage.

2. **Defer the LLM/assistant to a separate release.** Phases 1-2 (dictation + notes) are a complete, useful product. Shipping them in 4-6 weeks is realistic. Adding the LLM assistant doubles the scope and introduces the hardest resource-management problems.

3. **Budget 30% of development time for audio edge cases and text injection compatibility testing.** These are where real users will hit real bugs, and they are under-represented in the timeline.

---

Sources:
- [WhisperKit GitHub Repository](https://github.com/argmaxinc/WhisperKit)
- [WhisperKit API Documentation (DeepWiki)](https://deepwiki.com/argmaxinc/whisperkit)
- [whisper.cpp GitHub Repository](https://github.com/ggml-org/whisper.cpp)
- [WhisperKit vs whisper.cpp Discussion #250](https://github.com/argmaxinc/WhisperKit/discussions/250)
- [AVAudioEngine + AirPods (SuperMegaUltraGroovy)](https://supermegaultragroovy.com/2021/01/28/more-on-avaudioengine-airpods/)
- [How We Fixed the Mic on macOS Monterey (Octopus Think)](https://octopusthink.com/blog/2022-01-26-how-we-fixed-the-mic-on-macos-monterey)
- [llama.cpp Performance on Apple Silicon (Discussion #4167)](https://github.com/ggml-org/llama.cpp/discussions/4167)
- [Local LLMs Apple Silicon Mac 2026 Guide](https://www.sitepoint.com/local-llms-apple-silicon-mac-2026/)
- [whisper.cpp Memory Usage Issue #2310](https://github.com/ggml-org/whisper.cpp/issues/2310)
- [SQLite FTS5 Extension Documentation](https://www.sqlite.org/fts5.html)
- [Gemma 2B vs Phi-3 Mini Comparison](https://medium.com/@linz07m/gemma-2b-vs-phi-3-mini-which-small-llm-should-you-use-6acf9cda06a7)
- [Small Language Models: Enterprise Edge AI 2026](https://www.meta-intelligence.tech/en/insight-slm-enterprise)
- [NSPasteboard.org Conventions](http://nspasteboard.org/)
- [Maccy Clipboard Manager Source](https://github.com/p0deje/Maccy/blob/master/Maccy/Clipboard.swift)
- [Code Signing and Notarization: Sparkle and Tears (Peter Steinberger, 2025)](https://steipete.me/posts/2025/code-signing-and-notarization-sparkle-and-tears)
- [Sparkle Sandboxing Documentation](https://sparkle-project.org/documentation/sandboxing/)
- [GRDB.swift GitHub Repository](https://github.com/groue/GRDB.swift)
- [GRDB.swift Releases](https://github.com/groue/GRDB.swift/releases)
- [Electron Clipboard Issues #1902](https://github.com/electron/electron/issues/1902)

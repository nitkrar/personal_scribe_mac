# Ninimma — Codex ML/On-Device Inference Second Opinion

**Reviewer:** Codex (independent ML feasibility review)
**Date:** 2026-04-16
**Scope:** Second opinion on ML review, focusing on disagreements and blind spots

---

## 1. Memory Reality — Corrections to Existing Review

The existing review's numbers are largely correct but:

- **Slightly pessimistic on Whisper, slightly optimistic on LLM KV cache costs.** KV cache for 3B at 4K context is closer to 400-600 MB (not 200-400 MB). Gemma-2B uses full multi-head attention, making KV cache proportionally larger than Phi-3's grouped-query attention.

- **WhisperKit CoreML memory leak not flagged severely enough.** Memory grows ~2.44 GB to 3.3 GB after 40 minutes with medium model. For an always-on dictation app, this is a showstopper. Needs periodic model reload or switch to whisper.cpp Metal backend.

- **macOS swap behavior is worse than "unusable."** On 8GB, macOS aggressively uses SSD swap rather than killing processes. The app won't crash — it will silently degrade with beachballs and doubled latency. Users blame the app, not their RAM. Must monitor via `os_proc_available_memory()` and refuse to load LLM if headroom insufficient.

- **Unified memory bandwidth contention not accounted for.** CPU, GPU, and Neural Engine share the same memory bus. Running Whisper (memory-bandwidth-bound encoder passes) simultaneously with LLM (memory-bandwidth-bound token generation) creates contention. Real-world simultaneous throughput is 20-40% lower than sum of individual benchmarks.

---

## 2. Apple Foundation Models — Too Optimistic

The existing review is correct that this is the biggest miss, but too optimistic about it as a solution.

**Availability restrictions are severe:**
- Requires Apple Intelligence enabled (user must opt in)
- Requires macOS 26 Tahoe or later
- Requires supported device locale/language
- Any Mac before M1 is out
- Any Mac running macOS 14 (proposal's target minimum) is out

**Safety guardrails are a real problem:**
- Apple's content filtering cannot be disabled
- Medical notes with clinical descriptions, legal depositions with explicit content, fiction with violence, or personal journals with profanity may be refused
- For a "personal scribe that captures and processes everything you say," hitting a safety wall fundamentally contradicts the product promise

**"Model already loaded by OS" claim is speculative.** macOS may or may not keep Foundation Models resident. If user hasn't used Apple Intelligence recently, model likely paged out. Don't design around this assumption.

**Context window is limited.** Early reports suggest 2K-4K tokens for on-device variant. Tight for multi-note RAG. Can fit 2-3 note chunks + system prompt at best.

**Revised position:** Apple FM should be a supported backend, possibly default on supported hardware, but cannot be sole backend. llama.cpp fallback is essential.

---

## 3. Small Model Quality — Where Review Over/Underestimates

**Overestimates:**
- "80-90% of GPT-4 quality on summarization" → On messy dictation transcripts, more like 60-70%. Benchmarks test clean text; dictation output has run-on sentences, topic jumps, and filler artifacts.
- Grammar correction via community fine-tuned Phi-3 → Varies wildly in quality. For dictation apps, "grammar correction" means fixing transcription artifacts (homophones, sentence boundaries), not traditional grammar. Small models are mediocre at homophones ("their/there/they're"). Rule-based heuristics are better for common artifacts; reserve LLM for genuine rewriting.

**Underestimates:**
- RAG quality with small models → Recent 1B instruction-tuned models (Llama 3.2 1B, Qwen 2.5 1.5B) are actually decent at "answer using only this context" with short, focused retrieval. Key: fewer, more relevant chunks + explicit "answer only from context" prompt.
- Translation quality → Qwen 2.5 and Gemma 2 models produce genuinely good translations for common language pairs with informal text. Could be a legitimate differentiating feature.

**Missing:**
- **The 1B-to-3B quality gap is a cliff**, not a slope. Roughly equivalent to 3B-to-7B gap. 3B is where models become genuinely usable. Set 3B as minimum for assistant features, not 1B.
- **Prompt sensitivity** is dramatically higher for small models. The difference between a mediocre and well-engineered prompt on a 3B model can be useless vs genuinely helpful. Budget significant time for prompt engineering per model.

---

## 4. Inference Stack Recommendation

1. **Apple Foundation Models** — Default on macOS 26+ with Apple Intelligence. Zero distribution cost, Neural Engine utilization. Limitations: safety guardrails, limited context, availability.

2. **llama.cpp** — Primary self-hosted fallback. Better Swift integration today than MLX (despite MLX being faster). GGUF is de facto standard for quantized model distribution. More battle-tested for production Mac apps.

3. **MLX** — Consider for v2.0 when Swift bindings mature. 20-87% faster for sub-14B models, but Python-first with experimental Swift support as of mid-2025.

**Note:** If supporting both MLX and llama.cpp, model format fragmentation (MLX format vs GGUF) doubles model management complexity. Pick one for v1.0.

---

## 5. Additional Blind Spots

1. **Model selection UX** — Exposing "tiny/base/small/medium/large" is expert UI. Use speed-vs-accuracy slider with automatic RAM-based selection.

2. **Audio preprocessing** — Noise suppression and echo cancellation before Whisper directly impacts accuracy. AVAudioEngine provides some built-in noise reduction but may not be sufficient. Not discussed in proposal or existing review.

3. **Power/thermal** — Continuous Whisper on a laptop significantly impacts battery. Neural Engine (CoreML) is more power-efficient than GPU (Metal). This favors WhisperKit over whisper.cpp for battery life, despite whisper.cpp's advantages in other areas.

4. **Voice command disambiguation** — "search notes for X" vs dictating that phrase. Needs explicit mode switching (separate hotkey), not auto-detection. Auto-detect with a small model will produce frustrating false positives.

5. **Whisper inference stack choice matters too.** WhisperKit has the memory leak. whisper.cpp Metal doesn't. For a production always-on app, starting with whisper.cpp may avoid a painful migration later, despite easier WhisperKit integration.

---

## Overall Verdict

The app is buildable and useful if the team:
1. Accepts 16GB as the true minimum for assistant features
2. Uses the tiered architecture (rules → embeddings → LLM)
3. Does not over-promise on small model quality
4. Invests heavily in prompt engineering proportional to model quality constraints
5. Monitors memory pressure actively and degrades gracefully on 8GB

# Bug 1 Diagnostic — Parakeet streaming silently produces no EOU events

**Status**: **Investigation-blocked as of 2026-05-19 evening.** Code-level revert of `9d1945b` is shipped (`9eba15e`); Parakeet streaming still produces zero tokens. User locked the working theory: **"Parakeet streaming adapter is broken — not sure how. Not sure if this is integration/orchestrator/workflow change. The only reason it looked working before was second-pass."** FluidAudio dep itself is untouched and previously worked without second-pass on this same machine, so the regression is in OUR code path, not the dependency.
**Filed**: 2026-05-19 by claude-atlas during multi-session work.
**Related**: #056 (streaming dictation), `9d1945b`, `c167155`, `497a4cf`, `9eba15e`, req-0021, req-0022, req-0025, req-0038, req-0039.

---

## 0. How to use this doc

Two sections: **KNOWN** (every claim has a citation — log line, file:line, git commit, prior request) and **UNKNOWN** (questions without evidence). Do not move an item from UNKNOWN to KNOWN without adding a citation. Pivoting hypotheses without evidence is what landed us here.

---

## 1. KNOWN — symptoms reported by user

| # | Statement | Source |
|---|---|---|
| S1 | Parakeet streaming was working at some point earlier today | user (2026-05-19, this session) |
| S2 | Whisper.cpp and WhisperKit changes landed today | git log (`30afc64`, `364851d`, `00c9b4c`, `5a0df9e`) |
| S3 | User tested all 3 adapters; streaming card worked; EOU/live-paste bugs were filed | user + prior session jsonl |
| S4 | Those 3 bugs were code-fixed (commits `30afc64`, `364851d`, `c167155`) | git log + user |
| S5 | NOW manual check shows Parakeet broken — no live stream card, no live cursor paste | user (2026-05-19, this session) |
| S6 | One transcription failed mid-session; others succeeded only as final manual-paste from clipboard | user |
| S7 | User uses same `Streaming Dictation-683efe` mode but swaps the model inside it | user |
| S8 | Identical filenames in earlier screenshot were because user re-transcribed twice, not a multi-click bug | user (correction) |
| S9 | The 5-tap multi-click was caused by missing button-press feedback, not by user spamming | user (correction) |
| S10 | User stated yesterday: "VAD was introduced because FluidAudio's EoU detection is broken and doesn't work" | user, this session |
| S11 | User stated yesterday: "VAD should be required only for EoU paste at live cursor, this shouldn't affect the live stream card" | user, this session |
| S12 | User flagged: `hasEmittedSpeechEnded` was likely added as a post-fix or as part of some bug separately — might have been across multiple commits | user, this session |
| S13 | User said: "for parakeet model the vad solution to identify EoU worked fine if i remember correctly" | user, this session |

---

## 2. KNOWN — log evidence (after instrumentation `4069b6c` shipped today)

### 2a. Session timeline today, ordered

| Time | Mode | Adapter | `streaming_session_started`? | `streaming_eou_emitted`? | `streaming_sink_paste_outcome`? |
|---|---|---|---|---|---|
| 10:02:30 | (logged as error pre-instrumentation; `transcriptionFailure` line 850) | — | n/a | n/a | n/a |
| 10:02:59 | Streaming Dictation | FluidAudio (Parakeet) | (pre-instrumentation; cannot confirm) | **YES** (utterance 1-6) | **YES** (`posted` x4) |
| 10:04:22 | Streaming Dictation | FluidAudio (Parakeet) | (pre-instrumentation) | **YES** (utterance 1-4) | **YES** |
| 14:09:05 | Streaming Dictation | WhisperKit | (pre-instrumentation) | YES (utterance 1-4) | YES |
| 14:10:26 | Streaming Dictation | WhisperCpp | (pre-instrumentation) | YES (utterance 1-3) | YES |
| 14:11:33 | Streaming Dictation | WhisperKit | (pre-instrumentation) | YES (utterance 1-2) | YES |
| 14:12:48 | Streaming Dictation | WhisperKit | (pre-instrumentation) | YES (utterance 1) | YES |
| 14:15:04 | Streaming Dictation | WhisperKit | (pre-instrumentation) | YES (utterance 1-4) | YES |
| 14:17:04 | Streaming Dictation | WhisperCpp | (pre-instrumentation) | YES (utterance 1-3) | YES |
| **App cold start at 14:39:52** | — | — | — | — | — |
| 14:40:17, 14:41:44, 14:47:35, 14:47:49, 14:48:04 | (sessions with no streaming events; pre-instrumentation; cannot confirm adapter or recipe) | — | — | **NO** | **NO** |
| **Instrumentation commit `4069b6c` lands** | — | — | — | — | — |
| 15:49:52 | Dictation (batch) | — | n/a (skipped) | n/a | n/a |
| 15:57:37 | Dictation (batch) | — | skipped: `non_streaming_processor` ✓ | n/a | n/a |
| 15:58:29 | Streaming Dictation | FluidAudio (Parakeet) | **YES** (`FluidAudioStreamingTranscriberAdapter`) | **NO — zero EOUs** | **NO** |
| 16:00:53 | Streaming Dictation | FluidAudio (Parakeet) | **YES** (`FluidAudioStreamingTranscriberAdapter`) | **NO — zero EOUs** | **NO** |
| 16:02:04 | Streaming Dictation 2 (whisper cpp) | WhisperCpp | **YES** (`WhisperCppStreamingTranscriberAdapter`) | **YES** (utterance 1-2) | **YES** |

Source: `$HOME/Library/Application Support/personal_scribe/logs/diagnostics.log` lines 379-550.

### 2b. Recipe-bound details for the BROKEN Parakeet sessions

Log line at 15:58:29:
```
session_started_bound — recipeID=Streaming Dictation-683efe recipeName=Streaming Dictation pipelineShape=streaming processors=[streamingTranscriber] streamingBehavior=liveCard=true,liveCursor=true,secondPass=true,eouSec=0.7 secondPassTranscriber=set holdToRecord=false
```

The recipe is correctly built. All four streaming-behavior flags are true. The streaming branch fires. The FluidAudio adapter is constructed. No `VAD boundary unavailable` log → `vadSession` is non-nil.

### 2c. errors.log

No `FluidAudio` errors at any time during the broken Parakeet sessions (15:58 → 16:01). Only `TranscriptRepository` errors from unrelated bulk-delete work earlier (15:41).

### 2d. Database evidence

`sqlite3 transcripts.sqlite` confirms post-broken-session rows have `mode_id = 'Streaming Dictation-683efe'`, text was produced, audio file persisted. Transcription pipeline completes — it just runs as batch via `ClipboardBatchOutput` (which fires the "paste sink absent or disabled; leaving transcript on clipboard for manual paste" log every time).

---

## 3. KNOWN — code paths (file:line citations)

| # | Statement | Source |
|---|---|---|
| C1 | `FluidAudioStreamingTranscriberAdapter.transcribe(...)` body uses `vadSession.ingest(buffer.samples)` per buffer; emits boundary ONLY on `.speechEnded` | `Sources/PersonalScribeTranscription/Adapters/FluidAudioStreamingTranscriberAdapter.swift:228-237` |
| C2 | Stream-end fallback (`emitBoundaryIfNeeded` after `manager.finish()`) runs **only when `vadSession == nil`** | `FluidAudioStreamingTranscriberAdapter.swift:269-278` |
| C3 | An adapter test asserts the broken behavior: when VAD session exists but never fires `.speechEnded`, zero EOUs emit. Test name: `testStreamEndBeforeAnyBoundaryEmitsOnlyFinalized` | `Tests/PersonalScribeTranscriptionTests/Adapters/FluidAudioStreamingTranscriberAdapterTests.swift:172-199` |
| C4 | WhisperCpp adapter ALWAYS flushes a final boundary at stream end, even when VAD never fires | `Sources/PersonalScribeTranscription/Adapters/WhisperCppStreamingTranscriberAdapter.swift:298-313` |
| C5 | `FluidAudioVadSession.ingest` silently swallows ALL inference errors via `try?` | `Sources/PersonalScribeVAD/FluidAudioVadSession.swift:46` |
| C6 | `FluidAudioVadSession.hasEmittedSpeechEnded` field gates `.speechResumed` emission — first `speechStart` before any `speechEnd` returns nil | `Sources/PersonalScribeVAD/FluidAudioVadSession.swift:23-29, 41-58` |
| C7 | Same VAD factory wires up auto-stop AND boundary use-cases (single shared `FluidAudioVadSession` shape) | `Sources/PersonalScribeAppKit/Composition/AppComposition.swift:176-189` + `Sources/PersonalScribeVAD/FluidAudioVadProvider.swift:184-190` |
| C8 | VAD config passed to boundary path: `VadSegmentationConfig(minSilenceDuration: silenceThresholdSeconds)` (0.7s for our broken sessions) | `Sources/PersonalScribeVAD/FluidAudioVadProvider.swift:185` + bound recipe log |
| C9 | `FluidAudioVadSession.swift` `hasEmittedSpeechEnded` was added in commit `c689560` (2026-04-24) for the #046 VAD auto-stop feature — NOT for boundary EOU | `git log --all -S "hasEmittedSpeechEnded"` returns single commit `c689560` |
| C10 | `9d1945b` (2026-05-19 02:40) added 227+ lines to `FluidAudioStreamingTranscriberAdapter.swift` — switched Parakeet from manager EOU callbacks to VAD-driven boundary detection | `git show --stat 9d1945b` |
| C11 | `c167155` (2026-05-19 11:11) added leading-space-on-subsequent-EOU; text-formatting only. Single function change in adapter | `git show c167155` |
| C12 | Recipe-builder still passes `eouSilenceThresholdSeconds` correctly from mode → recipe → transcriber → VAD config | `Sources/PersonalScribeSession/Pipeline/Orchestrator/SessionPipelineOrchestrator.swift:1394-1403` |

---

## 4. KNOWN — design intent (prior-session evidence)

### 4a. Why VAD was introduced for EoU (req-0022 + req-0025 context)

From req-0022 brief (2026-05-19 ~00:18):

> "FluidAudio `StreamingEouAsrManager.eouDetected` latches `true` after first EOU and only clears in `reset()` (L420). Upstream design is push-to-talk single-EOU-per-session — not a bug from their POV."
> "Replace FluidAudio `StreamingEouAsrManager`'s broken sticky `eouDetected` latch (req-0021 findings) with a VAD-driven approach in `FluidAudioStreamingTranscriberAdapter`."

This aligns with user statement **S10**: VAD was introduced because FluidAudio's EoU detection was broken in a way the upstream team considered "by design."

### 4b. What req-0025 review locked in (pool-codex-1 review of `FOLLOWUP_vad_boundary.md`)

From `plans/056_streaming_dictation/REVIEW_vad_boundary.md` verdict = **Concerns. Would NOT GATE the plan as written.**

Three explicit blockers raised at review time, ALL relevant to today's bug:

1. **Phase A "instrumentation first" is not independently correct** — review §1.1 — but the implementation went ahead anyway.
2. **Adapter-local VAD injection seam was missing on trunk** — `PersonalScribeTranscription` did not depend on `PersonalScribeVAD` — review §1.2.
3. **Callback-to-actor `Task` hop is not ordering-safe** — can emit stale EOU deltas when last partial and `speechEnded` happen in same buffer, or when stream end races the queued task. Review §1.3 recommended a synchronous `NSLock`-protected inbox instead.

The review proposed using an `NSLock`-protected inbox drained immediately after each `await manager.process(...)` returns. Whether the actual implementation in `9d1945b` adopted that pattern OR kept the unsafe `Task { await }` hop is **not yet verified by atlas** — see UNKNOWN U6.

### 4c. Design intent mismatch flagged by user (S11)

User stated this session: "VAD should be required only for EoU paste at live cursor, this shouldn't affect the live stream card."

Current adapter code (C1) gates ALL EOU EVENT EMISSION on VAD `.speechEnded`. Live stream card consumes those same EOU events. So today's implementation does NOT match the user's stated intent — if VAD is silent, both live card AND live cursor get nothing.

**This is a design-implementation mismatch, not just a runtime bug.** Whether the intent was always "VAD gates only cursor delivery" or whether the design drifted during req-0025/implementation is **UNKNOWN** — see U7.

### 4d. Diagnostic gap flagged by req-0021 that was never closed

req-0021 §3 explicitly called out:

> "`LiveCursorOutput` only logs failure/skip paths... To distinguish 'no second EOU emitted' from 'EOU emitted cumulative text' from 'EOU emitted empty text and trimmed away,' the app needs traces at two upstream seams... Adapter bridge trace: log when the FluidAudio EOU callback fires... Orchestrator consumer trace: log receipt of `.endOfUtterance`."

Atlas's `4069b6c` instrumentation added `session_started_*` and `streaming_session_*` logs but did NOT add VAD-internal traces. `FluidAudioVadSession.ingest` still silently swallows errors and never logs per-chunk events (C5).

---

## 5. UNKNOWN — questions without evidence

| # | Question | Why it matters | Discriminator needed |
|---|---|---|---|
| U1 | Is the VAD CoreML model loading successfully at runtime in the broken sessions? | If it's not, every `inference()` call throws → silently swallowed by `try?` (C5) → no events ever | Add error logging to `FluidAudioVadSession.ingest` |
| U2 | Does Silero emit `.speechEnd` events during the broken sessions, or only `.speechStart`? | If only `.speechStart`, the `hasEmittedSpeechEnded` gating (C6) means first `speechStart` returns nil and we never get a `.speechEnded` to propagate | Add per-event logging in `FluidAudioVadSession.ingest` |
| U3 | Why did Parakeet emit EOU events end-to-end at 10:02-10:04 today but not at 15:58-16:00 on the SAME code path? | Differentiator between "static bug" and "environmental/state-dependent bug" | Diff the diagnostics + system state between the two windows |
| U4 | Was the binary running at 10:02-10:04 today the same as the one at 14:09+ vs 15:58+? User rebuilt several times today | If different binaries, "Parakeet worked at 10:02" is not load-bearing evidence | Binary mtime + commit-at-build correlation; or app-version line in logs |
| U5 | Whisper.cpp at 16:02 works because (C4) it always flushes at stream-end. Is that flush mechanism the ONLY difference, or does WhisperCpp ALSO emit mid-session EOUs without VAD? | If WhisperCpp also doesn't use VAD for mid-session boundaries, the architectural delta is bigger than "missing flush" | Read `WhisperCppStreamingTranscriberAdapter` boundary path end-to-end |
| U6 | Did `9d1945b` adopt the `NSLock`-protected inbox pattern that req-0025 review recommended, or did it ship the unsafe `Task { await }` callback hop? | Determines whether ordering races are a real risk in the current code | Read the actual `9d1945b` diff for the partial-callback bridge |
| U7 | Was the original design intent "VAD gates only cursor delivery" (per user S11) or "VAD gates all EOU event emission" (per current code)? Were these always in tension, or did the design drift? | Determines whether the fix is "add stream-end flush" (tactical) or "decouple VAD from EOU event emission" (architectural) | Cross-read req-0022 §4 vs `FOLLOWUP_vad_boundary.md` §4.6 vs current adapter code |
| U8 | Is the StreamCard rendering path itself working when EOU events DO fire? | If StreamCard has its own bug, fixing the VAD path won't make the card appear | Check StreamCard rendering at a session where EOUs did fire (e.g. 14:09 WhisperKit) |
| U9 | The req-0025 review § 1.2 said the adapter-local VAD injection seam was missing on trunk. Was that seam added in `9d1945b`, and does it work correctly? | If wired wrong, VAD instance might not be the same VAD used elsewhere, or might have init quirks | Read `9d1945b`'s wiring of `vadBoundarySessionFactory` end-to-end |

---

## 6. Hypotheses under consideration (NOT verdicts; all need U-evidence to confirm)

### H-A. Tactical: missing stream-end flush
Fix: copy WhisperCpp's pattern — always flush final boundary at stream end regardless of `vadSession` presence. Source: pool-codex-2 (req-0038).
- **Pros**: small change, restores user-visible behavior end-of-session.
- **Cons**: does NOT address WHY mid-session EOUs don't fire. User still won't see mid-session live card / cursor updates. Doesn't fix design-intent mismatch (S11 vs C1).
- **Required to verify**: U1, U2 to determine if VAD is silent due to model load failure OR Silero state machine

### H-B. Architectural: decouple VAD from EOU event emission
Fix: emit EOU events from manager callbacks (as before `9d1945b`); gate ONLY cursor sink delivery on VAD silence.
- **Pros**: matches user intent S11. Live card works always. Cursor delivery still respects user-pause semantics.
- **Cons**: re-introduces the "sticky `eouDetected` latch" problem req-0022 was designed to avoid. Requires either upstream FluidAudio fix OR a different EOU mechanism for the manager callback path.
- **Required to verify**: U2, U7 to determine whether intent was always "decouple" and whether current FluidAudio behavior has changed since req-0021's findings

### H-C. Bug: `hasEmittedSpeechEnded` causes Silero to never emit a useful event in some state
User's hunch S12. The gating logic was added 3 weeks ago for auto-stop, reused for boundary EOU without re-validation.
- **Pros**: would explain why it worked sometimes (when initial `.speechStart` happened after a real `.speechEnd`) and not others (when first speech triggers `.speechStart` only and gating swallows it)
- **Cons**: per (C6), `.speechEnd` ALWAYS returns `.speechEnded` regardless of the gate. The gate only affects `.speechStart`. So this hypothesis doesn't cleanly explain a "zero EOU" symptom unless Silero genuinely never emits `speechEnd`.
- **Required to verify**: U2 (does Silero emit `.speechEnd` at all in broken sessions?)

### H-D. VAD model not loaded
The `try?` swallow at C5 hides all inference failures. If the CoreML VAD model failed to load post-`9d1945b` (could be path issue, signing, anything), every call returns nil → no events forever.
- **Required to verify**: U1

---

## 7. Decision needed from user

Before any code changes:

**Q1**: Confirm or refute the design intent question (U7 / S11): is VAD supposed to gate (a) only cursor delivery, or (b) all EOU event emission?

- If (a): the fix path is H-B (architectural) — backout `9d1945b`'s adapter changes for EOU event emission; keep VAD only at the LiveCursorOutput layer.
- If (b): the fix path is H-A (tactical flush) PLUS investigate U1/U2 to find why VAD is silent.

**Q2**: Should the next code change be (a) a tactical band-aid to ship today's usability (H-A), (b) the architectural fix (H-B), or (c) investigation-first (add VAD logging per U1/U2) before any fix?

Atlas recommends (c): the cheapest correct next step is to log what VAD is actually doing. We're guessing without it. ~10 lines in `FluidAudioVadSession.ingest`.

---

## 8. Pending instrumentation that would close UNKNOWNs

| # | Change | Closes |
|---|---|---|
| I1 | Log every `try? await inference(...)` failure in `FluidAudioVadSession.ingest` instead of silently swallowing | U1 (VAD model load failures) |
| I2 | Log per-chunk event kind (`speechStart` / `speechEnd` / nil) in `FluidAudioVadSession.ingest` at debug or info level | U2 (Silero state machine behavior) |
| I3 | Log binary version + git commit hash at app launch | U4 (binary vs build correlation) |
| I4 | Log adapter bridge events: when `manager.process(...)` returns, what partial callbacks ran | U6 (ordering safety of callback hop) |
| I5 | Add StreamCard rendering logs (currently has zero) | U8 (rendering vs event-source distinction) |

---

## 9. Cross-references

- Prior investigation (req-0021): `plans/investigations/2026-05-19-056-eou-second-utterance-latency-codex.md`
- Adversarial review (req-0022): `plans/investigations/2026-05-19-056-vad-reset-eou-adversarial-codex.md`
- Implementation plan (atlas drafted): `plans/056_streaming_dictation/FOLLOWUP_vad_boundary.md`
- Plan review (req-0025): `plans/056_streaming_dictation/REVIEW_vad_boundary.md` — verdict: **Concerns, would not GATE**
- Today's investigation 1 (round-1, atlas): `plans/investigations/2026-05-19-streaming-regressions-brief.md` + `-pool-codex.md` + `-pool-second.md`
- Today's investigation 2 (round-2, pool-codex-2): req-0038 deliverable (in chat, not yet on disk)

## 10. Process learning from this debugging session

Atlas pivoted hypotheses multiple times based on partial evidence:
1. First diagnosis: `a31cff0` orchestrator wiring broke streaming → refuted (call sites use named args)
2. Second: cold-start order broke streaming → speculation, never verified
3. Third: per pool-codex-2, missing stream-end flush is the bug → tactically true but doesn't address U7 / S11 intent mismatch

The root cause of the debugging-process problem: each hypothesis chained directly into a fix recommendation before the evidence supported it uniquely. Going forward in this bug: every fix proposal must cite which UNKNOWN(s) it depends on, and those UNKNOWNs must be CLOSED (moved to KNOWN with citations) before the fix lands.

---

## 11. UPDATE (2026-05-19 evening) — additional evidence after revert + user verdict

### What shipped after §10
- `497a4cf` — stream-end flush + 5 TEMP-DIAG instrumentation points (VAD inference logs, per-chunk Silero events, app launch, partial-drain trace, StreamCard render logs, per-session summary)
- `9eba15e` — surgical revert of `9d1945b`. FluidAudio adapter back to direct `setPartialCallback`/`setEouCallback` pattern. `VadBoundaryStreamingTranscriber` conformance retained (orchestrator runtime-checks it); `vadBoundarySessionFactory` arg held but never invoked.

### What we learned from the post-revert sessions

| Session | Time | Build | Mode | Adapter | Variant | Result |
|---|---|---|---|---|---|---|
| FB914836 | 16:52 | post-`497a4cf` (with VAD path active) | Streaming Dictation | FluidAudio Parakeet | 160ms | 0 EOUs, 0 partial drains, `finalChars=0` |
| 582529D0 | 16:57 | post-`497a4cf` | Streaming Dictation | FluidAudio Parakeet | 160ms | VAD fired 2 `speechEnd` correctly, but 0 partial drains, 0 EOUs |
| A75EACDB | 17:28 | post-`9eba15e` (revert) | Streaming Dictation | FluidAudio Parakeet | 160ms | 0 EOUs, `finalChars=0` |
| D9375F40 | 17:41 | post-`9eba15e`, secondPass DISABLED | Streaming Dictation | FluidAudio Parakeet | 160ms | 0 EOUs, `finalChars=0`, orchestrator threw `transcriptionFailure` |
| (user-reported) | — | post-`9eba15e` | Streaming Dictation | FluidAudio Parakeet | **320ms** | Same — no tokens |

**WhisperCpp + WhisperKit streaming WORK on this same machine on the same build** (verified at 16:02 and 16:04 sessions: `streaming_eou_emitted` → `streaming_sink_paste_outcome=posted`).

### New KNOWN facts (citations)

| # | Fact | Evidence |
|---|---|---|
| S14 | After `9eba15e` revert, Parakeet still produces zero tokens for streaming | logs A75EACDB / D9375F40 — `finalChars=0`, zero `streaming_eou_emitted_direct` |
| S15 | 320ms variant produces zero tokens too | user verbal report 2026-05-19 evening |
| S16 | When `secondPassEnabled=false`, orchestrator raises `transcriptionFailure` because nothing else recovers the transcript | log D9375F40 at 17:41:24 + `SessionPipelineOrchestrator.swift:891` |
| S17 | When `secondPassEnabled=true`, the **second-pass batch (using `activeASR=whispercpp-small-q5_1`) is what made it "look working" earlier today** | per pool-codex-2 (req-0039): `buildStreamingSecondPassTranscriber` binds to `activeDescriptor(for: .asr)` not the streaming descriptor — `RecipeBuilder.swift:151-160` |

### Hypotheses rescoped

#### CONFIRMED-FALSE (with evidence)
- **H-A (stream-end flush is the bug)**: shipped in `497a4cf` then reverted in `9eba15e`. Didn't help — manager produces nothing to flush.
- **The orchestrator/VAD wiring is the bug**: `9eba15e` reverted the entire VAD path; Parakeet still produces zero tokens. Confirmed bug is upstream of any VAD logic.
- **VAD model load failure (U1)**: closed — VAD model loads and runs inference cleanly when present (session 582529D0 ran 115 chunks with proper probabilities).

#### LIVE (per user's locked verdict S15 + 2026-05-19 evening clarification)

**Premise (locked)**: FluidAudio dep is untouched. Parakeet streaming previously worked on this machine WITHOUT second-pass. The bug is in OUR integration/orchestrator/workflow code.

- **H-E**: Some change in OUR code path between "last known working" and now silently broke the streaming adapter's interaction with FluidAudio. The dep is fine; our wiring isn't. Candidates worth bisecting (NOT speculating into fixes yet):
  - `9d1945b` is reverted but a complete revert needs verifying — the orchestrator branch at `SessionPipelineOrchestrator.swift:1399` (`as? any VadBoundaryStreamingTranscriber`) still routes Parakeet through `transcribe(stream:eouSilenceThresholdSeconds:)` which the revert made delegate to `transcribe(stream:)`. Functionally identical, but worth confirming with a bisect.
  - Earlier orchestrator changes: `b3691cc` (release-idle whispercpp/vad), `b93336d` / `596d39f` (#091 language hint), `2b7cccd` (language hint gate). All since `c83c151` on May 18 evening.
  - `RecipeBuilder.swift` changes related to streaming behavior wiring.
  - `AppComposition` lifecycle changes (e.g. eviction/release helpers added 2026-04-28 in `53736a7`).
  - The `setPartialCallback` lifecycle race that req-0025 review flagged but was never resolved: callback registered then potentially overwritten by `cleanup()` or `reset()` called concurrently from another path.

### What's NOT been done that would advance the investigation

| # | Action | Why useful | Why not done yet |
|---|---|---|---|
| A1 | Patch vendored FluidAudio (`.build/checkouts/FluidAudio/.../StreamingEouAsrManager.swift`) with per-chunk `decodeResult.tokenIds.count` logs | Definitive: tells us if RNNT decode is producing tokens that the callback gate is dropping, vs. decoder producing nothing at all | Modifying dependency checkout (will be wiped by `swift package resolve`) |
| A2 | Build the app at an earlier commit (e.g. `9d1945b^`) and test Parakeet streaming there | Confirms whether Parakeet streaming EVER worked on this machine (independent of memory) | Requires rebuild + reinstall cycle the user explicitly wants to avoid |
| A3 | Bisect across all commits since the last known-working Parakeet streaming session (we have no log evidence of when that was on this machine) | Localizes the regression to a specific commit | Same rebuild cost; depends on knowing what "working" looks like |
| A4 | Re-download the Parakeet 160ms model (delete + restart, let it re-download) | Rules out on-disk corruption | One settings flip + relaunch; quick to try when user is fresh |
| A5 | File upstream FluidAudio issue with our logs + repro steps | Gets the dependency author's eyes on it | Premature without (A1) data showing where in their pipeline it dies |

### Locked working theory (user statement 2026-05-19 evening)

> "Parakeet streaming adapter is broken. Not sure how, not sure if this is some integration/orchestrator/workflow change that caused it to not work. The only reason I was seeing something before was because of second pass."

**Atlas adopts this verdict.** It is consistent with all log evidence collected today. Specifically:
- Second-pass batch transcribes audio successfully via `activeASR=whispercpp-small-q5_1` — that's why `text` lands in the DB
- Live cursor + live stream card both depend on the streaming adapter's partial/EOU callbacks firing — they do not fire
- We cannot point at the specific change in our code that broke it (the most-likely candidates `a31cff0`, `9d1945b`, and `c167155` have all been ruled out or reverted)

### Recommended next steps (in priority order, per user direction)

1. **Stop generating fix hypotheses tonight.** No more code changes without fresh data.
2. **When user returns to this bug**: file as a residual Parakeet-streaming task (separate from #056 Stage A close). Either commission A1 (vendor-patch debug) or A4 (model re-download — cheapest first test).
3. **Cleanup**: remove the `TEMP-DIAG #056-vad-bug` instrumentation only after the actual root cause is identified — they're still load-bearing for the future debug session.

### What's still useful and should NOT be reverted
- All instrumentation shipped in `497a4cf` (`session_started_*`, `streaming_session_*`, `vad_chunk_processed`, `app_launch`, `stream_card_*`, `streaming_session_summary`) — these will be the eyes for the next debug session.
- The `9eba15e` revert itself — code is now in the simpler pre-`9d1945b` shape, easier to diff against future fixes.
- Documentation in this file. The historical trace of pivots is the process-learning artifact.

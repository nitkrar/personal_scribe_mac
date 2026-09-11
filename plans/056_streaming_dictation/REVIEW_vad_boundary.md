# Review — #056 VAD-boundary follow-up plan

## 1. Verdict

**Concerns.** The plan is directionally correct and does preserve the core req-0022 recommendation, but I would **not** GATE it as written.

What is right:

- The core algorithm matches the no-reset recommendation from req-0022: keep `StreamingEouAsrManager` state intact, stop using `eouCallback`, derive utterance deltas from cumulative partials, and leave `finish()` unchanged. Compare `plans/056_streaming_dictation/FOLLOWUP_vad_boundary.md:16-23`, `:71-140` against `plans/investigations/2026-05-19-056-vad-reset-eou-adversarial-codex.md:246-258`.

What blocks approval:

1. **Phase A is not independently correct as written.** It claims a VAD-based `t1` before the plan adds adapter-local VAD, and its `t4` definition overclaims what `LiveCursorOutput.deliverPartial` success means. See `FOLLOWUP_vad_boundary.md:31-49`, `:204-209` versus `Sources/PersonalScribeTranscription/Adapters/FluidAudioStreamingTranscriberAdapter.swift:157-227` and `Sources/PersonalScribeAppKit/Output/LiveCursorOutput.swift:70-107`.
2. **The adapter-local VAD injection seam is missing.** Current trunk does not provide any VAD dependency to `FluidAudioStreamingTranscriberAdapter`, and `PersonalScribeTranscription` does not depend on `PersonalScribeVAD`. See `FOLLOWUP_vad_boundary.md:73-75`, `:139-140`, `:213-215`, `:231-237` versus `Sources/PersonalScribeSession/Models/Selection/ModelBoundProcessorProvider.swift:21-62`, `Sources/PersonalScribeTranscription/Adapters/FluidAudioStreamingTranscriberAdapter.swift:16-37`, and `Package.swift:74-103`.
3. **The proposed callback-to-actor `Task` hop is not ordering-safe.** It can emit stale EOU deltas when the last partial and `speechEnded` happen in the same buffer, or when stream end races the queued task. See `FOLLOWUP_vad_boundary.md:142-156`, `:264-268` versus `Sources/PersonalScribeTranscription/Adapters/FluidAudioStreamingTranscriberAdapter.swift:177-188` and `.build/checkouts/FluidAudio/Sources/FluidAudio/ASR/Parakeet/Streaming/EOU/StreamingEouAsrManager.swift:517-519`.

Non-blocking but real cleanups:

- The proposed LCP fallback example is wrong. `latest="hello word"` and `committed="hello world"` yields `"d"`, not `" word"`. See `FOLLOWUP_vad_boundary.md:184`.
- The proposed §5.2 integration test is already present under another name and does not exercise the adapter bug. See `FOLLOWUP_vad_boundary.md:191-193` versus `Tests/PersonalScribeSessionTests/Pipeline/SessionPipelineOrchestratorTests.swift:602-652`.
- Manual runbooks now live under `Tests/ManualVerifications/`, not inside a test target. See `FOLLOWUP_vad_boundary.md:196`, `:240` versus `Package.swift:126-129`.

## 2. Per-question answers

### 1. Does this faithfully implement the req-0022 §4 recommendation?

**Mostly yes on the algorithm, no on the implementation plan completeness.**

Matches:

- `FOLLOWUP_vad_boundary.md:16-23` and `:71-140` preserve the req-0022 recommendation almost verbatim: adapter-local VAD, cumulative-text caching, delta `.partial` / `.endOfUtterance`, no mid-session `reset()`, and unchanged `finish()`. That is faithful to `2026-05-19-056-vad-reset-eou-adversarial-codex.md:246-258`.

Drift / omissions:

- The plan treats adapter-local VAD as if it were already reachable from the adapter through the “existing `Sources/PersonalScribeVAD/` API” (`FOLLOWUP_vad_boundary.md:73-75`), but current trunk does not pass any VAD dependency into the adapter. `ModelBoundProcessorProvider` constructs `FluidAudioStreamingTranscriberAdapter` with only `descriptor` and `storageLocator` (`Sources/PersonalScribeSession/Models/Selection/ModelBoundProcessorProvider.swift:55-61`), and the adapter init surface matches that (`Sources/PersonalScribeTranscription/Adapters/FluidAudioStreamingTranscriberAdapter.swift:16-37`).
- The current module graph also does not let `PersonalScribeTranscription` import `PersonalScribeVAD` without a package change. `PersonalScribeTranscription` depends on `PersonalScribeCore`, `FluidAudio`, `WhisperKit`, and `WhisperFramework`; `PersonalScribeVAD` is a sibling target, not a dependency. See `Package.swift:74-103`.
- The plan says “Phase A ships independently” (`FOLLOWUP_vad_boundary.md:204-209`), but its metrics definition already assumes adapter-local VAD (`:31-37`). That is an implementation-planning drift from the clean “instrument first” recommendation in req-0022.

### 2. Is the delta derivation correct for current Parakeet streaming RNNT?

**Yes for current trunk as the hot path; no as a blanket claim about arbitrary future RNNT behavior.**

Why strict prefix is valid on the current pinned FluidAudio:

- `StreamingEouAsrManager` only ever **appends** newly decoded token IDs: `accumulatedTokenIds.append(contentsOf: decodeResult.tokenIds)`. See `.build/checkouts/FluidAudio/Sources/FluidAudio/ASR/Parakeet/Streaming/EOU/StreamingEouAsrManager.swift:514-519`.
- `RnntDecoder.decodeWithEOU(...)` returns newly predicted token IDs for the current chunk and never revises previously emitted IDs. See `.build/checkouts/FluidAudio/Sources/FluidAudio/ASR/Parakeet/Streaming/RnntDecoder.swift:63-143`.
- `Tokenizer.decode(ids:)` is pure append-style string construction: concatenate token strings, replace SentencePiece boundary markers with spaces, then trim outer whitespace. It does not rewrite prior interior text. See `.build/checkouts/FluidAudio/Sources/FluidAudio/ASR/Parakeet/Streaming/Tokenizer.swift:19-29`.

So on current trunk, `latest.hasPrefix(committed)` is the expected case.

What that means for the plan:

- `FOLLOWUP_vad_boundary.md:114-127` is right to treat strict prefix as the hot path.
- The LCP branch should be treated as a **diagnostic cold path**, not as a correctness-preserving normal mode. If it fires, current trunk has drifted away from the append-only contract the plan is relying on.
- The test example at `FOLLOWUP_vad_boundary.md:184` is wrong: with `latest="hello word"` and `committed="hello world"`, the longest common prefix is `"hello wor"`, so the delta is `"d"`, not `" word"`.

### 3. Is the actor concurrency pattern in §4.6 safe?

**No.** The proposed `Task { await self?.handlePartial(...) }` hop is not safe enough for boundary correctness.

Current-code reason:

- The adapter drives `manager.process(...)` sequentially in its main loop. See `Sources/PersonalScribeTranscription/Adapters/FluidAudioStreamingTranscriberAdapter.swift:177-188`.
- The manager invokes `partialCallback` synchronously during decoding before `process(...)` returns. See `.build/checkouts/FluidAudio/Sources/FluidAudio/ASR/Parakeet/Streaming/EOU/StreamingEouAsrManager.swift:517-519`.
- The plan’s recommended bridge is an unstructured task hop back to the adapter actor. See `FOLLOWUP_vad_boundary.md:146-156`.

Failure mode:

1. `manager.process(...)` decodes a new cumulative partial and synchronously calls the callback.
2. The callback schedules `Task { await self.handlePartial(...) }`.
3. `manager.process(...)` returns to the adapter loop before that task necessarily runs.
4. The adapter then ingests the same PCM buffer into VAD and sees `.speechEnded`, or reaches stream end and calls `finish()`.
5. Boundary emission reads stale `latestCumulative`.

That is not repaired by the plan’s “later larger text wins” argument at `FOLLOWUP_vad_boundary.md:264-268`, because the wrong `.endOfUtterance` may already have been emitted by the time the larger text arrives.

**Cleaner alternative:** use a tiny ordered callback inbox, not a task hop.

- The callback type is synchronous `@Sendable (String) -> Void`. See `.build/checkouts/FluidAudio/Sources/FluidAudio/ASR/Parakeet/Streaming/EOU/StreamingEouAsrManager.swift:155-159`.
- The codebase already uses `NSLock` in small shared-state bridges. See `Sources/PersonalScribeSession/Models/Selection/ModelBoundProcessorProvider.swift:9` and `Sources/PersonalScribeTranscription/Adapters/WhisperCppTranscriberAdapter.swift:463`.
- Recommended pattern: the callback appends partial texts into an `NSLock`-protected queue; the adapter actor drains that queue **immediately after each** `await manager.process(...)` returns, updates `latestCumulative`, emits derived `.partial` revisions in order, and only then evaluates the VAD event for that buffer. Drain once more before `finish()`.

That keeps all ordering decisions inside one explicit serial loop and avoids unstructured task races.

### 4. Is instrumentation step zero sufficient to localize the 5-6s latency?

**No as written.**

Gap 1: `t1` is defined in terms of adapter-local VAD before the plan adds adapter-local VAD.

- The plan defines `t1` as VAD `.speechEnded` and `t0` as VAD `.speechResumed` / first partial proxy. See `FOLLOWUP_vad_boundary.md:31-43`.
- But current adapter code has no VAD seam at all. See `Sources/PersonalScribeTranscription/Adapters/FluidAudioStreamingTranscriberAdapter.swift:157-227`.
- The repo’s existing VAD is wired at the capture/orchestrator layer, not into the streaming adapter. See `Sources/PersonalScribeSession/Pipeline/Orchestrator/SessionPipelineOrchestrator.swift:980-1001`.

Gap 2: `t4` is misdefined.

- The plan says `t4` is “`LiveCursorOutput.deliverPartial` returns successfully (post `⌘V` post)” at `FOLLOWUP_vad_boundary.md:35-36`.
- Current `deliverPartial` returns in **all** of these cases:
  - clipboard write succeeded but AX trust is false (`Sources/PersonalScribeAppKit/Output/LiveCursorOutput.swift:88-91`);
  - clipboard write succeeded but focus is in self (`:94-97`);
  - clipboard write succeeded but `pasteShortcutPoster()` failed (`:104-106`).
- So “function returned” does **not** mean paste posted, and definitely does not mean paste landed in the target app.

What I recommend instead:

- Keep Phase A independent, but narrow it to the slice current trunk can actually measure:
  - current EOU event emitted by the adapter,
  - orchestrator receives `.endOfUtterance`,
  - sink writes clipboard,
  - sink skip / paste-post attempt / paste-post failure outcome.
- Carry a `session` UUID, `utterance` counter, and monotonic `ms_since_session_start` on every line. Utterance-relative times alone are not enough to correlate cross-component logs.
- Add true speech-end timing only in Phase B, once the adapter actually has a VAD boundary seam.

That preserves the “instrument first” baseline without pretending Phase A can already measure speech-end latency.

### 5. Are the proposed tests enough?

**No.** The proposed test surface is close, but it misses the highest-risk seam and duplicates one test that already exists.

What is already covered today:

- The orchestrator already has `testStreamingLiveCursorDeliversEachEouChunkToOutputSink`, which drives two `.endOfUtterance` events and asserts two cursor deliveries. See `Tests/PersonalScribeSessionTests/Pipeline/SessionPipelineOrchestratorTests.swift:602-652`.

Why the plan’s §5.2 test is insufficient:

- `FOLLOWUP_vad_boundary.md:191-193` proposes essentially the same orchestrator test again.
- That test does **not** exercise the actual bug, because the bug is in the adapter producing multiple `.endOfUtterance` events from cumulative partials. A stubbed adapter that already emits the right two EOU events bypasses the seam that broke.

What is still missing:

1. **Ordering test**: same-buffer partial plus `speechEnded`.
   - Assert that when the final cumulative partial and the VAD boundary happen off the same input buffer, the emitted `.endOfUtterance` uses the newest cumulative text, not the previous one.
2. **Stop-before-boundary test**:
   - Stream ends after partial growth but before any VAD `speechEnded`. Assert no spurious `.endOfUtterance`, and `finish()` still yields the full cumulative final.
3. **VAD-unavailable policy test**:
   - If the injected boundary-session factory returns `nil`, assert the chosen policy explicitly. Do not let this become silent undefined behavior.
4. **Cold-path test correction**:
   - Fix the LCP example at `FOLLOWUP_vad_boundary.md:184`.

The proposed adapter tests in `FOLLOWUP_vad_boundary.md:178-186` are the right place to add 1-3.

### 6. Is Phase A genuinely shippable independently?

**Not as written.** With a small rewrite, yes.

As written, it depends implicitly on Phase B because:

- its `t1`/`t0` definitions require adapter-local VAD (`FOLLOWUP_vad_boundary.md:31-37`);
- its `t4` definition is inaccurate against current `LiveCursorOutput` behavior (`:35-36`, `:49` versus `Sources/PersonalScribeAppKit/Output/LiveCursorOutput.swift:82-106`).

**Cleaner revision:** keep Phase A, but redefine it as “current downstream live-cursor slice instrumentation” rather than “full speech-end-to-paste latency.”

That means:

- Phase A logs current-EOU emit -> orchestrator receive -> clipboard/paste outcome.
- Phase B adds true speech-end markers once adapter-local VAD exists.

I prefer that over merging Phase A into Phase B, because you still get a baseline on today’s broken behavior before changing the mechanism.

### 7. The five open questions in §10

Answered in §4 below. Short version:

- `800ms` is the better starting default.
- Yes, log every LCP cold-path firing.
- Include session/utterance correlation IDs and monotonic time; raw buffer count is optional.
- Do not add a long-lived mechanism flag.
- What is still missing is the injection seam, the ordered callback bridge, the corrected Phase A semantics, and an explicit VAD-unavailable policy.

## 3. Specific changes requested

1. **Rewrite §3 / Phase A so it is independently true.**
   - `FOLLOWUP_vad_boundary.md:31-49` and `:204-209` should stop claiming VAD-based speech-end timing before the adapter has a VAD seam.
   - Split sink outcome logging into at least:
     - clipboard write done,
     - AX/self-focus skip,
     - paste poster success/failure.
   - Session/utterance IDs plus monotonic `ms_since_session_start` should be part of every line.

2. **Add an explicit adapter-local VAD injection design.**
   - The current plan says “use existing `Sources/PersonalScribeVAD/` API” (`FOLLOWUP_vad_boundary.md:73-75`) but does not explain how that dependency reaches the adapter.
   - Recommended shape: **closure-based factory injection**, passed through `ModelBoundProcessorProvider` into `FluidAudioStreamingTranscriberAdapter`, instead of making `PersonalScribeTranscription` take a hard dependency on `PersonalScribeVAD`.
   - Why: current module boundaries are `PersonalScribeTranscription` without `PersonalScribeVAD` (`Package.swift:74-103`), while app/session composition already owns the VAD provider (`Sources/PersonalScribeAppKit/Composition/AppComposition.swift:86-97`).

3. **Replace the `Task`-hop callback bridge in §4.6 / §8.3.**
   - `FOLLOWUP_vad_boundary.md:146-156` and `:264-268` should be revised to an **ordered inbox** model:
     - synchronous callback appends to an `NSLock`-protected queue,
     - adapter drains that queue immediately after each `await manager.process(...)`,
     - adapter evaluates VAD only after draining,
     - adapter drains once more before `finish()`.
   - Add the same-buffer ordering test to §5.1.

4. **Fix the test/doc cleanup items in §5 / §7.**
   - Replace the duplicate orchestrator test at `FOLLOWUP_vad_boundary.md:191-193` with adapter-focused tests.
   - Fix the LCP example at `:184`.
   - Move the manual runbook path from `Tests/PersonalScribeAppKitTests/ManualStreamingVerification.md` (`:196`, `:240`) to `Tests/ManualVerifications/ManualStreamingVerification.md` or another runbook under the existing `Tests/ManualVerifications/` folder (`Package.swift:126-129`).
   - Add an explicit VAD-unavailable policy test if the design uses injected VAD sessions that can be absent.

## 4. Answers to the five open questions

### 1. `800ms` default or more conservative?

**Use `800ms` as the starting default.**

Reasoning:

- FluidAudio VAD already works in `4096`-sample chunks, which is `256ms` at 16 kHz. See `.build/checkouts/FluidAudio/Sources/FluidAudio/VAD/VadManager.swift:21-26`.
- `speechEnd` fires only after `minSilenceDuration` worth of samples have elapsed. See `.build/checkouts/FluidAudio/Sources/FluidAudio/VAD/VadManager+Streaming.swift:51-90`.
- So `1000-1200ms` would put the effective boundary floor back near or above the current `1280ms` EOU debounce the plan is trying to beat. See `.build/checkouts/FluidAudio/Sources/FluidAudio/ASR/Parakeet/Streaming/EOU/StreamingEouAsrManager.swift:200-202`, `:537-543`.

Recommendation:

- Start at `800ms`.
- Keep it configurable.
- Revisit only after instrumentation lands.

### 2. Should the LCP cold path emit a diagnostic log?

**Yes.**

On current trunk, LCP fallback should be effectively impossible unless the underlying append-only contract changed. So every cold-path hit is high-signal.

Recommendation:

- Log `delta_strategy=lcp_fallback`.
- Include `session`, `utterance`, `latest_char_count`, `committed_char_count`, and perhaps `lcp_char_count`.
- Do **not** log transcript text itself.

### 3. Should Phase A log session-start buffer count / timestamp, or is utterance-relative timing enough?

**Utterance-relative timing alone is not enough.**

Use:

- `session=<uuid>`
- `utterance=<n>`
- `ms_since_session_start=<monotonic>`

That is sufficient to correlate adapter, orchestrator, and sink lines without depending on raw buffer counts. Buffer count is optional; I would not make it the primary join key.

### 4. Should Phase B ship behind a `StreamingEouMechanism` flag?

**No long-lived product flag.**

Reasoning:

- The legacy mechanism is known-broken for multi-utterance streaming.
- Carrying two live mechanisms doubles the seam and the test surface for a bug fix that already has a clear preferred direction.

If the team wants comparison data:

- do it via instrumentation plus a short-lived debug/test seam,
- not via a persisted runtime `legacy`/`vadBoundary` user-facing mechanism toggle.

### 5. Anything missing from req-0022 that should be in the plan?

**Yes. Four things:**

1. The **adapter-local VAD injection path**.
2. The **ordering-safe callback bridge**.
3. The **corrected Phase A instrumentation scope** and sink outcome semantics.
4. An explicit **VAD-unavailable policy** if the chosen injection path can return no boundary session.

On that last point, current app composition can legally have no VAD provider if the bundled model fails to load. See `Sources/PersonalScribeAppKit/Composition/AppComposition.swift:81-97`. If the revised plan relies on an injected provider/session factory, it needs to say what the adapter does when that factory returns `nil`.

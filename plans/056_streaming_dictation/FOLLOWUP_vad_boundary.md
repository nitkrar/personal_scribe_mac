# #056 follow-up — VAD-boundary EOU without `manager.reset()`

**Status:** rev 5, in implementation (added: surface EOU silence threshold as a global setting in Settings → General, shared across adapters).
**Supersedes:** rev 1 (deleted instrumentation Phase A; pivoted to closure-injection for VAD; replaced Task-hop callback with ordered inbox; fixed test set + LCP example + runbook path).
**Source authority:** req-0021 + req-0022 + req-0025 (review). Where this plan disagrees with those docs, this plan wins.

## 1. Problem recap

Two bugs in #056 streaming dictation surfaced from dogfood:

- **Bug 1.** Second utterance per session does not paste at cursor. Root cause: `StreamingEouAsrManager.eouDetected` is a session-scoped sticky latch; once set, it is only cleared by `reset()`, so the manager's `eouCallback` fires once per session and never again.
- **Bug 2.** Perceived 5-6s latency between user stopping speech and paste landing. Cause stack not yet measured. Static-analysis floor: `eouDebounceMs = 1280ms` plus VAD chunk quantization. Does not explain a full 5s.

## 2. Approach

Bypass the broken `eouCallback`. Use VAD's `.speechEnded` event as the utterance boundary signal. Derive per-utterance text deltas from the manager's cumulative partial transcript inside the adapter. Never call `manager.reset()` mid-session.

Why no-reset: req-0022 refuted the reset-based variant on three integration costs (mid-process reentrancy, terminal `finish()` truncation, RNNT decoder state loss). The no-reset variant keeps `manager.finish()` correct (full-session text), preserves RNNT continuity, avoids reentrancy. Cost is moved into the adapter: it caches cumulative text and emits deltas.

## 3. Adapter changes

### 3.1 New responsibilities

- Take an injected closure-based VAD session factory (see §3.2).
- Fan out the incoming PCM buffer stream to both the FluidAudio manager AND the VAD session.
- Cache two strings on the adapter actor:
  - `latestCumulative: String` — manager's cumulative session-wide text, updated from `setPartialCallback`.
  - `lastCommittedBoundary: String` — cumulative text snapshot at the last utterance boundary commit.
- Map `.partial` / `.endOfUtterance` events from cached state, not from the broken `eouCallback`.

### 3.2 VAD injection — closure-based factory

The adapter does NOT import `PersonalScribeVAD`. Instead, its initializer takes an
**async** closure-based factory:

```swift
public typealias VadBoundarySessionFactory =
    @Sendable (_ silenceThresholdSeconds: Double) async -> VadSessionHandle?
```

`VadSessionHandle` already exists in `Sources/PersonalScribeVAD/VadMonitoring.swift`. The adapter consumes `VadSessionHandle` through a re-exported type alias in `PersonalScribeCore` (or as a fully erased closure — see §10 question 1) so the adapter module's import graph is unchanged.

Why async: current trunk's only public seam is `VadProviding.makeSession(...) async -> VadSessionHandle?`
in `Sources/PersonalScribeVAD/VadMonitoring.swift`. A synchronous factory would require an
artificial blocking bridge or a detached task just to mint the session handle, neither of which is
acceptable on this path.

**Wiring**:
- `ModelBoundProcessorProvider` accepts an injected factory and passes it to `FluidAudioStreamingTranscriberAdapter.init`.
- `AppComposition` constructs the factory by capturing the existing VAD provider.
- Tests inject an async fake factory that returns a scripted `VadSessionHandle`.

**Why closure injection** (per req-0025 §3): keeps `PersonalScribeTranscription` independent of `PersonalScribeVAD`. Composition root already owns the VAD provider — natural place to extend.

**VAD-unavailable policy** (per req-0025 §4 Q5): if `await factory(...)` returns `nil`, the adapter
logs a single warning at session start and falls back to **no-VAD mode** — emit
`.endOfUtterance` only at stream end (effectively the old broken behavior, but at least the final
text reaches the cursor). Bug 1 stays broken for that session; logged loudly so the user can see
why.

### 3.3 Event flow

**On `manager.setPartialCallback(text)` synchronous call**: append text into a thread-safe ordered inbox (see §3.5).

**Adapter loop, after each `await manager.process(buffer)` returns**:
1. Drain the partial-text inbox. For each entry in order:
   - Update `latestCumulative = entry`.
   - Compute `delta = derivedDelta(latest: latestCumulative, committed: lastCommittedBoundary)`.
   - If non-empty, yield `.partial(text: delta)`.
2. Feed the same buffer into VAD: `let vadEvent = await vadSession.ingest(buffer.samples)`.
3. If `vadEvent == .speechEnded`:
   - Compute `delta = derivedDelta(latest: latestCumulative, committed: lastCommittedBoundary)`.
   - If non-empty, yield `.endOfUtterance(text: delta)` and set `lastCommittedBoundary = latestCumulative`.

**On stream end** (existing flow, unchanged):
- Drain inbox one final time.
- `finalText = await manager.finish()` — returns full-session cumulative text.
- Yield `.finalized(TranscriptionResult(text: finalText, ...))`.

This pattern is **ordered by construction** because the inbox drain happens inline between `process()` and VAD ingest. There is no `Task` hop, no race between a queued callback and a VAD decision.

### 3.4 Delta derivation

```swift
private func derivedDelta(latest: String, committed: String) -> String {
    if latest.hasPrefix(committed) {
        return String(latest.dropFirst(committed.count))
    }
    // Cold path: the manager's cumulative text is not an extension of
    // the prior committed boundary. On current trunk this should be
    // unreachable (Parakeet RNNT is token-append-only + tokenizer is
    // pure concatenation). Log and fall back to longest common prefix.
    let lcp = longestCommonPrefix(latest, committed)
    logger.warning("LiveCursor delta cold-path: lcp_fallback session=\(sessionID) utterance=\(utteranceCount) latest_chars=\(latest.count) committed_chars=\(committed.count) lcp_chars=\(lcp.count)")
    return String(latest.dropFirst(lcp.count))
}
```

Whitespace-trim the delta before yielding to stay consistent with `LiveCursorOutput.deliverPartial`'s existing trim.

**Correctness note** (LCP example, per req-0025 §2.2): given `latest = "hello word"`, `committed = "hello world"`, the longest common prefix is `"hello wor"`, so the returned delta is `"d"`. The cold path is **diagnostic**, not a correctness-preserving normal mode.

### 3.5 Ordered inbox — implementation shape

The partial callback signature is synchronous `@Sendable (String) -> Void`. Pattern:

```swift
// On the adapter actor:
private let partialInbox = NSLock()  // protects partialQueue
private nonisolated(unsafe) var partialQueue: [String] = []

// Synchronous callback (called from manager's actor context):
await manager.setPartialCallback { text in
    self.partialInbox.lock()
    self.partialQueue.append(text)
    self.partialInbox.unlock()
}

// Drained on the adapter actor between process() and VAD ingest:
private func drainPartialInbox() -> [String] {
    partialInbox.lock()
    let drained = partialQueue
    partialQueue.removeAll(keepingCapacity: true)
    partialInbox.unlock()
    return drained
}
```

`NSLock` precedent exists in this repo at `ModelBoundProcessorProvider.swift:9` and `WhisperCppTranscriberAdapter.swift:463`.

### 3.6 Do not register `eouCallback`

The adapter does not call `manager.setEouCallback`. Per req-0022 §2.5, the manager simply skips emission when no callback is registered. The latch bug becomes irrelevant — we never read what's broken.

### 3.7 What stays unchanged

- `manager.finish()` — still called once at session stop, still returns full-session cumulative text.
- `.finalized(TranscriptionResult(...))` — adapter still emits this with full-session text.
- `LiveCursorOutput`, `SessionPipelineOrchestrator.consumeLiveStreamingEvent`, `StreamingTranscriptAccumulator`, `RecipeBuilder` — zero changes downstream.
- `StreamingTranscriber` protocol — unchanged.
- Second-pass batch transcription path — unchanged.

### 3.8 VAD silence threshold default

1000ms (1 second). Configurable globally via Settings → General; per-mode override remains available.

Rationale: user-set value. Natural pause length that matches how dictation users actually break utterances. Lives at the global level so it can be shared across streaming adapters (FluidAudio today, WhisperKit/whisper.cpp later per `plans/streaming_whisper/DESIGN.md`).

**Storage:**
- Global default: UserDefaults key `StreamingEouSilenceThresholdMs`, default `1000`. Exposed in Settings → General under a "Streaming dictation" section heading.
- Per-mode override: `streamingBehavior.eouSilenceThresholdMs` in `workflow-modes.json`, optional, source `setting` (falls through to the global default).

```json
"eouSilenceThresholdMs": {
  "key": "StreamingEouSilenceThresholdMs",
  "settingDefault": 1000,
  "source": "setting"
}
```

Read at session start via the existing `BoundStreamingBehavior` pattern. UI: number stepper or short text field in General settings, with 200ms-3000ms range guardrails.

### 3.9 Instrumentation (inline with implementation)

Add these logs as part of this single phase — no separate instrumentation pass.

**Logging discipline — must follow:**
- **Event-driven only.** Log at discrete user-meaningful events: EOU emit, EOU receive, sink outcome, cold-path fallback. Never log periodic ticks (e.g. every partial, every buffer, every second).
- **One line per event per utterance.** No repeated logging of the same state.
- **No per-partial logs.** Partials can fire many times per second. Logging each one is spam with no signal.
- **No "we're still processing" heartbeats.** If nothing changed, log nothing.

Each log line carries: `session=<uuid> utterance=<n> ms_since_session_start=<monotonic>`.

| Seam | File | What |
|---|---|---|
| Adapter: `.endOfUtterance` emit | `FluidAudioStreamingTranscriberAdapter.swift` | timestamp, delta char count |
| Adapter: LCP cold-path | same | per §3.4 warning |
| Orchestrator: `.endOfUtterance` receive | `SessionPipelineOrchestrator.swift:1335-1386` | timestamp |
| Sink: clipboard write done | `LiveCursorOutput.swift:82-86` | timestamp |
| Sink: AX trust skip | `LiveCursorOutput.swift:88-91` | timestamp, outcome=ax_skip |
| Sink: self-focus skip | `LiveCursorOutput.swift:94-97` | timestamp, outcome=self_focus_skip |
| Sink: paste poster outcome | `LiveCursorOutput.swift:100-106` | timestamp, outcome=posted/failed |

These give us per-utterance timing across the live-cursor slice. Not full speech-end-to-paste latency (would need a true acoustic-end signal — out of scope for this plan); enough to localize the 5-6s within adapter/orchestrator/sink.

## 4. Test surface

### 4.1 Adapter unit tests (new)

Add to `Tests/PersonalScribeTranscriptionTests/Adapters/FluidAudioStreamingTranscriberAdapterTests.swift`:

1. `testPartialCallbackDerivesDeltaFromLastCommittedBoundary` — feed mock manager with cumulative partials `"hello"`, `"hello world"`, `"hello world how"`. Drive a `.speechEnded` at "hello world". Assert event sequence: `.partial("hello")`, `.partial("hello world")`, `.endOfUtterance("hello world")`, `.partial("how")`.
2. `testSameBufferPartialThenSpeechEndedUsesNewestCumulative` — manager's partial callback fires with `"hello world"` during the same `process(buffer)` that VAD then flags as `.speechEnded`. Assert `.endOfUtterance("hello world")`, not `.endOfUtterance("hello")` or an earlier stale value.
3. `testStreamEndBeforeAnyBoundaryEmitsOnlyFinalized` — partials arrive, stream ends before any `.speechEnded`. Assert no spurious `.endOfUtterance`, and `.finalized` carries full cumulative text.
4. `testVadFactoryReturnsNilFallsBackToNoVadMode` — injected factory returns `nil`. Assert single warning log; assert `.endOfUtterance` is only emitted at stream end (or not at all if stream ends via `.finalized`); assert session does not crash.
5. `testManagerEouCallbackIsNeverRegistered` — assert adapter does NOT call `manager.setEouCallback` at any point in the session lifecycle.
6. `testNoManagerResetDuringSession` — assert `manager.reset()` is not called between utterances. Only at adapter `cleanup()` / cancel / error / stream-end paths (existing behavior).
7. `testDeltaLcpColdPathExample` — `latest="hello word"`, `committed="hello world"` → delta = `"d"`. Plus warning log fired.

### 4.2 Integration test

Existing orchestrator multi-EOU test (`testStreamingLiveCursorDeliversEachEouChunkToOutputSink` at `SessionPipelineOrchestratorTests.swift:602-652`) already covers the orchestrator's two-EOU path with a stubbed adapter. Do NOT duplicate it — it does not exercise this fix's seam.

### 4.3 Manual verification

Add to `Tests/ManualVerifications/ManualStreamingVerification.md` (create if missing; the dir already exists per `Package.swift:126-129`).

- MV-STR-1: Three-utterance dictation, paste lands at cursor for each utterance.
- MV-STR-2: Single-utterance dictation, paste lands once.
- MV-STR-3: Stop mid-utterance before VAD silence, second-pass result lands at cursor as fallback.
- MV-STR-4: Open instrumented log after a session, confirm per-utterance timing lines and no `lcp_fallback` warnings on a normal session.

## 5. Files touched (estimate)

- `Sources/PersonalScribeTranscription/Adapters/FluidAudioStreamingTranscriberAdapter.swift` — new state + VAD fan-out + delta logic + inbox + logs. Bulk of the change.
- `Sources/PersonalScribeCore/Transcription/StreamingTranscriber.swift` or a new file in `PersonalScribeCore` — async `VadBoundarySessionFactory` typealias (avoids cross-module import).
- `Sources/PersonalScribeSession/Models/Selection/ModelBoundProcessorProvider.swift` — accept and pass the factory through to the adapter init.
- `Sources/PersonalScribeAppKit/Composition/AppComposition.swift` — construct the factory from the existing VAD provider, pass into `ModelBoundProcessorProvider`.
- `Sources/PersonalScribeCore/WorkflowMode/StreamingBehavior.swift` (or current location of that type) — add `eouSilenceThresholdMs` field.
- `Sources/PersonalScribeSession/WorkflowMode/RecipeBuilder.swift` — bind the new field.
- `Sources/PersonalScribeAppKit/Output/LiveCursorOutput.swift` — outcome logs at existing branch points.
- `Sources/PersonalScribeSession/Pipeline/Orchestrator/SessionPipelineOrchestrator.swift` — `.endOfUtterance` receive log line.
- `Tests/PersonalScribeTranscriptionTests/Adapters/FluidAudioStreamingTranscriberAdapterTests.swift` — 7 new tests per §4.1.
- `Tests/ManualVerifications/ManualStreamingVerification.md` — new runbook entries.

## 6. Risks

- **Delta derivation cold path.** If the LCP fallback ever fires in production, the manager's cumulative text has drifted from append-only. Diagnostic log + cold-path test cover the regression signal.
- **VAD threshold tuning.** 800ms is a starting guess. Too short → mid-sentence false positives. Too long → perceived sluggish. Configurable per-mode; revisit after dogfood.
- **First-utterance latency may not improve.** This fix targets multi-utterance correctness + reduces silence-wait from 1280ms to 800ms. The 5-6s symptom's unmeasured remainder (~4s) likely lives in model warmup / ANE compilation / encoder cache init — out of scope here.

## 7. What this plan deliberately does NOT do

- Does not fork FluidAudio.
- Does not call `manager.reset()` mid-session.
- Does not redesign the `StreamingTranscriber` protocol or `StreamingTranscriptionEvent` enum.
- Does not introduce a new VAD audio capture surface — adapter reuses the existing PCM stream.
- Does not change second-pass batch behavior.
- Does not touch any non-Parakeet adapter.
- Does not pre-commit to or block on the streaming Whisper work (separate plan at `plans/streaming_whisper/DESIGN.md`).
- Does not ship a long-lived `legacy` vs `vadBoundary` mechanism flag. The legacy mechanism is broken; switch over hard.

## 8. Commit shape

Single phase, single (or small number of) commit(s):
- `phase-X step X.M: vad-boundary EOU emit for streaming dictation (#056) (<one or two test names>)`

Pick next phase number after current trunk head. Verify trunk head before claiming the phase number.

## 9. Open implementation question (one)

§3.2 VAD type re-export: `VadSessionHandle` lives in `PersonalScribeVAD`. The adapter (in
`PersonalScribeTranscription`) cannot import `PersonalScribeVAD`. The chosen factory is async; the
remaining question is only how to surface the handle/event type across the module boundary. Two
options:

- **(a) Re-export `VadSessionHandle` from `PersonalScribeCore`** so both modules can reference the same type without an import-graph dependency.
- **(b) Fully erase the handle in the closure type** — `(_ silenceThresholdSeconds: Double) -> ((_ samples: [Float]) async -> VadEvent?)?`. Slightly uglier signature, no type re-export needed.

Recommend (a) for readability. If `PersonalScribeCore` re-export is awkward (e.g. introduces a transitive dependency on `FluidAudio`), fall back to (b).

Hermes: resolve this during implementation. Edit this section to record the choice + why. Do not pre-commit either option in the plan — confirm against the actual module graph.

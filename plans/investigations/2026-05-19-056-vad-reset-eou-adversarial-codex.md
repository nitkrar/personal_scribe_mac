# Adversarial review — VAD-driven manager reset as EOU mechanism for #056

## 1. Verdict on the proposal

**Needs modification.** The proposal is not fatally wrong, but it is incomplete at the integration seam: mid-session `reset()` is only plausibly safe if serialized between `manager.process(...)` calls, the adapter cannot currently read the manager's cumulative transcript through its own protocol, and resetting between utterances breaks the manager's terminal `finish()` semantics unless the adapter also synthesizes its own full-session final result.

The new measured `5-6s` latency report also changes one earlier conclusion: `eouDebounceMs = 1280` is only one floor, not a full explanation. Static inspection still supports one narrow claim only: the optional second pass is a **stop-time** path, not an in-session end-of-utterance path. The remaining latency stack is not instrumented today.

Short version: **VAD can replace the broken EOU callback, but `reset()` is not the clean free lunch the proposal assumes.**

## 2. Per-question answers

### 1. Is `manager.reset()` actually safe to call mid-session on an active `StreamingEouAsrManager`?

**Answer: only if the adapter serializes it between `process(...)` calls; it is not proven safe if invoked while a chunk is mid-process.**

Evidence:

- `StreamingEouAsrManager` is an `actor`, so calls are serialized, but actor reentrancy still allows another method to run when `process(...)` or `processChunkAndDecode(...)` is suspended on `await`. See `.build/checkouts/FluidAudio/Sources/FluidAudio/ASR/Parakeet/Streaming/EOU/StreamingEouAsrManager.swift:176`, `:355-383`, `:448-559`.
- FluidAudio explicitly documents this interleaving risk in `process(...)`: after awaiting `processChunkAndDecode(chunk)`, it re-checks `audioBuffer` because “Another actor method (e.g., `reset()`) could have modified the buffer during the await.” See `StreamingEouAsrManager.swift:371-377`.
- There are **no** lifecycle preconditions, assertions, or safety guards on `reset()` itself. It simply clears state. See `StreamingEouAsrManager.swift:416-425`.
- `processChunkAndDecode(...)` captures `preCache`, `cacheLastChannel`, `cacheLastTime`, `cacheLastChannelLen`, and `rnntDecoder` into locals before awaiting CoreML prediction, then mutates shared state afterward (`accumulatedTokenIds`, `totalSamplesProcessed`, `eouDetected`, caches). See `StreamingEouAsrManager.swift:448-559`.

What that means:

- A `reset()` that interleaves **during** `processChunkAndDecode(...)` will not necessarily crash, but it can mix pre-reset locals with post-reset actor state.
- That is enough to reject the proposal **as written** if it imagines `reset()` as a free “whenever silence fires” call.
- The proposal becomes viable only if the adapter guarantees `reset()` happens **after** a `manager.process(...)` call returns and **before** the next one starts.

### 2. Does `manager.reset()` synchronously block?

**Answer: yes, once scheduled on the actor it runs synchronously to completion; there are no internal `await`s, but it is not trivial work.**

Evidence:

- `reset()` is declared `async`, but its body contains no `await`. It clears arrays, booleans, counters, calls `resetStates()`, and resets the RNNT decoder state. See `StreamingEouAsrManager.swift:416-425`.
- `resetStates()` allocates and zeroes fresh `MLMultiArray` state for `preCache`, `cacheLastChannel`, `cacheLastTime`, and `cacheLastChannelLen`. See `StreamingEouAsrManager.swift:333-346`.
- It does **not** unload or reload the CoreML models; `cleanup()` is the method that nils model references. See `StreamingEouAsrManager.swift:428-437`.

Implication:

- The caller pays actor scheduling plus synchronous state-reset work.
- Static analysis cannot prove whether that is 1 ms or 100 ms, but it is clearly more than flipping one boolean.
- If the adapter calls `reset()` in the hot path, the user-visible latency budget becomes `VAD silence threshold + VAD chunking/inference + reset work`.

### 3. Can `VadManager` subscribe to the same audio stream the streaming ASR is consuming, or does it need its own audio capture?

**Answer: it does not need its own audio capture, but there is no subscription API; the adapter must fan out the same buffers manually.**

Evidence:

- `VadManager` exposes a push API: `processStreamingChunk(_ audioChunk: [Float], state: VadStreamState, config: VadSegmentationConfig, ...)`. It does not own or subscribe to capture. See `.build/checkouts/FluidAudio/Sources/FluidAudio/VAD/VadManager+Streaming.swift:10-27`.
- Local Ninimma VAD already wraps this as a push-fed session handle: `FluidAudioVadSession.ingest(_ samples: [Float])` accumulates samples into `VadManager.chunkSize` windows and calls the injected inference closure. See `Sources/PersonalScribeVAD/FluidAudioVadSession.swift:36-60`.
- The existing orchestrator already fans one capture stream out to **both** streaming ASR and capture-level VAD with the same incoming buffer: `liveStreamingInputContinuation?.yield(buffer)` and `let event = await handle.ingest(buffer.samples)`. See `Sources/PersonalScribeSession/Pipeline/Orchestrator/SessionPipelineOrchestrator.swift:985-1001`.

Implication:

- The adapter can absolutely feed a second VAD session from the same stream it already consumes.
- But the right mental model is **manual fan-out**, not “two subscribers on one VAD stream.”

### 4. What is `VadManager`'s silence-detection contract?

**Answer: it emits discrete `speechStart` / `speechEnd` events after internal hysteresis and a configured `minSilenceDuration`; it does not emit a running `silenceContinued(duration)` stream.**

Evidence:

- `VadSegmentationConfig` carries `minSilenceDuration` as a `TimeInterval`, default `0.75`, and enforces it via precondition. See `.build/checkouts/FluidAudio/Sources/FluidAudio/VAD/VadTypes.swift:23-90`.
- `VadManager.streamingStateMachine(...)` computes `minSilenceSamples = Int(config.minSilenceDuration * Double(Self.sampleRate))` and emits `.speechEnd` only after `processedSamples - silenceStart >= minSilenceSamples`. See `.build/checkouts/FluidAudio/Sources/FluidAudio/VAD/VadManager+Streaming.swift:51-90`.
- `VadStreamEvent.Kind` only has `.speechStart` and `.speechEnd`. See `.build/checkouts/FluidAudio/Sources/FluidAudio/VAD/VadTypes.swift:189-218`.
- Ninimma's wrapper collapses that further into `VadEvent.speechEnded` / `speechResumed`; there is no duration payload. See `Sources/PersonalScribeVAD/VadMonitoring.swift:3-37` and `Sources/PersonalScribeVAD/FluidAudioVadSession.swift:36-60`.
- VAD runs in 4096-sample windows, i.e. 256 ms at 16 kHz. See `.build/checkouts/FluidAudio/Sources/FluidAudio/VAD/VadManager.swift:17-25` and `Sources/PersonalScribeVAD/FluidAudioVadSession.swift:36-45`.

Implication:

- The proposal can map `silenceThresholdMs` onto `minSilenceDuration`, but it does **not** get a continuously updated silence clock from VAD.
- Effective boundary latency is at least `minSilenceDuration + 256 ms chunk quantization + inference overhead`, not just the configured threshold.

### 5. What happens if `StreamingEouAsrManager`'s `eouCallback` is not registered?

**Answer: nothing special. The manager simply skips emission.**

Evidence:

- `eouCallback` is optional: `private var eouCallback: EouCallback?`. See `StreamingEouAsrManager.swift:192-198`.
- The callback site is guarded by `if let callback = eouCallback, let tokenizer = tokenizer { ... }`. See `StreamingEouAsrManager.swift:546-549`.
- There is no log, trap, precondition, or fallback path tied to a missing callback.

Implication:

- The proposal is correct that the adapter can bypass the built-in EOU callback by simply not registering one, or by registering a no-op.

### 6. What about `partialCallback` and `StreamingTranscriptAccumulator` if partial text shrinks after reset?

**Answer: this part is actually okay, provided the adapter emits `.endOfUtterance` before it resets.**

Evidence:

- `StreamingTranscriptAccumulator.apply(.partial(text:))` just replaces `inProgressUtterance` with the current partial; it does not assume monotonic growth. See `Sources/PersonalScribeSession/Pipeline/Orchestrator/StreamingTranscriptAccumulator.swift:9-15`.
- `cumulativeText` is `committedUtterances + inProgressUtterance`. See `StreamingTranscriptAccumulator.swift:30-35`.
- `apply(.endOfUtterance(text:))` appends the utterance to `committedUtterances` and clears `inProgressUtterance`. See `StreamingTranscriptAccumulator.swift:16-22`.

So if the adapter does:

1. VAD detects end of utterance A,
2. adapter emits `.endOfUtterance("A")`,
3. adapter calls `reset()`,
4. next utterance B begins and manager partials start again from `"B"`,

then the accumulator computes:

- committed utterances = `["A"]`
- in-progress utterance = `"B"`
- cumulative text = `"A B"`

That is correct.

**But** there is a more serious problem elsewhere:

- The real manager's `finish()` decodes **only** its current `accumulatedTokenIds`, then clears them. See `StreamingEouAsrManager.swift:404-413`.
- The adapter forwards that `finalText` unchanged as `.finalized(...)`. See `Sources/PersonalScribeTranscription/Adapters/FluidAudioStreamingTranscriberAdapter.swift:200-221`.
- The orchestrator fallback path prefers `accumulator.terminalFinalResult` over `accumulator.terminalText`. See `Sources/PersonalScribeSession/Pipeline/Orchestrator/SessionPipelineOrchestrator.swift:1517-1539`.
- `StreamingTranscriptAccumulator.terminalText` also prefers `terminalFinalResult.text` when present. See `StreamingTranscriptAccumulator.swift:38-45`.

That means a reset-based adapter would make `finish()` return only the **last post-reset utterance**, and the fallback path would drop earlier committed utterances unless the adapter also rewrites finalization semantics.

This is the biggest hidden correctness cost in the proposal.

### 7. Counter-proposals

#### 7a. Re-register the EOU callback after each fire

**Refuted.** Re-registering the callback does not clear the sticky latch. The one-shot behavior is guarded by `!eouDetected`, and only `reset()` clears `eouDetected`. See `StreamingEouAsrManager.swift:194`, `:420`, `:542-544`.

#### 7b. Patch the latch via runtime property access / reflection

**Refuted at the normal API layer.** `eouDetected` is `public private(set)`, so external code can read it but cannot write it. See `StreamingEouAsrManager.swift:193-194`.

#### 7c. Use a non-EOU streaming model and own the whole boundary stack

**Technically possible, but materially larger scope.** Nothing in the current code suggests an existing non-EOU streaming adapter path already wired for Ninimma's `ProcessorSpec.streamingTranscriber`. This would be a model/routing product decision, not a small seam fix.

#### 7d. Switch to WhisperKit / another streaming paradigm

**Real alternative, but not a drop-in swap.** WhisperKit's `AudioStreamTranscriber` is stronger than the reset proposal on native multi-utterance behavior, but weaker on integration cost.

What it gets you:

- `AudioStreamTranscriber` keeps long-lived streaming state (`currentText`, `confirmedSegments`, `unconfirmedSegments`, `lastConfirmedSegmentEndSeconds`) instead of a single sticky EOU latch. See `.build/checkouts/argmax-oss-swift/Sources/WhisperKit/Core/Audio/AudioStreamTranscriber.swift:7-17`.
- It exposes `requiredSegmentsForConfirmation`, `useVAD`, and `silenceThreshold`, so its streaming design is based on segment confirmation plus optional VAD, not on one-shot EOU callback delivery. See `AudioStreamTranscriber.swift:35-55`, `:142-192`.

What it does **not** solve for free:

- Personal Scribe currently classifies `whisperKit` as `.asr`, not `.streamingASR`, while `ProcessorSpec.streamingTranscriber` and `ModelBoundProcessorProvider.streamingTranscriber(...)` expect a `.streamingASR` descriptor. See `Sources/PersonalScribeCore/Models/Selection/TranscriptionEngine+Kind.swift:16-29`, `Sources/PersonalScribeCore/WorkflowMode/ProcessorSpec.swift:23-30`, and `Sources/PersonalScribeSession/Models/Selection/ModelBoundProcessorProvider.swift:101-113`.
- The current WhisperKit integration is batch-only: `WhisperKitTranscriberAdapter` conforms `Transcriber`, not `StreamingTranscriber`. See `Sources/PersonalScribeTranscription/Adapters/WhisperKitTranscriberAdapter.swift:57`, `:138-160`.
- Ninimma's streaming seam is buffer-fed (`transcribe(stream: AsyncThrowingStream<PCMBuffer, Error>)`), but `AudioStreamTranscriber` owns microphone capture via `startRecordingLive` / `stopRecording`. See `Sources/PersonalScribeCore/Transcription/StreamingTranscriber.swift:19-26` and `AudioStreamTranscriber.swift:76-95`.
- Ninimma expects `.partial`, utterance-scoped `.endOfUtterance(text:)`, and a full-session `.finalized(...)`; `AudioStreamTranscriber` exposes state-change callbacks, not utterance events, and the upstream CLI still has a TODO to “Print only net new text without any repeats.” See `Sources/PersonalScribeCore/Transcription/StreamingTranscriptionEvent.swift:8-21`, `AudioStreamTranscriber.swift:20-23`, `:164-192`, and `.build/checkouts/argmax-oss-swift/Sources/ArgmaxCLI/TranscribeCLI.swift:301-316`.
- `AudioStreamTranscriber` has its own latency floor: it waits until the next unread audio exceeds `1` second and otherwise sleeps `100ms` before checking again. See `AudioStreamTranscriber.swift:130-140`.

#### 7e. Recommended counter-proposal

**Use VAD only as the utterance-boundary signal, but do not call `reset()`.**

Why this is lower risk:

- The sticky `eouDetected` bug only breaks the manager's **EOU callback**. It does **not** stop the manager from appending tokens and emitting cumulative partials. Partials come from `accumulatedTokenIds.append(contentsOf: decodeResult.tokenIds)` followed by `tokenizer.decode(ids: accumulatedTokenIds)`. See `StreamingEouAsrManager.swift:514-519`.
- Because the manager only appends token IDs, it is already maintaining the full-session transcript internally. See `StreamingEouAsrManager.swift:189-190`, `:514`.
- If the adapter caches the latest cumulative partial text and separately tracks the last committed cumulative boundary text, then on VAD `speechEnd` it can emit:
  - `.endOfUtterance(deltaSinceLastBoundary)`
  - future `.partial(deltaSinceLastBoundary)`
- That preserves:
  - the manager's full-session `finish()` result,
  - RNNT/encoder state across utterances,
  - no mid-process `reset()` reentrancy hazard.

Head-to-head versus the reset proposal:

- **Reset proposal:** easier delta semantics, but harder concurrency, harder finalization, possible quality loss, and protocol widening/caching still needed.
- **No-reset VAD-boundary adapter:** harder delta derivation, but cleaner finalization and lower integration risk.

The main caveat for this counter-proposal is delta derivation quality:

- The adapter protocol does not expose token IDs, only text callbacks. See `Sources/PersonalScribeTranscription/Adapters/FluidAudioStreamingTranscriberAdapter.swift:143-155`.
- So the adapter would need to derive deltas from cached text, likely by prefix subtraction / longest common prefix. That is still simpler than reset-driven finalization surgery, because the real manager's cumulative transcript is append-only by token accumulation.

Relative to the user's broader architecture question, this means:

- **FluidAudio + VAD + reset:** smallest conceptual change from today's implementation, but highest seam risk because of reset serialization, finalization surgery, and context loss.
- **WhisperKit `AudioStreamTranscriber`:** native multi-utterance design, but it is a real streaming-stack rewrite rather than a model swap.
- **FluidAudio + VAD + no reset (recommended):** still a workaround, but it fixes the live-cursor contract at the adapter seam without taking on either mid-stream reset hazards or a fresh streaming integration.

## 3. Hidden costs

### Hidden cost 1 — adapter protocol gap

The proposal says “read the current cumulative transcript” before reset, but the adapter's abstraction does not expose that:

- `FluidAudioStreamingEouManaging` includes `setPartialCallback`, `setEouCallback`, `process`, `finish`, `reset`, `cleanup`, but **not** `getPartialTranscript()`. See `Sources/PersonalScribeTranscription/Adapters/FluidAudioStreamingTranscriberAdapter.swift:143-155`.
- The concrete manager does expose `getPartialTranscript()`. See `.build/checkouts/FluidAudio/Sources/FluidAudio/ASR/Parakeet/Streaming/EOU/StreamingEouAsrManager.swift:600-603`.

So the proposal needs one of:

- protocol widening, or
- adapter-side cached transcript state from partial callbacks.

### Hidden cost 2 — terminal finalization breakage

As covered above, resetting between utterances means `finish()` and `.finalized(...)` no longer represent the whole session. That is a correctness bug if second-pass is disabled or fails.

### Hidden cost 3 — state/context loss

`reset()` clears:

- `accumulatedTokenIds`
- `audioBuffer`
- `eouDetected`
- `eouFirstDetectedAt`
- `totalSamplesProcessed`
- RNNT decoder state
- encoder cache state via `resetStates()`

See `StreamingEouAsrManager.swift:416-425`.

That is not just “clear the EOU latch.” It discards acoustic/language-model continuity too.

### Hidden cost 4 — VAD adds coarse latency, not just threshold latency

Because VAD ingests `4096`-sample chunks (256 ms) and only emits `speechEnd` after `minSilenceDuration` has elapsed inside the state machine, the real latency budget is worse than the proposal's optimistic “threshold + ~50 ms” framing. See `VadManager.swift:17-25`, `VadManager+Streaming.swift:51-90`, and `FluidAudioVadSession.swift:36-60`.

### Hidden cost 5 — duplicated boundary logic and compute

The EOU head in the Parakeet EOU model becomes wasted work if the adapter ignores it entirely, and a second VAD consumer adds another streaming state machine in parallel. This is not fatal, but it is a real complexity/perf cost.

### Hidden cost 6 — latency observability gap

The new `5-6s` report is real input, but the current code does not instrument live end-of-utterance latency well enough to localize it:

- `FluidAudioStreamingTranscriberAdapter` emits `.finalized(...)` with `processingDuration: .zero`. See `Sources/PersonalScribeTranscription/Adapters/FluidAudioStreamingTranscriberAdapter.swift:211-219`.
- The orchestrator's fallback result also stamps `processingDuration: .zero`. See `Sources/PersonalScribeSession/Pipeline/Orchestrator/SessionPipelineOrchestrator.swift:1517-1539`.
- The active workflow mode does enable `secondPassEnabled`, and recipe binding converts that into a batch second-pass transcriber when an `.asr` descriptor is active. See `~/Library/Application Support/personal_scribe/workflow-modes.json:193-206` and `Sources/PersonalScribeSession/WorkflowMode/RecipeBuilder.swift:148-157`.
- But `runBoundStreamingTranscription()` only reaches that second pass after `finishLiveStreamingSessionForStop()` completes. See `Sources/PersonalScribeSession/Pipeline/Orchestrator/SessionPipelineOrchestrator.swift:802-839`, `:1409-1429`.

So static inspection can rule second pass out for an **in-session** second-EOU delay, but it cannot explain the rest of the `5-6s`. That needs measurement, not guesswork.

## 4. Counter-proposal recommendation

**Recommendation: prefer VAD boundary detection without manager reset.**

Concrete shape:

1. Keep using the real `StreamingEouAsrManager` for cumulative partial decoding.
2. Stop using its `eouCallback`.
3. Add adapter-local VAD on the same input buffers.
4. Cache:
   - latest cumulative partial text,
   - last committed cumulative text.
5. On VAD `speechEnd`, emit `.endOfUtterance(delta)` where `delta = latestCumulative - lastCommitted`.
6. For subsequent `.partial` events, emit the same kind of delta relative to `lastCommitted`, not the raw cumulative partial.
7. Leave `manager.finish()` untouched so `.finalized(...)` remains full-session text.

Why this wins:

- avoids mid-process reset hazards,
- avoids terminal-final truncation,
- preserves RNNT/encoder continuity,
- still solves sticky one-shot EOU emission by ignoring the broken built-in callback entirely.

Head-to-head on the user's requested decision axes:

- **Measured latency**
  - Current code does not preserve a reliable live-stream latency number today (`processingDuration` is `.zero` on both adapter finalization and fallback result). See `FluidAudioStreamingTranscriberAdapter.swift:211-219` and `SessionPipelineOrchestrator.swift:1517-1539`.
  - `FluidAudio + VAD + reset` has at least the VAD silence threshold plus `4096`-sample (`256ms`) chunking and reset work. See `.build/checkouts/FluidAudio/Sources/FluidAudio/VAD/VadManager.swift:17-25`, `.build/checkouts/FluidAudio/Sources/FluidAudio/VAD/VadManager+Streaming.swift:51-90`, and `.build/checkouts/FluidAudio/Sources/FluidAudio/ASR/Parakeet/Streaming/EOU/StreamingEouAsrManager.swift:416-425`.
  - `WhisperKit AudioStreamTranscriber` has its own static floor because it waits for `>1s` of unread audio and otherwise sleeps `100ms`. See `AudioStreamTranscriber.swift:130-140`.
  - Conclusion: the new `5-6s` measurement is a reason to instrument both paths, not a reason to assume either one wins from static reading alone.

- **Adapter complexity**
  - `FluidAudio + VAD + reset` is high complexity because it must serialize resets, cache cumulative transcript state, and synthesize full-session finalization.
  - `WhisperKit AudioStreamTranscriber` is also high complexity because the current app only wires WhisperKit as batch `.asr`, not streaming `.streamingASR`, and its upstream API owns capture instead of consuming `PCMBuffer` chunks. See `TranscriptionEngine+Kind.swift:16-29`, `ModelBoundProcessorProvider.swift:39-62`, `:101-113`, `StreamingTranscriber.swift:19-26`, and `AudioStreamTranscriber.swift:76-95`.
  - `FluidAudio + VAD + no reset` is medium complexity because it still needs delta derivation, but it does not need reset/finalization surgery.

- **Accuracy on dictation**
  - The repo's own catalog positions Parakeet EOU as the lowest-latency streaming dictation option and WhisperKit large models as higher-accuracy dictation options, but there is no repository-local head-to-head measurement for streaming dictation accuracy. See `Sources/PersonalScribeCore/Models/Selection/BuiltInModelCatalog.swift:348-362`, `:226-264`.

Reference/code divergence note:

- `BuiltInModelCatalog.swift` still has a stale comment saying the Parakeet EOU adapter is “not yet wired in PersonalScribeTranscription” and downloads via that descriptor currently fail. See `Sources/PersonalScribeCore/Models/Selection/BuiltInModelCatalog.swift:336-340`.
- The executable runtime path is different: `ModelBoundProcessorProvider` does wire `.parakeetEOU` to `FluidAudioStreamingTranscriberAdapter`, so the provider is the canonical source for current behavior. See `Sources/PersonalScribeSession/Models/Selection/ModelBoundProcessorProvider.swift:55-62`.

- **Multi-utterance behavior**
  - `FluidAudio + VAD + reset` is a workaround around a one-shot EOU latch.
  - `WhisperKit AudioStreamTranscriber` is natively continuous-stream and keeps confirmed/unconfirmed segments over time. See `AudioStreamTranscriber.swift:7-17`, `:168-192`.
  - `FluidAudio + VAD + no reset` is still a workaround, but it preserves the manager's cumulative transcript and full-session `finish()`.

Bottom line:

- For the current bug, stay on the FluidAudio seam and repair the contract there; the no-reset VAD boundary variant is the least risky path.
- If the user wants a product-level rethink rather than a seam fix, WhisperKit streaming is the more honest architecture to evaluate, but it should be scoped as a fresh streaming integration spike, not as a small bug-fix patch.

## 5. Implementation order if the proposal stands

If the team still wants the **reset-based** design, the safe order is:

1. **Serialize reset placement first.**
   Only call `reset()` after a `manager.process(...)` call has returned, never from a concurrent callback or timer task.

2. **Add adapter-owned transcript state.**
   Either widen `FluidAudioStreamingEouManaging` or cache cumulative partial text in the adapter so it can emit an EOU transcript before reset.

3. **Fix finalization semantics before shipping.**
   Do not forward the manager's `.finalized(lastUtteranceOnly)` unchanged. The adapter must synthesize a full-session final result if it has reset the manager between utterances.

4. **Then wire adapter-local VAD.**
   Feed the same input buffers into a VAD session; do not add a second audio capture surface.

5. **Only after that expose config/schema.**
   The `streamingBehavior.eouMechanism` schema is a follow-up once the seam itself is proven correct.

If the team adopts the **recommended no-reset counter-proposal**, the order is simpler:

1. Add adapter-local VAD.
2. Cache cumulative partial text and last committed boundary text.
3. Emit delta `.partial` / `.endOfUtterance` from the adapter.
4. Leave `finish()` and second-pass behavior unchanged.

If the team instead chooses the **WhisperKit streaming** path, the safe order is:

1. Lock the canonical event contract first: cumulative vs delta, utterance-boundary mapping, and full-session finalization against `StreamingTranscriptionEvent` and live-cursor append-only EOU delivery. See `Sources/PersonalScribeCore/Transcription/StreamingTranscriptionEvent.swift:8-21` and `Sources/PersonalScribeSession/Pipeline/Orchestrator/SessionPipelineOrchestrator.swift:1365-1384`.
2. Build a buffer-fed `StreamingTranscriber` adapter over WhisperKit; do **not** let the dependency take over microphone capture inside Personal Scribe. See `StreamingTranscriber.swift:19-26` and `AudioStreamTranscriber.swift:76-95`.
3. Add model routing for a WhisperKit streaming engine / kind instead of reusing the current batch-only `.whisperKit -> .asr` path. See `TranscriptionEngine+Kind.swift:16-29` and `ModelBoundProcessorProvider.swift:39-62`, `:101-113`.
4. Add latency instrumentation before making the product call on responsiveness; current live-streaming results do not preserve it. See `FluidAudioStreamingTranscriberAdapter.swift:211-219` and `SessionPipelineOrchestrator.swift:1517-1539`.
5. Only then compare dictation accuracy and UX against the repaired FluidAudio path.

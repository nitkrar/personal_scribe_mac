# Investigation — #056 streaming dictation EOU second-utterance + latency bugs

## 1. Findings — Bug 1 (second EOU does not paste)

### Verdict

Most likely root cause is **upstream EOU emission becoming one-shot inside FluidAudio's real `StreamingEouAsrManager`**. This is a refinement of H4 ("stream upstream stops emitting EOU events after first"), not an orchestrator/output-sink bug.

- `StreamingEouAsrManager` stores a session-scoped `eouDetected` latch initialized to `false` and only reset in `reset()` at session end, not per utterance. See `.build/checkouts/FluidAudio/Sources/FluidAudio/ASR/Parakeet/Streaming/EOU/StreamingEouAsrManager.swift:189-206` and `:416-425`.
- On EOU confirmation it gates callback emission with `if elapsedMs >= eouDebounceMs && !eouDetected`, then sets `eouDetected = true` before invoking the callback. See `StreamingEouAsrManager.swift:525-550`.
- When speech resumes, the code only clears `eouFirstDetectedAt`; it does **not** clear `eouDetected`. See `StreamingEouAsrManager.swift:527-555`.
- Result: the first utterance can confirm EOU and call back once, but later utterances in the same recording can continue producing partials while **never satisfying the `!eouDetected` gate again**.

That shape matches the user report closely:

- first utterance pastes once,
- later utterances do not paste,
- StreamCard can still keep updating because partial callbacks are independent of the sticky `eouDetected` latch (`StreamingEouAsrManager.swift:514-519`).

### Why the other hypotheses rank lower

- **H1 / H5 (accumulator poisoning / accumulator dropping the event):** refuted for the cursor path. `SessionPipelineOrchestrator.consumeLiveStreamingEvent` sends the raw `.endOfUtterance(let chunkText)` payload to `outputSink.deliverPartial(...)`; it does **not** use the accumulator return value for cursor delivery. See `Sources/PersonalScribeSession/Pipeline/Orchestrator/SessionPipelineOrchestrator.swift:1335-1384`.
- **H2 (self-focus probe stale after first paste):** low likelihood. `LiveCursorOutput.deliverPartial` would log the self-focus skip once per cycle if it were invoked and rejected by focus ownership. That log path exists at `Sources/PersonalScribeAppKit/Output/LiveCursorOutput.swift:94-99` and `:154-159`, but the cited diagnostics sample shows no `LiveCursorOutput` lines at all while the streaming rounds only show stop-time `ClipboardBatchOutput` logs. See `~/Library/Application Support/personal_scribe/logs/diagnostics.log:39-58`.
- **H3 (live streaming consumer task torn down too early):** low likelihood. The orchestrator creates `liveStreamingEventTask` once at session start and keeps it alive until stop/cancel/error. There is no in-session path that tears it down after the first EOU while recording continues. See `SessionPipelineOrchestrator.swift:1299-1329`, `:1409-1444`.

### Critical contract conflict surfaced

There is a separate, load-bearing reference/code conflict here:

- The app-level contract says `.endOfUtterance(text:)` is the stable transcript **for that utterance**. See `Sources/PersonalScribeCore/Transcription/StreamingTranscriptionEvent.swift:13-16`.
- The orchestrator comments also assume each EOU event is the **new append-only chunk** to send to the cursor. See `SessionPipelineOrchestrator.swift:1365-1378`.
- But the real FluidAudio manager does not emit a delta. It appends decoded token IDs into one session-long `accumulatedTokenIds` array and both the partial callback and the EOU callback decode that **entire accumulator**. See `StreamingEouAsrManager.swift:189-190`, `:408-411`, `:514-519`, `:546-549`.
- The adapter forwards that callback text unchanged as `.endOfUtterance(text:)`. See `Sources/PersonalScribeTranscription/Adapters/FluidAudioStreamingTranscriberAdapter.swift:166-172`.

So once the one-shot EOU bug is fixed upstream, the current app code would likely expose a **second bug immediately**:

- `LiveCursorOutput.deliverPartial` overwrites the clipboard with the supplied text, then posts Cmd+V. See `Sources/PersonalScribeAppKit/Output/LiveCursorOutput.swift:70-106`.
- If EOU #1 emits `"A"` and EOU #2 emits cumulative `"A B"`, the target app receives `"A"` and then `"A B"` pasted again, which is visible doubling rather than append-only `"B"`.
- The live card path has the same mismatch: `StreamingTranscriptAccumulator.apply(.endOfUtterance)` appends the incoming text to `committedUtterances`, which is only correct for per-utterance deltas. With cumulative payloads it duplicates prior content. See `Sources/PersonalScribeSession/Pipeline/Orchestrator/StreamingTranscriptAccumulator.swift:16-35`.

Current tests mask this mismatch because they stub delta-shaped EOU events:

- Orchestrator test expects `["hello", "world"]` as two separate EOU chunks. See `Tests/PersonalScribeSessionTests/Pipeline/SessionPipelineOrchestratorTests.swift:602-645`.
- Adapter bridge test also uses a stub manager that manually emits a single EOU string, not the real manager's cumulative contract. See `Tests/PersonalScribeTranscriptionTests/Adapters/FluidAudioStreamingTranscriberAdapterTests.swift:8-35`.

## 2. Findings — Bug 2 (EOU latency)

### Verdict

The main latency is **model-side EOU debounce inside FluidAudio**, not VAD and not a pipeline-side debounce in Ninimma.

- `FluidAudioStreamingTranscriberAdapter` constructs `StreamingEouAsrManager` with only `chunkSize:`; it does not override the debounce. See `Sources/PersonalScribeTranscription/Adapters/FluidAudioStreamingTranscriberAdapter.swift:22-25`.
- `StreamingEouAsrManager` defaults `eouDebounceMs` to `1280`. See `.build/checkouts/FluidAudio/Sources/FluidAudio/ASR/Parakeet/Streaming/EOU/StreamingEouAsrManager.swift:200-234`.
- The 160ms model still runs chunked streaming with `chunkSamples = 2560`, `shiftSamples = 1280`, and `durationMs = 160`; practically, EOU checks advance in 80ms shifts after each processed chunk. See `StreamingEouAsrManager.swift:49-87` and `:121-159`.
- The callback does not fire on first EOU detection. It waits until the model keeps reporting `decodeResult.eouDetected` long enough for `elapsedMs >= eouDebounceMs`. See `StreamingEouAsrManager.swift:525-550`.

That means mid-session cursor delivery cannot happen until roughly **1.28s of sustained silence plus chunk/model overhead**, even on the "160ms" variant. The `160ms` choice lowers chunking latency relative to the 320ms / 1280ms models, but it does **not** bypass the manager's 1280ms silence debounce.

### L1-L4 ranking

- **L1 (model chunk window / model-side configuration): matched strongly.** The manager's chunking plus the hard-coded default `eouDebounceMs = 1280` is the dominant delay source.
- **L2 (pipeline-side debounce): refuted.** In the local app path there is no `Task.sleep`, `DispatchQueue.asyncAfter`, or similar delay between the adapter callback and `outputSink.deliverPartial(...)`. The orchestrator just `for await`s events and immediately handles `.endOfUtterance`. See `SessionPipelineOrchestrator.swift:1320-1327` and `:1371-1380`.
- **L3 (AsyncStream backpressure / yield-late): low likelihood.** The adapter simply bridges manager callbacks into an `AsyncThrowingStream` and the orchestrator consumes that stream directly. There is no custom buffering policy or queueing layer here. See `FluidAudioStreamingTranscriberAdapter.swift:157-188` and `SessionPipelineOrchestrator.swift:1313-1329`.
- **L4 (second-pass confound): true for stop-time logs, but not for the mid-session complaint.** The actual mode config has `secondPassEnabled = true` (`~/Library/Application Support/personal_scribe/workflow-modes.json:193-206`), `RecipeBuilder` resolves that into `BoundStreamingBehavior.secondPassEnabled` (`Sources/PersonalScribeSession/WorkflowMode/RecipeBuilder.swift:134-155`), and after the user stops the whole session the orchestrator enters `.transcribing` and may run an authoritative second pass (`SessionPipelineOrchestrator.swift:645-690` and `:802-839`). That explains the observed 0.4-0.8s `transcribing -> done` stop-time gap in diagnostics, but it does **not** explain the user's mid-session "pause, then paste appears too late" perception.

## 3. Diagnostic gaps

- `LiveCursorOutput` only logs failure/skip paths: clipboard write failure, AX trust skip, self-focus skip, paste-poster failure. It has **no success-path log**. See `Sources/PersonalScribeAppKit/Output/LiveCursorOutput.swift:70-106`.
- A success log like `LiveCursorOutput: delivered chunk` would have made the current field evidence much faster to interpret. It would have shown whether the first EOU really reached the sink and whether a second one ever did.
- But a success log at the sink is still not sufficient to localize the failure. To distinguish "no second EOU emitted" from "EOU emitted cumulative text" from "EOU emitted empty text and trimmed away," the app needs traces at two upstream seams too:
  - **Adapter bridge trace:** log when the FluidAudio EOU callback fires, with transcript length (and ideally whether it equals the full accumulated transcript length).
  - **Orchestrator consumer trace:** log receipt of `.endOfUtterance` in `consumeLiveStreamingEvent` and log just before `outputSink.deliverPartial(...)`.
- There is also a **test gap**: current orchestrator and sink tests encode the intended per-utterance-delta contract, but they do not exercise the real manager's cumulative callback behavior or repeated EOU windows. That let the sticky `eouDetected` bug and the cumulative-vs-delta mismatch survive together.

## 4. Fix sketch

### Bug 1

The minimal safe fix needs to land in **two coupled pieces**, not one. First, fix the real upstream EOU state machine so one confirmed EOU does not permanently latch the session into "already emitted" state; `eouDetected` must become per-utterance/per-silence-window state, or be cleared as soon as speech resumes / after the callback fires so later silence windows can confirm again. Second, normalize the callback contract before Ninimma consumes it: the smallest-blast-radius place is the adapter, because the app-level `StreamingTranscriptionEvent.endOfUtterance` docs, the orchestrator comments, the live cursor sink, and the accumulator all currently assume delta chunks. If the real manager keeps sending cumulative transcript-so-far, the adapter should convert cumulative transcript into a per-utterance delta before emitting `.endOfUtterance`, and either do the same for `.partial` or explicitly split the event contract into cumulative-vs-delta forms. Fixing only the sticky EOU latch would surface visible duplication immediately.

### Bug 2

Expose EOU debounce as an explicit configuration instead of silently inheriting FluidAudio's `1280ms` default. The current adapter hard-wires only chunk size; it should also choose an `eouDebounceMs` appropriate for live-cursor dictation, or carry debounce as part of the model descriptor / streaming behavior so the "160ms" low-latency model is not paired with a 1.28s silence gate by accident. Keep the stop-time second pass separate; it is a finalization quality trade-off, not the mid-session cursor latency root cause. Add timing instrumentation around `EOU candidate started`, `EOU confirmed`, adapter callback emission, orchestrator event receipt, and sink delivery so future complaints can be localized in one log read instead of by static source audit.

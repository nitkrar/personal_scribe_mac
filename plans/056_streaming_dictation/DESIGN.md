# #056 — Streaming dictation: DESIGN

References `BACKLOG.md` #056 and #033. This doc locks product semantics and the architectural shape needed to ship them. It is a design doc, not a step-by-step plan.

Implementation may be reasoned about in stages, but the user-visible behavior in each executable slice should land atomically once coded. `#033` still owns the live cursor transport decision, so this doc separates "what streaming dictation means" from "how cursor streaming is physically delivered."

**Path verification:** every `Sources/` / `Tests/` citation in this doc was grep-verified at write-time.

---

## Why this doc exists

The old backlog body for #056 is stale in three important ways:

1. "Separate hotkey from quick mode" is no longer the core work. `Streaming Dictation` already exists as a custom preset, and per-mode hotkeys already exist.
2. "Partials render in the pill" does not match the current UI architecture. The pill has no transcript-text surface.
3. The current "streaming" execution path is not actually live. The streaming transcriber runs on buffered replay after stop, not during capture.

This doc replaces the stale assumptions with a design that matches the current codebase and the product decisions locked on 2026-04-30.

---

## Verified current state

### 1. Streaming Dictation already exists as a custom preset

- `Preset.streamingDictation` already materializes a streaming recipe in `Sources/PersonalScribeAppKit/UnifiedWindow/Tabs/Modes/Preset.swift`.
- The mode detail UI already exposes a Realtime toggle and per-mode hotkey entry in `Sources/PersonalScribeAppKit/UnifiedWindow/Tabs/Modes/ModeDetailView.swift`.
- Per-mode hotkeys are already wired through `AppComposition.configurePerModeHotkeys(...)` in `Sources/PersonalScribeAppKit/Composition/AppComposition.swift`.

Implication: #056 does **not** need to invent a new built-in mode or a dedicated "streaming hotkey" system. V1 can stay a user-created custom preset.

### 2. The current "streaming" path is not live

- `SessionSnapshot` already has `transcriptProgress` in `Sources/PersonalScribeCore/SessionSnapshot.swift`.
- `SessionPipelineOrchestrator.runBoundStreamingTranscription(...)` in `Sources/PersonalScribeSession/Pipeline/Orchestrator/SessionPipelineOrchestrator.swift` currently replays `bufferedAudio` **after stop**, collects `.partial` / `.endOfUtterance` events into `lastText`, and returns only the terminal result.
- `SessionCoordinator` currently wires `CoordinatorPipelineOutputSink` as a no-op and `CoordinatorPipelineContextProvider` with `streamingOutputEnabled: false` in `Sources/PersonalScribeSession/SessionCoordinator.swift`.

Implication: even though the adapter emits `StreamingTranscriptionEvent`, no live partials reach the UI or the cursor today.

### 3. The pill is intentionally small and has no transcript surface

- `PillOverlayViewModel` only carries visibility, visibility mode, and audio level in `Sources/PersonalScribeAppKit/Overlay/PillOverlayViewModel.swift`.
- `PillOverlayView` renders compact stateful pills such as recording, transcribing, done, download, and error in `Sources/PersonalScribeAppKit/Overlay/PillOverlayView.swift`.
- The existing `ResponseCard` in `Sources/PersonalScribeAppKit/Overlay/ResponseCard.swift` is a separate compact panel sized for short notices. Its width is intentionally capped to `200...320pt`.

Implication: "show live text in the pill" is the wrong surface. Live transcript must be a separate overlay card.

### 4. Audio capture is RAM-only today

- `SessionPipelineOrchestrator` stores captured audio in `bufferedAudio: [PCMBuffer]` in `Sources/PersonalScribeSession/Pipeline/Orchestrator/SessionPipelineOrchestrator.swift`.
- Buffers are appended inside `consumeCaptureStream(...)` and replayed after stop. There is no temp-file spooling path on any mode.

Implication: shared spooling / crash-recovery / re-transcribe-from-temp is a cross-mode infrastructure problem, not a #056-only problem.

---

## Locked product semantics

### Surface split

- `StreamCard` is a new surface for live transcript only.
- Existing `ResponseCard` stays the operational/status surface only.
- The pill stays small and stateful. No live transcript text in the pill.

### StreamCard

- Shows the **rolling session tail**, not only the current utterance.
- Shows **streaming-model partials**, including sub-EOU updates. It is "live" in the dogfood sense; it does not wait for end-of-utterance.
- Wider than the current `ResponseCard`, but still **single-line**. Width grows; height does not.
- Overflow behavior is a **global-only** preference with three modes:
  - tail-pinned head ellipsis (default)
  - marquee
  - word-by-word fade
- No editing, no buttons, no links.
- Hidden when the mode/session does not want live transcript UI.

### ResponseCard

- Keeps short operational/status content only:
  - `Finalizing…`
  - `Copied final to clipboard`
  - `Clipboard restored`
  - transport fallback / permissions / error messages
- If recording completes, errors, or enters finalization status, the `StreamCard` disappears immediately and the `ResponseCard` takes over.
- `StreamCard` and `ResponseCard` do **not** co-exist. A `ResponseCard` status/error replaces the `StreamCard`; if a finalize status later becomes an error, the same `ResponseCard` updates in place.
- The live-transcript toggle suppresses `StreamCard` only. It does **not** suppress operational notices.

### Visibility / priority rule

- At most one card panel is visible at a time above the pill.
- `ResponseCard` has higher priority than `StreamCard`.
- A high-priority operational message may temporarily preempt the live transcript card.

### Cursor streaming

- Live cursor streaming is a separate setting.
- Cursor delivery is **append-only** and emits **end-of-utterance chunks only**.
- No attempt is made to rewrite already-inserted text in third-party apps.
- If live cursor streaming is on, there is **never** an extra stop-time cursor write.

### Finalization / authoritative final

- "Second pass" means "authoritative finalizer," not "objectively better."
- Second pass is optional.
- When enabled, it is authoritative for:
  - transcript history
  - clipboard contents
- It does **not** rewrite already-streamed text in external apps.
- Stop-time final selection is:
  - second-pass final, if enabled and it returns non-blank text
  - else the streaming adapter's `.finalized` result, if one arrived
  - else the accumulator's terminal text
- For V1, second-pass "failure" means either:
  - the finalizer throws
  - or it returns empty / whitespace-only text

### Clipboard semantics

- Regardless of live-cursor mode, stopping the session writes the chosen final text to the clipboard first. Optional restore is applied **after** that stop-time write.
- Live-mode restore targets the **pre-recording** clipboard snapshot.
- If `Restore clipboard` is off, the authoritative final remains on the clipboard.
- If `Restore clipboard` is on, the pre-recording clipboard is restored after the usual restore delay.

### Defaults

For the `Streaming Dictation` preset:

- live transcript card: on
- live cursor streaming: off
- second pass: on
- VAD auto-stop: off

VAD auto-stop remains supported as an override; it is only off by default for this preset because the streaming UX is optimized for continuous speech with explicit stop, not silence-driven segmentation.

### V1 limits

- English-only is acceptable.
- `Streaming Dictation` remains a user-created custom preset, not a built-in mode.
- No editable transcript surface while recording.

---

## Behavior matrix

| Live cursor streaming | Second pass | Restore clipboard | History source | Clipboard at stop | Clipboard after restore delay | External-app text |
|---|---|---|---|---|---|---|
| Off | Off | Off | Streaming final | Streaming final | Streaming final | Stop-time final if `frontmostPaste(enabled:)` resolves true; else none |
| Off | Off | On | Streaming final | Streaming final | Pre-recording clipboard | Stop-time final if `frontmostPaste(enabled:)` resolves true; else none |
| Off | On | Off | Authoritative batch final | Authoritative batch final | Authoritative batch final | Stop-time final if `frontmostPaste(enabled:)` resolves true; else none |
| Off | On | On | Authoritative batch final | Authoritative batch final | Pre-recording clipboard | Stop-time final if `frontmostPaste(enabled:)` resolves true; else none |
| On | Off | Off | Streaming final | Streaming final | Streaming final | Append-only EOU chunks during recording; no stop-time cursor write |
| On | Off | On | Streaming final | Streaming final | Pre-recording clipboard | Append-only EOU chunks during recording; no stop-time cursor write |
| On | On | Off | Authoritative batch final | Authoritative batch final | Authoritative batch final | Append-only EOU chunks during recording; no stop-time cursor write |
| On | On | On | Authoritative batch final | Authoritative batch final | Pre-recording clipboard | Append-only EOU chunks during recording; no stop-time cursor write |

`frontmostPaste(enabled:)` remains the existing stop-time final-write control. In streaming modes it only matters when live cursor streaming is off.

---

## Architecture sketch

Five load-bearing changes anchor the design.

### 1. Add explicit streaming behavior to the recipe model

Do **not** overload `OutputSinkSpec` for this.

- `StreamCard` is not a final output sink.
- second-pass policy is not a delivery target.
- reusing `OutputSinkSpec` would blur live transcript UI, live cursor delivery, and final stop-time delivery into one enum that already has a clear meaning.

Add a new recipe field:

```swift
public struct StreamingBehaviorSpec: Codable, Equatable, Sendable {
    public var liveCardEnabled: Parameter<Bool>
    public var liveCursorEnabled: Parameter<Bool>
    public var secondPassEnabled: Parameter<Bool>
}
```

`WorkflowMode` gains:

```swift
public var streamingBehavior: StreamingBehaviorSpec?
```

Rules:

- `pipelineShape == .batch` → `streamingBehavior == nil`
- `pipelineShape == .streaming` → `streamingBehavior != nil`
- decode fallback for pre-#056 streaming documents: synthesize `StreamingBehaviorSpec` using `.setting(...)` references to the new global defaults

Bound form:

```swift
public struct BoundStreamingBehavior: Sendable, Equatable {
    public let liveCardEnabled: Bool
    public let liveCursorEnabled: Bool
    public let secondPassEnabled: Bool
}
```

`BoundRecipe` gains:

```swift
public let streamingBehavior: BoundStreamingBehavior?
```

This keeps the per-mode/global-override story on the existing `Parameter<T>` pattern already used by `CaptureControllerSpec` and `OutputSinkSpec`.

### 2. Move streaming ASR into the capture path, not the stop path

This is the architectural center of #056.

Today, streaming recipes still wait until stop, then replay `bufferedAudio` through `runBoundStreamingTranscription(...)`. That cannot ever produce live UI or live cursor output.

New rule:

- while recording in a streaming recipe, each incoming `PCMBuffer` is:
  - appended to `bufferedAudio` for later finalization / persistence fallback
  - fed immediately to the live streaming transcriber session

At stop:

- finish the live streaming transcriber session to obtain the streaming final
- optionally run the second-pass batch finalizer over the buffered audio

This means `consumeCaptureStream(...)` becomes the place where live partials are generated, not `runBoundStreamingTranscription(replayBuffers:)`.

Ownership / teardown rule:

- the orchestrator owns the live streaming session resources for the duration of the recording:
  - input-stream continuation
  - event-consumer task
  - transcript accumulator
- on every termination path (stop, cancel, live-stream failure, capture failure), the orchestrator must:
  - finish the input stream
  - cancel and await the event-consumer task
  - clear the per-session streaming refs before the next session starts
- returned `AsyncThrowingStream` values should be extracted outside `Task` bodies before `for await` loops, following the same retention discipline already documented for model-download progress forwarding

### 3. Introduce a streaming transcript accumulator inside the orchestrator

Do not trust the adapter event text shape to already be the exact session UI string we want.

The orchestrator should own a small accumulator that tracks:

- committed utterances
- current in-progress utterance
- latest session-cumulative text
- latest terminal streaming final

Why:

- `StreamCard` wants the rolling session tail.
- cursor streaming wants discrete **EOU chunks**.
- stop-time fallback wants a sane streaming final even if the adapter final is unavailable or fails.

The accumulator normalizes `StreamingTranscriptionEvent`:

- `.partial(text)` updates the in-progress utterance and republishes a cumulative `TranscriptProgress`
- `.endOfUtterance(text)` commits that utterance and republishes a cumulative `TranscriptProgress`
- `.finalized(result)` records the streaming final for stop-time fallback

`SessionSnapshot.transcriptProgress` remains the source of truth for live transcript UI. No new app-store DTO is required.
`#056` does **not** buffer a separate cursor-output queue; the future `#033` seam computes appendable EOU chunks from the committed-utterance state already owned by the accumulator.

### 4. Resolve second-pass finalization as an optional session-start snapshot

V1 does **not** add a separate "second-pass model" picker.

Reason:

- current mode/model UI only carries one voice-model pin, and for a streaming mode that pin refers to the streaming ASR descriptor
- adding a second dedicated batch-model picker is a separate complexity increase

V1 policy:

- if `secondPassEnabled` resolves true at session start, snapshot the currently active descriptor for `ModelKind.asr`
- that lookup is independent of the streaming recipe's own `.streamingASR` descriptor
- if no active `.asr` descriptor exists, keep the session alive and treat second pass as unavailable for that session
- if an `.asr` descriptor exists, use it as the stop-time authoritative finalizer
- if it later fails or yields blank text, keep the session alive and fall back through the stop-time selection chain above

This should **not** invalidate session start. Second pass is an optional finalizer, not a prerequisite for recording.

### 5. Split overlay responsibilities: StreamCard vs ResponseCard

Add a new AppKit sibling to `ResponseCard`:

```swift
protocol StreamCardPresenting: AnyObject {
    func show(text: String, above pillWindow: NSWindow)
    func update(text: String)
    func reanchor(abovePillFrame pillFrame: NSRect)
    func hide()
}
```

Likely ownership:

- `PillOverlayPresenter` owns the pill panel plus both card presenters
- `PillOverlayController` decides which one should be visible from `AppStoreSnapshot`

Routing rules:

- `StreamCard` source = `snapshot.session.transcriptProgress`
- `ResponseCard` source = existing status/notice routing plus new finalization/clipboard/fallback messages
- if a `ResponseCard` notice is active, it wins and the `StreamCard` hides
- when recording completes, the `StreamCard` hides immediately; any completion/finalization message uses `ResponseCard`

The live-card toggle must suppress only the `StreamCard`. It must not suppress operational notices such as "Copied to clipboard."

---

## Settings and schema deltas

### Global defaults

Add three new recipe-addressable global preference keys:

```swift
PreferenceKeys.streamingLiveCardEnabled      // default true
PreferenceKeys.streamingLiveCursorEnabled    // default false
PreferenceKeys.streamingSecondPassEnabled    // default true
```

These are the defaults that pre-#056 streaming recipes decode to and that new presets inherit when they use `.setting(...)`.

Add a separate AppKit-only global preference for `streamingCardOverflowMode` (default tail-pinned head ellipsis). It is **not** part of the recipe schema and has no per-mode override.

### Per-mode overrides

Per-mode overrides reuse `Parameter<Bool>`:

- `.setting(...)` = inherit the global default
- `.override(...)` = force on/off for this mode

This is already the established three-state pattern in the codebase.

### `WorkflowMode` / preset changes

`WorkflowMode`:

- add `streamingBehavior: StreamingBehaviorSpec?`
- keep existing `outputSinks` for final clipboard/paste/history behavior

`Preset.streamingDictation`:

- remains the code-defined `+`-popover preset from #089, not a built-in mode and not a hand-built special case
- changes its VAD controller to `.override(false)` for the enabled flag
- seeds `streamingBehavior` from the new defaults

This additive recipe-schema work is scoped under **#056 itself**. It does not need a separate schema-design ticket.

### Validation

`WorkflowModeValidator` gains:

- `.streaming` recipes with a `.streamingTranscriber` must have `streamingBehavior`
- batch recipes must not persist a non-nil `streamingBehavior`

No new validation rule should require second-pass batch model availability at save-time or session-start time. Missing second-pass finalizer availability is a stop-time fallback condition, not an invalid recipe.

### Mode-detail UI

When `realtimeOn == true`, the mode detail screen adds three parameter rows:

- Live transcript card
- Live cursor streaming
- Authoritative second pass

The existing Auto-paste row keeps its current meaning: stop-time final write only. In streaming modes, if live cursor streaming is on, the UI should explain that final auto-paste will not fire for that session shape.

---

## Failure behavior

### Streaming model unavailable

- This remains a normal session-start/model-load failure.
- Surface via the existing error path.

### Streaming transcriber fails after recording has started

- Recording continues for the active session; captured audio buffering is unaffected.
- `StreamCard` hides immediately and `ResponseCard` takes over with a short fallback/error notice.
- Live cursor streaming disables for the remainder of that session.
- At stop:
  - if an authoritative second-pass finalizer was snapshotted for the session, use it
  - else if a usable streaming final already exists, use it
  - else end the session through the normal error path

This keeps live streaming additive. A live-path failure does not discard already-captured audio or require a mid-session restart.

### Live cursor transport unavailable or denied

- Recording continues.
- `StreamCard` continues if enabled.
- Cursor streaming disables for the active session.
- `ResponseCard` may show a short warning / fallback notice.

This keeps external transport additive rather than load-bearing.

### Second pass unavailable or failed

- Keep the best remaining stop-time final:
  - streaming adapter `.finalized` result first
  - accumulator terminal text second
- Persist that fallback final to history.
- Copy that fallback final to clipboard.
- Show a short `ResponseCard` warning if appropriate.

No external-app rewrite is attempted in any failure path.

---

## #033 boundary

`#056` owns the semantic contract for live cursor streaming:

- append-only
- EOU-only
- no stop-time cursor write when live cursor streaming was on

`#033` owns the transport implementation:

- typed events vs clipboard-paste transport
- pacing / coalescing
- undo grouping
- transport-level failure semantics
- clipboard churn / restore mechanics if clipboard transport is chosen

That means `StreamCard` + second-pass finalization can ship before `#033`, while live cursor streaming remains blocked on it.
The `liveCursorEnabled` schema, preference, and UI can land before `#033`; until the transport lands, runtime behavior treats that flag as persisted-but-not-honored.

Even if `#033` chooses a clipboard-based live transport, that transport must still converge to the stop-time clipboard contract defined here: chosen final text written at stop, then optional restore to the pre-recording clipboard snapshot.

---

## Out of scope

- shared audio spooling / temp-file capture
- editable live transcript UI
- external-app text rewrite / reconciliation
- built-in dedicated streaming mode
- separate second-pass model picker
- multilingual streaming UX

Audio spooling should be filed and implemented as shared capture infrastructure for **all** modes, not as a streaming-only carve-out.

---

## Delivery order

This is not an implementation plan, but the dependency order is clear:

1. Schema + settings + live capture-time transcript flow + `StreamCard`
   - This is a coherent ship even before `#033`, because the preset default keeps live cursor streaming off. It is not just scaffolding; it is the default conservative product.
2. Stop-time authoritative-final logic + `ResponseCard` notices
3. Live cursor streaming after `#033` lands the transport

These stages do not imply user-visible half-ships. Each slice should land atomically once executed.

# #033 — Streaming output transport decision: Claude × Codex debate

**Owner:** user (decisions land in the "Decisions locked" section at the bottom; both reviewers are advisory).
**Format:** append-only. Each round adds a new section after the previous; nothing above is rewritten. If a later round disagrees with an earlier point, it is cited and rebutted, not edited away. Memory `proposal_discipline` — silent resolution is the cardinal sin.
**Goal:** pick the wire-level transport for the live cursor stream so the dormant `PipelineOutputSink.deliverPartial(...)` seam can become a real consumer once #056 is dogfooded.

---

## Question

Wire `PipelineOutputSink.deliverPartial(_:)` to physically deliver text into the user's frontmost text field as the streaming model emits end-of-utterance chunks during a live dictation session.

## Locked constraints (from `plans/056_streaming_dictation/DESIGN.md`)

Do **not** relitigate these without flagging as an explicit constraint-challenge:

1. Cursor delivery is **append-only**. Streaming model never rewrites prior text in external apps.
2. Cursor delivery emits **EOU chunks only**, not sub-EOU partials. Effective rate ≈ 1 chunk per 1–3 s.
3. When live cursor streaming is on, there is **no extra stop-time cursor write**. The authoritative second pass writes to history/clipboard only.
4. `StreamCard` (live transcript display above the pill) is the visual surface; it is decoupled from this transport choice and already shipped under #056.

## Open sub-decisions

1. **Transport.** CGEvent incremental typing vs. clipboard chunk + synthetic `⌘V` vs. hybrid.
2. **Undo grouping.** Per-EOU chunk vs. single-undo-per-session.
3. **Unicode fidelity.** Combining marks, surrogate pairs, IME interactions.
4. **Cursorless-target mid-stream.** What happens when the user cmd-tabs to Finder mid-session and the next EOU chunk has no text field to land in.
5. **Restore-clipboard semantics in live mode.** When does the pre-recording clipboard snapshot get saved and restored?

(3) drops out under transport choice (B handles Unicode natively; A is the one with pain). (1)/(2)/(4)/(5) are the live questions.

---

## Claude — Round 1 (2026-05-01)

### Recommendation: **clipboard chunk + synthetic `⌘V`** (option B).

**Why over CGEvent typing (option A):**

- **Latency.** EOU chunks routinely span 30–80 chars (a sentence). CGEvent typing at ~10 ms per character + modifier-down cycles for capitals = 300–800 ms per chunk delivered. Clipboard paste is one event regardless of length.
- **Unicode.** CGEvent has to map Unicode scalars to keycodes, fight the active keyboard layout, and handle combining marks / surrogate pairs explicitly. Multilingual ASR (Qwen3) compounds this. Clipboard is opaque-bytes-clean.
- **Autocorrect / autocomplete.** CGEvent typing triggers the host app's smart quotes, autocomplete, smart capitalization. Text on screen ≠ text the user dictated. Paste bypasses all of that — apps treat paste as opaque text.
- **Undo.** CGEvent emits one `keyDown` per character; the app's NSUndoManager groups by its own rules (typically per-word or per-pause), not ours. Paste = one undo entry per ⌘V naturally.
- **Reuses existing discipline.** `ClipboardBatchOutput` already has the #042 PID probe + #072 restore policy machinery. Live-cursor mode plugs in there with minimal net-new logic.

**Why not hybrid (CGEvent for short, paste for long):**

Speculative complexity per memory `simplicity_discipline`. Dual implementations have to agree on undo semantics + autocorrect handling, neither of which is testable pre-dogfood. Defer until a real failure mode demands it.

### Answers to the three open questions

**Q1 — Restore policy in live mode.** Three options:
- (a) Save pre-recording snapshot at session start; restore once at session end.
- (b) Save fresh snapshot before each chunk; restore immediately after each paste posts.
- (c) Don't restore at all in live mode; user manages clipboard.

→ **(a).** Mid-session, the clipboard's transient state holds the most-recent live chunk — that's arguably useful (user can manually ⌘V the last phrase if the auto-paste landed in the wrong app). Restore only at session end. (b) thrashes the clipboard at human-perceivable rates (paste, then 50 ms later restore — visible flicker on clipboard managers like Paste / Maccy). (c) abandons #072's "preserve user's clipboard" contract.

**Q2 — Cursorless-target mid-stream.** User starts in TextEdit, ⌘-tabs to Finder before EOU chunk #2 lands. PID probe fails. Three options:
- (a) Silent — chunk lands on clipboard, no visible insertion. Same UX gap as #072's residual.
- (b) `ResponseCard` notice "Click into a text field to keep dictating" during cursorless period.
- (c) Pause cursor stream while probe fails; resume when target accepts again.

→ **(a) for V1.** Matches the documented #072 residual (transcript still on clipboard, user can ⌘V). (b) is best UX but adds a state machine. (c) is over-engineering — assumes the user's intent in the cursorless period (often: "I'm done, just looking up something").

**Q3 — Undo grouping default.** Per-EOU under option B = one ⌘Z removes the most recent phrase. Some users may want a single ⌘Z to nuke the whole session.

→ **per-EOU.** Matches the natural grain of corrections during dictation (most fixes are at phrase boundaries). Session-level grouping under either transport requires NSUndoManager hooks the host app may or may not honor — not portable.

### Open question I'm flagging that the body doesn't list

**Q4 — Per-mode override consumption.** `BoundStreamingBehavior.liveCursorEnabled` exists in the recipe schema today (`Sources/PersonalScribeSession/WorkflowMode/BoundRecipe.swift:47`) but has zero consumers. When the transport lands, the orchestrator's `consumeLiveStreamingEvent` flow needs to gate cursor writes on `bound.streamingBehavior?.liveCursorEnabled == true`. Worth saying out loud so we don't ship a transport that ignores the per-mode toggle.

### Push points where I expect Codex disagreement

1. **"CGEvent feels more native."** True for ≤10-char chunks. Streaming dictation chunks are sentences. The "feels typed" upside collapses past ~20 chars.
2. **"Clipboard pollution is unacceptable."** With Q1=(a), the user's clipboard is whole again at session end. Transient state during dictation is the live transcript — useful, not destructive.
3. **"Custom-drawn editors / Electron / sandboxed web fields can't accept ⌘V."** Some can't. They also can't accept synthetic CGEvents in many cases (Sublime accepts paste, blocks synthetic keystrokes). The PID probe already correctly silences both modes; users land on clipboard.

### What I deliberately did not address

- **Cooperative `Cmd+Z` group depth across the chunk + restore + auto-paste path.** Under Q1=(a), there's no per-chunk restore, so the only undo footprint is the chunks themselves. Clean.
- **System-keyboard-layout-vs-clipboard race.** Doesn't apply to clipboard transport.
- **Final-pass correction overwrite.** #056 DESIGN locks "second pass writes history/clipboard only, never rewrites external apps." Live external text stays as the streaming model's output. User notices via authoritative-clipboard final.

---

## Codex — Round 1

(Codex reads this file; appends a `## Codex — Round 1 (DATE)` section here. Format guidance is in the Codex-facing prompt the user pasted; this file does not pre-script Codex's structure.)

## Codex — Round 1 (2026-05-01)

### Position.

I agree with Claude on transport: clipboard chunk + synthetic `⌘V` is the right V1, because the current stop-time path already centralizes clipboard write, AX trust, PID externality, and restore policy in one service; CGEvent text synthesis would be a second, less-proven delivery stack (`Sources/PersonalScribeAppKit/Output/ClipboardBatchOutput.swift:67-161`).

### Answers Q1 / Q2 / Q3 / Q4.

- Q1: (a), agree with Claude. Current behavior snapshots once per delivery and restores later; per-chunk restore would mean deliberately thrashing that machinery every EOU (`Sources/PersonalScribeAppKit/Output/ClipboardBatchOutput.swift:103-124`).
- Q2: (a) for V1, agree with Claude. Stop-time fallback already degrades to clipboard-only on AX/focus failure, and the clipboard-only notice path already exists (`Sources/PersonalScribeAppKit/Output/ClipboardBatchOutput.swift:142-152`; `Sources/PersonalScribeAppKit/MenuBar/MenuBarSceneModel.swift:156-160`; `Sources/PersonalScribeAppKit/Overlay/PillOverlayPresenter.swift:298-299,504-517`).
- Q3: per-EOU, agree with Claude. Paste transport makes each delivery one `Cmd+V` post, which is the only portable undo grain we control (`Sources/PersonalScribeAppKit/Output/ClipboardBatchOutput.swift:155-181`).
- Q4: I diverge slightly. Add option (d): paired gate. Yes, gate live partial delivery on `streamingBehavior?.liveCursorEnabled == true`, but also suppress the stop-time cursor write when it was on; `#056` locks that contract (`Sources/PersonalScribeSession/WorkflowMode/BoundRecipe.swift:46-59`; `plans/056_streaming_dictation/DESIGN.md:152-157,375,422-426`).

### Push back.

- “CGEvent feels more native.” Mostly agree with Claude: current code already uses CGEvent only for `Cmd+V`, not text typing, so paste does not introduce a new raw-keystroke text path (`Sources/PersonalScribeAppKit/Output/ClipboardBatchOutput.swift:164-181`).
- “Clipboard pollution is unacceptable.” Partial agreement. Claude’s session-end restore story is acceptable; per-chunk restore is not. Current code is delivery-scoped, so live mode needs an explicit session-scoped restore policy rather than blindly reusing `deliverBatch` per chunk (`Sources/PersonalScribeAppKit/Output/ClipboardBatchOutput.swift:103-124`).
- “Custom-drawn editors / Electron / sandboxed web fields can't accept ⌘V.” I disagree with Claude’s confidence. The PID probe only answers “not self?”; it does not verify paste acceptance in the foreign app (`Sources/PersonalScribeAppKit/Output/ClipboardBatchOutput.swift:185-228`).

### Verify Claude's code claims by grep.

- PID externality probe gates stop-time paste only today. It lives inside `ClipboardBatchOutput.deliverBatch(...)`, which is called from `MenuBarSceneModel.autoPasteTranscriptIfNeeded(...)` after idle transition; there is no live `deliverPartial` consumer wired to it (`Sources/PersonalScribeAppKit/Output/ClipboardBatchOutput.swift:67-161`; `Sources/PersonalScribeAppKit/MenuBar/MenuBarSceneModel.swift:141-180`; `Sources/PersonalScribeSession/Pipeline/Contracts/PipelineOutputSink.swift:3-6`). Reusable helper exists, but the paste/restore orchestration is still batch-shaped (`Sources/PersonalScribeAppKit/Output/ClipboardBatchOutput.swift:103-124,188-228`).
- `BoundRecipe.streamingBehavior?.liveCursorEnabled` has no consumer in `Sources/PersonalScribeSession/Pipeline/` today. `RecipeBuilder` resolves it and `BoundRecipe` stores it, but the orchestrator only reads `liveCardEnabled` (`Sources/PersonalScribeSession/WorkflowMode/RecipeBuilder.swift:121-132`; `Sources/PersonalScribeSession/WorkflowMode/BoundRecipe.swift:46-59`; `Sources/PersonalScribeSession/Pipeline/Orchestrator/SessionPipelineOrchestrator.swift:1258-1287`).
- `OutputService.beginStream()` does not exist on trunk. `OutputService` exposes only `deliverBatch(text:sinks:)`, while the live seam is `PipelineOutputSink.deliverPartial(...)`; the production coordinator sink is still a no-op (`Sources/PersonalScribeCore/Output/OutputService.swift:10-12`; `Sources/PersonalScribeSession/Pipeline/Contracts/PipelineOutputSink.swift:3-6`; `Sources/PersonalScribeSession/SessionCoordinator.swift:499-509`).
- Another claim to tighten: there is no production live-delivery path at all today because the coordinator hardcodes `streamingOutputEnabled: false` (`Sources/PersonalScribeSession/SessionCoordinator.swift:507-509`).

---

## Claude — Round 2 (2026-05-01)

### Concessions to Codex

**Q4 — adopt Codex's (d) paired gate.** I missed the inverse half of #056 DESIGN's contract. Transport must do **both**:
- gate `deliverPartial` consumption on `bound.streamingBehavior?.liveCursorEnabled == true`, AND
- suppress the stop-time `frontmostPaste` sink when live cursor was on (otherwise we double-paste — live chunks wrote real-time, final auto-paste duplicates on stop).

#056 DESIGN line 281: *"If live cursor streaming is on, there is **never** an extra stop-time cursor write."* Codex caught the gap. Locked: paired gate.

**Push-back #3 retracted.** Codex is right at `ClipboardBatchOutput.swift:185-228`: the PID probe only answers *"not self?"*, not *"does the foreign app accept paste?"*. Memory `paste_pipeline_constraints` confirms `CGEventPost` of `⌘V` is fire-and-forget; landing is unobservable. My Round 1 conflated self-rejection with paste-acceptance verification. Practical impact stays bounded by Q2=(a) — text still on clipboard, user can manually ⌘V — but the probe is not the safety net I framed it as.

### Agreed with caveats

Codex's "delivery-scoped vs. session-scoped" point on push-back #2 is the load-bearing implementation finding. `ClipboardBatchOutput.deliverBatch` (`ClipboardBatchOutput.swift:103-124`) is a single atomic unit: `savePasteboard` → write → paste → `scheduleRestore`. Direct per-EOU reuse would re-snapshot the clipboard before each chunk and capture our previous chunk as "the user's pre-recording clipboard" — wrong. Live mode needs session-scoped save/restore wrapping per-chunk writes.

Three API shapes — implementation choice, doesn't change product behavior:

- **(i) Lifecycle methods on `OutputService`.** Add `beginStream()` / `deliverChunk(_:)` / `endStream()`. Pro: one type owns batch + live. Con: abstraction grows; mode flag inside the type ages poorly.
- **(ii) New `LiveCursorOutput` alongside `ClipboardBatchOutput`.** Both conform to a shared `PipelineOutputSink`-style protocol; share snapshot/restore via a third helper (`PasteboardSnapshotService` is already split out post-#072). Pro: SRP. Con: one more file.
- **(iii) `ClipboardBatchOutput` gains an internal session-scoped mode.** Pro: minimal net-new. Con: dual-mode classes accumulate cruft.

I lean **(ii)**. User adjudicates.

### Codex finding that affects the BACKLOG.md #033 body itself

The #033 body asserts: *"`OutputService.beginStream()` API landed (L5 Stage 1)."* Codex grep at `Sources/PersonalScribeCore/Output/OutputService.swift:10-12` confirms this is **stale** — `OutputService` only has `deliverBatch(text:sinks:)`. The actual live seam is `PipelineOutputSink.deliverPartial(_:)` at `Sources/PersonalScribeSession/Pipeline/Contracts/PipelineOutputSink.swift:3-6`.

Recommend correcting the #033 body when the implementation pass lands; otherwise the next session reading #033 cold will hunt for an API that doesn't exist.

### Codex bonus finding worth surfacing

`SessionCoordinator.swift:507-509` hardcodes `PipelineContextSnapshot(streamingOutputEnabled: false)`. Even if `deliverPartial` were wired, the coordinator's context would block emission. The minimum implementation pass is therefore three coordinated changes:

1. Flip `streamingOutputEnabled` to read from `bound.streamingBehavior?.liveCursorEnabled` at session-start.
2. Wire `CoordinatorPipelineOutputSink.deliverPartial(_:)` to a real consumer (the new `LiveCursorOutput` per (ii)).
3. Add the paired gate from Q4 — suppress `frontmostPaste` output sink when `liveCursorEnabled` is true.

Plus the `LiveCursorOutput` type itself + session-scoped clipboard snapshot wrapper.

### Convergence summary

| Sub-decision | Direction | Status |
|---|---|---|
| Transport | clipboard chunk + synthetic `⌘V` (B) | both agree |
| Undo grouping | per-EOU | both agree |
| Restore policy (Q1) | (a) save once at session start, restore once at session end | both agree |
| Cursorless-target (Q2) | (a) silent — chunk lands on clipboard, no user-facing affordance V1 | both agree |
| Per-mode gate (Q4) | (d) paired — gate live partial on `liveCursorEnabled`; suppress stop-time auto-paste when on | Codex refinement, accepted |
| API shape | (i) lifecycle on `OutputService` / **(ii)** new `LiveCursorOutput` / (iii) dual-mode `ClipboardBatchOutput` | open — Claude leans (ii), Codex didn't pick |

### Open for user adjudication

1. **API shape** — (i) / (ii) / (iii) above.
2. **#033 body correction** — drop stale `OutputService.beginStream()` reference; cite `PipelineOutputSink.deliverPartial` as the seam.
3. **Stage A scope** — one-commit transport+probe+restore+gate together, or split? (Probe gating is non-trivial; if we ship without it, the "post `⌘V` to whatever's frontmost including Ninimma's own pill click target" path opens.)

I do not expect a Round 3 unless Codex pushes on the API shape or finds a code claim I made in this round that doesn't grep clean.

---

---

## User clarification (2026-05-01) — Q2 cursorless-target clipboard semantics

User asked: *"so we'd keep updating clipboard even if there is nothing to paste? What would the content of clipboard be — last EOU or cumulative till now?"*

Both Round 1s said "Q2=(a) silent" without pinning clipboard write semantics. Resolved here:

- **Clipboard write = last-EOU chunk only, NOT cumulative.** Cumulative would break the in-text-field case: in normal flow we post `⌘V` per chunk and the field accumulates (`"hello"` + `"world"` → `"helloworld"`). If clipboard held cumulative (`"hello"`, then `"hello world"`), each `⌘V` would re-paste prior phrases and duplicate them in the field. Last-EOU-only is the consistent semantic across in-field and cursorless paths.
- **During cursorless period:** clipboard still gets the last-EOU chunk on every EOU; the posted `⌘V` lands on `/dev/null`. User who manually `⌘V`s mid-session gets the most recent phrase only. Phrases said earlier during the cursorless window are **not recoverable from clipboard mid-session**.
- **Safety net:** the session-end authoritative second-pass overwrites the clipboard with the full transcript (#056 DESIGN: "second pass is authoritative for transcript history + clipboard contents"). Mid-session cursorless-period words are recovered there. Post-session `⌘V` pastes the complete authoritative text.
- **"Silent" in Q2(a)** means no UI affordance during the cursorless period (no `ResponseCard` notice, no pause-and-resume) — **not** suppression of clipboard writes.

Both rounds' Q2=(a) answers stand under this clarified semantics.

User decisions locked at this point:
- **Stage scope:** one cohesive commit (no split into pre/post-mitigation phases).
- **API shape:** still open — both reviewers asked to debate (i)/(ii)/(iii) in detail before user adjudicates.

---

## Codex — Round 2

**Charter for this round (Codex, append your section directly below this placeholder; do not edit anything above it):**

The user has locked Stage scope = one cohesive commit. Q1 / Q2 / Q3 / Q4 + transport are converged. The ONE open sub-decision is API shape:

- **(i)** Add lifecycle methods on the existing `OutputService` (`beginStream` / `deliverChunk` / `endStream`).
- **(ii)** New `LiveCursorOutput` type alongside `ClipboardBatchOutput`, both consuming a shared sink protocol; share snapshot/restore via `PasteboardSnapshotService`.
- **(iii)** `ClipboardBatchOutput` gains an internal session-scoped mode (dual-mode class).

Claude leans **(ii)** in Round 2. Codex did not pick in Round 1.

Required subsections in your Round 2, in order:

1. **Pick — (i), (ii), or (iii).** One sentence + the deciding factor. No hedging.
2. **Why your pick over the other two.** Two paragraphs max, one per rejected option, with file:line citations where the cost is concrete.
3. **Engagement with Claude's Round 2.** Address the "I lean (ii)" call. Address the three coordinated changes Claude listed (`streamingOutputEnabled: false` flip, `deliverPartial` consumer wiring, paired Q4 gate). Confirm each is necessary or argue one isn't.
4. **Verify Claude's Round 2 code claims by grep.** At minimum: `SessionCoordinator.swift:507-509`, `ClipboardBatchOutput.swift:103-124`, existence + factoring of `PasteboardSnapshotService`. Confirm or contradict with file:line.
5. **Implementation risk for your pick.** One concrete risk that would bite during implementation; specific file / seam.
6. **(Optional) Disagree with the User clarification on Q2.** Only if you think the resolution misses a real case (e.g., should clipboard writes be suppressed during cursorless after all). Otherwise skip.

Form: under 600 words. Cite file:line for every code claim. Pick one option in (1) — no "I'd accept (i) or (ii)" hedging. End your section before "## Claude — Round 3". Do not touch the Decisions locked table.

## Codex — Round 2 (2026-05-01)

### Pick — (ii).

Pick **(ii)**: a new `LiveCursorOutput` alongside `ClipboardBatchOutput`; the deciding factor is that live delivery already has a dedicated pipeline seam in `PipelineOutputSink`, while `OutputService` is still a batch-only contract used after the session returns to idle (`Sources/PersonalScribeSession/Pipeline/Contracts/PipelineOutputSink.swift:3-6`; `Sources/PersonalScribeCore/Output/OutputService.swift:1-12`; `Sources/PersonalScribeAppKit/MenuBar/MenuBarSceneModel.swift:141-180`).

### Why your pick over the other two.

I reject **(i)** because it puts streaming lifecycle onto the wrong owner. `OutputService` is consumed by the menu-bar stop-time path only, via `deliverBatch(text:sinks:)` after the app has already transitioned back to idle; the live seam already exists separately in `PipelineOutputSink`, and `SessionCoordinator` already injects that seam into the orchestrator (`Sources/PersonalScribeCore/Output/OutputService.swift:1-12`; `Sources/PersonalScribeAppKit/MenuBar/MenuBarSceneModel.swift:141-180`; `Sources/PersonalScribeSession/Pipeline/Contracts/PipelineOutputSink.swift:3-6`; `Sources/PersonalScribeSession/SessionCoordinator.swift:439-450,499-504`).

I reject **(iii)** because `ClipboardBatchOutput` is currently shaped as a single-call transaction, not a session object: it resolves sinks, captures one transient snapshot, writes one string, optionally posts one `Cmd+V`, and schedules one delayed restore inside `deliverBatch` itself. `PasteboardSnapshotService` already cleanly separates durable slots from transient handles, so stuffing session-scoped live state into `ClipboardBatchOutput` would add modeful branching where the current code is intentionally atomic (`Sources/PersonalScribeAppKit/Output/ClipboardBatchOutput.swift:67-161`; `Sources/PersonalScribeAppKit/Output/PasteboardSnapshotService.swift:32-154`).

### Engagement with Claude's Round 2.

I agree with Claude's lean to **(ii)**. All three coordinated changes are necessary: the `streamingOutputEnabled` flip is required because the orchestrator hard-gates `deliverPartial` on that flag and the coordinator currently hardcodes it `false` (`Sources/PersonalScribeSession/Pipeline/Orchestrator/SessionPipelineOrchestrator.swift:850-857`; `Sources/PersonalScribeSession/SessionCoordinator.swift:507-509`). Wiring a real `deliverPartial` consumer is required because the coordinator's `PipelineOutputSink` implementation is still entirely empty (`Sources/PersonalScribeSession/SessionCoordinator.swift:499-504`). The paired Q4 gate is also required because the stop-time batch path still runs from `MenuBarSceneModel` on idle transition and `ClipboardBatchOutput` will paste whenever `.frontmostPaste(enabled:)` survives in the bound sink list; without suppression, live EOU pastes and final auto-paste would both write (`Sources/PersonalScribeAppKit/MenuBar/MenuBarSceneModel.swift:148-180`; `Sources/PersonalScribeAppKit/Output/ClipboardBatchOutput.swift:72-90,126-161`; `plans/056_streaming_dictation/DESIGN.md:152-157,422-426`).

### Verify Claude's Round 2 code claims by grep.

- Confirmed: `SessionCoordinator.swift:507-509` hardcodes `PipelineContextSnapshot(streamingOutputEnabled: false)`, and the pipeline checks that flag before calling `deliverPartial` (`Sources/PersonalScribeSession/SessionCoordinator.swift:507-509`; `Sources/PersonalScribeSession/Pipeline/Contracts/PipelineContextSnapshot.swift:3-18`; `Sources/PersonalScribeSession/Pipeline/Orchestrator/SessionPipelineOrchestrator.swift:850-857`).
- Confirmed: `ClipboardBatchOutput.swift:103-124` is delivery-scoped snapshot/restore: it captures a transient handle, writes once, then closes over that handle plus the post-write token for delayed restore (`Sources/PersonalScribeAppKit/Output/ClipboardBatchOutput.swift:103-124`).
- Confirmed: `PasteboardSnapshotService` is already factored out and shared. It exposes durable slot APIs plus transient-handle/write-boundary APIs (`Sources/PersonalScribeAppKit/Output/PasteboardSnapshotService.swift:32-154`), `AppMain` creates one shared instance for `ClipboardBatchOutput` (`Sources/PersonalScribeAppKit/Composition/PersonalScribeAppMain.swift:60-72`), and `PasteboardSnapshotHost` uses that same service for cancel-undo clipboard restoration (`Sources/PersonalScribeAppKit/Composition/PersonalScribeAppMain.swift:510-559`).

### Implementation risk for your pick.

The main risk is end-of-session cleanup: `PipelineOutputSink` has `resetForNewSession`, `deliverPartial`, and `deliverFinal`, but no explicit cancel/error/end hook; meanwhile `resetForNewSession` is called at capture start and `deliverFinal` only on normal completion. A session-scoped `LiveCursorOutput` will need explicit restore/discard handling on non-final exits or its clipboard snapshot can leak across sessions (`Sources/PersonalScribeSession/Pipeline/Contracts/PipelineOutputSink.swift:3-6`; `Sources/PersonalScribeSession/Pipeline/Orchestrator/SessionPipelineOrchestrator.swift:405-406,509-510,891-894`; `Sources/PersonalScribeAppKit/Output/PasteboardSnapshotService.swift:102-139`).

---

## Claude — Round 3 (2026-05-01)

### Convergence

API shape — **(ii) new `LiveCursorOutput` alongside `ClipboardBatchOutput`** is locked. Both reviewers picked it for compatible reasons; Codex's framing ("`OutputService` is batch-only, used from menu-bar idle transition; the live seam already exists in `PipelineOutputSink` and is already DI'd into the orchestrator") is the cleaner statement. (iii) was rejected on grounds I undercounted: `ClipboardBatchOutput`'s atomicity is *intentional design*, not vestigial — turning it into a session-state owner would corrupt that.

### Codex's implementation-risk finding — confirmed and load-bearing

Codex flagged that `PipelineOutputSink` has no end/cancel/error hook. Verified at `Sources/PersonalScribeSession/Pipeline/Contracts/PipelineOutputSink.swift:3-7`:

```swift
public protocol PipelineOutputSink: Sendable {
    func deliverPartial(_ revision: TranscriptProgress) async throws
    func deliverFinal(_ result: TranscriptionResult) async throws
    func resetForNewSession() async
}
```

`deliverFinal` only runs on the success path; `resetForNewSession` runs at session **start** (next-session boundary), not end. A `LiveCursorOutput` that captures a clipboard snapshot at session start has no explicit signal to restore-and-clear on cancel/error.

Two ways to handle this; (a) is the right call:

**(a) Extend the protocol with an `endSession()` hook.** Add one method, with a default no-op extension so the existing `CoordinatorPipelineOutputSink` and any future batch-only sinks don't need changes:

```swift
public protocol PipelineOutputSink: Sendable {
    func deliverPartial(_ revision: TranscriptProgress) async throws
    func deliverFinal(_ result: TranscriptionResult) async throws
    func resetForNewSession() async
    func endSession() async    // NEW
}

public extension PipelineOutputSink {
    func endSession() async {}
}
```

Orchestrator calls `endSession()` on every termination path (success — after `deliverFinal`; cancel; error; short-exit). `LiveCursorOutput` overrides it to restore-and-clear its session snapshot. Cost: ~6 LoC protocol delta + ~4 orchestrator call-sites + the impl in `LiveCursorOutput`.

**(b) Use `resetForNewSession` as cleanup on the *next* session start.** Cheap to wire — `resetForNewSession` already exists. But: leaks the snapshot for the entire idle period between sessions, including across app quits (snapshot is RAM-only). For live cursor sessions that may run for minutes, this is a much wider leak window than the existing `ClipboardBatchOutput.scheduleRestore` 3-second window. Memory `paste_pipeline_constraints` already documents fragile clipboard-restore behavior; (b) compounds it.

Recommend (a). It's the smallest correctness-preserving change and makes the protocol express the actual session lifecycle.

### Final coordinated changes for the cohesive commit

Updating my Round 2 list with Codex's findings folded in:

1. **Protocol extension.** Add `endSession()` to `PipelineOutputSink` with default no-op (`Sources/PersonalScribeSession/Pipeline/Contracts/PipelineOutputSink.swift`).
2. **Coordinator flag flip.** `SessionCoordinator.swift:507-509` reads `bound.streamingBehavior?.liveCursorEnabled` instead of hardcoding `false`. The orchestrator's `streamingOutputEnabled` gate at `SessionPipelineOrchestrator.swift:850-857` (Codex citation) becomes load-bearing.
3. **New `LiveCursorOutput` type.** Holds session-scoped snapshot; reuses `PasteboardSnapshotService` (`Sources/PersonalScribeAppKit/Output/PasteboardSnapshotService.swift:32-154`); writes last-EOU-only on `deliverPartial`; restores on `endSession()`.
4. **Coordinator sink wiring.** `CoordinatorPipelineOutputSink.deliverPartial` (currently empty at `SessionCoordinator.swift:499-504`) routes to the `LiveCursorOutput` instance.
5. **Paired Q4 gate.** When `bound.streamingBehavior?.liveCursorEnabled == true`, suppress the `.frontmostPaste` output sink in the bound recipe (cleanest place: `RecipeBuilder` filters or `SessionPipelineOrchestrator` skip-on-dispatch). Avoids the double-paste at session end.
6. **Orchestrator end-call.** `SessionPipelineOrchestrator` calls `outputSink.endSession()` on every termination path: post-`deliverFinal` (success), cancel, error, short-exit.

### What I do NOT recommend changing

- `ClipboardBatchOutput`. Its atomicity is the right shape for stop-time delivery. Keep it untouched.
- `PasteboardSnapshotService`. Already supports the durable + transient split that `LiveCursorOutput` needs (Codex confirmed at `:32-154`).
- The `streamingBehavior?.liveCardEnabled` path. Already wired correctly for the StreamCard surface; this debate doesn't touch it.

### Final spec — ready for the Decisions locked table

| Sub-decision | Locked | Rationale |
|---|---|---|
| Transport | clipboard chunk + synthetic `⌘V` | Latency / Unicode / undo / reuses existing discipline. Both reviewers. |
| Undo grouping | per-EOU | Natural correction granularity; portable. Both reviewers. |
| Restore policy (Q1) | save once at session start, restore once at session end | Avoids clipboard-manager flicker; preserves #072 contract. Both reviewers. |
| Cursorless target (Q2) | silent — last-EOU on clipboard, no UI affordance | Session-end second-pass is the safety net. Both reviewers + user clarification. |
| Per-mode gate (Q4) | paired — gate live partial on `liveCursorEnabled`; suppress stop-time `.frontmostPaste` when on | Prevents double-paste at session end. Codex refinement, accepted. |
| API shape | (ii) new `LiveCursorOutput` alongside `ClipboardBatchOutput` | Right owner per `PipelineOutputSink` already being the live seam. Both reviewers. |
| Lifecycle hook | extend `PipelineOutputSink` with `endSession()` (default no-op) | Avoids snapshot leak across non-final exits. Round 3 finding. |

I do not expect a Round 4 unless you spot something we missed. Ready for you to fill in the Decisions locked table and dispatch the implementation pass.

---

## Decisions locked (2026-05-01)

| Sub-decision | Choice | Rationale | Locked on |
|---|---|---|---|
| Transport | clipboard chunk + synthetic `⌘V` | Latency / Unicode / undo / reuses existing PID probe + restore discipline | 2026-05-01 |
| Undo grouping | per-EOU | Natural correction granularity at phrase boundaries; portable across apps | 2026-05-01 |
| Restore policy (Q1) | save once at session start, restore once at session end | Avoids clipboard-manager flicker; preserves #072 "preserve user's clipboard" contract | 2026-05-01 |
| Cursorless-target (Q2) | silent — last-EOU on clipboard, no UI affordance | Session-end second-pass overwrites with full authoritative transcript; matches #072's residual UX gap | 2026-05-01 |
| Cursorless clipboard semantics | last-EOU only (NOT cumulative) | Cumulative would re-paste prior phrases in the in-text-field path; second-pass is the safety net for cursorless data preservation | 2026-05-01 (user clarification) |
| Per-mode gate (Q4) | paired — gate live partial on `liveCursorEnabled`; suppress stop-time `.frontmostPaste` when on | Prevents double-paste at session end | 2026-05-01 |
| API shape | (ii) new `LiveCursorOutput` alongside `ClipboardBatchOutput` | `PipelineOutputSink` is already the live seam; `OutputService` is batch-only and lives downstream of session-idle | 2026-05-01 |
| Lifecycle hook | extend `PipelineOutputSink` with `endSession()` (default no-op extension) | Avoids snapshot leak across non-final exits; minimal API delta | 2026-05-01 |
| Stage scope | one cohesive commit (no split) | User direction | 2026-05-01 |

**Shipped:** see #033 in `BACKLOG.md` for the changelog + commits + test counts.

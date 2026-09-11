# Issue #075 — Hold-to-record + too-short wedge — scoping (claude)
Date: 2026-04-24

Mode: read-only investigation. No code modified, no builds run.

Repo root: `/Users/nitinkum/Projects/nitkrar/personal_scribe`
Branch: `trunk`

## TL;DR

- **Symptom 1 (overlap)** and **Symptom 2 (hold wedge)** share a root cause: when `.error(.recordingTooShort)` is published, the UI layers *and* the coordinator's `startHoldIfIdle` guard all disagree about when that state should end. There is no single clearing moment — the pill glyph clears after 1.5s, the ResponseCard does not clear at all, and the coordinator only clears on `toggle()` / `cancelIfActive()`.
- **Hold path has no error-clearing entry point.** `SessionCoordinator.startHoldIfIdle` guards on `currentDisplayState() == .idle` only; `.error` never maps to `.idle` in `displayState(for:)`. The orchestrator's `startHoldCapture()` DOES contain error-recovery logic (`Sources/PersonalScribeSession/Pipeline/Orchestrator/SessionPipelineOrchestrator.swift:161-176`), but the coordinator filters the call before it reaches the orchestrator.
- **Tap path works** because `SessionCoordinator.toggle()` (`Sources/PersonalScribeSession/SessionCoordinator.swift:103-114`) explicitly routes `.error` → `performToggle()` → `pipeline.toggleCapture()`, and the orchestrator's `toggleCapture()` (`SessionPipelineOrchestrator.swift:142-159`) maps `.error` to idle + start.

## Symptom 1: Pill rendering overlap

### What renders where

Two independent renderers observe the same `AppStoreSnapshot`:

1. **Pill glyph "Too short — try again"** — rendered by `PillOverlayView` driven by `PillOverlayViewModel.visibility = .error(message: "Too short — try again")`. Published by `AppStore.handleSessionSnapshotChange` at `Sources/PersonalScribeCore/AppStore/AppStore.swift:145-155`. Message string at `AppStore.swift:366-383` (`pillMessage(for:)`).

2. **ResponseCard "Recording too short."** — rendered by `ResponseCard` NSPanel above the pill, content built by `RecordingStatusCardDriver.statusContent(...)` at `Sources/PersonalScribeAppKit/Overlay/RecordingStatusCardDriver.swift:66-72`:

    ```swift
    // 1. Error overrides every VAD state.
    if case let .error(err) = sessionState {
        return StatusCardContent(
            text: err.errorDescription ?? String(describing: err),  // → "Recording too short."
            link: nil
        )
    }
    ```

   String comes from `PersonalScribeError.errorDescription` (`Sources/PersonalScribeCore/Errors.swift:31-32`). The driver is called every snapshot change by `PillOverlayController.applySnapshot` → `applyRecordingStatusCardState` (`Sources/PersonalScribeAppKit/Overlay/PillOverlayController.swift:174-217`).

### Why both render simultaneously

This is a **state-machine** bug, not a layout bug. There are two independent dismissal policies for the same logical event:

- **Pill glyph** auto-dismisses after `AppStore.errorVisibilityDuration = 1.5s` (`AppStore.swift:7, 150-154`). The 1.5s timer fires `completePillTransition` → `rederivePillVisibility` → `derivePillVisibility`. That static func at `AppStore.swift:285-324` maps `.error` sessionState to `idleVisibility(...)` (line 302-304) — i.e. `.idle`, `.hidden`, or `.downloading/.loading`. So after 1.5s, the pill glyph clears **even though the session is still `.error`**.

- **ResponseCard** has no auto-dismiss for error content. `autoDismissDuration(for:)` at `PillOverlayController.swift:278-280` only returns non-nil for `.openVadSettings` link content. So the ResponseCard sticks until the session state leaves `.error`, which doesn't happen by itself.

Net effect: during the first 1.5s, both render. After 1.5s the pill glyph is gone but the card stays. The user sees the overlap until they press Esc or tap the pill.

### Coupling to Symptom 2

**Coupled.** Both symptoms stem from the same fact: there is no single authoritative moment when "the `.error(.recordingTooShort)` episode is over." The pill fakes it (timer), the card stays forever, and the coordinator's hold-start guard agrees with the card that the session is still in `.error` and refuses to start a new recording.

A fix that clears `.error` → `.idle` on some external trigger (timer, next user interaction, hold-press) would fix both the card overlap AND the hold wedge in one move.

## Symptom 2: Hold-path wedge from `.error(.recordingTooShort)`

### State machine trace

1. User holds hotkey < 1s, releases.
2. `GlobalHotkeyMonitor.handleKeyUp` fires `onHoldRelease()` (`Sources/PersonalScribeAppKit/Hotkeys/GlobalHotkeyMonitor.swift:361-399`). `isHolding` is reset to `false` on line 374.
3. `onHoldRelease` is wired to `coordinator.stopIfActive()` (`Sources/PersonalScribeAppKit/Composition/AppComposition.swift:131-135`).
4. `stopIfActive` sees `.holdRecording`, routes to `performStop` → `pipeline.toggleCapture()` (`Sources/PersonalScribeSession/SessionCoordinator.swift:151-158`, `261-268`).
5. `toggleCapture()` hits the `.recording, .holdRecording` branch and calls `stopRecordingAndRunPipeline()` (`SessionPipelineOrchestrator.swift:146-147`).
6. In `stopRecordingAndRunPipeline`, after capture teardown, the too-short guard fires (`SessionPipelineOrchestrator.swift:434-445`):
    ```swift
    guard bufferedDuration >= .milliseconds(1_000) else {
        publish { snapshot in
            snapshot.sessionState = .error(.recordingTooShort)
            ...
        }
        return
    }
    ```
7. Session is now `.error(.recordingTooShort)`. UI renders both pill glyph + ResponseCard (Symptom 1).

Next user action — press hotkey to hold again:

8. `GlobalHotkeyMonitor.handleKeyDown` fires, scheduler arms `enterHoldIfStillPressed`, which after 300ms sets `isHolding = true` and calls `onHoldStart()` (`GlobalHotkeyMonitor.swift:340-411`). `isHolding` starts at `false` (reset on line 353), so this path is NOT wedged at the monitor level.
9. `onHoldStart` is wired to `coordinator.startHoldIfIdle()` (`AppComposition.swift:126-130`).
10. **Wedge location:** `startHoldIfIdle` (`SessionCoordinator.swift:129-135`):
    ```swift
    public func startHoldIfIdle() async {
        guard await currentDisplayState() == .idle else {
            return
        }
        await performHoldStart()
    }
    ```
11. `currentDisplayState()` (`SessionCoordinator.swift:363-375`) maps only `.completed` → `.idle`. `.error` is passed through unchanged:
    ```swift
    private static func displayState(for state: SessionState) -> SessionState {
        switch state {
        case .completed:
            return .idle
        case .idle, .recording, .holdRecording, .transcribing, .error:
            return state
        }
    }
    ```
12. Guard fails (`.error != .idle`). `startHoldIfIdle` returns. Nothing happens. **This is the no-op.**

### The asymmetry: what tap-path does that hold-press doesn't

`SessionCoordinator.toggle()` (`SessionCoordinator.swift:103-114`):

```swift
public func toggle() async {
    switch await currentDisplayState() {
    case .idle:               await performStart()
    case .recording, .holdRecording: await performStop()
    case .transcribing, .error:      await performToggle()   // ← key branch
    case .completed:          await performStart()
    }
}
```

`performToggle()` routes to `pipeline.toggleCapture()`, and the orchestrator's `toggleCapture()` has the error-clearing branch at `SessionPipelineOrchestrator.swift:150-158`:

```swift
case .error:
    publish { snapshot in
        snapshot.sessionState = .idle
        snapshot.activeStage = nil
        ...
    }
    await startRecording()
```

So tap-path explicitly clears `.error` and starts a new session. `startHoldIfIdle` bypasses this entirely because it guards at the coordinator level before the pipeline sees the call.

Note that **the orchestrator's `startHoldCapture()` also contains error-clearing logic** at `SessionPipelineOrchestrator.swift:161-176`:

```swift
public func startHoldCapture() async {
    switch currentSnapshot.sessionState {
    case .idle, .completed:
        await startHoldRecording()
    case .error:                                 // ← exists, but never reached
        publish { snapshot in
            snapshot.sessionState = .idle
            ...
        }
        await startHoldRecording()
    case .recording, .holdRecording, .transcribing:
        logger.info("Ignored hold-start while session is not .idle")
    }
}
```

This orchestrator-level handling is **dead code under the current coordinator path** because `SessionCoordinator.startHoldIfIdle` never calls `pipeline.startHoldCapture()` unless display state is `.idle`.

### Is `GlobalHotkeyMonitor.isHolding` stuck?

No. Inspecting `GlobalHotkeyMonitor.swift:340-411`:

- `handleKeyDown` sets `isHolding = false` on every fresh (non-repeat) keyDown (line 353).
- `handleKeyUp` clears `isHolding = false` on release when the hold was live (line 374).
- `resetState()` (line 418-425) clears it on monitor start/restart.

The "too-short" release goes through `handleKeyUp` and clears `isHolding`. The next press goes through `handleKeyDown` cleanly. The monitor is not the wedge source.

### Exact no-op location

**`Sources/PersonalScribeSession/SessionCoordinator.swift:130-132`** (the `guard` in `startHoldIfIdle`).

## Fix options

### Option A: Let `startHoldIfIdle` also recover from `.error`

Change `SessionCoordinator.startHoldIfIdle` to accept `.error` in addition to `.idle`, and route to `pipeline.startHoldCapture()`. The orchestrator's `startHoldCapture` (lines 161-176) already clears `.error` → `.idle` before calling `startHoldRecording`, so the logic is already in place — the coordinator just needs to stop filtering the call.

- **Wedge fix**: Yes. Hold-press from `.error` now transitions `.error → .idle → .holdRecording` via the orchestrator's existing `.error` branch.
- **Overlap fix**: Partial. The session transitions out of `.error` on the user's next hold-press, so the ResponseCard finally clears. But during the **initial** 1.5s error window (before the user does anything), the overlap still shows. Sep fix for overlap is still needed unless the user is expected to absorb "card + pill glyph for up to 1.5s" as acceptable.
- **Invariant compatibility**: Yes. The AppStore remains the single source of `.holdToRecord` (via `isHoldRecording` → `.holdToRecord` mapping in `derivePillVisibility`). No side-channel push. `#071`'s eager-publish invariant is preserved (the orchestrator still publishes `.holdRecording` before awaiting `capture.start()`).
- **Contract concern**: The name `startHoldIfIdle` becomes a lie. Rename to `startHoldIfIdleOrError` (ugly) or `startHoldIfAvailable`, OR keep the name and document that `.error` is equivalent to `.idle` for hold-start purposes. Same asymmetry already exists in `toggle()` (which is also happy to start from `.error`), so it's a consistent pattern, just named misleadingly.
- **Test sketch**:
  - `test_startHoldIfIdle_fromErrorState_clearsErrorAndStartsHoldRecording`: set orchestrator to `.error(.recordingTooShort)`, call `coordinator.startHoldIfIdle()`, assert final state is `.holdRecording` and `.error` snapshot was transitional.
  - `test_startHoldIfIdle_fromErrorState_publishesHoldRecordingEagerly`: verify eager-publish invariant survives (snapshot sees `.holdRecording` before capture.start() resolves).

### Option B: Explicit `coordinator.clearErrorIfAny()` step that the hold path fires on hold-press before `startHoldIfIdle`

Add a no-op-safe `clearErrorIfAny()` that transitions `.error → .idle`. Call it from the composition's `onHoldStart` closure before `startHoldIfIdle`:

```swift
onHoldStart: {
    Task {
        await coordinator.clearErrorIfAny()
        await coordinator.startHoldIfIdle()
    }
},
```

- **Wedge fix**: Yes.
- **Overlap fix**: Same as A — clears on next hold-press, not during the initial window.
- **Invariant compatibility**: Yes. No signature change; new narrow method.
- **Contract concern**: Caller-side orchestration. Any future caller that wants the same behavior has to remember to call the same two-step sequence. Future divergence risk.
- **Test sketch**:
  - `test_clearErrorIfAny_fromErrorIdles`: verify the transition.
  - `test_clearErrorIfAny_fromIdleIsNoop`: verify idempotency.
  - `test_clearErrorIfAny_fromRecordingIsNoop`: don't kill an active session.

### Option C: Clear the error state automatically after a short delay

Match the pill's 1.5s `errorVisibilityDuration` with an orchestrator-side timer that flips `.error → .idle` after the same window. This would bring the session state in line with what the pill already shows.

- **Wedge fix**: Yes. After 1.5s, `.error → .idle`, so the next hold-press finds `.idle`.
- **Overlap fix**: Yes, same timer also clears the ResponseCard (driver's `.error` branch returns nil once session leaves `.error`).
- **Invariant compatibility**: Yes, but introduces a time-based state transition in the orchestrator. The orchestrator currently has no auto-transition out of `.error` — every state change is user-driven or pipeline-driven. Adds a new timer to the actor.
- **Contract concern**: The behavior becomes surprising for the `transcriptionFailure` / `modelLoadFailure` cases — user sees an error flash for 1.5s then silence, with no path to retry except re-pressing. Might actually be fine given every error case resolves to "try again" anyway.
- **Test sketch**:
  - `test_errorAutoClears_toIdle_after_errorDuration`: use a fake clock, assert state transitions.
  - `test_errorAutoClear_cancelledBy_newUserInput`: verify the timer doesn't fire if the user already re-armed via tap.

### Option D: Split the ResponseCard error-content lifecycle from the session `.error` state

Keep the current error state machine, but fix the **ResponseCard** policy so its error content auto-dismisses after 1.5s (or at least matches the pill glyph's lifecycle). Separately fix the hold wedge via Option A or B.

- **Wedge fix**: No (this is D for overlap only). Must be combined with A or B.
- **Overlap fix**: Yes, cleanly. Both UIs agree on the 1.5s lifecycle.
- **Invariant compatibility**: Yes. Driver already has auto-dismiss plumbing for `.openVadSettings` (`PillOverlayController.swift:278-280`) — extend `autoDismissDuration(for:)` to return `1.5` for error content.
- **Test sketch**:
  - `test_responseCardDriver_errorContent_autoDismissesAfter_1_5s`: with fake clock.

### Option D': Make the ResponseCard driver stop returning error content after a bounded window, OR stop returning it at all

The driver could skip the error branch entirely and let the pill glyph (with its own 1.5s timer) be the sole surface for error messaging. This is the simplest unification: one surface, one timer.

- **Wedge fix**: No.
- **Overlap fix**: Yes — by elimination. Only the pill glyph renders the error.
- **Invariant compatibility**: Yes.
- **Design concern**: Is there a reason we show the longer "Recording too short." on the card AND the shorter "Too short — try again" on the pill? If both surfaces are intentional product UX (card for detail, pill for at-a-glance), removing the card regresses that design. Worth checking with design owner.
- **Test sketch**:
  - `test_recordingStatusCardDriver_ignoresErrorSessionState`: driver returns nil on `.error`.

## Recommendation

**Option A + Option D' (remove error content from the ResponseCard driver).**

Justification:
- A fixes the wedge directly by aligning `startHoldIfIdle` with the existing tap/`toggle()` behavior that already tolerates `.error`. It keeps the orchestrator's existing error-recovery logic (which is currently dead code from the hold path) reachable. Lowest blast radius on the session state machine.
- D' fixes the overlap by collapsing two error renderers to one. The pill glyph already has a timer (1.5s) that clears it visually. Having the ResponseCard also claim the error territory creates the exact bug we're seeing. Ninimma's design does not seem to depend on the card carrying error text (the card's other consumers are VAD warnings, auto-stopped notifications, and record-without-transcribe progress — all orthogonal to session errors).
- Option C (auto-clearing `.error`) is tempting for its symmetry but introduces a timer in the `SessionPipelineOrchestrator` actor, which currently has no time-based state transitions. That's a larger design change for marginal benefit over A.
- Option B is viable but leaks coordination into composition. Prefer A.

If design insists the ResponseCard must show "Recording too short." (richer detail than the pill), fall back to A + D (bounded ResponseCard error TTL matching the pill's 1.5s).

## Open questions

1. **Is the ResponseCard rendering "Recording too short." an intentional design or an accident?** `RecordingStatusCardDriver`'s error branch is at the top of the priority chain (line 66-72), suggesting intent — but the current rendering produces overlap, which feels unintentional. Design owner should confirm.
2. **Does `.error(.transcriptionFailure)` produce the same overlap?** Same branch, same driver priority, same missing auto-dismiss for error content. Probably yes. Worth testing in the same fix.
3. **Option C note — does `errorVisibilityDuration = 1.5s` feel long enough for the ResponseCard text?** The ResponseCard text is longer ("Recording too short." vs the pill's "Too short — try again"). If D/D' is rejected and we keep the card, consider whether 1.5s is enough reading time.
4. **Are there any test fixtures that currently assert `.error` sticks?** If yes, Option C or an auto-clearing policy would break them. Before fixing, grep the test suite for explicit `.error(.recordingTooShort)` state assertions to understand the codified contract.

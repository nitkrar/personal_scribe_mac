# #046 Stage B — Grace window + auto-stop notification (preference-gated)

Stage A landed as commit `15e2496` (2026-04-24). Stage B adds two opt-in preferences that surface through the existing ResponseCard (not the pill). Plan iterated 2026-04-24 after codex review at `plans/investigations/2026-04-24-046-stage-b-plan-codex.md`.

## User-locked decisions

1. **Two new Bool preferences, defaults `false`:**
   - `VadShowStoppingWarning` — enables the 0.8s grace window + "…stopping, speak to continue" ResponseCard.
   - `VadShowAutoStoppedNotification` — enables the "Auto stopped. Update settings to change." ResponseCard after auto-stop lands.
2. **Settings layout**: collapsible section in `GeneralTab` Auto-stop card, gated by master `VadAutoStopEnabled`. Conditional render (not `DisclosureGroup`), vertical stacking only. `.animation` is optional polish — ship without, add if manual-verify needs it.
3. **Grace duration**: hard-coded 0.8s. Not a preference.
4. **Warning card text**: `…stopping, speak to continue`. No countdown. **No Esc wiring in the grace-cancel path** — Esc continues to mean "discard recording" (#002), unchanged. Cancel-without-losing-recording = speak again.
5. **Notification card text**: `Auto stopped. Update settings to change.` The substring "Update settings to change" is a clickable link that opens Settings via the existing `openSettingsTab` closure in `PersonalScribeAppMain`.
6. **Notification auto-dismiss**: 2.0s OR new session start, whichever first.
7. **Preference freeze at session start** — mid-session flips apply to next recording. Same rule as Stage A.
8. **Error priority**: pipeline error overrides warning/notification. Error-and-grace-clear publish in the **same** snapshot mutation, not back-to-back.
9. **Ticket treatment**: lands on #046 as Stage B. No new ticket.

## Runtime flow

### Both prefs off (shipped default)
Silence → immediate auto-stop. Identical to Stage A.

### Warn on, notify off
1. VAD detects `.speechEnded`.
2. Orchestrator starts 0.8s grace timer, publishes snapshot with `vadAutoStopGracePending = true` + deadline.
3. ResponseCard shows `…stopping, speak to continue`.
4. Three exits during grace:
   - **Timer elapses** → resolver fires auto-stop handler → session transitions to `.transcribing`. Card disappears (grace pending cleared).
   - **User resumes speaking** → Silero emits `.speechResumed` → resolver cancels grace → session stays `.recording`. Card disappears.
   - **User presses hotkey** → resolver fires handler immediately → `.transcribing`. Card disappears.
   - **Pipeline error** → resolver cancels grace, error state published in same mutation. Card shows error.

### Warn off, notify on
Silence → immediate auto-stop (Stage A behavior). After transition to `.transcribing`, orchestrator publishes a fresh `vadAutoStopFireToken`. ResponseCard sees a new token since last, renders `Auto stopped. Update settings to change.` Auto-dismisses at 2.0s or on next session start.

### Both on
Grace window first, then notification after the fire. The notification's fire-token is only published once grace resolves to "fired," so cancel paths (speech-resumed, error) never trigger the notification.

## Core types — state shape

Following the #071 rule: one producer-owned authority per piece of state. Snapshot consumers compare-against-last-seen rather than clearing mutable latches.

### `SessionSnapshot` additions

- `vadAutoStopGracePending: Bool` — true while the grace timer is pending. Set together with `vadAutoStopGraceDeadline`; both cleared atomically on resolve.
- `vadAutoStopGraceDeadline: Date?` — when the timer will fire. Consumers can compute remaining time if ever needed; for now the ResponseCard just reads `pending`.
- `vadAutoStopFireToken: UUID?` — producer-owned identity. Freshly generated each time auto-stop fires (via VAD path only). Consumers cache last-seen; new token ≠ last-seen → render notification once. **Replaces the broken `Bool` latch** flagged by codex.

All three fields additive + optional. No existing consumer breaks.

### `VadEvent` additions

Extend with `.speechResumed` so the consumer loop can cancel grace when Silero detects resumed speech. Emitted by `FluidAudioVadSession` when `VadStreamState.triggered` transitions `false → true` AFTER the session has already emitted a `.speechEnded`. Codex verified Silero's streaming state machine does emit `speechStart` on this transition.

## Orchestrator — grace state machine

Replace Stage A's `vadAlreadyFired: Bool` loop-local with a small phase type scoped to the consumer loop:

```
enum GracePhase {
    case idle
    case pending(token: UUID, deadline: Date, timerTask: Task<Void, Never>)
    case resolved
}
```

`idle` → session has not yet seen `.speechEnded`. Keep ingesting.
`pending` → grace timer running. Keep ingesting so `.speechResumed` can cancel.
`resolved` → handler fired or grace cancelled. Stop ingesting VAD.

### Tokenized resolver

A single actor-isolated method is the only way to transition `pending → resolved`:

```
func resolveGracePending(token: UUID, trigger: ResolveTrigger) async
```

Callers: timer-elapsed (from the timer task itself), hotkey-during-grace, error teardown, consumer-loop on `.speechResumed`. The resolver:

1. Checks token matches current pending token. If not, stale → no-op.
2. Cancels timer task (safe if it's the caller).
3. Updates snapshot in ONE mutation:
   - `.fire` trigger: set `vadAutoStopFireToken = UUID()`, clear grace fields, then detached-`Task { await onAutoStopRequested?() }` to invoke stop (per Stage A detached-Task pattern — must escape `captureTask`).
   - `.cancel` or `.error` trigger: clear grace fields only. No fire-token (no notification).
4. Transitions local phase → `.resolved`.

Race-safety: if the timer wakes up microseconds before a manual `.fire` lands, one of the two enters the actor first. The second sees token mismatch, no-ops. No double-stop.

### Error path

`handleStageFailure` additions: before publishing `.error`, cancel any pending grace timer task and clear `vadAutoStopGracePending`/`Deadline` in the SAME `publish` mutation that sets `.error`. No intermediate "recording-but-no-grace" snapshot observable.

### New session / cancel paths

`startRecording`, `startHoldRecording`, `discardActiveCapture`, `stopRecordingAndRunPipeline` all publish a clean snapshot at session boundary. Extend each to also reset `vadAutoStopFireToken` and grace fields in the same mutation. Cheap additive edits.

### Coordinator pass-through

`SessionCoordinator` gains one method:

```
public func fireVadGraceNowIfPending() async
```

Called by the hotkey handler when a manual stop arrives during grace. Routes through to `pipeline.resolveGracePending(..., trigger: .fire)`. Hotkey handler in `PersonalScribeAppMain` adds a lightweight "is grace pending?" check (read snapshot) and calls `fireVadGraceNowIfPending` before `stopIfActive`. If no grace pending, `stopIfActive` runs as today.

(Alternative considered: skip the pass-through, let hotkey just call `stopIfActive` which queues behind the actor — but that would race: the timer could fire, then the queued manual-stop would hit `.transcribing` and no-op, so from the user's POV their hotkey did nothing. Explicit fire-now is cleaner.)

## ResponseCard — driver extension

`RecordingStatusCardDriver.statusText` returns a new type to support link regions:

```
struct StatusCardContent: Sendable, Equatable {
    let text: String
    let link: StatusCardLink?  // nil for non-linked messages
}

struct StatusCardLink: Sendable, Equatable {
    let range: Range<String.Index>  // substring within `text`
    let action: StatusCardLinkAction
}

enum StatusCardLinkAction: Sendable, Equatable {
    case openVadSettings
}
```

Priority order (first match wins):

1. `.error` state → error text. No link.
2. `vadAutoStopGracePending && showStoppingWarning` → `…stopping, speak to continue`. No link.
3. `vadAutoStopFireToken != lastSeenFireToken && showAutoStoppedNotification` → `Auto stopped. Update settings to change.` with link range on "Update settings to change".
4. Existing record-without-transcribe messaging.
5. Nil (hide).

Consumer tracks `lastSeenFireToken` locally (in `PillOverlayController` state). Each new token flips the notification on once; subsequent re-renders with the same token don't repeat.

`ResponseCard` panel accepts optional `link: StatusCardLink?` alongside `text:` in `show(...)`. `ResponseCardView` renders the link range using `AttributedString` with a tap gesture on the linked substring. Tap invokes the `action` which the AppKit layer routes to `openSettingsTab`.

## Settings — collapsed layout

`GeneralTab` → Auto-stop card:

```
[always visible]
- "Auto-stop after silence" toggle (master)

[visible only when master is on]
- "Silence threshold" slider (existing)
- "Warn before stopping" toggle (NEW)
- "Show stop notification" toggle (NEW)
```

Implementation: `if viewModel.vadAutoStopEnabled { VStack { ... } }`. No `DisclosureGroup`. No `.animation(...)` — optional polish, skip for MVP.

`GeneralTabViewModel` additions mirror Stage A's pattern: two `@Published private(set)` properties + two setters + UserDefaults persist via the new preference enums.

### Link-to-Settings wiring

Reuse the existing `openSettingsTab` closure already wired into `PersonalScribeAppMain` (used by ⌘, and the menu-bar item). `ResponseCard`'s link-tap closure is injected at composition time and calls `openSettingsTab()`. No new notification channel, no new window-model API for General-tab targeting — General is already the default sub-tab when Settings opens fresh. If the user has Settings open on a different sub-tab, clicking the link opens Settings but they may see their prior sub-tab; acceptable for Stage B. (Can promote sub-tab routing later if dogfood asks.)

## Execution — 3 phases, linear, no builds until the end

### Phase 1 — Core types + preferences

Files:
- `Sources/PersonalScribeCore/Preferences/VadPreferences.swift` — add two Bool fields + init.
- `Sources/PersonalScribeCore/SessionSnapshot.swift` — add three VAD fields (all optional/defaulted).
- `Sources/PersonalScribeAppKit/Settings/VadPreferencePersistence.swift` — add two preference enums; reader returns all four fields.

No new tests. Existing `VadPreferencesTests` still valid.

### Phase 2 — Pipeline (orchestrator + VAD events + coordinator)

Files:
- `Sources/PersonalScribeVAD/VadMonitoring.swift` — add `.speechResumed` case to `VadEvent`.
- `Sources/PersonalScribeVAD/FluidAudioVadSession.swift` — detect `triggered: false → true` after prior `.speechEnd`, emit `.speechResumed`. Track an internal `hasEmittedSpeechEnded: Bool` to gate the transition.
- `Sources/PersonalScribeSession/Pipeline/Orchestrator/SessionPipelineOrchestrator.swift`:
  - Replace `vadAlreadyFired: Bool` in `consumeCaptureStream` with a local `GracePhase` variable.
  - Handle `.speechEnded` by transitioning idle → pending; handle `.speechResumed` by transitioning pending → resolved via resolver.
  - New actor method `resolveGracePending(token:trigger:)` — single transition path.
  - Extend `handleStageFailure` to clear grace fields in the same publish as `.error`.
  - Extend `startRecording`, `startHoldRecording`, `discardActiveCapture`, `stopRecordingAndRunPipeline` to clear grace fields in their existing publishes.
- `Sources/PersonalScribeSession/SessionCoordinator.swift` — add `fireVadGraceNowIfPending()` pass-through.

Tests (in `Tests/PersonalScribeSessionTests/Pipeline/VadOrchestratorIntegrationTests.swift`):
- `testGraceTimerFiresAutoStopAfterDuration` — warn enabled, 0.8s elapses, handler fires.
- `testSpeechResumedCancelsGrace` — during grace, fake VAD emits `.speechResumed`, handler never fires, session stays recording.
- `testTokenizedResolverPreventsDoubleStop` — race two `.fire` resolvers with different tokens; only one handler call observed.
- `testErrorDuringGraceClearsGraceInSamePublish` — snapshot-stream assertion: no intermediate snapshot with `.recording && !grace`.

### Phase 3 — UI + composition + runbook

Files:
- `Sources/PersonalScribeAppKit/Overlay/RecordingStatusCardDriver.swift` — new signature returning `StatusCardContent?`; priority order logic; `StatusCardContent` + `StatusCardLink` types.
- `Sources/PersonalScribeAppKit/Overlay/ResponseCard.swift` — `show(...)` accepts optional `link:`; render link range as tappable.
- `Sources/PersonalScribeAppKit/Components/ResponseCardView.swift` — `AttributedString`-based rendering with tap action on the link substring.
- `Sources/PersonalScribeAppKit/Overlay/PillOverlayController.swift` — feed new snapshot fields + pref snapshot into the driver; track `lastSeenFireToken`; route link taps to the injected `openSettingsTab` closure.
- `Sources/PersonalScribeAppKit/Settings/GeneralTab.swift` — collapsed auto-stop card + two new toggles + VM properties.
- `Sources/PersonalScribeAppKit/Composition/PersonalScribeAppMain.swift` — hotkey handler now calls `fireVadGraceNowIfPending` before `stopIfActive`; pass `openSettingsTab` reference into the pill controller's link-tap path.
- `Tests/PersonalScribeAppKitTests/ManualVADVerification.md` — MV-VAD-6..10 runbook entries.

Tests (in driver-level `RecordingStatusCardDriverTests.swift` — new file in `Tests/PersonalScribeAppKitTests/Overlay/`):
- `testDriverEmitsWarningOnlyWhenPrefOn` — grace pending + pref true → warning; pref false → nil.
- `testDriverNotificationFiresOnceForEachToken` — consumer with cached last-seen-token; same token → nil; new token → notification.
- `testDriverErrorOverridesVadStates` — error state short-circuits before warning/notification branches.

No tests for Settings VM setters (same fluff exclusion as Stage A).

### After all three phases: build + full suite + DMG

- `swift build` + `swift test --filter` per new test file, then full suite.
- `./scripts/package.py -i` for DMG rebuild.
- Runtime verify MV-VAD-6..10 scenarios.

## Test count

**7 total new tests** across the entire Stage B implementation:
- Phase 1: 0
- Phase 2: 4 (grace fires, speech resumed cancels, tokenized resolver, error-clear atomic)
- Phase 3: 3 (driver warning gate, driver notification token, driver error priority)

Intentionally cut from an earlier 15-test estimate after user feedback that several were fluff.

## Commit structure

Single commit per phase, tagged `#046 stage b step 2.N:`. Three commits total.

## Out of scope for Stage B

- Esc wiring in grace path — kept as "discard recording" per #002.
- Grace duration as a preference — hard-coded 0.8s.
- Countdown text in warning card — stays `…stopping, speak to continue`.
- Pill visual changes — pill never renders VAD grace/notification.
- Deep-link to a specific sub-tab of Settings — opens Settings; if already open on a different sub-tab, user sees whatever was selected.
- `.animation(.default, value:)` on the collapsed layout — optional polish, ship without.
- Speech-resumed cancellation via ambient noise — Silero's hysteresis handles threshold; no extra filtering.

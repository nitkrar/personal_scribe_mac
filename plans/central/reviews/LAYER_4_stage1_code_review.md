# Layer 4 Stage 1 Code Review

> Written by main-session Claude after 2 consecutive worktree-review-agent dispatches died silently without commits. Review is based on direct inspection of commits `048d25e` + `fed131d` + `201cf9f` on trunk.

## Verdict

NEEDS REVISION (minor).

Finding counts: Critical 0 / Major 1 / Minor 2 / Nit 1.

The Stage 1 implementation is ~95% correct and well-scoped. The one major finding is a sibling to the already-fixed `handleModelDownloadProgressChange` race — `handleVisibilityModeChange` has the same pattern and can clobber `.done`/`.error` transients.

## Scope reviewed

- `048d25e` — primary Stage 1 parallel-build (Candidate A facade)
- `fed131d` — fix-forward: `LiveAppStoreClock` public + drop redundant `guard let self`
- `201cf9f` — prod race fix: `handleModelDownloadProgressChange` early-returns on no-op yields
- Files inspected in full: all 8 under `Sources/SeshatCore/AppStore/` + all 5 test/fake files

## Plan fidelity

✅ **All 8 contract types/protocols present**:
- `AppStoreSnapshot` (struct) with the 7 required fields
- `PillVisibilityState` (enum, Core-neutral, no AppKit import) with 8 cases
- `AppStoreVisibilityMode` (enum, 3 cases)
- `AppStoreSessionProviding`, `AppStoreActiveModeProviding`, `AppStoreVisibilityModeProviding`, `AppStoreClock` protocols
- `AppStore` (`@MainActor final class`, `ObservableObject`, single `@Published snapshot`)

✅ **Candidate A honored** — no `AppStoreAction` / reducer surface. Facade only.

✅ **Core-neutral** — `PillVisibilityState` derives from `SessionState` + `ModelDownloadProgress` + `AppStoreVisibilityMode` without any AppKit import.

## Correctness

- ✅ 4 long-lived observation tasks: session state, model download progress, permissions, active mode + visibility mode.
- ✅ `.transcribing → .idle` transition sets `pillVisibility = .done` + schedules pill transition (line 138-144).
- ✅ `.error(_)` transition sets `.error(message:)` + schedules (line 147-152).
- ✅ `lastTranscriptionResult` refreshes only on `transcribing → idle` (line 140), not on every idle.
- ✅ Recording-duration loop starts on `recording` entry, clears on exit (lines 132-136, 189-221). Wall-clock via `clock.now()`; 250ms tick cadence per locked decision.
- ✅ Progress handler early-return on no-op yield (`201cf9f` prod race fix) closes the initial-replay clobber.

## Findings

### MAJOR — `handleVisibilityModeChange` has the same clobber-race as progress did

`Sources/SeshatCore/AppStore/AppStore.swift:183-187`:
```swift
private func handleVisibilityModeChange(_ visibilityMode: AppStoreVisibilityMode) {
    currentVisibilityMode = visibilityMode
    cancelPillTransition()
    rederivePillVisibility()
}
```

This unconditionally cancels any in-flight pill transition and rederives visibility. If the user flips visibility mode (or the stream's initial yield replays the *same* mode) while a `.done` or `.error(message:)` transient is active, the transient is lost.

Same failure mode as the pre-`201cf9f` progress bug. Recommended fix (mirrors the progress-handler shape):

```swift
private func handleVisibilityModeChange(_ visibilityMode: AppStoreVisibilityMode) {
    guard visibilityMode != currentVisibilityMode else { return }
    currentVisibilityMode = visibilityMode
    cancelPillTransition()
    rederivePillVisibility()
}
```

An early-return on unchanged mode closes the initial-yield replay. An orthogonal question is whether the cancel is even correct when the mode DOES change during a `.done`/`.error` transient — arguably the transient should finish before the new mode takes effect. But that's a UX nuance; the minimum fix is the no-op guard.

### MINOR #1 — Relative `clock.sleep` in recording-duration loop drifts under manual advance

`Sources/SeshatCore/AppStore/AppStore.swift:198-212` uses `clock.sleep(for: .milliseconds(250))` in a loop. Each sleep re-captures `currentTime + 250ms`, so if a test advances the clock non-monotonically, the tick cadence drifts.

For the production `LiveAppStoreClock` this is fine (wall-clock marches forward monotonically). For `ManualAppStoreClock` it means tests that advance by large chunks (e.g. 500ms) will see one tick fire, not two. Tests can work around by advancing 250ms at a time, but the cadence contract is subtle.

Suggested: document in `AppStoreClock` that `sleep(for:)` is relative and cadence loops should expect caller-driven granularity. Or expose an absolute-deadline variant and use it from the tick loop.

Not a blocker.

### MINOR #2 — Known AppStoreTests timing failures are latent races, not yet reviewed in scope

The following 3 tests fail on trunk and are flagged for separate review (not in Stage-1-scope for this review):
- `testDoneVisibilityIsTransientAfterTranscribingToIdle`
- `testErrorVisibilityIsTransientAfterErrorState`
- `testRecordingDurationTicksAndClearsOutsideRecording`

Root cause (investigated in main session):
- The `schedulePillTransition` / `startRecordingDurationLoop` tasks dispatch asynchronously; by the time the test advances the clock, the task may not have called `clock.sleep` yet, so the sleep's relative deadline is computed from an already-advanced currentTime and never wakes.
- Main session added a `sleeperCount` helper to `ManualAppStoreClock` and partial test fixes (stashed).

These are test-harness races, not production bugs. They overlap with MINOR #1 (relative sleep). A cleaner fix is the absolute-deadline clock variant proposed above.

### NIT — `LiveAppStoreClock` holds both `clock` and `reference`

`Sources/SeshatCore/AppStore/AppStore.swift:419-431` stores `clock: ContinuousClock()` and `reference: ContinuousClock().now` — two separate instances. The `now()` method computes `reference.duration(to: clock.now)` which is correct but reads two state sources. A simpler shape would be a single `startTime` captured at init and using `ContinuousClock().now - startTime`. Stylistic.

## Stage 1 scope check

✅ **Pass**. Zero existing consumer files modified. Only `Sources/SeshatCore/AppStore/**` and `Tests/SeshatCoreTests/AppStore/**` touched.

## Swift 6 concurrency

- `AppStore: @MainActor final class, ObservableObject` — consistent with planned core-neutral store.
- 4 observation tasks use `[weak self]` + `guard let self` patterns correctly.
- `Published<AppStoreSnapshot>` + `updateSnapshot` wraps mutation; no direct `@Published` mutation from non-MainActor contexts.
- Fake `ManualAppStoreClock` uses `@unchecked Sendable` + `NSLock` — acceptable for a test double.
- `FakePermissionService`/`FakeActiveModeProvider`/`FakeVisibilityModeProvider` all `@unchecked Sendable` + lock-free mutable state — would be a concurrency concern in production but fine for test doubles.

## Cross-layer concerns

- L1 Permissions dependency: `AppStore` holds `permissions: any PermissionService`. Correct protocol-boundary use. ✅
- L6 Model selection dependency: `AppStoreActiveModeProviding` is owned by Layer 4 as an adapter seam; Layer 6's `ModeDescriptor` flows through. ✅
- L7 Pipeline dependency: `AppStoreSessionProviding` wraps session state streams; stays protocol-only. ✅
- No direct coupling to unfinished Stage 2 consumers.

## Test coverage

- 8 test methods covering the 7 snapshot fields + `.done`/`.error`/recording-duration transients.
- 3 of 8 tests have known timing issues (flagged above).
- Missing: no test for the major-#1 visibility-mode clobber. Should add one.
- Missing: no test for `completePillTransition` being called without a pending transition (edge case — cancel races with completion).

## Summary

Layer 4 Stage 1 implements Candidate A faithfully, keeps Core-neutrality, and honors the Q1 wall-clock recording-duration decision. The `201cf9f` prod race fix already caught one clobber; the sibling bug in `handleVisibilityModeChange` is the one blocking finding.

Stage 2 readiness: **blocked on MAJOR fix** (trivial — add no-op guard to visibility-mode handler + test). Rest is Stage-2-ready after that.

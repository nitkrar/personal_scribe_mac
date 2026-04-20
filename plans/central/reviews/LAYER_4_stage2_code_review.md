# Layer 4 Stage 2 Code Review

## Verdict

REQUEST CHANGES

## Findings

### Blocker

- None.

### Major

- `Sources/SeshatAppKit/AppStore/AppKitActiveModeProvider.swift:7-14`, `Sources/SeshatCore/AppStore/AppStoreActiveModeProviding.swift:1-3`, `Sources/SeshatAppKit/Composition/AppComposition.swift:17-25`, `Sources/SeshatSession/Models/Selection/DefaultModelService.swift:10,78-86`, `plans/central/LAYER_4_appstore.md:333,366-377` — The new active-mode adapter satisfies the protocol syntactically but not semantically. The protocol says:

  ```swift
  public protocol AppStoreActiveModeProviding: Sendable {
      func currentActiveMode() -> ModeDescriptor?
      func activeModeStream() -> AsyncStream<ModeDescriptor?>
  }
  ```

  but the conforming type is:

  ```swift
  public struct AppKitActiveModeProvider: AppStoreActiveModeProviding, Sendable {
      public func currentActiveMode() -> ModeDescriptor? {
          ModeRegistry.descriptor(for: ModeRegistry.defaultModeID) ?? ModeRegistry.dictation
      }

      public func activeModeStream() -> AsyncStream<ModeDescriptor?> {
          AsyncStream { continuation in
              continuation.yield(currentActiveMode())
              continuation.finish()
          }
      }
  }
  ```

  `AppComposition` already builds a shared `DefaultModelService`, and that service publishes real selection changes through `activeDescriptor`, but this adapter never reads that shared source and never stays subscribed. Why it matters: Step 2.1 explicitly says Layer 6 Stage 2 is a dependency so `AppStore.activeMode` can use a real provider instead of a second fallback truth, and Step 2.3 relies on `snapshot.activeMode?.name` for the status-item header. As landed, `AppStore.snapshot.activeMode` is pinned to the default mode rather than the shared live source. Suggested fix: expose the shared model/active-mode source from composition and implement `AppStoreActiveModeProviding` against that shared service's current value plus a live stream, or explicitly surface and approve the fallback divergence before landing.

### Minor

- `Sources/SeshatAppKit/Overlay/PillOverlayController.swift:14-20` and the Stage 2 diff deleting the old public convenience initializers at `Sources/SeshatAppKit/Overlay/PillOverlayController.swift:28-60` (parent version), plus `plans/central/LAYER_4_appstore.md:404-414` — Stage 2 removes the legacy `statePublisher` / `preparationProgressPublisher` initializer surface and leaves only the package-internal `init(appStore:...)`. Why it matters: the locked plan puts old publisher-surface cleanup in the later delete pass, not in the consumer-swap commit. Pulling that removal forward narrows the compatibility surface earlier than the Stage 2 discipline allows. Suggested fix: restore the deleted public convenience initializers as thin adapters during Stage 2 and leave their removal for the Step 3 cleanup pass.

### Nit

- None.

## Plan Fidelity Summary

- `2.1` — Partial. `SeshatAppMain` now creates one shared `AppStore`, starts it, and injects it into `MenuBarSceneModel`; `MenuBarSceneModel` no longer opens coordinator state/progress streams directly; `SessionCoordinator` gained the new adapter in `Sources/SeshatSession/AppStore/SessionCoordinator+AppStore.swift`. The remaining miss is the fallback-only active-mode provider.
- `2.2` — Partial. `PillOverlayController` now listens to the store instead of combining session/progress publishers, and `PillOverlayViewModel` no longer owns `computeVisibility(...)`, cached raw inputs, or local done/error timers. The consumer swap itself is correct, but the commit also deletes the old public publisher initializer surface early.
- `2.3` — Partial. `StatusItemController` now reads permissions from `snapshot.permissions`, and `StatusItemMenuModel` no longer defaults the header to `"Quick Memo"`. The status-item header path is still only partially migrated because `snapshot.activeMode` is sourced from the fallback adapter above rather than a real live provider.
- `Candidate A` — Mostly honored. Reads are centralized through `AppStore.snapshot`, the session adapter lives in the new Stage 2 directory, and the pill/state consumers are thin presentation adapters. The one material divergence is the active-mode seam falling back to `ModeRegistry.defaultModeID` instead of consuming the shared live source.

## Known Regressions On Trunk

Informational only; not scored as findings for this review.

- `PillOverlayViewModelTests.testHiddenModeHidesIdleButRecordingOverridesHidden`
- `PillOverlayViewModelTests.testSetVisibilityModeReevaluatesVisibilityImmediately`
- `StatusItemMenuModelTests.testErrorStateShowsStartRecording`

## Summary

The Stage 2 consumer swap is structurally close: the menu bar, pill path, and status item now all read from one shared `AppStore`, and the new session/visibility adapters are correctly scoped into Stage 2 files. The review stops at request-changes because the active-mode adapter silently diverges from the locked plan by hard-coding the default mode instead of wiring the already-existing live source, and because one legacy pill-controller API surface was removed a phase early.

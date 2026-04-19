# Layer 1 Stage 2 Code Review

## 1. Verdict
NEEDS REVISION

## 2. Scope & inputs

- Reviewed commits: `d6d3171` (`trunk: step permissions.2 — Layer 1 Stage 2 consumer swap`) and `05a2035` (`trunk: layer 1 stage 2 fix-forward — publicity + arg-label compile fixes`).
- Plan doc: `plans/central/LAYER_1_permissions.md`
- Prior reviews referenced: `plans/central/reviews/LAYER_1_review.md`, `plans/central/reviews/LAYER_1_stage1_code_review.md`
- Scope note: trunk contains an unrelated intervening commit, `e299b2e`, that only touches `Tests/SeshatAppKitTests/MenuBarSceneModelTests.swift`; functional findings below stay anchored to the Stage 2 source diffs and fix-forward.

## 3. Per-consumer audit table

| Site | Migrated? | Behavior preserved? | Notes |
|---|---|---|---|
| `PasteInjector` | Partial | Yes | Main injected path now checks `Permission.accessibility` and calls `request(.accessibility)` before leaving the transcript on the clipboard, matching Step 2.1 at `plans/central/LAYER_1_permissions.md:119-131`. The consumer still stores `PermissionServiceAdapter` and keeps a raw-AX compatibility initializer in `Sources/SeshatAppKit/Paste/PasteInjector.swift:101-133,287-324`. |
| `GlobalHotkeyMonitor` | Partial | Yes | Failed monitor install now reads `.inputMonitoring` through the unified service and preserves the same denied/pending/granted log text from `Sources/SeshatAppKit/Hotkeys/GlobalHotkeyMonitor.swift:110-138`, matching Step 2.2 at `plans/central/LAYER_1_permissions.md:133-145`. The public initializer still keeps `PermissionProbing` as compatibility input. |
| `MenuBarSceneModel` | Partial | Yes | Record-button flow now uses unified microphone status/request and routes Settings through `systemSettingsDeepLink(for: .microphone)` in `Sources/SeshatAppKit/MenuBar/MenuBarSceneModel.swift:119-141`, preserving the no-onboarding-reroute behavior required by Step 2.3 at `plans/central/LAYER_1_permissions.md:147-159`. The boundary is still `PermissionServiceAdapter`, not `any PermissionService`. |
| `OnboardingViewModel` | Partial | Yes | Requests now go through the unified service and `.skipped` stays view-model-local in `Sources/SeshatAppKit/Onboarding/OnboardingViewModel.swift:48-98`, matching Step 2.4 at `plans/central/LAYER_1_permissions.md:161-176`. The compatibility path still depends on `OnboardingPermissionProbing`. |
| `OnboardingWindowControllerHost` | Partial | Yes | `areCriticalPermissionsGranted` now requires only onboarding completion, microphone, and Input Monitoring in `Sources/SeshatAppKit/Onboarding/OnboardingWindowController.swift:106-110`, fixing the old AX-required mismatch called out in Step 2.4. The host still retains `SeshatOnboardingCompleted` per the plan’s open question at `plans/central/LAYER_1_permissions.md:170`. |
| `StatusItemController` | Partial | Yes | Menu rebuild now consumes the unified snapshot and service-owned deep links in `Sources/SeshatAppKit/MenuBar/StatusItemController.swift:125-139,204-239`, preserving warning ordering through `StatusItemMenuModel.makeUnified(...)`, consistent with Step 2.5 at `plans/central/LAYER_1_permissions.md:178-190`. The controller still depends on `PermissionServiceAdapter` and keeps fallback URL helpers. |
| `SeshatAppMain` | Partial | Mostly | The parameterless `init()` now creates one shared live service and injects it into onboarding, paste, menu bar, and hotkey composition in `Sources/SeshatAppKit/Composition/SeshatAppMain.swift:20-35,54-97,120-130`, matching Step 2.6 at `plans/central/LAYER_1_permissions.md:192-204`. The injectable initializer still has a default `PasteInjector()` path that can bypass that shared service. |
| `SeshatApp` | Partial | Yes | The injectable shell now resolves a unified service and passes it into `MenuBarSceneModel` in `Sources/SeshatAppKit/SeshatApp.swift:15-45`, which is the intended compile-coverage mirror for Step 2.6. It still relies on `PermissionServiceAdapter` and the `SeshatAppMain.makeCompatibilityPermissionService(...)` bridge instead of accepting `any PermissionService` directly. |

## 4. Findings by severity

### Critical

- None.

### Major

1. `Sources/SeshatAppKit/MenuBar/MenuBarSceneModel.swift:13`

   Quote:
   ```swift
   private let permissionService: PermissionServiceAdapter
   ```

   Issue:
   Stage 2 did not actually move the consumers to the `PermissionService` protocol boundary the plan requires. The same concrete-adapter dependency appears across the Stage 2 consumers in `Sources/SeshatAppKit/Paste/PasteInjector.swift:68`, `Sources/SeshatAppKit/Hotkeys/GlobalHotkeyMonitor.swift:34`, `Sources/SeshatAppKit/Onboarding/OnboardingViewModel.swift:27`, `Sources/SeshatAppKit/Onboarding/OnboardingWindowController.swift:70`, `Sources/SeshatAppKit/MenuBar/StatusItemController.swift:31`, `Sources/SeshatAppKit/Composition/SeshatAppMain.swift:21,41`, and `Sources/SeshatAppKit/SeshatApp.swift:18`. That diverges from the locked contract in `plans/central/LAYER_1_permissions.md:68-70,122,136,150,164,181,195`, which says the consumers should consume `PermissionService` and observe the single published snapshot through that protocol. The new code also subscribes to adapter-specific `$statuses` publishers, for example in `Sources/SeshatAppKit/Onboarding/OnboardingViewModel.swift:41-45` and `Sources/SeshatAppKit/MenuBar/StatusItemController.swift:92-101`, rather than observing the protocol surface directly.

   Suggested fix shape:
   Move consumer fields and initializer parameters to `any PermissionService` or a generic `Permissions: PermissionService`, and observe via `objectWillChange` plus `statusSnapshot()`/`statuses` at the protocol boundary. If a concrete bridge is still needed for a SwiftUI seam, keep that type-erasure private and local instead of making every consumer depend on it.

2. `Sources/SeshatAppKit/Permissions/Service/PermissionServiceAdapter.swift:29`

   Quote:
   ```swift
   self.observation = service.objectWillChange.sink { [weak self] _ in
       self?.statuses = service.statusSnapshot()
   }
   ```

   Issue:
   The adapter’s observation bridge is wrong for the fake-service compatibility path that Stage 2 is supposed to preserve. `objectWillChange` fires before `@Published` storage changes, so this sink snapshots the wrapped service too early. That is harmless for `AppKitPermissionService`, because its `statusSnapshot()` re-probes the OS (`Sources/SeshatAppKit/Permissions/Service/AppKitPermissionService.swift:55-65`), but it is incorrect for stored-status services such as `Tests/SeshatCoreTests/AppStore/Fakes/FakePermissionService.swift:35-40`, where `statusSnapshot()` just returns `statuses`. In that case the adapter mirrors the pre-update snapshot and the first published update is stale. This is a Stage 2 regression in the advertised “wrap a fake `PermissionService`” test path, and it is currently unpinned because no test exercises `PermissionServiceAdapter` directly.

   Suggested fix shape:
   Defer the snapshot onto the next main-actor turn inside the sink, or expose a post-mutation publisher/read hook from the wrapped service. `Sources/SeshatCore/AppStore/AppStore.swift:46-50` already shows the safer pattern: it observes `objectWillChange` and then hops to a later main-actor task before re-reading `statusSnapshot()`.

3. `Sources/SeshatAppKit/Composition/SeshatAppMain.swift:43`

   Quote:
   ```swift
   pasteInjector: any PasteInjecting = PasteInjector(),
   ```

   Issue:
   The injectable `SeshatAppMain` initializer does not actually default paste wiring to the shared permission service it resolves later in the body. `Sources/SeshatAppKit/Composition/SeshatAppMain.swift:54-59` computes a shared `permissionService`, but if a caller omits `pasteInjector`, the default argument has already built a standalone `PasteInjector()` on the raw compatibility path. That breaks Step 2.6’s “inject one shared `PermissionService` into ... paste” guarantee from `plans/central/LAYER_1_permissions.md:195,202`, except in the parameterless production `init()` that remembers to override the argument explicitly at `Sources/SeshatAppKit/Composition/SeshatAppMain.swift:24-35`.

   Suggested fix shape:
   Make `pasteInjector` optional, resolve the permission service first inside the initializer body, and then default to `PasteInjector(permissionService: permissionService)` when the caller does not provide a custom injector.

### Minor

- None.

### Nit

- None.

## 5. Cross-layer concerns

- `PermissionServiceAdapter`
  Temporary scaffolding is understandable here: Stage 2 needed a bridge while old initializers and tests still traffic in legacy probes/requesters. The current implementation is only robust for the live `AppKitPermissionService` and the closure-backed compatibility constructors, though; it is not a sound long-term public abstraction for arbitrary fake `PermissionService` values because of the pre-mutation observation bug above. If the adapter survives past Stage 2, it should become an implementation detail behind protocol-typed consumers.

- `AppKitMicrophonePermissionRequester`
  Keeping this around as a Stage 2 legacy shim is reasonable. `Sources/SeshatAppKit/Composition/SeshatAppMain.swift:229-233` uses a narrow downcast to seed microphone status when constructing the compatibility adapter, which is acceptable as temporary glue. This should disappear in Stage 3 once the shell/tests inject fake or live `PermissionService` values directly.

- `SeshatAppMain.makeCompatibilityPermissionService`
  This is the right short-term pattern only if it is treated as disposable compatibility code. It keeps `SeshatApp` and the injectable `SeshatAppMain` compiling while legacy requester/probe-based tests still exist, but it also carries the only remaining `AppKitMicrophonePermissionRequester` downcast in app composition and it interacts poorly with the default `pasteInjector` parameter. It is removable in Stage 3 and should be removed there.

## 6. Test coverage gaps

- `PermissionServiceAdapter` has no direct test coverage. The new bridge in `Sources/SeshatAppKit/Permissions/Service/PermissionServiceAdapter.swift:6-89` is now part of the consumer-swap path, but no suite wraps a fake/live `PermissionService` and verifies observation, refresh, or request semantics through the adapter.
- The plan’s named Stage 2 consumer suites were not converted to fake `PermissionService` usage:
  - `Tests/SeshatAppKitTests/OnboardingViewModelTests.swift:8,18,30,86,106` still drive `OnboardingViewModel` through `OnboardingPermissionProbing`.
  - `Tests/SeshatAppKitTests/GlobalHotkeyMonitorTests.swift:289-292,307-310` still drive `GlobalHotkeyMonitor` through `PermissionProbing`.
  - `Tests/SeshatAppKitTests/MenuBarSceneModelTests.swift:13-20,28-35,51-58` still exercise mic-only requester/state inputs instead of a fake shared service.
  - `Tests/SeshatAppKitTests/AppEntryPointTests.swift:17-25` and `Tests/SeshatAppKitTests/MenuBarFlowIntegrationTests.swift:116-125` do not exercise the shared-service injection path.
  - `Tests/SeshatAppKitTests/MenuBar/StatusItemMenuModelTests.swift:12-217` still cover the legacy `make(...)` wrapper, not the unified `makeUnified(...)` path that `StatusItemController` now uses.
- Manual verification runbooks were not extended with the Stage 2 refresh checks requested by the plan:
  - `Tests/SeshatAppKitTests/ManualOnboardingVerification.md:18-25` has no “return from System Settings and verify refresh” step.
  - `Tests/SeshatAppKitTests/ManualStatusItemVerification.md:13-26` has no menu-warning refresh check after `NSApplication.didBecomeActiveNotification`.

## 7. Summary

The live production composition mostly preserves Stage 2 behavior: paste still falls back to the clipboard, hotkey failure logging still distinguishes denied vs pending vs granted, menu-bar mic prompting still happens in the same order, and onboarding now correctly treats Accessibility as optional in both the view model and the host gate. The two substantive blockers are architectural rather than UX-facing: the consumer swap stopped at a new concrete `PermissionServiceAdapter` instead of the `PermissionService` protocol boundary the plan requires, and that adapter’s observation bridge is incorrect for wrapped fake services, which undercuts the very compatibility path it was added to provide. `SeshatAppMain` also still has one integration seam where the default paste injector can bypass the shared service outside the parameterless production init.

# 1. Verdict

REQUEST-CHANGES

# 2. Scope summary

- Reviewed commits:
  - `883daddbc30925626023c36c08936ad311eaa3ca` (`trunk: step permissions.2 — Layer 1 Stage 2 consumer swap`)
  - `d6d31711b8c88e523f204056373defd51b69eb9d` (`trunk: step permissions.2 — Layer 1 Stage 2 consumer swap`)
- `git show --stat` is identical for both SHAs: 11 `Sources/**` files, `720 insertions(+), 110 deletions(-)`.
- Direct Layer 1 write set (11 files):
  - `Sources/SeshatAppKit/Composition/AppComposition.swift`
  - `Sources/SeshatAppKit/Composition/SeshatAppMain.swift`
  - `Sources/SeshatAppKit/Hotkeys/GlobalHotkeyMonitor.swift`
  - `Sources/SeshatAppKit/MenuBar/MenuBarSceneModel.swift`
  - `Sources/SeshatAppKit/MenuBar/StatusItemController.swift`
  - `Sources/SeshatAppKit/MenuBar/StatusItemMenuModel.swift`
  - `Sources/SeshatAppKit/Onboarding/OnboardingViewModel.swift`
  - `Sources/SeshatAppKit/Onboarding/OnboardingWindowController.swift`
  - `Sources/SeshatAppKit/Paste/PasteInjector.swift`
  - `Sources/SeshatAppKit/Permissions/Service/PermissionServiceAdapter.swift`
  - `Sources/SeshatAppKit/SeshatApp.swift`
- `git diff 883dadd d6d3171 -- Sources/SeshatAppKit` is empty. The broader `git diff 883dadd~1..d6d3171 -- Sources/` expands to 21 files because `d6d3171` sits on unrelated later work.
- Extra non-Layer-1 files in that broader range (10 files):
  - `Sources/SeshatCore/AppStore/AppStore.swift`
  - `Sources/SeshatCore/AppStore/AppStoreActiveModeProviding.swift`
  - `Sources/SeshatCore/AppStore/AppStoreClock.swift`
  - `Sources/SeshatCore/AppStore/AppStoreSessionProviding.swift`
  - `Sources/SeshatCore/AppStore/AppStoreSnapshot.swift`
  - `Sources/SeshatCore/AppStore/AppStoreVisibilityMode.swift`
  - `Sources/SeshatCore/AppStore/AppStoreVisibilityModeProviding.swift`
  - `Sources/SeshatCore/AppStore/PillVisibilityState.swift`
  - `Sources/SeshatCore/Storage/DiskSpaceSnapshot.swift`
  - `Sources/SeshatCore/Storage/FileManagerAtomicFileWriter.swift`

# 3. Findings grouped by severity

## Blocker

- None.

## Major

- The core Stage 2 swap did not actually remove the old Layer 1 constructor surface; several plan-listed consumers still accept legacy types and then synthesize a `PermissionServiceAdapter` from them. Evidence: `Sources/SeshatAppKit/MenuBar/MenuBarSceneModel.swift:85-129`, `Sources/SeshatAppKit/MenuBar/MenuBarSceneModel.swift:227-275`, `Sources/SeshatAppKit/Hotkeys/GlobalHotkeyMonitor.swift:48-78`, `Sources/SeshatAppKit/Hotkeys/GlobalHotkeyMonitor.swift:338-364`, `Sources/SeshatAppKit/Onboarding/OnboardingWindowController.swift:80-103`, `Sources/SeshatAppKit/Onboarding/OnboardingWindowController.swift:165-193`, `Sources/SeshatAppKit/Composition/SeshatAppMain.swift:35-61`, and `Sources/SeshatAppKit/Composition/SeshatAppMain.swift:226-306`.

- The onboarding flow was not consumer-swapped off the old onboarding-only model. `OnboardingPermissionOutcome` still drives the view and view model, `OnboardingViewModel` still defaults to `OnboardingPermissionProbing`, and the old `PermissionRequester` actor remains live. Evidence: `Sources/SeshatAppKit/Onboarding/OnboardingView.swift:205-326`, `Sources/SeshatAppKit/Onboarding/OnboardingViewModel.swift:5-39`, `Sources/SeshatAppKit/Onboarding/OnboardingViewModel.swift:97-167`, and `Sources/SeshatAppKit/Onboarding/PermissionRequester.swift:9-63`.

- `SeshatOnboardingCompleted` / `OnboardingState` remain live in the exact Step 2.5 and Step 2.6 consumers the plan said had to remove them or explicitly block on the open Step 2.4 question. I found no such explicit block in `883dadd` or `d6d3171`; the dependency was quietly preserved. Evidence: `Sources/SeshatAppKit/MenuBar/StatusItemController.swift:20-29`, `Sources/SeshatAppKit/MenuBar/StatusItemController.swift:45-55`, `Sources/SeshatAppKit/Onboarding/OnboardingWindowController.swift:103`, `Sources/SeshatAppKit/Onboarding/OnboardingWindowController.swift:154`, `Sources/SeshatAppKit/Composition/SeshatAppMain.swift:92-94`, and `Sources/SeshatAppKit/Composition/SeshatAppMain.swift:338-341`.

- Neither `permissions.2` commit updated any tests even though the Stage 2 plan names test migrations for the hotkey path, menu bar path, onboarding flow, and app entry point. `git show --stat 883dadd` and `git show --stat d6d3171` touch only `Sources/**`, and the targeted tests still bind to the old symbols. Evidence: commit SHAs `883daddbc30925626023c36c08936ad311eaa3ca` and `d6d31711b8c88e523f204056373defd51b69eb9d`; `Tests/SeshatAppKitTests/GlobalHotkeyMonitorTests.swift:386-388`; `Tests/SeshatAppKitTests/MenuBarSceneModelTests.swift:630-632`; `Tests/SeshatAppKitTests/OnboardingViewModelTests.swift:62`; `Tests/SeshatAppKitTests/OnboardingViewModelTests.swift:72`; `Tests/SeshatAppKitTests/OnboardingViewModelTests.swift:82`; `Tests/SeshatAppKitTests/OnboardingViewModelTests.swift:104`; `Tests/SeshatAppKitTests/OnboardingViewModelTests.swift:109`; and `Tests/SeshatAppKitTests/OnboardingViewModelTests.swift:125-149`.

## Minor

- `d6d3171` is not a second Layer 1 consumer-swap revision; for the Layer 1 AppKit surface it is a no-op relative to `883dadd`. Evidence: `git diff 883dadd d6d3171 -- Sources/SeshatAppKit` is empty, while `git diff 883dadd~1..d6d3171 -- Sources/` adds unrelated `Sources/SeshatCore/AppStore/*` and `Sources/SeshatCore/Storage/*` files.

## Nit

- None.

# 4. Consumer-swap completeness audit

Classification key:

- `(a)` legitimate remaining bridge/composition seam
- `(b)` test-only reference OK to survive Stage 2
- `(c)` genuine missed-consumer-swap that Stage 2 was supposed to handle

## `MicrophonePermissionState`

- Live refs: 12 across 7 files.
- `(a)` `Sources/SeshatAppKit/MenuBar/MicrophonePermissionState.swift:4`; `Sources/SeshatAppKit/MenuBar/StatusItemMenuModel.swift:143`; `Sources/SeshatAppKit/Permissions/AppKitMicrophonePermissionRequester.swift:41`; `Sources/SeshatAppKit/Permissions/AppKitMicrophonePermissionRequester.swift:45`; `Sources/SeshatAppKit/Permissions/Service/PermissionServiceAdapter.swift:107`; `Sources/SeshatAppKit/Permissions/Service/PermissionServiceAdapter.swift:134`.
- `(c)` `Sources/SeshatAppKit/MenuBar/MenuBarSceneModel.swift:55`; `Sources/SeshatAppKit/MenuBar/MenuBarSceneModel.swift:88`; `Sources/SeshatAppKit/MenuBar/MenuBarSceneModel.swift:229`; `Sources/SeshatAppKit/Onboarding/OnboardingWindowController.swift:84`; `Sources/SeshatAppKit/Onboarding/OnboardingWindowController.swift:166`; `Sources/SeshatAppKit/SeshatApp.swift:19`.

## `InputMonitoringPermissionState`

- Live refs: 16 across 8 files.
- `(a)` `Sources/SeshatAppKit/Hotkeys/GlobalHotkeyMonitor.swift:135`; `Sources/SeshatAppKit/MenuBar/StatusItemMenuModel.swift:144`; `Sources/SeshatAppKit/Permissions/Service/PermissionServiceAdapter.swift:120`; `Sources/SeshatCore/InputMonitoringPermissionProbe.swift:6`; `Sources/SeshatCore/InputMonitoringPermissionProbe.swift:13`; `Sources/SeshatCore/InputMonitoringPermissionProbe.swift:29`.
- `(b)` `Tests/SeshatCoreTests/PermissionStatusTests.swift:6`; `Tests/SeshatCoreTests/PermissionStatusTests.swift:7`; `Tests/SeshatCoreTests/PermissionStatusTests.swift:8`; `Tests/SeshatCoreTests/PermissionStatusTests.swift:9`; `Tests/SeshatCoreTests/PermissionStatusTests.swift:14`; `Tests/SeshatCoreTests/PermissionStatusTests.swift:15`.
- `(c)` `Sources/SeshatAppKit/Onboarding/PermissionRequester.swift:55`; `Tests/SeshatAppKitTests/GlobalHotkeyMonitorTests.swift:387`; `Tests/SeshatAppKitTests/GlobalHotkeyMonitorTests.swift:388`; `Tests/SeshatAppKitTests/MenuBarSceneModelTests.swift:631`.

## `OnboardingPermissionOutcome`

- Live refs: 27 across 5 files.
- `(a)` `Sources/SeshatAppKit/Permissions/Service/PermissionServiceAdapter.swift:145`.
- `(c)` `Sources/SeshatAppKit/Onboarding/OnboardingView.swift:210`; `Sources/SeshatAppKit/Onboarding/OnboardingView.swift:276`; `Sources/SeshatAppKit/Onboarding/OnboardingView.swift:295`; `Sources/SeshatAppKit/Onboarding/OnboardingView.swift:320`; `Sources/SeshatAppKit/Onboarding/OnboardingViewModel.swift:5`; `Sources/SeshatAppKit/Onboarding/OnboardingViewModel.swift:14`; `Sources/SeshatAppKit/Onboarding/OnboardingViewModel.swift:15`; `Sources/SeshatAppKit/Onboarding/OnboardingViewModel.swift:16`; `Sources/SeshatAppKit/Onboarding/OnboardingViewModel.swift:157`; `Sources/SeshatAppKit/Onboarding/PermissionRequester.swift:10`; `Sources/SeshatAppKit/Onboarding/PermissionRequester.swift:11`; `Sources/SeshatAppKit/Onboarding/PermissionRequester.swift:12`; `Sources/SeshatAppKit/Onboarding/PermissionRequester.swift:16`; `Sources/SeshatAppKit/Onboarding/PermissionRequester.swift:34`; `Sources/SeshatAppKit/Onboarding/PermissionRequester.swift:38`; `Sources/SeshatAppKit/Onboarding/PermissionRequester.swift:43`; `Sources/SeshatAppKit/Onboarding/PermissionRequester.swift:55`; `Tests/SeshatAppKitTests/OnboardingViewModelTests.swift:126`; `Tests/SeshatAppKitTests/OnboardingViewModelTests.swift:127`; `Tests/SeshatAppKitTests/OnboardingViewModelTests.swift:128`; `Tests/SeshatAppKitTests/OnboardingViewModelTests.swift:131`; `Tests/SeshatAppKitTests/OnboardingViewModelTests.swift:132`; `Tests/SeshatAppKitTests/OnboardingViewModelTests.swift:133`; `Tests/SeshatAppKitTests/OnboardingViewModelTests.swift:140`; `Tests/SeshatAppKitTests/OnboardingViewModelTests.swift:144`; `Tests/SeshatAppKitTests/OnboardingViewModelTests.swift:148`.

## `PermissionProbing`

- Live refs: 11 across 6 files.
- `(a)` `Sources/SeshatCore/InputMonitoringPermissionProbe.swift:12`; `Sources/SeshatCore/InputMonitoringPermissionProbe.swift:26`.
- `(b)` `Tests/SeshatCoreTests/PermissionStatusTests.swift:13`.
- `(c)` `Sources/SeshatAppKit/Composition/SeshatAppMain.swift:45`; `Sources/SeshatAppKit/Composition/SeshatAppMain.swift:228`; `Sources/SeshatAppKit/Hotkeys/GlobalHotkeyMonitor.swift:65`; `Sources/SeshatAppKit/Hotkeys/GlobalHotkeyMonitor.swift:339`; `Sources/SeshatAppKit/Onboarding/OnboardingWindowController.swift:85`; `Sources/SeshatAppKit/Onboarding/OnboardingWindowController.swift:167`; `Tests/SeshatAppKitTests/GlobalHotkeyMonitorTests.swift:386`; `Tests/SeshatAppKitTests/MenuBarSceneModelTests.swift:630`.

## `OnboardingPermissionProbing`

- Live refs: 6 across 3 files.
- `(c)` `Sources/SeshatAppKit/Onboarding/OnboardingViewModel.swift:34`; `Sources/SeshatAppKit/Onboarding/OnboardingViewModel.swift:114`; `Sources/SeshatAppKit/Onboarding/PermissionRequester.swift:9`; `Sources/SeshatAppKit/Onboarding/PermissionRequester.swift:15`; `Tests/SeshatAppKitTests/OnboardingViewModelTests.swift:104`; `Tests/SeshatAppKitTests/OnboardingViewModelTests.swift:125`.

## `AppKitMicrophonePermissionRequester`

- Live refs: 12 across 6 files.
- `(a)` `Sources/SeshatAppKit/Permissions/AppKitMicrophonePermissionRequester.swift:5`.
- `(b)` `Tests/SeshatAppKitTests/AppCompositionTests.swift:19`; `Tests/SeshatAppKitTests/AppKitMicrophonePermissionRequesterTests.swift:9`; `Tests/SeshatAppKitTests/AppKitMicrophonePermissionRequesterTests.swift:14`; `Tests/SeshatAppKitTests/AppKitMicrophonePermissionRequesterTests.swift:23`; `Tests/SeshatAppKitTests/AppKitMicrophonePermissionRequesterTests.swift:32`; `Tests/SeshatAppKitTests/AppKitMicrophonePermissionRequesterTests.swift:42`; `Tests/SeshatAppKitTests/AppKitMicrophonePermissionRequesterTests.swift:58`.
- `(c)` `Sources/SeshatAppKit/Composition/AppComposition.swift:117-119`; `Sources/SeshatAppKit/Composition/SeshatAppMain.swift:241`; `Sources/SeshatAppKit/MenuBar/MenuBarSceneModel.swift:87`; `Sources/SeshatAppKit/SeshatApp.swift:36`.

## `SeshatOnboardingCompleted`

- Live refs: 12 across 5 files.
- `(a)` `Sources/SeshatCore/OnboardingState.swift:5`; `Sources/SeshatCore/OnboardingState.swift:19`; `Sources/SeshatCore/OnboardingState.swift:34`.
- `(c)` `Sources/SeshatAppKit/Composition/SeshatAppMain.swift:93`; `Sources/SeshatAppKit/Composition/SeshatAppMain.swift:340`; `Sources/SeshatAppKit/MenuBar/StatusItemController.swift:25`; `Sources/SeshatAppKit/MenuBar/StatusItemController.swift:51`; `Sources/SeshatAppKit/Onboarding/OnboardingWindowController.swift:103`; `Tests/SeshatAppKitTests/OnboardingViewModelTests.swift:62`; `Tests/SeshatAppKitTests/OnboardingViewModelTests.swift:72`; `Tests/SeshatAppKitTests/OnboardingViewModelTests.swift:82`; `Tests/SeshatAppKitTests/OnboardingViewModelTests.swift:109`.

## `OnboardingState.swift`

- Live refs: 0 string refs in `Sources/**` and `Tests/**`.
- The file still exists at `Sources/SeshatCore/OnboardingState.swift`.
- This plan row is a filename, not a grep-able symbol. The real live dependency is already captured under `SeshatOnboardingCompleted` and `OnboardingState.completed.persist(...)` at `Sources/SeshatAppKit/Onboarding/OnboardingWindowController.swift:154`.

## `InputMonitoringPermissionProbe.swift`

- Live refs: 0 string refs in `Sources/**` and `Tests/**`.
- The file still exists at `Sources/SeshatCore/InputMonitoringPermissionProbe.swift`.
- This plan row is a filename, not a grep-able symbol. The real live dependencies are already captured under `PermissionProbing` and `InputMonitoringPermissionState`.

## Cleanup matrix

| Symbol | Live ref count | Classification | Action |
|---|---:|---|---|
| `MicrophonePermissionState` | 12 | mixed (`a=6`, `c=6`) | needs S2 retry |
| `InputMonitoringPermissionState` | 16 | mixed (`a=6`, `b=6`, `c=4`) | needs S2 retry |
| `OnboardingPermissionOutcome` | 27 | mixed (`a=1`, `c=26`) | needs S2 retry |
| `PermissionProbing` | 11 | mixed (`a=2`, `b=1`, `c=8`) | needs S2 retry |
| `OnboardingPermissionProbing` | 6 | missed swap only (`c=6`) | needs S2 retry |
| `AppKitMicrophonePermissionRequester` | 12 | mixed (`a=1`, `b=7`, `c=4`) | needs S2 retry |
| `SeshatOnboardingCompleted` | 12 | mixed (`a=3`, `c=9`) | needs S2 retry |
| `OnboardingState.swift` | 0 string refs | filename-only plan entry; real dependency captured under `SeshatOnboardingCompleted` | needs plan update |
| `InputMonitoringPermissionProbe.swift` | 0 string refs | filename-only plan entry; real dependency captured under `PermissionProbing` / `InputMonitoringPermissionState` | needs plan update |

- Result: 0 symbols are fully `OK`.
- Result: 7 symbols have genuine missed-swap refs (`(c)` present).
- Result: 2 plan entries need wording cleanup because they are filename rows rather than symbol rows.

# 5. Plan Fidelity Summary

- `Step 2.1 - PasteInjector`: landed. `Sources/SeshatAppKit/Paste/PasteInjector.swift` has no live refs to any Stage 3 Layer 1 symbol and now gates Accessibility through `PermissionService`.
- `Step 2.2 - GlobalHotkeyMonitor`: partial. Runtime permission reads moved to the unified service, but the consumer still exposes `PermissionProbing` and `InputMonitoringPermissionState` compatibility surface in `Sources/SeshatAppKit/Hotkeys/GlobalHotkeyMonitor.swift:65`, `Sources/SeshatAppKit/Hotkeys/GlobalHotkeyMonitor.swift:135`, and `Sources/SeshatAppKit/Hotkeys/GlobalHotkeyMonitor.swift:339`.
- `Step 2.3 - MenuBarSceneModel`: partial. Runtime state is unified, but `MicrophonePermissionState` and `AppKitMicrophonePermissionRequester` remain live in `Sources/SeshatAppKit/MenuBar/MenuBarSceneModel.swift:55`, `Sources/SeshatAppKit/MenuBar/MenuBarSceneModel.swift:87-88`, and `Sources/SeshatAppKit/MenuBar/MenuBarSceneModel.swift:229`.
- `Step 2.4 - onboarding flow`: missed/partial. `Sources/SeshatAppKit/Onboarding/OnboardingViewModel.swift:32-39` can accept a `PermissionService`, but the flow still centers on `OnboardingPermissionOutcome`, `OnboardingPermissionProbing`, `PermissionRequester`, `MicrophonePermissionState`, `PermissionProbing`, and `SeshatOnboardingCompleted`.
- `Step 2.5 - StatusItemController`: partial. The controller now rebuilds from `StatusItemMenuModel.makeUnified(...)`, but it still reads `SeshatOnboardingCompleted` in `Sources/SeshatAppKit/MenuBar/StatusItemController.swift:25` and `Sources/SeshatAppKit/MenuBar/StatusItemController.swift:51`, which the plan explicitly said must be removed or explicitly blocked.
- `Step 2.6 - SeshatAppMain`: partial. The default path can compose `AppKitPermissionService`, but `Sources/SeshatAppKit/Composition/SeshatAppMain.swift:37-46`, `Sources/SeshatAppKit/Composition/SeshatAppMain.swift:226-306`, `Sources/SeshatAppKit/Composition/AppComposition.swift:117-123`, and `Sources/SeshatAppKit/SeshatApp.swift:17-43` still preserve the legacy mic/IM/onboarding composition path.
- Acceptance-test fidelity: missed. Both reviewed commits touch zero `Tests/**` files even though the plan names concrete test migrations for Steps 2.2, 2.4, 2.5, and 2.6.
- Stage 3 readiness: not ready. The delete list still has genuine missed-swap refs for 7 of 9 plan-listed entries, and the remaining 2 entries need plan wording cleanup before a delete audit can be mechanically accurate.

# 6. Summary + Recommendation

- This Stage 2 swap is not complete enough to support the Layer 1 Stage 3 delete pass. The runtime path clearly moved toward `PermissionService`, but most of the old Layer 1 surfaces were wrapped rather than retired.
- Recommended L1 S2 retry PR order:
  1. Onboarding cluster first: `Sources/SeshatAppKit/Onboarding/OnboardingView.swift`, `Sources/SeshatAppKit/Onboarding/OnboardingViewModel.swift`, `Sources/SeshatAppKit/Onboarding/OnboardingWindowController.swift`, `Sources/SeshatAppKit/Onboarding/PermissionRequester.swift`, and `Tests/SeshatAppKitTests/OnboardingViewModelTests.swift`. This clears the densest missed-swap set: `OnboardingPermissionOutcome`, `OnboardingPermissionProbing`, `PermissionProbing`, `MicrophonePermissionState`, and `SeshatOnboardingCompleted`.
  2. Composition cluster second: `Sources/SeshatAppKit/Composition/SeshatAppMain.swift`, `Sources/SeshatAppKit/Composition/AppComposition.swift`, and `Sources/SeshatAppKit/SeshatApp.swift`. This removes the compatibility builders that keep rehydrating the old mic/IM/requester surface.
  3. Menu bar cluster third: `Sources/SeshatAppKit/MenuBar/MenuBarSceneModel.swift`, `Sources/SeshatAppKit/MenuBar/StatusItemController.swift`, `Sources/SeshatAppKit/MenuBar/StatusItemMenuModel.swift`, and `Tests/SeshatAppKitTests/MenuBarSceneModelTests.swift`.
  4. Hotkey cluster fourth: `Sources/SeshatAppKit/Hotkeys/GlobalHotkeyMonitor.swift` and `Tests/SeshatAppKitTests/GlobalHotkeyMonitorTests.swift`.
  5. After the retry PR, rerun the delete audit and update the Stage 3 plan rows for `OnboardingState.swift` and `InputMonitoringPermissionProbe.swift` so the delete matrix tracks exported symbols instead of filename strings.
- `PasteInjector` does not appear to need a retry; it is the only plan-listed Stage 2 consumer that looks fully migrated off the old Layer 1 symbols.

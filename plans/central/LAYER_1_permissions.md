# Layer 1 - Permissions

## Critical discipline
> **Do NOT diverge from this plan. Silent divergence is the cardinal sin. To deviate, surface the proposed divergence in a commit-message comment AND in the hand-off report; wait for main-session confirmation. Paraphrasing the contract is divergence. Renaming a protocol the plan specifies is divergence. Choosing a different storage format than the plan specifies is divergence.**

## Why this layer exists
Permission handling is split across mic-only, Input Monitoring-only, and onboarding-only types today. `Sources/SeshatCore/Protocols.swift:38-40` exposes only `MicrophonePermissionRequesting`, `Sources/SeshatCore/PermissionStatus.swift:6-44` owns only `InputMonitoringPermissionState` plus `PermissionProbing`, and `Sources/SeshatAppKit/Onboarding/PermissionRequester.swift:9-63` re-implements three-permission request semantics with different truth tables. That fragmentation leaks into the menu bar, onboarding, paste, hotkey, and app-entry surfaces, so each site decides for itself when to prompt, when to deep-link to System Settings, and what "pending" means.

Layer 1 centralizes those facts into one observable permission service with one refreshable snapshot and one set of deep links. That is required to fix the current Accessibility mismatch between `OnboardingViewModel` and `OnboardingWindowController`, preserve the clipboard fallback already implemented in `PasteInjector`, and unblock Layer 4's state store plus Layer 9's TCC-link centralization per `plans/CENTRAL_LAYERS_PROMPT.md:160-180`.

## Observed current spread
| File | Line(s) | What lives there |
|---|---|---|
| `Sources/SeshatCore/Protocols.swift` | `38-40` | `MicrophonePermissionRequesting` only models microphone access. |
| `Sources/SeshatCore/PermissionStatus.swift` | `6-44` | `InputMonitoringPermissionState`, `PermissionProbing`, and `IOHIDPermissionProbe`; note `IOHIDCheckAccess` remains `.notDetermined` until after a monitor-install attempt (`22-25`). |
| `Sources/SeshatAppKit/MenuBar/MicrophonePermissionState.swift` | `3-7` | `MicrophonePermissionState` duplicates microphone status with its own `.notYetRequested` case. |
| `Sources/SeshatAppKit/Permissions/AppKitMicrophonePermissionRequester.swift` | `4-56` | Mic-only live requester maps `AVAuthorizationStatus` and prompts only when not determined. |
| `Sources/SeshatAppKit/Onboarding/PermissionRequester.swift` | `9-63` | `OnboardingPermissionProbing` plus `PermissionRequester` re-implement microphone, Input Monitoring, and Accessibility requests; untrusted AX currently maps to `.denied` (`38-40`). |
| `Sources/SeshatAppKit/Onboarding/OnboardingViewModel.swift` | `4-24` | `OnboardingPermissionOutcome` adds `.skipped`; `canContinue` already requires microphone plus Input Monitoring only; Accessibility stays UI-local. |
| `Sources/SeshatAppKit/Onboarding/OnboardingView.swift` | `54-356` | The onboarding SwiftUI view renders three permission rows from `OnboardingPermissionOutcome`, including optional-AX warning copy and the `Open Settings`/`Skipped` states. |
| `Sources/SeshatAppKit/Onboarding/OnboardingWindowController.swift` | `67-156` | Startup host reads `MicrophonePermissionState`, `PermissionProbing`, AX trust, and `SeshatOnboardingCompleted`; `areCriticalPermissionsGranted` still requires AX (`98-103`). |
| `Sources/SeshatCore/OnboardingState.swift` | `3-34` | `OnboardingState` persists first-run completion and exports `SeshatOnboardingCompleted`. |
| `Sources/SeshatAppKit/Paste/PasteInjector.swift` | `68-171` | Paste path does direct AX trust checks and prompts; if AX is missing it leaves text on the clipboard (`168-171`). |
| `Sources/SeshatAppKit/Hotkeys/GlobalHotkeyMonitor.swift` | `34-129` | Hotkey monitor logs Input Monitoring failures through `PermissionProbing` and `InputMonitoringPermissionState`. |
| `Sources/SeshatAppKit/MenuBar/MenuBarSceneModel.swift` | `8-118` | Menu-bar scene model stores mic-only permission state and requester. |
| `Sources/SeshatAppKit/MenuBar/StatusItemController.swift` | `31-267` | Status item controller probes IM directly, owns mic/IM System Settings URLs, and still reads onboarding completion. |
| `Sources/SeshatAppKit/MenuBar/StatusItemMenuModel.swift` | `65-172` | Menu warning rows are keyed to split mic/IM enums and suppress warnings while permission is pending/not-yet-requested. |
| `Sources/SeshatAppKit/Composition/SeshatAppMain.swift` | `9-245` | App entry composes split microphone requester, Input Monitoring probe, AX closure, onboarding completion state, and paste dependencies. |
| `Sources/SeshatAudio/AVAudioCaptureService.swift` | `39-45` | Audio capture keeps its own direct microphone authorization guard that must remain untouched. |
| `Tests/SeshatCoreTests/PermissionStatusTests.swift` | `4-33` | Core tests currently pin only the IM-specific enum/probe surface. |
| `Tests/SeshatAppKitTests/AppKitMicrophonePermissionRequesterTests.swift` | `7-70` | AppKit tests currently pin only mic-requester mapping and caching behavior. |
| `Tests/SeshatAppKitTests/OnboardingViewModelTests.swift` | `7-99` | Existing tests pin optional-AX onboarding behavior and `.skipped` staying in UI state. |
| `Tests/SeshatAppKitTests/PasteInjectorTests.swift` | `20-203` | Existing tests pin AX prompt/clipboard fallback and restore-delay reads. |
| `Tests/SeshatAppKitTests/GlobalHotkeyMonitorTests.swift` | `286-322` | Existing tests pin denied/pending/granted Input Monitoring log messaging. |
| `Tests/SeshatAppKitTests/MenuBarSceneModelTests.swift` | `11-120,291-445,504-515` | Existing tests pin mic prompt/toggle behavior, clipboard-only notices, open-settings behavior, and the injectable app shell compile seam. |
| `Tests/SeshatAppKitTests/MenuBar/StatusItemMenuModelTests.swift` | `101-172` | Existing tests pin warning ordering and the "no warning while pending" rule. |
| `Tests/SeshatAppKitTests/AppEntryPointTests.swift` | `8-31` | Current app-entry test constructs `SeshatAppMain` with split permission collaborators. |
| `Tests/SeshatAppKitTests/MenuBarFlowIntegrationTests.swift` | `87-149` | Integration guard ensures `SeshatAppMain.init()` does not block startup work on the main actor. |
| `Tests/SeshatAppKitTests/SeshatAppKitPermissionsCompileTests.swift` | `4-7` | Compile-only guard for the current AppKit permissions module surface. |
| `Tests/SeshatAppKitTests/ManualOnboardingVerification.md` | `12-25` | Manual runbook already treats AX as optional and clipboard fallback as required UX. |
| `Tests/SeshatAppKitTests/ManualStatusItemVerification.md` | `13-26` | Manual runbook exists for status-item behavior and is the right place to add activation-refresh checks. |

## Proposed API / contracts
The following locked decisions are restated verbatim and apply to every step in this layer:

- Permission enum cases: microphone, inputMonitoring, accessibility.
- PermissionStatus enum cases: pending, granted, denied.
- RequestOutcome struct fields: prompted, openedSettings, requiresRelaunch, finalStatus.
- Service is @MainActor, not just Sendable.
- refresh() triggered on NSApplication.didBecomeActiveNotification; one @Published dictionary exposing all three permissions; NO per-permission AsyncStream.
- Accessibility (AX) maps to .pending when AXIsProcessTrusted() is false — NEVER to .denied.
- Stage 3 deletions (exact list): MicrophonePermissionState, InputMonitoringPermissionState, OnboardingPermissionOutcome, PermissionProbing, OnboardingPermissionProbing, AppKitMicrophonePermissionRequester, SeshatOnboardingCompleted, OnboardingState.swift, PermissionStatus.swift.
- Stage 2 call-site migrations (exact list): PasteInjector, GlobalHotkeyMonitor, MenuBarSceneModel, the onboarding flow, StatusItemController, SeshatAppMain.
- Naming: rename at creation time — NO 'Seshat' prefix on new types.
- AX is optional everywhere (locked decision #6 in prompt).
- AVAudioCaptureService.swift:41 guard stays as-is; do NOT inject the new service into SeshatAudio (locked decision #5 in prompt).

### Types (enums, structs)
- `Permission` is the shared domain enum with exactly `microphone`, `inputMonitoring`, and `accessibility`; it replaces the current split mic-only and IM-only enums.
- `PermissionStatus` is the shared status enum with exactly `pending`, `granted`, and `denied`; `pending` absorbs the current `.notYetRequested` and `.notDetermined` cases, while onboarding-only `.skipped` remains outside the core layer.
- `RequestOutcome` is the shared fact bag with exactly `prompted`, `openedSettings`, `requiresRelaunch`, and `finalStatus`; `finalStatus` is the honest post-request status re-read from the OS and may remain `pending` when the OS still cannot distinguish grant vs denial.

### Protocols
- `PermissionService` is the single shared permission contract. It is `Sendable` and `@MainActor`, with main-actor isolation treated as mandatory rather than optional, and its required surface is `status(for: Permission) -> PermissionStatus`, `request(_ permission: Permission) async -> RequestOutcome`, `statusSnapshot() -> [Permission: PermissionStatus]`, `refresh()`, and `systemSettingsDeepLink(for: Permission) -> URL`.
- The observable surface is one `@Published` dictionary keyed by `Permission`. Consumers subscribe to that one snapshot and do not invent per-permission `AsyncStream` side channels.

### Errors
- None. Layer 1 reports facts through `PermissionStatus` and `RequestOutcome`; it does not add a new error enum.

## Proposed live implementation
`AppKitPermissionService` lives in `Sources/SeshatAppKit/Permissions/` and is an `@MainActor final class` that conforms to `PermissionService` and `ObservableObject`. It owns one published `[Permission: PermissionStatus]` dictionary, seeds that dictionary from `refresh()` during initialization, and registers exactly one `NSApplication.didBecomeActiveNotification` observer so returning from System Settings re-reads all three permissions automatically. `status(for:)` and `statusSnapshot()` use the same direct OS probes that `refresh()` uses, so the synchronous read path and the published snapshot cannot drift.

Microphone status/request semantics come from `AVCaptureDevice.authorizationStatus(for: .audio)` and `AVCaptureDevice.requestAccess(for: .audio)`, replacing the current mic-only requester at `Sources/SeshatAppKit/Permissions/AppKitMicrophonePermissionRequester.swift:4-56`. Input Monitoring status/request semantics remain grounded in `IOHIDCheckAccess(kIOHIDRequestTypeListenEvent)` and `IOHIDRequestAccess(kIOHIDRequestTypeListenEvent)`, preserving the current caveat in `Sources/SeshatCore/PermissionStatus.swift:16-25` that a reliable denied/granted verdict appears only after a monitor-install attempt. Accessibility status/request semantics use `AXIsProcessTrusted()` and `AXIsProcessTrustedWithOptions`, but untrusted AX maps to `PermissionStatus.pending`, never `.denied`, so paste fallback and optional-AX onboarding remain truthful. System Settings deep links for microphone, Input Monitoring, and Accessibility are owned here rather than spread across `MenuBarSceneModel`, `StatusItemController`, or onboarding. `Sources/SeshatAudio/AVAudioCaptureService.swift:39-45` stays unchanged as defense-in-depth.

Stage 1 tests should be built around injected closures or tiny wrapper collaborators for AVFoundation, IOKit, AX, `NSWorkspace`, and `NotificationCenter`, so the service can be verified without real TCC prompts. Those fakes live in new test directories and do not require any Stage 1 edits to existing consumers.

## Migration of existing call sites
Step numbering intentionally uses Stage `1.x`, `2.x`, and `3.x` to match `plans/CENTRAL_LAYERS_PROMPT.md:42-59` and the user brief.

### Step 1.1 - Stage 1: Add the shared permission domain under `Sources/SeshatCore/Permissions/`
| Change | Before | After |
|---|---|---|
| Shared domain contract | `Sources/SeshatCore/Protocols.swift:38-40` only defines `MicrophonePermissionRequesting`; `Sources/SeshatCore/PermissionStatus.swift:6-44` only defines IM status/probing. | New files in `Sources/SeshatCore/Permissions/*` define `Permission`, `PermissionStatus`, `RequestOutcome`, and `PermissionService`; legacy files remain untouched until Step 3.1. |
| Stage-1 tests | `Tests/SeshatCoreTests/PermissionStatusTests.swift:4-33` only covers the IM-only surface. | New files in `Tests/SeshatCoreTests/Permissions/*` pin the unified contract in isolation, without migrating any consumer yet. |

Acceptance tests: new `Tests/SeshatCoreTests/Permissions/*` contract tests, while `Tests/SeshatCoreTests/PermissionStatusTests.swift:4-33` remains untouched until Stage 3.1.

Deps: no in-layer prerequisite; parallel with Layer 2 Stage 1, Layer 3 Stage 1, and Layer 9 Stage 1 because those stages claim different directories per `plans/CENTRAL_LAYERS_PROMPT.md:50-59`; blocks Step 1.2, every Step 2.x in this layer, Layer 4 Stage 1/2, and Layer 5 Stage 1 if that layer wants to compile against `PermissionService`.

Validation checklist:
- [ ] New runtime files live only under new Stage 1 directories, matching `plans/CENTRAL_LAYERS_PROMPT.md:44-59`, while `Sources/SeshatCore/Protocols.swift:38-40` and `Sources/SeshatCore/PermissionStatus.swift:6-44` remain untouched during Stage 1.
- [ ] The new contract encodes `Permission`, `PermissionStatus`, and `RequestOutcome` exactly as locked above and as required by `plans/CENTRAL_LAYERS_PROMPT.md:160-177`.
- [ ] `.skipped` stays outside the core contract, matching `plans/CENTRAL_LAYERS_PROMPT.md:175-177` and the current UI-only usage in `Sources/SeshatAppKit/Onboarding/OnboardingViewModel.swift:4-24`.
- [ ] Legacy IM-only and mic-only surfaces are not deleted yet, matching the Stage 1 isolation rule in `plans/CENTRAL_LAYERS_PROMPT.md:44-46` and the current legacy files `Sources/SeshatCore/PermissionStatus.swift:6-44` and `Sources/SeshatAppKit/MenuBar/MicrophonePermissionState.swift:3-7`.

### Step 1.2 - Stage 1: Add `AppKitPermissionService` under `Sources/SeshatAppKit/Permissions/`
| Change | Before | After |
|---|---|---|
| Live service | `Sources/SeshatAppKit/Permissions/AppKitMicrophonePermissionRequester.swift:4-56`, `Sources/SeshatAppKit/Onboarding/PermissionRequester.swift:9-63`, and `Sources/SeshatAppKit/Paste/PasteInjector.swift:68-171` each talk to different OS permission APIs directly. | New files in `Sources/SeshatAppKit/Permissions/*` add `AppKitPermissionService`, OS-call adapters, activation-refresh wiring, and System Settings deep-link helpers; existing consumers are still untouched until Stage 2. |
| Stage-1 tests | `Tests/SeshatAppKitTests/AppKitMicrophonePermissionRequesterTests.swift:7-70` only pins the mic-only requester. | New files in `Tests/SeshatAppKitTests/Permissions/*` pin mic/IM/AX status mapping, `RequestOutcome` behavior, deep links, and `didBecomeActive` refresh behavior against service-specific fakes. |

Acceptance tests: new `Tests/SeshatAppKitTests/Permissions/*` behavior tests plus `Tests/SeshatAppKitTests/SeshatAppKitPermissionsCompileTests.swift:4-7` kept green until Stage 3.1 retires the old surface.

Deps: depends on Step 1.1; still parallel with Layer 2 Stage 1, Layer 3 Stage 1, and Layer 9 Stage 1; blocks all Stage 2 swaps in this layer, Layer 4 Stage 1/2, Layer 5 Stage 1/2, and Layer 9 Stage 2.

[QUESTION][Stage 1] `plans/CENTRAL_LAYERS_PROMPT.md:44-59` requires Stage 1 files to land in new directories, but trunk already contains `Sources/SeshatAppKit/Permissions/AppKitMicrophonePermissionRequester.swift:4-56` and `Sources/SeshatAppKit/Permissions/SeshatAppKitPermissionsModule.swift:1`. Should Step 1.2 place `AppKitPermissionService` directly in `Sources/SeshatAppKit/Permissions/` per `plans/CENTRAL_LAYERS_PROMPT.md:169`, or in a new nested subdirectory under `Sources/SeshatAppKit/Permissions/` to preserve directory isolation?

Validation checklist:
- [ ] New live-service files land without editing existing consumers, matching `plans/CENTRAL_LAYERS_PROMPT.md:44-59`, while `Sources/SeshatAppKit/Permissions/AppKitMicrophonePermissionRequester.swift:4-56`, `Sources/SeshatAppKit/Onboarding/PermissionRequester.swift:9-63`, and `Sources/SeshatAppKit/Paste/PasteInjector.swift:68-171` stay untouched in Stage 1.
- [ ] `refresh()` is triggered on `NSApplication.didBecomeActiveNotification`; one `@Published` dictionary exposes all three permissions; no per-permission `AsyncStream` is introduced, matching the locked decision and `plans/CENTRAL_LAYERS_PROMPT.md:162-168`.
- [ ] Accessibility maps to `.pending` when `AXIsProcessTrusted()` is false, never `.denied`, preserving the optional-AX intent in `Sources/SeshatAppKit/Onboarding/OnboardingViewModel.swift:18-24`, the clipboard fallback in `Sources/SeshatAppKit/Paste/PasteInjector.swift:168-171`, and the Layer 1 scope in `plans/CENTRAL_LAYERS_PROMPT.md:168-170`.
- [ ] `Sources/SeshatAudio/AVAudioCaptureService.swift:39-45` is untouched, matching `plans/CENTRAL_LAYERS_PROMPT.md:67-68,175-177`.

### Step 2.1 - Stage 2: Migrate `PasteInjector`
| Change | Before | After |
|---|---|---|
| AX permission plumbing in paste | `Sources/SeshatAppKit/Paste/PasteInjector.swift:68-171` owns raw AX trust closures, a raw AX prompt closure, and local fallback logic. | `PasteInjector` consumes `PermissionService`, reads `Permission.accessibility` through the unified snapshot/status API, requests AX through the service when needed, and keeps the same clipboard-only fallback behavior. |

Acceptance tests: update `Tests/SeshatAppKitTests/PasteInjectorTests.swift:20-203` to use a fake permission service and keep the "leave transcript on clipboard when AX is missing" assertions intact.

Deps: depends on Step 1.2; can run in parallel with Steps 2.2, 2.3, and 2.4 because they touch different consumers; blocks Step 2.6 because `SeshatAppMain` composes the live `PasteInjector`.

Validation checklist:
- [ ] `PasteInjector` stops calling `AXIsProcessTrusted()` / `AXIsProcessTrustedWithOptions` directly from `Sources/SeshatAppKit/Paste/PasteInjector.swift:87-93,168-171` and instead routes through `Permission.accessibility`, matching `plans/CENTRAL_LAYERS_PROMPT.md:161-168`.
- [ ] Clipboard fallback behavior from `Sources/SeshatAppKit/Paste/PasteInjector.swift:163-171` and `Tests/SeshatAppKitTests/PasteInjectorTests.swift:20-45` remains unchanged, consistent with `plans/CENTRAL_LAYERS_PROMPT.md:168-177` and `AX is optional everywhere (locked decision #6 in prompt).`
- [ ] This step migrates only the named consumer `PasteInjector`, matching the one-consumer-per-step swap rule in `plans/CENTRAL_LAYERS_PROMPT.md:45`.

### Step 2.2 - Stage 2: Migrate `GlobalHotkeyMonitor`
| Change | Before | After |
|---|---|---|
| Input Monitoring status reads | `Sources/SeshatAppKit/Hotkeys/GlobalHotkeyMonitor.swift:34-129` depends on `PermissionProbing` and `InputMonitoringPermissionState` directly. | `GlobalHotkeyMonitor` consumes `PermissionService` for `Permission.inputMonitoring`, keeps logging on failed monitor installation, and preserves the current "re-check only after install attempt" semantics. |

Acceptance tests: update `Tests/SeshatAppKitTests/GlobalHotkeyMonitorTests.swift:286-322` to assert the same denied/pending/granted log output through a fake permission service.

Deps: depends on Step 1.2; can run in parallel with Steps 2.1, 2.3, and 2.4; blocks Step 2.6 because app composition still constructs the hotkey monitor.

Validation checklist:
- [ ] `GlobalHotkeyMonitor` no longer depends on `PermissionProbing` from `Sources/SeshatCore/PermissionStatus.swift:12-44` and instead consumes unified `Permission.inputMonitoring`.
- [ ] The "pending until after monitor install attempt" caveat from `Sources/SeshatCore/PermissionStatus.swift:16-25` and the log assertions in `Tests/SeshatAppKitTests/GlobalHotkeyMonitorTests.swift:286-322` are preserved exactly.
- [ ] This step does not silently add prompt-on-start behavior; it only swaps the status source for the named consumer, consistent with `plans/CENTRAL_LAYERS_PROMPT.md:164-166`.

### Step 2.3 - Stage 2: Migrate `MenuBarSceneModel`
| Change | Before | After |
|---|---|---|
| Menu-bar mic state and request flow | `Sources/SeshatAppKit/MenuBar/MenuBarSceneModel.swift:8-118` stores `MicrophonePermissionState`, depends on `MicrophonePermissionRequesting`, and owns a mic-only open-settings closure. | `MenuBarSceneModel` consumes `PermissionService`, uses unified microphone status/request outcomes, and routes microphone privacy navigation through the service deep link instead of a local mic-only collaborator. |

Acceptance tests: update `Tests/SeshatAppKitTests/MenuBarSceneModelTests.swift:11-120,291-445` to use a fake permission service while preserving clipboard-only notices and open-settings behavior.

Deps: depends on Step 1.2; can run in parallel with Steps 2.1, 2.2, and 2.4; blocks Step 2.5 because `StatusItemController` rebuilds menu warnings from scene-model state.

Validation checklist:
- [ ] `MenuBarSceneModel` stops storing the old mic enum from `Sources/SeshatAppKit/MenuBar/MenuBarSceneModel.swift:8-18` and instead uses unified `PermissionStatus` or a projection from the service snapshot, matching `plans/CENTRAL_LAYERS_PROMPT.md:161-168`.
- [ ] `handleRecordButtonTap()` preserves the no-onboarding-reroute behavior locked in by `Sources/SeshatAppKit/MenuBar/MenuBarSceneModel.swift:102-117` and `Tests/SeshatAppKitTests/MenuBarSceneModelTests.swift:88-120`.
- [ ] Microphone Settings routing moves behind `systemSettingsDeepLink(for: .microphone)` while preserving the current behavior asserted by `Tests/SeshatAppKitTests/MenuBarSceneModelTests.swift:427-444`.

### Step 2.4 - Stage 2: Migrate the onboarding flow
| Change | Before | After |
|---|---|---|
| Onboarding permission state and gating | `Sources/SeshatAppKit/Onboarding/OnboardingViewModel.swift:4-68`, `Sources/SeshatAppKit/Onboarding/OnboardingView.swift:54-356`, `Sources/SeshatAppKit/Onboarding/PermissionRequester.swift:9-63`, and `Sources/SeshatAppKit/Onboarding/OnboardingWindowController.swift:67-156` use `OnboardingPermissionOutcome`, `OnboardingPermissionProbing`, split mic/IM/AX calls, and `SeshatOnboardingCompleted`. | The onboarding flow reads and requests through `PermissionService`, keeps `.skipped` as view-model-only UI state, and treats microphone plus Input Monitoring as the only critical gate while AX remains optional. |

Acceptance tests: update `Tests/SeshatAppKitTests/OnboardingViewModelTests.swift:7-99`; extend `Tests/SeshatAppKitTests/ManualOnboardingVerification.md:18-24` with a service-refresh check after returning from System Settings.

Deps: depends on Step 1.2; can run in parallel with Steps 2.1, 2.2, and 2.3; blocks Steps 2.5, 2.6, and 3.1 because both app composition and deletion still depend on the onboarding decision.

[QUESTION][Stage 2] The brief requires Stage 3 deletion of `SeshatOnboardingCompleted` / `OnboardingState.swift`, but trunk still reads that state in `Sources/SeshatAppKit/Onboarding/OnboardingWindowController.swift:95-147`, `Sources/SeshatAppKit/Composition/SeshatAppMain.swift:68-70`, and `Sources/SeshatAppKit/MenuBar/StatusItemController.swift:48-60`. Does "the onboarding flow" in Stage 2 mean this step removes first-run persistence inside Layer 1, or is Step 3.1 intended to wait for the successor permissions surface referenced by `plans/CENTRAL_LAYERS_PROMPT.md:172` ("OnboardingViewModel (or its successor in the Permissions sub-tab)")?

Validation checklist:
- [ ] `OnboardingViewModel` keeps `.skipped` local to onboarding UI state and does not leak it into core `PermissionStatus`, preserving `Sources/SeshatAppKit/Onboarding/OnboardingViewModel.swift:4-24` and `plans/CENTRAL_LAYERS_PROMPT.md:175-177`.
- [ ] `OnboardingView.swift` swaps off `OnboardingPermissionOutcome` without changing the optional-AX copy and controls grounded in `Sources/SeshatAppKit/Onboarding/OnboardingView.swift:90-108,253-356` and `Tests/SeshatAppKitTests/ManualOnboardingVerification.md:18-24`.
- [ ] `OnboardingWindowControllerHost.areCriticalPermissionsGranted` no longer treats AX as required, fixing the mismatch between `Sources/SeshatAppKit/Onboarding/OnboardingViewModel.swift:18-24` and `Sources/SeshatAppKit/Onboarding/OnboardingWindowController.swift:98-103` per `plans/CENTRAL_LAYERS_PROMPT.md:67-68,170-177`.
- [ ] `Tests/SeshatAppKitTests/OnboardingViewModelTests.swift:29-99` and `Tests/SeshatAppKitTests/ManualOnboardingVerification.md:18-24` still prove microphone plus Input Monitoring are mandatory while AX remains optional everywhere.

### Step 2.5 - Stage 2: Migrate `StatusItemController`
| Change | Before | After |
|---|---|---|
| Menu warning and deep-link source | `Sources/SeshatAppKit/MenuBar/StatusItemController.swift:31-267` probes IM directly, owns hardcoded mic/IM URLs, and rebuilds the menu from split enums. | `StatusItemController` consumes the shared `PermissionService` snapshot/publisher, gets System Settings URLs from `systemSettingsDeepLink(for:)`, and keeps `StatusItemMenuModel` warning ordering correct under unified statuses. |

Acceptance tests: update `Tests/SeshatAppKitTests/MenuBar/StatusItemMenuModelTests.swift:101-172`; extend `Tests/SeshatAppKitTests/ManualStatusItemVerification.md:13-26` with a "return from System Settings and reopen menu" refresh check.

Deps: depends on Steps 1.2 and 2.3; if the Step 2.4 onboarding-state question resolves inside Layer 1, complete Step 2.4 before removing the remaining onboarding-completion provider; blocks Step 2.6 and Step 3.1.

Validation checklist:
- [ ] `StatusItemController` no longer depends on `PermissionProbing` or hardcoded Settings URLs from `Sources/SeshatAppKit/MenuBar/StatusItemController.swift:32-37,196-267`; it instead uses `PermissionService.statusSnapshot()` / the published dictionary and `systemSettingsDeepLink(for:)`, matching `plans/CENTRAL_LAYERS_PROMPT.md:163-168`.
- [ ] Warning rows still preserve the ordering and "no warning while pending" rules captured in `Sources/SeshatAppKit/MenuBar/StatusItemMenuModel.swift:74-100,157-172` and `Tests/SeshatAppKitTests/MenuBar/StatusItemMenuModelTests.swift:101-172`.
- [ ] Any remaining read of `SeshatOnboardingCompleted` is either removed here or explicitly blocked on the Step 2.4 question; this step must not quietly preserve a dependency slated for Step 3.1 deletion.

### Step 2.6 - Stage 2: Migrate `SeshatAppMain`
| Change | Before | After |
|---|---|---|
| App composition | `Sources/SeshatAppKit/Composition/SeshatAppMain.swift:21-167` constructs split microphone requester, IM probe, AX closure, onboarding completion provider, and paste dependencies. | `SeshatAppMain` composes one shared `PermissionService` and injects it into onboarding, menu bar, paste, hotkey, and any helper shell that must mirror the production entry point to keep compile coverage green. |

Acceptance tests: update `Tests/SeshatAppKitTests/AppEntryPointTests.swift:8-31`, `Tests/SeshatAppKitTests/MenuBarFlowIntegrationTests.swift:87-149`, and `Tests/SeshatAppKitTests/MenuBarSceneModelTests.swift:504-515`.

Deps: depends on Steps 1.2, 2.1, 2.2, 2.3, 2.4, and 2.5; blocks Step 3.1, Layer 4 Stage 2, and any later composition step that wants one app-wide permission source.

Validation checklist:
- [ ] `SeshatAppMain` stops constructing split mic/IM/AX collaborators from `Sources/SeshatAppKit/Composition/SeshatAppMain.swift:21-167` and instead injects one shared `PermissionService`, matching `plans/CENTRAL_LAYERS_PROMPT.md:162-172`.
- [ ] Startup remains non-blocking, preserving `Tests/SeshatAppKitTests/MenuBarFlowIntegrationTests.swift:87-140` after the new shared service is introduced.
- [ ] `Sources/SeshatAudio/AVAudioCaptureService.swift:39-45` remains untouched and the new service is not injected into `SeshatAudio`, matching `plans/CENTRAL_LAYERS_PROMPT.md:67-68,175-177`.

### Step 3.1 - Stage 3: Global delete of legacy permission surfaces
| Change | Before | After |
|---|---|---|
| Delete split permission legacy code | The old mic-only, IM-only, onboarding-only, and onboarding-completion permission surfaces still exist only as compatibility scaffolding after Steps 2.1-2.6. | Delete exactly `MicrophonePermissionState`, `InputMonitoringPermissionState`, `OnboardingPermissionOutcome`, `PermissionProbing`, `OnboardingPermissionProbing`, `AppKitMicrophonePermissionRequester`, `SeshatOnboardingCompleted`, `OnboardingState.swift`, and `PermissionStatus.swift` as the Layer 1 slice of the global deletion pass. |

Acceptance tests: re-run the Layer 1 suite named in the Test strategy after the deletions; no legacy-only test may remain as the only proof of behavior.

Deps: depends on every Step 2.x in this plan; also depends on the Step 2.4 onboarding-flow question being resolved before deleting `SeshatOnboardingCompleted` / `OnboardingState.swift`; blocks no later Layer 1 work because this is the final deletion pass.

Validation checklist:
- [ ] Delete exactly `MicrophonePermissionState`, `InputMonitoringPermissionState`, `OnboardingPermissionOutcome`, `PermissionProbing`, `OnboardingPermissionProbing`, `AppKitMicrophonePermissionRequester`, `SeshatOnboardingCompleted`, `OnboardingState.swift`, and `PermissionStatus.swift`, matching the locked decision and `plans/CENTRAL_LAYERS_PROMPT.md:171`.
- [ ] Every Stage 2 consumer named at `plans/CENTRAL_LAYERS_PROMPT.md:172` and in Steps 2.1-2.6 has already stopped referencing those symbols; the current references are in `Sources/SeshatAppKit/Paste/PasteInjector.swift:68-171`, `Sources/SeshatAppKit/Hotkeys/GlobalHotkeyMonitor.swift:34-129`, `Sources/SeshatAppKit/MenuBar/MenuBarSceneModel.swift:8-118`, `Sources/SeshatAppKit/Onboarding/OnboardingViewModel.swift:4-68`, `Sources/SeshatAppKit/MenuBar/StatusItemController.swift:31-267`, and `Sources/SeshatAppKit/Composition/SeshatAppMain.swift:9-245`.
- [ ] `Sources/SeshatAudio/AVAudioCaptureService.swift:39-45` still survives unchanged after the deletion pass, matching `plans/CENTRAL_LAYERS_PROMPT.md:67-68,175-177`.

## Test strategy
- Unit tests: add `Tests/SeshatCoreTests/Permissions/*` for the shared domain contract and `Tests/SeshatAppKitTests/Permissions/*` for mic/IM/AX mapping, `RequestOutcome` semantics, deep links, and `didBecomeActive` refresh behavior.
- Integration tests: migrate `Tests/SeshatAppKitTests/PasteInjectorTests.swift:20-203`, `Tests/SeshatAppKitTests/GlobalHotkeyMonitorTests.swift:286-322`, `Tests/SeshatAppKitTests/MenuBarSceneModelTests.swift:11-120,291-445`, `Tests/SeshatAppKitTests/MenuBar/StatusItemMenuModelTests.swift:101-172`, `Tests/SeshatAppKitTests/AppEntryPointTests.swift:8-31`, and `Tests/SeshatAppKitTests/MenuBarFlowIntegrationTests.swift:87-149` to fake the new service instead of the split collaborators.
- Fakes for the new protocols: one `@MainActor` fake permission service with configurable snapshots and request outcomes for consumer tests, plus low-level AVFoundation/IOKit/AX/NotificationCenter/NSWorkspace spies for `AppKitPermissionService` tests.
- Regression guards the layer must preserve: `Tests/SeshatAppKitTests/OnboardingViewModelTests.swift:29-99` for optional AX, `Tests/SeshatAppKitTests/PasteInjectorTests.swift:20-45` for clipboard fallback, `Tests/SeshatAppKitTests/GlobalHotkeyMonitorTests.swift:286-322` for IM failure logs, `Tests/SeshatAppKitTests/MenuBar/StatusItemMenuModelTests.swift:101-172` for warning ordering, and `Tests/SeshatAppKitTests/MenuBarFlowIntegrationTests.swift:87-149` for non-blocking startup composition.
- Manual verification: extend `Tests/SeshatAppKitTests/ManualOnboardingVerification.md:18-24` to verify refresh after returning from System Settings, and extend `Tests/SeshatAppKitTests/ManualStatusItemVerification.md:13-26` to verify menu warnings refresh after `NSApplication.didBecomeActiveNotification`.

## Open design questions (surface - do not resolve)
- [QUESTION][Stage 1] `plans/CENTRAL_LAYERS_PROMPT.md:44-59` requires Stage 1 files to land in new directories, but trunk already contains `Sources/SeshatAppKit/Permissions/AppKitMicrophonePermissionRequester.swift:4-56` and `Sources/SeshatAppKit/Permissions/SeshatAppKitPermissionsModule.swift:1`. Should Step 1.2 place `AppKitPermissionService` directly in `Sources/SeshatAppKit/Permissions/` per `plans/CENTRAL_LAYERS_PROMPT.md:169`, or in a new nested subdirectory under `Sources/SeshatAppKit/Permissions/` to preserve directory isolation?
- [QUESTION][Stage 2] The brief requires Stage 3 deletion of `SeshatOnboardingCompleted` / `OnboardingState.swift`, but trunk still reads that state in `Sources/SeshatAppKit/Onboarding/OnboardingWindowController.swift:95-147`, `Sources/SeshatAppKit/Composition/SeshatAppMain.swift:68-70`, and `Sources/SeshatAppKit/MenuBar/StatusItemController.swift:48-60`. Does "the onboarding flow" in Stage 2 mean this layer removes first-run persistence before Step 3.1, or does Step 3.1 wait for the successor permissions surface referenced by `plans/CENTRAL_LAYERS_PROMPT.md:172`?

## Validation checklist (implementer ticks box-by-box)
- [ ] Stage 1 adds only new files in new layer-owned directories, matching `plans/CENTRAL_LAYERS_PROMPT.md:42-59`, while the current consumers in `Sources/SeshatAppKit/Paste/PasteInjector.swift:55-184`, `Sources/SeshatAppKit/Hotkeys/GlobalHotkeyMonitor.swift:48-129`, `Sources/SeshatAppKit/MenuBar/MenuBarSceneModel.swift:29-118`, `Sources/SeshatAppKit/Onboarding/OnboardingWindowController.swift:79-149`, `Sources/SeshatAppKit/MenuBar/StatusItemController.swift:43-229`, and `Sources/SeshatAppKit/Composition/SeshatAppMain.swift:21-168` remain untouched until Stage 2.
- [ ] Stage 2 migrates exactly `PasteInjector`, `GlobalHotkeyMonitor`, `MenuBarSceneModel`, the onboarding flow, `StatusItemController`, and `SeshatAppMain`, matching the locked decision and `plans/CENTRAL_LAYERS_PROMPT.md:171-173`.
- [ ] Stage 3 deletes exactly the locked legacy list and nothing from `SeshatAudio`, matching `plans/CENTRAL_LAYERS_PROMPT.md:67-68,171-177` and `Sources/SeshatAudio/AVAudioCaptureService.swift:39-45`.
- [ ] AX remains optional everywhere, consistent with `plans/CENTRAL_LAYERS_PROMPT.md:67-68,170-177`, `Sources/SeshatAppKit/Onboarding/OnboardingViewModel.swift:18-24`, and `Sources/SeshatAppKit/Paste/PasteInjector.swift:168-171`.
- [ ] No files outside "Observed current spread" modified (unless in explicit collision list: the new Stage 1 source/test directories named in Steps 1.1-1.2).
- [ ] No `Color(hex:` outside `Theme/*` (house rule)
- [ ] No direct `UserDefaults.standard.*` - typed resolvers only
- [ ] No `type` / `kind` / `intent` column added to SQLite
- [ ] `swift build --build-tests` green (main session)
- [ ] All acceptance tests named in plan pass

## Backlog tickets authored
- None.

## Inter-layer dependencies
- **Requires**: no earlier layer for Stage 1; Step 3.1 also requires the Step 2.4 onboarding-flow question to be resolved before deleting `SeshatOnboardingCompleted` / `OnboardingState.swift`.
- **Blocks**: layer 4 because the state store needs a unified `[Permission: PermissionStatus]` snapshot and observable service; layer 5 because output delegates AX checks to this service; layer 9 because the app-wide TCC routing should use `systemSettingsDeepLink(for:)`.

## Commit style
`trunk: layer 1.N: <verb-led subject>`. Test + fix in same commit.

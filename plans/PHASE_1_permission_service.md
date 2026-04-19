# Phase 1 — Permission Service

## Critical discipline
> Do NOT diverge from this plan or the Manus mockups. Silent divergence is the cardinal sin. To deviate, surface the proposed divergence in a comment in the commit message AND in the hand-off report; wait for main-session confirmation. Paraphrasing the contract is divergence. Renaming variables the plan specifies is divergence. Choosing a different animation curve than the mockup implies is divergence.

## Prerequisites
- Execute Phase 0 first. This file assumes the post-rename symbols from [plans/PHASE_0_rename.md](/Users/nitinkum/Projects/nitkrar/seshat/plans/PHASE_0_rename.md), even though the grounding citations below still point at the pre-rename trunk paths in `1ea02e4`.
- Read the current split permission surface before editing:
  - `Sources/SeshatCore/Protocols.swift:38-40` — trunk still exposes the microphone-only `MicrophonePermissionRequesting` protocol instead of a unified service.
  - `Sources/SeshatCore/PermissionStatus.swift:6-44` — Input Monitoring state/probe lives in `SeshatCore` today as a separate enum + probe protocol.
  - `Sources/SeshatAppKit/Permissions/AppKitMicrophonePermissionRequester.swift:4-57` — microphone request semantics are AppKit-local and separate from IM / AX.
  - `Sources/SeshatAppKit/Onboarding/PermissionRequester.swift:9-63` — onboarding owns its own three-permission request actor.
  - `Sources/SeshatAppKit/Onboarding/OnboardingViewModel.swift:18-24` — onboarding state already treats Accessibility as optional.
  - `Sources/SeshatAppKit/Onboarding/OnboardingWindowController.swift:98-103` — the window host still treats Accessibility as part of `areCriticalPermissionsGranted`, which is the inconsistency locked decision `#8` forbids.
  - `Sources/SeshatAppKit/Paste/PasteInjector.swift:168-171` — paste already falls back to clipboard when Accessibility is not trusted; the new service must preserve that behavior.
  - `Sources/SeshatAudio/AVAudioCaptureService.swift:39-45` — the direct microphone authorization guard in audio is already present and must stay as defense-in-depth.
  - `Sources/SeshatAppKit/MenuBar/MenuBarSceneModel.swift:99-117` and `Sources/SeshatAppKit/MenuBar/StatusItemController.swift:193-229` — the menu bar still reads legacy permission types directly.
  - `Sources/SeshatAppKit/Composition/SeshatAppMain.swift:61-167` — app composition still wires onboarding, pill, and menu bar around split permission collaborators.
- Carry forward the prior review constraints instead of re-litigating them:
  - `plans/PLAN_PHASES-review-1.md:45-55` — Input Monitoring detection must use `IOHIDCheckAccess(kIOHIDRequestTypeListenEvent)` only.
  - `plans/PLAN_PHASES-review-1.md:47-54` — pre-attempt IM state must remain “not determined” / pending until the app has attempted to register the monitor once.
  - `plans/CENTRAL_LAYERS_PROMPT.md:160-170` — the service is `@MainActor`, observable, exposes `status(for:)`, `statusSnapshot()`, `request(_:)`, `refresh()`, and deep links, with AX mapped to pending when untrusted.
- Do not execute Steps 1.7, 1.8, or 1.9 on the Phase 1 branch. They remain in this file only because the user asked to preserve the 9-step skeleton. Their work transfers into Phase 2 once the Manus-backed Settings UI exists.

## Locked design decisions applicable to this phase
- Locked decision `#8`: Accessibility is optional everywhere. Drop it from every “critical permissions” gate. AX must map to `.pending` when untrusted, never `.denied`, and paste must continue to fall back to clipboard when AX is absent.
- Locked decision `#9`: do not inject the permission service into `SeshatAudio`; `Sources/SeshatAudio/AVAudioCaptureService.swift:39-45` stays unchanged as defense-in-depth.
- Phase-1-specific lock: keep `RequestOutcome { prompted, openedSettings, requiresRelaunch }` as the request result contract. Do not collapse `request(_:)` into “return a status”.
- Phase-1-specific lock: the service itself is `@MainActor`, not merely `Sendable`, and it publishes one refreshed snapshot dictionary instead of per-permission `AsyncStream`s.
- Sequencing lock: skeleton Steps 1.7, 1.8, and 1.9 are Phase 2-owned handoff steps because they require the Manus Settings surface from `plans/App UI design/Claude_Final_Bundle_Prompt.md:68-76` and `plans/App UI design/final_settings_permissions_v2.png`.

## Step 1.1 — Define the shared permission domain contract
> Do NOT diverge from this plan or the Manus mockups. Silent divergence is the cardinal sin. To deviate, surface the proposed divergence in a comment in the commit message AND in the hand-off report; wait for main-session confirmation. Paraphrasing the contract is divergence. Renaming variables the plan specifies is divergence. Choosing a different animation curve than the mockup implies is divergence.

### Files touched (exhaustive) — path:line-range — what changes
- `Sources/SeshatCore/Protocols.swift:38-40` — delete the microphone-only contract once the new protocol exists, or replace it with a compatibility comment that points callers at `PermissionService`; do not leave two competing primary permission protocols.
- `Sources/SeshatCore/PermissionDomain.swift:new file` — add the unified permission-domain types:
  - `Permission` with exactly `.microphone`, `.inputMonitoring`, and `.accessibility`.
  - `PermissionStatus` with exactly `.pending`, `.granted`, and `.denied`.
  - `RequestOutcome` with exactly `prompted`, `openedSettings`, and `requiresRelaunch`.
- `Sources/SeshatCore/PermissionService.swift:new file` — add the `@MainActor` protocol surface: `status(for:)`, `statusSnapshot()`, `request(_:) async`, `refresh()`, and `systemSettingsDeepLink(for:)`.
- `Tests/SeshatCoreTests/PermissionStatusTests.swift:1-34` — replace the current IM-only enum/probe assertions with shared-domain tests that pin the new enum cases and `RequestOutcome` shape.
- `Tests/SeshatCoreTests/PermissionServiceContractTests.swift:new file` — add compile-level contract tests for the `@MainActor` protocol surface and its three-case status enum.

### Scope — IN
- Introduce the shared vocabulary only. This step is where the app stops inventing one-off permission enums per feature.
- Keep `RequestOutcome` as a three-flag fact bag. The contract is “what the request did”, not “what the final OS state is”.
- Keep UI-only state like onboarding “skipped” out of the core enum surface. `plans/CENTRAL_LAYERS_PROMPT.md:175-177` is still the right rule here even though this plan intentionally keeps the onboarding UI alive until Phase 2.

### Scope — OUT (with backlog ticket paths where applicable)
- No AppKit/OS implementation work yet. No `AVCaptureDevice`, `AXIsProcessTrusted`, or `IOHID*` calls in this step.
- No consumer migration yet. `MenuBarSceneModel`, `GlobalHotkeyMonitor`, `PasteInjector`, and onboarding remain on the old surface until Steps 1.5 and 1.6.
- Do not touch Settings UI. Those moves are Phase 2 work under [plans/PHASE_2_unified_ui.md](/Users/nitinkum/Projects/nitkrar/seshat/plans/PHASE_2_unified_ui.md).

### Acceptance tests — Tests/... — test name + what it asserts + mockup/doc clause it ties to
- `Tests/SeshatCoreTests/PermissionStatusTests.swift` — `testPermissionStatusHasOnlyPendingGrantedDenied`; asserts the shared enum surface has no onboarding-only `.skipped` case; ties to `plans/CENTRAL_LAYERS_PROMPT.md:161-171` and locked decision `#8`.
- `Tests/SeshatCoreTests/PermissionStatusTests.swift` — `testRequestOutcomeCarriesPromptedOpenedSettingsRequiresRelaunch`; asserts the request contract is the three-flag struct rather than a returned status; ties to the user-locked Phase 1 outcome contract.
- `Tests/SeshatCoreTests/PermissionServiceContractTests.swift` — `testPermissionServiceIsMainActorProtocol`; asserts the service contract is main-actor isolated and exposes the five required entry points; ties to `plans/CENTRAL_LAYERS_PROMPT.md:162-168`.

### Validation checklist (implementer ticks box-by-box in hand-off)
- [ ] `Permission` has exactly `microphone`, `inputMonitoring`, and `accessibility`.
- [ ] `PermissionStatus` has exactly `pending`, `granted`, and `denied`; there is no core `.skipped`.
- [ ] `RequestOutcome` contains exactly `prompted`, `openedSettings`, and `requiresRelaunch`; no bundled final-status field was smuggled in.
- [ ] Locked decision `#8` is reflected in the contract: AX can be represented as `.pending` without inventing a fake `.denied`.
- [ ] Diff against this step shows no silent divergence; every modified file is listed above, and any proposed deviation is recorded in the commit message comment and hand-off report.
- [ ] No `Color(hex:` outside `Theme/*` (hard rule — long-standing).
- [ ] No `UserDefaults.standard.*` direct reads — typed resolvers only.
- [ ] No `type`/`kind`/`intent` field added (hard rule — Phase 3 design lock: `project_phase3_notes_equals_history.md`).
- [ ] `swift build --build-tests` green from the main-repo path.
- [ ] No files outside `Files touched` modified.

### Commit style — `trunk: phase 1.1: <verb-led subject>`. Test + fix in same commit.
`trunk: phase 1.1: define unified permission domain contract`

### Hand-off report template
```md
Phase 1.1 hand-off
- Commit: <sha> trunk: phase 1.1: define unified permission domain contract
- Types introduced: <list>
- Contract assertions added: <list>
- Verification commands: <list>
- Deviations from plan: none | <required explicit note>
- Follow-ups / blockers: none | <list>
```

## Step 1.2 — Implement live AppKitPermissionService status probing and deep links
> Do NOT diverge from this plan or the Manus mockups. Silent divergence is the cardinal sin. To deviate, surface the proposed divergence in a comment in the commit message AND in the hand-off report; wait for main-session confirmation. Paraphrasing the contract is divergence. Renaming variables the plan specifies is divergence. Choosing a different animation curve than the mockup implies is divergence.

### Files touched (exhaustive) — path:line-range — what changes
- `Sources/SeshatCore/PermissionStatus.swift:1-44` — keep the existing IOHID probe implementation as the low-level IM state reader for now, but reduce it to an implementation detail used by the new service rather than a second public domain model.
- `Sources/SeshatAppKit/Permissions/AppKitPermissionService.swift:new file` — implement the live `@MainActor` service:
  - microphone status from `AVCaptureDevice.authorizationStatus(for: .audio)`.
  - Input Monitoring status from `IOHIDCheckAccess(kIOHIDRequestTypeListenEvent)` via the existing probe.
  - Accessibility status from `AXIsProcessTrusted()` mapped to `.granted` or `.pending` only.
  - `systemSettingsDeepLink(for:)` URLs for microphone, Input Monitoring, and Accessibility.
- `Sources/SeshatAppKit/Composition/AppComposition.swift:8-93` — add a factory or singleton entry point for the live service so later steps do not instantiate ad hoc copies.
- `Tests/SeshatCoreTests/PermissionStatusTests.swift:1-34` — keep one smoke test proving the IOHID probe still returns only recognized states.
- `Tests/SeshatAppKitTests/Permissions/AppKitPermissionServiceTests.swift:new file` — add unit tests for status mapping and deep-link resolution.

### Scope — IN
- Build the status-reading surface and deep-link mapping only.
- Keep `status(for:)` and `statusSnapshot()` synchronous and non-triggering. They must not prompt the OS.
- Preserve `plans/PLAN_PHASES-review-1.md:47-55`: IM status remains pending until the app has attempted monitor registration once; do not misreport “granted” off Accessibility APIs.

### Scope — OUT (with backlog ticket paths where applicable)
- No `request(_:)` semantics yet. Prompting/open-settings behavior belongs to Step 1.3.
- No published snapshot / activation observer yet. That belongs to Step 1.4.
- No call-site migrations yet. `MenuBarSceneModel`, `GlobalHotkeyMonitor`, `PasteInjector`, and onboarding stay on their old collaborators until Steps 1.5 and 1.6.

### Acceptance tests — Tests/... — test name + what it asserts + mockup/doc clause it ties to
- `Tests/SeshatAppKitTests/Permissions/AppKitPermissionServiceTests.swift` — `testAccessibilityUntrustedMapsToPendingNotDenied`; asserts AX status never lies as denied; ties to `plans/CENTRAL_LAYERS_PROMPT.md:169-171` and locked decision `#8`.
- `Tests/SeshatAppKitTests/Permissions/AppKitPermissionServiceTests.swift` — `testInputMonitoringStatusUsesIOHIDProbeOnly`; asserts IM status is sourced from the IOHID path, not AX APIs; ties to `plans/PLAN_PHASES-review-1.md:45-55`.
- `Tests/SeshatAppKitTests/Permissions/AppKitPermissionServiceTests.swift` — `testSystemSettingsDeepLinksMatchPermissionKind`; asserts microphone/Input Monitoring/Accessibility each open the correct anchor; ties to the existing hard-coded URLs in `Sources/SeshatAppKit/Composition/SeshatAppMain.swift:203-210` and `Sources/SeshatAppKit/MenuBar/StatusItemController.swift:253-267`.

### Validation checklist (implementer ticks box-by-box in hand-off)
- [ ] `status(for:)` performs no prompting and no URL opening.
- [ ] Accessibility resolves to `.pending` when `AXIsProcessTrusted()` is false; it never resolves to `.denied`.
- [ ] Input Monitoring probing routes through `IOHIDCheckAccess(kIOHIDRequestTypeListenEvent)` only, matching `plans/PLAN_PHASES-review-1.md:45-55`.
- [ ] Locked decision `#9` is honored: `Sources/SeshatAudio/AVAudioCaptureService.swift:39-45` is untouched.
- [ ] Diff against this step shows no silent divergence; every modified file is listed above, and any proposed deviation is recorded in the commit message comment and hand-off report.
- [ ] No `Color(hex:` outside `Theme/*` (hard rule — long-standing).
- [ ] No `UserDefaults.standard.*` direct reads — typed resolvers only.
- [ ] No `type`/`kind`/`intent` field added (hard rule — Phase 3 design lock: `project_phase3_notes_equals_history.md`).
- [ ] `swift build --build-tests` green from the main-repo path.
- [ ] No files outside `Files touched` modified.

### Commit style — `trunk: phase 1.2: <verb-led subject>`. Test + fix in same commit.
`trunk: phase 1.2: implement live appkit permission status service`

### Hand-off report template
```md
Phase 1.2 hand-off
- Commit: <sha> trunk: phase 1.2: implement live appkit permission status service
- Status sources shipped: microphone=<api>, inputMonitoring=<api>, accessibility=<api>
- Deep links shipped: <list>
- Verification commands: <list>
- Deviations from plan: none | <required explicit note>
- Follow-ups / blockers: none | <list>
```

## Step 1.3 — Implement honest request semantics with relaunch-aware outcomes
> Do NOT diverge from this plan or the Manus mockups. Silent divergence is the cardinal sin. To deviate, surface the proposed divergence in a comment in the commit message AND in the hand-off report; wait for main-session confirmation. Paraphrasing the contract is divergence. Renaming variables the plan specifies is divergence. Choosing a different animation curve than the mockup implies is divergence.

### Files touched (exhaustive) — path:line-range — what changes
- `Sources/SeshatAppKit/Permissions/AppKitPermissionService.swift:new file` — extend the live service with `request(_:) async` for all three permissions:
  - microphone: prompt only when the OS status is `.notDetermined`; otherwise open Settings if already denied/restricted.
  - Input Monitoring: request via `IOHIDRequestAccess(kIOHIDRequestTypeListenEvent)` and surface `requiresRelaunch = true` whenever the user must relaunch for the monitor to become reliable.
  - Accessibility: request via `AXIsProcessTrustedWithOptions` and keep the returned service status pending until trust flips true.
- `Tests/SeshatAppKitTests/Permissions/AppKitPermissionServiceTests.swift:new file` — add request-path tests using injected OS-call closures rather than real TCC prompts.
- `Tests/SeshatAppKitTests/AppKitMicrophonePermissionRequesterTests.swift:1-71` — either delete these tests when the legacy requester becomes a pure wrapper in a later step, or convert them into compatibility tests that pin the microphone request semantics against the new service.

### Scope — IN
- Make `request(_:)` honest per permission kind. The outcome must tell the caller whether the OS was prompted, whether the app opened Settings directly, and whether a relaunch is required.
- Re-read state through `refresh()` / `status(for:)` after a request; do not add a hidden “final status” side channel.
- Keep Accessibility semantics aligned with paste fallback: not trusted means “prompt or open settings and leave the app usable”, not “hard stop”.

### Scope — OUT (with backlog ticket paths where applicable)
- No activation observer yet. The service still needs Step 1.4 before the snapshot is self-refreshing.
- No UI work. Buttons, banners, and rows that consume `RequestOutcome` stay in later steps.
- Do not start deleting legacy consumers in this step. Migration belongs to Steps 1.5 and 1.6.

### Acceptance tests — Tests/... — test name + what it asserts + mockup/doc clause it ties to
- `Tests/SeshatAppKitTests/Permissions/AppKitPermissionServiceTests.swift` — `testRequestMicrophonePromptsOnlyWhenNotDetermined`; asserts the service does not reopen Settings or pretend to prompt when mic status is already decided; ties to `Sources/SeshatAppKit/Permissions/AppKitMicrophonePermissionRequester.swift:30-56`.
- `Tests/SeshatAppKitTests/Permissions/AppKitPermissionServiceTests.swift` — `testRequestInputMonitoringRequiresRelaunchWhenSettingsOrPromptPathRuns`; asserts IM request outcomes preserve `requiresRelaunch = true`; ties to the restart warning already logged in `Sources/SeshatAppKit/Hotkeys/GlobalHotkeyMonitor.swift:118-129`.
- `Tests/SeshatAppKitTests/Permissions/AppKitPermissionServiceTests.swift` — `testRequestAccessibilityTriggersPromptWithoutFakingDenied`; asserts AX request behavior never fabricates `.denied`; ties to locked decision `#8` and `Sources/SeshatAppKit/Paste/PasteInjector.swift:168-171`.

### Validation checklist (implementer ticks box-by-box in hand-off)
- [ ] `RequestOutcome` remains the exact three-flag struct from Step 1.1.
- [ ] Microphone request behavior mirrors the current requester semantics when status is `.notDetermined`, but denied/restricted paths open Settings instead of pretending a prompt still exists.
- [ ] Input Monitoring request paths always set `requiresRelaunch = true`.
- [ ] Accessibility request paths never manufacture a `.denied` service state; the service remains `.pending` until AX trust becomes true.
- [ ] Diff against this step shows no silent divergence; every modified file is listed above, and any proposed deviation is recorded in the commit message comment and hand-off report.
- [ ] No `Color(hex:` outside `Theme/*` (hard rule — long-standing).
- [ ] No `UserDefaults.standard.*` direct reads — typed resolvers only.
- [ ] No `type`/`kind`/`intent` field added (hard rule — Phase 3 design lock: `project_phase3_notes_equals_history.md`).
- [ ] `swift build --build-tests` green from the main-repo path.
- [ ] No files outside `Files touched` modified.

### Commit style — `trunk: phase 1.3: <verb-led subject>`. Test + fix in same commit.
`trunk: phase 1.3: add relaunch-aware permission request semantics`

### Hand-off report template
```md
Phase 1.3 hand-off
- Commit: <sha> trunk: phase 1.3: add relaunch-aware permission request semantics
- Request semantics shipped:
  - microphone: <summary>
  - inputMonitoring: <summary>
  - accessibility: <summary>
- Verification commands: <list>
- Deviations from plan: none | <required explicit note>
- Follow-ups / blockers: none | <list>
```

## Step 1.4 — Publish one refreshed snapshot and refresh on app activation
> Do NOT diverge from this plan or the Manus mockups. Silent divergence is the cardinal sin. To deviate, surface the proposed divergence in a comment in the commit message AND in the hand-off report; wait for main-session confirmation. Paraphrasing the contract is divergence. Renaming variables the plan specifies is divergence. Choosing a different animation curve than the mockup implies is divergence.

### Files touched (exhaustive) — path:line-range — what changes
- `Sources/SeshatAppKit/Permissions/AppKitPermissionService.swift:new file` — make the live service `ObservableObject`, store one published `[Permission: PermissionStatus]` snapshot, and add a single `NSApplication.didBecomeActiveNotification` observer that calls `refresh()`.
- `Sources/SeshatAppKit/Composition/AppComposition.swift:8-93` — instantiate one shared live service and expose it to app composition.
- `Tests/SeshatAppKitTests/Permissions/AppKitPermissionServiceTests.swift:new file` — add notification-driven refresh tests and published-snapshot assertions.
- `Tests/SeshatAppKitTests/AppEntryPointTests.swift:8-82` — extend the entry-point test surface if the app now builds with an injected shared permission service from composition.

### Scope — IN
- Publish one snapshot dictionary. This is the only observable permission stream in Phase 1.
- Refresh when the app becomes active again so settings changes made in System Settings are picked up without bespoke polling.
- Keep refresh idempotent. Multiple `didBecomeActive` notifications must not stack duplicate observers or leak refresh loops.

### Scope — OUT (with backlog ticket paths where applicable)
- No UI consumers yet. This step stops at the observable service surface.
- No per-permission publishers, no `AsyncStream`, and no timer polling.
- No routing changes yet. The existing menu bar and onboarding UI stay on their old collaborators until the next two steps.

### Acceptance tests — Tests/... — test name + what it asserts + mockup/doc clause it ties to
- `Tests/SeshatAppKitTests/Permissions/AppKitPermissionServiceTests.swift` — `testRefreshPublishesSingleSnapshotUpdate`; asserts one published dictionary update occurs for a refresh; ties to `plans/CENTRAL_LAYERS_PROMPT.md:166-169`.
- `Tests/SeshatAppKitTests/Permissions/AppKitPermissionServiceTests.swift` — `testDidBecomeActiveNotificationTriggersRefresh`; asserts the service re-reads OS state on activation; ties to the Phase 1 lock that activation refresh replaces per-permission streams.
- `Tests/SeshatAppKitTests/AppEntryPointTests.swift` — `testAppCompositionProvidesSharedPermissionService`; asserts the entry point reads one composed service rather than building feature-local requesters; ties to `Sources/SeshatAppKit/Composition/AppComposition.swift:8-93`.

### Validation checklist (implementer ticks box-by-box in hand-off)
- [ ] Exactly one published snapshot dictionary exists on the service.
- [ ] Exactly one activation observer exists; repeated init/deinit cycles do not accumulate observers.
- [ ] No per-permission `AsyncStream` or polling timer was introduced.
- [ ] The shared service is constructed in composition, not ad hoc in each consumer.
- [ ] Diff against this step shows no silent divergence; every modified file is listed above, and any proposed deviation is recorded in the commit message comment and hand-off report.
- [ ] No `Color(hex:` outside `Theme/*` (hard rule — long-standing).
- [ ] No `UserDefaults.standard.*` direct reads — typed resolvers only.
- [ ] No `type`/`kind`/`intent` field added (hard rule — Phase 3 design lock: `project_phase3_notes_equals_history.md`).
- [ ] `swift build --build-tests` green from the main-repo path.
- [ ] No files outside `Files touched` modified.

### Commit style — `trunk: phase 1.4: <verb-led subject>`. Test + fix in same commit.
`trunk: phase 1.4: publish permission snapshots with activation refresh`

### Hand-off report template
```md
Phase 1.4 hand-off
- Commit: <sha> trunk: phase 1.4: publish permission snapshots with activation refresh
- Snapshot publisher shape: <description>
- Activation refresh wiring: <description>
- Verification commands: <list>
- Deviations from plan: none | <required explicit note>
- Follow-ups / blockers: none | <list>
```

## Step 1.5 — Migrate menu bar, hotkey, and paste consumers onto the service
> Do NOT diverge from this plan or the Manus mockups. Silent divergence is the cardinal sin. To deviate, surface the proposed divergence in a comment in the commit message AND in the hand-off report; wait for main-session confirmation. Paraphrasing the contract is divergence. Renaming variables the plan specifies is divergence. Choosing a different animation curve than the mockup implies is divergence.

### Files touched (exhaustive) — path:line-range — what changes
- `Sources/SeshatAppKit/Hotkeys/GlobalHotkeyMonitor.swift:11-130,221-240` — replace `PermissionProbing` injection with the shared service, record “first monitor attempt” before interpreting IM status, and keep the existing warn-log path grounded in unified status values.
- `Sources/SeshatAppKit/Paste/PasteInjector.swift:28-184` — replace raw AX closures with the shared service, preserving clipboard fallback when AX is absent.
- `Sources/SeshatAppKit/MenuBar/MenuBarSceneModel.swift:7-151` — replace mic-specific state/request collaborators with the shared service for microphone status + request flow.
- `Sources/SeshatAppKit/MenuBar/StatusItemMenuModel.swift:13-174` — derive warning rows from unified `PermissionStatus` values instead of legacy IM / mic enums.
- `Sources/SeshatAppKit/MenuBar/StatusItemController.swift:29-268` — replace direct IM probe and hard-coded settings URLs with the service snapshot + deep links.
- `Sources/SeshatAppKit/Composition/AppComposition.swift:48-93` — inject the composed service into the hotkey monitor and menu-bar stack.
- `Tests/SeshatAppKitTests/GlobalHotkeyMonitorTests.swift:284-322` — migrate the IM-failure tests to a service fake.
- `Tests/SeshatAppKitTests/PasteInjectorTests.swift:20-203` — migrate AX prompt/fallback tests to a service fake.
- `Tests/SeshatAppKitTests/MenuBarSceneModelTests.swift:11-260` — migrate mic request/state tests to a service fake.
- `Tests/SeshatAppKitTests/MenuBar/StatusItemMenuModelTests.swift:12-217` — keep warning-order coverage under the new service status surface.
- `Tests/SeshatAppKitTests/MenuBarFlowIntegrationTests.swift:17-149` — keep integration coverage after the menu-bar stack switches to the service.
- `Tests/SeshatAppKitTests/ManualStatusItemVerification.md:11-25` — add activation-refresh coverage for permission warning rows and keep the existing packaged-app manual checks.

### Scope — IN
- Move every non-Settings runtime consumer that already exists on trunk onto the new service.
- Keep the current menu-bar UX shape intact for now. This step is service migration, not Manus menu redesign.
- Preserve the existing paste fallback semantics from `Sources/SeshatAppKit/Paste/PasteInjector.swift:168-171`.

### Scope — OUT (with backlog ticket paths where applicable)
- No Manus menu layout changes here. `screen_menu.png` belongs to Phase 2.2 in [plans/PHASE_2_unified_ui.md](/Users/nitinkum/Projects/nitkrar/seshat/plans/PHASE_2_unified_ui.md).
- No onboarding-window migration yet. That is Step 1.6.
- Do not touch `Sources/SeshatAudio/AVAudioCaptureService.swift:39-45`.

### Acceptance tests — Tests/... — test name + what it asserts + mockup/doc clause it ties to
- `Tests/SeshatAppKitTests/GlobalHotkeyMonitorTests.swift` — `testNilMonitorFailureEmitsDeniedWarningThroughLogSink`; asserts IM failure logging now flows through unified service state; ties to `Sources/SeshatAppKit/Hotkeys/GlobalHotkeyMonitor.swift:102-129`.
- `Tests/SeshatAppKitTests/PasteInjectorTests.swift` — `testPromptsAccessibilityWhenNotTrustedAndLeavesTranscriptOnClipboard`; asserts AX fallback behavior is unchanged under the new service; ties to locked decision `#8` and `Sources/SeshatAppKit/Paste/PasteInjector.swift:168-171`.
- `Tests/SeshatAppKitTests/MenuBarSceneModelTests.swift` — `testHandleRecordButtonTapRequestsMicrophoneThroughPermissionService`; asserts the menu-bar record path prompts microphone through the unified service rather than the legacy requester; ties to `Sources/SeshatAppKit/MenuBar/MenuBarSceneModel.swift:99-117`.
- `Tests/SeshatAppKitTests/MenuBar/StatusItemMenuModelTests.swift` — `testDeniedMicrophonePrependsPermissionsNoteAndWarningItem` and `testDeniedInputMonitoringPrependsPermissionsNoteAndWarningItem`; assert warning rows are still correct after the migration; ties to `Sources/SeshatAppKit/MenuBar/StatusItemMenuModel.swift:74-100`.

### Validation checklist (implementer ticks box-by-box in hand-off)
- [ ] `GlobalHotkeyMonitor`, `PasteInjector`, `MenuBarSceneModel`, and `StatusItemController` all consume the shared service instead of split request/probe types.
- [ ] The first IM monitor-registration attempt is still what unlocks a non-pending IM verdict, matching `Sources/SeshatCore/PermissionStatus.swift:22-25`.
- [ ] Locked decision `#8` still holds: if AX is missing, paste leaves the transcript on the clipboard and never blocks recording/transcription.
- [ ] Locked decision `#9` still holds: `Sources/SeshatAudio/AVAudioCaptureService.swift:39-45` is unchanged.
- [ ] Diff against this step shows no silent divergence; every modified file is listed above, and any proposed deviation is recorded in the commit message comment and hand-off report.
- [ ] No `Color(hex:` outside `Theme/*` (hard rule — long-standing).
- [ ] No `UserDefaults.standard.*` direct reads — typed resolvers only.
- [ ] No `type`/`kind`/`intent` field added (hard rule — Phase 3 design lock: `project_phase3_notes_equals_history.md`).
- [ ] `swift build --build-tests` green from the main-repo path.
- [ ] No files outside `Files touched` modified.

### Commit style — `trunk: phase 1.5: <verb-led subject>`. Test + fix in same commit.
`trunk: phase 1.5: migrate menu bar hotkey and paste flows to permission service`

### Hand-off report template
```md
Phase 1.5 hand-off
- Commit: <sha> trunk: phase 1.5: migrate menu bar hotkey and paste flows to permission service
- Consumers migrated: <list>
- Legacy permission collaborators still present: <list>
- Verification commands: <list>
- Deviations from plan: none | <required explicit note>
- Follow-ups / blockers: none | <list>
```

## Step 1.6 — Migrate onboarding gating and app entry to the service; make AX optional everywhere
> Do NOT diverge from this plan or the Manus mockups. Silent divergence is the cardinal sin. To deviate, surface the proposed divergence in a comment in the commit message AND in the hand-off report; wait for main-session confirmation. Paraphrasing the contract is divergence. Renaming variables the plan specifies is divergence. Choosing a different animation curve than the mockup implies is divergence.

### Files touched (exhaustive) — path:line-range — what changes
- `Sources/SeshatAppKit/Onboarding/OnboardingViewModel.swift:4-68` — replace the onboarding-specific probe actor dependency with the shared service while keeping onboarding-only UI state like “skipped” local to the view model.
- `Sources/SeshatAppKit/Onboarding/OnboardingView.swift:54-396` — keep the existing layout/copy, but route button taps and row states through the service-backed view model.
- `Sources/SeshatAppKit/Onboarding/OnboardingWindowController.swift:67-156` — replace the split mic/IM/AX gate with service snapshot checks; drop Accessibility from `areCriticalPermissionsGranted`.
- `Sources/SeshatAppKit/Composition/SeshatAppMain.swift:9-259` (post-Phase-0 path `Sources/SeshatAppKit/Composition/AppMain.swift`) — inject the shared service into onboarding, menu bar, pill tap routing, and paste composition.
- `Sources/SeshatAppKit/SeshatApp.swift:12-53` — if the injectable shell still mirrors the old mic-requester surface, move it to the shared service so compile-time coverage matches production wiring.
- `Tests/SeshatAppKitTests/OnboardingViewModelTests.swift:7-150` — migrate the view-model tests to a service fake while preserving the current optional-AX assertions.
- `Tests/SeshatAppKitTests/AppEntryPointTests.swift:8-82` — assert the app entry point now builds around one shared permission service.
- `Tests/SeshatAppKitTests/SeshatAppKitShellCompileTests.swift:1-38` — keep the injectable shell compile coverage after the signature change.
- `Tests/SeshatAppKitTests/ManualOnboardingVerification.md:12-25` — tighten the runbook so it explicitly verifies AX is optional and clipboard fallback copy remains true.

### Scope — IN
- Make the service authoritative for every Phase 1 runtime permission gate.
- Preserve the existing onboarding window temporarily, but eliminate the AX inconsistency called out by locked decision `#8`.
- Keep onboarding completion persistence where it is for now. Full onboarding-window deletion belongs to Phase 2.10, not this step.

### Scope — OUT (with backlog ticket paths where applicable)
- Do not build the unified Settings > Permissions tab here. That is Phase 2.7.
- Do not remove the onboarding window yet. That is Phase 2.8 / 2.10 once the unified window is live.
- Do not delete `OnboardingState.swift` yet. That cleanup is intentionally deferred to Phase 2.10.

### Acceptance tests — Tests/... — test name + what it asserts + mockup/doc clause it ties to
- `Tests/SeshatAppKitTests/OnboardingViewModelTests.swift` — `testCanContinueRequiresMicrophoneAndInputMonitoringButNotAccessibility`; asserts AX remains optional after the migration; ties to `Sources/SeshatAppKit/Onboarding/OnboardingViewModel.swift:18-24`.
- `Tests/SeshatAppKitTests/OnboardingViewModelTests.swift` — `testContinueTappedPersistsCompletionWhenMandatoryPermissionsGranted`; asserts only microphone + IM are critical; ties to locked decision `#8`.
- `Tests/SeshatAppKitTests/AppEntryPointTests.swift` — `testAppMainBuildsWithSharedPermissionService`; asserts the entry point now composes one service instead of split requesters/probes; ties to `Sources/SeshatAppKit/Composition/SeshatAppMain.swift:61-167`.
- `Tests/SeshatAppKitTests/ManualOnboardingVerification.md` — `MV-OB-4`, `MV-OB-5`, and `MV-OB-7`; confirm the live onboarding surface still behaves like the current dark checklist UI while AX remains optional; ties to the existing view copy in `Sources/SeshatAppKit/Onboarding/OnboardingView.swift:73-176`.

### Validation checklist (implementer ticks box-by-box in hand-off)
- [ ] `OnboardingWindowControllerHost.areCriticalPermissionsGranted` checks only microphone + Input Monitoring; Accessibility is no longer part of the critical gate.
- [ ] `OnboardingViewModel` still exposes onboarding-only `skipped` UI state locally instead of leaking it into the shared core enum.
- [ ] Locked decision `#8` is fully honored: AX is optional in both tests and live app composition, and paste still falls back to clipboard when AX is absent.
- [ ] The existing onboarding visual layout/copy from `Sources/SeshatAppKit/Onboarding/OnboardingView.swift:15-176` is unchanged in this step; only the permission plumbing moved.
- [ ] Diff against this step shows no silent divergence; every modified file is listed above, and any proposed deviation is recorded in the commit message comment and hand-off report.
- [ ] No `Color(hex:` outside `Theme/*` (hard rule — long-standing).
- [ ] No `UserDefaults.standard.*` direct reads — typed resolvers only.
- [ ] No `type`/`kind`/`intent` field added (hard rule — Phase 3 design lock: `project_phase3_notes_equals_history.md`).
- [ ] `swift build --build-tests` green from the main-repo path.
- [ ] No files outside `Files touched` modified.

### Commit style — `trunk: phase 1.6: <verb-led subject>`. Test + fix in same commit.
`trunk: phase 1.6: make onboarding and app entry use the permission service`

### Hand-off report template
```md
Phase 1.6 hand-off
- Commit: <sha> trunk: phase 1.6: make onboarding and app entry use the permission service
- Gating rule shipped: <paste the final mic/IM-only rule>
- Call sites migrated: <list>
- Verification commands: <list>
- Deviations from plan: none | <required explicit note>
- Follow-ups / blockers: none | <list>
```

## Step 1.7 — Phase 2 handoff: move permission rows into unified Settings > Permissions [BLOCKED: Q.M1] [BLOCKED: Q.M2]
> Do NOT diverge from this plan or the Manus mockups. Silent divergence is the cardinal sin. To deviate, surface the proposed divergence in a comment in the commit message AND in the hand-off report; wait for main-session confirmation. Paraphrasing the contract is divergence. Renaming variables the plan specifies is divergence. Choosing a different animation curve than the mockup implies is divergence.

### Files touched (exhaustive) — path:line-range — what changes
- `Sources/SeshatAppKit/Settings/SettingsView.swift:4-201` — current 5-tab window is the source surface that Phase 2.7 replaces.
- `Sources/SeshatAppKit/Onboarding/OnboardingView.swift:54-396` — current permission-row copy/layout is the source surface that Phase 2.7 must transplant into the unified Settings permissions tab.
- `Sources/SeshatAppKit/Onboarding/OnboardingWindowController.swift:67-156` — current onboarding host logic is the routing input Phase 2.8 removes after the new tab exists.
- `plans/App UI design/Claude_Final_Bundle_Prompt.md:68-76` — authoritative Settings/Permissions tab spec.
- `plans/App UI design/final_settings_permissions_v2.png` — authoritative mockup for the target surface.
- `Sources/SeshatAppKit/MainWindow/Settings/PermissionsTabView.swift:new file (Phase 2 only)` — destination surface for the migrated permission rows.

### Scope — IN
- Preserve this step number in sequencing only.
- Treat the current onboarding permission content as the input to Phase 2.7’s unified permissions tab work.

### Scope — OUT (with backlog ticket paths where applicable)
- Do not execute this step on the Phase 1 branch.
- Do not invent a Settings control mapping before Q.M1 / Q.M2 are answered in main session.

### Acceptance tests — Tests/... — test name + what it asserts + mockup/doc clause it ties to
- `Tests/SeshatAppKitTests/ManualSettingsVerification.md` — future Phase 2.7 runbook entries must assert the final rows match `final_settings_permissions_v2.png` and `plans/App UI design/Claude_Final_Bundle_Prompt.md:75-76`.
- `Tests/SeshatAppKitTests/OnboardingViewModelTests.swift` — keep the current permission-row logic green until Phase 2.7 replaces the surface.

### Validation checklist (implementer ticks box-by-box in hand-off)
- [ ] This step is not implemented on the Phase 1 branch.
- [ ] The hand-off explicitly points implementers at Phase 2.7 and marks `[BLOCKED: Q.M1] [BLOCKED: Q.M2]`.
- [ ] `final_settings_permissions_v2.png` is the target mockup once Phase 2 executes this work.
- [ ] Locked decision `#8` still applies when the step eventually lands: AX remains optional in the unified tab.
- [ ] Diff against this step shows no silent divergence; if anyone attempts to implement it early, the deviation is recorded and main-session confirmation is requested first.
- [ ] No `Color(hex:` outside `Theme/*` (hard rule — long-standing).
- [ ] No `UserDefaults.standard.*` direct reads — typed resolvers only.
- [ ] No `type`/`kind`/`intent` field added (hard rule — Phase 3 design lock: `project_phase3_notes_equals_history.md`).
- [ ] `swift build --build-tests` green from the main-repo path.
- [ ] No files outside `Files touched` modified.

### Commit style — No Phase 1 commit. Execute only under Phase 2.7 commit styles in [plans/PHASE_2_unified_ui.md](/Users/nitinkum/Projects/nitkrar/seshat/plans/PHASE_2_unified_ui.md).

### Hand-off report template
```md
Phase 1.7 hand-off
- Status: deferred to Phase 2.7
- Blockers: Q.M1, Q.M2
- Phase 2 target files: <list>
- Deviations from plan: none | <required explicit note>
- Follow-ups / blockers: waiting on main-session answers
```

## Step 1.8 — Phase 2 handoff: replace onboarding routing with unified-window permission entrypoints [BLOCKED: Q.M1] [BLOCKED: Q.M2]
> Do NOT diverge from this plan or the Manus mockups. Silent divergence is the cardinal sin. To deviate, surface the proposed divergence in a comment in the commit message AND in the hand-off report; wait for main-session confirmation. Paraphrasing the contract is divergence. Renaming variables the plan specifies is divergence. Choosing a different animation curve than the mockup implies is divergence.

### Files touched (exhaustive) — path:line-range — what changes
- `Sources/SeshatAppKit/Composition/SeshatAppMain.swift:61-167` (post-Phase-0 path `Sources/SeshatAppKit/Composition/AppMain.swift`) — current onboarding fallback and first-launch routing live here today.
- `Sources/SeshatAppKit/Onboarding/OnboardingWindowController.swift:67-156` — current onboarding window host that Phase 2.8 must retire from runtime routing.
- `plans/App UI design/Claude_Final_Bundle_Prompt.md:68-76,93-100` — authoritative “Permissions replaces standalone onboarding” and implementation-order clauses.
- `plans/App UI design/final_settings_permissions_v2.png` — target landing surface for missing-permission remediation.
- `Sources/SeshatAppKit/MainWindow/MainWindowController.swift:new file (Phase 2 only)` — future routing owner.

### Scope — IN
- Preserve this step number in sequencing only.
- Transfer the runtime “missing permissions” fallback from onboarding-window routing to unified-window routing once the unified Settings > Permissions tab exists.

### Scope — OUT (with backlog ticket paths where applicable)
- Do not execute this step on the Phase 1 branch.
- Do not remove the onboarding window before Phase 2.7 supplies the replacement surface.

### Acceptance tests — Tests/... — test name + what it asserts + mockup/doc clause it ties to
- `Tests/SeshatAppKitTests/AppEntryPointTests.swift` — future Phase 2.8 coverage must assert missing permissions open the unified Settings > Permissions route rather than the standalone onboarding window; ties to `plans/App UI design/Claude_Final_Bundle_Prompt.md:75-76,98-100`.
- `Tests/SeshatAppKitTests/ManualSettingsVerification.md` — future Phase 2.8 runbook entries must assert the first-launch fallback lands on the Manus permissions tab.

### Validation checklist (implementer ticks box-by-box in hand-off)
- [ ] This step is not implemented on the Phase 1 branch.
- [ ] The hand-off explicitly points implementers at Phase 2.8.
- [ ] `final_settings_permissions_v2.png` is the target fallback surface once Phase 2 executes this work.
- [ ] Locked decision `#8` remains intact when the fallback moves: AX is optional and does not block continuation.
- [ ] Diff against this step shows no silent divergence; if anyone attempts to implement it early, the deviation is recorded and main-session confirmation is requested first.
- [ ] No `Color(hex:` outside `Theme/*` (hard rule — long-standing).
- [ ] No `UserDefaults.standard.*` direct reads — typed resolvers only.
- [ ] No `type`/`kind`/`intent` field added (hard rule — Phase 3 design lock: `project_phase3_notes_equals_history.md`).
- [ ] `swift build --build-tests` green from the main-repo path.
- [ ] No files outside `Files touched` modified.

### Commit style — No Phase 1 commit. Execute only under Phase 2.8 commit styles in [plans/PHASE_2_unified_ui.md](/Users/nitinkum/Projects/nitkrar/seshat/plans/PHASE_2_unified_ui.md).

### Hand-off report template
```md
Phase 1.8 hand-off
- Status: deferred to Phase 2.8
- Blockers: Q.M1, Q.M2
- Phase 2 target files: <list>
- Deviations from plan: none | <required explicit note>
- Follow-ups / blockers: waiting on unified permissions surface
```

## Step 1.9 — Phase 2 handoff: delete legacy permission/requester surfaces after the UI cutover
> Do NOT diverge from this plan or the Manus mockups. Silent divergence is the cardinal sin. To deviate, surface the proposed divergence in a comment in the commit message AND in the hand-off report; wait for main-session confirmation. Paraphrasing the contract is divergence. Renaming variables the plan specifies is divergence. Choosing a different animation curve than the mockup implies is divergence.

### Files touched (exhaustive) — path:line-range — what changes
- `Sources/SeshatCore/PermissionStatus.swift:1-44` — legacy IM-only domain file to delete in Phase 2.10 after all consumers are on the new service.
- `Sources/SeshatAppKit/MenuBar/MicrophonePermissionState.swift:1-7` — legacy mic-only state enum to delete after all menu/onboarding consumers are migrated.
- `Sources/SeshatAppKit/Permissions/AppKitMicrophonePermissionRequester.swift:1-57` — legacy mic-only requester to delete once no consumers remain.
- `Sources/SeshatAppKit/Onboarding/PermissionRequester.swift:9-63` — onboarding-specific request actor to delete once the unified Settings permissions UI replaces onboarding.
- `plans/App UI design/Claude_Final_Bundle_Prompt.md:97-100` — cleanup-order clause that lands after permissions + unified shell.
- `Sources/SeshatAppKit/Onboarding/OnboardingWindowController.swift:67-156` and `Sources/SeshatCore/OnboardingState.swift:3-34` — runtime cleanup companions once the old routing is gone.

### Scope — IN
- Preserve this step number in sequencing only.
- Make the cleanup dependency explicit so nobody deletes the old surfaces before Phase 2.7 / 2.8 land.

### Scope — OUT (with backlog ticket paths where applicable)
- Do not execute this step on the Phase 1 branch.
- Do not delete compatibility surfaces early “because the new service exists”. Wait until the unified settings route is live and app entry no longer references them.

### Acceptance tests — Tests/... — test name + what it asserts + mockup/doc clause it ties to
- `Tests/SeshatAppKitTests/AppEntryPointTests.swift` — future Phase 2.10 coverage must prove the app entry point builds without onboarding-window or legacy permission types.
- `Tests/SeshatAppKitTests/MenuBar/StatusItemMenuModelTests.swift` — future Phase 2.10 coverage must prove the menu still builds after the legacy enums disappear.

### Validation checklist (implementer ticks box-by-box in hand-off)
- [ ] This step is not implemented on the Phase 1 branch.
- [ ] The hand-off explicitly points implementers at Phase 2.10.
- [ ] No legacy permission/requester type is deleted before Phase 2.7 and 2.8 land.
- [ ] Diff against this step shows no silent divergence; if anyone attempts to implement it early, the deviation is recorded and main-session confirmation is requested first.
- [ ] No `Color(hex:` outside `Theme/*` (hard rule — long-standing).
- [ ] No `UserDefaults.standard.*` direct reads — typed resolvers only.
- [ ] No `type`/`kind`/`intent` field added (hard rule — Phase 3 design lock: `project_phase3_notes_equals_history.md`).
- [ ] `swift build --build-tests` green from the main-repo path.
- [ ] No files outside `Files touched` modified.

### Commit style — No Phase 1 commit. Execute only under Phase 2.10 commit styles in [plans/PHASE_2_unified_ui.md](/Users/nitinkum/Projects/nitkrar/seshat/plans/PHASE_2_unified_ui.md).

### Hand-off report template
```md
Phase 1.9 hand-off
- Status: deferred to Phase 2.10
- Cleanup queue: <list>
- Phase 2 target files: <list>
- Deviations from plan: none | <required explicit note>
- Follow-ups / blockers: waiting on unified-window cutover
```

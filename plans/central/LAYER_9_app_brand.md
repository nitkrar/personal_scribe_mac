# Layer 9 — App brand / identity

## Critical discipline
> **Do NOT diverge from this plan. Silent divergence is the cardinal sin. To deviate, surface the proposed divergence in a commit-message comment AND in the hand-off report; wait for main-session confirmation. Paraphrasing the contract is divergence. Renaming a protocol the plan specifies is divergence. Choosing a different storage format than the plan specifies is divergence.**

## Why this layer exists
"Seshat" string literal + bundle ID + absent marketing URLs are scattered. One struct consolidates them; a future rebrand flips one file; the "hide links if URL nil" decision lands mechanically.

Scope summary, copied forward from `plans/CENTRAL_LAYERS_PROMPT.md:375-388`:
- Type: `AppBrand` — `enum` (namespace-only) in `SeshatCore`.
- `AppBrand` owns `displayName`, `bundleIdentifier`, `logSubsystem`, `websiteURL`, `privacyURL`, `termsURL`, `version`, and `buildNumber`.
- Migrate all user-facing `"Seshat"` literals to `AppBrand.displayName`. Menu header, window title, About header, menu bar status-item accessibility label, etc.
- Migrate `"com.nitkrar.seshat"` literals to `AppBrand.bundleIdentifier`. Include: `PasteInjector.seshatBundleIdentifier`, `AppLogger` subsystem, TCC deep-link sites.
- Settings About tab reads `AppBrand.displayName + " " + AppBrand.version + " (" + AppBrand.buildNumber + ")"` per `plans/App UI design/Seshat Q4_Q5 Handoff Spec.md:34-38`.
- Link rows: if `AppBrand.websiteURL == nil`, don't render the row, per `plans/CENTRAL_LAYERS_PROMPT.md:71` and `plans/CENTRAL_LAYERS_PROMPT.md:388`.

Dependency summary before execution:
- Stage 1 can run in parallel with Layers 1, 2, 3, 6, 7, and 8 because it only claims new `AppBrand/` subdirectories, satisfying `plans/CENTRAL_LAYERS_PROMPT.md:42-59`.
- Stage 2 cleanup of TCC deep-link callers requires Layer 1 Stage 2 first, because Layer 1 explicitly blocks Layer 9 for `systemSettingsDeepLink` adoption in `plans/CENTRAL_LAYERS_PROMPT.md:179-180`.
- No numbered Layer 1-8 consumer depends on Layer 9 finishing Stage 2; this layer instead unblocks the external Phase 2 About-tab contract in `plans/CENTRAL_LAYERS_PROMPT.md:387-400` and `plans/App UI design/Seshat UI Polish & Unified Window Implementation.md:68-76`.

## Observed current spread
| File | Line(s) | What lives there |
|---|---|---|
| `Sources/SeshatCore/Logger.swift` | `4-10` | `SeshatLogger.subsystem` hard-codes `"com.nitkrar.seshat"` instead of reading a shared identity source. |
| `Sources/SeshatAppKit/Paste/PasteInjector.swift` | `72-115` | `PasteInjector` owns its own `"com.nitkrar.seshat"` constant and injects it into self-frontmost routing. |
| `Sources/SeshatAppKit/MenuBar/StatusItemController.swift` | `135-183`, `253-266` | Status-item tooltip copy hard-codes `"Seshat"`; the same file also owns hard-coded microphone/input-monitoring System Settings URLs. |
| `Sources/SeshatAppKit/MenuBar/StatusItemMenuModel.swift` | `103-131` | Menu rows include `Quit Seshat`, which is current user-facing brand text in the status-item menu. |
| `Sources/SeshatAppKit/Onboarding/OnboardingWindowController.swift` | `18-24` | Onboarding window title is hard-coded as `Welcome to Seshat`. |
| `Sources/SeshatAppKit/Onboarding/OnboardingView.swift` | `43-94`, `254`, `387-394` | Onboarding header/copy hard-code `"Seshat"` and the same file owns a local privacy-settings deep-link builder. |
| `Sources/SeshatAppKit/Settings/SettingsWindowController.swift` | `11-26` | Settings window title is hard-coded as `Seshat Settings`. |
| `Sources/SeshatAppKit/Notes/NotesWindowController.swift` | `12-24` | Notes/history window title is hard-coded as `Seshat History`. |
| `Sources/SeshatAppKit/Settings/AdvancedTab.swift` | `30-33`, `100-102` | Advanced copy describes `Seshat` app-support data and base-directory selection text with hard-coded app-name strings. |
| `Sources/SeshatAppKit/Settings/ShortcutsTab.swift` | `31-43` | Restart and emergency-quit explanatory copy hard-codes `Seshat`. |
| `Sources/SeshatCore/BaseDirectoryMigrator.swift` | `17-42` | User-visible migration failure reason says `Seshat could not create and remove a write probe...`. |
| `Sources/SeshatAppKit/Overlay/PillOverlayView.swift` | `88-145`, `226-227` | Pill accessibility labels embed the app name directly for idle/recording/transcribing/error states. |
| `Sources/SeshatAppKit/MenuBar/BuildInfo.swift` | `11-22` | Version parsing and build display own a hard-coded `"Seshat"` display string, but no build-number source yet. |
| `Sources/SeshatAppKit/SeshatApp.swift` | `62-70` | App-shell fallback `openSettings` uses a local microphone privacy deep-link. |
| `Sources/SeshatAppKit/Composition/SeshatAppMain.swift` | `203-211` | Entry-point fallback `openSettings` uses the same local microphone privacy deep-link. |

## Proposed API / contracts
### Types (enums, structs)
| Type | Shape | Notes |
|---|---|---|
| `AppBrand` | Namespace-only `enum` in `Sources/SeshatCore/AppBrand/AppBrand.swift` | Public static identity surface for display name, bundle identifier, log subsystem, optional marketing URLs, version, and build number. |

### Protocols
None. This layer centralizes immutable app identity; it should not introduce a service protocol or mutable state holder.

### Errors
None. Existing consumers keep their own error types; they only replace embedded brand strings with `AppBrand`.

## Proposed live implementation
`AppBrand` lives in `SeshatCore`, not `SeshatAppKit`, so both core infrastructure (`SeshatLogger`) and AppKit surfaces (`PasteInjector`, onboarding, windows, pill labels) can import the same source of truth without creating a UI dependency. This file must sit in a brand-specific new subdirectory, e.g. `Sources/SeshatCore/AppBrand/`, so Layer 9 Stage 1 stays collision-free under `plans/CENTRAL_LAYERS_PROMPT.md:56-59`.

Keep the type synchronous and side-effect-light. `displayName`, `bundleIdentifier`, `logSubsystem`, and the three marketing URLs are static constants. `version` and `buildNumber` read from `Bundle.main.infoDictionary` using the same whitespace-trimming approach already present in `Sources/SeshatAppKit/MenuBar/BuildInfo.swift:11-18`, extended to `CFBundleVersion` for the About contract in `plans/App UI design/Seshat Q4_Q5 Handoff Spec.md:34-38`. If a package-internal parsing helper is needed for tests, keep it internal to `AppBrand.swift`; do not introduce another public brand type. No AppKit import, no observable object, no mutable cache that can drift from `Bundle.main`.

Execution dependency notes for implementers:
- Stage 1 parallelizes with Layers 1, 2, 3, 6, 7, and 8.
- Stage 2 steps 2.1 through 2.7 are independent of other numbered layers.
- Stage 2 step 2.8 and Stage 3 step 3.1 require Layer 1 Stage 2 first because those consumers are also where the shared permission deep-link API lands.

## Migration of existing call sites
### Stage 1 — Build in parallel
Stage 1 can run in parallel with Layers 1, 2, 3, 6, 7, and 8. Do not touch any existing consumer in this stage.

### Step 1.1 — Add the `AppBrand` namespace in a new core directory
Dependency: none.

| Change | Before | After |
|---|---|---|
| Brand source of truth | Brand literals are scattered across logger, paste routing, window titles, onboarding copy, pill accessibility copy, and build display helpers (`Sources/SeshatCore/Logger.swift:4-10`, `Sources/SeshatAppKit/Paste/PasteInjector.swift:72-115`, `Sources/SeshatAppKit/MenuBar/BuildInfo.swift:11-22`) | A new `AppBrand` namespace in `Sources/SeshatCore/AppBrand/` owns the exact static surface mandated by `plans/CENTRAL_LAYERS_PROMPT.md:376-384`. |

Validation hooks:
- [ ] The new type is isolated to a new `Sources/SeshatCore/AppBrand/` directory, satisfying the Stage 1 isolation rules in `plans/CENTRAL_LAYERS_PROMPT.md:42-59`.
- [ ] `displayName`, `bundleIdentifier`, `logSubsystem`, `websiteURL`, `privacyURL`, `termsURL`, `version`, and `buildNumber` match `plans/CENTRAL_LAYERS_PROMPT.md:376-384` exactly; URLs stay `nil` by default per `plans/CENTRAL_LAYERS_PROMPT.md:71`.
- [ ] The bundle-metadata parsing reuses the current version-trimming behavior visible in `Sources/SeshatAppKit/MenuBar/BuildInfo.swift:11-18` and satisfies the About-tab contract in `plans/App UI design/Seshat Q4_Q5 Handoff Spec.md:34-38`.

### Step 1.2 — Add Stage 1 tests for constants, optional URLs, and bundle metadata parsing
Dependency: none.

| Change | Before | After |
|---|---|---|
| Brand tests | Existing tests guard logger subsystem and build-string parsing in separate files (`Tests/SeshatCoreTests/SeshatLoggerTests.swift:4-10`, `Tests/SeshatAppKitTests/BuildInfoTests.swift:5-40`) | New `AppBrand` tests in a new `Tests/SeshatCoreTests/AppBrand/` directory cover the static constants, nil-link behavior, and version/build-number parsing without touching any live consumer. |

Validation hooks:
- [ ] The new tests preserve current expectations now guarded by `Tests/SeshatCoreTests/SeshatLoggerTests.swift:5-9` and `Tests/SeshatAppKitTests/BuildInfoTests.swift:11-40`, but move the source of truth to `AppBrand`.
- [ ] Nil-link assertions explicitly enforce `plans/CENTRAL_LAYERS_PROMPT.md:71` and `plans/CENTRAL_LAYERS_PROMPT.md:388`.
- [ ] No existing consumer file from the Observed current spread changes during Stage 1, in line with `plans/CENTRAL_LAYERS_PROMPT.md:44`.

### Stage 2 — Swap per consumer
Stage 2 migrates each consumer to `AppBrand`. Keep the old helpers only long enough to preserve per-step revertability.

### Step 2.1 — Switch `SeshatLogger` to `AppBrand.logSubsystem`
Dependency: none.

| Change | Before | After |
|---|---|---|
| Log subsystem | `Sources/SeshatCore/Logger.swift:4-10` hard-codes `"com.nitkrar.seshat"` and `Tests/SeshatCoreTests/SeshatLoggerTests.swift:5-9` asserts the literal directly | `SeshatLogger` delegates the subsystem string to `AppBrand.logSubsystem`, while tests continue asserting the effective value until a future rebrand actually changes it. |

Validation hooks:
- [ ] `Sources/SeshatCore/Logger.swift:4-10` no longer owns the bundle identifier literal; it resolves through the Stage 1 `AppBrand` contract from `plans/CENTRAL_LAYERS_PROMPT.md:378-379`.
- [ ] `Tests/SeshatCoreTests/SeshatLoggerTests.swift:5-9` still proves the subsystem resolves to `com.nitkrar.seshat`, preserving current logging behavior.

### Step 2.2 — Switch `PasteInjector` self-frontmost routing to `AppBrand.bundleIdentifier`
Dependency: none.

| Change | Before | After |
|---|---|---|
| Self-frontmost bundle identity | `Sources/SeshatAppKit/Paste/PasteInjector.swift:72-115` owns `seshatBundleIdentifier`; `Tests/SeshatAppKitTests/PasteInjectorTests.swift:103-128` hard-code the same identifier in the frontmost-app fake | `PasteInjector` reads `AppBrand.bundleIdentifier`, and the tests keep proving that self-frontmost routing falls back to clipboard instead of synthetic paste. |

Validation hooks:
- [ ] `Sources/SeshatAppKit/Paste/PasteInjector.swift:72-115` no longer stores a local `"com.nitkrar.seshat"` constant, matching `plans/CENTRAL_LAYERS_PROMPT.md:385-386`.
- [ ] `Tests/SeshatAppKitTests/PasteInjectorTests.swift:103-128` still covers `.frontmostAppIsSeshat` routing semantics after the constant moves behind `AppBrand.bundleIdentifier`.

### Step 2.3 — Swap menu-bar strings and status-item label/tooltip copy to `AppBrand.displayName`
Dependency: none.

| Change | Before | After |
|---|---|---|
| Menu-bar user-facing brand copy | `Sources/SeshatAppKit/MenuBar/StatusItemController.swift:151-183` hard-codes idle/recording/transcribing tooltip text and `Sources/SeshatAppKit/MenuBar/StatusItemMenuModel.swift:128-131` hard-codes `Quit Seshat` | Status-item tooltip/accessibility text and the quit row derive their branded prefix from `AppBrand.displayName`, preserving existing state-specific wording and menu order. |

Validation hooks:
- [ ] `Sources/SeshatAppKit/MenuBar/StatusItemController.swift:151-183` derives the idle/recording/transcribing brand prefix from `AppBrand.displayName`, satisfying `plans/CENTRAL_LAYERS_PROMPT.md:385`.
- [ ] `Sources/SeshatAppKit/MenuBar/StatusItemMenuModel.swift:103-131` still preserves the menu ordering and quit row expected by `Tests/SeshatAppKitTests/MenuBar/StatusItemMenuModelTests.swift:12-25`.
- [ ] The manual runbook in `Tests/SeshatAppKitTests/ManualStatusItemVerification.md:11-26` gains a brand-copy check for the status item without regressing the packaged-app icon/tint checks already listed there.

### Step 2.4 — Swap onboarding title and explanatory copy to `AppBrand.displayName`
Dependency: none.

| Change | Before | After |
|---|---|---|
| Onboarding brand copy | `Sources/SeshatAppKit/Onboarding/OnboardingWindowController.swift:18-24` and `Sources/SeshatAppKit/Onboarding/OnboardingView.swift:43-94,254` hard-code the app name in the title, heading, and explanatory text | Onboarding surfaces read `AppBrand.displayName`, so the user-visible name stays consistent across the window title, header, popovers, and Accessibility-skip warning copy. |

Validation hooks:
- [ ] `Sources/SeshatAppKit/Onboarding/OnboardingWindowController.swift:18-24` no longer hard-codes `Welcome to Seshat`, matching the Stage 2 display-name migration in `plans/CENTRAL_LAYERS_PROMPT.md:385`.
- [ ] `Sources/SeshatAppKit/Onboarding/OnboardingView.swift:43-94,254` uses `AppBrand.displayName` everywhere the user currently reads `Seshat`.
- [ ] `Tests/SeshatAppKitTests/ManualOnboardingVerification.md:10-25` gains a runtime check that the heading, subtitle context, and Accessibility-skip message still render correctly after the copy is centralized.

### Step 2.5 — Swap Settings-surface brand copy to `AppBrand.displayName`
Dependency: none.

| Change | Before | After |
|---|---|---|
| Settings window and settings-related copy | `Sources/SeshatAppKit/Settings/SettingsWindowController.swift:11-26`, `Sources/SeshatAppKit/Settings/AdvancedTab.swift:30-33,100-102`, `Sources/SeshatAppKit/Settings/ShortcutsTab.swift:31-43`, and `Sources/SeshatCore/BaseDirectoryMigrator.swift:17-42` hard-code the app name in titles, descriptions, restart copy, and migration failure reasons | The Settings window title, advanced descriptions, restart text, and base-directory migration failures all derive the brand name from `AppBrand.displayName`. |

Validation hooks:
- [ ] `Sources/SeshatAppKit/Settings/SettingsWindowController.swift:11-26` and `Sources/SeshatAppKit/Settings/AdvancedTab.swift:30-33,100-102` no longer own hard-coded `Seshat` strings.
- [ ] `Sources/SeshatAppKit/Settings/ShortcutsTab.swift:31-43` and `Sources/SeshatCore/BaseDirectoryMigrator.swift:17-42` keep the exact current behavior/message structure while moving the brand token behind `AppBrand.displayName`.
- [ ] `Tests/SeshatAppKitTests/ManualSettingsVerification.md:1-23` gains checks for the centralized Settings title and, when the Phase 2 About tab lands, for the header/version/link contract from `plans/App UI design/Seshat Q4_Q5 Handoff Spec.md:34-43` and `plans/App UI design/Seshat UI Polish & Unified Window Implementation.md:68-76`.

### Step 2.6 — Swap History window title to `AppBrand.displayName`
Dependency: none.

| Change | Before | After |
|---|---|---|
| Notes/history title | `Sources/SeshatAppKit/Notes/NotesWindowController.swift:12-24` hard-codes `Seshat History`; `Tests/SeshatAppKitTests/ManualNotesVerification.md:1-4` expects that exact string in the runbook | The history window title composes from `AppBrand.displayName` and the existing `History` suffix. |

Validation hooks:
- [ ] `Sources/SeshatAppKit/Notes/NotesWindowController.swift:12-24` no longer owns the raw app-name literal, matching `plans/CENTRAL_LAYERS_PROMPT.md:385`.
- [ ] `Tests/SeshatAppKitTests/Notes/NotesWindowControllerTests.swift:7-23` is extended to assert the window title alongside the existing window-reuse behavior.
- [ ] `Tests/SeshatAppKitTests/ManualNotesVerification.md:1-4` gains a runtime check that the reused window still presents the branded title from `AppBrand`.

### Step 2.7 — Swap pill accessibility labels to `AppBrand.displayName`
Dependency: none.

| Change | Before | After |
|---|---|---|
| Pill accessibility copy | `Sources/SeshatAppKit/Overlay/PillOverlayView.swift:88-145,226-227` embeds `Seshat` in idle/recording/transcribing/error accessibility labels | Accessibility labels build their branded prefix from `AppBrand.displayName` while preserving each state description. |

Validation hooks:
- [ ] `Sources/SeshatAppKit/Overlay/PillOverlayView.swift:88-145,226-227` keeps the current four state-specific accessibility phrases, but the app-name token comes from `AppBrand.displayName` per `plans/CENTRAL_LAYERS_PROMPT.md:385`.
- [ ] `Tests/SeshatAppKitTests/ManualPillOverlayVerification.md:1-118` gains a VoiceOver or Accessibility Inspector pass for the idle/recording/transcribing/error labels, because SwiftUI accessibility output is not fully XCTest-verifiable under the Flexible TDD rule.

### Step 2.8 — Replace local TCC deep-link builders after Layer 1 Stage 2 lands
Dependency: Layer 1.

| Change | Before | After |
|---|---|---|
| Permission-launcher URLs | `Sources/SeshatAppKit/MenuBar/StatusItemController.swift:253-266`, `Sources/SeshatAppKit/Onboarding/OnboardingView.swift:387-394`, `Sources/SeshatAppKit/SeshatApp.swift:62-70`, and `Sources/SeshatAppKit/Composition/SeshatAppMain.swift:203-211` each own local `x-apple.systempreferences:` URLs | Once Layer 1 Stage 2 lands, these callers read the shared permission deep-link API instead of keeping per-file URL builders, satisfying Layer 1's explicit block on Layer 9. |

Validation hooks:
- [ ] No TCC-deep-link literal remains in the four files above after the Layer 1 swap, satisfying `plans/CENTRAL_LAYERS_PROMPT.md:179-180`.
- [ ] The resulting settings-opening behavior still points to the same current anchors (`Privacy_Microphone`, `Privacy_ListenEvent`, `Privacy_Accessibility`) evidenced in `Sources/SeshatAppKit/Onboarding/OnboardingView.swift:70-107` and `Sources/SeshatAppKit/MenuBar/StatusItemController.swift:253-266`.

### Step 2.9 — Move version/build display ownership to `AppBrand` and prepare the future About surface
Dependency: none.

| Change | Before | After |
|---|---|---|
| Build metadata source | `Sources/SeshatAppKit/MenuBar/BuildInfo.swift:11-22` trims `CFBundleShortVersionString`, knows about `SeshatGitSHA`, and renders a hard-coded `Seshat` display string, but nothing exposes `CFBundleVersion` yet | `AppBrand` becomes the sole owner of version/build-number display inputs, and `BuildInfo` either delegates to it as a migration bridge or is marked for deletion in Stage 3. |

Validation hooks:
- [ ] The version/build-number source of truth now satisfies `plans/CENTRAL_LAYERS_PROMPT.md:383-388`.
- [ ] `Tests/SeshatAppKitTests/BuildInfoTests.swift:5-40` is either rewritten around `AppBrand` or retained only as a temporary bridge with an explicit Stage 3 deletion note.
- [ ] The future About-tab header/links can be built exactly as required by `plans/App UI design/Seshat Q4_Q5 Handoff Spec.md:34-43` without introducing another brand helper.

### Stage 3 — Delete
Run Stage 3 only after every Stage 2 consumer above is green. This layer's deletions are small but should still be isolated for easy revert.

### Step 3.1 — Delete leftover migration-only constants and local URL builders
Dependency: Layer 1 and all Layer 9 Stage 2 steps.

| Change | Before | After |
|---|---|---|
| Cleanup of transitional duplication | Stage 2 may leave behind migration-only helpers such as `PasteInjector.seshatBundleIdentifier` and per-file TCC URL builders until every consumer is swapped | Transitional constants/helpers are removed so `AppBrand` and Layer 1's shared deep-link API are the only remaining identity/deep-link sources. |

Validation hooks:
- [ ] `Sources/SeshatAppKit/Paste/PasteInjector.swift:72-115` no longer contains `seshatBundleIdentifier`, completing the `AppBrand.bundleIdentifier` migration required by `plans/CENTRAL_LAYERS_PROMPT.md:385-386`.
- [ ] `Sources/SeshatAppKit/MenuBar/StatusItemController.swift:253-266`, `Sources/SeshatAppKit/Onboarding/OnboardingView.swift:387-394`, `Sources/SeshatAppKit/SeshatApp.swift:62-70`, and `Sources/SeshatAppKit/Composition/SeshatAppMain.swift:203-211` no longer own private `x-apple.systempreferences:` builders after Layer 1 has landed.

### Step 3.2 — Delete `BuildInfo` only if [QUESTION-BRAND-1] resolves to “drop the short-SHA helper”
Dependency: all Layer 9 Stage 2 steps and main-session answer to [QUESTION-BRAND-1].

| Change | Before | After |
|---|---|---|
| Optional build-helper deletion | `Sources/SeshatAppKit/MenuBar/BuildInfo.swift` and `Tests/SeshatAppKitTests/BuildInfoTests.swift` remain as an unused bridge or future debug helper | If main session decides the git-SHA helper is out of scope for Layer 9, delete both files; otherwise leave them in place and do not force this deletion. |

Validation hooks:
- [ ] `Sources/SeshatAppKit/MenuBar/BuildInfo.swift:3-22` and `Tests/SeshatAppKitTests/BuildInfoTests.swift:4-40` are deleted only if no live consumer remains, `AppBrand` fully covers `plans/CENTRAL_LAYERS_PROMPT.md:383-388`, and [QUESTION-BRAND-1] is answered in favor of deletion.
- [ ] If the answer is “keep”, this step is skipped explicitly in the hand-off report rather than silently half-executed.

## Test strategy
- Unit tests: add `AppBrand` tests in a new `Tests/SeshatCoreTests/AppBrand/` directory covering exact constants, nil-link behavior, and `CFBundleShortVersionString` / `CFBundleVersion` parsing derived from `Sources/SeshatAppKit/MenuBar/BuildInfo.swift:11-18` and `plans/App UI design/Seshat Q4_Q5 Handoff Spec.md:34-38`.
- Unit tests: update `Tests/SeshatCoreTests/SeshatLoggerTests.swift:5-9`, `Tests/SeshatAppKitTests/PasteInjectorTests.swift:103-128`, and `Tests/SeshatAppKitTests/MenuBar/StatusItemMenuModelTests.swift:12-25` to assert the same runtime behavior after the constant source moves.
- Unit tests: extend `Tests/SeshatAppKitTests/Settings/SettingsWindowControllerTests.swift:7-21` and `Tests/SeshatAppKitTests/Notes/NotesWindowControllerTests.swift:7-23` to assert branded window titles in addition to the existing reuse behavior.
- Unit tests: keep `Tests/SeshatAppKitTests/BuildInfoTests.swift:5-40` only as long as `BuildInfo` still exists; otherwise replace it with `AppBrand` parsing coverage.
- Integration/regression guards: preserve the current self-frontmost paste fallback from `Tests/SeshatAppKitTests/PasteInjectorTests.swift:103-128`, the menu structure from `Tests/SeshatAppKitTests/MenuBar/StatusItemMenuModelTests.swift:12-25`, and the manual onboarding/settings/status-item/notes/pill runbooks already in `Tests/SeshatAppKitTests/`.
- Fakes: keep bundle-metadata parsing testable via a package-internal info-dictionary seam rather than stubbing `Bundle.main`; existing frontmost-app fakes and AppKit window-controller tests remain sufficient.

## Open design questions (surface — do not resolve)
- [QUESTION-BRAND-1] `Sources/SeshatAppKit/MenuBar/BuildInfo.swift:3-22` owns `SeshatGitSHA` short-SHA formatting but currently has no visible consumer. Should Layer 9 Stage 3 delete `BuildInfo.swift` and `Tests/SeshatAppKitTests/BuildInfoTests.swift`, or preserve/rename that helper for a future About/Advanced debug row?
- [QUESTION-BRAND-2] `plans/CENTRAL_LAYERS_PROMPT.md:383-384` requires `AppBrand.buildNumber`, but the repo has no current fallback semantics for missing `CFBundleVersion`. Should tests and dev-mode behavior use `"dev"`, `"unknown"`, or another explicit sentinel when the key is absent?

## Manual verification checklist
- `Tests/SeshatAppKitTests/ManualStatusItemVerification.md`: add `MV-SI-6` for the `Quit <AppBrand.displayName>` row and `MV-SI-7` for the idle/recording/transcribing status-item label/tooltip copy, covering `Sources/SeshatAppKit/MenuBar/StatusItemController.swift:151-183` and `Sources/SeshatAppKit/MenuBar/StatusItemMenuModel.swift:128-131`.
- `Tests/SeshatAppKitTests/ManualOnboardingVerification.md`: add `MV-OB-9` confirming the onboarding window title, heading, and Accessibility-skip warning all show the centralized display name from `Sources/SeshatAppKit/Onboarding/OnboardingWindowController.swift:18-24` and `Sources/SeshatAppKit/Onboarding/OnboardingView.swift:43-94,254`.
- `Tests/SeshatAppKitTests/ManualSettingsVerification.md`: add a check that the Settings window title and Settings-surface copy use `AppBrand.displayName`, and add a future-facing About-sub-tab check that the header/version/link rows match `plans/App UI design/Seshat Q4_Q5 Handoff Spec.md:34-43` while hiding nil URLs per `plans/CENTRAL_LAYERS_PROMPT.md:71`.
- `Tests/SeshatAppKitTests/ManualNotesVerification.md`: add a check that opening History shows `<AppBrand.displayName> History` from `Sources/SeshatAppKit/Notes/NotesWindowController.swift:12-24`.
- `Tests/SeshatAppKitTests/ManualPillOverlayVerification.md`: add `MV-B1-10` covering the four accessibility labels in `Sources/SeshatAppKit/Overlay/PillOverlayView.swift:88-145,226-227`, verified with VoiceOver or Accessibility Inspector.

## Validation checklist (implementer ticks box-by-box)
- [ ] `AppBrand` exposes only the Layer 9 contract from `plans/CENTRAL_LAYERS_PROMPT.md:376-384`, with nil URLs honoring `plans/CENTRAL_LAYERS_PROMPT.md:71`.
- [ ] Logger, paste routing, menu bar, onboarding, settings, history, pill accessibility, and build-metadata consumers listed in Observed current spread no longer own hard-coded `"Seshat"` or `"com.nitkrar.seshat"` literals once their Stage 2 step lands.
- [ ] The future About-tab header/version/link rows can be built exactly as required by `plans/App UI design/Seshat Q4_Q5 Handoff Spec.md:34-43`, `plans/App UI design/Seshat UI Polish & Unified Window Implementation.md:68-76`, and `plans/CENTRAL_LAYERS_PROMPT.md:387-388`.
- [ ] No files outside "Observed current spread" modified (unless in explicit collision list).
- [ ] No `Color(hex:` outside `Theme/*` (house rule).
- [ ] No direct `UserDefaults.standard.*` — typed resolvers only.
- [ ] No `type` / `kind` / `intent` column added to SQLite.
- [ ] `swift build --build-tests` green (main session).
- [ ] All acceptance tests named in plan pass.

## Backlog tickets authored
- None.

## Inter-layer dependencies
- **Requires**: Layer 1 for the TCC deep-link caller cleanup in Stage 2.8 / Stage 3.1.
- **Blocks**: None of Layers 1-8. This layer instead unblocks the external Phase 2 About-tab rendering contract after Stage 1 is available.

## Commit style
`trunk: layer 9.M: <verb-led subject>`. Test + fix in same commit.

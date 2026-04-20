# Layer 9 Stage 2 — Code Review

## Verdict
REQUEST-CHANGES. `1c350be` migrates most visible `AppBrand.displayName` consumers, but Stage 2.1, Stage 2.5, and Stage 2.9 are still incomplete, and the commit also edits one out-of-plan consumer.

## Scope summary
`1c350be` changes 12 files / 74 lines (`43` insertions, `31` deletions). It swaps raw `Seshat` display literals to `AppBrand.displayName` in the menu bar, onboarding, settings, history, pill accessibility labels, and the `BuildInfo` display string; it also swaps local bundle-ID constants to `AppBrand.bundleIdentifier` in `PasteInjector` and `ClipboardBatchOutput`.

## Findings
1. major — `Sources/SeshatCore/Logger.swift:5` — Stage 2.1 did not land. `SeshatLogger.subsystem` still hard-codes `"com.nitkrar.seshat"` instead of delegating to `AppBrand.logSubsystem`, so logs/signposts still depend on a second identity source even after Stage 2 is marked complete. Suggested action: replace the raw literal with `AppBrand.logSubsystem` and keep `Tests/SeshatCoreTests/SeshatLoggerTests.swift:8` asserting the effective value.
2. major — `Sources/SeshatAppKit/MenuBar/BuildInfo.swift:12` — Stage 2.9 is only half-done. `BuildInfo` still owns `CFBundleShortVersionString` parsing locally and never delegates version/build-number ownership to `AppBrand.version` / `AppBrand.buildNumber`, so the future About header contract is still blocked on a second brand helper. Suggested action: make `BuildInfo` delegate version/build display inputs to `AppBrand` (or explicitly mark it as a temporary Stage 3 bridge and update `Tests/SeshatAppKitTests/BuildInfoTests.swift:5-40` accordingly).
3. minor — `Sources/SeshatCore/BaseDirectoryMigrator.swift:30` — Stage 2.5 missed a remaining user-facing `Seshat` literal in the migration failure reason shown from Settings > Advanced. A future rebrand would still surface the old app name here. Suggested action: compose the failure reason from `AppBrand.displayName`.
4. nit — `Sources/SeshatAppKit/Output/ClipboardBatchOutput.swift:30` — This commit edits `ClipboardBatchOutput`, which is outside the Layer 9 plan's "Observed current spread" and not called out in the Stage 2 file list. The change is mechanically safe, but it is still a scope divergence from the approved consumer set. Suggested action: either update the Layer 9 plan/collision list to include this consumer or keep this swap in a separate follow-up.
5. minor — `Tests/SeshatAppKitTests/ManualOnboardingVerification.md:12`, `Tests/SeshatAppKitTests/ManualOnboardingVerification.md:19`, `Tests/SeshatAppKitTests/ManualSettingsVerification.md:3`, `Tests/SeshatAppKitTests/ManualNotesVerification.md:3`, `Tests/SeshatAppKitTests/ManualStatusItemVerification.md:11`, `Tests/SeshatAppKitTests/ManualPillOverlayVerification.md:111` — The UI-verification runbooks were not updated with the new centralized brand-copy checks required by Stage 2. Three runbooks still spell out fixed `Seshat` expectations, and the status-item / pill runbooks still stop short of the new label/accessibility checks called for in the plan. Suggested action: update the runbooks to verify `AppBrand.displayName`-backed copy and add the missing status-item / pill accessibility entries.

## Residual literal audit
Full-tree grep at `1c350be` still returns `2708` `Seshat` hits and `41` `com.nitkrar.seshat` hits; most are plans/docs/history. Implementation-relevant residuals are classified below.

### `Seshat`
- `Sources/SeshatCore/AppBrand/AppBrand.swift:4` — legitimate. Source-of-truth display-name literal.
- `Sources/SeshatCore/BaseDirectoryMigrator.swift:30` — missed-swap. Remaining user-facing runtime copy.
- `Package.swift:6`, `Package.swift:12`, `Package.swift:16`, `Package.swift:20`, `Package.swift:24`, `Package.swift:28`, `Package.swift:32`, `Package.swift:48`, `Package.swift:55`, `Package.swift:62`, `Package.swift:70`, `Package.swift:79`, `Package.swift:86`, `Package.swift:99`, `Package.swift:106`, `Package.swift:114`, `Package.swift:122`, `Package.swift:130` — legitimate. Package / target / product names are explicitly out of scope.
- `Sources/SeshatCore/Config.swift:95`, `Sources/SeshatCore/Config.swift:107`, `Sources/SeshatCore/Storage/AppConfig.swift:48`, `Sources/SeshatCore/Storage/AppConfig.swift:61` — legitimate. App-support directory names / storage layout, not Stage 2 display-copy sites.
- `Sources/SeshatCore/Metrics/MetricsModels.swift:88`, `Sources/SeshatCore/OnboardingState.swift:19`, `Sources/SeshatAppKit/MenuBar/BuildInfo.swift:17` — legitimate. Internal notification/defaults/build-info keys.
- `Tests/SeshatAppKitTests/BuildInfoTests.swift:13`, `Tests/SeshatAppKitTests/BuildInfoTests.swift:21`, `Tests/SeshatAppKitTests/MenuBar/StatusItemMenuModelTests.swift:25`, `Tests/SeshatCoreTests/AppBrand/AppBrandTests.swift:6`, `Tests/SeshatCoreTests/SeshatLoggerTests.swift:8` — legitimate. Test fixtures asserting the current effective runtime value.
- `Tests/SeshatAppKitTests/ManualOnboardingVerification.md:12`, `Tests/SeshatAppKitTests/ManualOnboardingVerification.md:19`, `Tests/SeshatAppKitTests/ManualSettingsVerification.md:3`, `Tests/SeshatAppKitTests/ManualSettingsVerification.md:17`, `Tests/SeshatAppKitTests/ManualSettingsVerification.md:23`, `Tests/SeshatAppKitTests/ManualNotesVerification.md:3`, `Tests/SeshatAppKitTests/ManualNotesVerification.md:8` — missed-swap. Stale manual-verification expectations still spell out `Seshat` instead of checking the centralized display name.
- `plans/**`, `BACKLOG.md`, `PROPOSAL.md`, and other design/review docs — legitimate. Historical documentation references dominate the raw grep count and are not Layer 9 consumer sites.

### `com.nitkrar.seshat`
- `Sources/SeshatCore/AppBrand/AppBrand.swift:5` — legitimate. Source-of-truth bundle identifier literal.
- `Sources/SeshatCore/Logger.swift:5` — missed-swap. Stage 2.1 should route through `AppBrand.logSubsystem`.
- `scripts/package.sh:103` — legitimate. Packaging-time bundle-ID configuration.
- `Sources/SeshatCore/Config.swift:70`, `Sources/SeshatAppKit/Hotkeys/GlobalHotkeyMonitor.swift:108` — legitimate. Comments / examples using the real bundle domain.
- `Tests/SeshatAppKitTests/Output/ClipboardBatchOutputTests.swift:115`, `Tests/SeshatAppKitTests/PasteInjectorTests.swift:120`, `Tests/SeshatCoreTests/AppBrand/AppBrandTests.swift:7`, `Tests/SeshatCoreTests/AppBrand/AppBrandTests.swift:8`, `Tests/SeshatCoreTests/SeshatLoggerTests.swift:8`, `Tests/SeshatAppKitTests/ManualPillOverlayVerification.md:33`, `Tests/SeshatAppKitTests/ManualPillOverlayVerification.md:45`, `Tests/SeshatAppKitTests/ManualPillOverlayVerification.md:55`, `Tests/SeshatAppKitTests/ManualPillOverlayVerification.md:67`, `Tests/SeshatAppKitTests/ManualPillOverlayVerification.md:92`, `Tests/SeshatCoreTests/ManualConfigVerification.md:4`, `Tests/SeshatCoreTests/ManualConfigVerification.md:7`, `Tests/SeshatTranscriptionTests/ManualTranscriptionVerification.md:30` — legitimate. Tests and manual commands that intentionally use the current bundle domain.
- `plans/**` and other docs — legitimate. Historical / explanatory references outside the consumer swap surface.

## Cross-layer check
No cross-layer edits were identified. `1c350be` stays within Layer 9 consumer sites plus one extra same-layer consumer (`Sources/SeshatAppKit/Output/ClipboardBatchOutput.swift:30`). I did not find any new Layer 1 deep-link cleanup, new About UI, or other stepping into unrelated layers.

About tab / link rows status: no About-tab or brand-link-row implementation exists in `Sources` at `1c350be`; `git grep -n -E 'AboutTab|About.*View|websiteURL|privacyURL|termsURL' 1c350be -- Sources Tests` only hits `Sources/SeshatCore/AppBrand/AppBrand.swift:7-9` and `Tests/SeshatCoreTests/AppBrand/AppBrandTests.swift:12-14`. That is acceptable for Stage 2, but Finding #2 means the future About header/version surface is not fully prepared yet.

## Summary
Findings: `0 blocker`, `2 major`, `2 minor`, `1 nit`.

Recommended next action: fix the `Logger.swift`, `BuildInfo.swift`, and `BaseDirectoryMigrator.swift` misses first; then either revert or explicitly plan the `ClipboardBatchOutput` scope expansion and update the manual runbooks before re-requesting review.

## Verdict

APPROVED-WITH-FOLLOWUPS

## Summary

Commit `5b6e023` migrates the five compiled Layer 3 settings resolvers to `Preference<Value>`, renames their live `UserDefaults` keys away from the `Seshat*` prefix, and also lands the gated `BaseDirectoryPath` rename/centralization work in `SeshatConfig` and `AppConfig` (`Sources/SeshatCore/SeshatPasteMode.swift:8-28`, `Sources/SeshatCore/WaveformDecayMode.swift:18-47`, `Sources/SeshatCore/PasteRestoreDelay.swift:8-47`, `Sources/SeshatCore/HotkeyPreference.swift:9-45`, `Sources/SeshatAppKit/Overlay/PillVisibilityMode.swift:29-56`, `Sources/SeshatCore/Config.swift:13-103`, `Sources/SeshatCore/Storage/AppConfig.swift:12-57`). The defaults and round-trip behavior remain intact for the migrated enum, scalar, struct, and base-directory cases, and the touched consumer/tests/manual-runbook edits are narrowly aligned to that swap rather than broad churn (`Tests/SeshatCoreTests/PasteModeTests.swift:13-45`, `Tests/SeshatCoreTests/WaveformDecayModeTests.swift:24-67`, `Tests/SeshatCoreTests/PasteRestoreDelayTests.swift:13-57`, `Tests/SeshatCoreTests/HotkeyPreferenceTests.swift:14-67`, `Tests/SeshatAppKitTests/PillVisibilityModeTests.swift:38-88`, `Tests/SeshatCoreTests/SeshatConfigTests.swift:8-80`, `Tests/SeshatCoreTests/Storage/AppConfigTests.swift:8-31`). `WindowTint` and `PillAppearance` are correctly left as no-ops because the current compiled theme source is still token-only and defines no typed theme resolvers (`Sources/SeshatAppKit/Theme/SeshatTheme.swift:1-220`; `plans/central/LAYER_3_settings.md:25-26,102-103,141`). The follow-up is architectural rather than behavioral: `BaseDirectoryPath` now has two owners, with a `Preference` on `SeshatConfig` and a duplicate inline key constant on `AppConfig`, which violates the Layer 3 duplicate-owner audit and leaves Layer 2/3 ownership fuzzy (`Sources/SeshatCore/Config.swift:40-43`, `Sources/SeshatCore/Storage/AppConfig.swift:12-37,56-57`, `plans/central/LAYER_3_settings.md:117-120`).

## Resolver Migration Checklist

| Resolver | File:Line | Key (old -> new) | Default preserved | Round-trip preserved | Notes |
|---|---|---|---|---|---|
| `PasteMode` | `Sources/SeshatCore/SeshatPasteMode.swift:5-24`; `Tests/SeshatCoreTests/PasteModeTests.swift:13-45` | `SeshatPasteMode` -> `PasteMode` | Yes | Yes | Type rename landed and consumers now read `PasteMode` (`Sources/SeshatAppKit/Settings/GeneralTab.swift:105-113,153-176,205-207`, `Sources/SeshatAppKit/Paste/PasteInjector.swift:29-45`, `Sources/SeshatAppKit/Output/ClipboardBatchOutput.swift:106-117`). Transitional alias remains at `Sources/SeshatCore/SeshatPasteMode.swift:28` and is a Stage 3 cleanup item per `plans/central/LAYER_3_settings.md:109-113`. |
| `WaveformDecayMode` | `Sources/SeshatCore/WaveformDecayMode.swift:15-47`; `Tests/SeshatCoreTests/WaveformDecayModeTests.swift:24-67` | `SeshatWaveformDecayMode` -> `WaveformDecayMode` | Yes | Yes | Persistence plumbing moved to `Preference<Self>` while `durationSeconds` / `linearLevel` stayed untouched at `Sources/SeshatCore/WaveformDecayMode.swift:25-72`, matching the plan's "plumbing only" requirement (`plans/central/LAYER_3_settings.md:45,130`). |
| `PasteRestoreDelay` | `Sources/SeshatCore/PasteRestoreDelay.swift:5-47`; `Tests/SeshatCoreTests/PasteRestoreDelayTests.swift:13-57` | `SeshatPasteRestoreDelaySeconds` -> `PasteRestoreDelaySeconds` | Yes | Yes | The wrapper stores the scalar seconds value through `storedSeconds`, while clamp/sanitize logic stays on the semantic type at `Sources/SeshatCore/PasteRestoreDelay.swift:27-47`, as required by `plans/central/LAYER_3_settings.md:22,45,55,131`. |
| `PillVisibilityMode` | `Sources/SeshatAppKit/Overlay/PillVisibilityMode.swift:25-56`; `Tests/SeshatAppKitTests/PillVisibilityModeTests.swift:38-88` | `SeshatPillVisibilityMode` -> `PillVisibilityMode` | Yes | Yes | The resolver migrated in place and still preserves `.autoShow` fallback; the visibility invariant remains in `GeneralTabViewModel.applyVisibilityConfig` at `Sources/SeshatAppKit/Settings/GeneralTab.swift:185-197`, matching `plans/central/LAYER_3_settings.md:47,132`. |
| `HotkeyPreference` | `Sources/SeshatCore/HotkeyPreference.swift:6-45`; `Tests/SeshatCoreTests/HotkeyPreferenceTests.swift:14-67` | `SeshatRecordingHotkey` -> `RecordingHotkey` | Yes | Yes | Struct storage now routes through `Preference<HotkeyPreference>` but still rejects unsupported decoded payloads via `isSupported` at `Sources/SeshatCore/HotkeyPreference.swift:35-41,51-53`, preserving pre-swap behavior. |
| `WindowTint` | `plans/central/LAYER_3_settings.md:25,102,141`; `Sources/SeshatAppKit/Theme/SeshatTheme.swift:1-220` | `SeshatWindowTint` -> `WindowTint` | No-op | No-op | Correct no-op. The Layer 3 plan marks this conditional/reference-only, and the current compiled theme source contains no `WindowTint` resolver or persisted setting surface. |
| `PillAppearance` | `plans/central/LAYER_3_settings.md:26,103,141`; `Sources/SeshatAppKit/Theme/SeshatTheme.swift:1-220` | `SeshatPillAppearance` -> `PillAppearance` | No-op | No-op | Correct no-op. As with `WindowTint`, there is still no compiled `PillAppearance` resolver to migrate in `Sources/`. |

`BaseDirectoryPath` is not one of the seven resolver rows above, but the gated Stage `3.7` work did land and is assessed under cross-layer concerns because the plan treats it as a storage-owned candidate rather than a compiled Layer 3 resolver (`plans/central/LAYER_3_settings.md:10,30-33,58,101,134`).

## Findings by Severity

### Critical

None.

### Major

None.

### Minor

1. `BaseDirectoryPath` still has two owners after the `3.7` migration.

   File: `Sources/SeshatCore/Config.swift:40-43`, `Sources/SeshatCore/Storage/AppConfig.swift:12-37,56-57`, `plans/central/LAYER_3_settings.md:117-120`, `plans/central/LAYER_2_storage.md:45-46,65,192`

   What's wrong: the new `Preference<String?>` lives on `SeshatConfig.baseDirectoryPathPreference`, but `AppConfig` still carries a separate inline `baseDirectoryUserDefaultsKey = "BaseDirectoryPath"` constant and remains the storage layer's advertised "canonical owner of override plumbing." That violates the Layer 3 duplicate-owner audit ("Do not leave both an inline `userDefaultsKey` and a `Preference` side by side after `3.7`") and leaves the Layer 2/3 ownership boundary internally inconsistent.

   Suggested fix: make a single source of truth for the base-directory override key. Either move the `Preference<String?>` onto `AppConfig` and have `SeshatConfig` forward to it, or derive `AppConfig.baseDirectoryUserDefaultsKey` from the preference instead of keeping a second literal owner.

### Nit

1. Stage 2 landed as one aggregate commit instead of the plan's per-step commit cadence.

   File: `plans/central/LAYER_3_settings.md:92-103`; commit `5b6e023`

   What's wrong: the plan says "Each Stage 2 step is one commit," but `5b6e023` bundles the `3.2` through `3.7` work into a single landing. That reduces the revertability the plan was aiming for.

   Suggested fix: keep the remaining Stage `3.10` cleanup separate, and if strict plan cadence still matters for adjacent layers, preserve one-step-per-commit on those follow-on swaps.

## Cross-Layer Concerns

The `Config.swift` / `AppConfig.swift` spillover is expected, not accidental: Layer 3 explicitly gates `BaseDirectoryPath` on Layer 2 (`plans/central/LAYER_3_settings.md:10,101,134`), and Layer 2 explicitly says the `SeshatBaseDirectoryPath` -> `BaseDirectoryPath` rename belongs to Layer 3 rather than Layer 2 (`plans/central/LAYER_2_storage.md:95`). The commit also leaves the `testingBaseDirectoryOverride` seam intact, so it does not violate Layer 3's "do not touch that seam" rule in any behavioral way (`Sources/SeshatCore/Config.swift:18-27,76,94-104`; `plans/CENTRAL_LAYERS_PROMPT.md:216-218`; `plans/central/LAYER_3_settings.md:1,32,134`).

The remaining concern is ownership cleanup, not correctness: Layer 2 still describes `AppConfig` as the canonical owner of override plumbing (`plans/central/LAYER_2_storage.md:45-46,65,192`), while the actual preference instance now lives on `SeshatConfig` (`Sources/SeshatCore/Config.swift:40-43`). That is acceptable spillover for this commit, but it should be normalized before the eventual `SeshatConfig` shim deletion.

No Layer 4/AppStore or other neighbour-layer runtime code was touched in `5b6e023`; the spillover is confined to Layer 2 storage/config files plus their tests/runbooks (`git show --name-only 5b6e023` read in full; touched production files are limited to `Sources/SeshatCore/Config.swift`, `Sources/SeshatCore/Storage/AppConfig.swift`, and the five Layer 3 resolver/consumer files listed above).

## Test Coverage Gaps

Existing coverage is appropriately scoped for this swap. The commit updates resolver tests to assert the new key names and `Preference`-backed round-trips (`Tests/SeshatCoreTests/PasteModeTests.swift:13-45`, `Tests/SeshatCoreTests/WaveformDecayModeTests.swift:24-67`, `Tests/SeshatCoreTests/PasteRestoreDelayTests.swift:13-57`, `Tests/SeshatCoreTests/HotkeyPreferenceTests.swift:14-67`, `Tests/SeshatAppKitTests/PillVisibilityModeTests.swift:38-88`), keeps consumer regression tests aligned for paste routing and restore-delay reads (`Tests/SeshatAppKitTests/PasteInjectorTests.swift:75-202`, `Tests/SeshatAppKitTests/Output/ClipboardBatchOutputTests.swift:77-266`, `Tests/SeshatAppKitTests/Settings/GeneralTabViewModelTests.swift:67-84`, `Tests/SeshatAppKitTests/Settings/HotkeyRecorderTests.swift:16-42`), and updates the packaged-app/manual runbooks to the new keys (`Tests/SeshatCoreTests/ManualConfigVerification.md:1-10`, `Tests/SeshatAppKitTests/ManualPillOverlayVerification.md:29-97`). Those are legitimate behavior-alignment changes, not compile-only churn.

What is still unpinned is the "no migration means legacy keys are ignored" contract. The implementation now reads only the new keys by construction (`Sources/SeshatCore/SeshatPasteMode.swift:19-24`, `Sources/SeshatCore/WaveformDecayMode.swift:41-46`, `Sources/SeshatCore/PasteRestoreDelay.swift:27-35`, `Sources/SeshatCore/HotkeyPreference.swift:35-44`, `Sources/SeshatAppKit/Overlay/PillVisibilityMode.swift:48-56`, `Sources/SeshatCore/Config.swift:102-103`), but no test explicitly proves that old `Seshat*` keys are ignored after the rename. That is a coverage gap, not a correctness defect, because the plan explicitly chose no migration (`plans/CENTRAL_LAYERS_PROMPT.md:213`; `plans/central/LAYER_3_settings.md:1,20-32`).

`WindowTint` / `PillAppearance` appropriately have no Stage 2 coverage added here. The compiled theme source is still token-only (`Sources/SeshatAppKit/Theme/SeshatTheme.swift:1-220`; `Tests/SeshatAppKitTests/Theme/SeshatThemeTests.swift:1-220`), and Layer 3 marked those two rows as conditional/no-op until a future theme source actually defines them (`plans/central/LAYER_3_settings.md:25-26,102-103,135,141`).

## Residual Seshat* Keys Audit

- `SeshatOnboardingCompleted` - intentionally deferred per plan. Live references remain in `Sources/SeshatCore/OnboardingState.swift:5,19,34`, `Sources/SeshatAppKit/Onboarding/OnboardingWindowController.swift:95`, `Sources/SeshatAppKit/Composition/SeshatAppMain.swift:69,227`, `Sources/SeshatAppKit/MenuBar/StatusItemController.swift:49`, and `Tests/SeshatAppKitTests/OnboardingViewModelTests.swift:62,72,82,109`. Classification: `(a) intentionally deferred per plan`, because Layer 3 explicitly keeps onboarding completion under Layer 1 ownership (`plans/central/LAYER_3_settings.md:122,136`; `plans/central/LAYER_1_permissions.md:21-22,57,170,209`).
- `SeshatBaseDirectoryPath` - no live `Sources/` or `Tests/` reference remains after `5b6e023`. Residual mentions are historical/spec markdown only, for example `plans/SPEC_model_registry_and_base_dir.md:111,153,184,190` and `plans/PLAN_PHASES.md:110-123`. Classification: `(c) unrelated/stale documentation`, not a missed live migration.
- `SeshatPasteMode`, `SeshatWaveformDecayMode`, `SeshatPasteRestoreDelaySeconds`, `SeshatPillVisibilityMode`, `SeshatRecordingHotkey`, `SeshatWindowTint`, `SeshatPillAppearance`, and `SeshatActiveModelDescriptor` - no live `Sources/` or `Tests/` UserDefaults key references remain. Residual mentions are confined to historical plan/review docs such as `plans/PHASE_0_rename.md:9-15,43-49,80`, `plans/PLAN_PHASES.md:293`, `plans/central/LAYER_2_storage.md:61,95`, `plans/central/LAYER_3_settings.md:20-26,32,142`, `plans/central/LAYER_6_model_selection.md:43,230`, and `plans/central/reviews/LAYER_5_review.md:25,35`. Classification: `(c) unrelated/stale documentation`, not missed runtime migrations.

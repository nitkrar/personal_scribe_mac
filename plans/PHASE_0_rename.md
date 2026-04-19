# Phase 0 — Rename Pass

## Critical discipline
> Do NOT diverge from this plan or the Manus mockups. Silent divergence is the cardinal sin. To deviate, surface the proposed divergence in a comment in the commit message AND in the hand-off report; wait for main-session confirmation. Paraphrasing the contract is divergence. Renaming variables the plan specifies is divergence. Choosing a different animation curve than the mockup implies is divergence.

## Prerequisites
- Execute Phase 0 before any Phase 1 or Phase 2 work. Later plans assume the post-rename symbols and post-rename UserDefaults keys already exist.
- Confirm the current key inventory before editing. On trunk, the only persisted `Seshat*` keys in `Sources/` are:
  - `Sources/SeshatCore/Config.swift:78` — `SeshatBaseDirectoryPath`
  - `Sources/SeshatCore/OnboardingState.swift:19` — `SeshatOnboardingCompleted`
  - `Sources/SeshatCore/SeshatPasteMode.swift:13` — `SeshatPasteMode`
  - `Sources/SeshatCore/PasteRestoreDelay.swift:12` — `SeshatPasteRestoreDelaySeconds`
  - `Sources/SeshatCore/HotkeyPreference.swift:14` — `SeshatRecordingHotkey`
  - `Sources/SeshatCore/WaveformDecayMode.swift:35` — `SeshatWaveformDecayMode`
  - `Sources/SeshatAppKit/Overlay/PillVisibilityMode.swift:36` — `SeshatPillVisibilityMode`
- Confirm the rename-now production symbol inventory before editing:
  - `Sources/SeshatCore/Config.swift:3-107` — `SeshatConfig` -> `Config`
  - `Sources/SeshatCore/Errors.swift:3-80` — `SeshatError` -> `AppError`
  - `Sources/SeshatCore/Logger.swift:4-52` — `SeshatLogger` -> `AppLogger`; `SeshatLogCategory` -> `AppLogCategory`
  - `Sources/SeshatCore/SeshatPasteMode.swift:8-28` — `SeshatPasteMode` -> `PasteMode`
  - `Sources/SeshatAppKit/Theme/SeshatTheme.swift:12-259` — `SeshatTheme` -> `Theme`
  - `Sources/SeshatAppKit/Components/SeshatLogoView.swift:16-37` — `SeshatLogoView` -> `LogoView`
  - `Sources/SeshatAppKit/Composition/SeshatAppMain.swift:7-259` — `SeshatAppMain` -> `AppMain`
  - `Sources/SeshatCore/OnboardingState.swift:34` — delete the `SeshatOnboardingCompleted` alias instead of inventing a second alias.
- Confirm the explicit keeps before editing:
  - Keep `Sources/SeshatAppKit/SeshatApp.swift:6-42` unchanged in Phase 0. The file comment documents why `App` is a bad post-rename spelling here: the shell deliberately does not conform to `SwiftUI.App`, and the bare name `App` collides with that protocol boundary.
  - Keep the module-marker enums and their compile tests unchanged because target-name renaming is deferred: `Package.swift:11-34,47-97`, `Sources/SeshatCore/SeshatCoreModule.swift:1`, `Sources/SeshatSession/SeshatSessionModule.swift:1`, `Sources/SeshatTranscription/SeshatTranscriptionModule.swift:1`, `Sources/SeshatTestSupport/SeshatTestSupportModule.swift:1`, `Sources/SeshatAppKit/Permissions/SeshatAppKitPermissionsModule.swift:1`.
- Freeze the repo-wide Phase 0.3 call-site inventory before the first call-site commit. The exhaustive surface is the output of:

```text
rg -l '\bSeshatConfig\b|\bSeshatPasteMode\b|\bSeshatOnboardingCompleted\b|\bSeshatTheme\b|\bSeshatLogoView\b|\bSeshatAppMain\b|\bSeshatError\b|\bSeshatLogger\b|\bSeshatLogCategory\b' Sources Tests | sort
```

## Locked design decisions applicable to this phase
- Locked decision `#7`: drop the `Seshat` prefix from UserDefaults keys and from type/file names where removing the prefix does not create a collision. `SeshatError` becomes `AppError`; `SeshatLogger` becomes `AppLogger`. Keep SPM target names unchanged.
- Locked decision `#10`: no UserDefaults migration is required. The old prefixed keys must stop being read immediately.
- Locked decision `#3`: Phase 2 will replace the theme in a single big-bang commit. Phase 0 only renames the theme file/type; it does not change theme content.

## Step 0.1 — Rename persisted UserDefaults keys
> Do NOT diverge from this plan or the Manus mockups. Silent divergence is the cardinal sin. To deviate, surface the proposed divergence in a comment in the commit message AND in the hand-off report; wait for main-session confirmation. Paraphrasing the contract is divergence. Renaming variables the plan specifies is divergence. Choosing a different animation curve than the mockup implies is divergence.

### Files touched (exhaustive) — path:line-range — what changes
- `Sources/SeshatCore/Config.swift:13-16,30-40,67-79,96-103` — rename `SeshatBaseDirectoryPath` to `BaseDirectoryPath` in docs, resolver, setter, and cleanup comments.
- `Sources/SeshatCore/OnboardingState.swift:3-31` — rename `SeshatOnboardingCompleted` to `OnboardingCompleted` in the stored-key docs and resolver/persist constant.
- `Sources/SeshatCore/SeshatPasteMode.swift:3-27` — rename `SeshatPasteMode` to `PasteMode` at the persisted-key constant and docs only; type/file rename lands in Step 0.2.
- `Sources/SeshatCore/PasteRestoreDelay.swift:3-36` — rename `SeshatPasteRestoreDelaySeconds` to `PasteRestoreDelaySeconds`.
- `Sources/SeshatCore/HotkeyPreference.swift:4-46` — rename `SeshatRecordingHotkey` to `RecordingHotkey`.
- `Sources/SeshatCore/WaveformDecayMode.swift:15-49` — rename `SeshatWaveformDecayMode` to `WaveformDecayMode`.
- `Sources/SeshatAppKit/Overlay/PillVisibilityMode.swift:24-57` — rename `SeshatPillVisibilityMode` to `PillVisibilityMode`.
- `Tests/SeshatCoreTests/SeshatConfigTests.swift:8-74` — update hard-coded cleanup literals and add failing-first assertions that only the new key is honored.
- `Tests/SeshatCoreTests/TranscriptStoreTests.swift:158-177` — rename the hard-coded cleanup literal for the base-directory key.
- `Tests/SeshatCoreTests/SQLiteTranscriptStoreTests.swift:201-224` — rename the hard-coded cleanup literal for the base-directory key.
- `Tests/SeshatAppKitTests/Notes/TranscriptReaderTests.swift:60-77` — rename the hard-coded cleanup literal for the base-directory key.
- `Tests/SeshatCoreTests/PasteModeTests.swift:13-40` — update the persistence-key assertions to the new unprefixed key.
- `Tests/SeshatCoreTests/PasteRestoreDelayTests.swift:13-52` — update the persistence-key assertions to the new unprefixed key.
- `Tests/SeshatCoreTests/HotkeyPreferenceTests.swift:14-48` — update the persistence-key assertions to the new unprefixed key.
- `Tests/SeshatCoreTests/WaveformDecayModeTests.swift:33-64` — update the persistence-key assertions to the new unprefixed key.
- `Tests/SeshatAppKitTests/PillVisibilityModeTests.swift:35-84` — update the persistence-key assertions to the new unprefixed key.
- `Tests/SeshatCoreTests/OnboardingStateTests.swift:6-27` — update the persistence-key assertions to the new unprefixed key.

### Scope — IN
- Rename the seven persisted key strings listed in `Prerequisites` and nowhere else.
- Add failing-first tests proving the new unprefixed keys work and the old `Seshat*` keys are ignored.
- Update comments and docs in the touched files so they state the new key names exactly.
- Keep the resolver APIs, default values, and persistence semantics unchanged apart from the key spelling.

### Scope — OUT (with backlog ticket paths where applicable)
- No type/file renames in this step. That is Step 0.2.
- No compatibility read path for the old keys. Locked decision `#10` forbids migration shims.
- Do not add any Phase 2 keys (`WindowTint`, `PillAppearance`, `LaunchAtLogin`, `ShowInDock`) here; those values do not exist on trunk yet.

### Acceptance tests — Tests/... — test name + what it asserts + mockup/doc clause it ties to
- `Tests/SeshatCoreTests/SeshatConfigTests.swift` — `testUserDefaultsOverrideUsesBaseDirectoryPathAndIgnoresLegacySeshatBaseDirectoryPath`; asserts only `BaseDirectoryPath` is honored after the rename; ties to `Sources/SeshatCore/Config.swift:13-16,78` and locked decision `#10`.
- `Tests/SeshatCoreTests/PasteModeTests.swift` — `testUserDefaultsKeyDropsSeshatPrefix`; asserts the persisted key spelling is `PasteMode`; ties to `Sources/SeshatCore/SeshatPasteMode.swift:5-13`.
- `Tests/SeshatCoreTests/HotkeyPreferenceTests.swift` — `testUserDefaultsKeyDropsSeshatPrefix`; asserts the persisted hotkey key is `RecordingHotkey`; ties to `Sources/SeshatCore/HotkeyPreference.swift:4-15`.
- `Tests/SeshatCoreTests/WaveformDecayModeTests.swift` — `testUserDefaultsKeyDropsSeshatPrefix`; asserts the persisted decay key is `WaveformDecayMode`; ties to `Sources/SeshatCore/WaveformDecayMode.swift:15-35`.
- `Tests/SeshatAppKitTests/PillVisibilityModeTests.swift` — `testUserDefaultsKeyDropsSeshatPrefix`; asserts the persisted pill-visibility key is `PillVisibilityMode`; ties to `Sources/SeshatAppKit/Overlay/PillVisibilityMode.swift:24-36`.

### Validation checklist (implementer ticks box-by-box in hand-off)
- [ ] The seven-key mapping is exact: `SeshatBaseDirectoryPath -> BaseDirectoryPath`, `SeshatOnboardingCompleted -> OnboardingCompleted`, `SeshatPasteMode -> PasteMode`, `SeshatPasteRestoreDelaySeconds -> PasteRestoreDelaySeconds`, `SeshatRecordingHotkey -> RecordingHotkey`, `SeshatWaveformDecayMode -> WaveformDecayMode`, `SeshatPillVisibilityMode -> PillVisibilityMode`.
- [ ] `rg -n '"Seshat(BaseDirectoryPath|OnboardingCompleted|PasteMode|PasteRestoreDelaySeconds|RecordingHotkey|WaveformDecayMode|PillVisibilityMode)"' Sources Tests` returns zero hits before the step closes.
- [ ] Locked decision `#10` is honored: there is no fallback read, no migration code, and no “legacy key” branch anywhere in `Sources/`.
- [ ] Diff against this step shows no silent divergence; every modified file is listed above, and any proposed deviation is recorded in the commit message comment and hand-off report.
- [ ] No `Color(hex:` outside `Theme/*` (hard rule — long-standing).
- [ ] No `UserDefaults.standard.*` direct reads — typed resolvers only.
- [ ] No `type`/`kind`/`intent` field added (hard rule — Phase 3 design lock: `project_phase3_notes_equals_history.md`).
- [ ] `swift build --build-tests` green from the main-repo path.
- [ ] No files outside `Files touched` modified.

### Commit style — `trunk: phase 0.1: <verb-led subject>`. Test + fix in same commit.
`trunk: phase 0.1: rename persisted defaults keys`

### Hand-off report template
```md
Phase 0.1 hand-off
- Commit: <sha> trunk: phase 0.1: rename persisted defaults keys
- Tests added/updated: <list>
- Verification commands: <list>
- Exact key mapping shipped: <paste the seven-key mapping>
- Deviations from plan: none | <required explicit note>
- Follow-ups / blockers: none | <list>
```

## Step 0.2 — Rename production symbols and prefixed files with `git mv`
> Do NOT diverge from this plan or the Manus mockups. Silent divergence is the cardinal sin. To deviate, surface the proposed divergence in a comment in the commit message AND in the hand-off report; wait for main-session confirmation. Paraphrasing the contract is divergence. Renaming variables the plan specifies is divergence. Choosing a different animation curve than the mockup implies is divergence.

### Files touched (exhaustive) — path:line-range — what changes
- `Sources/SeshatCore/Config.swift:1-107` — rename the top-level type from `SeshatConfig` to `Config`; the file name already matches the post-rename spelling and must not move.
- `Sources/SeshatCore/Errors.swift:1-80` — rename `SeshatError` to `AppError`.
- `Sources/SeshatCore/Logger.swift:1-52` — rename `SeshatLogger` to `AppLogger` and `SeshatLogCategory` to `AppLogCategory`.
- `Sources/SeshatCore/SeshatPasteMode.swift:1-28 -> Sources/SeshatCore/PasteMode.swift` — use `git mv`, then rename the enum from `SeshatPasteMode` to `PasteMode`.
- `Sources/SeshatAppKit/Theme/SeshatTheme.swift:1-277 -> Sources/SeshatAppKit/Theme/Theme.swift` — use `git mv`, then rename `SeshatTheme` to `Theme` only; do not change theme content in this step.
- `Sources/SeshatAppKit/Components/SeshatLogoView.swift:1-135 -> Sources/SeshatAppKit/Components/LogoView.swift` — use `git mv`, then rename `SeshatLogoView` to `LogoView`.
- `Sources/SeshatAppKit/Composition/SeshatAppMain.swift:1-259 -> Sources/SeshatAppKit/Composition/AppMain.swift` — use `git mv`, then rename `SeshatAppMain` to `AppMain`.
- `Sources/SeshatCore/OnboardingState.swift:34` — delete the `SeshatOnboardingCompleted` alias.
- `Tests/SeshatCoreTests/SeshatConfigTests.swift:1-75 -> Tests/SeshatCoreTests/ConfigTests.swift` — use `git mv`, rename the XCTestCase type to `ConfigTests`.
- `Tests/SeshatCoreTests/SeshatConfigScaffoldingTests.swift:1-9 -> Tests/SeshatCoreTests/ConfigScaffoldingTests.swift` — use `git mv`, rename the XCTestCase type to `ConfigScaffoldingTests`.
- `Tests/SeshatCoreTests/SeshatErrorTests.swift:1-63 -> Tests/SeshatCoreTests/AppErrorTests.swift` — use `git mv`, rename the XCTestCase type to `AppErrorTests`.
- `Tests/SeshatCoreTests/SeshatErrorScaffoldingTests.swift:1-9 -> Tests/SeshatCoreTests/AppErrorScaffoldingTests.swift` — use `git mv`, rename the XCTestCase type to `AppErrorScaffoldingTests`.
- `Tests/SeshatCoreTests/SeshatLoggerTests.swift:1-16 -> Tests/SeshatCoreTests/AppLoggerTests.swift` — use `git mv`, rename the XCTestCase type to `AppLoggerTests`.
- `Tests/SeshatCoreTests/SeshatLoggerScaffoldingTests.swift:1-9 -> Tests/SeshatCoreTests/AppLoggerScaffoldingTests.swift` — use `git mv`, rename the XCTestCase type to `AppLoggerScaffoldingTests`.
- `Tests/SeshatAppKitTests/Theme/SeshatThemeTests.swift:1-244 -> Tests/SeshatAppKitTests/Theme/ThemeTests.swift` — use `git mv`, rename the XCTestCase type to `ThemeTests`.
- `Tests/SeshatAppKitTests/Components/SeshatLogoViewTests.swift:1-48 -> Tests/SeshatAppKitTests/Components/LogoViewTests.swift` — use `git mv`, rename the XCTestCase type to `LogoViewTests`.

### Scope — IN
- Use `git mv` for every file-path rename in this step; do not “rename” by deleting and recreating files.
- Rename the production symbols listed above and their mirrored test file/type names in the same commit series.
- Remove the `SeshatOnboardingCompleted` alias outright instead of keeping a compatibility synonym.
- Keep all implementation bodies behavior-identical. This step is spelling-only except for the alias deletion.

### Scope — OUT (with backlog ticket paths where applicable)
- Do not rename `Sources/SeshatAppKit/SeshatApp.swift:6-42`; bare `App` is the documented collision.
- Do not rename any SPM target name or any target-marker enum/compile test: `Package.swift:11-34,47-97`, `Sources/SeshatCore/SeshatCoreModule.swift:1`, `Sources/SeshatSession/SeshatSessionModule.swift:1`, `Sources/SeshatTranscription/SeshatTranscriptionModule.swift:1`, `Sources/SeshatTestSupport/SeshatTestSupportModule.swift:1`, `Sources/SeshatAppKit/Permissions/SeshatAppKitPermissionsModule.swift:1`.
- Do not update repo-wide call sites here except what the renamed files themselves require to keep their own declarations compiling. The wide sweep is Step 0.3.

### Acceptance tests — Tests/... — test name + what it asserts + mockup/doc clause it ties to
- `Tests/SeshatCoreTests/ConfigScaffoldingTests.swift` — `testTypeExists`; asserts the post-rename `Config` surface still resolves at compile time; ties to `Sources/SeshatCore/Config.swift:3-107`.
- `Tests/SeshatCoreTests/AppErrorScaffoldingTests.swift` — `testTypeExists`; asserts the post-rename `AppError` surface still resolves; ties to `Sources/SeshatCore/Errors.swift:3-80`.
- `Tests/SeshatCoreTests/AppLoggerScaffoldingTests.swift` — `testTypeExists`; asserts the post-rename `AppLogger` surface still resolves; ties to `Sources/SeshatCore/Logger.swift:4-52`.
- `Tests/SeshatAppKitTests/Theme/ThemeTests.swift` — `testColorHexInitializerRoundTrip`; asserts the theme type rename did not change behavior; ties to `Sources/SeshatAppKit/Theme/SeshatTheme.swift:24-25`.
- `Tests/SeshatAppKitTests/Components/LogoViewTests.swift` — existing logo-view geometry tests under the new type/file names; ties to `Sources/SeshatAppKit/Components/SeshatLogoView.swift:16-37`.

### Validation checklist (implementer ticks box-by-box in hand-off)
- [ ] The rename-now set is exact: `SeshatConfig -> Config`, `SeshatError -> AppError`, `SeshatLogger -> AppLogger`, `SeshatLogCategory -> AppLogCategory`, `SeshatPasteMode -> PasteMode`, `SeshatTheme -> Theme`, `SeshatLogoView -> LogoView`, `SeshatAppMain -> AppMain`, and the `SeshatOnboardingCompleted` alias is gone.
- [ ] The explicit keep set is exact: `SeshatApp`, the five module-marker enums, and the target-name compile tests remain prefixed.
- [ ] Every path rename in this step used `git mv`; there are no delete-and-recreate artifacts in `git diff --summary`.
- [ ] Locked decision `#3` is honored: the theme rename is spelling-only here; no theme-token changes piggybacked into this step.
- [ ] Diff against this step shows no silent divergence; every modified file is listed above, and any proposed deviation is recorded in the commit message comment and hand-off report.
- [ ] No `Color(hex:` outside `Theme/*` (hard rule — long-standing).
- [ ] No `UserDefaults.standard.*` direct reads — typed resolvers only.
- [ ] No `type`/`kind`/`intent` field added (hard rule — Phase 3 design lock: `project_phase3_notes_equals_history.md`).
- [ ] `swift build --build-tests` green from the main-repo path.
- [ ] No files outside `Files touched` modified.

### Commit style — `trunk: phase 0.2: <verb-led subject>`. Test + fix in same commit.
`trunk: phase 0.2: git-mv renamed production symbols and mirrored tests`

### Hand-off report template
```md
Phase 0.2 hand-off
- Commit: <sha> trunk: phase 0.2: git-mv renamed production symbols and mirrored tests
- Files renamed with git mv: <list>
- Symbols renamed: <list>
- Explicit keeps preserved: <list>
- Verification commands: <list>
- Deviations from plan: none | <required explicit note>
- Follow-ups / blockers: none | <list>
```

## Step 0.3 — Update repo-wide call sites, imports, comments, and test references
> Do NOT diverge from this plan or the Manus mockups. Silent divergence is the cardinal sin. To deviate, surface the proposed divergence in a comment in the commit message AND in the hand-off report; wait for main-session confirmation. Paraphrasing the contract is divergence. Renaming variables the plan specifies is divergence. Choosing a different animation curve than the mockup implies is divergence.

### Files touched (exhaustive) — path:line-range — what changes
- Whole-file mechanical updates in every file returned by the frozen inventory below. This is the exhaustive Step 0.3 surface; do not touch files outside this list.
- The inventory is intentionally frozen on trunk before Step 0.2 path renames. When executing Step 0.3 after Step 0.2, substitute the post-rename paths `Sources/SeshatCore/PasteMode.swift`, `Sources/SeshatAppKit/Theme/Theme.swift`, `Sources/SeshatAppKit/Components/LogoView.swift`, `Sources/SeshatAppKit/Composition/AppMain.swift`, `Tests/SeshatCoreTests/ConfigTests.swift`, `Tests/SeshatCoreTests/ConfigScaffoldingTests.swift`, `Tests/SeshatCoreTests/AppErrorTests.swift`, `Tests/SeshatCoreTests/AppErrorScaffoldingTests.swift`, `Tests/SeshatCoreTests/AppLoggerTests.swift`, `Tests/SeshatCoreTests/AppLoggerScaffoldingTests.swift`, `Tests/SeshatAppKitTests/Theme/ThemeTests.swift`, and `Tests/SeshatAppKitTests/Components/LogoViewTests.swift` for their pre-Step-0.2 counterparts without widening the surface.

```text
Sources/SeshatAppKit/Components/ActionButton.swift
Sources/SeshatAppKit/Components/AudioPlayerThumbnail.swift
Sources/SeshatAppKit/Components/ModeCard.swift
Sources/SeshatAppKit/Components/ResponseCardView.swift
Sources/SeshatAppKit/Components/SeshatLogoView.swift
Sources/SeshatAppKit/Components/SineWaveView.swift
Sources/SeshatAppKit/Components/StatusPill.swift
Sources/SeshatAppKit/Components/TagChip.swift
Sources/SeshatAppKit/Components/TranscriptRow.swift
Sources/SeshatAppKit/Components/WaveformView.swift
Sources/SeshatAppKit/Composition/AppComposition.swift
Sources/SeshatAppKit/Composition/AppStartupCoordinator.swift
Sources/SeshatAppKit/Composition/SeshatAppMain.swift
Sources/SeshatAppKit/Hotkeys/GlobalHotkeyMonitor.swift
Sources/SeshatAppKit/MenuBar/MenuBarSceneModel.swift
Sources/SeshatAppKit/MenuBar/StatusItemController.swift
Sources/SeshatAppKit/Notes/NotesContextPanel.swift
Sources/SeshatAppKit/Notes/NotesEditor.swift
Sources/SeshatAppKit/Notes/NotesSidebar.swift
Sources/SeshatAppKit/Notes/NotesView.swift
Sources/SeshatAppKit/Onboarding/OnboardingView.swift
Sources/SeshatAppKit/Onboarding/OnboardingWindowController.swift
Sources/SeshatAppKit/Overlay/PillOverlayController.swift
Sources/SeshatAppKit/Overlay/PillOverlayPresenter.swift
Sources/SeshatAppKit/Overlay/PillOverlayView.swift
Sources/SeshatAppKit/Overlay/PillOverlayViewModel.swift
Sources/SeshatAppKit/Paste/PasteInjector.swift
Sources/SeshatAppKit/SeshatApp.swift
Sources/SeshatAppKit/Settings/AIModelsTab.swift
Sources/SeshatAppKit/Settings/AdvancedTab.swift
Sources/SeshatAppKit/Settings/GeneralTab.swift
Sources/SeshatAppKit/Settings/HotkeyRecorder.swift
Sources/SeshatAppKit/Settings/ModesTab.swift
Sources/SeshatAppKit/Settings/SettingsView.swift
Sources/SeshatAppKit/Settings/ShortcutsTab.swift
Sources/SeshatAppKit/Theme/SeshatTheme.swift
Sources/SeshatAudio/AVAudioCaptureService.swift
Sources/SeshatAudio/AudioResampler.swift
Sources/SeshatCore/BaseDirectoryMigrator.swift
Sources/SeshatCore/Config.swift
Sources/SeshatCore/Errors.swift
Sources/SeshatCore/Logger.swift
Sources/SeshatCore/OnboardingState.swift
Sources/SeshatCore/PCMBuffer.swift
Sources/SeshatCore/Protocols.swift
Sources/SeshatCore/SQLiteTranscriptStore.swift
Sources/SeshatCore/SeshatPasteMode.swift
Sources/SeshatCore/SessionState.swift
Sources/SeshatCore/TranscriptReader.swift
Sources/SeshatCore/TranscriptStore.swift
Sources/SeshatSession/SessionCoordinator.swift
Sources/SeshatTestSupport/FakeAudioCapturing.swift
Sources/SeshatTestSupport/FakeTranscriber.swift
Sources/SeshatTranscription/FluidAudioTranscriber.swift
Tests/SeshatAppKitTests/AppEntryPointTests.swift
Tests/SeshatAppKitTests/Components/ActionButtonTests.swift
Tests/SeshatAppKitTests/Components/SeshatLogoViewTests.swift
Tests/SeshatAppKitTests/Components/StatusPillTests.swift
Tests/SeshatAppKitTests/Components/TagChipTests.swift
Tests/SeshatAppKitTests/DevelopmentComposition.swift
Tests/SeshatAppKitTests/ManualPillOverlayVerification.md
Tests/SeshatAppKitTests/ManualVisualVerification.md
Tests/SeshatAppKitTests/MenuBarFlowIntegrationTests.swift
Tests/SeshatAppKitTests/MenuBarSceneModelTests.swift
Tests/SeshatAppKitTests/Notes/TranscriptReaderTests.swift
Tests/SeshatAppKitTests/OnboardingViewModelTests.swift
Tests/SeshatAppKitTests/PasteInjectorTests.swift
Tests/SeshatAppKitTests/PillOverlayViewModelTests.swift
Tests/SeshatAppKitTests/SeshatAppKitShellCompileTests.swift
Tests/SeshatAppKitTests/Theme/SeshatThemeTests.swift
Tests/SeshatAudioTests/AVAudioCaptureServiceTests.swift
Tests/SeshatAudioTests/AudioTestSupport.swift
Tests/SeshatAudioTests/FakeSupportTests.swift
Tests/SeshatCoreTests/BaseDirectoryMigratorTests.swift
Tests/SeshatCoreTests/PCMBufferTests.swift
Tests/SeshatCoreTests/PasteModeTests.swift
Tests/SeshatCoreTests/SQLiteTranscriptStoreTests.swift
Tests/SeshatCoreTests/SeshatConfigScaffoldingTests.swift
Tests/SeshatCoreTests/SeshatConfigTests.swift
Tests/SeshatCoreTests/SeshatErrorScaffoldingTests.swift
Tests/SeshatCoreTests/SeshatErrorTests.swift
Tests/SeshatCoreTests/SeshatLoggerScaffoldingTests.swift
Tests/SeshatCoreTests/SeshatLoggerTests.swift
Tests/SeshatCoreTests/TranscriptStoreTests.swift
Tests/SeshatSessionTests/SessionCoordinatorAudioLevelTests.swift
Tests/SeshatSessionTests/SessionCoordinatorErrorTests.swift
Tests/SeshatSessionTests/SessionCoordinatorHappyPathTests.swift
Tests/SeshatSessionTests/SessionCoordinatorPreparationTests.swift
Tests/SeshatSessionTests/SessionCoordinatorStateTests.swift
Tests/SeshatSessionTests/SessionCoordinatorTranscriptStoreTests.swift
Tests/SeshatTranscriptionTests/FluidAudioTranscriberAlreadyDownloadedTests.swift
Tests/SeshatTranscriptionTests/FluidAudioTranscriberCompileTests.swift
Tests/SeshatTranscriptionTests/FluidAudioTranscriberTests.swift
Tests/SeshatTranscriptionTests/ManualTranscriptionVerification.md
Tests/SeshatTranscriptionTests/ModelDownloadFailureTests.swift
Tests/SeshatTranscriptionTests/ModelDownloadProgressTests.swift
Tests/SeshatTranscriptionTests/ModelIntegrityTests.swift
Tests/SeshatTranscriptionTests/ModelPathTests.swift
Tests/SeshatTranscriptionTests/Support/SeshatTranscriptionFilesystemTestCase.swift
```

- `Sources/SeshatAppKit/SeshatApp.swift:15-42` — keep the shell named `SeshatApp`, but update its collaborator spellings to `AppLogger`, `Config`, `PasteMode`, `Theme`, `LogoView`, and `AppMain`.
- `Sources/SeshatAppKit/Onboarding/OnboardingWindowController.swift:95-146` — replace the deleted `SeshatOnboardingCompleted` alias with `OnboardingState`.
- `Tests/SeshatAppKitTests/SeshatAppKitShellCompileTests.swift:8-31` — keep the file name because it is a target compile test, but update all collaborator spellings inside it.

### Scope — IN
- Replace every repo-wide reference to the renamed symbols from Step 0.2.
- Update comments, manual runbooks, preview labels, and test names that still mention the old prefixed symbols.
- Keep `SeshatApp` unchanged while updating its internals to the renamed collaborators.
- Keep the target-marker enum references unchanged.

### Scope — OUT (with backlog ticket paths where applicable)
- Do not touch the five module-marker files or their compile tests.
- Do not change behavior, layout, or copy beyond the mechanical rename surface.
- Do not piggyback Phase 1 permission-service work or Phase 2 UI work into this step.

### Acceptance tests — Tests/... — test name + what it asserts + mockup/doc clause it ties to
- `Tests/SeshatAppKitTests/AppEntryPointTests.swift` — `testCanInstantiateAppMainAfterRename`; asserts the app entry point still compiles and wires correctly under `AppMain`, `AppLogger`, and `Config`.
- `Tests/SeshatAppKitTests/MenuBarFlowIntegrationTests.swift` — `testStartupCoordinatorDoesNotBlockInitOnHotkeyInstall`; asserts the renamed entry-point surface still preserves startup ordering.
- `Tests/SeshatAudioTests/AVAudioCaptureServiceTests.swift` — existing microphone-error mapping tests remain green under `AppError`/`AppLogger`; ties to `Sources/SeshatAudio/AVAudioCaptureService.swift:39-45`.
- `Tests/SeshatSessionTests/SessionCoordinatorPreparationTests.swift` — existing preparation tests remain green under `AppLogger`/`AppError`; ties to `Sources/SeshatSession/SessionCoordinator.swift`.
- `Tests/SeshatTranscriptionTests/FluidAudioTranscriberTests.swift` — existing model-path/download tests remain green under `Config`; ties to `Sources/SeshatCore/Config.swift:43-63`.

### Validation checklist (implementer ticks box-by-box in hand-off)
- [ ] The frozen Step 0.3 inventory above is exactly the touched surface; no extra files were edited.
- [ ] `rg -n '\bSeshat(Config|Error|Logger|LogCategory|PasteMode|Theme|LogoView|AppMain|OnboardingCompleted)\b' Sources Tests` returns zero hits after the step.
- [ ] `rg -n '\bSeshat(App|CoreModule|SessionModule|TranscriptionModule|TestSupportModule|AppKitPermissionsModule)\b' Sources Tests` returns only the explicit keep set.
- [ ] Comments and manual runbooks were updated alongside code so no stale rename vocabulary remains in shipped docs.
- [ ] Diff against this step shows no silent divergence; every modified file is listed above, and any proposed deviation is recorded in the commit message comment and hand-off report.
- [ ] No `Color(hex:` outside `Theme/*` (hard rule — long-standing).
- [ ] No `UserDefaults.standard.*` direct reads — typed resolvers only.
- [ ] No `type`/`kind`/`intent` field added (hard rule — Phase 3 design lock: `project_phase3_notes_equals_history.md`).
- [ ] `swift build --build-tests` green from the main-repo path.
- [ ] No files outside `Files touched` modified.

### Commit style — `trunk: phase 0.3: <verb-led subject>`. Test + fix in same commit.
`trunk: phase 0.3: update repo-wide rename call sites`

### Hand-off report template
```md
Phase 0.3 hand-off
- Commit: <sha> trunk: phase 0.3: update repo-wide rename call sites
- Frozen inventory used: <paste the rg command and confirm it matched>
- Files changed: <list or “exact frozen inventory”>
- Residual allowed `Seshat*` symbols: <paste keep-set grep output>
- Verification commands: <list>
- Deviations from plan: none | <required explicit note>
- Follow-ups / blockers: none | <list>
```

## Step 0.4 — Verification sweep: build/tests clean, no stragglers
> Do NOT diverge from this plan or the Manus mockups. Silent divergence is the cardinal sin. To deviate, surface the proposed divergence in a comment in the commit message AND in the hand-off report; wait for main-session confirmation. Paraphrasing the contract is divergence. Renaming variables the plan specifies is divergence. Choosing a different animation curve than the mockup implies is divergence.

### Files touched (exhaustive) — path:line-range — what changes
- No planned source-file edits. This step is verification-first.
- If verification finds a break, fold the fix back into the smallest failing file set from Step 0.2 or Step 0.3 and list those files explicitly in the hand-off report instead of widening Phase 0 silently.

### Scope — IN
- Run the full rename semantic audit after Steps 0.1-0.3.
- Run the main-repo verification command set for the renamed tree.
- Fix only true rename fallout discovered by verification; do not expand scope.

### Scope — OUT (with backlog ticket paths where applicable)
- No behavior changes, no new tests beyond rename fallout, no UI/content work.
- Do not rename any additional symbols “while you’re here.”

### Acceptance tests — Tests/... — test name + what it asserts + mockup/doc clause it ties to
- `Tests/SeshatCoreTests/ConfigTests.swift` — renamed config tests still pass, proving the base-directory override path survived the sweep.
- `Tests/SeshatAppKitTests/AppEntryPointTests.swift` — app entry point still compiles after the full rename surface.
- `Tests/SeshatAudioTests/AVAudioCaptureServiceTests.swift` — audio permission/error plumbing still compiles under the new names.
- `Tests/SeshatSessionTests/SessionCoordinatorHappyPathTests.swift` — session happy path still compiles under the new names.
- `Tests/SeshatTranscriptionTests/FluidAudioTranscriberTests.swift` — transcription stack still compiles under the new names.

### Validation checklist (implementer ticks box-by-box in hand-off)
- [ ] `swift build --build-tests` succeeds from `/Users/nitinkum/Projects/nitkrar/seshat`.
- [ ] `swift test --filter ConfigTests`, `swift test --filter AppEntryPointTests`, `swift test --filter AVAudioCaptureServiceTests`, `swift test --filter SessionCoordinatorHappyPathTests`, and `swift test --filter FluidAudioTranscriberTests` all pass from the main-repo path.
- [ ] `rg -n '\bSeshat(Config|Error|Logger|LogCategory|PasteMode|Theme|LogoView|AppMain|OnboardingCompleted)\b' Sources Tests` returns zero hits.
- [ ] `git diff --name-only --diff-filter=ACMR HEAD` shows only the Phase 0 file surface.
- [ ] Diff against this step shows no silent divergence; every modified file is accounted for and any proposed deviation is recorded in the commit message comment and hand-off report.
- [ ] No `Color(hex:` outside `Theme/*` (hard rule — long-standing).
- [ ] No `UserDefaults.standard.*` direct reads — typed resolvers only.
- [ ] No `type`/`kind`/`intent` field added (hard rule — Phase 3 design lock: `project_phase3_notes_equals_history.md`).
- [ ] `swift build --build-tests` green from the main-repo path.
- [ ] No files outside `Files touched` modified.

### Commit style — `trunk: phase 0.4: <verb-led subject>`. Test + fix in same commit.
`trunk: phase 0.4: make rename sweep verification-clean`

### Hand-off report template
```md
Phase 0.4 hand-off
- Commit: <sha> trunk: phase 0.4: make rename sweep verification-clean
- Verification commands run: <list>
- Any fallout fixes folded here: none | <list>
- Residual allowed `Seshat*` grep output: <paste keep-set output>
- Deviations from plan: none | <required explicit note>
- Ready for Phase 1: yes | no (<reason>)
```

# Phase 2 — Unified UI Bundle

## Critical discipline
> Do NOT diverge from this plan or the Manus mockups. Silent divergence is the cardinal sin. To deviate, surface the proposed divergence in a comment in the commit message AND in the hand-off report; wait for main-session confirmation. Paraphrasing the contract is divergence. Renaming variables the plan specifies is divergence. Choosing a different animation curve than the mockup implies is divergence.

## Prerequisites
- Execute Phase 0 and Phase 1 first. This phase assumes the post-rename symbols and the unified permission-service surface from [plans/PHASE_0_rename.md](/Users/nitinkum/Projects/nitkrar/seshat/plans/PHASE_0_rename.md) and [plans/PHASE_1_permission_service.md](/Users/nitinkum/Projects/nitkrar/seshat/plans/PHASE_1_permission_service.md), even though the grounding citations below still point at trunk `1ea02e4`.
- Read the authoritative bundle spec before touching any UI file:
  - `plans/App UI design/Claude_Final_Bundle_Prompt.md:5-100` — authoritative Sections 1-4 and implementation order.
  - `plans/App UI design/Seshat UI Polish & Unified Window Implementation.md:5-101` — same bundle in short form, plus the explicit “ResponseCard scaffold only” note at `:87-91`.
  - `plans/App UI design/SeshatTheme.swift:1-255` — authoritative replacement theme file with `WindowTint`, `PillAppearance`, palette tokens, layout metrics, and typed `UserDefaults` resolvers.
  - Mockups viewed and cited verbatim in this phase’s validation lists: `screen_home.png`, `screen_menu.png`, `screen_modes.png`, `screen_transcriptions.png`, `final_settings_general_v2.png`, `final_settings_permissions_v2.png`, `screen_pill_appearance.png`.
- Freeze the legacy UI baseline before editing so the Phase 2 diff is easy to audit:
  - `Sources/SeshatAppKit/Settings/SettingsView.swift:4-69` — current settings still ship as a 5-tab `TabView`.
  - `Sources/SeshatAppKit/Settings/GeneralTab.swift:22-137`, `Sources/SeshatAppKit/Settings/AIModelsTab.swift:16-48`, `Sources/SeshatAppKit/Settings/ShortcutsTab.swift:15-103`, `Sources/SeshatAppKit/Settings/AdvancedTab.swift:28-187` — current settings content is still split across separate tabs.
  - `Sources/SeshatAppKit/Settings/ModesTab.swift:5-44` and `Sources/SeshatCore/ModeDescriptor.swift:25-39` — current modes surface is read-only and the registry only seeds one static Dictation mode.
  - `Sources/SeshatAppKit/Notes/NotesView.swift:4-102`, `Sources/SeshatAppKit/Notes/NotesSidebar.swift:4-109`, `Sources/SeshatAppKit/Notes/NotesEditor.swift:4-66`, `Sources/SeshatAppKit/Notes/NotesContextPanel.swift:4-137`, `Sources/SeshatAppKit/Notes/NotesWindowController.swift:5-79` — current transcript/history UI is a separate 3-column Notes window.
  - `Sources/SeshatAppKit/MenuBar/StatusItemMenuModel.swift:65-136` and `Sources/SeshatAppKit/MenuBar/StatusItemController.swift:154-229` — current menu still uses the pre-Manus layout and state-based icon swapping instead of the required 0.6s recording timer.
  - `Sources/SeshatAppKit/Composition/SeshatAppMain.swift:7-259` — app composition still wires separate Notes / Settings / Onboarding windows.
  - `Sources/SeshatAppKit/Onboarding/OnboardingWindowController.swift:67-156` — standalone onboarding window still owns first-launch routing on trunk.
  - `Sources/SeshatAppKit/Overlay/PillOverlayPresenter.swift:281-294` and `Sources/SeshatAppKit/Overlay/ResponseCard.swift:21-172` — `ResponseCard` already exists and is currently consumed by the clipboard-only notice path, which Phase 2 must neutralize because locked decision `#5` forbids a production caller this phase.
  - `Sources/SeshatAppKit/Resources/StatusBarIcon.png`, `Sources/SeshatAppKit/Resources/StatusBarIconListening.png`, and `Sources/SeshatAppKit/MenuBar/StatusItemIconLoader.swift:25-63` — the two icon frames already exist; Phase 2.2 must change the runtime behavior, not invent new assets.
- Do not silently invent title-bar behavior that the text spec does not lock. `plans/App UI design/Claude_Final_Bundle_Prompt.md:43-50` makes the sidebar, routing, and microphone footer authoritative; the settings mockups also show extra title-bar chrome (`final_settings_general_v2.png`, `final_settings_permissions_v2.png`) that is not described in the text. If implementers believe that chrome must ship, that is a main-session review item, not an in-lane decision.
- Locked decision `#1` requires backlog docs at `plans/backlog/home-stats-metrics.md`, `plans/backlog/check-for-updates-sparkle.md`, `plans/backlog/mic-device-picker.md`, and `plans/backlog/launch-at-login-and-dock.md`. This planning task does not create them because `plans/backlog/` is a protected user drop in the current worktree; future implementers must create or update those files before closing the affected Phase 2 steps.

## Locked design decisions applicable to this phase
- Locked decision `#1`: ship the full bundle in one phase group, with only the explicitly allowed stub exceptions. Home metrics stay partially stubbed, the menu omits `Check for Updates`, the microphone picker is a hard-coded no-op, and `Launch at login` / `Show in Dock` persist only.
- Locked decision `#2`: Pill Style (`Classic`, `Mini`, `None`) and Pill Visibility (`alwaysOn`, `autoShow`, `hidden`) are orthogonal controls. The UI must preserve both axes.
- Locked decision `#3`: theme migration is a big-bang replacement. This phase does one call-site conversion, not a compatibility layer.
- Locked decision `#4`: Settings copy says `Simulate Keypresses` for backend enum case `PasteMode.pasteAtCursor`; the enum name does not change.
- Locked decision `#5`: `ResponseCard` is a separate floating `NSPanel` above the pill. This phase ships the scaffold and styling only. No production path fires it.
- Locked decision `#6`: the menu-bar `Home` row appears once. The duplicate in `screen_menu.png` is a mockup artifact, not executable UI.
- Locked decision `#8`: Accessibility stays optional everywhere. Any missing-permission remediation in the unified window must keep AX optional and preserve clipboard fallback.
- Locked decision `#9`: `Sources/SeshatAudio/AVAudioCaptureService.swift:39-45` remains untouched; Phase 2 uses the Phase 1 permission service only in AppKit consumers.

## Step 2.1 — Theme big-bang replacement
> Do NOT diverge from this plan or the Manus mockups. Silent divergence is the cardinal sin. To deviate, surface the proposed divergence in a comment in the commit message AND in the hand-off report; wait for main-session confirmation. Paraphrasing the contract is divergence. Renaming variables the plan specifies is divergence. Choosing a different animation curve than the mockup implies is divergence.

### Files touched (exhaustive) — path:line-range — what changes
- `Sources/SeshatAppKit/Theme/Theme.swift:1-277` (trunk source `Sources/SeshatAppKit/Theme/SeshatTheme.swift:1-277`) — replace the Phase-0-renamed theme file with the authoritative content from `plans/App UI design/SeshatTheme.swift:1-255`, keeping the Phase 0 spellings `Theme`, `WindowTint`, and `PillAppearance` instead of reintroducing `SeshatTheme`.
- Whole-file big-bang call-site migration across every existing theme consumer returned by the frozen inventory below. Execute the step against the post-Phase-0 renamed paths `Components/LogoView.swift`, `Theme/Theme.swift`, `Tests/.../LogoViewTests.swift`, and `Tests/.../ThemeTests.swift`, but do not widen the surface beyond this list:

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
Sources/SeshatAppKit/Notes/NotesContextPanel.swift
Sources/SeshatAppKit/Notes/NotesEditor.swift
Sources/SeshatAppKit/Notes/NotesSidebar.swift
Sources/SeshatAppKit/Notes/NotesView.swift
Sources/SeshatAppKit/Onboarding/OnboardingView.swift
Sources/SeshatAppKit/Overlay/PillOverlayView.swift
Sources/SeshatAppKit/Settings/AIModelsTab.swift
Sources/SeshatAppKit/Settings/AdvancedTab.swift
Sources/SeshatAppKit/Settings/GeneralTab.swift
Sources/SeshatAppKit/Settings/HotkeyRecorder.swift
Sources/SeshatAppKit/Settings/ModesTab.swift
Sources/SeshatAppKit/Settings/SettingsView.swift
Sources/SeshatAppKit/Settings/ShortcutsTab.swift
Sources/SeshatAppKit/Theme/SeshatTheme.swift
Tests/SeshatAppKitTests/Components/ActionButtonTests.swift
Tests/SeshatAppKitTests/Components/SeshatLogoViewTests.swift
Tests/SeshatAppKitTests/Components/StatusPillTests.swift
Tests/SeshatAppKitTests/Components/TagChipTests.swift
Tests/SeshatAppKitTests/ManualVisualVerification.md
Tests/SeshatAppKitTests/Theme/SeshatThemeTests.swift
```

### Scope — IN
- Land the new theme in one big-bang call-site swap. Every touched consumer compiles only against the new `Theme`, `WindowTint`, and `PillAppearance` APIs when this step closes.
- Preserve the Phase 0 rename contract while copying the Manus file. The source of truth is `plans/App UI design/SeshatTheme.swift:1-255`; the destination names stay post-Phase-0.
- Add or update tests that pin the new persisted defaults keys and theme-token expectations, including `WindowTint` default `.warm` and `PillAppearance` default `.dark`.
- Update visual/manual runbooks so reviewers validate the new theme tokens rather than the pre-Manus dark-only palette.

### Scope — OUT (with backlog ticket paths where applicable)
- No menu layout or menu action changes here. That is Step 2.2.
- No unified-window shell yet. That is Step 2.3.
- No settings interaction mapping yet. The theme file ships now; the General / Permissions / About UI that mutates it lands in Step 2.7.
- Do not create a compatibility shim between the old and new theme APIs. Locked decision `#3` forbids coexistence.

### Acceptance tests — Tests/... — test name + what it asserts + mockup/doc clause it ties to
- `Tests/SeshatAppKitTests/Theme/ThemeTests.swift` — `testWindowTintDefaultsToWarmAndPersists`; asserts `WindowTint.resolve()` defaults to `.warm` and persists through the typed resolver; ties to `plans/App UI design/SeshatTheme.swift:13-33`.
- `Tests/SeshatAppKitTests/Theme/ThemeTests.swift` — `testPillAppearanceDefaultsToDarkAndPersists`; asserts `PillAppearance.resolve()` defaults to `.dark` and persists through the typed resolver; ties to `plans/App UI design/SeshatTheme.swift:85-117`.
- `Tests/SeshatAppKitTests/Theme/ThemeTests.swift` — `testThemeTokensMatchProvidedManusFile`; asserts the palette, status, spacing, radius, and layout metrics now match `plans/App UI design/SeshatTheme.swift:121-255`.
- `Tests/SeshatAppKitTests/ManualVisualVerification.md` — add a new Manus-theme section that verifies window-tint and pill-appearance tokens against `plans/App UI design/Seshat UI Polish & Unified Window Implementation.md:5-13`.

### Validation checklist (implementer ticks box-by-box in hand-off)
- [ ] `Sources/SeshatAppKit/Theme/Theme.swift` matches `plans/App UI design/SeshatTheme.swift:1-255` token-for-token except for the already-locked Phase 0 rename from `SeshatTheme` to `Theme`.
- [ ] `screen_home.png` warm main background, pale sidebar, and white cards are all reachable from `WindowTint.warm` in `plans/App UI design/SeshatTheme.swift:35-80`.
- [ ] `screen_transcriptions.png` uses the same warm shell/card palette as `screen_home.png`; no legacy dark-only theme assumptions survive in the shell components.
- [ ] `screen_modes.png` active-state green, warm shell tint, and white cards are all mapped through `plans/App UI design/SeshatTheme.swift:127-138,150-163`.
- [ ] `final_settings_general_v2.png` grouped cards, segment backgrounds, and neutral text hierarchy all come from the new theme file rather than ad hoc per-view colors.
- [ ] `final_settings_permissions_v2.png` orange required dot, blue `Grant Access` button, and green granted dot map to `plans/App UI design/SeshatTheme.swift:133-138`.
- [ ] `screen_pill_appearance.png` dark, light, and system pill surfaces are represented by `PillAppearance` and the explicit pill tokens in `plans/App UI design/SeshatTheme.swift:85-117,150-163`.
- [ ] Locked decision `#3` is honored: the theme lands as one big-bang call-site swap; there is no dual-API bridge and no “old theme still used in some views” exception.
- [ ] Diff against this step shows no silent divergence; every modified file is listed above, and any proposed deviation is recorded in the commit message comment and hand-off report.
- [ ] No `Color(hex:` outside `Theme/*` (hard rule — long-standing).
- [ ] No `UserDefaults.standard.*` direct reads — typed resolvers only.
- [ ] No `type`/`kind`/`intent` field added (hard rule — Phase 3 design lock: `project_phase3_notes_equals_history.md`).
- [ ] `swift build --build-tests` green from the main-repo path.
- [ ] No files outside `Files touched` modified.

### Commit style — `trunk: phase 2.1: <verb-led subject>`. Test + fix in same commit.
Use 3-5 commits if needed. Prefix every commit with `trunk: phase 2.1:`. Recommended close-out subject: `trunk: phase 2.1: replace the app theme in one big-bang swap`.

### Hand-off report template
```md
Phase 2.1 hand-off
- Commit(s): <sha list>
- Theme source copied from: plans/App UI design/SeshatTheme.swift:1-255
- Consumers migrated: <list>
- Tests added/updated: <list>
- Verification commands: <list>
- Deviations from plan: none | <required explicit note>
- Follow-ups / blockers: none | <list>
```

## Step 2.2 — Menu bar un-gating, Manus layout, and 0.6s icon animation
> Do NOT diverge from this plan or the Manus mockups. Silent divergence is the cardinal sin. To deviate, surface the proposed divergence in a comment in the commit message AND in the hand-off report; wait for main-session confirmation. Paraphrasing the contract is divergence. Renaming variables the plan specifies is divergence. Choosing a different animation curve than the mockup implies is divergence.

### Files touched (exhaustive) — path:line-range — what changes
- `Sources/SeshatAppKit/MenuBar/StatusItemMenuModel.swift:13-174` — replace the legacy menu model with the Manus row order, add SF Symbol names, add `Paste Last Transcript`, add the microphone submenu placeholder, and remove any onboarding-based enable/disable logic.
- `Sources/SeshatAppKit/MenuBar/StatusItemController.swift:29-268` — render icon-backed `NSMenuItem`s, support the new menu model shape, and replace the current state-based pose switch with a recording-only `Timer` that toggles the two icon frames every 0.6s.
- `Sources/SeshatAppKit/MenuBar/MenuBarSceneModel.swift:7-151` — expose enough state for `Paste Last Transcript` enabled/disabled behavior and keep record/paste actions available under the new layout.
- `Sources/SeshatAppKit/MenuBar/StatusItemIconLoader.swift:25-63` — keep the idle/listening asset loader and add any helper needed by the new timer-driven animation without changing the underlying asset names.
- `Sources/SeshatAppKit/Composition/AppMain.swift:72-167` (post-Phase-0 path `Sources/SeshatAppKit/Composition/AppMain.swift`) — update menu action wiring so the renamed `Home` action is injectable and ready for Step 2.3’s unified-window host.
- `Tests/SeshatAppKitTests/MenuBar/StatusItemMenuModelTests.swift:12-248` — replace the old order/permission assertions with Manus-layout coverage.
- `Tests/SeshatAppKitTests/MenuBarSceneModelTests.swift:11-674` — keep menu actions and transcript-availability behavior green after the row changes.
- `Tests/SeshatAppKitTests/MenuBarFlowIntegrationTests.swift:17-207` — keep end-to-end menu-bar flow coverage after the layout and action-id changes.
- `Tests/SeshatAppKitTests/MenuBar/StatusItemIconLoaderTests.swift:14-33` — retain asset-loading coverage while the timer starts using both frames.
- `Tests/SeshatAppKitTests/ManualStatusItemVerification.md:1-26` — rewrite the runbook for the Manus layout and frame animation.

### Scope — IN
- Remove all onboarding gating from `Home` and `Settings`. The menu is always interactive per `plans/App UI design/Claude_Final_Bundle_Prompt.md:19-23`.
- Change `History` to `Home`, keep only one `Home` row, add SF Symbols, add `Paste Last Transcript`, and add the hard-coded `MacBook Pro Microphone` row with a no-op submenu that contains disabled `Coming soon` copy.
- Implement the 2-frame icon animation exactly as specified: `StatusBarIcon.png` idle, `StatusBarIconListening.png` recording, 0.6s timer only while recording.
- Keep the actual `Home` window target injectable because the unified window does not exist until Step 2.3.

### Scope — OUT (with backlog ticket paths where applicable)
- Do not build the unified main window in this step. That is Step 2.3.
- Do not render `Check for Updates...` in this phase. Locked decision `#1` sends it to `plans/backlog/check-for-updates-sparkle.md`.
- Do not build a real microphone picker. Locked decision `#1` requires the static `MacBook Pro Microphone` label and a no-op submenu only; the real picker lives in `plans/backlog/mic-device-picker.md`.
- Do not route `Settings` to the unified window yet. That cutover belongs to Step 2.8.

### Acceptance tests — Tests/... — test name + what it asserts + mockup/doc clause it ties to
- `Tests/SeshatAppKitTests/MenuBar/StatusItemMenuModelTests.swift` — `testMenuMatchesManusLayoutWithoutDuplicateHomeOrUpdatesRow`; asserts the row order matches `plans/App UI design/Claude_Final_Bundle_Prompt.md:23-33` except for the locked omission of `Check for Updates...`, and asserts `Home` appears once.
- `Tests/SeshatAppKitTests/MenuBar/StatusItemMenuModelTests.swift` — `testPasteLastTranscriptRowDisablesWhenNoTranscriptExists`; asserts the new row exists and disables when `lastResultText` is absent; ties to `screen_menu.png`.
- `Tests/SeshatAppKitTests/MenuBarSceneModelTests.swift` — `testCopyLatestTranscriptBacksPasteLastTranscriptMenuAction`; asserts the new menu row calls the existing transcript copy/paste path; ties to `plans/App UI design/Claude_Final_Bundle_Prompt.md:27-29`.
- `Tests/SeshatAppKitTests/MenuBarFlowIntegrationTests.swift` — `testRecordingStartsAndStopsMenuBarIconAnimationTimer`; asserts the controller starts the 0.6s timer only while recording; ties to `plans/App UI design/Claude_Final_Bundle_Prompt.md:34-37`.
- `Tests/SeshatAppKitTests/ManualStatusItemVerification.md` — replace the current tint-only checks with a Manus-layout runbook that verifies `screen_menu.png` and the 0.6s frame toggle.

### Validation checklist (implementer ticks box-by-box in hand-off)
- [ ] `screen_menu.png` header row shows the quill/app-name header and a single highlighted `Home` row; the duplicate `Home` row in the mockup is treated as the locked hover/rest artifact and does not ship.
- [ ] `screen_menu.png` row order is `Home`, separator, `Start Recording`, `Paste Last Transcript`, separator, `MacBook Pro Microphone`, separator, `Quit Seshat`, matching `plans/App UI design/Claude_Final_Bundle_Prompt.md:23-33` after applying locked decision `#1` to omit `Check for Updates...`.
- [ ] `screen_menu.png` `MacBook Pro Microphone` row is hard-coded and its submenu is a no-op with disabled `Coming soon` copy, per locked decision `#1` and backlog `plans/backlog/mic-device-picker.md`.
- [ ] `screen_menu.png` does not render `Check for Updates...`; the omission is explicit and cited to `plans/backlog/check-for-updates-sparkle.md`.
- [ ] `plans/App UI design/Claude_Final_Bundle_Prompt.md:19-23` is honored literally: `Home` and `Settings` are always enabled, regardless of onboarding completion.
- [ ] `plans/App UI design/Claude_Final_Bundle_Prompt.md:34-37` is honored literally: recording starts a 0.6s icon timer that alternates `StatusBarIcon` and `StatusBarIconListening`, and leaving recording invalidates the timer cleanly.
- [ ] Locked decision `#6` is honored: there is one `Home` row only.
- [ ] Diff against this step shows no silent divergence; every modified file is listed above, and any proposed deviation is recorded in the commit message comment and hand-off report.
- [ ] No `Color(hex:` outside `Theme/*` (hard rule — long-standing).
- [ ] No `UserDefaults.standard.*` direct reads — typed resolvers only.
- [ ] No `type`/`kind`/`intent` field added (hard rule — Phase 3 design lock: `project_phase3_notes_equals_history.md`).
- [ ] `swift build --build-tests` green from the main-repo path.
- [ ] No files outside `Files touched` modified.

### Commit style — `trunk: phase 2.2: <verb-led subject>`. Test + fix in same commit.
Use 2-4 commits if needed. Prefix every commit with `trunk: phase 2.2:`. Recommended close-out subject: `trunk: phase 2.2: ship the Manus menu bar layout and recording icon timer`.

### Hand-off report template
```md
Phase 2.2 hand-off
- Commit(s): <sha list>
- Final menu order shipped: <paste row order>
- Locked omissions/backlogs: <list>
- Timer behavior verified: <summary>
- Tests added/updated: <list>
- Verification commands: <list>
- Deviations from plan: none | <required explicit note>
- Follow-ups / blockers: none | <list>
```

## Step 2.3 — Build the unified `NavigationSplitView` shell
> Do NOT diverge from this plan or the Manus mockups. Silent divergence is the cardinal sin. To deviate, surface the proposed divergence in a comment in the commit message AND in the hand-off report; wait for main-session confirmation. Paraphrasing the contract is divergence. Renaming variables the plan specifies is divergence. Choosing a different animation curve than the mockup implies is divergence.

### Files touched (exhaustive) — path:line-range — what changes
- `Sources/SeshatAppKit/Composition/AppMain.swift:7-259` (trunk source `Sources/SeshatAppKit/Composition/SeshatAppMain.swift:7-259`) — compose a shared unified-window host and wire the menu bar’s `Home` action to `show(tab: .home)`.
- `Sources/SeshatAppKit/MainWindow/AppTab.swift:new file` — define the sidebar selection enum with exactly `.home`, `.transcriptions`, `.modes`, and `.settings`.
- `Sources/SeshatAppKit/MainWindow/MainWindowViewModel.swift:new file` — own the selected tab and expose the single-window route state used by menu-bar and app-entry callers.
- `Sources/SeshatAppKit/MainWindow/MainWindowView.swift:new file` — build the `NavigationSplitView` shell with a fixed 200pt sidebar, app icon/title at the top, tab links in the middle, and the current microphone indicator at the bottom.
- `Sources/SeshatAppKit/MainWindow/MainWindowController.swift:new file` — host the shell inside one reusable `NSWindow` titled `Seshat`, with `show(tab:)` selecting the requested destination before presenting the window.
- `Tests/SeshatAppKitTests/MainWindow/MainWindowViewModelTests.swift:new file` — pin default selection and route updates.
- `Tests/SeshatAppKitTests/MainWindow/MainWindowControllerTests.swift:new file` — pin single-window reuse and selection changes.
- `Tests/SeshatAppKitTests/AppEntryPointTests.swift:8-82` — update the app-entry test surface for the new host.
- `Tests/SeshatAppKitTests/ManualUnifiedWindowVerification.md:new file` — create the unified-window runbook that later Phase 2 steps extend.

### Scope — IN
- Create exactly one unified window host for the four tabs described in `plans/App UI design/Claude_Final_Bundle_Prompt.md:43-50`.
- Use `NavigationSplitView` and a 200pt sidebar as the only shell architecture for Home, Transcriptions, Modes, and Settings.
- Wire only the `Home` menu item to the new window in this step. This keeps the shell reachable while later steps migrate the actual content.
- Placeholder detail content is allowed inside this step only because Steps 2.4-2.7 immediately replace it in the same phase group.

### Scope — OUT (with backlog ticket paths where applicable)
- Do not invent extra title-bar chrome beyond the text spec in `plans/App UI design/Claude_Final_Bundle_Prompt.md:43-50`; the settings mockups show additional toolbar detail that is not text-locked and therefore requires main-session confirmation before use.
- Do not migrate Notes, Modes, or Settings content yet. Those are Steps 2.4-2.7.
- Do not remove onboarding routing yet. That is Step 2.8.
- Do not delete legacy windows yet. That is Step 2.10.

### Acceptance tests — Tests/... — test name + what it asserts + mockup/doc clause it ties to
- `Tests/SeshatAppKitTests/MainWindow/MainWindowViewModelTests.swift` — `testDefaultSelectionIsHome`; asserts the shell boots into `.home`; ties to `plans/App UI design/Claude_Final_Bundle_Prompt.md:47-50`.
- `Tests/SeshatAppKitTests/MainWindow/MainWindowControllerTests.swift` — `testShowHomeReusesSingleWindowAndSelectsHome`; asserts one `NSWindow` is reused for repeat opens; ties to `plans/App UI design/Claude_Final_Bundle_Prompt.md:44-50`.
- `Tests/SeshatAppKitTests/AppEntryPointTests.swift` — `testAppMainBuildsUnifiedWindowHostAndRoutesHomeMenuAction`; asserts the entry point now composes the new host and connects the `Home` action to it.
- `Tests/SeshatAppKitTests/ManualUnifiedWindowVerification.md` — add `MV-UW-1` and `MV-UW-2` covering the shared shell, sidebar order, and one-window reuse; ties to `screen_home.png` and `plans/App UI design/Claude_Final_Bundle_Prompt.md:43-50`.

### Validation checklist (implementer ticks box-by-box in hand-off)
- [ ] `screen_home.png` shell is matched: top-left app icon/name, `Home / Transcriptions / Modes / Settings` sidebar order, and Home selected by default.
- [ ] `screen_transcriptions.png` uses the same sidebar shell with only the selected row changing.
- [ ] `screen_modes.png` uses the same sidebar shell with only the selected row changing.
- [ ] `final_settings_general_v2.png` uses the same sidebar shell with `Settings` selected.
- [ ] `final_settings_permissions_v2.png` uses the same sidebar shell with the current microphone indicator at the bottom.
- [ ] `plans/App UI design/Claude_Final_Bundle_Prompt.md:43-50` is implemented literally: one `NSWindow`, one `NavigationSplitView`, one `AppTab` route owner, 200pt sidebar.
- [ ] `Home` from Step 2.2 now opens this shell at `.home`; `Settings` can still point at the legacy settings window until Step 2.8.
- [ ] Diff against this step shows no silent divergence; every modified file is listed above, and any proposed deviation is recorded in the commit message comment and hand-off report.
- [ ] No `Color(hex:` outside `Theme/*` (hard rule — long-standing).
- [ ] No `UserDefaults.standard.*` direct reads — typed resolvers only.
- [ ] No `type`/`kind`/`intent` field added (hard rule — Phase 3 design lock: `project_phase3_notes_equals_history.md`).
- [ ] `swift build --build-tests` green from the main-repo path.
- [ ] No files outside `Files touched` modified.

### Commit style — `trunk: phase 2.3: <verb-led subject>`. Test + fix in same commit.
Use 3-5 commits if needed. Prefix every commit with `trunk: phase 2.3:`. Recommended close-out subject: `trunk: phase 2.3: build the unified window shell`.

### Hand-off report template
```md
Phase 2.3 hand-off
- Commit(s): <sha list>
- New shell files: <list>
- Routing entrypoints wired: <list>
- Placeholder tabs still pending: <list>
- Tests added/updated: <list>
- Verification commands: <list>
- Deviations from plan: none | <required explicit note>
- Follow-ups / blockers: none | <list>
```

## Step 2.4 — Build the Home tab with the allowed metric stubs
> Do NOT diverge from this plan or the Manus mockups. Silent divergence is the cardinal sin. To deviate, surface the proposed divergence in a comment in the commit message AND in the hand-off report; wait for main-session confirmation. Paraphrasing the contract is divergence. Renaming variables the plan specifies is divergence. Choosing a different animation curve than the mockup implies is divergence.

### Files touched (exhaustive) — path:line-range — what changes
- `Sources/SeshatAppKit/MainWindow/MainWindowView.swift:new file from Step 2.3` — replace the Home placeholder with the real Home tab surface.
- `Sources/SeshatAppKit/MainWindow/Home/HomeViewModel.swift:new file` — load recent transcripts and compute the live `Recordings` count.
- `Sources/SeshatAppKit/MainWindow/Home/HomeTabView.swift:new file` — render the `Home` header, four stat cards, recent-transcriptions section, and empty state.
- `Sources/SeshatAppKit/Composition/AppMain.swift:183-259` (trunk source `Sources/SeshatAppKit/Composition/SeshatAppMain.swift:183-259`) — provide the transcript reader dependency to the unified window host.
- `Tests/SeshatAppKitTests/MainWindow/HomeViewModelTests.swift:new file` — pin the recordings count and recent-list behavior.
- `Tests/SeshatAppKitTests/MainWindow/HomeTabViewTests.swift:new file` — pin empty-state and card rendering behavior that is still practical to assert in XCTest.
- `Tests/SeshatAppKitTests/ManualUnifiedWindowVerification.md:new file from Step 2.3` — extend the runbook with Home-tab visual checks.

### Scope — IN
- Match the Home content described in `plans/App UI design/Claude_Final_Bundle_Prompt.md:54-57`.
- Use the existing transcript-reading surface to load the 3 most recent transcriptions and to compute the live recordings count. Do not invent a parallel store.
- Render `Words this week`, `Mins saved`, and `WPM avg` as `—` placeholders, while `Recordings` is the one live card.
- Render the empty state exactly when there are no transcriptions.

### Scope — OUT (with backlog ticket paths where applicable)
- Do not implement real metrics for `Words this week`, `Mins saved`, or `WPM avg`. Locked decision `#1` sends that work to `plans/backlog/home-stats-metrics.md`.
- Do not invent click-through behavior from Home cards or recent rows unless a later main-session plan adds it.
- Do not widen `TranscriptReading` unless the current `recent(limit:)` / `all()` surface is proven insufficient and the change is called out explicitly in the commit hand-off.

### Acceptance tests — Tests/... — test name + what it asserts + mockup/doc clause it ties to
- `Tests/SeshatAppKitTests/MainWindow/HomeViewModelTests.swift` — `testLoadsTopThreeRecentTranscriptionsAndLiveRecordingsCount`; asserts the view model uses `recent(limit: 3)` for the feed and a live count for the `Recordings` card; ties to `plans/App UI design/Claude_Final_Bundle_Prompt.md:54-57`.
- `Tests/SeshatAppKitTests/MainWindow/HomeViewModelTests.swift` — `testStubMetricsRenderEmDashUntilBacklogIsDone`; asserts the three allowed stub cards render `—` and do not fabricate computed numbers; ties to locked decision `#1`.
- `Tests/SeshatAppKitTests/MainWindow/HomeTabViewTests.swift` — `testEmptyStateAppearsWhenNoTranscriptionsExist`; asserts the empty-state copy and icon gate on an empty transcript list; ties to `screen_home.png`.
- `Tests/SeshatAppKitTests/ManualUnifiedWindowVerification.md` — add `MV-UW-H1`, `MV-UW-H2`, and `MV-UW-H3` for the stat cards, recent list, and empty state; ties to `screen_home.png`.

### Validation checklist (implementer ticks box-by-box in hand-off)
- [ ] `screen_home.png` header text is exactly `Home` with the same top-left placement in the detail column.
- [ ] `screen_home.png` card order is `Words this week`, `Recordings`, `Mins saved`, `WPM avg`.
- [ ] `plans/App UI design/Claude_Final_Bundle_Prompt.md:54-57` and `plans/App UI design/Seshat UI Polish & Unified Window Implementation.md:54-57` are implemented literally before any optional embellishment is considered.
- [ ] Locked decision `#1` is honored: `Recordings` is computed live, while `Words this week`, `Mins saved`, and `WPM avg` render `—` placeholders and point at `plans/backlog/home-stats-metrics.md`.
- [ ] `screen_home.png` recent section heading is `RECENT TRANSCRIPTIONS` with the divider immediately below it.
- [ ] `screen_home.png` empty state shows the centered quill treatment and the two-line `No transcriptions yet` / `Press ⌥⌥ to start recording` copy.
- [ ] Diff against this step shows no silent divergence; every modified file is listed above, and any proposed deviation is recorded in the commit message comment and hand-off report.
- [ ] No `Color(hex:` outside `Theme/*` (hard rule — long-standing).
- [ ] No `UserDefaults.standard.*` direct reads — typed resolvers only.
- [ ] No `type`/`kind`/`intent` field added (hard rule — Phase 3 design lock: `project_phase3_notes_equals_history.md`).
- [ ] `swift build --build-tests` green from the main-repo path.
- [ ] No files outside `Files touched` modified.

### Commit style — `trunk: phase 2.4: <verb-led subject>`. Test + fix in same commit.
Use 2-4 commits if needed. Prefix every commit with `trunk: phase 2.4:`. Recommended close-out subject: `trunk: phase 2.4: ship the Home tab with allowed metric stubs`.

### Hand-off report template
```md
Phase 2.4 hand-off
- Commit(s): <sha list>
- Live data on Home: <list>
- Stub metrics/backlogs: <list>
- Tests added/updated: <list>
- Verification commands: <list>
- Deviations from plan: none | <required explicit note>
- Follow-ups / blockers: none | <list>
```

## Step 2.5 — Build the Transcriptions tab [BLOCKED: Q.M6]
> Do NOT diverge from this plan or the Manus mockups. Silent divergence is the cardinal sin. To deviate, surface the proposed divergence in a comment in the commit message AND in the hand-off report; wait for main-session confirmation. Paraphrasing the contract is divergence. Renaming variables the plan specifies is divergence. Choosing a different animation curve than the mockup implies is divergence.

### Files touched (exhaustive) — path:line-range — what changes
- `Sources/SeshatAppKit/MainWindow/MainWindowView.swift:new file from Step 2.3` — replace the Transcriptions placeholder with the real tab.
- `Sources/SeshatAppKit/MainWindow/Transcriptions/TranscriptionsViewModel.swift:new file` — own grouped transcript loading and search behavior for the unified tab.
- `Sources/SeshatAppKit/MainWindow/Transcriptions/TranscriptionsTabView.swift:new file` — render the header, full-width search field, grouped day sections, and row selection behavior chosen by Q.M6.
- `Sources/SeshatCore/TranscriptReader.swift:3-42` — extend only if the Q.M6-approved interaction requires a small helper that the current protocol cannot express; otherwise keep this file unchanged and document that choice in the hand-off.
- `Sources/SeshatAppKit/Notes/NotesViewModel.swift:6-65` and `Sources/SeshatAppKit/Notes/NotesSidebar.swift:4-109` — extract or retire row-formatting helpers if the unified tab reuses them.
- `Tests/SeshatAppKitTests/MainWindow/TranscriptionsViewModelTests.swift:new file` — pin grouping, searching, and any Q.M6-approved interaction model.
- `Tests/SeshatAppKitTests/MainWindow/TranscriptionsTabViewTests.swift:new file` — pin empty state and basic row rendering.
- `Tests/SeshatAppKitTests/Notes/NotesViewModelTests.swift:7-128` — update or delete tests only if helper extraction changes those types.
- `Tests/SeshatAppKitTests/ManualUnifiedWindowVerification.md:new file from Step 2.3` — extend the runbook with Transcriptions-tab checks.

### Scope — IN
- Do not start implementation until main session answers Q.M6 in writing.
- After Q.M6 is answered, build the `Transcriptions` tab to match `plans/App UI design/Claude_Final_Bundle_Prompt.md:59-63` and `screen_transcriptions.png`.
- Reuse the existing search/read surface where possible. This tab is a UI migration, not a new storage engine.
- Keep the surface read-only unless the explicit Q.M6 answer adds editing or deletion behavior.

### Scope — OUT (with backlog ticket paths where applicable)
- Do not resolve Q.M6 yourself. The unresolved parts are: row tap behavior, inline editor vs separate editor, delete affordance, and any mode-badge/filtering behavior.
- Do not add new transcript metadata fields speculatively. Trunk `TranscriptEntry` at `Sources/SeshatCore/TranscriptStore.swift:3-23` has no mode metadata today; any new field requires main-session approval and must still respect the no-`type`/`kind`/`intent` hard rule.
- Do not delete the legacy Notes window/files yet. That is Step 2.10 after the unified tab is live.

### Acceptance tests — Tests/... — test name + what it asserts + mockup/doc clause it ties to
- `Tests/SeshatAppKitTests/MainWindow/TranscriptionsViewModelTests.swift` — `testSearchUsesTranscriptReaderAndGroupsResultsByRelativeDay`; asserts the unified tab groups rows into day buckets and reuses transcript search; ties to `plans/App UI design/Claude_Final_Bundle_Prompt.md:59-63`.
- `Tests/SeshatAppKitTests/MainWindow/TranscriptionsTabViewTests.swift` — `testEmptyStateMatchesUnifiedShellWhenNoEntriesExist`; asserts the unified tab has a stable empty-state rendering when the store is empty; ties to `screen_transcriptions.png`.
- `Tests/SeshatAppKitTests/MainWindow/TranscriptionsViewModelTests.swift` — `testRowInteractionMatchesMainSessionAnswerForQM6`; asserts the final row-tap/delete/editor behavior matches the written Q.M6 answer rather than implementer invention.
- `Tests/SeshatAppKitTests/ManualUnifiedWindowVerification.md` — add `MV-UW-T1`, `MV-UW-T2`, and `MV-UW-T3` for search, grouping, and the Q.M6-selected interaction; ties to `screen_transcriptions.png`.

### Validation checklist (implementer ticks box-by-box in hand-off)
- [ ] Main session answered Q.M6 in writing and the exact answer is quoted in the step hand-off before coding began.
- [ ] `screen_transcriptions.png` header text is exactly `Transcriptions`.
- [ ] `screen_transcriptions.png` search field is full-width and uses the placeholder copy `Search transcriptions...`.
- [ ] `screen_transcriptions.png` list grouping uses uppercase day headings such as `TODAY` and `YESTERDAY`.
- [ ] `screen_transcriptions.png` rows show timestamp plus truncated transcript text, and any badge/editor/delete behavior matches the written Q.M6 answer exactly.
- [ ] `plans/App UI design/Claude_Final_Bundle_Prompt.md:59-63` and `plans/App UI design/Seshat UI Polish & Unified Window Implementation.md:59-63` are both satisfied with no extra interaction invented.
- [ ] No new `type`/`kind`/`intent` field was introduced in transcript storage; if Q.M6 required additional metadata, the main-session-approved source is cited explicitly in the hand-off.
- [ ] Diff against this step shows no silent divergence; every modified file is listed above, and any proposed deviation is recorded in the commit message comment and hand-off report.
- [ ] No `Color(hex:` outside `Theme/*` (hard rule — long-standing).
- [ ] No `UserDefaults.standard.*` direct reads — typed resolvers only.
- [ ] No `type`/`kind`/`intent` field added (hard rule — Phase 3 design lock: `project_phase3_notes_equals_history.md`).
- [ ] `swift build --build-tests` green from the main-repo path.
- [ ] No files outside `Files touched` modified.

### Commit style — `trunk: phase 2.5: <verb-led subject>`. Test + fix in same commit.
No implementation commits until Q.M6 is answered. After unblock, use 2-4 commits if needed, each prefixed `trunk: phase 2.5:`. Recommended close-out subject: `trunk: phase 2.5: migrate history into the unified Transcriptions tab`.

### Hand-off report template
```md
Phase 2.5 hand-off
- Status: blocked until Q.M6 | completed
- Q.M6 answer used: <quote>
- Commit(s): <sha list or none>
- Interaction model shipped: <summary>
- Tests added/updated: <list>
- Verification commands: <list>
- Deviations from plan: none | <required explicit note>
- Follow-ups / blockers: none | <list>
```

## Step 2.6 — Build the Modes tab and persisted CRUD scaffold [BLOCKED: Q.M5]
> Do NOT diverge from this plan or the Manus mockups. Silent divergence is the cardinal sin. To deviate, surface the proposed divergence in a comment in the commit message AND in the hand-off report; wait for main-session confirmation. Paraphrasing the contract is divergence. Renaming variables the plan specifies is divergence. Choosing a different animation curve than the mockup implies is divergence.

### Files touched (exhaustive) — path:line-range — what changes
- `Sources/SeshatCore/ModeDescriptor.swift:3-39` — replace the static single-mode-only registry surface with a persisted multi-mode model that can still seed Dictation by default.
- `Sources/SeshatCore/Config.swift:47-49` — use the reserved `modes` directory if the persisted store needs a filesystem home.
- `Sources/SeshatAppKit/MainWindow/MainWindowView.swift:new file from Step 2.3` — replace the Modes placeholder with the real tab.
- `Sources/SeshatAppKit/MainWindow/Modes/ModesViewModel.swift:new file` — own the mode list, seed behavior, and CRUD operations chosen by Q.M5.
- `Sources/SeshatAppKit/MainWindow/Modes/ModesTabView.swift:new file` — render the Manus card list, active indicator, and `+ New Mode` affordance.
- `Sources/SeshatAppKit/MainWindow/Modes/ModeEditorSheet.swift:new file` — render the Q.M5-approved create/edit flow.
- `Sources/SeshatAppKit/Components/ModeCard.swift:4-122` — restyle the reusable card so it matches `screen_modes.png` and the final active/inactive actions.
- `Sources/SeshatAppKit/Settings/ModesTab.swift:5-44` — remove any temporary dependency on the legacy read-only settings tab once the unified tab owns this surface.
- `Tests/SeshatCoreTests/ModeDescriptorTests.swift:5-15` — update or replace the old one-mode assertions.
- `Tests/SeshatCoreTests/ModeStoreTests.swift:new file` — pin seed/default/persistence behavior for the new multi-mode data model.
- `Tests/SeshatAppKitTests/MainWindow/ModesViewModelTests.swift:new file` — pin the Q.M5-approved CRUD behavior.
- `Tests/SeshatAppKitTests/ManualUnifiedWindowVerification.md:new file from Step 2.3` — extend the runbook with Modes-tab checks.

### Scope — IN
- Do not start implementation until main session answers Q.M5 in writing.
- After Q.M5 is answered, build the Modes tab UI and the persisted data model together. The UI cannot stay read-only after this step.
- Seed exactly one default mode on first launch: Dictation, active by default.
- Make the stored data model capable of multiple modes immediately, even though the default install only seeds Dictation.

### Scope — OUT (with backlog ticket paths where applicable)
- Do not resolve Q.M5 yourself. The unresolved parts are: the new-mode dialog fields, single-active vs multi-active semantics, and the delete affordance.
- Do not ship built-in Command or Notes cards just because `screen_modes.png` shows them. Locked decision `#1` overrides the mockup count: this phase seeds only Dictation until the user creates more.
- Do not delete the legacy settings `ModesTab` or old tests until the unified tab is proven live and cleanup reaches Step 2.10.

### Acceptance tests — Tests/... — test name + what it asserts + mockup/doc clause it ties to
- `Tests/SeshatCoreTests/ModeStoreTests.swift` — `testSeededStoreContainsSingleActiveDictationMode`; asserts first launch seeds one active Dictation mode and no other built-ins; ties to locked decision `#1`.
- `Tests/SeshatAppKitTests/MainWindow/ModesViewModelTests.swift` — `testCreateEditDeleteFlowMatchesQm5Answer`; asserts the create/edit/delete behavior and active-state semantics match the written Q.M5 answer; ties to `screen_modes.png`.
- `Tests/SeshatAppKitTests/MainWindow/ModesViewModelTests.swift` — `testPersistedDataModelSupportsMultipleModes`; asserts the backing store can hold more than one mode immediately; ties to locked decision `#1`.
- `Tests/SeshatAppKitTests/ManualUnifiedWindowVerification.md` — add `MV-UW-M1`, `MV-UW-M2`, and `MV-UW-M3` for card layout, active state, and create/edit/delete flow; ties to `screen_modes.png`.

### Validation checklist (implementer ticks box-by-box in hand-off)
- [ ] Main session answered Q.M5 in writing and the exact answer is quoted in the step hand-off before coding began.
- [ ] `screen_modes.png` header text is exactly `Modes`.
- [ ] `plans/App UI design/Claude_Final_Bundle_Prompt.md:64-67` and `plans/App UI design/Seshat UI Polish & Unified Window Implementation.md:64-67` are implemented literally everywhere the written spec is more specific than the mockup.
- [ ] `screen_modes.png` card chrome, active-state green indicator, and bottom `+ New Mode` affordance are matched.
- [ ] Locked decision `#1` is honored: first launch seeds exactly one mode (`Dictation`), active by default, even though the data model now supports multiple modes.
- [ ] Locked decision `#1` is honored: Command/Notes do not ship as built-in cards unless main session explicitly changes the lock.
- [ ] The create/edit/delete flow, active-state semantics, and dialog fields match the written Q.M5 answer exactly.
- [ ] Diff against this step shows no silent divergence; every modified file is listed above, and any proposed deviation is recorded in the commit message comment and hand-off report.
- [ ] No `Color(hex:` outside `Theme/*` (hard rule — long-standing).
- [ ] No `UserDefaults.standard.*` direct reads — typed resolvers only.
- [ ] No `type`/`kind`/`intent` field added (hard rule — Phase 3 design lock: `project_phase3_notes_equals_history.md`).
- [ ] `swift build --build-tests` green from the main-repo path.
- [ ] No files outside `Files touched` modified.

### Commit style — `trunk: phase 2.6: <verb-led subject>`. Test + fix in same commit.
No implementation commits until Q.M5 is answered. After unblock, use 3-5 commits if needed, each prefixed `trunk: phase 2.6:`. Recommended close-out subject: `trunk: phase 2.6: ship the persisted Modes tab CRUD scaffold`.

### Hand-off report template
```md
Phase 2.6 hand-off
- Status: blocked until Q.M5 | completed
- Q.M5 answer used: <quote>
- Commit(s): <sha list or none>
- Seed behavior shipped: <summary>
- CRUD behavior shipped: <summary>
- Tests added/updated: <list>
- Verification commands: <list>
- Deviations from plan: none | <required explicit note>
- Follow-ups / blockers: none | <list>
```

## Step 2.7 — Consolidate Settings into General / Permissions / About [BLOCKED: Q.M1] [BLOCKED: Q.M2] [BLOCKED: Q.M3] [BLOCKED: Q.M4]
> Do NOT diverge from this plan or the Manus mockups. Silent divergence is the cardinal sin. To deviate, surface the proposed divergence in a comment in the commit message AND in the hand-off report; wait for main-session confirmation. Paraphrasing the contract is divergence. Renaming variables the plan specifies is divergence. Choosing a different animation curve than the mockup implies is divergence.

### Files touched (exhaustive) — path:line-range — what changes
- `Sources/SeshatAppKit/MainWindow/MainWindowView.swift:new file from Step 2.3` — replace the Settings placeholder with the final consolidated settings surface.
- `Sources/SeshatAppKit/MainWindow/Settings/SettingsSubtab.swift:new file` — define the `General`, `Permissions`, and `About` subtab enum.
- `Sources/SeshatAppKit/MainWindow/Settings/SettingsTabView.swift:new file` — render the shared settings container and subtab picker.
- `Sources/SeshatAppKit/MainWindow/Settings/GeneralTabView.swift:new file` — render the consolidated General subtab.
- `Sources/SeshatAppKit/MainWindow/Settings/PermissionsTabView.swift:new file` — render the unified permission rows using the Phase 1 permission service.
- `Sources/SeshatAppKit/MainWindow/Settings/AboutTabView.swift:new file` — render the Q.M3-approved About content.
- `Sources/SeshatAppKit/MainWindow/Settings/PillStylePickerView.swift:new file` — render the `Classic / Mini / None` style controls and previews.
- `Sources/SeshatAppKit/Settings/SettingsView.swift:4-201`, `Sources/SeshatAppKit/Settings/GeneralTab.swift:5-222`, `Sources/SeshatAppKit/Settings/AIModelsTab.swift:5-49`, `Sources/SeshatAppKit/Settings/ShortcutsTab.swift:5-122`, `Sources/SeshatAppKit/Settings/AdvancedTab.swift:6-187`, `Sources/SeshatAppKit/Settings/HotkeyRecorder.swift:1-410` — source surfaces for the existing controls/content that must be moved, merged, or retired.
- `Tests/SeshatAppKitTests/Settings/GeneralTabViewModelTests.swift:15-85` — migrate existing visibility/persistence tests to the new settings owner.
- `Tests/SeshatAppKitTests/Settings/AdvancedTabViewModelTests.swift:8-98` and `Tests/SeshatAppKitTests/Settings/HotkeyRecorderTests.swift:16-119` — keep these green only if the relevant controls survive in the Q.M1-approved mapping.
- `Tests/SeshatAppKitTests/MainWindow/SettingsViewModelTests.swift:new file` — pin the consolidated settings behavior and persistence mapping.
- `Tests/SeshatAppKitTests/MainWindow/PermissionsTabViewTests.swift:new file` — pin the unified permission-row rendering and button wiring.
- `Tests/SeshatAppKitTests/ManualUnifiedWindowVerification.md:new file from Step 2.3` — extend the runbook with General / Permissions / About validation.

### Scope — IN
- Do not start implementation until main session answers Q.M1, Q.M2, Q.M3, and Q.M4 in writing.
- After unblock, ship the unified `Settings` tab with exactly three subtabs: `General`, `Permissions`, `About`.
- `General` must include `Window tint`, `Pill theme`, the `Classic / Mini / None` style row, and the existing settings controls mapped per the Q.M1/Q.M2 answers.
- `Permissions` must replace the standalone onboarding permission surface and use the Phase 1 permission service for live status and `Grant Access` actions.
- `About` must ship the exact content main session chooses in Q.M3; do not improvise a build/version/log-export layout.

### Scope — OUT (with backlog ticket paths where applicable)
- Do not resolve Q.M1/Q.M2/Q.M3/Q.M4 yourself.
- Do not give `Launch at login` or `Show in Dock` any production effect. Locked decision `#1` limits them to persisted UI state only and sends follow-up behavior to `plans/backlog/launch-at-login-and-dock.md`.
- Do not render `Check for Updates` here as a substitute for the omitted menu row. That remains out of scope in `plans/backlog/check-for-updates-sparkle.md`.
- Do not collapse Pill Style and Pill Visibility into one control, regardless of the final subtab ownership. Locked decision `#2` forbids that simplification.

### Acceptance tests — Tests/... — test name + what it asserts + mockup/doc clause it ties to
- `Tests/SeshatAppKitTests/MainWindow/SettingsViewModelTests.swift` — `testWindowTintAndPillAppearancePersistThroughTypedResolvers`; asserts the settings UI uses `WindowTint` and `PillAppearance` typed resolvers rather than ad hoc storage; ties to `plans/App UI design/SeshatTheme.swift:13-33,85-117`.
- `Tests/SeshatAppKitTests/MainWindow/PermissionsTabViewTests.swift` — `testMissingPermissionRowsShowRequiredStatusAndGrantAccessAction`; asserts missing permissions show the orange required dot and blue button; ties to `plans/App UI design/Claude_Final_Bundle_Prompt.md:75-76` and `final_settings_permissions_v2.png`.
- `Tests/SeshatAppKitTests/MainWindow/SettingsViewModelTests.swift` — `testPillStyleAndVisibilityRemainOrthogonalControls`; asserts the UI keeps separate state for Style and Visibility; ties to locked decision `#2`.
- `Tests/SeshatAppKitTests/MainWindow/SettingsViewModelTests.swift` — `testPasteModeCopyUsesSimulateKeypressesWithoutRenamingBackendEnum`; asserts the UI label changes while the backend storage stays `PasteMode.pasteAtCursor`; ties to locked decision `#4`.
- `Tests/SeshatAppKitTests/ManualUnifiedWindowVerification.md` — add `MV-UW-S1` through `MV-UW-S6` for the subtab picker, style previews, permission rows, and the Q.M3-approved About content; ties to `final_settings_general_v2.png`, `final_settings_permissions_v2.png`, and `screen_pill_appearance.png`.

### Validation checklist (implementer ticks box-by-box in hand-off)
- [ ] Main session answered Q.M1, Q.M2, Q.M3, and Q.M4 in writing and the exact answers are quoted in the step hand-off before coding began.
- [ ] `final_settings_general_v2.png` subtab picker contains exactly `General`, `Permissions`, and `About`.
- [ ] `final_settings_general_v2.png` recording-window style row shows `Classic`, `Mini`, and `None`, and the `Mini` visual matches the written Q.M4 answer exactly.
- [ ] `screen_pill_appearance.png` dark / light / system cards are live SwiftUI previews driven by `PillAppearance`, matching `plans/App UI design/Claude_Final_Bundle_Prompt.md:71-75` instead of static images.
- [ ] `final_settings_general_v2.png` `Window tint` and `Pill theme` segmented controls persist through `WindowTint` and `PillAppearance` typed resolvers.
- [ ] `final_settings_permissions_v2.png` permission rows show live status dots and blue `Grant Access` buttons wired to the Phase 1 permission service.
- [ ] Locked decision `#2` is honored: Pill Style and Pill Visibility remain separate controls even after Q.M1/Q.M2 decide where they live.
- [ ] Locked decision `#4` is honored: the UI copy says `Simulate Keypresses` for backend value `PasteMode.pasteAtCursor`.
- [ ] Locked decision `#1` is honored: `Launch at login` and `Show in Dock` render and persist only, with follow-up behavior explicitly cited to `plans/backlog/launch-at-login-and-dock.md`.
- [ ] Diff against this step shows no silent divergence; every modified file is listed above, and any proposed deviation is recorded in the commit message comment and hand-off report.
- [ ] No `Color(hex:` outside `Theme/*` (hard rule — long-standing).
- [ ] No `UserDefaults.standard.*` direct reads — typed resolvers only.
- [ ] No `type`/`kind`/`intent` field added (hard rule — Phase 3 design lock: `project_phase3_notes_equals_history.md`).
- [ ] `swift build --build-tests` green from the main-repo path.
- [ ] No files outside `Files touched` modified.

### Commit style — `trunk: phase 2.7: <verb-led subject>`. Test + fix in same commit.
No implementation commits until Q.M1/Q.M2/Q.M3/Q.M4 are answered. After unblock, use 4-6 commits if needed, each prefixed `trunk: phase 2.7:`. Recommended close-out subject: `trunk: phase 2.7: consolidate settings into the unified General/Permissions/About tabs`.

### Hand-off report template
```md
Phase 2.7 hand-off
- Status: blocked until Q.M1/Q.M2/Q.M3/Q.M4 | completed
- Manus answers used:
  - Q.M1: <quote>
  - Q.M2: <quote>
  - Q.M3: <quote>
  - Q.M4: <quote>
- Commit(s): <sha list or none>
- Control mapping shipped: <summary>
- Persisted-only toggles/backlogs: <list>
- Tests added/updated: <list>
- Verification commands: <list>
- Deviations from plan: none | <required explicit note>
- Follow-ups / blockers: none | <list>
```

## Step 2.8 — Drop onboarding routing and make the unified window authoritative
> Do NOT diverge from this plan or the Manus mockups. Silent divergence is the cardinal sin. To deviate, surface the proposed divergence in a comment in the commit message AND in the hand-off report; wait for main-session confirmation. Paraphrasing the contract is divergence. Renaming variables the plan specifies is divergence. Choosing a different animation curve than the mockup implies is divergence.

### Files touched (exhaustive) — path:line-range — what changes
- `Sources/SeshatAppKit/Composition/AppMain.swift:7-259` (trunk source `Sources/SeshatAppKit/Composition/SeshatAppMain.swift:7-259`) — remove standalone onboarding-window routing, route missing-permission remediation to the unified window, and make the main window host the authoritative `Home` / `Settings` surface.
- `Sources/SeshatAppKit/MenuBar/StatusItemController.swift:29-268` — route `Settings` to unified-window `.settings` and keep `Home` routed to unified-window `.home`.
- `Sources/SeshatAppKit/MenuBar/MenuBarSceneModel.swift:7-151` — remove any onboarding fallback hooks and replace them with unified-window route signals where needed.
- `Sources/SeshatAppKit/SeshatApp.swift:12-53` — keep the injectable shell compiling if the app entry surface changes with the new route owner.
- `Tests/SeshatAppKitTests/AppEntryPointTests.swift:8-82` — prove the entry point no longer constructs or depends on the onboarding window.
- `Tests/SeshatAppKitTests/MenuBarFlowIntegrationTests.swift:17-207` — prove missing-permission flows and menu actions now target the unified window.
- `Tests/SeshatAppKitTests/MenuBarSceneModelTests.swift:11-674` — replace old onboarding-fallback expectations with unified-window routing assertions.
- `Tests/SeshatAppKitTests/ManualUnifiedWindowVerification.md:new file from Step 2.3` — extend the runbook with route verification.

### Scope — IN
- Make the unified window the single runtime surface for `Home` and `Settings`.
- Replace the old onboarding window as the permissions-remediation destination. Missing permissions now land in `Settings > Permissions`.
- Remove the app-entry gating that prevented access to Notes/Settings/menu actions until onboarding completion.
- Preserve the Phase 1 permission-service behavior: the app can still run with missing Accessibility and must continue to fall back to clipboard when AX is absent.

### Scope — OUT (with backlog ticket paths where applicable)
- Do not delete the onboarding files in this step. Remove runtime use now; delete the dead files in Step 2.10.
- Do not remove any legacy tests or runbooks until the cleanup step proves the new routes are authoritative.
- Do not reintroduce a different first-launch gating mechanism. The replacement surface is the unified window, not a new modal.

### Acceptance tests — Tests/... — test name + what it asserts + mockup/doc clause it ties to
- `Tests/SeshatAppKitTests/AppEntryPointTests.swift` — `testColdLaunchRoutesToUnifiedWindowWithoutConstructingOnboarding`; asserts app entry no longer depends on `OnboardingWindowController`; ties to `plans/App UI design/Claude_Final_Bundle_Prompt.md:68-76,93-100`.
- `Tests/SeshatAppKitTests/MenuBarFlowIntegrationTests.swift` — `testMissingPermissionsOpenUnifiedSettingsPermissionsTab`; asserts remediation targets the unified settings permissions route; ties to `final_settings_permissions_v2.png`.
- `Tests/SeshatAppKitTests/MenuBarSceneModelTests.swift` — `testMenuActionsUseUnifiedWindowRoutesRatherThanOnboardingFallback`; asserts the menu bar no longer signals onboarding fallback actions.
- `Tests/SeshatAppKitTests/ManualUnifiedWindowVerification.md` — add `MV-UW-R1`, `MV-UW-R2`, and `MV-UW-R3` for launch, menu, and permission-remediation routing; ties to `screen_home.png` and `final_settings_permissions_v2.png`.

### Validation checklist (implementer ticks box-by-box in hand-off)
- [ ] `screen_home.png` is reachable from the menu bar without any onboarding gate.
- [ ] `final_settings_permissions_v2.png` is the only missing-permission remediation surface after this step; the standalone onboarding window is no longer part of runtime routing.
- [ ] `plans/App UI design/Claude_Final_Bundle_Prompt.md:68-76,93-100` is honored literally: the unified Settings > Permissions tab replaces the standalone onboarding surface.
- [ ] Locked decision `#8` remains intact after the route move: Accessibility is optional and clipboard fallback still works when AX is absent.
- [ ] No new runtime path consults `OnboardingState` or `areCriticalPermissionsGranted` before showing `Home` or `Settings`.
- [ ] Diff against this step shows no silent divergence; every modified file is listed above, and any proposed deviation is recorded in the commit message comment and hand-off report.
- [ ] No `Color(hex:` outside `Theme/*` (hard rule — long-standing).
- [ ] No `UserDefaults.standard.*` direct reads — typed resolvers only.
- [ ] No `type`/`kind`/`intent` field added (hard rule — Phase 3 design lock: `project_phase3_notes_equals_history.md`).
- [ ] `swift build --build-tests` green from the main-repo path.
- [ ] No files outside `Files touched` modified.

### Commit style — `trunk: phase 2.8: <verb-led subject>`. Test + fix in same commit.
Use 2-4 commits if needed. Prefix every commit with `trunk: phase 2.8:`. Recommended close-out subject: `trunk: phase 2.8: make the unified window the only routing surface`.

### Hand-off report template
```md
Phase 2.8 hand-off
- Commit(s): <sha list>
- Unified routes now authoritative: <list>
- Legacy runtime routes removed: <list>
- Tests added/updated: <list>
- Verification commands: <list>
- Deviations from plan: none | <required explicit note>
- Follow-ups / blockers: none | <list>
```

## Step 2.9 — Pill polish: Manus sine wave, verified border clip, ResponseCard scaffold only
> Do NOT diverge from this plan or the Manus mockups. Silent divergence is the cardinal sin. To deviate, surface the proposed divergence in a comment in the commit message AND in the hand-off report; wait for main-session confirmation. Paraphrasing the contract is divergence. Renaming variables the plan specifies is divergence. Choosing a different animation curve than the mockup implies is divergence.

### Files touched (exhaustive) — path:line-range — what changes
- `Sources/SeshatAppKit/Components/SineWaveView.swift:1-103` — change the current timing/animation implementation so it matches the Manus sine-wave contract exactly.
- `Sources/SeshatAppKit/Overlay/PillOverlayView.swift:29-311` — keep the pill text-free during recording/response-card scenarios, and verify the root-view clip/shadow order still matches the Manus border-fix contract.
- `Sources/SeshatAppKit/Overlay/PillOverlayPresenter.swift:175-318` — keep `ResponseCard` as a separate floating panel, add an explicit harness path if needed, and remove the clipboard-only production consumer from live app flow.
- `Sources/SeshatAppKit/Overlay/ResponseCard.swift:1-172` — keep the separate panel anchored above the pill with an 8pt gap and 6s auto-dismiss, but ensure it is scaffold-only this phase.
- `Sources/SeshatAppKit/Components/ResponseCardView.swift:1-91` — keep the card styling aligned with the new theme/pill appearance.
- `Sources/SeshatAppKit/Overlay/PillOverlayController.swift:20-117` — adjust only if the presenter/harness wiring changes.
- `Sources/SeshatAppKit/Composition/AppMain.swift:51-110` (trunk source `Sources/SeshatAppKit/Composition/SeshatAppMain.swift:51-110`) — remove the clipboard-only response-card hook from production composition.
- `Sources/SeshatAppKit/MenuBar/MenuBarSceneModel.swift:135-144` — remove any production callback that still drives the response card from clipboard-only routing.
- `Tests/SeshatAppKitTests/Components/SineWaveViewTests.swift:new file` — pin the Manus animation timing and phase math.
- `Tests/SeshatAppKitTests/PillOverlayPresenterTests.swift:8-302` — replace clipboard-only response-card assertions with scaffold/harness assertions.
- `Tests/SeshatAppKitTests/PillOverlayViewModelTests.swift:8-293` — keep visibility mapping green after the pill polish work.
- `Tests/SeshatAppKitTests/MenuBarSceneModelTests.swift:264-323` — update clipboard-only tests so they no longer expect the response card from a production path.
- `Tests/SeshatAppKitTests/ManualPillOverlayVerification.md:1-118` — rewrite the runbook for the Manus sine wave and scaffold-only ResponseCard.

### Scope — IN
- Match `plans/App UI design/Claude_Final_Bundle_Prompt.md:77-90` exactly for the pill surface.
- Keep `ResponseCard` as a separate panel above the pill, with a single `show(text:)`-style entry point and a visible harness/preview/manual test path.
- Remove the current clipboard-only production consumer. Locked decision `#5` forbids a live caller this phase.
- Preserve the already-correct panel/root-view border-fix settings and explicitly test that they are not regressed.

### Scope — OUT (with backlog ticket paths where applicable)
- No Command Mode or any other production response-card consumer in this phase. That wiring is deferred until a later phase beyond this plan set.
- Do not move the response text inside the pill. The card stays a separate panel permanently.
- Do not alter `AVAudioCaptureService` or any other audio-permission behavior while doing pill work.

### Acceptance tests — Tests/... — test name + what it asserts + mockup/doc clause it ties to
- `Tests/SeshatAppKitTests/Components/SineWaveViewTests.swift` — `testPhaseLoopsZeroToTwoPiOverOneSecond`; asserts the wave timing matches the Manus `1.0s` contract rather than the current 1.2s approximation; ties to `plans/App UI design/Claude_Final_Bundle_Prompt.md:81-83`.
- `Tests/SeshatAppKitTests/PillOverlayPresenterTests.swift` — `testResponseCardAnchorsEightPointsAbovePillAndAutoDismissesAfterSixSeconds`; asserts the card remains a separate panel with the required gap and dismiss timing; ties to `plans/App UI design/Claude_Final_Bundle_Prompt.md:87-90`.
- `Tests/SeshatAppKitTests/PillOverlayPresenterTests.swift` — `testPhaseTwoHasNoProductionResponseCardConsumer`; asserts the clipboard-only flow no longer invokes `ResponseCard`; ties to locked decision `#5`.
- `Tests/SeshatAppKitTests/ManualPillOverlayVerification.md` — replace the old clipboard-only notice checks with Manus sine-wave and harness-only ResponseCard checks; ties to `plans/App UI design/Claude_Final_Bundle_Prompt.md:77-90`.

### Validation checklist (implementer ticks box-by-box in hand-off)
- [ ] `plans/App UI design/Claude_Final_Bundle_Prompt.md:81-83` is honored literally: the recording pill uses a phase-animated sine wave with a 1.0-second linear loop from `0` to `2π`; the current 1.2-second approximation is removed unless main session explicitly approves divergence.
- [ ] `plans/App UI design/Claude_Final_Bundle_Prompt.md:84-86` is still honored literally: `panel.hasShadow = false`, `panel.backgroundColor = .clear`, `panel.isOpaque = false`, and the SwiftUI root view clips before shadowing.
- [ ] `plans/App UI design/Claude_Final_Bundle_Prompt.md:87-90` is honored literally: `ResponseCard` is a separate panel above the pill with an 8pt gap, 6s auto-dismiss, and no response text inside the pill.
- [ ] `screen_pill_appearance.png` preview cards still reflect the actual dark / light / system pill chrome after the rendering updates.
- [ ] Locked decision `#5` is honored: no production flow calls `ResponseCard.show(...)`; only a harness/preview/manual-verification path exercises it.
- [ ] Diff against this step shows no silent divergence; every modified file is listed above, and any proposed deviation is recorded in the commit message comment and hand-off report.
- [ ] No `Color(hex:` outside `Theme/*` (hard rule — long-standing).
- [ ] No `UserDefaults.standard.*` direct reads — typed resolvers only.
- [ ] No `type`/`kind`/`intent` field added (hard rule — Phase 3 design lock: `project_phase3_notes_equals_history.md`).
- [ ] `swift build --build-tests` green from the main-repo path.
- [ ] No files outside `Files touched` modified.

### Commit style — `trunk: phase 2.9: <verb-led subject>`. Test + fix in same commit.
Use 2-4 commits if needed. Prefix every commit with `trunk: phase 2.9:`. Recommended close-out subject: `trunk: phase 2.9: finish the pill polish and leave ResponseCard scaffold-only`.

### Hand-off report template
```md
Phase 2.9 hand-off
- Commit(s): <sha list>
- Production ResponseCard callers remaining: none | <explicit list if this step diverged>
- Sine-wave timing shipped: <summary>
- Border-fix verification: <summary>
- Tests added/updated: <list>
- Verification commands: <list>
- Deviations from plan: none | <required explicit note>
- Follow-ups / blockers: none | <list>
```

## Step 2.10 — Cleanup legacy windows, onboarding state, and old permission surfaces
> Do NOT diverge from this plan or the Manus mockups. Silent divergence is the cardinal sin. To deviate, surface the proposed divergence in a comment in the commit message AND in the hand-off report; wait for main-session confirmation. Paraphrasing the contract is divergence. Renaming variables the plan specifies is divergence. Choosing a different animation curve than the mockup implies is divergence.

### Files touched (exhaustive) — path:line-range — what changes
- `Sources/SeshatAppKit/Notes/NotesWindowController.swift:1-79` — delete once the unified Transcriptions tab is authoritative.
- `Sources/SeshatAppKit/Settings/SettingsWindowController.swift:1-69` — delete once the unified Settings tab is authoritative.
- `Sources/SeshatAppKit/Onboarding/OnboardingWindowController.swift:1-156` — delete once the unified Settings > Permissions route is authoritative.
- `Sources/SeshatCore/OnboardingState.swift:1-34` — delete once runtime no longer references onboarding completion.
- `Sources/SeshatCore/PermissionStatus.swift:1-44` — delete the legacy Input Monitoring-only domain/probe surface after the Phase 1 permission service has fully replaced it.
- `Sources/SeshatAppKit/MenuBar/MicrophonePermissionState.swift:1-8` — delete the legacy microphone-only enum.
- `Sources/SeshatAppKit/Permissions/AppKitMicrophonePermissionRequester.swift:1-57` — delete the legacy microphone requester.
- `Sources/SeshatAppKit/Onboarding/PermissionRequester.swift:1-63` — delete the onboarding-specific permission requester.
- `Sources/SeshatAppKit/Settings/SettingsView.swift:4-201`, `Sources/SeshatAppKit/Settings/GeneralTab.swift:5-222`, `Sources/SeshatAppKit/Settings/AIModelsTab.swift:5-49`, `Sources/SeshatAppKit/Settings/ShortcutsTab.swift:5-122`, `Sources/SeshatAppKit/Settings/AdvancedTab.swift:6-187`, `Sources/SeshatAppKit/Settings/ModesTab.swift:5-44` — delete the legacy window-backed settings surfaces once no callers remain, unless a specific helper was intentionally moved and is still imported by the unified window.
- `Sources/SeshatAppKit/Composition/AppMain.swift:7-259` — remove dead hosts, dead factories, and any leftover legacy routing.
- `Tests/SeshatAppKitTests/Notes/NotesWindowControllerTests.swift:7-42` and `Tests/SeshatAppKitTests/Settings/SettingsWindowControllerTests.swift:7-22` — delete or replace with unified-window coverage once the old windows are gone.
- `Tests/SeshatAppKitTests/ManualOnboardingVerification.md:1-25`, `Tests/SeshatAppKitTests/ManualSettingsVerification.md:1-23`, and `Tests/SeshatAppKitTests/ManualNotesVerification.md:1-29` — delete or replace these runbooks once the standalone surfaces are gone and `ManualUnifiedWindowVerification.md` is the only live runbook.
- `Tests/SeshatAppKitTests/AppEntryPointTests.swift:8-82`, `Tests/SeshatAppKitTests/MenuBarFlowIntegrationTests.swift:17-207`, and `Tests/SeshatAppKitTests/SeshatAppKitShellCompileTests.swift:1-38` — close the compile/runtime loop after the deletions.

### Scope — IN
- Delete the dead standalone windows and the legacy permission/onboarding support types only after Steps 2.5-2.9 are complete.
- Collapse tests and runbooks onto the unified-window surface so the repo no longer carries obsolete verification targets.
- Leave only one authoritative window surface for Home, Transcriptions, Modes, and Settings.
- Keep any intentionally extracted helper only if it is still referenced by live unified-window code after the deletions.

### Scope — OUT (with backlog ticket paths where applicable)
- Do not use this cleanup step as cover for unrelated refactors.
- Do not delete a helper that the unified window still imports; move it first, then delete the dead wrapper in the same step.
- Do not remove tests without replacing the behavior with unified-window coverage in the same commit series.

### Acceptance tests — Tests/... — test name + what it asserts + mockup/doc clause it ties to
- `Tests/SeshatAppKitTests/AppEntryPointTests.swift` — `testAppMainBuildsWithoutLegacyWindowHostsOrOnboardingState`; asserts app entry no longer references the deleted windows or onboarding state.
- `Tests/SeshatAppKitTests/MenuBarFlowIntegrationTests.swift` — `testHomeAndSettingsActionsUseUnifiedWindowOnly`; asserts menu actions no longer route to standalone windows.
- `Tests/SeshatAppKitTests/SeshatAppKitShellCompileTests.swift` — `testShellCompilesWithoutLegacyPermissionTypes`; asserts the compile surface no longer depends on `PermissionStatus`, `MicrophonePermissionState`, or the legacy requesters.
- `Tests/SeshatAppKitTests/ManualUnifiedWindowVerification.md` — final `MV-UW-E2E-1` through `MV-UW-E2E-4` entries prove the unified bundle matches `screen_home.png`, `screen_transcriptions.png`, `screen_modes.png`, `final_settings_general_v2.png`, and `final_settings_permissions_v2.png`.

### Validation checklist (implementer ticks box-by-box in hand-off)
- [ ] `screen_home.png`, `screen_transcriptions.png`, `screen_modes.png`, `final_settings_general_v2.png`, and `final_settings_permissions_v2.png` are all reachable from one unified window; no standalone Notes / Settings / Onboarding windows remain.
- [ ] `screen_menu.png` `Home` and `Settings` actions now target the unified window only.
- [ ] `plans/App UI design/Claude_Final_Bundle_Prompt.md:95-100` and `plans/App UI design/Seshat UI Polish & Unified Window Implementation.md:95-101` are satisfied in order: theme, menu, shell, content migration, permissions, pill polish, then cleanup.
- [ ] Phase 1.9’s deferred cleanup queue is empty: `PermissionStatus.swift`, `MicrophonePermissionState.swift`, `AppKitMicrophonePermissionRequester.swift`, and `Onboarding/PermissionRequester.swift` are deleted.
- [ ] Locked decision `#8` still holds after cleanup: Accessibility remains optional and no critical-permission gate was reintroduced.
- [ ] Any surviving helper extracted from a deleted window file is imported by live unified-window code; no dead wrappers or dead legacy filenames remain.
- [ ] Diff against this step shows no silent divergence; every modified file is listed above, and any proposed deviation is recorded in the commit message comment and hand-off report.
- [ ] No `Color(hex:` outside `Theme/*` (hard rule — long-standing).
- [ ] No `UserDefaults.standard.*` direct reads — typed resolvers only.
- [ ] No `type`/`kind`/`intent` field added (hard rule — Phase 3 design lock: `project_phase3_notes_equals_history.md`).
- [ ] `swift build --build-tests` green from the main-repo path.
- [ ] No files outside `Files touched` modified.

### Commit style — `trunk: phase 2.10: <verb-led subject>`. Test + fix in same commit.
Use 2-4 commits if needed. Prefix every commit with `trunk: phase 2.10:`. Recommended close-out subject: `trunk: phase 2.10: delete the legacy windows and permission leftovers`.

### Hand-off report template
```md
Phase 2.10 hand-off
- Commit(s): <sha list>
- Files deleted: <list>
- Legacy helpers retained intentionally: none | <list with current importers>
- Replacement tests/runbooks: <list>
- Verification commands: <list>
- Deviations from plan: none | <required explicit note>
- Follow-ups / blockers: none | <list>
```

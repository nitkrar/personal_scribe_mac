# Manual Settings Verification

- Opening via menu bar: with onboarding completed, click the status-item `Settings` row and confirm the `<AppBrand.displayName> Settings` window opens in front of the app.
- **MV-SETT-1 — All 5 tabs visible:** confirm `General`, `AI Models`, `Advanced`, `Permissions`, and `About` render and can each be selected from the tab strip.
- General-tab toggles persist across relaunch: change pill visibility, waveform decay, and paste mode, relaunch Ninimma, and confirm the three selections remain at their last chosen values.
- Both-hidden combination blocked with visible error state: hide the menu bar item, then try to set pill visibility to `Hidden`, and confirm the UI rejects the change with an inline explanation that one surface must remain visible.
- [ ] **MV-SETT-1** Open Settings. The segmented sub-tab picker (General / AI Models / Shortcuts / Advanced / Permissions) renders on a single line at the default window width (760pt). The redundant "Settings" largeTitle above the picker must NOT be present — window title bar + sidebar row already identify the tab.

## Clipboard restore delay

- Slider reflects current delay: open `General`, confirm the `Clipboard restore delay` control matches the current setting value, and confirm the helper text reads `After paste, wait Ns before restoring your clipboard` with the same value.
- Changing slider persists across relaunch: move the slider to a non-default value, quit and relaunch Ninimma, reopen `General`, and confirm the slider and helper text still show the chosen delay.
- `0.1s` fast restore: set the delay to `0.1s`, dictate into Slack, confirm the transcript pastes into the compose field, then press `Cmd+V` manually and confirm Slack pastes the clipboard content that existed before dictation.
- `5.0s` slow restore: set the delay to `5.0s`, dictate into Slack, wait after the initial paste, and confirm the clipboard remains the transcribed text for the full five-second window before the pre-paste clipboard is restored.

## RAM-aware default model (#016)

`DefaultModelSelectionPolicy` picks the fresh-install default voice
model based on `ProcessInfo.physicalMemory`. Machines below 10 GiB
(i.e. 8 GB Macs) get `parakeet-tdt-ctc-110m` (110M params, 407 MB);
everyone else gets `parakeet-tdt-0.6b-v2` (baseline). The probe is
only consulted when no `ActiveModelDescriptor` is persisted — once
the user has a saved selection, the probe is ignored forever.

Hard to verify on a single dev machine without swapping hardware —
these entries are guidance, not a literal checklist item.

- **MV-RAM-1 — 8 GB Mac fresh install:** on an 8 GB M-series Mac
  (or equivalent) with clean UserDefaults (`defaults delete
  com.nitkrar.personal_scribe ActiveModelDescriptor`), launch Ninimma.
  Open `Settings → AI Models`. `Parakeet TDT-CTC 110M` should show
  the `Active` chip; `Parakeet TDT 0.6B` should show `Not downloaded`
  or `Ready` but NOT `Active`.
- **MV-RAM-2 — 16+ GB Mac fresh install:** same flow on a 16 GB+
  Mac. `Parakeet TDT 0.6B` is the Active row; CTC-110M is inactive.
- **MV-RAM-3 — user choice wins after first launch:** from MV-RAM-1
  state, click `Set Active` on `Parakeet TDT 0.6B`. Confirm it flips
  to Active. Quit and relaunch. `Parakeet TDT 0.6B` stays Active —
  the RAM probe does NOT reassert CTC-110M on the 8 GB machine.

## First-run onboarding completion (#015)

`OnboardingCompletionObserver` watches the PermissionService and
flips the `OnboardingCompleted` UserDefault to `true` the first time
Microphone + Input Monitoring are both `.granted` (Accessibility is
optional — an app that can't hear you or receive your hotkey can't
work, but paste-at-cursor has a clipboard fallback). After the first
flip the observer self-terminates, so a later permission revoke in
System Settings does NOT re-trigger first-run auto-open.

- [ ] **MV-ONB-1 — fresh install grants both required perms:** clean
  the TCC database for the bundle (`tccutil reset All com.nitkrar.personal_scribe`
  then quit Ninimma). Launch Ninimma. Confirm the unified window
  auto-opens to Settings → Permissions. Grant Microphone + Input
  Monitoring via their "Grant Access" buttons; return to Ninimma.
  Quit and relaunch. Confirm the unified window does NOT auto-open
  — it stays closed behind the menu-bar icon.
- [ ] **MV-ONB-2 — accessibility alone does not complete onboarding:**
  from a fresh TCC state, grant only Accessibility. Quit and
  relaunch. Confirm the unified window still auto-opens to Settings
  → Permissions (flag did not flip).
- [ ] **MV-ONB-3 — later revoke does not re-trigger onboarding:**
  with onboarding complete (MV-ONB-1 final state), revoke Microphone
  in `System Settings → Privacy & Security → Microphone`. Return to
  Ninimma; relaunch. The window must stay closed — `OnboardingCompleted`
  is a first-run indicator, not a perpetual state check. The
  menu-bar permission-warning row will still surface the missing
  permission (existing MV-PERMS-* behavior).

## Permissions sub-tab — fresh status on render

- Fresh install mic accept refreshes correctly: install a build whose bundle ID has no existing TCC grants, launch, accept the microphone TCC prompt that appears on first launch, navigate to `Settings > Permissions`, and confirm the Microphone row shows the green dot + no "Grant Access" button (mic TCC dialogs are system-modal and do not fire `didBecomeActiveNotification`, so this exercises the `.onAppear` refresh path).
- Returning to Permissions after a silent external change picks it up: with the app running, open `Settings > Permissions`, switch to a different sub-tab (General / AI Models / Advanced / About), then toggle a permission in System Settings from another window, return to `Permissions`, and confirm the row updates on the next tab render without needing to restart the app.

## Change recording hotkey

- **MV-SETT-2 — Change recording hotkey:** in `General > Shortcuts`, click `Change…` on `Record / stop dictation`, record a new shortcut, confirm `Cmd+Space` is rejected inline, click `Set`, confirm a restart-required note appears, relaunch `<AppBrand.displayName>`, and verify the new recording shortcut works.
- [ ] **MV-SETT-3** Settings > General renders a `Shortcuts` subsection
  at the bottom containing the `Record / stop dictation` hotkey row.
  The top-level `Shortcuts` sub-tab must NOT exist. Regression guard for
  bug #14 (2026-04-21 dogfood).

## Streaming dictation defaults (#056)

- **MV-SETT-STREAM-1 — General card renders all streaming controls:** open
  `Settings → General`. Confirm a `Streaming dictation` card appears
  with toggles for `Live transcript card`, `Live cursor streaming`, and
  `Authoritative second pass`, plus an `Overflow mode` picker.
- **MV-SETT-STREAM-2 — Live cursor note is explicit:** under the
  `Live cursor streaming` toggle, confirm the helper copy says the flag
  is saved now but live cursor transport is not active in this build.
- **MV-SETT-STREAM-3 — Streaming defaults persist across relaunch:**
  change all three toggles and the overflow picker to non-default
  values, relaunch Ninimma, reopen `Settings → General`, and confirm
  the same values are still selected.
- **MV-SETT-STREAM-4 — New streaming modes inherit the current global
  defaults:** change the global streaming defaults, create a fresh
  `Streaming Dictation` mode from the Modes tab, and confirm its
  realtime-only rows resolve to the same defaults until you override
  them per-mode.

## Change base directory

- Pick a new writable folder from `Advanced > Change Base Directory…` and confirm the tab shows an in-progress spinner followed by a success message naming the migrated subdirectories.
- After the migration completes, confirm the selected directory now contains the expected `models`, `modes`, and/or `recordings` folders, and the old base directory is left behind without those moved folders.
- Relaunch `<AppBrand.displayName>`, then confirm the app reads from the new base directory by finding an existing downloaded model and recent transcripts there without re-downloading or losing history.

## Advanced — base-directory row layout + Open-in-Finder target (#006)

Regression guard for bug #006 — the previous row stacked a metadata
block above two full-width action buttons, which wrapped onto a second
line at the default Settings width (760pt). Finder was also being
handed the base directory via `activateFileViewerSelecting([url])`,
which opens the PARENT folder with `personal_scribe` highlighted
instead of its contents.

- [ ] **MV-BASE-DIR-1 — Single-line compact row:** open `Settings >
  Advanced` at the default window width. The base-directory row
  renders on ONE visual line: bold caption `Base directory`, the
  resolved path in a middle-truncated monospaced label (so long paths
  show `/Users/…/personal_scribe`), followed by two icon-only buttons
  (magnifying-glass + folder). The row must NOT wrap to two lines; the
  two buttons must NOT be full-width pill buttons.
- [ ] **MV-BASE-DIR-2 — Open-in-Finder opens the folder, not the
  parent:** click the magnifying-glass icon in the base-directory row.
  Finder opens a window titled `personal_scribe` whose contents
  (`models/`, `modes/`, `recordings/`, etc.) are visible. Finder must
  NOT instead surface `~/Library/Application Support/` with
  `personal_scribe` highlighted — that's the bug #006 regression.
- Hover tooltips: hovering the magnifying-glass icon shows `Open in
  Finder`; hovering the folder icon shows `Change base directory…`.

## AI Models tab — Stage A (step 3.2)

Stage A replaces the inert AIModelsTab with one `SettingsCard` row per registered voice model. Chip + button are driven by `DefaultModelService.downloadStates[descriptor.id]`. A single `SettingsSection` header (`Voice models`) is used for now; Stage B will add an `AI models` section below without restructuring.

**#007 update (2026-04-22):** each row now shows a one-line inline description (from `ModelDescriptor.shortDescription`) in place of the raw byte size, plus an ⓘ info button next to the display name. Clicking ⓘ opens a popover with the full metadata — Speed / Accuracy bars (computed-relative across registered siblings), Size, Architecture, Repository, Revision, Parameters. Row padding tightened to `compactCardPadding` so three models fit under the default window height without scrolling.

- **MV-AIM-1 — fresh install, not downloaded:** delete `~/Library/Application Support/com.nitkrar.personal_scribe/models/parakeet-tdt-0.6b-v2/` (and any other model folders), relaunch Ninimma, open `Settings > AI Models`, and confirm each registered voice model row renders with a grey `Not downloaded` badge plus a prominent `Download` button. The default `Parakeet TDT 0.6B` row shows its inline description (`High-accuracy default — balanced RAM and speed.`) under the display name and an ⓘ icon next to the name.
- **MV-AIM-2 — live download updates:** from MV-AIM-1 state, click `Download` on the `Parakeet TDT 0.6B` row and confirm the badge transitions to an amber `Downloading NN%` chip that updates live over the next several minutes (no Download button while in-flight), then switches to an amber `Loading…` chip briefly, then to a green `Active` chip with a disabled `Active` button (no separate `Set Active` button).
- **MV-AIM-3 — switch active model:** with `Parakeet TDT 0.6B` active and downloaded, also download `Parakeet TDT-CTC 110M` (click its `Download` button and wait for it to flip to green `Ready`). Click `Set Active` on the CTC row, confirm its chip becomes `Active` (green) + button is disabled, and the `Parakeet TDT 0.6B` row's chip flips from `Active` to `Ready` with a `Set Active` button reappearing.
- **MV-AIM-4 — failure + retry:** enable Airplane Mode (or drop the wi-fi) mid-download, wait for the chip to flip to a red `Failed: …` badge with a `Retry` button, re-enable network, click `Retry`, and confirm the chip resumes the amber `Downloading NN%` → `Loading…` → green `Active` sequence.
- [ ] **MV-AIM-6 — ⓘ info popover renders computed-relative ratings (#007):**
  open `Settings → AI Models`. Click the ⓘ icon next to each model's
  display name and confirm the popover renders:
  - **Parakeet TDT 0.6B (v2)**: Speed bar 2/3 "Fast"; Accuracy bar 3/3 "High"; Size 450 MB; Architecture `FastConformer-TDT`; Parameters `600M`.
  - **Parakeet TDT-CTC 110M**: Speed bar 3/3 "Fastest"; Accuracy bar 1/3 "Low"; Size 407 MB; Architecture `Hybrid FastConformer-TDT-CTC`; Parameters `110M`.
  - **Parakeet TDT 0.6B v3**: Speed bar 1/3 "Slow"; Accuracy bar 2/3 "Medium"; Size 700 MB; Architecture `FastConformer-TDT`; Parameters `600M`.
  Revision row renders a monospaced 8-char short SHA. Clicking outside
  the popover dismisses it; clicking the ⓘ again re-opens.
- [ ] **MV-AIM-7 — three rows fit without scrolling (#007):** at the
  default unified-window size (760×520), confirm all three voice-model
  rows are visible under `Settings → AI Models` without needing to
  scroll. Each row shows name + description (one line) + chip +
  action button. Adding a 4th model would introduce scrolling by
  design — three is the registered-model ceiling today.
- **MV-AIM-5 — Disk-space precheck (Stage B).**
  1. Simulate low disk: either fill the volume to near capacity, or inject a small `diskSpaceProvider` via a Debug-only harness (if present). Real-world simulation is fine — move large files onto the volume until < 300 MB free.
  2. Click **Download** on a model (choose Parakeet TDT 0.6B v2, ~450 MB).
  3. Confirm no HuggingFace network activity starts (Activity Monitor → Network → search for huggingface).
  4. Confirm the row immediately shows a red **Failed** badge with text like `"Not enough disk space to download Parakeet TDT 0.6B. Needs 650 MB, 280 MB available."` and a **Retry** button.
  5. Free up space on the volume; click Retry; confirm download proceeds normally.

## Stale-state on tab return (#039)

Regression guards for ticket #039. AIModelsTab now calls
`service.refresh()` on `.onAppear`; this re-reads `isDownloaded` from
disk for every registered voice model and flips `.ready` ↔ `.notDownloaded`
if the on-disk truth has changed. In-flight `.downloading` / `.loading`
and explicit `.failed` states are preserved — `refresh()` only
transitions between the two terminal phases.

- [ ] **MV-SETT-STALE-1 — model appears on disk while AI Models is off-screen:**
  open `Settings → General` (or any non-AI-Models sub-tab). Start a
  voice model download by navigating to `Settings → AI Models` briefly,
  clicking `Download` on a not-yet-downloaded model, then immediately
  switching to another sub-tab. Wait for the download to finish (check
  the model folder in Finder, or watch `du -sh ~/Library/.../models/<id>/`).
  Switch back to `Settings → AI Models`. The row MUST show the green
  `Ready` (or `Active`) chip on first render — no window close/reopen
  required.
- [ ] **MV-SETT-STALE-2 — model deleted from disk while AI Models is off-screen:**
  with at least one model showing `Ready` in `Settings → AI Models`,
  switch to another sub-tab. From a terminal: `rm -rf
  ~/Library/Application\ Support/com.nitkrar.personal_scribe/models/<model-id>/`.
  Switch back to AI Models. The row MUST flip to a grey `Not downloaded`
  badge with a `Download` button — no window close/reopen required.
- [ ] **MV-SETT-STALE-3 — in-flight download is NOT stomped by tab re-entry:**
  start a voice-model download on `Settings → AI Models`. While the
  amber `Downloading NN%` chip is still ticking, switch to another
  sub-tab and immediately back. The chip MUST continue to tick
  `Downloading NN%` from the current progress — it must NOT reset to
  `Not downloaded`. This guards `refresh()`'s preservation of in-flight
  states.
- [ ] **MV-SETT-STALE-4 — a `.failed` state survives tab re-entry:**
  force a download failure (Airplane Mode mid-download, as in MV-AIM-4).
  Confirm the red `Failed: …` chip renders. Switch to another sub-tab
  and back. The chip MUST still read `Failed: …` with a `Retry` button —
  refresh must not quietly clear an error the user hasn't acknowledged.

## Launch-at-Login status feedback (#005)

Small status dot + tooltip icon next to the `Launch at login` toggle.
Green (`Palette.statusReady`) when `SMAppService.mainApp.status == .enabled`, red (`Palette.statusRecording`) otherwise. View model re-reads the injected service on `.onAppear` and immediately after every `register()` / `unregister()` — no optimistic UI, no alert.

- **MV-LAL-1 — toggle ON reflects success:** from a fresh state where the app is NOT registered (dot red), click `Launch at login`. Expected: toggle flips on, the dot flips to green within one frame. Relaunch the app, reopen `Settings → General`, confirm the dot is still green on appear.
- **MV-LAL-2 — toggle OFF reflects success:** with the dot green, click `Launch at login` off. Expected: toggle off, dot red. Relaunch, confirm dot is still red on appear.
- **MV-LAL-3 — register failure surfaces via red dot (no alert):** run the unsigned `swift run` binary (or any build where `SMAppService.mainApp.register()` throws) and click the toggle on. Expected: no alert is shown; the toggle visually snaps back to off and the dot stays red. (This is the intended feedback path for #005 — the swallowed error is now visible.)
- **MV-LAL-4 — out-of-band change picked up on reopen:** with the app running and Settings closed, open `System Settings → General → Login Items` and flip the Ninimma row's toggle. Open `Settings → General` in Ninimma and confirm the `Launch at login` toggle + dot reflect the System-Settings state (not the pre-change state).
- **MV-LAL-5 — info-icon tooltip:** hover the ⓘ icon next to the checkbox and confirm a help tooltip appears reading `Verify or change this in System Settings → General → Login Items`.

## ⌘, keyboard shortcut opens Settings tab

Wired in `PersonalScribeAppMain.body` via `CommandGroup(replacing: .appSettings)` — replaces the default SwiftUI `Settings { EmptyView() }` handler so the shortcut opens the unified window's Settings tab instead of the empty placeholder scene.

- **MV-CMD-1 — `⌘,` with unified window already open:** click the menu bar status item → `Home` (or any tab), then press `⌘,`. The tab selector jumps to `Settings`. Pressing `⌘,` a second time is a no-op (already there).
- **MV-CMD-2 — `⌘,` with unified window closed but app frontmost:** close the unified window (red traffic light), then immediately press `⌘,` while Ninimma is still frontmost. The unified window reappears with the Settings tab selected.
- **MV-CMD-3 — `⌘,` from another app:** while a non-Ninimma app is frontmost (e.g. Finder), press `⌘,`. Expected: Finder's own Preferences opens; Ninimma's shortcut must NOT steal the keystroke (LSUIElement apps only receive menu shortcuts when their own window is key).

## About — sidebar footer (bug #1c)

`About` is NOT a Settings sub-tab; it's a clickable footer row under the
Microphone footer in the unified-window sidebar, styled as a muted caption
row (not a tab-row).

- **MV-ABOUT-1 — About row visible at sidebar bottom:** open the unified
  window. The sidebar shows `Home / Transcriptions / Modes / Settings`
  as tab rows, a `Microphone` footer, and directly below it an `About`
  footer row with an info-circle icon. Neither footer has a tab-row
  accent bar.
- **MV-ABOUT-2 — About is NOT in Settings:** click `Settings`. The
  segmented sub-tab picker shows `General / AI Models / Shortcuts /
  Advanced / Permissions` — no `About` entry.
- **MV-ABOUT-3 — Clicking About routes to the About view:** click the
  `About` footer row. The detail pane swaps to the About card (app icon,
  version/build, origin copy, mythlok link). The sidebar list stays
  visible throughout; neither the footer nor any sidebar tab-row shows
  a tab-row accent bar.
- **MV-ABOUT-4 — Active-state affordance:** while on About, the footer
  row reads at full opacity; the Microphone footer above remains muted.
  Click Home — the About footer dims back to muted caption opacity.

## Transcribe output (#072)

Consolidated section in Settings → General. Two orthogonal toggles
("Auto-paste to cursor", default ON; "Restore clipboard", default OFF)
plus a delay slider that surfaces only when Restore is ON, with a
summary caption at the bottom that adapts to toggle state.

- **MV-072-1 — Section layout matches spec:** open Settings → General.
  Confirm the "Transcribe output" card contains, top-to-bottom: Auto-paste
  to cursor toggle, divider, Restore clipboard toggle, divider, summary
  caption. No "Paste result text" master toggle, no "Paste mode" picker,
  no separate restore-delay slider under "Behavior" — those shipped pre-
  #072 and were consolidated here.
- **MV-072-2 — Restore slider toggles visibility:** with Restore clipboard
  OFF, confirm no slider is visible between the toggle and the caption.
  Flip Restore ON; a "Restore delay" slider + description appears
  (default `3.0`s, range `0.1`–`10.0`). Flip OFF; slider disappears.
- **MV-072-3 — Summary caption adapts:** cycle all four toggle
  combinations and verify the caption sentence changes accordingly:
  - AutoPaste ON + Restore ON: mentions "paste into the focused text
    field", the slider seconds, and "restored — unless you've copied
    something new in the meantime".
  - AutoPaste ON + Restore OFF: mentions "paste into the focused text
    field" and "until you copy something else".
  - AutoPaste OFF + Restore ON: mentions "⌘V to paste" and the slider
    seconds restore with the changeCount caveat.
  - AutoPaste OFF + Restore OFF: mentions "⌘V to paste" and "not
    restored".
- **MV-072-4 — Cursorless paste no longer silently wipes transcript:**
  start a recording, switch focus to a Finder window or any surface
  without a text cursor, stop. The pill confirms "Copied · ⌘V to paste".
  Switch to a text editor; press `⌘V`. With Restore OFF (default), the
  transcript pastes correctly. With Restore ON + delay `3.0`s, press
  `⌘V` within 3s — still pastes correctly; after 3s, the user's pre-
  recording clipboard contents are restored.
- **MV-072-5 — Sequential recordings don't corrupt clipboard
  (changeCount guard):** with Restore ON, start Recording A, stop,
  IMMEDIATELY start Recording B, stop. Before the 3s timer from A fires,
  Transcript B should be on the clipboard. After 3s (A's timer) and
  again after 6s (B's timer), Transcript B should STILL be on the
  clipboard — not A's pre-recording snapshot, not A's transcript. The
  `changeCount` guard prevents the stale restore from overwriting newer
  content.
- **MV-072-6 — Cancel Card Undo still works (System A unified into
  service):** start a recording, click ✕ on the pill before transcription
  completes (or press Esc). The Cancel Card appears briefly with an Undo
  button. Click Undo. The clipboard returns to whatever it held
  pre-recording — including non-string types like RTF or file URLs
  (fidelity upgrade over pre-#072 string-only behavior).
- **MV-072-7 — Auto-paste OFF skips Cmd+V post:** flip Auto-paste OFF.
  Start a recording, stop with focus in TextEdit. No transcript appears
  in TextEdit; the clipboard holds the transcript; `⌘V` pastes it.
- **MV-072-8 — Restore default bump:** fresh install (delete
  `UserDefaults` for `PasteRestoreDelaySeconds`). Open Settings, flip
  Restore ON. Slider sits at `3.0`s — not the pre-#072 `0.5`s default.

## #078.33 — GeneralTab toggles bridge to WorkflowModeRegistry

L27 wiring: each of the three structural toggles in General mutates the
active workflow recipe in addition to the legacy `UserDefaults` write.
First touch on the built-in `Dictation` mode forks it into a custom
copy named `Dictation (custom)` (or `Dictation (migrated)` if the
legacy migrator already forked); subsequent touches mutate the active
custom mode in place.

- **MV-078-33-1 — Auto-paste OFF removes paste from active recipe:**
  flip Auto-paste OFF. Start a recording, stop with focus in TextEdit.
  No transcript appears in TextEdit; clipboard holds the transcript.
  Open Settings → Modes (when Modes editor lands) — confirm a
  `Dictation (custom)` entry exists distinct from `Dictation`.
  Quitting and relaunching preserves the ON/OFF choice (recipe is
  saved to `workflow-modes.json`).
- **MV-078-33-2 — Auto-stop after silence ON adds VAD to recipe:**
  flip Auto-stop after silence ON. Start a recording, hold silent for
  the configured threshold. Recording auto-stops without manual
  hotkey press. Flip OFF — silence no longer auto-stops; only manual
  hotkey / pill click stops recording. Threshold slider, "Warn before
  stopping", and "Show stop notification" continue to act as global
  settings (the recipe references them via `.setting(...)`).
- **MV-078-33-3 — Restore clipboard rewrites parameter to override:**
  flip Restore clipboard OFF. Quit and relaunch. The toggle remains
  OFF — the recipe holds `Parameter.override(false)` for the
  clipboard sink, locking the value regardless of any future global
  default. Flip ON; same persistence guarantee at `Parameter.override(true)`.
- **MV-078-33-4 — Fail-soft when registry rejects mutation:** the
  registry validator only checks processors and pipeline shape;
  toggling Auto-paste / Auto-stop / Restore should never fail
  validation. If a future change breaks this assumption, the legacy
  `UserDefaults` write still lands and the toggle visibly reflects
  the user's intent — the recipe path is fail-soft (errors swallowed
  in `mutateActiveRecipe`).

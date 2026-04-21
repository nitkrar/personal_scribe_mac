# Manual Settings Verification

- Opening via menu bar: with onboarding completed, click the status-item `Settings` row and confirm the `<AppBrand.displayName> Settings` window opens in front of the app.
- All 5 tabs visible: confirm `General`, `AI Models`, `Modes`, `Shortcuts`, and `Advanced` render and can each be selected from the tab strip.
- General-tab toggles persist across relaunch: change pill visibility, waveform decay, and paste mode, relaunch Ninimma, and confirm the three selections remain at their last chosen values.
- Both-hidden combination blocked with visible error state: hide the menu bar item, then try to set pill visibility to `Hidden`, and confirm the UI rejects the change with an inline explanation that one surface must remain visible.

## Clipboard restore delay

- Slider reflects current delay: open `General`, confirm the `Clipboard restore delay` control matches the current setting value, and confirm the helper text reads `After paste, wait Ns before restoring your clipboard` with the same value.
- Changing slider persists across relaunch: move the slider to a non-default value, quit and relaunch Ninimma, reopen `General`, and confirm the slider and helper text still show the chosen delay.
- `0.1s` fast restore: set the delay to `0.1s`, dictate into Slack, confirm the transcript pastes into the compose field, then press `Cmd+V` manually and confirm Slack pastes the clipboard content that existed before dictation.
- `5.0s` slow restore: set the delay to `5.0s`, dictate into Slack, wait after the initial paste, and confirm the clipboard remains the transcribed text for the full five-second window before the pre-paste clipboard is restored.

## Permissions sub-tab — fresh status on render

- Fresh install mic accept refreshes correctly: install a build whose bundle ID has no existing TCC grants, launch, accept the microphone TCC prompt that appears on first launch, navigate to `Settings > Permissions`, and confirm the Microphone row shows the green dot + no "Grant Access" button (mic TCC dialogs are system-modal and do not fire `didBecomeActiveNotification`, so this exercises the `.onAppear` refresh path).
- Returning to Permissions after a silent external change picks it up: with the app running, open `Settings > Permissions`, switch to a different sub-tab (General / Modes), then toggle a permission in System Settings from another window, return to `Permissions`, and confirm the row updates on the next tab render without needing to restart the app.

## Change recording hotkey

- In `Shortcuts`, click `Change…` on `Record / stop dictation`, record a new shortcut, confirm `Cmd+Space` is rejected inline, click `Set`, confirm a restart-required note appears, relaunch `<AppBrand.displayName>`, and verify the new recording shortcut works.

## Change base directory

- Pick a new writable folder from `Advanced > Change Base Directory…` and confirm the tab shows an in-progress spinner followed by a success message naming the migrated subdirectories.
- After the migration completes, confirm the selected directory now contains the expected `models`, `modes`, and/or `recordings` folders, and the old base directory is left behind without those moved folders.
- Relaunch `<AppBrand.displayName>`, then confirm the app reads from the new base directory by finding an existing downloaded model and recent transcripts there without re-downloading or losing history.

## AI Models tab — Stage A (step 3.2)

Stage A replaces the inert AIModelsTab with one `SettingsCard` row per registered voice model. Chip + button are driven by `DefaultModelService.downloadStates[descriptor.id]`. A single `SettingsSection` header (`Voice models`) is used for now; Stage B will add an `AI models` section below without restructuring.

- **MV-AIM-1 — fresh install, not downloaded:** delete `~/Library/Application Support/com.nitkrar.personal_scribe/models/parakeet-tdt-0.6b-v2/` (and any other model folders), relaunch Ninimma, open `Settings > AI Models`, and confirm each registered voice model row renders with a grey `Not downloaded` badge plus a prominent `Download` button. The default `Parakeet TDT 0.6B` row is visible with its size (`~450 MB`).
- **MV-AIM-2 — live download updates:** from MV-AIM-1 state, click `Download` on the `Parakeet TDT 0.6B` row and confirm the badge transitions to an amber `Downloading NN%` chip that updates live over the next several minutes (no Download button while in-flight), then switches to an amber `Loading…` chip briefly, then to a green `Active` chip with a disabled `Active` button (no separate `Set Active` button).
- **MV-AIM-3 — switch active model:** with `Parakeet TDT 0.6B` active and downloaded, also download `Parakeet TDT-CTC 110M` (click its `Download` button and wait for it to flip to green `Ready`). Click `Set Active` on the CTC row, confirm its chip becomes `Active` (green) + button is disabled, and the `Parakeet TDT 0.6B` row's chip flips from `Active` to `Ready` with a `Set Active` button reappearing.
- **MV-AIM-4 — failure + retry:** enable Airplane Mode (or drop the wi-fi) mid-download, wait for the chip to flip to a red `Failed: …` badge with a `Retry` button, re-enable network, click `Retry`, and confirm the chip resumes the amber `Downloading NN%` → `Loading…` → green `Active` sequence.
- **MV-AIM-5 — Disk-space precheck (Stage B).**
  1. Simulate low disk: either fill the volume to near capacity, or inject a small `diskSpaceProvider` via a Debug-only harness (if present). Real-world simulation is fine — move large files onto the volume until < 300 MB free.
  2. Click **Download** on a model (choose Parakeet TDT 0.6B v2, ~450 MB).
  3. Confirm no HuggingFace network activity starts (Activity Monitor → Network → search for huggingface).
  4. Confirm the row immediately shows a red **Failed** badge with text like `"Not enough disk space to download Parakeet TDT 0.6B. Needs 650 MB, 280 MB available."` and a **Retry** button.
  5. Free up space on the volume; click Retry; confirm download proceeds normally.

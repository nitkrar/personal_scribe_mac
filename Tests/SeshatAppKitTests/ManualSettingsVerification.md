# Manual Settings Verification

- Opening via menu bar: with onboarding completed, click the status-item `Settings` row and confirm the Seshat Settings window opens in front of the app.
- All 5 tabs visible: confirm `General`, `AI Models`, `Modes`, `Shortcuts`, and `Advanced` render and can each be selected from the tab strip.
- General-tab toggles persist across relaunch: change pill visibility, waveform decay, and paste mode, relaunch Seshat, and confirm the three selections remain at their last chosen values.
- Both-hidden combination blocked with visible error state: hide the menu bar item, then try to set pill visibility to `Hidden`, and confirm the UI rejects the change with an inline explanation that one surface must remain visible.

## Clipboard restore delay

- Slider reflects current delay: open `General`, confirm the `Clipboard restore delay` control matches the current setting value, and confirm the helper text reads `After paste, wait Ns before restoring your clipboard` with the same value.
- Changing slider persists across relaunch: move the slider to a non-default value, quit and relaunch Seshat, reopen `General`, and confirm the slider and helper text still show the chosen delay.
- `0.1s` fast restore: set the delay to `0.1s`, dictate into Slack, confirm the transcript pastes into the compose field, then press `Cmd+V` manually and confirm Slack pastes the clipboard content that existed before dictation.
- `5.0s` slow restore: set the delay to `5.0s`, dictate into Slack, wait after the initial paste, and confirm the clipboard remains the transcribed text for the full five-second window before the pre-paste clipboard is restored.

## Change recording hotkey

- In `Shortcuts`, click `Change…` on `Record / stop dictation`, record a new shortcut, confirm `Cmd+Space` is rejected inline, click `Set`, confirm a restart-required note appears, relaunch Seshat, and verify the new recording shortcut works.

## Change base directory

- Pick a new writable folder from `Advanced > Change Base Directory…` and confirm the tab shows an in-progress spinner followed by a success message naming the migrated subdirectories.
- After the migration completes, confirm the selected directory now contains the expected `models`, `modes`, and/or `recordings` folders, and the old base directory is left behind without those moved folders.
- Relaunch Seshat, then confirm the app reads from the new base directory by finding an existing downloaded model and recent transcripts there without re-downloading or losing history.

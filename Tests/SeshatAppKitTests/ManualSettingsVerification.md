# Manual Settings Verification

- Opening via menu bar: with onboarding completed, click the status-item `Settings` row and confirm the Seshat Settings window opens in front of the app.
- All 5 tabs visible: confirm `General`, `AI Models`, `Modes`, `Shortcuts`, and `Advanced` render and can each be selected from the tab strip.
- General-tab toggles persist across relaunch: change pill visibility, waveform decay, and paste mode, relaunch Seshat, and confirm the three selections remain at their last chosen values.
- Both-hidden combination blocked with visible error state: hide the menu bar item, then try to set pill visibility to `Hidden`, and confirm the UI rejects the change with an inline explanation that one surface must remain visible.

## Change base directory

- Pick a new writable folder from `Advanced > Change Base Directory…` and confirm the tab shows an in-progress spinner followed by a success message naming the migrated subdirectories.
- After the migration completes, confirm the selected directory now contains the expected `models`, `modes`, and/or `recordings` folders, and the old base directory is left behind without those moved folders.
- Relaunch Seshat, then confirm the app reads from the new base directory by finding an existing downloaded model and recent transcripts there without re-downloading or losing history.

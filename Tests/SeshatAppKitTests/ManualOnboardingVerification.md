# Onboarding Window — Manual Verification Runbook

This slice changes first-run permission timing and the fallback path used
when recording surfaces are tapped before Seshat has the required macOS
permissions. XCTest covers the onboarding state machine and menu fallback
logic, but the actual window lifecycle and TCC prompts still require
runtime verification.

---

## First launch

- [ ] **MV-OB-1** Fresh install / fresh defaults: launch Seshat and confirm the onboarding window appears immediately.
- [ ] **MV-OB-2** While the onboarding window is open, clicking the pill or choosing `Start Recording` from the menu does not begin recording; the onboarding window remains the active path.
- [ ] **MV-OB-3** Complete all onboarding panes with either Grant or Skip actions. The window closes only after the final pane resolves.

## Permissions granted

- [ ] **MV-OB-4** Grant Microphone, Input Monitoring, and Accessibility in order. After the window closes, the pill tap starts recording normally and the first completed transcription pastes without showing a late Accessibility prompt.

## Permissions incomplete fallback

- [ ] **MV-OB-5** Deny Microphone during onboarding. After the window closes, the menu shows the `Permissions needed before recording` note and choosing `Start Recording` reopens onboarding instead of crashing or toggling recording.
- [ ] **MV-OB-6** Skip or deny Input Monitoring, then click the pill. The app does not crash; it reopens onboarding instead of entering the recording path.

## Re-grant path

- [ ] **MV-OB-7** With onboarding already completed once, grant the previously missing permission(s) in System Settings, relaunch Seshat, and verify recording works on the next launch without showing onboarding first.

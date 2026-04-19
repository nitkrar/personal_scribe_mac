# Hotkeys — Manual Verification Runbook

Hotkey routing depends on global `NSEvent` monitoring and app lifecycle
integration that XCTest cannot fully prove in-process. Run the checklist
below after changes in `Sources/SeshatAppKit/Hotkeys/` or the hotkey
composition wiring.

## Double-tap ⌥ recording toggle (regression baseline)

- [ ] **MV-HK-1** Double-tap right Option within ~0.4s — pill enters
  recording state (waveform animates). Double-tap again — pill stops
  and transcription fires.
- [ ] **MV-HK-2** Single right-Option press — nothing happens. No pill,
  no session.
- [ ] **MV-HK-3** Two taps spaced > 0.4s apart — no toggle fires (window
  expired, second tap starts a fresh sequence).

## Triple-tap ⌥ emergency quit (new in I.1)

- [ ] **MV-HK-4** Triple-tap right Option within ~0.4s between taps —
  app quits within ~1s. No preceding toggle. Confirm by checking Dock:
  Seshat is gone.
- [ ] **MV-HK-5** Same as MV-HK-4 but on the LEFT Option key — should
  also quit. Both option keys are wired.
- [ ] **MV-HK-6** Triple-tap with the third tap > 0.4s after the second
  — the second tap's double-tap toggle STILL fires (recording starts);
  the slow third tap does NOT trigger quit. Confirms the window boundary.

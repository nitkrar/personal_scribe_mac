# Hotkeys — Manual Verification Runbook

Hotkey routing depends on global `NSEvent` monitoring and app lifecycle
integration that XCTest cannot fully prove in-process. Run the checklist
below after changes in `Sources/PersonalScribeAppKit/Hotkeys/` or the hotkey
composition wiring.

## Double-tap ⌥ recording toggle (regression baseline)

- [ ] **MV-HK-1** Double-tap right Option within ~0.4s — pill enters
  recording state (waveform animates) **immediately on the second tap,
  no perceptible delay**. Double-tap again — pill stops and
  transcription fires. If you notice a delay between the second tap
  and the pill appearing, the old deferred-toggle regression is back.
- [ ] **MV-HK-2** Single right-Option press — nothing happens. No pill,
  no session.
- [ ] **MV-HK-3** Two taps spaced > 0.4s apart — no toggle fires (window
  expired, second tap starts a fresh sequence).
- [ ] **MV-HK-4** Triple-tap right Option within ~0.4s between taps —
  the FIRST two taps fire the toggle (recording starts); the third tap
  alone does nothing (window reset). App does NOT quit. The
  triple-tap emergency-quit path was removed — the last survival of
  accidental triple-taps is "recording started" rather than "app
  terminated".

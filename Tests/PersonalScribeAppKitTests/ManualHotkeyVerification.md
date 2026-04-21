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

## Hotkey fires when Ninimma is frontmost (bug #4)

`NSEvent.addGlobalMonitorForEvents` only fires for events headed to
*other* apps. A matching `addLocalMonitorForEvents` is now installed
alongside, so the hotkey still works when our own window is frontmost.
Matching events are swallowed so `÷` doesn't leak into Ninimma's text
fields. This does NOT address `÷` leakage into *other* apps during
hold (bug #5 — requires a CGEventTap).

- [ ] **MV-HK-5** Open the unified window and click to make it
  frontmost. Tap ⌥+/ — the pill appears and recording starts. Tap
  again — recording stops and transcription fires. Regression guard
  for bug #4 (2026-04-21 dogfood) where the hotkey was dead whenever
  Ninimma was focused.
- [ ] **MV-HK-6** With the unified window frontmost, focus a text
  field (Shortcuts → Record field, or any Settings text input). Tap
  ⌥+/ — recording starts AND the text field must remain empty (no `÷`
  inserted). Regression guard for local-monitor swallow logic.
- [ ] **MV-HK-7** Switch to another app (e.g. Notes) until Ninimma's
  window is NOT frontmost. Tap ⌥+/ — recording still starts. Regression
  guard that the original global-monitor path still works.

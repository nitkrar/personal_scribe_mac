# Hotkeys — Manual Verification Runbook

Hotkey routing depends on macOS hot-key registration, local `NSEvent`
monitoring, and app lifecycle integration that XCTest cannot fully prove
in-process. Run the checklist below after changes in
`Sources/PersonalScribeAppKit/Hotkeys/` or the hotkey composition wiring.

## Tap and hold gestures

- [ ] **MV-HK-1** Tap ⌥+/ and release within 300ms. The pill enters
  recording state. After 400ms, tap again; recording stops and
  transcription runs.
- [ ] **MV-HK-2** Hold ⌥+/ for more than 300ms. Hold-to-record starts;
  releasing the chord stops capture and runs transcription.
- [ ] **MV-HK-3** Tap ⌥+/ twice within 400ms. Recording starts once;
  the second tap is absorbed instead of stopping the new session.
- [ ] **MV-HK-4** Tap ⌥+/ twice with more than 400ms between releases.
  The first tap starts recording and the second stops it.

## Hotkey fires when Ninimma is frontmost

`RegisterEventHotKey` delivers configured shortcuts while another app is
frontmost. A local `NSEvent` monitor handles the same shortcut when
Ninimma is frontmost. Both paths suppress the matching chord.

- [ ] **MV-HK-5** Open the unified window and click to make it
  frontmost. Tap ⌥+/ — the pill appears and recording starts. Tap
  again — recording stops and transcription fires.
- [ ] **MV-HK-6** With the unified window frontmost, focus a text
  field (Shortcuts → Record field, or any Settings text input). Tap
  ⌥+/ — recording starts AND the text field must remain empty (no `÷`
  inserted). Regression guard for local-monitor swallow logic.
- [ ] **MV-HK-7** Switch to another app (e.g. Notes) until Ninimma's
  window is NOT frontmost. Tap ⌥+/ — recording still starts.

## Registered shortcuts are suppressed system-wide

`GlobalHotkeyMonitor` registers configured chords through
`RegisterEventHotKey`. macOS delivers those chords only to Ninimma and
does not deliver their key events to the focused app.

- [ ] **MV-HK-8** Open any other app (Notes, TextEdit, Safari address
  bar) and click into a text field so it owns focus. **Tap ⌥+/ once**
  — recording starts, and the text field stays empty (no stray `÷`
  character). Tap again — recording stops, still no `÷`.
- [ ] **MV-HK-9** Same setup. **Hold ⌥+/ for ~1.5s, then release.**
  The text field stays empty throughout — no `÷÷÷÷` stream from auto-
  repeat keyDowns.
- [ ] **MV-HK-11** Press a plain `/` (no option) in another app's text
  field. The `/` character types normally because only registered
  chords are suppressed.

## Hold-to-record no longer wedges after release (bug #71)

Pre-#71 behaviour was a flaky wedge: release occasionally failed to
stop the session; the hold pill stuck; hitting Esc spawned a *second*
recording pill underneath. Root cause was a race between the start
and stop tasks through `coordinator.toggle()` — stop could observe
`.idle` before `.recording` was published, silently no-op, and leave
capture alive. Post-fix: hold has a first-class `.holdRecording` state
published **eagerly** by the pipeline before awaiting capture, and the
coordinator uses mode-specific `startHoldIfIdle()` / `stopIfActive()`
methods instead of the toggle path.

- [ ] **MV-HOLD-1** Hold the hotkey for ~1s, speak a short phrase,
  release. Transcript pastes. Repeat 10× in a row (different apps,
  different durations). No release should leave the pill stuck. This
  is the primary repro the user reported (2026-04-22). If any release
  wedges, note it and re-open #71.
- [ ] **MV-HOLD-2** Hold the hotkey for ~1s, release. Before the
  transcribe settles, hold again. The pill must cleanly re-enter
  `.holdToRecord` (the 7-bar equaliser, not the waveform pill) — no
  stale pill carried over from the prior session.
- [ ] **MV-HOLD-3** Hold the hotkey very briefly (below the 300ms
  threshold) and release. No hold-pill appears; if a toggle fires it
  goes through the normal `.recording` path. Regression guard that
  the tap vs hold discrimination still works.
- [ ] **MV-HOLD-4** Hold the hotkey and press Esc mid-gesture. The pill
  transitions to the Cancel Card (current behaviour — true-cancel
  lands under #002). No second pill appears underneath.
- [ ] **MV-HOLD-5** Hold the hotkey during a model download. Pill
  shows the `.holdToRecord` pane with "Recording — transcribing when
  model is ready" status card (from `RecordingStatusCardDriver`).
  Release transitions to `.transcribing`; transcript appears once
  download + prepare complete.

## #075 — Short-hold no longer wedges entry points (2026-04-24)

Pre-fix: releasing a hold under 1 second published `.error(.recordingTooShort)`.
The pill showed "Too short — try again" AND the response card showed
the same message. Next hold/tap-hotkey/pill-click was a no-op —
entry-point guards rejected `.error` and there was no clean recovery
path. Post-fix: short-hold publishes `.shortExit` (non-error terminal);
display-state maps it to `.idle` so every entry point accepts the next
action; the pill shows the chip alone for 1.5s; the response card
renders nothing.

- [ ] **MV-SHORT-1** Hold the hotkey briefly (< 1s), release. Pill
  shows "Too short — try again" chip for ~1.5s, then fades. **The
  response card does NOT appear** — the pill is the sole surface.
- [ ] **MV-SHORT-2** Immediately after MV-SHORT-1's chip appears
  (within or after the 1.5s window), hold the hotkey again for ~1s
  and speak. Recording starts cleanly; transcript pastes. No wedge.
- [ ] **MV-SHORT-3** Same as MV-SHORT-1, but instead of a second hold,
  tap the hotkey (double-tap ⌥, or the configured shortcut). New
  recording starts cleanly. No wedge.
- [ ] **MV-SHORT-4** Same as MV-SHORT-1, but click the pill after
  the chip appears. New recording starts cleanly. No wedge.
- [ ] **MV-SHORT-5** After MV-SHORT-1, wait past the 1.5s chip TTL
  without any interaction. Pill returns to idle/hidden on its own —
  no stale chip, no stuck state.
- [ ] **MV-SHORT-6** Regression guard for real errors: deny mic
  permission (or trigger another real error) to confirm the response
  card still shows a full error description for genuine errors,
  distinguishing them from the (pill-only) short-exit chip.

## #017 — Hotkey customization (Stage A, 2026-04-24)

Ticket: `plans/backlog/#017` — split across Steps 1.1–1.4 in a single
landing lane.

Covers: restore-default affordance, intra-app reserved registry (Esc),
plist-backed system-shortcut collision detection with disabled-shortcut
warning, live apply (no relaunch).

- [ ] **MV-HK-1** Settings → General → Shortcuts. Press "Change…",
  capture a non-default combination (e.g. `⌘⇧R`). Confirm. Without
  relaunching, press `⌘⇧R` from another app — recording starts. Press
  again — recording stops and transcript pastes. Press the default
  `opt + /` — nothing happens (old binding is gone). This is the live-
  apply invariant from Step 1.4.
- [ ] **MV-HK-2** With a non-default shortcut active, the "Restore
  default" button on the shortcut card is enabled. Click it — the card
  flips to `⌥/` and the next `opt + /` press starts recording. With
  the default already selected, the button is greyed out.
- [ ] **MV-HK-3** Press "Change…". While the recorder is open, attempt
  to bind **Spotlight**'s shortcut (usually `⌘Space`). The recorder
  displays a red-style rejection line naming "Spotlight" (or whatever
  your system maps it to) and the **Set** button stays disabled.
  Separately, try to bind any combination that includes **Escape**
  (e.g. `⌘Esc`) — rejection names Escape. Plain `Esc` cancels the
  recorder as before.
- [ ] **MV-HK-4** Disable one of your system shortcuts in System
  Settings → Keyboard → Keyboard Shortcuts (e.g. toggle Spotlight off).
  Re-open Ninimma's recorder and press the disabled combination. The
  recorder shows a yellow-style warning naming the disabled system
  shortcut — and the **Set** button is enabled. Confirm and verify the
  new binding fires. Re-enable the system shortcut after the test.

- [ ] **MV-SHORT-7 — Hotkeys don't depend on Accessibility (DECISIONS #25):**
  With Ninimma running, switch it off under System Settings → Privacy &
  Security → Accessibility. Typing in every app stays responsive, and
  ⌥/ still starts and stops a recording; the transcript lands on the
  clipboard with "Copied · enable Accessibility to auto-paste". Switch
  Accessibility back on; the next dictation auto-pastes.

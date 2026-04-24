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

## CGEventTap swallow — `÷÷÷÷` leak fix (bug #5a-v1 c2)

`GlobalHotkeyMonitor`'s global path now uses a `CGEventTap` instead of
`NSEvent.addGlobalMonitorForEvents`. The tap sits at
`.cgSessionEventTap` + `.headInsertEventTap`, can return `nil` from its
callback, and swallows matching ⌥+/ events system-wide — so `÷`
keystrokes no longer leak into focused apps.

- [x] **MV-HK-8** Open any other app (Notes, TextEdit, Safari address
  bar) and click into a text field so it owns focus. **Tap ⌥+/ once**
  — recording starts, and the text field stays empty (no stray `÷`
  character). Tap again — recording stops, still no `÷`. Regression
  guard for 5a's CGEventTap swallow on tap/double-tap.
  Verified 2026-04-21 on DMG.
- [x] **MV-HK-9** Same setup. **Hold ⌥+/ for ~1.5s, then release.**
  The text field stays empty throughout — no `÷÷÷÷` stream from auto-
  repeat keyDowns. Pre-5a this leaked; post-5a the tap consumes each
  repeat before it reaches the target app. Regression guard for the
  auto-repeat swallow.
  Verified 2026-04-21 on DMG.
- [x] **MV-HK-10** ~~Grant Input Monitoring permission freshly (e.g.
  remove Ninimma from the list in System Settings → Privacy & Security
  → Input Monitoring, relaunch). The hotkey should fail silently until
  re-granted, then start working on re-grant without a second relaunch.
  Confirms `CGEvent.tapCreate` nil handling routes through the existing
  permission-failure path.~~
  **Premise stale post-5a.** `.cgSessionEventTap` + `.headInsertEventTap`
  can be satisfied by *either* Input Monitoring or Accessibility on
  modern macOS; our app grants Accessibility for paste synthesis
  (`ClipboardBatchOutput.swift:54`), so removing Input Monitoring alone
  doesn't disable the hotkey. To actually exercise the fail-open path,
  revoke BOTH Input Monitoring AND Accessibility for Ninimma before
  relaunch. Verified 2026-04-21: accessibility-grant path carries the
  tap cleanly; permission-probe plumbing covered by
  `InputMonitoringPermissionProbeTests`.
- [x] **MV-HK-11** Press a plain `/` (no option) in another app's text
  field. The `/` character types normally — tap swallow is scoped to
  the matching hotkey, not all keyDowns. Regression guard for the
  swallow-decision logic.
  Verified 2026-04-21 on DMG.

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

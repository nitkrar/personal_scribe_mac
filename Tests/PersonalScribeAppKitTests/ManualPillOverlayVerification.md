# Pill Overlay — Manual Verification Runbook

SwiftUI view bodies cannot be fully asserted in XCTest — the items below
require a runtime build (DMG install or `swift run`) and visual
inspection. Tick each box the first time you dogfood a change that
touches the pill overlay.

Reference mockups live at:
- `plans/seshat_agent_bundle/03_Surfaces/PillOverlayWindow/architecture.png`
- `plans/seshat_agent_bundle/03_Surfaces/PillOverlayWindow/command_mode_states.png`
- `plans/seshat_agent_bundle/03_Surfaces/PillOverlayWindow/recording_states.png`
- `plans/seshat_agent_bundle/03_Surfaces/PillOverlayWindow/light_mode_states.png`

---

## Baseline (Sprint 1 — still valid after rewrite)

1. Launch the app and click `Record`.
2. Confirm the pill fades in at the bottom center of the visible screen area.
3. Confirm the recording state shows the quill glyph (listening) + an
   animated waveform + stop glyph — NOT the legacy three pulsing dots.
4. Click `Stop` and confirm the pill transitions in place to the quill +
   `Transcribing…` rather than fully dismissing immediately.
5. After transcription completes, confirm the pill fades out smoothly in
   auto-show mode (or returns to the idle layout in always-on).

---

## Sprint 2 Lane B1 — Three visibility modes

### Mode 1 — Always On

Setup: set `defaults write com.nitkrar.personal_scribe PillVisibilityMode "always-on"`
and relaunch.

- [ ] **MV-B1-1** At rest (no recording) the pill is VISIBLE at the
  bottom of the screen, rendered as a compact 180×34pt capsule
  containing the quill glyph (idle wave) + "Idle" label. NOT a bare
  dot (that was the Sprint 1 behaviour that BUG-10 closed).
- [ ] **MV-B1-2** Starting a recording swaps the idle pill in place into
  the recording layout — no full fade-out / fade-in cycle.

### Mode 2 — Auto-show (default)

Setup: `defaults delete com.nitkrar.personal_scribe PillVisibilityMode` and
relaunch — this exercises the first-launch default path.

- [ ] **MV-B1-3** At rest the pill is HIDDEN. Only the menu bar status
  item is visible. Starting a recording slides the pill in from the
  bottom. Stopping transcription and the pill fades out to hidden
  again. Matches `architecture.png` Mode 2 row.

### Mode 3 — Hidden

Setup: `defaults write com.nitkrar.personal_scribe PillVisibilityMode "hidden"`
and relaunch.

- [ ] **MV-B1-4** The pill never appears, not even during recording or
  transcription. The menu bar remains the only user-reachable surface.
  Invariant held because Phase 2 does not ship a menu-bar-hide toggle.

---

## Sprint 2 Lane B1 — Waveform decay coast-down

Toggle `WaveformDecayMode` via
`defaults write com.nitkrar.personal_scribe WaveformDecayMode "…"`.

- [ ] **MV-B1-5 (immediate default)** Record a loud sentence, then stop.
  The waveform SNAPS flat to zero on stop (this is the Sprint 1
  behaviour retained as the default).
- [ ] **MV-B1-6 (animated)** Flip the default to `"animated"` and
  relaunch. Record a loud sentence, then stop. The waveform fades from
  the last-known bar heights to zero smoothly over roughly 500 ms, then
  snaps. No bounce, no overshoot — strictly linear interpolation.

---

## Slice A — Clipboard-only fallback notice

Leave `PasteMode` unset (default `"paste-at-cursor"`) unless a step
below tells you to change it.

- [ ] **MV-B1-7 (self-frontmost fallback)** Start a recording by clicking
  the pill or the menu-bar `Start Recording` item so Ninimma is the
  frontmost app. Speak a short sentence, stop, and confirm the text is
  NOT pasted into Ninimma itself. Instead, a response card appears above
  the pill reading `Copied to clipboard · ⌘V to paste`, dismisses after
  roughly 3 seconds, and the transcript pastes successfully into
  TextEdit with a manual `⌘V`.
- [ ] **MV-B1-8 (clipboard-only mode)** Run
  `defaults write com.nitkrar.personal_scribe PasteMode "clipboard-only"`
  and relaunch. Trigger dictation from another app while its text cursor
  is active (hotkey or menu path). Confirm Ninimma never posts a
  synthetic paste, the same response card appears for roughly 3 seconds,
  and the transcript is available only via clipboard/manual `⌘V`.

---

## Sine-wave animation during recording (9c4540a)

- [ ] **MV-B1-9 (sine-wave crawls)** Start a recording (hotkey, pill
  click, or menu item). Watch the centre of the recording pill: the
  sine wave must visibly travel horizontally, completing one full loop
  roughly every 1.2 s at ~30 fps. If the wave is rendered but frozen,
  `SineWaveView`'s `TimelineView(.animation)` driver has regressed.
  Stop recording and confirm the wave snaps to its static rest pose.

- [ ] **MV-B1-10 (brand-backed accessibility labels)** Use Accessibility
  Inspector or VoiceOver on the pill in idle, recording, and transcribing
  states, and on any surfaced error card. Confirm the labels read
  `<AppBrand.displayName> idle — double-tap right Option to record`,
  `<AppBrand.displayName> recording — tap to stop`,
  `<AppBrand.displayName> transcribing`, and
  `<AppBrand.displayName> error: …`.

---

## Record-without-transcribe — status card during model download

Wired in commit series `adb3b60..a63331c` (Apr 2026). Driven by
`RecordingStatusCardDriver.statusText(sessionState:progress:)` and shown
via `PillOverlayPresenter.showRecordingStatusCard(text:)` +
`updateRecordingStatusCard(text:)`.

**MV-RWT-1 — First-launch record during download.**
1. Fresh install (no model on disk). Grant mic + input-monitoring.
2. Hit the record hotkey immediately (before model finishes downloading).
3. Confirm the pill enters the `.recording` variant as normal.
4. Confirm a ResponseCard fades in above the pill with text
   `"Recording — transcribing when model is ready (NN%)"`. NN% updates
   live as the download progresses — no flash, no rebuild.
5. When the phase switches to `.loading`, confirm the card text updates
   to `"Recording — model loading, transcription starts shortly"`.
6. Stop the recording. Confirm the pill goes to `.transcribing` and the
   card text changes to
   `"Waiting — finishing model download (NN%)"` (if download is still
   running) or
   `"Waiting — model loading"` (if load is in flight).
7. When the model reaches `.finished`, confirm the card dismisses
   automatically (150ms fade) and the normal transcribe → done →
   clipboard flow runs. Audio is NOT lost — captured transcript matches
   what was spoken.

**MV-RWT-2 — Hotkey during an established download (Settings switch).**
1. App already has a working model. Go to Modes tab and switch to a
   model variant that is NOT yet downloaded.
2. As `DefaultModelService.setActive` kicks off the download, hit the
   record hotkey.
3. Confirm the ResponseCard appears with the progress text and updates
   live.

**MV-RWT-3 — No card when the model is ready.**
1. With the model already prepared (`.finished` in the app state),
   record + stop normally.
2. Confirm NO ResponseCard appears at any point in the record →
   transcribe → done flow. Only the clipboard-only notice (if triggered)
   should ever flash.

**MV-RWT-4 — Card text never leaks during idle/error.**
1. Trigger an error path (e.g. record-too-short by tapping stop within
   500ms of start).
2. Confirm the pill shows the error message and NO ResponseCard appears
   concurrently.

---

## Non-activating panel (Issue 6 — 2026-04-21)

The pill panel must not promote Ninimma to frontmost on click. Verified
in unit tests by asserting `canBecomeKey == false` + `canBecomeMain == false`
on `DraggablePanel`, but the real-world effect is only observable at runtime.

- [ ] **MV-NAP-1 (pill click preserves prior frontmost)** Bring Slack (or
  any text-input app) to the front and place the cursor in a compose
  field. Start a recording via the hotkey so the pill appears without
  changing focus. Speak a sentence. Stop by clicking the pill itself.
  Immediately observe: Slack's window chrome remains active (title bar
  not dimmed), and the transcript pastes directly into the Slack
  compose field — **no `Copied to clipboard · ⌘V to paste` card**.
  Regression: if the card appears, `DraggablePanel.canBecomeKey` has
  been flipped back to `true`.
- [ ] **MV-NAP-2 (pill click does not change menu-bar focus)** Open
  another app's menu (File menu in Finder is easy). Click the pill.
  Confirm the open menu does NOT close — clicking a non-activating
  panel should not deliver a system click that dismisses other menus.
- [ ] **MV-NAP-3 (menu-bar stop path preserves prior frontmost)** Same
  as MV-NAP-1 but stop via the status-item menu's `Stop Recording`
  row. Status-item menus are tracked separately by AppKit and should
  also preserve Slack as frontmost; transcript pastes into Slack.

---

## Pill UX redesign — 5-state interaction model (spec Claude_Pill_UX_Prompt.md, 2026-04-21)

End-to-end runbook for Phases 1-6 (state machine + visuals + hotkey +
Cancel Card + clipboard Undo + Esc monitor). Run in order after any
rebuild that touches `Sources/PersonalScribeAppKit/Overlay/` or
`Sources/PersonalScribeAppKit/Hotkeys/`.

### Visual states (spec §2)

- [ ] **MV-PUX-1 (idle)** At rest, pill is 80×28 with an 8pt champagne
  quill dot centered and a 1px white-8%-opacity border. Radius 14pt.
- [ ] **MV-PUX-2 (hold-to-record)** Press and HOLD `opt + /`. Within
  ~300ms the pill expands to 160×36 showing a 7-bar vertical equaliser
  with a 1.5px Clay (#C9A96E) border and 18pt radius. Bars respond to
  your voice (silence → minimum-height baseline, speaking → taller
  bars). Release the key — pill transitions to transcribing.
- [ ] **MV-PUX-3 (recording — committed via tap)** Tap `opt + /` once
  (press + release under 300ms). Pill becomes 220×36 with ✕ on the
  left, sine waveform centre, red stop ⏹ on the right. Clay border.
  Tap `opt + /` again or click ⏹ to stop.
- [ ] **MV-PUX-4 (transcribing)** After stop, pill becomes 160×36 with
  a spinner + "Transcribing…" text. 1px Champagne @ 40% opacity
  border, 18pt radius.
- [ ] **MV-PUX-5 (done)** After transcription, pill briefly shows a
  green checkmark in a 100×32 rect with a 1px Green (#50C878) border
  and 16pt radius. Auto-returns to idle within ~1.2s.

### Hotkey gestures (spec §3)

- [ ] **MV-PUX-6 (single tap toggles recording)** Tap `opt + /` once —
  pill transitions idle → recording. Tap again — pill transitions
  recording → transcribing → done → idle, transcript pasted into
  frontmost app's cursor if AX focused element has a cursor (Issue 1
  AX probe).
- [ ] **MV-PUX-7 (double-tap alias)** Tap `opt + /` twice in rapid
  succession (< 400ms between taps). Pill should start recording
  ONCE, not start-and-immediately-stop. The second tap is debounced
  silently.
- [ ] **MV-PUX-8 (hold → release transcribes)** Hold `opt + /` for
  more than 300ms. Pill enters hold-to-record state. Speak. Release
  — pill transitions immediately to transcribing without needing a
  stop click. For short dictations this is the fastest path.
- [ ] **MV-PUX-9 (default on fresh install)** `defaults delete
  com.nitkrar.personal_scribe RecordingHotkey` and relaunch. Confirm
  the default persists as `opt + /` (no right-Option double-tap
  legacy). Persisted custom hotkeys from prior versions may need to
  be reset manually.

### Cancel Card + Undo (spec §2f + §3 + §4)

- [ ] **MV-PUX-10 (Esc while recording → Cancel Card)** Start a
  recording. Press Esc. Pill surface is replaced by a 280×44 rounded
  rect with a 1.5px Red (#F75138) border, cooler-navy (#1E2032)
  background, "Recording cancelled" on the left, and an Undo button
  on the right (clay text on dark fill, rounded 8pt corners).
- [ ] **MV-PUX-11 (Esc while hold-to-record → Cancel Card)** Hold
  `opt + /` for >300ms to enter hold-to-record. Press Esc while still
  holding. Cancel Card appears; releasing the hold key afterward does
  nothing (no transcribing).
- [ ] **MV-PUX-12 (Esc outside recording is a no-op)** With the pill
  idle, press Esc. Nothing visible happens — Esc should not intercept
  when the pill isn't active. You can still use Esc in other apps /
  dialogs.
- [ ] **MV-PUX-13 (Cancel Card auto-dismiss)** Trigger a Cancel Card.
  Wait 4 seconds. Card fades out and the pill returns to idle.
- [ ] **MV-PUX-14 (Undo restores pre-recording clipboard)** Copy some
  unique string (e.g., "pre-recording clipboard") into your clipboard
  BEFORE starting a recording. Start a recording, transcribe it (so
  the transcript auto-pastes into a text field and overwrites the
  clipboard), then trigger a Cancel Card via Esc, then click Undo
  on the Cancel Card within 4 seconds. Confirm your clipboard now
  contains "pre-recording clipboard" again, not the transcript.

### Esc global monitor — regression guards

- [ ] **MV-PUX-15 (Cmd+Esc passes through)** With the pill idle, press
  Cmd+Esc. The normal system / frontmost-app handler should receive
  the event unaffected (typically nothing visible, but specific apps
  may bind Cmd+Esc — confirm no regression there).
- [ ] **MV-PUX-16 (Esc in a text field is unaffected while pill idle)**
  Focus a text field in any other app. Press Esc. Normal Esc
  behaviour for that field (e.g., dismissing a dropdown) should fire
  — we should not intercept.
- [ ] **MV-PUX-17 [DEFERRED] (full-screen space triage / bug #5b.C)**
  `AppKitPillOverlayPanelBuilder.makePanel` in
  `Sources/PersonalScribeAppKit/Overlay/PillOverlayPresenter.swift`
  already sets `panel.collectionBehavior = [.canJoinAllSpaces,
  .stationary, .fullScreenAuxiliary]`, and
  `PillOverlayPresenter.show()` already uses `orderFrontRegardless()`.
  If the pill still renders off the active full-screen app space at
  runtime, investigate placement and visibility flow next:
  `updatePanelPosition(_:)` anchors to `NSScreen.main?.visibleFrame`,
  which may not match the active full-screen space, and the
  presenter/controller visibility pipeline should be checked for any
  transient `.hidden` bounce before the panel is ordered front.

## Known spec deviations (flagged in commits)

- Esc currently lets the recording transcribe + auto-paste, and the
  user clicks Undo to revert the paste. True "discard audio without
  transcribing" requires a new `SessionCoordinator.cancelRecording()`
  method — deferred to a Phase 8 follow-up.

## Notes

- Manual checklist entries above are the only verification path for the
  SwiftUI `body` parts of `PillOverlayView`. Unit-tested pieces (view
  model visibility mapping, decay math, presenter `intendsToShow`, etc.)
  live under `Tests/PersonalScribeAppKitTests/` and `Tests/PersonalScribeCoreTests/`.
- Light-mode parity check: flip macOS Appearance to Light and repeat
  MV-B1-1 + MV-B1-5 to confirm palette resolution.

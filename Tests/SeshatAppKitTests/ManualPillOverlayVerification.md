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

Setup: set `defaults write com.nitkrar.seshat SeshatPillVisibilityMode "always-on"`
and relaunch.

- [ ] **MV-B1-1** At rest (no recording) the pill is VISIBLE at the
  bottom of the screen, rendered as a compact 180×34pt capsule
  containing the quill glyph (idle wave) + "Idle" label. NOT a bare
  dot (that was the Sprint 1 behaviour that BUG-10 closed).
- [ ] **MV-B1-2** Starting a recording swaps the idle pill in place into
  the recording layout — no full fade-out / fade-in cycle.

### Mode 2 — Auto-show (default)

Setup: `defaults delete com.nitkrar.seshat SeshatPillVisibilityMode` and
relaunch — this exercises the first-launch default path.

- [ ] **MV-B1-3** At rest the pill is HIDDEN. Only the menu bar status
  item is visible. Starting a recording slides the pill in from the
  bottom. Stopping transcription and the pill fades out to hidden
  again. Matches `architecture.png` Mode 2 row.

### Mode 3 — Hidden

Setup: `defaults write com.nitkrar.seshat SeshatPillVisibilityMode "hidden"`
and relaunch.

- [ ] **MV-B1-4** The pill never appears, not even during recording or
  transcription. The menu bar remains the only user-reachable surface.
  Invariant held because Phase 2 does not ship a menu-bar-hide toggle.

---

## Sprint 2 Lane B1 — Waveform decay coast-down

Toggle `SeshatWaveformDecayMode` via
`defaults write com.nitkrar.seshat SeshatWaveformDecayMode "…"`.

- [ ] **MV-B1-5 (immediate default)** Record a loud sentence, then stop.
  The waveform SNAPS flat to zero on stop (this is the Sprint 1
  behaviour retained as the default).
- [ ] **MV-B1-6 (animated)** Flip the default to `"animated"` and
  relaunch. Record a loud sentence, then stop. The waveform fades from
  the last-known bar heights to zero smoothly over roughly 500 ms, then
  snaps. No bounce, no overshoot — strictly linear interpolation.

---

## Slice A — Clipboard-only fallback notice

Leave `SeshatPasteMode` unset (default `"paste-at-cursor"`) unless a step
below tells you to change it.

- [ ] **MV-B1-7 (self-frontmost fallback)** Start a recording by clicking
  the pill or the menu-bar `Start Recording` item so Seshat is the
  frontmost app. Speak a short sentence, stop, and confirm the text is
  NOT pasted into Seshat itself. Instead, a response card appears above
  the pill reading `Copied to clipboard · ⌘V to paste`, dismisses after
  roughly 3 seconds, and the transcript pastes successfully into
  TextEdit with a manual `⌘V`.
- [ ] **MV-B1-8 (clipboard-only mode)** Run
  `defaults write com.nitkrar.seshat SeshatPasteMode "clipboard-only"`
  and relaunch. Trigger dictation from another app while its text cursor
  is active (hotkey or menu path). Confirm Seshat never posts a
  synthetic paste, the same response card appears for roughly 3 seconds,
  and the transcript is available only via clipboard/manual `⌘V`.

---

## Notes

- Manual checklist entries above are the only verification path for the
  SwiftUI `body` parts of `PillOverlayView`. Unit-tested pieces (view
  model visibility mapping, decay math, presenter `intendsToShow`, etc.)
  live under `Tests/SeshatAppKitTests/` and `Tests/SeshatCoreTests/`.
- Light-mode parity check: flip macOS Appearance to Light and repeat
  MV-B1-1 + MV-B1-5 to confirm palette resolution.

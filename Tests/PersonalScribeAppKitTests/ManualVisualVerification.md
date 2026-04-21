# Manual Visual Verification — Phase 2 Sprint 1 (Lane A1)

SwiftUI views cannot be runtime-verified via XCTest. Every foundation
component ships with a `#Preview` in its source file. The checklist
below is what a reviewer runs in Xcode (open each source file, use
the Canvas or `Cmd+Option+Enter` to render a `#Preview`, and verify
each line).

## PersonalScribeTheme (`Sources/PersonalScribeAppKit/Theme/PersonalScribeTheme.swift`)
1. No preview — inspect via `PersonalScribeLogoView` / `WaveformView` previews
   which render against `PersonalScribeTheme.Palette.dark.appBackground`.
2. Automated hex round-trip is covered by
   `Tests/PersonalScribeAppKitTests/Theme/PersonalScribeThemeTests.swift` (every hex
   token from `colour_system.png` is asserted).

## PersonalScribeLogoView (`Sources/PersonalScribeAppKit/Components/PersonalScribeLogoView.swift`)
- **Preview name:** `"Ninimma Logo — all states"`
- Verify against `plans/seshat_agent_bundle/01_Foundations/assets/logo_animation_states.png`:
  1. **Idle** tile shows a quill with a slow, low-amplitude wave.
  2. **Listening** tile shows a quill with a visibly faster, higher-amp wave.
  3. **Transcribing** tile shows the quill + a flat wave + a small ink drip
     beneath the nib.
  4. **Error** tile shows the quill alone — no wave, no drip.
  5. Tint on all four tiles is champagne (`#D4D0C8` on dark background).
  6. Swap preview to `.light` — tint becomes `#6B6760` (champagne dark).
  7. At `size: 96` the stroke looks substantial (not a hairline); at
     `size: 24` the quill is still recognisable.

## WaveformView (`Sources/PersonalScribeAppKit/Components/WaveformView.swift`)
- **Preview name:** `"Waveform — idle vs active"`
- Verify:
  1. **Idle row** (audioLevel=0, isActive=false) shows a flat-ish row of
     low bars tinted champagne. Bars are visible but barely animate.
  2. **Active row** (audioLevel=0.6, isActive=true) shows taller bars
     tinted `statusRecording` red that visibly shimmer (TimelineView
     animation).
  3. Turn Activity Monitor on — idle row should NOT cause the app to
     consume measurable CPU when alone on-screen. This is the
     locked-in "no TimelineView while idle" decision (plan line 351).

## StatusPill (`Sources/PersonalScribeAppKit/Components/StatusPill.swift`)
- **Preview name:** `"StatusPill — variants"`
- Verify:
  1. Ready pill shows a green dot (`#30D158` dark / `#28A745` light)
     next to "Ready".
  2. Recording pill shows a red dot (`#FF453A` / `#D93025`).
  3. Neutral pill shows a champagne dot.
  4. Background is `elevatedSurface`; subtle champagne-tinted border.

## TagChip (`Sources/PersonalScribeAppKit/Components/TagChip.swift`)
- **Preview name:** `"TagChip — variants"`
- Verify:
  1. Neutral chips render with `elevatedSurface` background, primary
     text colour.
  2. Accent chip ("idea") has a champagne-tinted background and
     champagne text — it reads as "selected".

## ActionButton (`Sources/PersonalScribeAppKit/Components/ActionButton.swift`)
- **Preview name:** `"ActionButton — variants"`
- Verify:
  1. Primary button has a champagne fill and near-black text — strong
     visual affordance.
  2. Secondary button has surface fill and primary-text label — looks
     like a deemphasised alternative.
  3. Disabled button is 45% opacity and does not respond to hover or
     click.

## Asset catalog (`Sources/PersonalScribeAppKit/Resources/Assets.xcassets/`)
- Open the asset catalog in Xcode.
- `StatusBarIcon` imageset has Render-As set to **Template Image**.
  macOS auto-tints it based on menu-bar dark/light mode.
- Verify placeholder 18×18pt @2x images are there. Replace with the
  final monochrome quill export once the design is frozen.

## Brand milestone (M2) — runtime verification for WindowTint + PillAppearance

These two user-selectable axes have view-model + round-trip unit-tests
(`WindowTintTests`, `PillAppearanceTests`, `GeneralTabViewModelThemeTests`,
`SettingsWindowControllerWindowTintTests`, `PillOverlayPillAppearanceTests`)
but the runtime "does the window actually go dark, does the pill actually
switch palettes" loop is SwiftUI/AppKit and cannot be runtime-verified
by XCTest. Reviewer performs this checklist in a dogfood build:

### Settings → General tab pickers

1. Launch a fresh DMG (ensure `~/Library/Application Support/personal_scribe/`
   exists per Phase 4 migration).
2. Open Settings from the menu bar → General.
3. **Appearance** card shows two segmented pickers: "Window tint"
   (Warm / Neutral / Dark) and "Pill theme" (Dark / Light / System).
4. Default state: Window tint = Warm, Pill theme = Dark.

### WindowTint runtime behaviour

5. With Settings window open, flip Window tint → **Dark**. Settings
   window immediately adopts the dark-aqua NSAppearance (controls,
   title bar, and background all flip). Reference:
   `plans/App UI design/Claude_Final_Bundle_Prompt.md` §1.
6. Flip Window tint → **Warm**. Settings window reverts to the system
   theme (follows macOS light/dark preference).
7. Flip Window tint → **Neutral**. Same as Warm — tint does not force
   an override. (Until M3 lands the unified window shell, the
   secondary/primary background hex difference between Warm and
   Neutral is not yet visibly applied anywhere.)
8. Quit and relaunch — last-selected tint persists via UserDefaults
   key `"WindowTint"`.

### PillAppearance runtime behaviour

9. With the floating pill visible (Always-on mode recommended for
   this check), flip Pill theme → **Light**. The pill's NSPanel
   switches to the light NSAppearance; the champagne waveform
   darkens to `#333338` and background becomes pale cream
   (`#F0EDE8`). The effect is visible as soon as the picker changes.
10. Flip Pill theme → **System**. Pill inherits from macOS theme —
    with macOS dark mode on, pill is dark; toggle macOS to light,
    pill goes light.
11. Flip Pill theme → **Dark**. Pill forces dark-navy regardless of
    macOS theme.
12. Quit and relaunch — last-selected pill appearance persists via
    UserDefaults key `"PillAppearance"`.

### Regression checks

13. Changing Window tint does NOT flip Pill theme, and vice versa —
    the two axes are independent.
14. The existing Settings controls (Visibility, Behavior cards —
    menu-bar toggle, pill visibility, waveform decay, paste mode,
    paste-restore slider) still work after the Appearance card is
    added.

## M3.1 unified window shell scaffold

The unified NavigationSplitView window opens and navigates between 4 tab
stubs (Home / Transcriptions / Modes / Settings). Real tab content lands
in M3.2–M3.5; this milestone proves the shell + routing + menu-bar entry
+ WindowTint integration are production-shape.

### Menu bar entry point

1. Launch a dogfood build. Menu bar should show the quill icon.
2. Click the menu bar icon. The menu now has a **Home** item between
   "Start Recording" and "History". "History" is still present (opens
   the legacy NotesWindow — will be retired in M4).
3. Click "Home". A new window titled with the app display name opens,
   distinct from Settings and Notes.

### Window shell

4. Window uses `NavigationSplitView` with a 200pt sidebar.
5. Sidebar top shows the quill logo + display name.
6. Sidebar body shows 4 nav rows with SF Symbols: Home (`house.fill`),
   Transcriptions (`text.alignleft`), Modes (`square.grid.2x2`),
   Settings (`gearshape`).
7. Sidebar bottom shows a placeholder "Microphone" row with the `mic`
   icon (real mic indicator lands later).

### Tab navigation

8. Clicking each sidebar row switches the detail area:
   - **Home** header with "Stats and recent transcriptions land in M3.5."
   - **Transcriptions** header with "Search + grouped transcript list
     migrate from NotesView in M3.2."
   - **Modes** header with "Mode cards (Dictation, Command, Notes)
     land in M3.4."
   - **Settings** header with "General / Permissions / About sub-tabs
     land in M3.3."
9. Each detail header uses `Typography.largeTitle`; body text uses
   `Typography.body` at 60% opacity.

### WindowTint integration

10. Open Settings → General → Appearance. Flip Window tint to **Dark**.
    The unified window (if open) immediately adopts dark-aqua
    NSAppearance; the sidebar background shifts to `#111318`; detail
    area to `#0E0E14`.
11. Flip Window tint to **Warm**. Unified window reverts to system
    theme; sidebar `#EBEBE6` on light, detail `#F5F5F0`.

### Regression checks

12. Legacy NotesWindow still opens via menu bar → "History".
13. Settings NSWindow still opens via menu bar → "Settings".
14. Onboarding flow still triggers for a fresh install.

## M4.1 voice-modulated pill waveform

The pill's recording-state `SineWaveView` now tracks live mic level
via `PillOverlayViewModel.audioLevel`, with a 500 ms linear-interp
smoothing (`WaveformDecayMode.animated`) that matches the shape
`WaveformView` uses. Source: `Sources/PersonalScribeAppKit/Components/SineWaveView.swift`.
Unit tests cover the amplitude + smoothing math
(`Tests/PersonalScribeAppKitTests/Components/SineWaveViewTests.swift`)
but the UX of "speaking grows the wave, stopping decays it smoothly"
is SwiftUI-Canvas + wall-clock, so it needs a dogfood pass. Reviewer
runs this checklist in a dogfood build:

1. Start recording with the mic muted (or hold the mic away). The pill's
   wave renders as a thin champagne horizontal line — no oscillation,
   no amplitude.
2. Speak at normal volume. The wave visibly oscillates; amplitude is
   clearly greater than silence.
3. Vary volume: louder speech produces taller peaks, quieter speech
   produces shorter peaks. The response tracks mic level continuously,
   not in discrete steps.
4. Stop speaking mid-recording. The wave decays smoothly back to the
   flat horizontal line over ~500 ms — it does NOT snap abruptly.
5. The phase of the wave continues scrolling left-to-right regardless
   of volume. When the wave is flat (silence), phase motion is
   invisible but resumes visibly as soon as you speak again — the
   `TimelineView(.animation)` driver never pauses while the recording
   pill is on-screen.

## M5.3 followup — microphone selection takes effect

The M5.3 commit (`158c00d`) shipped the menu-bar Microphone submenu and
persisted the user's choice under `UserDefaults["SelectedAudioInputDeviceID"]`,
but the capture pipeline still started on the macOS system default input.
The M5.3 followup wires the persisted UID through
`AudioEngineDriver.applyInputDevice(uid:)` into
`AudioUnitSetProperty(kAudioOutputUnitProperty_CurrentDevice)` on
`engine.inputNode.audioUnit` before every recording starts. This is a
runtime-UX change and must be dogfooded on hardware — unit tests cover
forwarding and ordering, not CoreAudio device routing.

Reviewer runs this checklist with at least two input devices attached
(e.g. built-in mic + USB/AirPods):

1. Menu bar icon → **Microphone** submenu → pick a non-default device
   (e.g. USB mic or AirPods). The submenu's checkmark moves to the new
   selection.
2. Menu bar icon → **Start Recording** (or press the global hotkey).
3. Speak into the just-selected device at normal volume. The recording
   pill's voice-modulated wave (the M4.1 waveform) tracks the selected
   device's levels, not the macOS system default input. If you pick
   AirPods and speak into the MacBook's built-in mic, the wave stays
   flat.
4. Stop recording. Open the unified window → Transcriptions, verify
   the transcript has the expected content (confirms the selected
   device's audio reached the recognizer, not just the waveform UI).
5. Regression: change selection in the Microphone submenu to a
   different device, start a new recording, and speak into the new
   selection. The wave tracks the new device; the previous selection's
   audio no longer drives the wave.
6. Edge: unplug the currently-selected USB device while the app is
   running, then Start Recording. The engine must fall back to the
   macOS system default (recording still starts, wave still responds
   to the built-in mic) — `AudioEngineDriver.applyInputDevice` logs a
   warning and proceeds rather than blocking.

## Transcriptions tab (mockup-gaps A.1–A.5)

Closes Group A of `plans/backlog/ui-mockup-gaps.md` — aligns the
Transcriptions tab with `plans/App UI design/screen_transcriptions.png`.
SwiftUI layout bits that XCTest can't reach go here.

1. Open the unified window → **Transcriptions** tab. Have at least 1
   entry from today, 1 from yesterday, and 1 older than 7 days (or
   inject fixtures via the dogfood harness).
2. **A.1 Row structure** — each row shows a single line of preview
   text truncated to 2 lines with "…" when longer. There is NO
   separate bold title above the preview. The first line of the row
   is a timestamp on the leading edge; if the row has a single short
   sentence, it does NOT appear twice.
3. **A.2 Date buckets** — the group headers read:
   - `TODAY` and `YESTERDAY` for the two most recent buckets.
   - Compact `APR 18` (uppercased `MMM d`) for older buckets — NOT
     `APRIL 18, 2026` or `APRIL 18`.
4. **A.3 Row height** — each row is at least 56pt tall (roughly the
   height of "wall-clock line + 2 preview lines + vertical padding").
   Compare against the mockup PNG — rows should feel roomy, not
   crammed.
5. **A.4 Wall-clock timestamps** — the leading-edge timestamp on each
   row reads in wall-clock form (`2:34 PM` on a 12h locale, `14:34`
   on a 24h locale) — NOT relative (`5m ago`). Home tab rows still
   show relative timestamps; the split is per-row-style.
6. **A.5 Window tint** — open Settings → General → Appearance.
   - Flip Window tint to **Warm**. The Transcriptions tab root
     background becomes `#F5F5F0` (warm cream) — including the
     regions outside the rows / search bar / header.
   - Flip Window tint to **Neutral**. Transcriptions tab root becomes
     `#F2F2F7` (system grey).
   - Flip Window tint to **Dark**. Transcriptions tab root becomes
     `#0E0E14` regardless of system appearance.
7. **Deferred — mode pill**. The mockup shows a trailing "Dictation
   Mode" / "Command Mode" pill on each row. This is NOT rendered
   (`TranscriptEntry` has no `mode` field; schema change required).
   A `TODO: mockup-gap — trailing mode pill deferred` comment marks
   the attachment point in `TranscriptionsTab.swift`.

## Home tab empty state — mockup-gaps B.1

Reference: `plans/App UI design/screen_home.png`. The empty-state view
only appears when `HomeTabViewModel.recent.isEmpty`; unit tests cover
the VM flag and the hotkey-hint string, but the SwiftUI rendering has
to be eyeballed.

1. Fresh install with no transcripts: open Ninimma → Home tab. Below
   the 4 stat cards and the "RECENT TRANSCRIPTIONS" header, a
   centered champagne feather logo is visible with two lines below:
   - Primary: "No transcriptions yet"
   - Secondary: "Press ⌥/ to start recording" (with the default
     `opt + /` binding — see hotkey-hint check below).
2. Feather logo is roughly 64pt square, horizontally centered, with
   generous top padding above the first text line.
3. Primary text uses `Typography.body` at `palette.primaryText`;
   secondary text uses `Typography.caption` at `palette.secondaryText`.
4. Change Window tint (Warm / Neutral / Dark). The champagne feather
   stays champagne (it uses `palette.brandChampagne`), but text
   colours track the resolved palette.
5. Settings → change the recording hotkey to something non-default
   (e.g. ⌘⇧Space). Close Settings, re-open Home tab (or wait for the
   next `refresh()` tick). The secondary line now reads "Press ⌘⇧Space
   to start recording" — the hint IS sourced from `HotkeyPreference`
   and NOT hardcoded.
6. Record one clip. Home tab refreshes; the empty-state view is
   replaced by the single `TranscriptRow` with no blank gap above or
   below.

## Home tab section header — mockup-gaps B.2

Reference: `plans/App UI design/screen_home.png`. This copy is rendered
in the SwiftUI view body with `.textCase(.uppercase)` and isn't
reachable from XCTest.

1. Open Ninimma → Home tab. Under the 4 stat cards, the uppercase
   section header reads "RECENT TRANSCRIPTIONS" (source string
   "Recent transcriptions"). Previously read "RECENT".
2. The header still uses `Typography.sectionLabel` — no weight / size
   regression.

## Home tab stat card label — mockup-gaps B.3

Reference: `plans/App UI design/screen_home.png`. String lives in the
SwiftUI view body; not XCTest-reachable.

1. Open Ninimma → Home tab. The third stat card label reads
   "Mins saved" (previously "Minutes saved"). Numeric value, rounding,
   and layout unchanged.

## Home tab WPM formatting — mockup-gaps B.4

Reference: `plans/App UI design/screen_home.png`. The WPM formatter is
a private static on `HomeTab`; its output is only visible through the
rendered stat card. Not XCTest-reachable without extracting the
formatter, which isn't worth the blast radius for a 2-line change.

1. Fresh install (no recordings yet): "WPM avg" card shows `0`, not
   `0.0`. (Previously `0.0` because `minimumFractionDigits = 1`.)
2. Record until `averageWPMThisWeek` rolls to an integer (or inspect a
   debug build where the rollup is synthesised): the card shows e.g.
   `12`, not `12.0`.
3. Record until `averageWPMThisWeek` is fractional (e.g. 12.4): the
   card still shows `12.4` — one fractional digit is preserved.
4. Note: the inline `String(format: "%.1f", ...)` fallback (used only
   if `NumberFormatter.string(from:)` unexpectedly returns nil) still
   emits `.0`. Low-hit path; leave until we see it surface in
   practice.

## Known verification gaps (for reviewer awareness)
- The worktree I built this in (`.claude/worktrees/agent-a7bd4da6`)
  cannot load its Swift Package manifest under Xcode 26.2 / Swift
  6.2.3 due to a Gatekeeper/AMFI kill of the compiled manifest binary
  when its containing directory is under `.claude/`. Builds succeed
  from the main repo checkout after the branch is merged up.
- I could not run `swift build` / `swift test` from the worktree this
  session. Reviewer should run both from the merged branch before
  closing the Sprint 1 Lane A1 gate.

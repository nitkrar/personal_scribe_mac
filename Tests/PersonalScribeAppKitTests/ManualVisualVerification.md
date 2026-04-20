# Manual Visual Verification — Phase 2 Sprint 1 (Lane A1)

SwiftUI views cannot be runtime-verified via XCTest. Every foundation
component ships with a `#Preview` in its source file. The checklist
below is what a reviewer runs in Xcode (open each source file, use
the Canvas or `Cmd+Option+Enter` to render a `#Preview`, and verify
each line).

## SeshatTheme (`Sources/SeshatAppKit/Theme/SeshatTheme.swift`)
1. No preview — inspect via `SeshatLogoView` / `WaveformView` previews
   which render against `SeshatTheme.Palette.dark.appBackground`.
2. Automated hex round-trip is covered by
   `Tests/SeshatAppKitTests/Theme/SeshatThemeTests.swift` (every hex
   token from `colour_system.png` is asserted).

## SeshatLogoView (`Sources/SeshatAppKit/Components/SeshatLogoView.swift`)
- **Preview name:** `"Seshat Logo — all states"`
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

## WaveformView (`Sources/SeshatAppKit/Components/WaveformView.swift`)
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

## StatusPill (`Sources/SeshatAppKit/Components/StatusPill.swift`)
- **Preview name:** `"StatusPill — variants"`
- Verify:
  1. Ready pill shows a green dot (`#30D158` dark / `#28A745` light)
     next to "Ready".
  2. Recording pill shows a red dot (`#FF453A` / `#D93025`).
  3. Neutral pill shows a champagne dot.
  4. Background is `elevatedSurface`; subtle champagne-tinted border.

## TagChip (`Sources/SeshatAppKit/Components/TagChip.swift`)
- **Preview name:** `"TagChip — variants"`
- Verify:
  1. Neutral chips render with `elevatedSurface` background, primary
     text colour.
  2. Accent chip ("idea") has a champagne-tinted background and
     champagne text — it reads as "selected".

## ActionButton (`Sources/SeshatAppKit/Components/ActionButton.swift`)
- **Preview name:** `"ActionButton — variants"`
- Verify:
  1. Primary button has a champagne fill and near-black text — strong
     visual affordance.
  2. Secondary button has surface fill and primary-text label — looks
     like a deemphasised alternative.
  3. Disabled button is 45% opacity and does not respond to hover or
     click.

## Asset catalog (`Sources/SeshatAppKit/Resources/Assets.xcassets/`)
- Open the asset catalog in Xcode.
- `StatusBarIcon` imageset has Render-As set to **Template Image**.
  macOS auto-tints it based on menu-bar dark/light mode.
- Verify placeholder 18×18pt @2x images are there. Replace with the
  final monochrome quill export once the design is frozen.

## Known verification gaps (for reviewer awareness)
- The worktree I built this in (`.claude/worktrees/agent-a7bd4da6`)
  cannot load its Swift Package manifest under Xcode 26.2 / Swift
  6.2.3 due to a Gatekeeper/AMFI kill of the compiled manifest binary
  when its containing directory is under `.claude/`. Builds succeed
  from the main repo checkout after the branch is merged up.
- I could not run `swift build` / `swift test` from the worktree this
  session. Reviewer should run both from the merged branch before
  closing the Sprint 1 Lane A1 gate.

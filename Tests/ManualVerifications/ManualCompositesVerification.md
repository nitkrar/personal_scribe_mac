# Manual Composites Verification — Phase 2 Sprint 2 (Lane B2)

SwiftUI view bodies cannot be fully runtime-verified via XCTest. Every
composite in this lane ships with a `#Preview` in its source file. The
checklist below is what a reviewer runs in Xcode (open each source
file, use the Canvas or `Cmd+Option+Enter` to render a `#Preview`, and
verify each line) against
`plans/seshat_agent_bundle/02_Composites/component_map.png`.

## TranscriptRow (`Sources/PersonalScribeAppKit/Components/TranscriptRow.swift`)
- **Preview name:** `"TranscriptRow — variants"`
- Verify:
  1. First row shows title "Product sync notes", timestamp "Just now",
     and a single-line body preview — reads as a natural history entry.
  2. Second row has a visibly long title that truncates mid-word with
     an ellipsis (`…`); the timestamp "45m ago" sits flush-right and
     does not wrap.
  3. Third row (`isSelected: true`) has a hover-state background fill
     — it reads as "currently highlighted" but the surrounding
     champagne-tinted border matches every other row.
  4. Fourth row has an empty body — the row renders without a gap
     where the preview would be; only title + timestamp are visible.
  5. Body preview wraps at two lines max and truncates with `…` when
     longer (try lengthening the first row's body in the preview).
  6. Swap preview to `.light` — text contrast stays readable, surface
     fill becomes pale cream (`#FFFFFF`), border stays champagne.

## ModeCard (`Sources/PersonalScribeAppKit/Components/ModeCard.swift`)
- **Preview name:** `"ModeCard — active + inactive"`
- Verify:
  1. First card ("Dictation") shows `Active` pill (green dot) at the
     right edge; subtitle reads `"Voice: Parakeet-TDT · AI: Fast
     rewrite"` with a middle-dot (`·`) separator.
  2. Second + third cards ("Command", "Notes") show `Inactive` pill
     (neutral champagne dot).
  3. Mode-name typography is semibold body (13pt); subtitle is caption
     (11pt) at `secondaryText` opacity — the hierarchy is obvious.
  4. StatusPill hugs the trailing edge; it does NOT expand to fill.
  5. Swap to `.light` — surface becomes pure white, subtitle grey,
     active pill still visibly green.

## AudioPlayerThumbnail (`Sources/PersonalScribeAppKit/Components/AudioPlayerThumbnail.swift`)
- **Preview name:** `"AudioPlayerThumbnail — variants"`
- Verify:
  1. First row (`durationSeconds: 12`) shows label `"0:12"` with a
     short static waveform. Waveform is **static** — no shimmer.
  2. Second row (`75`) shows `"1:15"`.
  3. Third row (`3_725`) shows `"1:02:05"` — the `h:mm:ss` format
     kicks in above an hour.
  4. Waveform tint is champagne (`#D4D0C8` on dark / `#6B6760` on
     light) — it is NOT the red `statusRecording` variant. Confirms
     `isActive: false` is being honoured.
  5. Duration label uses monospaced digits — numbers don't shift
     horizontally as they change between previews.
  6. Turn Activity Monitor on — hovering over the preview should NOT
     cause measurable CPU. This confirms the idle-waveform
     no-`TimelineView` path is being taken (plan line 351).

## Cross-component
- All three composite cards share the same card chrome: `surface`
  fill, champagne-tinted 0.5pt border, `Radius.row` (8pt) corners.
- In the `component_map.png` mockup, the composite row (blue) shows
  `TranscriptRow | ModeCard | AudioPlayerThumbnail | ResponseCard`.
  `ResponseCard` is owned by Lane B1 (pill rewrite) and is NOT in
  scope for this runbook.

## Known verification gaps (for reviewer awareness)
- Final placement inside `NotesWindow` / `SettingsWindow` / Notes
  Context Panel surfaces is Phase 3 — nothing in Phase 2 wires these
  composites to a real surface.
- Dark/light wiring relies on `@Environment(\.colorScheme)` — the
  previews only render the dark path by default. Reviewer should flip
  `preferredColorScheme` to `.light` in the preview or open a
  light-mode Xcode canvas to confirm the light palette.
- The worktree this lane was built in
  (`.claude/worktrees/agent-a37791ea`) cannot load its Swift Package
  manifest under Xcode 26.2 / Swift 6.2.3 due to a Gatekeeper/AMFI
  kill of the compiled manifest binary when its containing directory
  is under `.claude/`. Same failure mode reported for Sprint 1 Lane
  A1 in `ManualVisualVerification.md`. Builds succeed from the main
  repo checkout after the branch is merged up. Reviewer MUST run
  `swift test` from the merged `phase-2` branch (expect 254 prior +
  new B2 tests) before closing the Sprint 2 Lane B2 gate.

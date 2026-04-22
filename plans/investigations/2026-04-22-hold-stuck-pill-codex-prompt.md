You are investigating a flaky bug in Ninimma, a Swift macOS menu-bar dictation app at /Users/nitinkum/Projects/nitkrar/personal_scribe. RESEARCH ONLY — do NOT edit source code, do NOT run `swift build` / `swift test` / `sl`.

## Bug symptoms (user, 2026-04-22, verbatim)

"sometimes it actually just transcribes when I leave the hotkey. But sometimes it just gets stuck. I leave the hotkey, the pill for hold experience stays open. Now there is no way to close it. I hit escape and then it opens the default UI, default pill UX for recording. Which is [in] the background. And then I hit escape again and then I see the cancel / the undo card for hey maybe you hit escape by mistake. So when it gets stuck for whatever reason the UX is terrible."

Summary: intermittent stuck-pill after hold-hotkey release. First Esc opens a SECOND pill (default toggle-mode UX for a new recording) in the background. Second Esc shows the Cancel Card / Undo. Recording works most of the time — intermittent.

## Your job

Understand the pill visibility state machine and answer:
1. Who owns the transitions `.hidden ↔ .holdToRecord ↔ .recording`? Enumerate every caller of `viewModel.apply(visibility: ...)` with file:line.
2. What's supposed to drive `.holdToRecord → .hidden` when the hotkey is released? Direct call from `onHoldRelease`, or indirect via session-state routed through the store?
3. If `onHoldRelease` doesn't fire, is there a secondary path (timeout, session-state observation, app-store subscription) that would eventually clear `.holdToRecord`? Why might it also fail?
4. The sticky hold-to-record logic at Sources/PersonalScribeAppKit/Overlay/PillOverlayViewModel.swift:74-81 — confirm exact semantics. Does it suppress transitions to `.hidden`, or only to `.recording`? Can it trap the pill in `.holdToRecord`?
5. If the pill is stuck in `.holdToRecord` and the user presses Esc, what happens? Does Esc route to `apply(visibility: .hidden)`? Can a second pill panel appear over/under it?

## Files to read

- Sources/PersonalScribeAppKit/Overlay/PillOverlayPresenter.swift
- Sources/PersonalScribeAppKit/Overlay/PillOverlayViewModel.swift
- Sources/PersonalScribeAppKit/Overlay/PillOverlayController.swift
- Sources/PersonalScribeAppKit/Overlay/PillVisibilityMode.swift
- Sources/PersonalScribeAppKit/Overlay/PillOverlayView.swift (layout/size dispatch only)
- Sources/PersonalScribeCore/AppStore/PillVisibilityState.swift
- Grep Sources/PersonalScribeCore/AppStore/ for `pillVisibility` / `derivePillVisibility`
- Grep Sources/PersonalScribeAppKit/Composition/ for pill wiring + Esc handling

## Discipline

- Open with grep, not full-file reads. Cap upfront reading at ~100 lines total.
- Cite file:line for EVERY claim.
- If stuck after 15 min, write a `[BLOCKED]` partial to the output file and exit.
- Independent perspective — consider how three independent state holders (hotkey monitor / coordinator / view-model) could drift.

## Output — MANDATORY

Write your entire report to this file (create directory if missing):

  /Users/nitinkum/Projects/nitkrar/personal_scribe/plans/investigations/2026-04-22-hold-stuck-pill-codex.md

Include, ≤500 words total:
- State diagram: who calls `apply(visibility:)` for each transition (direction + source), with file:line.
- What drives `.holdToRecord → .hidden` on release today.
- Whether a session-state change alone can clear the pill.
- Sticky-hold logic: exact gating conditions, can it trap `.holdToRecord`?
- Whether clicking the pill or pressing Esc has any escape hatch to force `.hidden`.
- Whether "second pill appears in the background" has a plausible code path (z-ordering, second panel, sticky guard bypass).
- Ranked hypotheses (most → least likely) for why the hold-pill stays visible when `onHoldRelease` doesn't fire.

Do not print the report to stdout only — the file is the deliverable. Write it even if incomplete.

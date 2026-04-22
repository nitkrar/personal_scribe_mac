You are investigating a flaky bug in Ninimma, a Swift macOS menu-bar dictation app at /Users/nitinkum/Projects/nitkrar/personal_scribe. RESEARCH ONLY — do NOT edit source code, do NOT run `swift build` / `swift test` / `sl`.

## Bug symptoms (user, 2026-04-22, verbatim)

"sometimes it actually just transcribes when I leave the hotkey. But sometimes it just gets stuck. I leave the hotkey, the pill for hold experience stays open. Now there is no way to close it. I hit escape and then it opens the default UI, default pill UX for recording. Which is [in] the background. And then I hit escape again and then I see the cancel / the undo card for hey maybe you hit escape by mistake. So when it gets stuck for whatever reason the UX is terrible."

Summary: intermittent stuck-pill after hold-hotkey release. First Esc opens a SECOND pill (default toggle-mode UX for a new recording) in the background. Second Esc shows the Cancel Card / Undo. Recording works most of the time — intermittent.

## Your job

Trace the Session layer and answer:
1. How are `GlobalHotkeyMonitor.onHoldStart` and `onHoldRelease` wired into `SessionCoordinator`? Name the composition site file:line.
2. What coordinator method does each invoke, and how does that differ from the toggle-path (pill click / menu-bar click / Esc)?
3. Do hold and toggle share a single `.recording` state, or are they distinguishable at the coordinator level?
4. What happens if `coordinator.toggle()` is called while `.recording` is already in flight from a hold?
5. **Critical:** Why does pressing Esc during a stuck hold-session START a new toggle session instead of cancelling the existing one? What does the Esc handler actually do?

## Files to read

- Sources/PersonalScribeSession/SessionCoordinator.swift
- Sources/PersonalScribeSession/Pipeline/Orchestrator/SessionPipelineOrchestrator.swift
- Sources/PersonalScribeSession/AppStore/ (all files)
- Sources/PersonalScribeAppKit/Composition/PersonalScribeAppMain.swift (grep for onHoldStart, onHoldRelease, EscapeKeyMonitor)
- Sources/PersonalScribeAppKit/Composition/AppComposition.swift
- Sources/PersonalScribeAppKit/Hotkeys/EscapeKeyMonitor.swift

## Discipline

- Open with grep, not full-file reads. Cap upfront reading at ~100 lines total.
- Cite file:line for EVERY claim.
- If stuck after 15 min, write a `[BLOCKED]` partial to the output file and exit.
- Independent perspective — don't echo the most obvious explanation. Consider race conditions, state drift, and design gaps separately.

## Output — MANDATORY

Write your entire report to this file (create directory if missing):

  /Users/nitinkum/Projects/nitkrar/personal_scribe/plans/investigations/2026-04-22-hold-stuck-session-codex.md

Include, ≤500 words total:
- Hold-start chain, hold-release chain, toggle chain, Esc handler chain — each with file:line citations.
- Any duplicated/divergent state between hotkey monitor (`isHolding`) and coordinator (`.recording` / `.idle`).
- Ranked hypotheses (most → least likely) for why Esc on a stuck hold-pill spawns a new toggle session.

Do not print the report to stdout only — the file is the deliverable. Write it even if incomplete.

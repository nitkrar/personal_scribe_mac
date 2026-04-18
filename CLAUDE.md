# Seshat — Project Guidelines

Extends `~/Projects/nitkrar/CLAUDE.md` (local-first search, backward-compat APIs, don't break core functionality) and `~/.claude/CLAUDE.md` (global operating principles).

## Testing Discipline
- **Rigid TDD** for logic, protocols, state machines: write a failing test demonstrating the exact broken/missing behavior *first*. Commit test + fix together; reference the test name in the commit message.
- **Flexible TDD** for SwiftUI UI that can't be XCTest'd: test what can be tested (view model, published state, presenter behavior). Add a manual-verification checklist entry to the relevant `Tests/*/Manual*Verification.md` runbook before claiming shipped.
- `swift build` succeeding is not evidence the feature works. Runtime verification is the only proof for UI.

## Architectural Invariants
<!-- TODO: fill in load-bearing invariants from the plan in progress in another session.
  Candidates to confirm: PillOverlayPresenter routing, menu bar lifecycle,
  hotkey monitor setup, paste injection permission flow. -->

## Commit Conventions
- Use `phase-N step N.M:` tags. Never `week-N` or `sprint-N`.
- Test + fix go in the same commit when TDD applies.

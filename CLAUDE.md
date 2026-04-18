# Seshat — Project Guidelines

Extends `~/Projects/nitkrar/CLAUDE.md` (local-first search, backward-compat APIs, don't break core functionality) and `~/.claude/CLAUDE.md` (global operating principles).

## Testing Discipline
- **Rigid TDD** for logic, protocols, state machines: write a failing test demonstrating the exact broken/missing behavior *first*. Commit test + fix together; reference the test name in the commit message.
- **Flexible TDD** for SwiftUI UI that can't be XCTest'd: test what can be tested (view model, published state, presenter behavior). Add a manual-verification checklist entry to the relevant `Tests/*/Manual*Verification.md` runbook before claiming shipped.
- `swift build` succeeding is not evidence the feature works. Runtime verification is the only proof for UI.

## Build / test frequency — Santa-gated machines batch, don't loop

### The check (run once at session start, or at subagent dispatch)
```bash
command -v santactl >/dev/null 2>&1 && echo "SANTA=on" || echo "SANTA=off"
```
If `SANTA=on`, the developer machine gates every unsigned binary behind a per-binary approval prompt. `swift build` / `swift test` produces unsigned `.build/**/SeshatPackageTests.xctest` — one prompt per rebuild. Iterative loops become tens of popups.

### When `SANTA=on` — batching rule (strict)
- Write all tests for a step + the implementation, then run `swift build` / `swift test` ONCE at the end of the step.
- TDD's red-green-refactor still applies conceptually, but you verify by reading code + running tests at the step boundary — not after each intermediate edit.
- Prefer one `swift test` invocation that covers the whole lane's tests over many targeted runs.
- NEVER run `swift build` / `swift test` "to check syntax" — use the Swift language server / visual inspection first; only compile when you're ready to commit.

### When `SANTA=off` — normal cadence
- Iterative `swift build` / `swift test` is fine. Classic red-green-refactor per edit is allowed.
- Still prefer one invocation over many when the work is mechanically obvious and batching doesn't cost signal.

### Subagent contract
Every implementer/reviewer prompt dispatched from this repo must run the check above as its first step, and explicitly state which cadence it will follow in its return message. Do not assume — probe.

## Architectural Invariants
<!-- TODO: fill in load-bearing invariants from the plan in progress in another session.
  Candidates to confirm: PillOverlayPresenter routing, menu bar lifecycle,
  hotkey monitor setup, paste injection permission flow. -->

## Commit Conventions
- Use `phase-N step N.M:` tags. Never `week-N` or `sprint-N`.
- Test + fix go in the same commit when TDD applies.

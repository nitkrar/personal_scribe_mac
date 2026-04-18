# Seshat — Project Guidelines

Extends `~/Projects/nitkrar/CLAUDE.md` (local-first search, backward-compat APIs, don't break core functionality) and `~/.claude/CLAUDE.md` (global operating principles).

## Testing Discipline
- **Rigid TDD** for logic, protocols, state machines: write a failing test demonstrating the exact broken/missing behavior *first*. Commit test + fix together; reference the test name in the commit message.
- **Flexible TDD** for SwiftUI UI that can't be XCTest'd: test what can be tested (view model, published state, presenter behavior). Add a manual-verification checklist entry to the relevant `Tests/*/Manual*Verification.md` runbook before claiming shipped.
- `swift build` succeeding is not evidence the feature works. Runtime verification is the only proof for UI.

## Build / test frequency

Santa on this machine runs in **Lockdown** with **Transitive Allowlisting** enabled (53 compiler rules, confirmed via `santactl status`). Binaries produced by `swiftc` / `clang` are auto-allowed — iterative `swift build` / `swift test` in the main repo is fine, no popups, no batching discipline needed.

### Worktree-path caveat

`Agent`-tool subagents run in isolated worktrees under `.claude/worktrees/<agent-id>/`. Transitive Allowlisting does NOT fully cover worktree paths end-to-end — we've seen both Package.swift manifest AMFI kills (`"Missing or empty JSON output from manifest compilation"`) and Santa popups when xctest binaries execute from a worktree path.

**Subagent contract (worktree agents)**: use `swift build --build-tests` at lane close. This compiles the xctest bundles without executing them, which stays inside Transitive Allowlisting's coverage. **Do NOT run `swift test` from a worktree** — it executes fresh unsigned xctest binaries and will prompt. The main session runs `swift test` from the canonical repo path after cherry-picking the worktree's commits (Transitive Allowlisting covers that path fine).

## Architectural Invariants
<!-- TODO: fill in load-bearing invariants from the plan in progress in another session.
  Candidates to confirm: PillOverlayPresenter routing, menu bar lifecycle,
  hotkey monitor setup, paste injection permission flow. -->

## Commit Conventions
- Use `phase-N step N.M:` tags. Never `week-N` or `sprint-N`.
- Test + fix go in the same commit when TDD applies.

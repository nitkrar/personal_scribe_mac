# Agent Delivery Discipline

**Status**: ratified 2026-05-24.
**Scope**: rules for any delegated agent (hermes via agent-broker, atlas-direct, pool workers) implementing work in this repo. Atlas references this doc from every implementation brief.

This doc complements (does not replace):
- `~/.claude/CLAUDE.md` — global operating principles
- `~/Projects/nitkrar/CLAUDE.md` — nitkrar-wide search + API rules
- `~/Projects/nitkrar/personal_scribe/CLAUDE.md` — project-level TDD + Santa caveats
- `docs/INSTRUMENTATION_PRINCIPLES.md` — log routing + frequency budget

---

## TL;DR

| Stage | Gate |
|---|---|
| Per intermediate commit | `swift build --build-tests` + targeted `swift test --filter <SuiteName>` for the change's tests |
| **Before marking DONE** | **Full `swift test` from canonical repo path** + diff vs. start-of-request failure count |
| Composition / App / lifecycle changes | + `python3 scripts/package.py -i -r` + `pgrep` verification + recent crash report check |

---

## The full-suite gate (before DONE)

### Why

Targeted `--filter` tests are great for iteration speed during TDD, but they hide:
- Tests in other suites the change accidentally broke
- Pre-existing failures we inherit but never see
- Integration-level breakage where unit tests pass but composition wiring is off

A real example from 2026-05-24: `testMakeModelLanguagePreferenceValidatesPersistedHintsOnInit` was red on `b6699b2` baseline and stayed red through 10 commits because nobody ran the full suite. Hermes flagged it during req-0049 verification — that's the right behavior.

### The rule

Before sending a `DONE` message in any agent-broker request:

1. Run `swift test` (no filter) from the canonical repo path.
2. Compare failure count against start-of-request baseline. If you don't have a start-of-request baseline (because no one captured it), compare against your best estimate of the pre-existing failure set.
3. Classify each failure:
   - **New failure caused by my work** → BLOCKER. Do not mark DONE. Fix or surface.
   - **Pre-existing failure my work didn't touch** → Note in DONE message: `Pre-existing failures (not introduced): <test name(s)>`. Atlas tracks separately.
   - **Skipped tests** → Note count; usually benign (`AppEntryPointTests` has a deliberately skipped test).
4. DONE message MUST include the full-suite outcome (test count + failure count + skipped count), not just the targeted filter result.

Example DONE format:
```
DONE | req-NNNN | commit=<sha>
Tests: swift build --build-tests; swift test --filter <SuiteA>; swift test --filter <SuiteB>; swift test (full)
Full suite: 1344 tests, 1 failed (pre-existing testMakeModelLanguagePreferenceValidatesPersistedHintsOnInit, not introduced), 1 skipped
Launch gate: <if applicable> passed via pgrep+crash-report check
```

### When the rule does NOT apply

- **Doc-only commits** — no test impact, full suite gate skipped. Note "(doc-only, no test gate)" in DONE.
- **TempFix / hotfix where atlas explicitly waives the gate** — must be explicit, in writing, in the brief.

### What to do if full suite is too slow

Today (2026-05-24) full suite runs in ~25 seconds. If it ever grows past 5 minutes, surface to atlas — we'll add a test-tag system or split into fast/slow buckets. Until then, no exception based on speed.

---

## The launch-verification gate

### When it applies

Any change that touches:
- `Sources/PersonalScribeAppKit/Composition/PersonalScribeAppMain.swift` or any `App` struct
- `@NSApplicationDelegateAdaptor` / `@SceneStorage` / `@StateObject` declarations
- Any composition-level `static let` lazy initializer
- Lifecycle hooks (`init`, `didFinishLaunching`, `willTerminate`, `applicationShouldTerminate`)
- Reporter / sink composition wiring in `AppComposition.swift`
- Any `ModelLifecycle` protocol implementation
- Any code path that fires during `SwiftUI.App.main()` resolution

### Why

`swift build` + targeted tests catch type errors and unit-level bugs but NOT SwiftUI App.main() resolution failures. Real example from 2026-05-23 (`de40fae` regression): `FastExitApplicationTerminationDelegate` had a labelled init with defaulted parameters; SwiftUI's `@NSApplicationDelegateAdaptor` requires a literal parameterless `init()`. Build green, targeted tests green, EVERY launch crashed with `EXC_BREAKPOINT` in `FallbackDelegateBox.delegate.getter`. Caught only by manual launch.

### The procedure

Before sending DONE:

1. `python3 scripts/package.py -i -r` — builds, installs to `/Applications/Ninimma.app`, launches with `-r`
2. `sleep 5; pgrep -fl Ninimma` — verify process is alive
3. `ls -lt ~/Library/Logs/DiagnosticReports/PersonalScribeAppKit* 2>/dev/null | head -3` — verify no new crash report in the last 5 minutes
4. Optionally inspect `~/Library/Application Support/personal_scribe/logs/diagnostics.log` for `Starting AppStore observation` to confirm normal startup
5. Note the launch verification in DONE: `Launch gate: passed via pgrep+crash-report check`

### What to do if launch verification fails

- BLOCKER, not DONE. Surface the crash trace / lack of pgrep result.
- Do NOT leave broken /Applications/Ninimma.app installed. Either revert your changes or roll back the install.
- Atlas burns a manual rebuild cycle to recover otherwise — user has limited Santa reapproval bandwidth.

---

## The cherry-pick / cherry-fix discipline

When implementing rebuild work or cherry-picking reference commits:

- **Behavior spec, not blind cherry-pick.** Use the reference commit as the source of truth for behavior + test names. Adjust to current baseline shape. If a reference doesn't apply cleanly because of intermediate refactors, write new code that satisfies the test names — don't drag in unrelated infrastructure to make the cherry-pick clean.
- **No 9-commit history for rebuild buckets.** Sub-features land as intermediate commits during work, squashed to ONE final commit before DONE. Mirror the commit message format from prior rebuilds (`63bdc58`, `2288e8b`, `b465aea`).
- **Smoke-test consideration per bucket.** When the bucket touches Parakeet-streaming-adjacent code (idle resource release, VAD lifecycle, model selection), atlas runs a Parakeet smoke test after install. Surface a "needs Parakeet smoke" note in DONE.

---

## File hygiene

Always-untracked-don't-stage:
- `BACKLOG.md` — atlas owns
- `plans/REBUILD_BACKLOG.md` — atlas owns
- `plans/*BRIEF*.md` — atlas owns
- `~/Library/Application Support/personal_scribe/**` — runtime state

Touched-with-feature-commit:
- `docs/INSTRUMENTATION_PRINCIPLES.md` — touched when adding/removing observability
- `docs/AGENT_DELIVERY_DISCIPLINE.md` — this file; touched when rules change
- `Tests/ManualVerifications/*.md` — touched when adding manual verification steps

---

## Coordination with concurrent requests

When multiple agent-broker requests are in flight against the same repo:

- **Serialize on overlapping files.** If two requests both touch `SessionPipelineOrchestrator.swift`, the second waits for the first to land + rebases on top. Pick serialization based on which ACK comes first.
- **Surface conflicts as BLOCKER.** Don't merge-resolve creative conflicts silently. Surface in side room, wait for atlas judgment.
- **Use `git log --oneline -3` at start.** Confirm you know which HEAD you're rebasing onto. Trunk moves fast during multi-agent work.

---

## DONE message canonical format

```
DONE | req-NNNN | commit=<final-squashed-sha>
Subject: <commit subject>
Tests:
  - swift build --build-tests
  - swift test --filter <SuiteA>
  - swift test --filter <SuiteB>
  - swift test (full)
Full suite: <total> tests, <fail> failed (<pre-existing notes>), <skipped> skipped
Launch gate: <passed via pgrep+crash-check | not applicable (no composition wiring)>
Manual verification: <added MV-XXX-N | not applicable>
Notes: <serialization notes, smoke-test asks, BLOCKER conversions, etc.>
```

Atlas closes the request after verifying. If the DONE message is missing fields, atlas requests them rather than closing.

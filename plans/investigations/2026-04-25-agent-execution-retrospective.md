# Agent-driven execution retrospective — Ninimma

**Date:** 2026-04-25
**Scope:** 7-day window, 2026-04-18 → 2026-04-25
**Mode:** read-only investigation; no code modified

This document captures two related analyses so we can resume the conversation later:

1. **Five gaps** — comparison of Matt Pocock's `mattpocock/skills` repo against this project's memory + feedback patterns.
2. **Agent-execution retrospective** — what 7 days of git log + investigation files tell us about working with agents on this codebase.

A third section ("transcript-level evidence") is appended after scanning Claude Code session JSONLs for user-pushback patterns.

---

## Part 1 — The five gaps (Matt Pocock skills vs. this project)

### Crux

The 4-5 day cleanup cycle that follows each 1-2 day initial implementation has five upstream causes. Project memory contains *defenses* (rules I follow when I notice problems). Matt's `mattpocock/skills` repo contains *interventions* (skills that prevent the problems from happening). The gap is structural, not knowledge-based.

Matt's repo is at `https://github.com/mattpocock/skills` (18.2k stars as of 2026-04-25).

### Gap 1 — Terminology drifts between code, plans, and conversation

The project has 30+ domain terms (pill, wedge, mode, holdToRecord, ResponseCard, central layers, AppBrand, snapshot, transcript, paste pipeline, …) scattered across `Sources/`, `plans/`, and `Tests/Manual*Verification.md`. Agents drift on every fresh worktree.

- **Matt has:** `ubiquitous-language` skill — produces one `UBIQUITOUS_LANGUAGE.md` with definitions, aliases-to-avoid, and a sample dev↔domain-expert dialogue.
- **You have:** nothing equivalent. Memory references all the terms but no canonical glossary.

### Gap 2 — AI builds something directionally right but wrong in detail

Manifests at runtime: `#075` wedge symptom, `#017` modifier-only binding gap. You catch it, but only after it ships.

- **Matt has:** `grill-me` skill — four lines that flip the AI into interrogator mode, walking every branch of the design tree before any plan is written. Quote: *"Interview me relentlessly about every aspect of this plan until we reach a shared understanding. Walk down each branch of the design tree, resolving dependencies between decisions one-by-one. For each question, provide your recommended answer."*
- **You have:** `feedback_user_intent_over_literal_read.md` — but it's reactive ("if you find a gap, restate it"). Matt's is preventive.

### Gap 3 — Refactors sprawl; can't bisect when something breaks

One big refactor lands; regressions appear; takes days to untangle. Central-layers refactor and `#072` snapshot-unification fit this shape.

- **Matt has:** `request-refactor-plan` skill — forces (a) "what NOT to change" section, (b) test-coverage audit before starting, (c) Fowler-style tiny commits where the codebase always works, (d) decision document, (e) explicit out-of-scope section.
- **You have:** `architecture_heuristics.md` with three good patterns (race-fix layer, contract questions, sticky guards), but no scope-hammering or tiny-commits gate.

### Gap 4 — Tests written alongside code lock in the bug

Same agent writes the buggy code and the tests; tests then block the fix because they "specify" the bug. Hit on `#075`. Surfaced concretely on Apr 23-24 with **1,360 lines of dead tests pruned in 41 minutes** (commits `78c3ba3` / `a372e34` / `99cee6a`).

- **You have, richer than Matt:** `test_rigor_no_fluff.md` (3 fluff modes), `test_review_heuristics.md` (dead-test taxonomy), `feedback_tests_as_spec.md` (bug-fossil framing).
- **Matt has, that you don't:** the upstream rule — *don't write all tests first, then all code.* Bulk-written tests describe imagined behavior, not real behavior. Vertical slices only: one test → one impl → repeat. Quote from his TDD skill: *"Tests written in bulk test imagined behavior, not actual behavior. You end up testing the shape of things rather than user-facing behavior."*

You're cleaning up after the fact. Matt prevents the fluff from landing.

### Gap 5 — AI is verbose, over-explores, generates 3× code for 1× problem

You've been treating this as a behavioral problem ("be terse").

- **Matt's claim:** verbosity drops when the codebase has *deep modules* (lots of behavior, simple interface) instead of *shallow modules* (many tiny files). Agent doesn't have to traverse 20 files to reason about one change.
- **Your central-layers refactor is already moving this direction** — you just don't have the vocabulary for *why* it reduces verbosity. The framing comes from Ousterhout, *A Philosophy of Software Design*.

### What you have that Matt doesn't

These complement Matt's skills; they don't compete:

- Dead-test taxonomy (SPM boilerplate, scaffolding, synthesized-code, post-refactor duplicates)
- Codex failure modes (silent completions, worktree evaporation, shutdown delays)
- Pre-dogfood phasing (on-disk state is disposable)
- Platform quirks (Santa allowlisting, `@StateObject` XCTest trap, FluidAudio bundling)
- Incident-tied architecture heuristics (`#071` race, `#075` wedge)

### Recommended adoption order

1. **`ubiquitous-language` first.** ~30 min to draft. Highest leverage. Cuts terminology drift, which feeds half the other problems.
2. **`grill-me` second.** Use on every plan kickoff. Replaces the "I propose → you push back → I revise" loop with one structured interview.
3. **`request-refactor-plan` when the next big refactor surfaces** (post-central-layers). The "what NOT to change" section is the load-bearing piece.

Skip `to-prd` and `to-issues` — your `plans/` workflow is equivalent. Steal one line from Matt's TDD skill into `test_rigor_no_fluff.md`: *"horizontal slicing — writing all tests then all code — is the root cause of fluff."*

---

## Part 2 — Agent-execution retrospective (7 days)

### Methodology

Read:
- `git log --since='2026-04-18'` with file-change stats — ~120 commits.
- `BACKLOG.md` (head section + multiple ticket bodies).
- 6 of the larger investigation files in `plans/investigations/`:
  - `2026-04-24-issue-075-hold-too-short-wedge-claude.md` (17.8KB)
  - `2026-04-24-mute-system-audio-codex.md` (3.5KB)
  - `2026-04-24-mute-system-audio-simpler-codex-2.md` (2.8KB)
  - `2026-04-24-snapshot-unification-claude.md` (21KB, partial)
  - `2026-04-23-pill-flicker-root-cause-codex.md` (8.2KB)
  - `2026-04-22-042-ax-probe-claude-2.md` (10.4KB)
- Memory files: 9 feedback/project memories.

### Recurring failure patterns

#### P1 — First-pass agent output is over-engineered, even on the second try

`#076` mute-system-audio: five investigation files in 30 minutes.

| Time  | File                                      | Proposed |
|-------|-------------------------------------------|----------|
| 19:42 | `mute-system-audio-prompt.md` (9.8KB)     | Initial brief |
| 19:50 | `mute-system-audio-codex.md` (3.5KB)      | CoreAudio HAL, per-device latching, route-change tracking, full system-output handling. Verdict: ship-with-changes, 4 must-fixes. |
| 20:01 | `mute-system-audio-simpler-prompt.md`     | You pushed for simpler |
| 20:07 | `mute-system-audio-simpler-codex.md`      | Still proposed `SystemOutputMuter` in PersonalScribeAudio with HAL calls |
| 20:14 | `mute-system-audio-simpler-codex-2.md`    | *"I would not make AppleScript the default implementation. My preferred v1 is still small, but native"* |

Shipped (`89ab9de`): AppleScript via `NSAppleScript`, ~20 lines. Memory `project_macos_system_audio_mute.md` confirms HAL was over-engineering.

**You went two levels simpler than codex's "simpler" version.** Even when explicitly prompted to simplify, the agent's anchor remained complexity.

#### P2 — High-stakes designs need 3 independent reviews

`#042` (AX probe) had **four investigation files**: two Claude agents (`claude.md`, `claude-2.md`), a Codex prompt + result, and AX SDK dump scripts. BACKLOG entry:

> *"independent deep-reviews by 2 Claude agents + 1 Codex agent... converged on the root cause. Of the 3 options, Option 2 was rejected unanimously..."*

Cost: ~3 hours of investigation before the 30-minute fix could be locked. You don't trust any single agent's recommendation, and the data shows you're correct not to.

#### P3 — Bug fossils — agents wrote tests that codified the bugs as "by design"

Apr 23-24 dead-test cleanup before `#046` Stage A:

| Commit    | Time  | Deletions |
|-----------|-------|-----------|
| `78c3ba3` | 00:11 | 885 lines (audio/transcription/session) |
| `a372e34` | 00:45 | 189 lines (PersonalScribeAppKitTests) |
| `99cee6a` | 00:52 | 286 lines (PersonalScribeCoreTests) |

**1,360 lines pruned in 41 minutes.** `d3696ed` Apr 23 01:50 also drops "tautological size tests" caught at runtime.

`feedback_tests_as_spec.md` cites the same pattern on `#075`: a `RecordingStatusCardDriverTests.testDriverErrorOverridesVadStates` test pinned the buggy duplicate-surface behavior; deleted in the fix commit.

#### P4 — Agents build parallel systems where they should reuse

| Refactor commit | Stats | What collapsed |
|-----------------|-------|----------------|
| `8d06afc` `#072` | 28 files / +2868 / −829 | Two parallel clipboard-snapshot systems → one keyed-token service |
| `00d836a` pill flicker | 22 files / +323 / −365 | Two unsynchronized pipeline-state delivery paths → single snapshot stream |
| `e55d8f7` `#071.4` | 5 files / +25 / −58 | Sticky `isShowingHoldToRecord` guard removed once underlying race was fixed at the right layer |

`snapshot-unification-claude.md` notes: *"Anti-pattern already logged: BACKLOG `#074` calls this exact split out under the state-ownership audit."* The pattern was a known category before this instance landed.

#### P5 — The pill is a structural pain magnet

In 7 days the pill alone produced:
- 4 separate investigation files (dimensions 15.6KB, shape-stages × 3, flicker × 3, hit-testing in memory)
- `bug-071` race fix (5 micro-commits)
- `#075` wedge + ResponseCard overlap (7 micro-commits)
- Pill height/width enums (`d7f8f49`) added specifically to prevent dimension drift
- Tautological size-test prune (`d3696ed`)

It straddles AppKit panel + SwiftUI content + ClickThroughHostingView hit-testing + AppStore state + ResponseCardDriver state + multiple visual states. Memory `project_pill_hit_testing.md` already notes the architectural seam. **The pill is the most expensive component to change** — a shallow-module conglomerate, in Matt's framing.

#### P6 — Micro-commit cadence works when you control the slicing

Pattern that works: you decompose, agent executes one step, you verify, next step. `phase-N step N.M:` convention is an empirical adaptation to agent failure modes.

Examples: `bug-071` 1.1→1.5 (5 commits, regression test landed in 1.2 pinning the eager-publish invariant); `#075` 1.1→1.7 (7 commits); `#024` 1.1→1.7 (model service redesign).

Pattern that fails: one agent, one big task, one big commit.

### Three concrete "3× time" instances

#### 3X-1: `#016` RAM-aware default model — speculative-abstraction round-trip (Apr 22)

- `930330e` 1.1: `DefaultModelSelectionPolicy` (+196 lines)
- `da96525` 1.2: wire it (+108 lines)
- `db791b0` 1.3: *"simplify policy + tests — drop premature abstraction"* (+22 / −171)

Net: 1 useful commit took 3 commits to land. `simplicity_discipline.md` captures your reaction: *"I thought this would be a simple test file of mocking memory and checking if it picked well"* after the agent wrote 8 tests for a 3-line policy.

#### 3X-2: `bug-007` model labels — wrong-architecture pivot (Apr 22)

- `457ca81` 1.1: `RelativeRating` enum + `speedRating`/`accuracyRating` fields on the descriptor (+140 lines)
- `0df02cd` 1.2: **pivot** — *"Enum-based approach put user-facing labels in code rather than the registry — user called it out."* Removed `RelativeRating`, added `architecture` + `performance: ModelPerformance` (+127 / −72)
- `33d25a1` 1.3: presenter that computes labels at render time (+400 lines)
- `b3f3278` 1.4: UI integration (+233 / −36)

You shipped on the second design. The first was an architectural error the agent didn't surface; you caught it in review.

#### 3X-3: `#075` wedge — investigation cost > implementation cost (Apr 24)

- 19:16 → 19:50: 4 investigation files (~35KB total) across two agents
- 20:24 → 21:05: 7 implementation commits (steps 1.1 through 1.7)

Each step 1.X is tens of lines. Investigation took as long as the fix because two coupled symptoms (pill + card overlap, hold path wedge) had to be traced to a shared root cause (`.error(.recordingTooShort)` had no single clearing moment) before fix options could be evaluated.

The 17.8KB `claude.md` investigation maps the entire state machine, four fix options with trade-offs, and recommends Option A + Option D'. Quality work — but work you had to commission because the agent that wrote the original code didn't see the coupling.

### Three takeaways

1. **Agent recommendations on architecture and "what's enough" are systematically off by 2-3× complexity.** Even codex-on-second-pass under-corrects. Your role is calibration, not just review. Investigation-file evidence shows this is repeatable.

2. **The investigation-then-implement split is doing real work for you.** When you spend 30-60 minutes on investigation files (sometimes with parallel agents), the implementation commits are clean. When you go directly from problem to commit, you get over-engineered output (P1) or parallel systems (P4). The investigation phase is where your judgment lands; the commit phase is mechanical.

3. **Most of the 4-5 day "fixing" time is structural debt the agent silently created on day 1-2.** Specifically: parallel systems (`#072`, pill flicker), bug-fossil tests (1,360 lines), wrong-layer fixes (`bug-071` coordinator-vs-pipeline classic), speculative abstractions (`#016`), opaque-architecture choices (`bug-007` enum labels). None were unit-test bugs — they were design errors that surfaced as bugs when the code met reality.

`grill-me` and `ubiquitous-language` from Matt's repo target #1 and #4 specifically. Bug fossils are addressed by your existing `feedback_tests_as_spec.md` and `test_rigor_no_fluff.md`, and the data shows the prunes are happening earlier and more aggressively than they used to.

---

## Part 3 — Transcript-level evidence (extent of the problem)

### Methodology

Scanned 25 Claude Code session JSONLs in `~/.claude/projects/-Users-nitinkum-Projects-nitkrar-personal-scribe/` from 2026-04-18 → 2026-04-25 with `/tmp/scan_transcripts.py`. The script:

- Filters to `type == "user"` records.
- Strips system-reminder / hook / command auto-injected content.
- Excludes `tool_result` blocks (those are tool output, not user-typed).
- Counts hits per pushback regex pattern in real user-typed text.
- Per-session: counts user turns and turns matching ANY pushback pattern.

### Aggregate pattern counts (top 15)

Across **25 sessions, 919 real user turns, 191 pushback hits** (turns can hit multiple patterns):

| Pattern             | Hits |
|---------------------|------|
| `don't`             | 68   |
| `simpler`           | 22   |
| `useless`           | 22   |
| `again,`            | 13   |
| `stop X`            | 12   |
| `no need (to/for)`  | 7    |
| `fluff`             | 6    |
| `tautology`         | 6    |
| `you keep`          | 5    |
| `over-engineer`     | 4    |
| `why are we`        | 4    |
| `why do we`         | 4    |
| `wait`              | 3    |
| `you didn't`        | 2    |
| `premature`         | 2    |

### Per-session pushback rate

Sessions with ≥30 user turns, ranked by % of turns containing a pushback signal:

| Session    | Date         | Turns | Pushback turns | Rate  | Likely topic |
|------------|--------------|-------|----------------|-------|--------------|
| `35834045` | 2026-04-23/24 | 78    | 24             | **30.8%** | Test cleanup (1,360 dead lines pruned) |
| `d3537d8b` | 2026-04-24   | 43    | 12             | **27.9%** | `#072` snapshot unification — *"why do we have 2 snapshot systems again"* |
| `38db1bee` | 2026-04-18   | 48    | 13             | **27.1%** | (early week, large session) |
| `c9168194` | 2026-04-24/25 | 54    | 14             | **25.9%** | `#024` model row redesign — *"Why do you keep inventing complex solutions"* |
| `5a59eb5e` | 2026-04-24   | 34    | 8              | **23.5%** | `#076` mute system audio — *"sounds over engineering again"* |
| `0920678e` | 2026-04-18   | 47    | 9              | 19.1% | (early week) |
| `57243e60` | 2026-04-21   | 44    | 6              | 13.6% | BACKLOG schema design |
| `f5605899` | 2026-04-22/23 | 80    | 10             | 12.5% | Architecture / pre-dogfood reframes |
| `3745ca28` | 2026-04-19   | 82    | 9              | 11.0% | (early week) |
| `9846c48e` | 2026-04-24   | 58    | 6              | 10.3% | (Stage A VAD) |

**Reading:** The high-pushback sessions cluster around feature work where the agent was actively building the wrong thing or persisting in a wrong direction. The 35834045 outlier is partly inflated because that session was orchestrating parallel codex agents reviewing tests, and codex's own outputs contain the strings "USELESS" / "tautology" — but even with that noise, the user-driven corrections in 35834045 are heavy.

### Highest-signal verbatim quotes

These come directly from the scan output (each shown with session id + user-turn index). They carry texture that isn't in memory:

- **Drift mid-feature:** *"wait what notes feature are we building. The requirement is user can dictate the note and it get's stored which I can search later. maybe need bits of editing. i think you went ahead and overengineered it."* — `f5605899 turn 35`
- **Persistent symptom-fixing:** *"Why do you keep focussing on symptom not root cause and keep overindexing on it."* — `c9168194 turn 41`
- **Same mistake, multiple sessions:** *"we've gone through rounds of this, why do we have 2 snapshot systems again for same thing, I've repeatedly asked for centrally managed [source of truth] for output."* — `d3537d8b turn 15` (this is the moment that triggered `#072`)
- **Pre-dogfood reframe ignored:** *"I am not sure why are we complicating this. What part of nuke JSONL and start over do you not understand. Every agent keeps talking like this is live app with many users"* — `5694de6d turn 8`
- **Test fluff caught at runtime:** *"screw the test file you make changes and write same to test it's useless, might as well delete it at this point."* — `f5605899 turn 61` (origin of the `simplicity_discipline.md` §4 circular-assertion rule)
- **Repeated ask about same root issue:** *"there is no need to overcomplicate this. I don't know why we keep going down this route every time."* — `f5605899 turn 32`
- **Architecture pivot caught in real-time:** *"why are we implementing labels in code? don't we have a model registry which should have all the info"* — `c765cbed turn 9` (this is the `bug-007` pivot moment, prior to the `0df02cd` 1.2 commit)
- **Memory over-eagerness:** *"you keep jumping to conclusion to add stuff to memory. I can try allowlisting locally"* — `d3537d8b turn 31`
- **Missed enumeration:** *"it was in this original table but you missed it in merge step for width"* — `f5605899 turn 55` (the `.holdToRecord` silent-omission incident captured in `proposal_discipline.md`)
- **Investigation-came-up-empty:** *"and you didn't find it after 3 attempts?"* — `f5605899 turn 70`
- **Stuck:** *"wait what are you stuck on right now?"* — `6761dc3b turn 23`
- **Initial scope was simple:** *"I thought this would be a simple test file of mocking memory and checking if it picked well. i don't understand are we adding so many tests for."* — `c765cbed turn 24` (this is the `#016` over-test moment)
- **Mute-audio over-engineering:** *"seems very complicated solution again. Write a prompt for codex to design a simple minimal solution for this and you do another attempt as well. how complicated is muting audio on a laptop"* — `5a59eb5e turn 15`

### What the transcript data adds beyond git log

1. **You repeat yourself a lot.** "again," appears 13 times. "you keep" 5 times. "I don't know why we keep going down this route every time" once. The agent forgets between turns — you re-establish constraints repeatedly within a single session, never mind across sessions.

2. **Pushback rate scales with session duration AND topic complexity.** Short sessions (≤10 turns, focused asks) show 0-12% pushback. Mid-sized feature sessions (40-80 turns) cluster at 10-28%. The `35834045` test-cleanup outlier hits 31% partly due to scan noise, but even discounted is still high.

3. **Three categories of pushback dominate, in order of frequency:**
   - **Scope/complexity correction** — "simpler", "no need", "we don't need", "over-engineer", "premature" (~36 hits combined). The agent's default is too much.
   - **Negation/redirect** — "don't", "stop", "wait", "no" (~85 hits). The agent did a thing the user didn't ask for.
   - **Fluff calls** — "useless", "fluff", "tautology", "circular" (~35 hits combined). Tests primarily, sometimes prose.

4. **Several pushbacks reference *prior* corrections.** "Again," "you keep," "we've gone through rounds of this," "every time," "every agent keeps talking like." This is the data-equivalent of memory being load-bearing — the user has internalized rules, but each new session is fresh ground for the agent.

### Implications

- The 191 pushback hits in 919 user turns ≈ **1 in 5 user messages** is a course-correction. That's the literal cost of agent-driven execution as it stands.
- Most of the *correctable-in-advance* category (scope/complexity, ~36 hits) maps to Gap 2 (`grill-me` would catch a fraction of this before the wrong thing gets built) and Gap 5 (deep-modules framing reduces the surface where the agent can over-explore).
- The fluff/test category (~35 hits) is already targeted by your existing memory and the prune cadence is improving, but the upstream rule from Matt's TDD skill (*"don't write tests in bulk, vertical slices only"*) would prevent the fluff from landing in the first place.
- The repetition signals ("again," "you keep") suggest a **per-session-context-priming gap**: memory loads at session start but doesn't always inflect agent behavior on the second or third pivot inside the same session. Adoption candidate: a project skill that, at session start, explicitly enumerates the top-5 active constraints (pre-dogfood, no migrations, simplicity-first, small commits, etc.) so the agent re-anchors on each fresh spawn instead of relying on memory alone.

---

## Part 4 — Operating-instruction stack inventory

### Methodology

Located every file or surface that imposes constraints/instructions on the agent during a personal_scribe session. Read each in full where length permitted; quoted verbatim where load-bearing. Audited drift between authoritative copies and their derivatives.

Findings come in seven layers, in load order from most-foundational to most-ephemeral.

---

### Layer 1 — Hardcoded Claude Code system prompt (built into the binary)

This is what's prepended to every conversation by Claude Code itself. Visible to me as the prompt prefix; not user-editable. Highlights:

- **Tool discipline:** "Prefer dedicated tools over Bash when one fits (Read, Edit, Write)." "If you intend to call multiple tools and there are no dependencies between them, make all of the independent tool calls in parallel."
- **Tone and style:** "Your responses should be short and concise." "End-of-turn summary: one or two sentences. What changed and what's next. Nothing else."
- **Code style:** "Default to writing no comments." "Don't add features, refactor, or introduce abstractions beyond what the task requires." "Don't add error handling, fallbacks, or validation for scenarios that can't happen."
- **Verification before claiming done:** "For UI or frontend changes, start the dev server and use the feature in a browser before reporting the task as complete… if you can't test the UI, say so explicitly rather than claiming success."
- **Risky-action gating:** "Carefully consider the reversibility and blast radius of actions… For actions that are hard to reverse… check with the user before proceeding."

This layer is **always present, always identical**. Project CLAUDE.md cannot remove or override it; it can only stack on top.

---

### Layer 2 — User CLAUDE.md hierarchy (3 files, loaded in order)

**File A — `~/.claude/CLAUDE.md` (4,141 bytes)**

Title: "Global Operating Principles. Applies to every project unless project CLAUDE.md overrides."

Eight numbered principles, all behavioral discipline:

| # | Principle | Load-bearing rule |
|---|-----------|-------------------|
| 1 | Verification before claiming done | "build succeeds ≠ feature works. Never claim shipped without runtime verification. Default to understating: 'committed + tests pass, please verify' over 'shipped'." |
| 2 | Hold decisions; classify before pivoting | "When the user questions a prior decision, DO NOT default to proposing the alternative. Classify: Fact change → pivot. Re-check → defend with original rationale. Preference change → pivot. Predictable consequences are NOT new information." |
| 3 | Adopt reference artifacts verbatim | "Read every file, full content. Copy tables, assignments, contracts by value. **Silent divergence is the cardinal sin.**" |
| 4 | Semantic audits, not keyword grep | "Map by semantic role, not by name. Different name + same concept = duplicate." |
| 5 | Small-chunks review; no silent divergence | "Never dump a 100+ line diff and expect review." "For >3 changes to a plan or summary doc: ask 'one-by-one or batch?' Default one-by-one." |
| 6 | Phase multi-task requests; dispatch subagents | "When a user message contains ≥2 distinct verbs ('revisit X, fix Y, remove Z'): Do NOT execute all in one pass. Propose a phased breakdown… Wait for approval." |
| 7 | Phase by product milestones, not dates | "Phase = usable product milestone. No dates, week labels, or sprints-by-calendar." "Commit tags: `phase-N step N.M:` — never `week-N` or `sprint-N`." |
| 8 | Classify rule scope before checking in | Architectural patterns → project CLAUDE.md. Machine quirks → memory. Behavioral discipline → global. Factual references → memory. |

**File B — `~/Projects/nitkrar/CLAUDE.md` (~700 bytes)**

Two short sections:

- **Search Preferences:** "ALWAYS prefer local file searches (Glob, Grep, Read) first before using remote or meta codesearch agents. This is NOT a Meta monorepo project — all code is local. Only use remote/web searches for external documentation or APIs."
- **Core Rules:** Never break core functionality (auth, encryption, vault key unlock); APIs always backward-compatible; ASK before breaking changes.

The "auth, encryption, vault key unlock" mention is for the `citadel` sibling project — irrelevant to Ninimma but loaded anyway.

**File C — `~/Projects/nitkrar/personal_scribe/CLAUDE.md` (~3,400 bytes)**

Title: "Ninimma — Project Guidelines. Extends `~/Projects/nitkrar/CLAUDE.md` and `~/.claude/CLAUDE.md`."

Sections:

- **Testing Discipline:** Rigid TDD for logic/protocols/state machines, flexible TDD for SwiftUI UI with manual-verification runbook entries.
- **Build / test frequency:** Santa runs in Lockdown + Transitive Allowlisting; iterative `swift build`/`swift test` is fine on canonical path. Worktree caveat: `swift build --build-tests` only — never `swift test` from a worktree (TA doesn't fully cover those paths).
- **Architectural Invariants:** **Empty section** — has a `<!-- TODO: fill in load-bearing invariants -->` placeholder. Has been a TODO since at least early Apr (no fills observed in `git log -- CLAUDE.md`).
- **Design references:** SeshatTheme is informational, not a drop-in. Theme types live in `Sources/PersonalScribeAppKit/Theme/`, NOT in `PersonalScribeCore`.
- **Commit Conventions:** `phase-N step N.M:` tags. Test + fix in the same commit when TDD applies.

**Total operating-rule surface across all three: ~10,000 bytes.** All three load on every session.

---

### Layer 3 — Auto-loaded memory index

**`~/.claude/projects/-Users-nitinkum-Projects-nitkrar-personal-scribe/memory/MEMORY.md` (51 lines).**

Two-tier system:

1. The **index** (`MEMORY.md`) auto-loads at session start. 51 lines. Linked entries are NOT loaded — only the one-line hooks.
2. **33+ memory files** in the same directory. Loaded *on-demand* when "the topic surfaces" (per global CLAUDE.md §8). The mechanism for "surfaces" is unclear from documentation; in practice it means the agent reads them lazily.

Sections in the index:
- Project state — 21 hooks (decisions, execution state, layers refactor, BACKLOG location, codex setup, TCC quirk, Santa, FluidAudio model trap, …).
- Feedback — consolidated clusters — 16 hooks (simplicity, proposal discipline, verify before asserting, decision discipline, response shape, codex workflow, codex failure modes, worktree pitfalls, git workflow, BACKLOG conventions, project phasing, testing discipline, test cadence, test-review heuristics, test rigor — no fluff, architecture heuristics).
- Feedback — standalone — 7 hooks (Stage 2 implementor discipline, rebuild friction, memory discipline, scope completion, bundle/pref alignment, user-intent over literal read, tests-as-spec fossils).

**Behavioral implication:** the index gives me a list of headlines. To act on the actual rule, I have to recognize the topic and read the file. Both steps can fail. If I don't recognize the topic, I never load the rule. **This is structurally invisible to the user.**

---

### Layer 4 — Plugin / skill system (high-impact, low-visibility)

**`~/.claude/settings.json` enables 13 plugins:**

```
10x-engineer@claude-templates             ← injects "using-superpowers" skill
browser@claude-templates
cdm-dw@claude-templates
chat-notifications@claude-templates
codex-cc@claude-templates                 ← codex-rescue agent
codex-plugin-cc@agent-market              ← duplicate codex-rescue
data@claude-templates
datamate@claude-templates
debrief@claude-templates
gdrive-mount@claude-templates
hyperclaude@claude-templates
meta-statusline-pro@claude-templates
para-workspace@claude-templates           ← deprecated; migration notice fires
source-control-at-meta@claude-templates   ← disabled
tmux-statusline@claude-templates
tracing@Meta                              ← disabled
```

Plus `effortLevel: "high"`, `model: "opus[1m]"`, `skipDangerousModePermissionPrompt: true`.

**Two plugin layers contribute behavioral instructions:**

- **`10x-engineer` plugin's `using-superpowers` skill** is the single most aggressive instruction in the stack. Verbatim from this session's SessionStart hook:
  > *"If you think there is even a 1% chance a skill might apply to what you are doing, you ABSOLUTELY MUST invoke the skill. IF A SKILL APPLIES TO YOUR TASK, YOU DO NOT HAVE A CHOICE. YOU MUST USE IT."*
  >
  > "Invoke relevant or requested skills BEFORE any response or action. Even a 1% chance a skill might apply means that you should invoke the skill to check."

  This overrides almost every other instruction. It demands a Skill-tool invocation *before* any clarifying question. In practice this fires in nearly every turn of every session.

- **Available skills (Meta-internal, exposed via SessionStart):** `analytics-agent-handoff`, `calendar`, `deep-research`, `gchat`, `google-docs`, `google-drive`, `google-slides-presentation`. None apply to Ninimma. They live at `/opt/facebook/claude-templates-cli/components/skills/`, surfaced via the symlink at `~/.llms/skills/claude-templates → ~/.claude/skills`.

- **Other plugin skills** (loaded indirectly via `~/.claude/plugins/cache/`):
  - `claude-templates/source-control-at-meta/1.12.0/skills/{creating-or-updating-diffs, fixing-diffs, reviewing-diffs, using-source-control, diff-splitter}` — disabled here.
  - `claude-templates/meta-cli-core/1.1.0/skills/meta-cli`
  - `claude-templates/para-workspace-core/1.3.0/skills/tasks`
  - `agent-market/codex-plugin-cc/1.0.4/skills/{codex-cli-runtime, codex-result-handling, gpt-5-4-prompting}`

- **Plugin agents** are spawnable via the Agent tool: `Explore`, `Plan`, `meta_codesearch:code_search`, `meta_knowledge:knowledge_search`, `codex-cc:codex-rescue`, `codex-plugin-cc:codex-rescue`, several `debrief:*`, `10x-engineer:code-reviewer`, `claude-code-guide`, etc. Each agent ships its own description + permitted-tools list, which is effectively a per-agent system prompt.

**This entire layer is invisible to the user in any single CLAUDE.md file.** The behavioral instructions live across plugin packages, surface dynamically, and override CLAUDE.md when they fire.

---

### Layer 5 — SessionStart hooks (per-session injections)

Visible at the top of this conversation as `<system-reminder>` blocks. From this session:

1. *"SessionStart:startup hook success: This is a Git repository, run `git --help` instead."* — uninformative noise; appears benign.
2. *"ALWAYS use the meta_codesearch:code_search agent instead of the Explore agent when exploring the codebase."*
3. *"ALWAYS use the search_files MCP tool as a replacement for the Grep and Glob tools and for recursive find/grep/rg Bash commands."*
4. *"For web searches, use mcp__plugin_meta_mux__three_pai_external_web_search…"*
5. *"NEVER use external or public hosting sites including but not limited to catbox.moe, imgur, pastebin, file.io, 0x0.st, or any similar service. ONLY use PixelCloud, Google Suite, or *.facebook.com / *.fbcdn.net / *.internalfb.com domains."*
6. *"MIGRATION NOTICE: You have deprecated para-workspace sub-plugins installed: para-workspace-core, para-workspace-gdrive, para-workspace-integrations, para-workspace-meetings, para-workspace-reporting. These were consolidated into para-workspace in v4.0.0."*
7. The full `using-superpowers` skill content (Layer 4 already covered).

**Direct conflicts with Layer 2:**

- Layer 2 File B: *"ALWAYS prefer local file searches (Glob, Grep, Read) first."* This is **NOT a Meta monorepo project — all code is local.**
- Layer 5 Hook 2: *"ALWAYS use the meta_codesearch:code_search agent instead of the Explore agent when exploring the codebase."*
- Layer 5 Hook 3: *"ALWAYS use the search_files MCP tool as a replacement for the Grep and Glob tools…"*

The hooks are written for Meta-internal projects and fire even when the project is explicitly **not** Meta. The hooks override CLAUDE.md by virtue of being more recent in the prompt and being phrased as ALWAYS-mandates.

**Effect on the agent**: hesitation about which tool to use, occasional improper tool selection, and (when memory loads `simplicity_discipline.md`'s "ALWAYS prefer local") momentary contradiction.

---

### Layer 6 — Per-turn injections

Patterns I can see in this session's prompt:

- `<system-reminder>` blocks attached to user messages.
- `<command-name>` / `<command-message>` blocks for slash commands.
- `<user-prompt-submit-hook>` blocks (treated as user input).
- "MANDATORY SKILL EVALUATION" block fires every turn, instructing me to:
  > *"You MUST evaluate EVERY skill listed below before doing anything else. … For each skill, decide YES/NO with a one-sentence reason. … For EVERY skill marked YES: Use Read tool to load it NOW. … Only after Step 2 is complete may you answer the user."*
- TaskTool reminders ("The task tools haven't been used recently…") fire intermittently.
- Deferred-tool schemas surface via `<functions>` blocks when needed.

These are unaffected by CLAUDE.md and are the most aggressive constraint surface.

---

### Layer 7 — Worktree CLAUDE.md drift (the silent failure mode)

This is the finding I think matters most.

- Project CLAUDE.md was last updated by `8b829a3` (Apr 21 13:20) — added the *"Design references"* section (SeshatTheme is informational; theme types live in `AppKit/Theme/`).
- 20 agent worktrees exist under `.claude/worktrees/agent-*/`. Each has its own copy of CLAUDE.md (snapshotted at worktree-creation time, never re-synced).
- **11 of 20 worktree CLAUDE.md files differ from project root.** All differ in the same way: missing the post-`8b829a3` Design references section.

```
DRIFTED:
  agent-a0fb3b02   mtime=2026-04-21 23:45
  agent-a239ae70   mtime=2026-04-21 21:47
  agent-a492e85b   mtime=2026-04-21 13:04   ← seconds before 13:20 update
  agent-a6261937   mtime=2026-04-21 23:11
  agent-a6b3a040   mtime=2026-04-21 12:26
  agent-a7f2ee1c   …
  agent-aa0fc891   …
  agent-aae6ecee   …
  agent-ae492320   …
  agent-ae498b62   …
  agent-af135dbb   …
  (11/20 total)
```

**Operational consequence:** any subagent dispatched into one of these stale worktrees does NOT see the rule that *"SeshatTheme is informational/brainstorm-seed only — it is NOT a drop-in to adopt verbatim."* That subagent could "fix" the deliberate divergences (e.g., revert `Palette.brandChampagne = #D4D0C8` back to `#CCB990` from the reference), and to that subagent it would look like clean compliance.

**This is precisely the failure mode of memory in `proposal_discipline.md`** (*"adopt reference artifacts verbatim, but Ninimma has deliberately diverged"*) — and it can happen silently, because the agent in the stale worktree believes its CLAUDE.md is authoritative.

The same drift class can apply to *any* CLAUDE.md addition. Every commit to project CLAUDE.md leaves a wake of stale snapshots in long-lived worktrees.

---

### Conflicts and surprises (consolidated)

| # | Surface conflict | Authoritative? |
|---|------------------|----------------|
| 1 | Layer 2B says "ALWAYS prefer Glob/Grep/Read" — Layer 5 says "ALWAYS use search_files MCP" | Ambiguous. Hooks fire later in prompt; their `ALWAYS` lexically wins. But CLAUDE.md is project-specific. Behavior is undefined and depends on which I weight more. |
| 2 | Layer 2B says "NOT a Meta monorepo, all code is local" — Layer 5 hook is written assuming Meta monorepo (codesearch agent, three_pai_external_web_search) | Unresolved. The hooks aren't context-aware. |
| 3 | Layer 4's `using-superpowers` says "even 1% chance a skill might apply" — Layer 1 system prompt's tone-and-style says "match responses to the task: a simple question gets a direct answer" | Contradictory in spirit. Skill check fires first; can produce ceremony before answers. |
| 4 | Layer 2C "Architectural Invariants" section is a TODO placeholder | Unfilled. The most project-load-bearing section is empty. |
| 5 | 11/20 worktree CLAUDE.md files are stale (Layer 7) | Subagents in stale worktrees act on outdated rules silently. |
| 6 | Memory MEMORY.md indexes 33+ files but only loads them "when topic surfaces" | Recognition-dependent; rules in memory can fail to fire even when relevant. |

### Rule-budget and load shape

Approximate operating-instruction surface that can fire during a Ninimma session:

| Layer | Bytes (approx) | Load timing |
|-------|---------------|-------------|
| 1 — Hardcoded system prompt | ~12,000 | Always |
| 2 — User CLAUDE.md hierarchy | ~10,000 | Always |
| 3 — MEMORY.md index | ~3,500 | Always |
| 3b — Memory files (33×, avg 4-6 KB each) | ~150,000 | On-demand |
| 4 — `using-superpowers` skill | ~3,500 | SessionStart hook each session |
| 4b — Other plugin instructions | unknown, large | Plugin-dependent |
| 5 — SessionStart hooks | ~2,500 | Once per session |
| 6 — Per-turn reminders | ~1,500 (recurring) | Each turn |
| 7 — Worktree CLAUDE.md (subagents) | ~3,400 each, possibly stale | When subagent spawns |

**Always-loaded surface ≈ 33,000 bytes.** Plus on-demand memory and per-turn reminders. The agent's first ~33 KB of context every session is operating instructions before any actual task content.

### Implications

1. **The 1-in-5-pushback rate from Part 3 is partly a layer-conflict tax.** When Layer 5 and Layer 2 disagree about tool choice, or when `using-superpowers` fires ceremony before a 3-sentence answer, the user pays a turn.

2. **Worktree drift (Layer 7) is a real source of agent misbehavior** that you've never had visibility into. If 11/20 worktrees are stale today, then ~55% of subagent dispatches are running on outdated rules. The "every agent keeps talking like this is live app with many users" complaint from `5694de6d turn 8` could literally be subagents in worktrees that never received the pre-dogfood reframe.

3. **Project CLAUDE.md is undersized for the actual rule density.** ~3,400 bytes for Ninimma vs ~10,000 bytes of hierarchy total, but `simplicity_discipline.md` alone is 4 KB and `proposal_discipline.md` is 4 KB. Most operational discipline lives in memory (Layer 3b) which only loads on topic-recognition. Layer 2C (project CLAUDE.md) has an empty Architectural Invariants section that ought to carry load-bearing rules.

4. **There is no project skill layer at all.** `~/.claude/skills/` only has Meta-internal symlinks plus `writing-plans`. `~/Projects/nitkrar/personal_scribe/.claude/` has worktrees + settings.local.json but no `skills/` or `agents/` directory. This is the gap that adopting `grill-me` and `ubiquitous-language` would fill.

5. **The skill-system layer (Layer 4) contributes more behavioral pressure than CLAUDE.md does**, but is invisible from any text file you control. If you wanted to suppress the pre-answer skill-eval ceremony in this project, you'd need to disable the `10x-engineer` plugin in `~/.claude/settings.json` — the project CLAUDE.md cannot do it.

---

## Resumption pointer

If picking this up later: the next decisions are

- **(immediate)** whether to clean up stale worktree CLAUDE.md copies (`rm -rf .claude/worktrees/agent-*` then let fresh ones recreate as needed), and
- **(short-term)** whether to fill the empty *Architectural Invariants* section in project CLAUDE.md, and
- **(medium-term)** whether to draft `grill-me` and `ubiquitous-language` as project skills under `personal_scribe/.claude/skills/` (or wherever Claude Code's skill-discovery picks them up — needs verification).

The transcript scan script at `/tmp/scan_transcripts.py` can be re-run with adjusted patterns. The drift audit can be re-run with the script in Part 4's worktree section.


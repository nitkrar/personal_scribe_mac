# Phase 4 — Operating-instruction stack evidence (verbatim)

**Date:** 2026-04-25
**Companion summary:** `2026-04-25-agent-execution-retrospective.md` Part 4

This file persists the verbatim contents of every constraint surface that loads
during a personal_scribe Claude Code session. The summary file analyzes the
implications; this file holds the raw text so conclusions can be re-derived or
re-audited.

---

## File 1 — `~/.claude/CLAUDE.md` (global, always loaded)

Path: `/Users/nitinkum/.claude/CLAUDE.md`
Size: 4,141 bytes

```markdown
# Global Operating Principles

Applies to every project unless project CLAUDE.md overrides.

## 1. Verification before claiming done
Distinguish committed / built / tested / runtime-verified. Only the last earns "done", "shipped", "fixed".
- `build succeeds` ≠ `feature works`. Never claim shipped without runtime verification.
- Default to understating: "committed + tests pass, please verify" over "shipped".
- If multiple fixes can't be manually verified, flag the unknowns explicitly.

## 2. Hold decisions; classify before pivoting
When the user questions a prior decision, DO NOT default to proposing the alternative. Classify:
- **Fact change** — new data contradicts prior rationale → pivot, surface what changed.
- **Re-check** — user rechecking or surprised by known consequence → defend with original rationale, ask what's new.
- **Preference change** — user dropped a constraint → pivot, note the shift.

Predictable consequences of the prior decision (code volume, complexity, size) are NOT new information.

## 3. Adopt reference artifacts verbatim
When handed a reference folder/spec/bundle:
- Read every file, full content.
- Copy tables, assignments, contracts by value. Only restructure where the reference is silent.
- **Silent divergence is the cardinal sin.** To deviate: surface the proposed divergence with reasons, wait for confirmation.
- Before claiming thoroughness: "Does my output contain every named rule and structure, or did I paraphrase them away?"

## 4. Semantic audits, not keyword grep
When reviewing for duplicate/forbidden symbols or contract violations:
- Inventory every declaration (protocol/actor/struct/enum/class).
- Map by semantic role, not by name. Different name + same concept = duplicate.
- Require explicit "Forbidden Duplicates Semantic Audit" sections in revisions that share a contract.

## 5. Small-chunks review; no silent divergence
- Never dump a 100+ line diff and expect review.
- Walk references one section at a time: state what the reference says, state match/divergence, ask before moving on.
- For >3 changes to a plan or summary doc: ask "one-by-one or batch?" Default one-by-one.
- For high-blast-radius writes (global CLAUDE.md, shared contracts): show draft in chat before committing.

## 6. Phase multi-task requests; dispatch subagents
When a user message contains ≥2 distinct verbs ("revisit X, fix Y, remove Z"):
- Do NOT execute all in one pass.
- Propose a phased breakdown with dependencies and checkpoints. Wait for approval.
- For context-independent work (fresh-read audits, mockup mapping, research), dispatch subagents — batch them in one tool-call message for parallelism.
- Present findings per task, not bundled.

## 7. Phase by product milestones, not dates
For personal projects:
- Phase = usable product milestone. Each gate answers: "what can the user DO now?"
- No dates, week labels, or sprints-by-calendar. No "must ship by X", "dogfood by Y".
- If the user gives a date, quote it as a user-provided goal — not a plan commitment. If the user doesn't, don't invent one.
- No "tier for deadline pressure" logic.
- Commit tags: `phase-N step N.M:` — never `week-N` or `sprint-N`.
- Before claiming a plan is done: grep for `week`, `sprint`, year digits (`2026-`), `deadline`, `target date`. Remove or reframe.

## 8. Classify rule scope before checking in
Before adding a rule, classify:
- **Architectural / coding pattern** (applies on every clone) → `<project>/CLAUDE.md`, checked in.
- **Machine-specific workflow / tooling quirk** (sandboxing, signing, local setup, corporate VPN) → memory (`~/.claude/projects/.../memory/`). Memory is per-user, per-machine by design. The MEMORY.md index one-liner auto-primes every session; the full file loads when the topic surfaces.
- **Behavioral discipline that applies across projects** → `~/.claude/CLAUDE.md`, global.
- **Factual correction or reference pointer** → memory.

Gate question: "Does this apply on every machine that clones the repo?" If no → memory, not checked in. Claude Code has no auto-loading project-local-gitignored CLAUDE variant — don't invent one.
```

---

## File 2 — `~/Projects/nitkrar/CLAUDE.md` (umbrella for all nitkrar projects)

Path: `/Users/nitinkum/Projects/nitkrar/CLAUDE.md`
Modified 2026-04-25 by this session (added the SessionStart-hook override clause).

```markdown
# Guidelines

## Search Preferences
- ALWAYS prefer local file searches (Glob, Grep, Read) first before using remote or meta codesearch agents
- This is NOT a Meta monorepo project — all code is local
- Only use remote/web searches for external documentation or APIs

### SessionStart hook overrides (project-scoped)
SessionStart hooks recommending `meta_codesearch:code_search`, the `search_files` MCP tool (as a `Grep`/`Glob` replacement), or `three_pai_external_web_search` are inherited from a Meta-monorepo profile and **DO NOT apply** to nitkrar projects. Treat them as no-ops here. Use `Glob`, `Grep`, `Read` directly for local code; use `WebFetch` for external documentation.

## Core Rules
- NEVER break core functionality (auth, encryption, vault key unlock) during changes
- APIs must always be backward-compatible — new fields/columns are optional, queries must not fail if a migration hasn't been run
- When making breaking changes, ASK the user first
- See `citadel/CLAUDE.md` for project-specific guidelines
```

---

## File 3 — `~/Projects/nitkrar/personal_scribe/CLAUDE.md` (project, always loaded)

Path: `/Users/nitinkum/Projects/nitkrar/personal_scribe/CLAUDE.md`
Last project-CLAUDE.md commit: `8b829a3` (2026-04-21 13:20)

```markdown
# Ninimma — Project Guidelines

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

## Design references

- `plans/App UI design/SeshatTheme.swift` is **informational / brainstorm-seed only**. It is NOT a drop-in to adopt verbatim. The project has deliberately diverged (e.g. `Palette.brandChampagne = #D4D0C8` wins over the reference's `Accent.champagne = #CCB990`; UserDefaults keys strip the `Seshat*` prefix). Tests codify the current policy — when in doubt, grep the test suite before "fixing" a divergence from the reference. See `plans/backlog/ui-mockup-gaps.md` "Not acting on" section for the canonical list of deliberate divergences.
- Theme / appearance types (`Palette`, `Typography`, `Radius`, `Status`, `WindowTint`, `PillAppearance`, `PillStyle`, `AppTheme`) live in `Sources/PersonalScribeAppKit/Theme/` — NOT in `PersonalScribeCore`. The central-layers refactor only consolidated app identity into `PersonalScribeCore/AppBrand/` (display name, bundle ID, version).

## Commit Conventions
- Use `phase-N step N.M:` tags. Never `week-N` or `sprint-N`.
- Test + fix go in the same commit when TDD applies.
```

**Notable observation:** `## Architectural Invariants` is an unfilled `<!-- TODO -->` placeholder. Candidates listed inline (PillOverlayPresenter routing, menu bar lifecycle, hotkey monitor setup, paste injection permission flow) but the section has been a placeholder since at least early April per `git log -- CLAUDE.md`.

---

## File 4 — `~/.claude/settings.json` (Claude Code config)

Path: `/Users/nitinkum/.claude/settings.json`

```json
{
  "env": {
    "CLAUDE_CODE_DISABLE_FEEDBACK_SURVEY": "1",
    "CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS": "1",
    "DISABLE_AUTOUPDATER": "1",
    "DISABLE_ERROR_REPORTING": "1",
    "DISABLE_TELEMETRY": "1",
    "STATUSLINE_DIRECTORY_MAX_LEN": "20",
    "STATUSLINE_DISABLE_BRANCH": "1",
    "STATUSLINE_DISABLE_CALENDAR": "1",
    "STATUSLINE_DISABLE_SESSION_NAME": "1",
    "STATUSLINE_ENABLE_TIMER": "1"
  },
  "permissions": {
    "allow": [
      "Bash(bash *source-all.sh*)",
      "...(many bash patterns omitted for brevity — full list at the file path above)..."
    ]
  },
  "model": "opus[1m]",
  "statusLine": {
    "type": "command",
    "command": "bash \"$(find $HOME/.claude/plugins/cache -path '*/meta-statusline-pro/*/bin/statusline.sh' 2>/dev/null | sort -V | tail -1)\""
  },
  "enabledPlugins": {
    "10x-engineer@claude-templates": true,
    "browser@claude-templates": true,
    "cdm-dw@claude-templates": true,
    "chat-notifications@claude-templates": true,
    "codex-cc@claude-templates": true,
    "codex-plugin-cc@agent-market": true,
    "data@claude-templates": true,
    "datamate@claude-templates": true,
    "debrief@claude-templates": true,
    "gdrive-mount@claude-templates": true,
    "hyperclaude@claude-templates": true,
    "meta-statusline-pro@claude-templates": true,
    "para-workspace@claude-templates": true,
    "source-control-at-meta@claude-templates": false,
    "tmux-statusline@claude-templates": true,
    "tracing@Meta": false
  },
  "extraKnownMarketplaces": {
    "agent-market": {
      "source": {
        "source": "directory",
        "path": "/Users/nitinkum/.claude/agent-market"
      }
    }
  },
  "effortLevel": "high",
  "skipDangerousModePermissionPrompt": true
}
```

**Key behavioral knobs:**
- `model: "opus[1m]"` — Opus 4.7 with 1M context.
- `effortLevel: "high"` — likely affects reasoning/thinking budget.
- `skipDangerousModePermissionPrompt: true` — skips the dangerous-mode opt-in for this user.
- 13 plugins enabled (4 marked false / disabled). The `10x-engineer@claude-templates` enables the `using-superpowers` skill that demands skill invocation before any response.
- 2 plugins explicitly disabled: `source-control-at-meta@claude-templates` (Phabricator/diffsplit tooling, wrong project), `tracing@Meta` (Meta-internal tracing).

---

## File 5 — `~/.claude/plugins/installed_plugins.json` (full plugin manifest)

```json
{
  "version": 2,
  "plugins": {
    "llm-rules@Meta": [
      { "scope": "user", "installPath": "...Meta/llm-rules/unknown", "version": "unknown", "installedAt": "2026-01-25T12:34:45.547Z", "lastUpdated": "2026-02-25T13:13:31.900Z" }
    ],
    "meta@Meta": [
      { "scope": "user", "installPath": "...Meta/meta/unknown", "version": "unknown", "installedAt": "2026-01-25", "lastUpdated": "2026-02-25" }
    ],
    "trajectory@Meta": [
      { "scope": "local", "projectPath": "/Users/nitinkum/Projects/nitkrar/citadel", "version": "unknown", "installedAt": "2026-01-25", "lastUpdated": "2026-04-03" }
    ],
    "code_provenance@Meta": [
      { "scope": "local", "projectPath": "/Users/nitinkum/Projects/nitkrar/citadel", "version": "0.0.1", "installedAt": "2026-02-23", "lastUpdated": "2026-04-03" }
    ],
    "knowledge_search@Meta": [
      { "scope": "user", "version": "0.0.1", "installedAt": "2026-02-23", "lastUpdated": "2026-02-25" }
    ],
    "10x-engineer@claude-templates": [
      { "scope": "user", "installPath": "...claude-templates/10x-engineer/1.0.0", "version": "1.0.0", "installedAt": "2026-03-02", "lastUpdated": "2026-03-02" }
    ],
    "source-control-at-meta@claude-templates": [
      { "scope": "user", "version": "1.12.0", "installedAt": "2026-02-23", "lastUpdated": "2026-02-23" }
    ],
    "meta-statusline-pro@claude-templates": [
      { "scope": "user", "version": "1.7.0", "installedAt": "2026-02-23", "lastUpdated": "2026-03-14" }
    ],
    "chat-notifications@claude-templates": [
      { "scope": "user", "version": "1.0.0", "installedAt": "2026-02-23", "lastUpdated": "2026-04-22" }
    ],
    "meta_codesearch@Meta": [
      { "scope": "local", "projectPath": "/Users/nitinkum/Projects/nitkrar/citadel", "version": "0.0.1", "installedAt": "2026-02-25", "lastUpdated": "2026-04-03" }
    ],
    "meta_knowledge@Meta": [
      { "scope": "local", "projectPath": "/Users/nitinkum/Projects/nitkrar/citadel", "version": "0.0.1", "installedAt": "2026-02-25", "lastUpdated": "2026-04-03" }
    ],
    "data@claude-templates": [
      { "scope": "user", "version": "1.0.0", "installedAt": "2026-03-09", "lastUpdated": "2026-04-22" }
    ],
    "tmux-statusline@claude-templates": [
      { "scope": "user", "version": "1.2.0", "installedAt": "2026-03-05", "lastUpdated": "2026-04-22" }
    ],
    "hyperclaude@claude-templates": [
      { "scope": "user", "version": "1.0.1", "installedAt": "2026-03-05", "lastUpdated": "2026-04-22" }
    ],
    "debrief@claude-templates": [
      { "scope": "user", "version": "1.4.1", "installedAt": "2026-03-09", "lastUpdated": "2026-04-22" }
    ],
    "gdrive-mount@claude-templates": [
      { "scope": "user", "version": "1.1.2", "installedAt": "2026-03-09", "lastUpdated": "2026-04-22" }
    ],
    "para-workspace-core@claude-templates": [
      { "scope": "local", "projectPath": "/Users/nitinkum/Projects/nitkrar/citadel", "version": "1.3.0", "installedAt": "2026-03-09", "lastUpdated": "2026-04-03" }
    ],
    "para-workspace-gdrive@claude-templates": [
      { "scope": "local", "projectPath": "/Users/nitinkum/Projects/nitkrar/citadel", "version": "1.2.0", "installedAt": "2026-03-09", "lastUpdated": "2026-04-03" }
    ],
    "para-workspace-reporting@claude-templates": [
      { "scope": "local", "projectPath": "/Users/nitinkum/Projects/nitkrar/citadel", "version": "1.2.0", "installedAt": "2026-03-09", "lastUpdated": "2026-04-03" }
    ],
    "para-workspace-meetings@claude-templates": [
      { "scope": "local", "projectPath": "/Users/nitinkum/Projects/nitkrar/citadel", "version": "1.0.0", "installedAt": "2026-03-09", "lastUpdated": "2026-04-03" }
    ],
    "para-workspace-integrations@claude-templates": [
      { "scope": "local", "projectPath": "/Users/nitinkum/Projects/nitkrar/citadel", "version": "1.0.0", "installedAt": "2026-03-09", "lastUpdated": "2026-04-03" }
    ],
    "para-workspace@claude-templates": [
      { "scope": "user", "version": "3.1.0", "installedAt": "2026-03-09", "lastUpdated": "2026-04-22" }
    ],
    "datamate@claude-templates": [
      { "scope": "user", "version": "1.0.0", "installedAt": "2026-03-09", "lastUpdated": "2026-04-22" }
    ],
    "sl@Meta": [
      { "scope": "local", "projectPath": "/Users/nitinkum/Projects/nitkrar/citadel", "version": "2.1.0", "installedAt": "2026-03-16", "lastUpdated": "2026-04-03" }
    ],
    "cdm-dw@claude-templates": [
      { "scope": "user", "version": "1.0.1", "installedAt": "2026-03-24", "lastUpdated": "2026-04-22" }
    ],
    "browser@claude-templates": [
      { "scope": "user", "version": "1.1.0", "installedAt": "2026-03-24", "lastUpdated": "2026-04-22" }
    ],
    "meta-cli-core@claude-templates": [
      { "scope": "user", "version": "1.1.0", "installedAt": "2026-04-17", "lastUpdated": "2026-04-17" }
    ],
    "privacylib@Meta": [
      { "scope": "user", "version": "0.1.1", "installedAt": "2026-04-06", "lastUpdated": "2026-04-06" }
    ],
    "codex-cc@claude-templates": [
      { "scope": "user", "version": "1.0.1", "installedAt": "2026-04-14", "lastUpdated": "2026-04-14" }
    ],
    "codex-plugin-cc@agent-market": [
      { "scope": "user", "version": "1.0.4", "installedAt": "2026-04-14", "lastUpdated": "2026-04-14" }
    ],
    "agent-security-guardrails@claude-templates": [
      { "scope": "user", "version": "1.0.4", "installedAt": "2026-04-22", "lastUpdated": "2026-04-22" }
    ],
    "tracing@Meta": [
      { "scope": "user", "version": "0.1.0", "installedAt": "2026-04-22", "lastUpdated": "2026-04-22" }
    ]
  }
}
```

**Total plugins installed:** 30. Of those, 13 are enabled per `settings.json`.

**Local-scoped plugins (citadel-only)** — pulled in for the citadel project, but their cache lives globally and can leak: `trajectory@Meta`, `code_provenance@Meta`, `meta_codesearch@Meta`, `meta_knowledge@Meta`, `para-workspace-core/-gdrive/-reporting/-meetings/-integrations`, `sl@Meta`. These are the source of the SessionStart hook recommendations that don't apply to Ninimma.

---

## File 6 — `~/.claude/projects/-Users-nitinkum-Projects-nitkrar-personal-scribe/memory/MEMORY.md` (auto-loaded index)

51 lines. Loads on every session start.

```markdown
## Project state

- [Ninimma decisions](project_seshat.md) — display "Ninimma"; bundle `com.nitkrar.personal_scribe`; Swift prefix `PersonalScribe*`; UserDefaults keys unprefixed; three-pillar vision; Parakeet-TDT via FluidAudio; product-milestone phasing.
- [Ninimma execution state](project_seshat_execution_state.md) — resumption pointer: 2026-04-24 session 4 — #017 stage A landed (`9d01f84`, live-apply hotkey customization + plist collision + restore-default); modifier-only binding remains unimplemented by design.
- [Central-layers refactor overview](project_central_layers_refactor.md) — 9-layer parallel-build-then-swap-then-delete strategy; plans at `plans/central/`; behavior-neutral invariant through Stages 1–3.
- [Ninimma rename + PS prefix](project_ninimma_rename.md) — Stage A types `Seshat*` → `PS*` (mechanical); Stage B deferred atomic rebrand.
- [BACKLOG.md canonical location](project_backlog_structure.md) — at repo root as of 2026-04-22; `BACKLOG_ARCHIVE.md` alongside; ROADMAP in `plans/`.
- [Codex setup probe](project_codex_setup.md) — run codex-cc setup script before proposing alternatives; `ready: true` means `codex-cc:codex-rescue` works.
- [macOS TCC ad-hoc quirk](project_tcc_ad_hoc_quirk.md) — ad-hoc signed apps get per-path TCC records; permissions don't follow from DMG copy to /Applications.
- [Santa Transitive Allowlisting — main repo](project_santa_build_gate.md) — Lockdown + TA covers compiler output on canonical path; `swift test` runs clean. Worktree paths: `swift build --build-tests` only, never `swift test`.
- [Test clipboard leak — fixed 2026-04-18](project_test_clipboard_leak.md) — historical; sandbox seams landed via `d10dd4e`/`da776ac`/`d87ad24`; `swift test` is safe again.
- [Phase 3 — notes = transcripts](project_phase3_notes_equals_history.md) — Phase 3 stores every transcription unconditionally; no `type` column; defer intent distinction to Phase 4.
- [App size strip](project_app_size_strip.md) — `scripts/package.sh` runs `strip -x` on release builds only (`561e157`); 20MB → 9.5MB. Debug builds keep symbols.
- [Swift 6 Sendable boundary](project_swift6_sendable_boundary.md) — NSEvent/CGEvent can't cross MainActor.assumeIsolated directly; use `@unchecked Sendable` box pattern.
- [Pill hit-testing constraint](project_pill_hit_testing.md) — `ClickThroughHostingView.mouseDown` overrides without super → SwiftUI gestures inside the pill don't fire; sub-region interactivity needs AppKit hit-testing.
- [SessionCoordinator Option A API](project_session_coord_option_a.md) — mode-specific starts (`startIfIdle`/`startHoldIfIdle`) + mode-agnostic stop/cancel (`stopIfActive`/`cancelIfActive`).
- [AI Models tab authoritative](project_ai_models_tab_authoritative.md) — Voice + future LLM model state, progress, disk usage, download/delete, active-switch all live in AIModelsTab.
- [Record-without-transcribe path](project_record_without_transcribe.md) — hotkey during model-download is allowed; capture runs; transcription stage deferred until model `.finished`. ResponseCard surfaces live status.
- [Paste pipeline constraints](project_paste_pipeline_constraints.md) — `CGEventPost` of `Cmd+V` is fire-and-forget; Ninimma cannot observe whether paste landed. Silent-drop into a cursorless surface combined with unconditional `scheduleRestore` wipes transcript from clipboard too (#072). #042's PID probe is load-bearing; don't regress.
- [FluidAudio bundled-model trap](project_fluidaudio_model_bundling.md) — `VadManager(modelDirectory:)` is a cache-root API that silently downloads from HuggingFace on layout mismatch; bundled `.mlmodelc` must be loaded via `MLModel(contentsOf:)` + `VadManager(config:vadModel:)`. Applies to all FluidAudio model families.
- [Modifier-only hotkey binding unimplemented](project_hotkey_modifier_only_unimplemented.md) — double-tap ⌥ not bindable end-to-end by design; `tapCount` is legacy storage; re-enabling needs recorder + monitor gesture-machine changes in both layers.
- [macOS system-audio mute = AppleScript not HAL](project_macos_system_audio_mute.md) — `set volume output muted` via `NSAppleScript` is route-independent, covers all output routes, ~20 LoC. CoreAudio HAL `kAudioDevicePropertyMute` is per-device and requires latching device ID + separate handling for system-output — over-engineering for "mute the laptop." Landed in #076.

## Feedback — consolidated clusters

- [Simplicity discipline](simplicity_discipline.md) — crux first; pre-dogfood simple answer; lean plan structure; no speculative abstraction or circular tests.
- [Proposal discipline](proposal_discipline.md) — adopt references verbatim; small-chunks review; enumerate every item in collapse tables; semantic (not keyword) audits.
- [Verify before asserting](verify_before_asserting.md) — framing labels; scoping claims; debug-to-consumers not producers; regression history; runtime "done" claims.
- [Decision discipline](decision_discipline.md) — don't flip on first prompt (classify fact-change vs re-check); tests codify current policy over stale reference specs.
- [Response shape](response_shape.md) — phased breakdown for multi-task messages; conversation-level (not implementation-level) flow diagrams.
- [Codex workflow](codex_workflow.md) — when to dispatch; atomic chunks; parallel N-for-N agents; wedge-proof brief structure; Santa no-build/no-test mode.
- [Codex failure modes](codex_failure_modes.md) — silent completions (20-30%); shutdown delays (20-40 min); worktree evaporation under async wrappers.
- [Worktree pitfalls](worktree_pitfalls.md) — skip swift commands from worktree paths; stale-HEAD snapshots; peer-conformer drift on protocol extensions.
- [Git workflow](git_workflow.md) — explicit file-by-name staging (never `-A`); stash traps; trunk-only; push cadence at end-of-phase.
- [BACKLOG conventions](backlog_conventions.md) — never stage `BACKLOG.md` unless asked; session naming (one per main session); in-flight row ownership.
- [Project phasing](project_phasing.md) — product milestones not calendar dates; Stage A/B for non-trivial backlog; pre-dogfood on-disk state is disposable.
- [Testing discipline](testing_discipline.md) — TDD required; `@StateObject` doesn't retain in XCTest harness; probe tool availability before proposing fallbacks.
- [Test cadence](test_cadence.md) — `swift build --build-tests` per sub-step; `--filter` tests at staged-changes checkpoints; full suite only at end-of-phase.
- [Test-review heuristics](test_review_heuristics.md) — dead-test patterns (SPM boilerplate, scaffolding, synthesized-code tests, post-refactor duplicates); keep-rails for codex reviewers (defaults, constants, enum raw values); spot-check when one agent flags 3×+ more than siblings.
- [Test rigor — no fluff](test_rigor_no_fluff.md) — when WRITING new tests: every test must pass the "would fail if code were broken meaningfully" filter. Skip mock-theater, tautology, constant-matches-itself. Default to ≤ half the reflex count; expect 50–70% of first-draft lists to be trimmable.
- [Architecture heuristics](architecture_heuristics.md) — race fixes belong in pipeline not coordinator; per-caller patterns are contract questions; sticky UI guards smell like source-of-truth bugs.

## Feedback — standalone

- [Central-layers Stage 2 implementor discipline](feedback_stage2_discipline.md) — briefs change source only; main session verifies + dispatches test-fix agent per layer.
- [Rebuild friction minimization](feedback_rebuild_friction.md) — each DMG rebuild costs a Gatekeeper reapproval round; batch fixes into one rebuild cycle.
- [Memory discipline](feedback_memory_discipline.md) — don't commit speculative root-cause claims; wait for fix confirmation before recording mechanism as fact.
- [Scope completion](feedback_scope_completion.md) — finish single-unit tasks; don't self-chunk into internal steps and stop mid-work. One user ask = one landable outcome.
- [Bundle / pref default alignment](feedback_bundle_pref_alignment.md) — when a Settings toggle overrides a bundle-level launch flag (Info.plist LSUIElement etc.), the pref default must match the bundle default OR startup code must read the pref and apply the API before user input. Otherwise the "default" is a lie and fresh installs land in an unreachable state.
- [User-intent over literal read](feedback_user_intent_over_literal_read.md) — when the user names a gap, investigate the user-visible behavior they want; don't dismiss by finding a narrow technical sense where the word is already satisfied. Proof is product behavior, not code presence.
- [Tests written alongside implementation are not spec](feedback_tests_as_spec.md) — same-session tests codify whatever the agent happened to build; manual-verification docs / product intent / user-reported symptoms are the oracle. Fix commits delete/rewrite bug-fossil tests.
```

---

## All 43 memory files (filenames only)

Path: `/Users/nitinkum/.claude/projects/-Users-nitinkum-Projects-nitkrar-personal-scribe/memory/`

```
architecture_heuristics.md
backlog_conventions.md
codex_failure_modes.md
codex_workflow.md
decision_discipline.md
feedback_bundle_pref_alignment.md
feedback_memory_discipline.md
feedback_rebuild_friction.md
feedback_scope_completion.md
feedback_stage2_discipline.md
feedback_tests_as_spec.md
feedback_user_intent_over_literal_read.md
git_workflow.md
MEMORY.md
project_ai_models_tab_authoritative.md
project_app_size_strip.md
project_backlog_structure.md
project_central_layers_refactor.md
project_codex_setup.md
project_fluidaudio_model_bundling.md
project_hotkey_modifier_only_unimplemented.md
project_macos_system_audio_mute.md
project_ninimma_rename.md
project_paste_pipeline_constraints.md
project_phase3_notes_equals_history.md
project_phasing.md
project_pill_hit_testing.md
project_record_without_transcribe.md
project_santa_build_gate.md
project_seshat_execution_state.md
project_seshat.md
project_session_coord_option_a.md
project_swift6_sendable_boundary.md
project_tcc_ad_hoc_quirk.md
project_test_clipboard_leak.md
proposal_discipline.md
response_shape.md
simplicity_discipline.md
test_cadence.md
test_review_heuristics.md
test_rigor_no_fluff.md
testing_discipline.md
verify_before_asserting.md
worktree_pitfalls.md
```

Total = 44 entries (43 individual memory files + the MEMORY.md index).

---

## Worktree drift audit (pre-cleanup state, 2026-04-25)

At the time of audit, `.claude/worktrees/` contained 20 agent worktrees, each with its own copy of `CLAUDE.md` snapshotted at worktree-creation time (never re-synced).

### Project CLAUDE.md commit history

```
8b829a3 trunk: CLAUDE.md — SeshatTheme is informational + theme types live in AppKit/Theme  (2026-04-21 13:20)
ab0ad5f trunk: rename phase 6 — docs sweep (BACKLOG + README + CLAUDE + manual verification runbooks)
115960a phase-2 meta: rewrite Santa build-frequency rule (TA covers main repo)
2ffa8c6 phase-2 setup: gitignore agent worktrees + document Santa-gated build cadence
bf1f205 chore: retire week1 plans, adopt phase-based PLAN_PHASES + agent bundle v3
```

### Drifted worktrees (all missing the post-`8b829a3` Design references section)

```
DRIFTED:
  agent-a0fb3b02   CLAUDE.md_mtime=2026-04-21 23:45
  agent-a239ae70   CLAUDE.md_mtime=2026-04-21 21:47
  agent-a492e85b   CLAUDE.md_mtime=2026-04-21 13:04   ← seconds before 13:20 update
  agent-a6261937   CLAUDE.md_mtime=2026-04-21 23:11
  agent-a6b3a040   CLAUDE.md_mtime=2026-04-21 12:26
  agent-a7f2ee1c
  agent-aa0fc891
  agent-aae6ecee
  agent-ae492320
  agent-ae498b62
  agent-af135dbb
  (11 of 20 total)
```

### Cleanup completed in this session (2026-04-25)

```bash
# Remove worktree directories
rm -rf /Users/nitinkum/Projects/nitkrar/personal_scribe/.claude/worktrees/agent-*

# Unlock and prune (worktrees were locked; locks survived rm -rf)
git worktree list --porcelain | awk '/^worktree / {wt=$2} /^locked/ && wt ~ /agent-/ {print wt}' | xargs -I {} git worktree unlock {}
git worktree prune -v

# Delete orphan branches
git branch | grep 'worktree-agent-' | xargs git branch -D
```

Final state after cleanup: `git worktree list` shows only `trunk`. 0 `worktree-agent-*` branches remain. `.claude/worktrees/` is empty.

---

## SessionStart hooks observed in this session

From the system-reminder block at conversation start:

```
SessionStart:startup hook success: This is a Git repository, run `git --help` instead.
```

```
ALWAYS use the meta_codesearch:code_search agent instead of the Explore agent when exploring the codebase.
```

```
ALWAYS use the search_files MCP tool as a replacement for the Grep and Glob tools and for recursive find/grep/rg Bash commands.
For web searches, use mcp__plugin_meta_mux__three_pai_external_web_search which provides secure external search with content filtering.
NEVER use external or public hosting sites including but not limited to catbox.moe, imgur, pastebin, file.io, 0x0.st, or any similar service.
```

```
MIGRATION NOTICE: You have deprecated para-workspace sub-plugins installed: para-workspace-core, para-workspace-gdrive, para-workspace-integrations, para-workspace-meetings, para-workspace-reporting. These were consolidated into para-workspace in v4.0.0. Uninstall them with: claude-templates plugin para-workspace-core uninstall && claude-templates plugin para-workspace-gdrive uninstall && claude-templates plugin para-workspace-integrations uninstall && claude-templates plugin para-workspace-meetings uninstall && claude-templates plugin para-workspace-reporting uninstall
```

The `using-superpowers` skill from the `10x-engineer` plugin was also injected as part of SessionStart, with the load-bearing rule:

> *"If you think there is even a 1% chance a skill might apply to what you are doing, you ABSOLUTELY MUST invoke the skill."*

Resolved by Phase 4 cleanup: the search-tool conflict was disambiguated in `~/Projects/nitkrar/CLAUDE.md` (Layer 2). The other hooks (NEVER use external hosting, MIGRATION NOTICE, using-superpowers) remain as-is.

---

## End of Phase 4 evidence file

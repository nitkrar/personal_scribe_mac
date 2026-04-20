# Session notes — 2026-04-20

Snapshot of the decisions, patterns, and open items surfaced across today's multi-session central-layers refactor + rename-pass planning work. Durable rules live in the memory store under `~/.claude/projects/-Users-nitinkum-Projects-nitkrar-seshat/memory/`; this doc is a retrospective pointer for the next session.

## Naming decisions

Decisions ordered most to least user-visible. All decisions captured in `project_ninimma_rename.md` memory + reflected in `plans/PHASE_0_rename.md`.

- **Types adopt `PS` prefix** (e.g., `SeshatConfig → PSConfig`, `SeshatTheme → PSTheme`, `SeshatLogger → PSLogger`, `SeshatApp → PSApp`). Earlier PHASE_0 revisions said prefix-less (`Config`, `Theme`, `AppLogger`); reverted because (a) generic names collide with SwiftUI/os types, (b) grep-uniqueness matters, (c) aligns with the locked product-code decision.
- **UserDefaults keys stay unprefixed** (`BaseDirectoryPath`, not `SeshatBaseDirectoryPath`, not `PSBaseDirectoryPath`). Per-bundle-ID storage makes a prefix redundant.
- **SPM target names unchanged in Stage A** — `SeshatCore`, `SeshatAppKit`, etc. Module rename lands in the deferred Stage B atomic rebrand alongside bundle-ID flip, folder migration, and display-name flip.
- **Filename = type name**. `Config.swift → PSConfig.swift`, `Errors.swift → PSError.swift`, `Logger.swift → PSLogger.swift`, `SeshatApp.swift → PSApp.swift`. Broke the "errors/logger as namespace idiom" pattern for consistency with every other prefix-rename file move.
- **Display brand "Ninimma"** stays confined to one place: `PSAppBrand.displayName`. Zero `"Seshat"` or `"Ninimma"` string literals elsewhere. Stage B atomic flip.

## Architecture insights

- **Rename pass splits into two stages** (decided 2026-04-20, was previously "one atomic commit").
  - **Stage A — type prefix**: `Seshat* → PS*` on types only. Mechanical. No bundle-ID, no folder, no display flip. User-invisible. Can land anytime post-Stage-3 (or before, if prioritized — see tradeoff below).
  - **Stage B — user-visible rebrand**: module target renames + bundle-ID flip + `Info.plist` + folder migration + assets + `PSAppBrand.displayName = "Ninimma"`. One release moment. Triggers macOS TCC permission reset (mic / input monitoring / accessibility) — user re-grants once, not repeatedly.
- **Phase sequence**: PHASE_0 (rename) → PHASE_1 (permission-service unification) → PHASE_2 (unified UI bundle). PHASE_1 depends on Layer 1 Stage 2 being landed. PHASE_2 references the Manus bundle at `plans/App UI design/` + `/tmp/manus-rename-bundle/Ninimma_UI_Bundle/`.
- **Rename-before-Stage-3 is viable** (surfaced today, not yet acted on). PHASE_0 is behavior-neutral; Stage 3 is behavior-neutral; either order works. Flipping to PHASE_0 first unblocks PHASE_1/PHASE_2 sooner at the cost of renaming code that Stage 3 will delete (minor mechanical waste) and needing a grep-pattern flip pass on in-flight Stage 3 inventory drafts. Current default: Stage 3 → PHASE_0. Open to flip if PHASE_1/PHASE_2 priority rises.
- **Central-layers refactor is a moving target**. Scope-creep commit `a489d55` (labeled "L5 fix Step 1") actually deleted ~14 dead methods in `SessionCoordinator.swift` that belonged to the L7 Step 2 scope. Stage 3 inventory caught the drift via tree-wins methodology — plans lagged, code was ahead.

## Stage 3 inventory pattern (the methodology)

`plans/central/GLOBAL_STAGE3_PROMPT.md` locks a **code-first** approach — `rg`/`ls` authoritative, plans = commentary, tree wins when they disagree. Every row in the aggregated delete table carries a `Grep to prove unreferenced` column so inventory is reproducible at execution time (catches drift mid-chunk).

Per-layer drafts live in `plans/central/drafts/stage3/layer_<N>_inventory.md` + `cross_layer_inventory.md`. 8 of 10 layer drafts landed today (L1, L2, L4, L6, L7, L8, L9, cross). L3 on third attempt (first two wedged at `reading-inputs` phase). L5 deferred to a post-trunk-stable re-run alongside L7 (which snapshotted before the scope-creep commit landed).

Key signal from L1: zero approved delete rows — every plan-listed Stage 3 symbol still has live refs. L1 Stage 2 swap is incomplete. That confirms PHASE_1 is blocked behind a Stage 2 finish pass.

## Parallel agent orchestration patterns

- **Parallel codex sub-agents > one big writer**. 10 agents in one dispatch, background execution, each with a single owned output file. Pattern captured in `feedback_parallel_small_agents.md`.
- **Strict file ownership + no worktrees** is safer for read-heavy inventory tasks than worktree isolation. Each agent gets one draft path; everything else is read-only. Avoids Santa-TA worktree popups and eliminates merge complexity. Worked cleanly for 10 concurrent agents today.
- **Heartbeat contract** (`plans/codex-heartbeat-contract.md`): 3–5 min cadence, first within 60 s, filename `.codex-heartbeat/<agent-id>.md`, delete on success. Probe via `python3 plans/central/agents_status.py` — tags `active / stale / wedged` on 5/10 min thresholds.
- **Forwarder completion != task completion**. The Claude forwarder returns in ~45–180 s after launching the underlying Codex task; the actual work continues in the background. Treat the "agent completed" notification as a hand-off signal only. Heartbeat + draft file are ground truth.
- **Wedge-proofing future dispatches**: brief agents to (a) open with phase `grepping-codebase`, not `reading-inputs`, (b) cap upfront doc reading (e.g., ≤100 lines before first grep), (c) write a `[BLOCKED]` stub at 15 min if stuck rather than wedging silently. Applied on L3 v3 after two prior wedges.

## Discipline / process calls

- **Small-chunks review**. Proposed every non-trivial change before executing (the PHASE_0 edit flow: banner + flag → user confirms SeshatApp rename → filename alignment question → user confirms option (a) → full edit + commit). Avoided silent divergence.
- **Commit what you changed, not the whole index**. Used targeted `git add plans/PHASE_0_rename.md` — other modified files (`Sources/SeshatAppKit/Composition/*`, `Tests/SeshatAppKitTests/*`, etc.) belong to the parallel Layer 1 fix session and stay untouched in my commits.
- **Memory updates are retrospective**. `project_ninimma_rename.md` rewritten today to capture the staging split + PHASE_0 divergence flag. MEMORY.md index line updated to reflect Stage A / Stage B split.
- **Trunk HEAD shifts mid-session are survivable**. Multiple parallel sessions committing during the Stage 3 inventory run caused HEAD to move 5+ commits during dispatch. Tree-wins methodology + reproducible greps absorbed this cleanly — no re-dispatch needed except for L3 + L5 + L7.

## Open items (what's still in flight or queued)

- **Layer 1 Stage 2 swap incomplete** — Q1 fix agent inflight in a parallel session (`.codex-heartbeat/l1-s2-retry.md` seen on probe). PHASE_1 blocked behind this.
- **L3 inventory** — v3 codex task running; first two attempts wedged.
- **L5, L7 inventory re-runs** queued for after trunk stabilizes (L5 took a mid-flight `7d52e70` commit; L7 draft pre-dates the scope-creep deletion in `a489d55`).
- **Stage 3 synthesis** — once L3 lands, produce `plans/central/INDEX.md` + `plans/central/STAGE_3_DELETION.md` per GLOBAL_STAGE3_PROMPT.md with a drift callout at the top.
- **Hotkey #22** — still open (from prior session memory).
- **Rename-vs-delete order** — decision pending (see Architecture insights above).

## References

- Memory (durable rules): `~/.claude/projects/-Users-nitinkum-Projects-nitkrar-seshat/memory/`
- Central-layers plans: `plans/central/LAYER_*.md`, `plans/central/GLOBAL_STAGE3_PROMPT.md`, `plans/CENTRAL_LAYERS_PROMPT.md` (locked reference)
- Rename plans: `plans/PHASE_0_rename.md`, `plans/PHASE_1_permission_service.md`, `plans/PHASE_2_unified_ui.md`
- Heartbeat + probe: `plans/codex-heartbeat-contract.md`, `plans/central/agents_status.py`
- In-flight Stage 3 drafts: `plans/central/drafts/stage3/` (uncommitted scratch; will be folded into the synthesis step then cleaned up)

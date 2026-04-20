# Global Stage 3 — Plan-Writing Prompt

## What this file is

A standalone prompt to hand to a fresh Claude Code session at the project repo path (pre-rename: `/Users/nitinkum/Projects/nitkrar/seshat`; post-rename: `/Users/nitinkum/Projects/nitkrar/personal_scribe`). The session's job is to **write the global Stage 3 deletion plan** — one markdown file aggregating the deletion surface across the 9 central-layer refactor layers, with ordering, chunking, verification gates, and commit conventions.

**The session writes a plan. It does NOT execute deletions.** Stage 3 execution is user-triggered later, after every layer's Stage 2 has landed and the full test suite is green.

## How to use

Paste this entire file as the first message in a new Claude Code session at the project repo path on branch `trunk`.

## Critical discipline (baked into the plan)

The plan you write MUST open with this paragraph verbatim:

> **Do NOT diverge from this plan. Silent divergence is the cardinal sin. To deviate, surface the proposed divergence in a commit-message comment AND in the hand-off report; wait for main-session confirmation. Paraphrasing the contract is divergence. Deleting a symbol not listed here is divergence. Deleting in an order other than the one specified is divergence.**

Every delete chunk in your plan MUST list the exact symbol/file paths being removed and the exact `rg` pattern that would prove nothing still references them.

## Working directory

Project repo path on branch `trunk` (pre-rename `/Users/nitinkum/Projects/nitkrar/seshat`; post-rename `/Users/nitinkum/Projects/nitkrar/personal_scribe`).

Out of scope for Stage 3 (do not touch): `plans/seshat_agent_bundle/`, `plans/App UI design/`, `plans/app rename and branding_UI_Bundle.zip`, `/tmp/manus-rename-bundle/`. Those belong to the post-Stage-3 rename pass.

## Current state (read first)

- 9-layer central-layers refactor is mid-Stage-2 on trunk.
- Every layer plan (`plans/central/LAYER_<N>_*.md`) has its own local "Stage 3 — Delete" section.
- `plans/central/PROGRESS.md` (may be stale — prefer `git log`) tracks per-layer progress.
- `plans/CENTRAL_LAYERS_PROMPT.md:54` called for an `INDEX.md` with a global Stage 3 section. `INDEX.md` was never written — that's the gap this plan closes.

## Locked decisions (do not re-open)

1. **Stage 3 is behavior-neutral.** No UX change, no copy change, no animation tweak, no UserDefaults migration, no bundle ID change, no folder rename. Delete-only.
2. **Stage 3 is NOT the rename pass.** Do not touch anything related to Ninimma, `PersonalScribe*` prefix, `personal_scribe`, `com.nitkrar.personal_scribe`, or the `AppBrand.displayName` value. Those land in a separate post-Stage-3 rename phase per `plans/rename/PLAN.md`.
3. **SPM target names unchanged this phase.** The central-layers refactor phase keeps the pre-rename `SeshatAppKit`, `SeshatCore`, `SeshatAudio`, `SeshatSession`, `SeshatTranscription`, `SeshatTestSupport` names as-is. No `Package.swift` product/target edits except removing references to deleted files. (The rename pass itself moves them to `PersonalScribe*` in a separate phase.)
4. **No UserDefaults key deletions** unless the layer plan explicitly lists the key in its Stage 3 section (e.g., `SeshatOnboardingCompleted` per Layer 1 — historical key name retained; the rename pass handles its migration to `OnboardingCompleted`).
5. **One commit per chunk.** Subject format: `trunk: stage 3 — <layer-or-cross-layer-scope> delete <one-line summary>`. No squash.
6. **Never skip hooks.** `git commit --no-verify` is forbidden.

## Building the deletion inventory — code-first

**Use this methodology. Do not deviate.** Today's refactor run showed repeated drift between layer plans and landed code (stale symbol names in plan text, fix-forward renames the plans missed, Stage 2 scope expansions the plans didn't capture, plan-doc references to types that were deleted a week ago). The tree is authoritative; the plans are commentary.

### Procedure

1. **Inventory new central-layer directories** (Stage 1 creations — confirm exact paths via `ls Sources/*/` and `ls Sources/*/*/`, don't trust this list blindly). Paths listed below are pre-rename; post-rename replace the `Seshat*` module segments with `PersonalScribe*` per `plans/rename/INVENTORY.md`:
   - `Sources/SeshatCore/Permissions/` (Layer 1)
   - `Sources/SeshatCore/Storage/` + `Sources/SeshatAppKit/Storage/` (Layer 2)
   - `Sources/SeshatCore/Preferences/` (Layer 3)
   - `Sources/SeshatCore/AppStore/` + `Sources/SeshatAppKit/AppStore/` (Layer 4)
   - `Sources/SeshatCore/Output/` + `Sources/SeshatAppKit/Output/` (Layer 5)
   - `Sources/SeshatCore/ModelSelection/` or `Sources/SeshatCore/Models/Selection/` (Layer 6)
   - `Sources/SeshatSession/Pipeline/` (Layer 7)
   - `Sources/SeshatCore/Metrics/` + `Sources/SeshatAppKit/Metrics/` (Layer 8)
   - `Sources/SeshatCore/AppBrand/` (Layer 9)

2. **Enumerate legacy siblings** — types/files outside the new dirs that deal with the same concern. For each, run:
   - `rg -l '<SymbolName>' Sources/ Tests/`
   - Zero production + zero test hits → **APPROVED for delete**.
   - Still-referenced → Stage 2 swap incomplete OR actively-used cross-layer primitive. **NOT a Stage 3 candidate**; flag as `[QUESTION]`.

3. **Enumerate dead methods inside surviving files**. Some files aren't being deleted entirely but have dead private methods from Stage 2 delegation (e.g., L7 S2 Step 1 left ~14 private methods in `SessionCoordinator.swift` unreferenced). Use `rg 'func <methodName>' Sources/` — methods declared but not called from anywhere under `Sources/` or `Tests/` are dead. Hand-off report lists them per-file for chunked deletion.

4. **Renamed-for-collision files** (Stage 1 deviations documented in commits) — e.g., `InputMonitoringPermissionProbe.swift` was renamed from `PermissionStatus.swift` to resolve a Stage 1 basename collision. Grep confirms they have no active consumers. Delete.

5. **Legacy test files** — if every type a test imports is slated for deletion, the test itself goes too.

6. **Consult plans only when grep is ambiguous** or when you need the *why*. Plans = commentary, not source of truth. If the plan and the code disagree, **the code wins**. Optionally flag plan staleness as a separate `[QUESTION]` for post-Stage-3 plan cleanup.

7. **Stage 1 & Stage 2 code reviews** — `rg -l 'delete|remove' plans/central/reviews/` — scan for reviewer-flagged deletions that didn't make it into layer plans' Stage 3 sections. These are high-confidence candidates with an explicit reviewer trace.

### Why code-first (not plan-first, not hybrid)

- Inventory is reproducible: run `rg` with the same patterns, get the same answer.
- Surfaces drift automatically: anything in the tree that shouldn't be there is findable.
- Avoids the plan-writing session inheriting any earlier plan's bias or omissions.
- Plans can be updated post-facto to match what actually landed.

## Your task

Produce **one file**: `plans/central/INDEX.md`.

`INDEX.md` serves two purposes:
1. A short overview — per-layer summary row, dependency graph, pointer to `PROGRESS.md`.
2. **The global "Stage 3 — Deletion pass" section** — the detailed delete plan.

If splitting is cleaner, produce `plans/central/INDEX.md` (overview) AND `plans/central/STAGE_3_DELETION.md` (detailed plan), and justify the split in the hand-off report.

## Required structure of the Stage 3 plan section

### 1. Methodology declaration

State up front: "This plan uses the code-first methodology per `plans/central/GLOBAL_STAGE3_PROMPT.md`. Inventory from `rg`/`ls`; plans consulted only for disambiguation of *why*; when plan and tree disagree, tree wins." Record every `rg` pattern used to build the inventory so the result is reproducible.

### 2. Preconditions gate (must-be-true before execution)

- Every layer's Stage 2 commit landed on trunk.
- Every layer's Stage 2 code review verdict is APPROVED-ish (APPROVED / APPROVED-W-NITS / APPROVED-W-FOLLOWUPS; no NEEDS REVISION / CHANGES REQUIRED).
- Full test suite green on trunk (`swift test` passes from the canonical repo path, not a worktree).
- `swift build --build-tests` green.
- No open worktrees with uncommitted changes.
- Explicit user go-ahead.

### 3. Aggregated delete inventory

One table. Columns:

- **Layer** (1–9, or "cross-layer")
- **Kind** (type | protocol | extension | file | test | UserDefaults key)
- **Name**
- **Path** — `file:line` or `file`
- **Source of truth** — how this was identified: `plan` (Approach A), `grep` (Approach B), `hybrid-confirmed` (both), `grep-only` (not in plan)
- **Why safe to delete** — one sentence
- **Grep to prove unreferenced** — exact `rg` pattern that must return 0 `Sources/` + `Tests/` hits before the delete commit
- **Depends on** — other deletions that MUST happen first ("none" if leaf)

Rows grouped by layer then by dependency (leaves first within each layer).

### 4. Ordering strategy

- **Leaves first**: deletions with no cross-references.
- **Internal roots next**: types only this layer's old code referenced.
- **Cross-layer roots last**: types that multiple layers' old code once referenced.

Document circular dependencies (if any) and propose resolution (usually: delete their shared parent first).

### 5. Chunks + verification gates

Group the delete inventory into **chunks** — each chunk is one commit, 1–N related deletions safe to land together. Between chunks:

- `swift build --build-tests` — must pass.
- Relevant test target — must pass (e.g., after Layer 1 chunk run `SeshatAppKitTests` + `SeshatCoreTests`).
- Full `swift test` after the last chunk of each layer.

Chunk failure → fix forward (re-add missed reference, adjust grep, split smaller). Never silently revert.

Guideline: ≤200 LoC deleted per chunk, or one conceptually-cohesive group.

### 6. Commit convention

- Subject: `trunk: stage 3 — layer <N> delete <what>` or `trunk: stage 3 — cross-layer delete <what>`.
- Body:
  - Bulleted list of files/symbols removed.
  - Exact `rg` patterns confirmed to return 0 hits on `Sources/` + `Tests/`.
  - Any `Package.swift` notes (only if a product/target definition references the deleted file).

### 7. Failure-handling playbook

- **Reference discovered mid-chunk** (grep missed it, or Stage 2 didn't fully swap): halt chunk, do NOT commit. Surface the still-referenced symbol + call site. Decide: (a) finish the Stage 2 swap in a fix-forward commit, or (b) exclude the symbol with a `[QUESTION]` comment. Never delete and let the build break.
- **Test breaks**: if the test exercised deleted behavior, delete the test (it's part of Stage 3). If the test exercises surviving behavior through a deleted helper, rewrite against the new layer in the same commit.
- **Cross-layer surprise**: e.g., Layer 5 Stage 3 wants to delete `X` but Layer 7's Stage 2 introduced a new reference. Treat as Stage 2 regression; fix forward on the other layer before proceeding.

### 8. Rename-pass decoupling

Plan MUST include verbatim: *"Do not rename modules, types, files, bundle IDs, UserDefaults keys, or brand strings during Stage 3. Those changes belong to the post-Stage-3 rename pass."* Reviewers should flag any chunk that crosses this line.

## Overview section (in INDEX.md if single file, at the top)

~30 lines:
- One-line description of each layer.
- Dependency graph (which layer's Stage 2 depends on which).
- Pointer to `PROGRESS.md` as the authoritative current-state snapshot.
- Pointer to `CENTRAL_LAYERS_PROMPT.md` as the locked master spec.
- Pointer to the global Stage 3 section (or `STAGE_3_DELETION.md` if split).

## What NOT to do

- **Do NOT execute any deletions.** Plan only.
- **Do NOT modify `plans/CENTRAL_LAYERS_PROMPT.md`.** It's a locked reference artifact.
- **Do NOT modify any `plans/central/LAYER_*.md`** except to flag drift with a `[QUESTION]` comment — silent plan edits are divergence.
- **Do NOT run `swift build` or `swift test`.** `rg` + reading source is enough to plan.
- **Do NOT dispatch subagents.** Single-session planning task.
- **Do NOT start the rename pass.**
- **Do NOT add new concepts** beyond aggregating the existing layer plans + observed code.

## Hand-off report

- Commit SHA + subject of the `INDEX.md` (and optional `STAGE_3_DELETION.md`) commit.
- Methodology used (A / B / C). If C, the split of which items came from which source.
- Total deletion count: N types, M protocols, P files, Q tests, R UserDefaults keys.
- Number of chunks + expected cumulative LoC deletion range.
- Cross-layer ordering surprises found.
- Per-layer Stage 3 section discrepancies: plan lists deletion that's already gone / plan lists deletion that grep shows is still referenced / plan missing a deletion that grep surfaced. Flag each with `[QUESTION]`.
- Confidence: APPROVED / NEEDS REVIEW / QUESTIONS OPEN.
- Confirmation lines:
  - `No deletions executed — plan only.`
  - `No swift build or swift test invoked.`
  - `No CENTRAL_LAYERS_PROMPT.md modifications.`
  - `No LAYER_*.md modifications.`

## Commit convention for the plan itself

One commit: `trunk: plans/central — global Stage 3 deletion plan`.

If split into `INDEX.md` + `STAGE_3_DELETION.md`: `trunk: plans/central — INDEX + global Stage 3 deletion plan`.

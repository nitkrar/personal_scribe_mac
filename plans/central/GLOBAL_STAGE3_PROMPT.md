# Global Stage 3 — Plan-Writing Prompt

## What this file is

A standalone prompt to hand to a fresh Claude Code session at `/Users/nitinkum/Projects/nitkrar/seshat`. The session's job is to **write the global Stage 3 deletion plan** — one markdown file aggregating the deletion surface across the 9 central-layer refactor layers, with ordering, chunking, verification gates, and commit conventions.

**The session writes a plan. It does NOT execute deletions.** Stage 3 execution is user-triggered later, after every layer's Stage 2 has landed and the full test suite is green.

## How to use

Paste this entire file as the first message in a new Claude Code session at `/Users/nitinkum/Projects/nitkrar/seshat` on branch `trunk`.

## Critical discipline (baked into the plan)

The plan you write MUST open with this paragraph verbatim:

> **Do NOT diverge from this plan. Silent divergence is the cardinal sin. To deviate, surface the proposed divergence in a commit-message comment AND in the hand-off report; wait for main-session confirmation. Paraphrasing the contract is divergence. Deleting a symbol not listed here is divergence. Deleting in an order other than the one specified is divergence.**

Every delete chunk in your plan MUST list the exact symbol/file paths being removed and the exact `rg` pattern that would prove nothing still references them.

## Working directory

`/Users/nitinkum/Projects/nitkrar/seshat`. Branch `trunk`.

Out of scope for Stage 3 (do not touch): `plans/seshat manus resources/`, `plans/App UI design/`, `plans/app rename and branding_UI_Bundle.zip`, `/tmp/manus-rename-bundle/`. Those belong to the post-Stage-3 rename pass.

## Current state (read first)

- 9-layer central-layers refactor is mid-Stage-2 on trunk.
- Every layer plan (`plans/central/LAYER_<N>_*.md`) has its own local "Stage 3 — Delete" section.
- `plans/central/PROGRESS.md` (may be stale — prefer `git log`) tracks per-layer progress.
- `plans/CENTRAL_LAYERS_PROMPT.md:54` called for an `INDEX.md` with a global Stage 3 section. `INDEX.md` was never written — that's the gap this plan closes.

## Locked decisions (do not re-open)

1. **Stage 3 is behavior-neutral.** No UX change, no copy change, no animation tweak, no UserDefaults migration, no bundle ID change, no folder rename. Delete-only.
2. **Stage 3 is NOT the rename pass.** Do not touch anything related to Ninimma, `PS*` prefix, `personal_scribe`, `com.nitkrar.personal_scribe`, or the `AppBrand.displayName` value. Those land in a separate post-Stage-3 rename phase.
3. **SPM target names unchanged this phase.** `SeshatAppKit`, `SeshatCore`, `SeshatAudio`, `SeshatSession`, `SeshatTranscription`, `SeshatTestSupport` stay as-is. No `Package.swift` product/target edits except removing references to deleted files.
4. **No UserDefaults key deletions** unless the layer plan explicitly lists the key in its Stage 3 section (e.g., `SeshatOnboardingCompleted` per Layer 1).
5. **One commit per chunk.** Subject format: `trunk: stage 3 — <layer-or-cross-layer-scope> delete <one-line summary>`. No squash.
6. **Never skip hooks.** `git commit --no-verify` is forbidden.

## Building the deletion inventory — code-first vs plan-first

This is the central methodological choice for this plan. Pick one before you start and record the choice in the plan file.

### Approach A — Plan-first (read 9 layer plans, aggregate their delete lists)

**How**: Read every `plans/central/LAYER_<N>_*.md`, extract the Stage 3 section's delete list, merge into one table. Spot-check source via `rg` to confirm each symbol still exists.

**Pros**:
- Captures *intent* — why a symbol is slated for deletion, which Stage 2 swap freed it, what special handling (e.g., renamed-for-collision alias files).
- Every deletion is traceable back to a locked contract the user signed off on.

**Cons**:
- Plans may have drifted from landed reality. Stage 1 code reviews surfaced deviations that were fix-forwarded in commits (e.g., Layer 1's `PermissionStatus.swift` rename to `InputMonitoringPermissionProbe.swift`) — some of those deviations may or may not be reflected in the plan text.
- Deletions that plans forgot won't surface; deletions the plan lists that already happened will look like pending work.

### Approach B — Code-first (enumerate code, let plans provide context)

**How**:
1. List the **new central-layer directories** (the ones Stage 1 created):
   - `Sources/SeshatCore/Permissions/` (Layer 1)
   - `Sources/SeshatCore/Storage/` + `Sources/SeshatAppKit/Storage/` (Layer 2)
   - `Sources/SeshatCore/Preferences/` (Layer 3)
   - `Sources/SeshatAppKit/AppStore/` (Layer 4)
   - `Sources/SeshatCore/Output/` + `Sources/SeshatAppKit/Output/` (Layer 5)
   - `Sources/SeshatCore/ModelSelection/` (Layer 6)
   - `Sources/SeshatSession/Pipeline/` (Layer 7)
   - `Sources/SeshatCore/Metrics/` + `Sources/SeshatAppKit/Metrics/` (Layer 8)
   - `Sources/SeshatCore/AppBrand/` (Layer 9)
   - Confirm exact paths via `ls Sources/*/` — don't trust this list blindly.
2. For each **legacy sibling** (types/files that live *outside* the new dirs and deal with the same concern), check for still-existing references:
   - `rg -l '<SymbolName>' Sources/ Tests/`
   - Zero production-code hits + zero test hits → safe to delete.
   - Still-referenced → either Stage 2 swap is incomplete, or this is an actively-used cross-layer primitive (not a Stage 3 candidate).
3. For each **renamed-for-collision file** (Stage 1 deviations documented in commits): those appear in the tree but have no meaningful consumers; grep confirms, plan confirms intent. Delete.
4. For each **legacy test file** that exercised the old API: if the types it imports are all slated for deletion, the test goes too.
5. Consult plans only when the grep result is ambiguous or when you need the *why*.

**Pros**:
- Source of truth is the source code. Divergences-from-plan surface automatically because they're in the tree.
- Less text to read — 9 plan files are verbose.
- Matches how we debug: read the code first, docs when stuck.

**Cons**:
- Doesn't explain *why* a file is alive. Some files are deliberately preserved (renamed-for-collision, defense-in-depth) and that context lives in plans/commits, not code.
- Risk of proposing deletions for types that are still needed for reasons not obvious from `rg` alone (e.g., cross-module test helpers, future-parked features).

### Approach C — Recommended: hybrid (code-first with plan as context)

1. **Inventory**: code-first. Enumerate new dirs → find legacy siblings → grep for references.
2. **Classification**: for each candidate deletion, consult the corresponding layer plan's Stage 3 section.
   - Plan confirms → mark APPROVED.
   - Plan silent but grep is unambiguous (zero refs, no intent hint needed) → mark APPROVED with note "not in layer plan Stage 3 list; code-first justification".
   - Plan lists deletion but grep finds references → Stage 2 incomplete OR cross-layer user; mark `[QUESTION]`, surface to user.
   - Plan lists deletion and grep confirms gone-from-trunk already → mark OBSOLETE (nothing to delete here; flag plan text as stale).
3. **Stage 1 code reviews**: `rg -l 'delete|remove' plans/central/reviews/LAYER_*_stage1_code_review.md` — scan for reviewer-flagged deletions that didn't make it into the layer plans' Stage 3 sections.
4. **Source of truth wins**: if the plan and the code disagree, the code is authoritative. Update the plan's Stage 3 section in a separate commit only after this global plan lands.

## Your task

Produce **one file**: `plans/central/INDEX.md`.

`INDEX.md` serves two purposes:
1. A short overview — per-layer summary row, dependency graph, pointer to `PROGRESS.md`.
2. **The global "Stage 3 — Deletion pass" section** — the detailed delete plan.

If splitting is cleaner, produce `plans/central/INDEX.md` (overview) AND `plans/central/STAGE_3_DELETION.md` (detailed plan), and justify the split in the hand-off report.

## Required structure of the Stage 3 plan section

### 1. Methodology declaration

State up front which approach (A / B / hybrid C) this plan uses. If hybrid, name which step checked which source.

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

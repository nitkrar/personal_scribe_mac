# Central-Layers Refactor — Progress Snapshot

**Last updated**: 2026-04-19 22:04 BST
**Branch**: `trunk`
**Source of truth**: this file is a snapshot. Re-generate by querying `git log --oneline plans/central/*` and inspecting heartbeat files under `.codex-heartbeat/`.

## Status columns

- **Plan**: commit that landed the layer's `plans/central/LAYER_N_*.md`
- **Plan review**: first-pass review of the plan (commit in `plans/central/reviews/LAYER_N_review.md`)
- **Stage 1**: parallel-build implementation (new types + tests in new dirs, no consumer migration)
- **S1 code review**: review of Stage 1 implementation
- **S1 fix-forward**: commit addressing S1 code-review findings (or N/A if verdict was APPROVED)
- **Stage 2**: consumer swap — migrate existing call sites to use the new layer
- **S2 review**: review of Stage 2 consumer-swap implementation

Legend: ✅ done / 🔧 in flight / — not started / ⛔ blocked / N/A not needed

## Current state (all 9 layers)

| Layer | Plan | Plan review | Stage 1 | S1 code review | S1 fix-forward | Stage 2 | S2 review |
|---|---|---|---|---|---|---|---|
| **1 Permissions** | ✅ `38ca52f` | ✅ `9c322d9` NEEDS REV | ✅ `64d7999` | ✅ `c12d2c7` NEEDS REV (1C/3M/1m) | ✅ `39e655e` | ⛔ held | — |
| **2 Storage** | ✅ `f1518a7` | ✅ `748acc6` NEEDS REV | ✅ `8cfc844` | ✅ `677f70b` NEEDS REV (0/1M/0/1n) | 🔧 in flight (worktree) | ⛔ blocked on fix | — |
| **3 Settings** | ✅ `3a93392` | ✅ `020935d` NEEDS REV | ✅ `dd9a44c` | ✅ `ecd8c70` APPROVE-W-NITS (0/0/1m/1n) | N/A | ✅ `5b6e023` | — |
| **4 AppStore** | ✅ `f7ed814` | — never done | 🔧 in flight (worktree, Candidate A) | — | — | ⛔ blocked on S1 + L1 S2 | — |
| **5 Output** | ✅ `7c43e53` | ✅ `6c5483a` NEEDS REV | ✅ `23247a6` | ✅ `7872a52` NEEDS REV (0/2H/2M/0) | ✅ `624f91f` | ⛔ held (API changed, re-review needed) | — |
| **6 Model selection** | ✅ `e3852c9` | — reviewer wedged | ✅ `23725ce` | ✅ `a7c024a` APPROVED-W-FOLLOWUPS (0/0/0/2 low) | ✅ `d85e627` | ✅ `a3a0ba8` | — |
| **7 Pipeline** | ✅ `9b527ec` | ✅ `b80e343` NEEDS REV | ✅ `f395327` | ✅ `db3b15a` CHANGES REQUIRED (1B/0/1m) | ✅ `7c5f978` + 3 regress. pending | ⛔ held (high risk + regressions) | — |
| **8 Metrics** | ✅ `e3aba93` | ✅ `98bfc70` NEEDS REV | ✅ `ab402c3` | ✅ `897cf3c` CHANGES REQUIRED (0/2M/1m) | ✅ `89512bd` | ⛔ not dispatched | — |
| **9 App Brand** | ✅ `b1d407e` | ✅ `e8ebdd8` NEEDS REV | ✅ `8d866da` | ✅ `71e4473` APPROVE-W-NITS (0/0/0/1n) | N/A | 🔧 restart in flight (worktree) | — |

Verdict legend: C=critical, B=blocker, H=high, M=major, m=minor, n=nit.

## Decisions locked

- **Locked reference**: `plans/CENTRAL_LAYERS_PROMPT.md` — do not modify.
- **Candidate A (facade/republisher)** approved for Layer 4 at 2026-04-19. Do NOT revisit unless new technical data emerges.
- **Layer 4 Q1**: `currentRecordingDuration` = wall-clock since `.recording` began, 250ms UI cadence, clears on state transitions out of `.recording`. Final stored duration in SQLite reflects `TranscriptionResult.audioDuration` (ASR post-trim view) — unchanged.
- **Layer 5 streaming** deferred: `plans/backlog/pipeline-streaming-defer.md`. L5 Stage 1 stripped its streaming surface; Layer 7's `PipelineOutputSink.deliverPartial` stays dormant until the stream-build slice.
- **Layer 6 v3 descriptor**: placeholder `revision = "main"` pending user-supplied SHA. `defaultActiveDescriptor` stays on v2.
- **Layer 7 `SessionPipelining`**: protocol now requires `Actor` conformers in addition to `Sendable` (Swift 6 isolation-safe — Stage 1 accepted deviation from plan text).
- **Rename pass deferred post-Stage-3**: all 9 plans stay behavior-neutral. PS prefix, `personal_scribe` folder, Ninimma display name land in a separate future pass — not during Stages 1/2/3.

## In-flight agents

| Agent | Worktree branch | Phase |
|---|---|---|
| L2 review-fix | `worktree-agent-a74c2918` | address permissions-ordering race + dead code |
| L4 Stage 1 | `worktree-agent-a3bde7b9` | Candidate A contracts + facade + tests |
| L9 Stage 2 restart | `worktree-agent-a6774bda` | consumer literal swap |
| L8 fix v2 | main repo (landed `89512bd`) | ✅ complete |

## Queued work (awaiting quiet trunk)

- **L7 regression fix**: 3 tests in `SessionPipelineOrchestratorTests` broke from `7c5f978` fix: `testRepeatedToggleDuringTranscribingIsIgnoredAndFinalResultSurvives`, `testShortRecordingPublishesRecordingTooShortWithoutCallingTranscriber`, `testToggleCapturePublishesStagesProgressAndFinalResult`.
- **L2, L5, L7, L8 Stage 2 dispatch**: after their Stage 1 fixes are stable + re-reviewed if API changed.
- **L1 Stage 2 dispatch**: after L1 fix stabilizes (observable contract may have consumer impact).
- **L4 Stage 2 dispatch**: after L4 Stage 1 lands + L1 Stage 2 lands.
- **Main-session full test run**: held until in-flight worktree agents commit and we cherry-pick.

## Process learnings captured in memory

- `feedback_parallel_small_agents.md` — dispatch N parallel agents beats one big writer.
- `feedback_codex_no_build_test.md` — brief agents to skip `swift build`/`swift test` when 3+ parallel to avoid Santa popup storms.
- `feedback_stage2_discipline.md` — Stage 2 agents: source-only, no bundled test updates, worktree isolation, main session runs test + dispatches dedicated test-fix agent per layer.

## Regeneration

To refresh this file in a future session:
1. `git log --oneline plans/central/` — pull all layer-related commits.
2. `ls plans/central/reviews/` — enumerate completed reviews.
3. `ls .codex-heartbeat/` — enumerate in-flight agents.
4. Rebuild the status table above.

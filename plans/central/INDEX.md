# Central-layers refactor — INDEX

## Status (2026-04-20): Stage 3 executed

All 7 approved-now delete rows landed on trunk. `swift build --build-tests` green. L1 + L7 re-inventory confirmed 0 new approvals — remaining `[QUESTION]` rows are Stage 2 follow-up work, not Stage 3 scope. See `STAGE_3_DELETION.md` §Execution-status and §Retrospective (parallel-commit race).


Overview of the 9-layer parallel-build-then-swap-then-delete refactor on `trunk`. The full Stage 3 deletion plan lives at [`plans/central/STAGE_3_DELETION.md`](./STAGE_3_DELETION.md). Master reference is [`plans/CENTRAL_LAYERS_PROMPT.md`](../CENTRAL_LAYERS_PROMPT.md); per-layer plans at `plans/central/LAYER_<N>_*.md`; per-layer progress snapshot at `plans/central/PROGRESS.md` (may be stale — prefer `git log`).

## Critical discipline

> **Do NOT diverge from this plan. Silent divergence is the cardinal sin. To deviate, surface the proposed divergence in a commit-message comment AND in the hand-off report; wait for main-session confirmation. Paraphrasing the contract is divergence. Deleting a symbol not listed here is divergence. Deleting in an order other than the one specified is divergence.**

## Layer summary

| # | Layer | New central dir | Stage 2 status (current trunk) | Stage 3 approved rows | Notes |
|---|---|---|---|---|---|
| 1 | Permissions | `Sources/PersonalScribeCore/Permissions/` | Fix-forward in flight (`phase-2 step 1.retry` cluster) | 0 — **snapshot stale**, re-inventory after fix lands | Every plan-listed Stage 3 symbol still has live refs in current draft |
| 2 | Storage | `Sources/PersonalScribeCore/Storage/` | Landed; duplicate `BaseDirectoryPath` owner remains (L2/L3 ambiguity) | 2 | `PersonalScribeConfig.modesDirectory()` dead method; `PersonalScribeConfigScaffoldingTests` test |
| 3 | Preferences | `Sources/PersonalScribeCore/Preferences/` | Landed `5b6e023` (bundled) | 1 | `typealias SeshatPasteMode = PasteMode` transitional shim (historical name retained in Stage 3 inventory for audit) |
| 4 | AppStore | `Sources/PersonalScribeCore/AppStore/` + `Sources/PersonalScribeAppKit/AppStore/` | Partial — `AppKitActiveModeProvider` hardcoded; S2 review `REQUEST CHANGES` | 0 — candidate rows blocked on precursors | 2 blocked-on-precursor candidates flagged |
| 5 | Output | `Sources/PersonalScribeCore/Output/` + `Sources/PersonalScribeAppKit/Output/` | Landed `7d52e70`; `PasteInjector`/`MenuBarSceneModel` compatibility seam still live | 0 — all candidates blocked on Stage 2 swap completion | 9 blocked `[QUESTION]` rows; 5 plan-stale items (`SilentPaster`, `OutputService.copy`, `CopyOutputService`, `PasteOutput`, `NotificationOutput` already gone) |
| 6 | Model Selection | `Sources/PersonalScribeCore/Models/Selection/` | Stage 2 UI/menu swaps not landed on trunk; core path done | 1 | `PersonalScribeConfig.modelId` shim; 11 blocked `[QUESTION]` rows |
| 7 | Pipeline | `Sources/PersonalScribeSession/Pipeline/` | Landed through Step 1; scope-creep `a489d55` already deleted ~14 dead methods | 1 — **snapshot partially stale** | `SessionCoordinator.seconds(from:)` dead method; 8 blocked `[QUESTION]` rows |
| 8 | Metrics | `Sources/PersonalScribeCore/Metrics/` | Core landed; consumer wiring not landed (no Home-tab use) | 0 | No legacy ad-hoc rollup code on trunk to delete |
| 9 | AppBrand | `Sources/PersonalScribeCore/AppBrand/` | Landed | 2 | `BuildInfo` + `BuildInfoTests` — paired leaf |
| — | cross-layer | — | — | 0 | No cross-layer deletions ready on current trunk |

**Totals**: 7 approved-now rows across 5 layers. Additional ~20 `[QUESTION]` rows blocked on Stage 2 precursors (see `STAGE_3_DELETION.md` §3).

## Dependency graph (layer-level, Stage 3 scope)

No Stage 3 delete-time dependencies between layers: each approved row is a leaf whose `Depends on` column is `none`. The ordering strategy in `STAGE_3_DELETION.md` §4 groups by **file** (not by layer) to minimize touching the same file in multiple commits.

Execution precondition is per-layer, not cross-layer: a layer's rows execute only after that layer's Stage 2 is landed and APPROVED. Currently that's true for L2, L3, L6, L7, L9. L1/L4 have open Stage 2 follow-ups. L5 inventory is pending. L8 is empty.

## Pointers

- **Full Stage 3 plan**: [`plans/central/STAGE_3_DELETION.md`](./STAGE_3_DELETION.md)
- **Master reference (locked)**: [`plans/CENTRAL_LAYERS_PROMPT.md`](../CENTRAL_LAYERS_PROMPT.md)
- **Per-layer plans**: `plans/central/LAYER_1_permissions.md` … `plans/central/LAYER_9_app_brand.md`
- **Per-layer drafts (Stage 3 inventory inputs, scratch, uncommitted)**: `plans/central/drafts/stage3/layer_<N>_inventory.md` + `cross_layer_inventory.md`
- **Progress snapshot**: `plans/central/PROGRESS.md` (may lag `git log`)
- **Heartbeat contract**: [`plans/codex-heartbeat-contract.md`](../codex-heartbeat-contract.md)
- **Agent status probe**: `plans/central/agents_status.py`

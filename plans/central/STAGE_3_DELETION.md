# Stage 3 — Global deletion pass

> **Do NOT diverge from this plan. Silent divergence is the cardinal sin. To deviate, surface the proposed divergence in a commit-message comment AND in the hand-off report; wait for main-session confirmation. Paraphrasing the contract is divergence. Deleting a symbol not listed here is divergence. Deleting in an order other than the one specified is divergence.**

> Historical-reference note (added during rename pass): the tables, grep patterns, and symbol paths below were authored before the `Seshat* → PersonalScribe*` + folder rename and are preserved verbatim for Stage 3 audit traceability. Implementers running any remaining Stage 3 chunks post-rename must translate `SeshatCore/` → `PersonalScribeCore/`, `SeshatAppKit/` → `PersonalScribeAppKit/`, `SeshatSession/` → `PersonalScribeSession/`, and `SeshatConfig` → `AppConfig` / `PersonalScribeConfig` per the locked inventory at `plans/rename/INVENTORY.md` before running the greps. Stage 3 execution for the 7 approved rows completed 2026-04-20 (see §Execution status) so this note is primarily for future audit readers.

## Execution status (2026-04-20, post-execution)

**DONE.** All 7 approved-now delete rows landed on trunk across 3 commits:
- `f0d258e` — landed L2 `SeshatConfig.modesDirectory()`, L6 `SeshatConfig.modelId` shim, L2 `SeshatConfigScaffoldingTests.swift`, L9 `BuildInfo.swift`, L9 `BuildInfoTests.swift` (commit subject says only "layer 9 delete BuildInfo + BuildInfoTests" — parallel-chunk staging race absorbed multiple chunks into one commit).
- `aed5406` — landed L3 `typealias SeshatPasteMode = PasteMode` (subject says "layer 2 delete SeshatConfigScaffoldingTests" — misattributed from same race).
- `45e94da` — landed L7 `SessionCoordinator.seconds(from:)` dead method (main-session commit after chunk 2 subagent declined a non-existent diff).

`swift build --build-tests` green post-execution.

**Post-execution L1 + L7 re-inventory** (drafts at `plans/central/drafts/stage3/layer_<1,7>_inventory.md`): **0 new approved rows**. All remaining candidates blocked on Stage 2 follow-up work (PermissionServiceAdapter cleanup, canonical coordinator move L7.S3.1.x, PostProcessor call-site migration, etc.), NOT on additional Stage 3 deletions. Stage 3 is as-complete-as-scope-allows.

**Known retrospective issues (do not re-execute):**
- Parallel chunk agents running `git commit` without `--only <path>` swept each other's staged changes → commit messages don't describe actual contents. See §Retrospective below.
- `swift build --build-tests` green confirms the *functional* state is correct even if the git history is misleading.

## Retrospective — parallel-commit race (2026-04-20)

5 chunk agents dispatched in parallel with `git add <specific-path>` instructions, but each ran `git commit` (not `git commit -o <path>`). Consequence: the commit that fired first swept every currently-staged path from sibling agents. Result:
- 5 chunk subagents → 3 actual commits, 2 with misattributed subjects, 1 subagent blocked (Chunk 3 found its targets already absorbed into f0d258e).
- Chunk 1 subagent blocked because the typealias it was about to remove wasn't in HEAD — it had been staged by another chunk's `git add` then committed by a third chunk. Main session couldn't have prevented this without a lockfile or `git commit -o`.

**Guideline updated** in `~/Projects/nitkrar/ENGINEERING_GUIDELINES.md` §"Give subagents the smallest possible unit of work": parallel chunk execution must either (a) use `git commit --only <path>` to scope commits, (b) serialize via a single-writer dispatch, or (c) use isolated worktrees for each chunk. Plain `git add <path>` + `git commit` is not enough when multiple agents stage concurrently.

## Snapshot drift callout (read before executing)

This plan is synthesized from per-layer inventory drafts at `plans/central/drafts/stage3/` that were produced across a moving-target trunk. Two sources of staleness remain to address **before execution** (down from three — L5 resolved post-initial-synthesis):

1. **Layer 1 inventory predates the `phase-2 step 1.retry` permission-fix cluster that just landed.** The L1 draft concluded zero approved rows because every plan-listed symbol still had live refs. With the fix landed, several of those `[QUESTION: Stage 2 swap incomplete]` entries likely become APPROVED. Re-inventory L1 before executing any L1 chunk; the 0 approved-rows count in §3 may grow.
2. **Layer 7 inventory predates scope-creep commit `a489d55`** (labeled "L5 fix Step 1" but actually deleted ~14 dead methods in `SessionCoordinator.swift`). Several L7 `[QUESTION]` rows may already be gone. Re-inventory L7 before executing any L7 chunk.

(Resolved: L5 inventory landed post-synthesis — `plans/central/drafts/stage3/layer_5_inventory.md` at trunk `a651090`. No new approved-now rows from L5; all candidates blocked on `PasteInjector` / `MenuBarSceneModel` Stage 2 swap completion. Rows folded into §3b below.)

**General safeguard**: every approved row carries a reproducible `Grep to prove unreferenced` column. The execution-time grep is authoritative — re-run it immediately before each chunk's commit and halt the chunk if it returns any live hits (see §7).

## 1. Methodology declaration

This plan uses the code-first methodology per `plans/central/GLOBAL_STAGE3_PROMPT.md`. Inventory from `rg`/`ls`; plans consulted only for disambiguation of *why*; when plan and tree disagree, tree wins.

Representative `rg` patterns used in per-layer drafts (full command lists in each `plans/central/drafts/stage3/layer_<N>_inventory.md` §Methodology):

- Zero-callers check: `rg -l '\b<SymbolName>\b' Sources/ Tests/`
- Key-string check: `rg -n '"Seshat<key>"' Sources Tests`
- Dead-method check: `rg -n --fixed-strings '<methodName>(' <declaring-file>` + repo-wide call-site sweep
- Reviewer-flagged-deletion sweep: `rg -l 'delete|remove' plans/central/reviews/LAYER_<N>_*`
- Stage-2 touched surviving files: `git show --name-only --format= <stage-2-commit>`

## 2. Preconditions gate (must-be-true before execution)

- [ ] Every layer's Stage 2 commit landed on trunk (currently **pending** for L1 fix-in-flight + L4 partial; L5/L7 drifted per §Snapshot drift).
- [ ] Every layer's Stage 2 code review verdict is APPROVED / APPROVED-W-NITS / APPROVED-W-FOLLOWUPS (no NEEDS REVISION / CHANGES REQUIRED). Currently **pending** for L4 (still `REQUEST CHANGES`).
- [ ] `swift test` green on trunk from the canonical repo path (NOT a worktree).
- [ ] `swift build --build-tests` green.
- [ ] No open worktrees with uncommitted changes.
- [ ] L1 inventory re-run to pick up newly-unblocked rows after the permission-fix cluster lands.
- [ ] L5 inventory landed (`plans/central/drafts/stage3/layer_5_inventory.md` exists).
- [ ] L7 inventory re-run on post-`a489d55` trunk.
- [ ] Explicit user go-ahead.

## 3. Aggregated delete inventory

### 3a. APPROVED-NOW delete rows (execute in the order specified in §4–§5)

| Layer | Kind | Name | Path | Source of truth | Why safe to delete | Grep to prove unreferenced | Depends on |
|-------|------|------|------|-----------------|---------------------|----------------------------|-----------|
| 2 | dead-method | `SeshatConfig.modesDirectory()` | `Sources/SeshatCore/Config.swift:52` | hybrid-confirmed | No `Sources/` or `Tests/` call sites remain; `ManagedDirectory.modes` + `StorageLocator.url(for: .modes)` is the surviving root API | `rg -l 'SeshatConfig\.modesDirectory\(' Sources Tests` → must be empty | none |
| 6 | file | `SeshatConfig.modelId` shim | `Sources/SeshatCore/Config.swift:7` | hybrid-confirmed | L6 Stage 3.1 calls the fixed-default Config shim legacy; exact qualified-symbol grep returned 0 hits | `rg -l '\bSeshatConfig\.modelId\b' Sources Tests` → must be empty | none |
| 3 | type | `typealias SeshatPasteMode = PasteMode` | `Sources/SeshatCore/SeshatPasteMode.swift:28` | hybrid-confirmed (L3 plan §Stage-3.10 + L3 S2 review Resolver-Migration-Checklist) | Transitional forwarding alias left behind by Stage 2 `5b6e023`. Zero consumers outside its own declaration line | `rg '\bSeshatPasteMode\b' Sources Tests` → only the declaration | none |
| 7 | dead-method | `SessionCoordinator.seconds(from:)` | `Sources/SeshatSession/SessionCoordinator.swift:270` | grep-only | Declaration present, no call sites — fixed-string scan: 1 decl hit, 0 call hits | `rg -n --fixed-strings 'Self.seconds(from' Sources/SeshatSession/SessionCoordinator.swift` → must be empty | none |
| 2 | test | `SeshatConfigScaffoldingTests` | `Tests/SeshatCoreTests/SeshatConfigScaffoldingTests.swift` | hybrid-confirmed | File only asserts `_ = SeshatConfig.self`; no runtime or regression coverage for surviving storage behavior | `rg -l '\bSeshatConfigScaffoldingTests\b' Sources Tests` → only the file itself | none |
| 9 | type | `BuildInfo` | `Sources/SeshatAppKit/MenuBar/BuildInfo.swift:4` | hybrid-confirmed | `AppBrand.version` / `AppBrand.buildNumber` now own live brand metadata; exclusion-glob grep returned 0 hits | `rg -n --glob '!Sources/SeshatAppKit/MenuBar/BuildInfo.swift' --glob '!Tests/SeshatAppKitTests/BuildInfoTests.swift' '\bBuildInfo\b' Sources/ Tests/` → must be empty | none |
| 9 | test | `BuildInfoTests` | `Tests/SeshatAppKitTests/BuildInfoTests.swift:4` | hybrid-confirmed | Only test consumer of `BuildInfo` / `SeshatGitSHA`; legacy bridge test after `BuildInfo` removal | `rg -n --glob '!Tests/SeshatAppKitTests/BuildInfoTests.swift' 'BuildInfo\|SeshatGitSHA' Tests/` → must be empty | `BuildInfo` |

**Row count**: 7 approved-now rows across layers L2, L3, L6, L7, L9.

### 3b. BLOCKED-ON-PRECURSOR rows (do NOT execute in this pass)

These rows exist in the per-layer inventories but are blocked by surviving consumers. Listed here for traceability; they become candidates only after their precursors land.

| Layer | Kind | Name | Blocker (must-resolve first) |
|-------|------|------|-----------------------------|
| 1 | multiple | (all L1 rows) | L1 Stage 2 swap incomplete on snapshot — re-inventory after fix cluster lands |
| 4 | test | `PillOverlayViewModelTests` | `PillOverlayViewModel.apply(sessionState:preparationProgress:)` still called from `PillOverlayView`, presenter tests |
| 4 | type | `LegacyPasteInjectorOutputService` (L4 citation) | Legacy `MenuBarSceneModel(coordinator:permissionRequester:...)` convenience init still used |
| 5 | type | `PasteInjector` | `ClipboardBatchOutput` still uses `PasteInjector.RestoreScheduler`/`PasteShortcutPoster`/`postPasteShortcut` |
| 5 | file | `Sources/SeshatAppKit/Paste/PasteInjector.swift` | Owns `PasteInjecting`, `PasteRoutingDecision`, `FrontmostAppProviding`, `WorkspaceFrontmostAppProvider`; `ClipboardBatchOutput` imports helper types |
| 5 | protocol | `PasteInjecting` | Still referenced by `PasteInjector.swift`, `MenuBarSceneModel.swift`, `SeshatAppMain.swift` |
| 5 | type | `PasteRoutingDecision` | Still referenced by `PasteInjector.swift`, `MenuBarSceneModel.swift`, `MenuBarSceneModelTests` |
| 5 | type | `LegacyPasteInjectorOutputService` (L5 citation) | Private shim still instantiated by `MenuBarSceneModel`; keeps legacy result-mapping path alive |
| 5 | dead-method | `MenuBarSceneModel.autoPasteTranscriptIfNeeded(_:)` | `applySnapshot(_:)` still calls this on idle transitions; `lastAutoPastedTranscript` deduplicates |
| 5 | seam | `SeshatAppMain` unused `pasteInjector` parameter | Convenience init still accepts the legacy closure seam |
| 5 | test | `MenuBarSceneModel` idle-transition `pasteInjector` tests | Legacy seam tests still inject `pasteInjector` |
| 5 | test | `PasteInjectorTests` | Blocked on `PasteInjector.swift` whole-file delete |
| 6 | file | `AppConfig.modelId` shim | `AppConfigTests` assertion |
| 6 | file | `FluidAudioTranscriber.activeModelId` shim | `FluidAudioTranscriberCompileTests` |
| 6 | type | `ModelRegistry` | `BuiltInModelCatalog` still aliases `ModelRegistry.parakeetTDT06Bv2`; AppKit UI/menu swaps not landed |
| 6 | file | `ModeDescriptor` raw `voiceModelID`/`aiModelID` path | Cross-layer consumers (AppStore, Pipeline, DefaultModelService, ModesTab) |
| 6 | file | `FluidAudioInferenceClient.swift`, `FluidAudioModelDownloader.swift`, `FluidAudioTranscriber.swift` | `ModelAwareFluidAudioTranscriber` still reuses these helpers |
| 6 | test | `ModelRegistryTests`, `ModeDescriptorTests`, `FluidAudioTranscriberCompileTests`, `ManualTranscriptionVerification.md` | Production symbols still live |
| 7 | type | `CoordinatorPipelineCapture`, `CoordinatorPipelineTranscriber`, `CoordinatorPipelineOutputSink`, `CoordinatorPipelineContextProvider`, `SessionDownloadProgressBroadcaster`, `CoordinatorPostProcessingPipeline` | All still instantiated by `SessionCoordinator.makePipeline`; L7.S3.1 canonical coordinator move must land first |
| 7 | file | `PostProcessor.swift` | Still used by `SessionCoordinator` via `CoordinatorPostProcessingPipeline` bridge |
| 7 | test | `PostProcessorTests` | Blocked on `PostProcessor.swift` |
| cross | (inherited from L1 review) | `SeshatAppMain.makeCompatibilityPermissionService` | Live in 7+ source files; resolve after Layer 1 shell/test swaps land |

### 3c. Questions / drift flags (unchanged from per-layer drafts — surface here for reviewer)

- Per-layer drafts (`plans/central/drafts/stage3/layer_<N>_inventory.md` §Questions) record a further ~20 plan-vs-tree drift items. Key ones:
  - L2 plan §173 lists `BaseDirectoryMigrator.managedSubdirectories` as Stage 3 target — already absent from trunk; plan stale.
  - L5 plan/reviews cite `SilentPaster`, `OutputService.copy`, `CopyOutputService`, `PasteOutput`, `NotificationOutput` as Stage 3 targets — all already absent from trunk (cleanup landed pre-inventory, partly via `1ac9f98`); plan stale.
  - L5 plan says `SeshatAppMain` still constructs `PasteInjector()` / calls `pasteInjector.paste(text)` — already removed; only an unused `pasteInjector:` parameter + `_ = pasteInjector` remains.
  - L6 plan names `AppComposition.swift` / `FluidAudioInferenceClient.swift` as fixed-default cleanup targets — both already Stage-2-swapped on trunk; plan stale.
  - L9 plan `[QUESTION-BRAND-1]` about optional `BuildInfo` delete — resolved in favor of delete by §3a row.
  - L1/L2 `BaseDirectoryPath` cross-layer ownership split (Config.swift + AppConfig.swift both own it) — Minor from L3 S2 review; not in §3a because fix direction is ambiguous; cross-layer decision needed.

## 4. Ordering strategy

Leaves-first, grouped by **file** to minimize touching the same file in multiple commits. Approved rows cluster onto 5 files:

- `Sources/SeshatCore/Config.swift` — 2 approved rows (L2 `modesDirectory`, L6 `modelId` shim)
- `Sources/SeshatCore/SeshatPasteMode.swift` — 1 approved row (L3 typealias)
- `Sources/SeshatSession/SessionCoordinator.swift` — 1 approved row (L7 dead method)
- `Tests/SeshatCoreTests/SeshatConfigScaffoldingTests.swift` — 1 approved row (L2 test file)
- `Sources/SeshatAppKit/MenuBar/BuildInfo.swift` + `Tests/SeshatAppKitTests/BuildInfoTests.swift` — 2 approved rows (L9, paired leaf)

No circular dependencies. No cross-layer delete-time dependencies. Execution order below is chosen to minimize reviewer cognitive load per chunk (tiny ones first) and to pair file-coupled rows.

## 5. Chunks + verification gates

Five chunks. Each chunk = one commit. Between chunks: `swift build --build-tests` must pass; relevant test target must pass; full `swift test` after the final chunk of the batch.

### Chunk 1 — L3 typealias (1 LoC)

- Delete `Sources/SeshatCore/SeshatPasteMode.swift:28` (`public typealias SeshatPasteMode = PasteMode`).
- **Verify before commit**: `rg '\bSeshatPasteMode\b' Sources Tests` returns only the file header/doc comment (not the line-28 declaration).
- **Verify after commit**: `swift build --build-tests` green; `swift test --filter PasteMode` green.

### Chunk 2 — L7 dead method (1 LoC body + signature)

- Delete `Sources/SeshatSession/SessionCoordinator.swift:270` `private static func seconds(from duration: Duration)` and its 6-line body.
- **Verify before commit**: `rg -n --fixed-strings 'Self.seconds(from' Sources/SeshatSession/SessionCoordinator.swift` returns 0 hits.
- **Verify after commit**: `swift build --build-tests` green; `swift test --filter SessionCoordinator` green.

### Chunk 3 — Config.swift cleanup (L2 + L6 paired)

- Delete `SeshatConfig.modesDirectory()` at `Sources/SeshatCore/Config.swift:52` (function body).
- Delete `SeshatConfig.modelId` shim at `Sources/SeshatCore/Config.swift:7` (field / accessor).
- **Verify before commit**: `rg -l 'SeshatConfig\.modesDirectory\(' Sources Tests` empty; `rg -l '\bSeshatConfig\.modelId\b' Sources Tests` empty.
- **Verify after commit**: `swift build --build-tests` green; `swift test --filter SeshatConfig` + `--filter Config` green.

### Chunk 4 — L2 scaffolding test removal

- Delete `Tests/SeshatCoreTests/SeshatConfigScaffoldingTests.swift` entirely.
- **Verify before commit**: `rg -l '\bSeshatConfigScaffoldingTests\b' Sources Tests` returns only the file itself.
- **Verify after commit**: `swift build --build-tests` green; full `SeshatCoreTests` target green.

### Chunk 5 — L9 BuildInfo pair (final chunk of this batch)

- Delete `Sources/SeshatAppKit/MenuBar/BuildInfo.swift` and `Tests/SeshatAppKitTests/BuildInfoTests.swift` entirely.
- **Verify before commit**:
  - `rg -n --glob '!Sources/SeshatAppKit/MenuBar/BuildInfo.swift' --glob '!Tests/SeshatAppKitTests/BuildInfoTests.swift' '\bBuildInfo\b' Sources/ Tests/` empty.
  - `rg -n --glob '!Tests/SeshatAppKitTests/BuildInfoTests.swift' 'SeshatGitSHA' Tests/` empty.
- **Verify after commit**: `swift build --build-tests` green; full `swift test` green from canonical repo path.

### Cumulative LoC

Rough estimate: chunks 1–5 delete ~200 LoC total (chunks 1–3 are tiny; chunks 4–5 remove a scaffolding file and a bridge type respectively).

## 6. Commit convention

Subject format: `trunk: stage 3 — <layer-or-cross-layer-scope> delete <one-line summary>`.

Body:
- Bulleted list of files/symbols removed.
- Exact `rg` patterns confirmed to return 0 hits on `Sources/` + `Tests/`.
- Any `Package.swift` notes if a product/target definition references the deleted file.

Example subjects:
- `trunk: stage 3 — layer 3 delete SeshatPasteMode typealias`
- `trunk: stage 3 — layer 7 delete SessionCoordinator.seconds(from:) dead method`
- `trunk: stage 3 — layers 2+6 delete SeshatConfig.{modesDirectory, modelId} shims`
- `trunk: stage 3 — layer 2 delete SeshatConfigScaffoldingTests`
- `trunk: stage 3 — layer 9 delete BuildInfo + BuildInfoTests`

**Forbidden**: `git commit --no-verify` (skip hooks). Fix the hook issue; never bypass.

## 7. Failure-handling playbook

- **Reference discovered mid-chunk** (grep returned empty at plan time but now finds a live hit): halt chunk, do NOT commit. Surface the still-referenced symbol + call site. Decide: (a) finish the Stage 2 swap in a fix-forward commit, or (b) exclude the symbol with a `[QUESTION]` comment and drop it from this execution pass. Never delete and let the build break.
- **Test breaks after commit**: if the test exercised deleted behavior, delete the test in the same commit series (it's part of Stage 3 scope). If the test exercises surviving behavior through a deleted helper, rewrite against the new layer in the same commit. Do not silently disable.
- **Cross-layer surprise** (e.g., Layer 5 delete blocked by a new reference in Layer 7 code): treat as Stage 2 regression; fix forward on the other layer before proceeding with the chunk.
- **Build fails but no grep miss visible**: check `Package.swift` — the deleted file may have been a product/target member. Update the manifest in the same commit.

## 8. Rename-pass decoupling

*Do not rename modules, types, files, bundle IDs, UserDefaults keys, or brand strings during Stage 3. Those changes belong to the post-Stage-3 rename pass (staged per `project_ninimma_rename` memory).*

Reviewers MUST flag any chunk that crosses this line. The `PersonalScribe`-prefix type rename plan lives at `plans/rename/PLAN.md` (which supersedes the drifted `plans/PHASE_0_rename.md`) and executes **after** Stage 3 (or before, if the order flip is approved — see session notes).

## Hand-off report

- **Synthesis commit**: this file + `INDEX.md` in one commit (subject: `trunk: plans/central — INDEX + global Stage 3 deletion plan`).
- **Methodology**: code-first, inventory built via per-layer codex agents (L5 + L3 re-runs; L3 ultimately done in main session).
- **Total deletion count**: 7 approved-now rows: 2 types (incl. 1 typealias), 1 file-contents (shim accessor), 2 tests (incl. 1 file delete), 2 dead methods.
- **Number of chunks**: 5; cumulative LoC deleted ~200.
- **Cross-layer ordering surprises**: none among approved rows. Questions surfaced in §3c for L1/L2 `BaseDirectoryPath` duplicate ownership.
- **Per-layer Stage 3 plan vs grep discrepancies**: recorded per-layer draft §Questions. Notable: L2 `managedSubdirectories` already gone; L6 `AppComposition.swift` / `FluidAudioInferenceClient.swift` already Stage-2-swapped; L9 `BuildInfo` optional-delete resolved to delete; L4 stale `PillOverlayController` convenience-init text.
- **Confidence**: **NEEDS REVIEW** until L1 + L7 drift is cleared per §Snapshot drift callout (L5 resolved post-synthesis; no new approved-now rows added).
- **Confirmation**:
  - `No deletions executed — plan only.`
  - `No swift build or swift test invoked during synthesis.`
  - `No CENTRAL_LAYERS_PROMPT.md modifications.`
  - `No LAYER_*.md modifications.`

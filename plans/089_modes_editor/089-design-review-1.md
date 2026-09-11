# #089 design review 1 — codex

Codex's sandbox blocked the original file write; report contents fetched via `/codex:result task-moj5msek-bbbzzh` and recorded here verbatim. Codex session: `019dd60d-b7e4-7a83-8b21-6cf38134e364`.

## Summary
Strongest problem: the plan edits per-mode output sinks, but live transcript delivery still ignores them and reads global prefs, so Auto-paste/Restore clipboard would ship as placebo after GeneralTab cleanup. Next: L-7 validity gating is not backed by real model availability. Third: the `activeMode` split audit is under-scoped and `currentMode` concurrency is still mushy.

## Objections (ranked, strongest first)

### 1. Per-mode output settings are placebo
**Severity**: critical
**Where**: L-16 / IMPLEMENTATION Step 6; `Sources/PersonalScribeAppKit/MenuBar/MenuBarSceneModel.swift:142-152`, `Sources/PersonalScribeAppKit/Output/ClipboardBatchOutput.swift:76-105`, `Sources/PersonalScribeSession/SessionCoordinator.swift:557-560`
**Issue**: The plan moves Auto-paste / Restore clipboard into modes, then deletes the only live global controls. But the runtime output path still ignores `BoundRecipe.outputSinks`: `MenuBarSceneModel` always calls `outputService.deliverBatch(text:)`, `ClipboardBatchOutput` reads `AutoPasteEnabledPreference` and `ClipboardRestoreEnabledPreference` from `UserDefaults`, and the coordinator pipeline output sink is a no-op. The new per-mode toggles would be placebo.
**Suggested fix**: Either keep the global controls for #089 or add the missing runtime routing from current mode / bound recipe into final transcript delivery before deleting GeneralTab.

### 2. L-7 validity gating is not backed by backend truth
**Severity**: major
**Where**: DESIGN "Validity surface"; `Sources/PersonalScribeAppKit/Composition/AppComposition.swift:81-100`, `Sources/PersonalScribeAppKit/Composition/AppComposition.swift:128-138`, `Sources/PersonalScribeCore/WorkflowMode/WorkflowModeValidator.swift:17-20`, `Sources/PersonalScribeSession/Models/Selection/ActiveModelService.swift:242-247`
**Issue**: `WorkflowModeValidator` only enforces the `availableKinds` set it receives. Production currently passes "all enabled kinds," not downloaded/active truth. `removeDownloaded` also leaves the active descriptor selected. So rows can say invalid while `setDefault` and session-start validation still pass, then fail later in recipe build or prep. That violates L-7's promised activation gate.
**Suggested fix**: Define one real availability source and use it consistently in row validity, `setDefault`, and session-start validation. `downloadStates` alone is not enough unless backend validation uses the same rule.

### 3. The rename/split audit is under-scoped
**Severity**: major
**Where**: IMPLEMENTATION Step 2; `Sources/PersonalScribeCore/AppStore/AppStore.swift:60-63`, `Sources/PersonalScribeCore/AppStore/AppStore.swift:101-107`, `Sources/PersonalScribeAppKit/UnifiedWindow/Tabs/ModesTabViewModel.swift:23-40`
**Issue**: Step 2's concrete source-callsite list is incomplete. Live consumers still read `registry.activeMode` / `activeModeStream()` in AppStore and the old Modes tab VM. The grep note helps, but the plan body itself under-specs the compile-critical rename surface; follow the enumerated list literally and this does not compile cleanly.
**Suggested fix**: Promote the full source-callsite inventory into the plan instead of relying on a late grep sweep.

### 4. `currentMode` concurrency is not designed, only named
**Severity**: major
**Where**: DESIGN "Domain layer"; `Sources/PersonalScribeCore/WorkflowMode/WorkflowModeRegistry.swift:21-24`, `Sources/PersonalScribeCore/WorkflowMode/WorkflowModeRegistry.swift:60-63`, `Sources/PersonalScribeSession/SessionCoordinator.swift:316-323`, `Sources/PersonalScribeSession/SessionCoordinator.swift:385-391`
**Issue**: Today registry state is serialized under one lock. The plan adds mutable runtime-only `currentMode`, says `setCurrent(id:)` is in-memory only, and also says `currentMode` is `@MainActor`. Session-start validation is still a synchronous non-main path. If `setCurrent` is unlocked you get stale/delete races; if it is `@MainActor`, the current API surface no longer matches.
**Suggested fix**: Pick one model and state it plainly: either keep `currentMode` under the existing lock, or actor-isolate the registry and update every non-main callsite.

## No-objection items
- `1` No objection — empty Modes tab is consistent with L-1/L-2, and the plan explicitly compensates for the empty menu case; current `StatusItemMenuModel` simply omits the submenu when `modes.isEmpty` (`Sources/PersonalScribeAppKit/MenuBar/StatusItemMenuModel.swift:255-274`).
- `6` No objection — AppKit already depends on Core (`Sources/PersonalScribeAppKit/UnifiedWindow/Tabs/ModesTab.swift:1-3`, `Sources/PersonalScribeAppKit/Settings/GeneralTab.swift:1-4`), so `Preset` calling `WorkflowMode.dictation` does not create a reverse dependency.
- `7` No objection — current registry writes already serialize under one `NSLock` (`Sources/PersonalScribeCore/WorkflowMode/WorkflowModeRegistry.swift:21-24`, `Sources/PersonalScribeCore/WorkflowMode/WorkflowModeRegistry.swift:87-99`, `Sources/PersonalScribeCore/WorkflowMode/WorkflowModeRegistry.swift:209-217`).
- `9` No objection — live non-test caller of `mutateActiveOrFork` is `Sources/PersonalScribeAppKit/Settings/GeneralTab.swift:831`; the rest of the hits are tests or registry internals.
- `10` No objection — first-launch fallback is real: missing/stale persisted selection resolves to `.dictation` (`Sources/PersonalScribeCore/WorkflowMode/WorkflowModeRegistry.swift:222-227`), and session start builds from the registry (`Sources/PersonalScribeSession/SessionCoordinator.swift:316-323`, `Sources/PersonalScribeSession/SessionCoordinator.swift:385-391`).

## Plan-vs-code drift
- `DESIGN.md:130` / `IMPLEMENTATION.md:38,135` use `Sources/PersonalScribeSession/Coordinator/SessionCoordinator.swift`; current file is `Sources/PersonalScribeSession/SessionCoordinator.swift:6`.
- `DESIGN.md:129` / `IMPLEMENTATION.md:37` say `SessionPipelineOrchestrator` owns the `validateActiveForSessionStart` callsite; current callsite is `Sources/PersonalScribeSession/SessionCoordinator.swift:322`.
- `IMPLEMENTATION.md:95` targets `Tests/PersonalScribeCoreTests/WorkflowMode/WorkflowModeRegistryTests.swift`; current file is `Tests/PersonalScribeSessionTests/WorkflowMode/WorkflowModeRegistryTests.swift:5`.
- `IMPLEMENTATION.md:143` uses placeholder `Tests/PersonalScribeAppKitTests/Settings/<removed-toggle-tests>.swift`; current toggle-bridge coverage sits in `Tests/PersonalScribeAppKitTests/Settings/GeneralTabViewModelRecipeBridgeTests.swift:12`.

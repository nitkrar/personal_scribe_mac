# #089 IMPLEMENTATION review 1 — codex

## Summary
Two compile blockers remain unresolved in the build sequence: Stage C.4 creates a `Core -> Session` target cycle, and Stage C.3/C.6’s `currentBoundRecipe()` plumbing does not compile as written. The rename audit is also incomplete: live `setActive(id:)` survivors are missing from both B.2 and the final grep gate.

## Objections (ranked, strongest first)

### 1. Stage C.4 is not executable as written
**Severity**: critical  
**Where**: `IMPLEMENTATION.md:215-247`; `Sources/PersonalScribeCore/Output/OutputService.swift:1-3`; `Package.swift:52-57,84-92`; `Tests/PersonalScribeCoreTests/Output/OutputContractsTests.swift:40-61`; `Tests/PersonalScribeAppKitTests/Fakes/OutputServiceDoubles.swift:4-27`  
**Issue**: `PersonalScribeSession` already depends on `PersonalScribeCore`, so C.4’s “add `import PersonalScribeSession` to Core” creates a package cycle. Even after relocating `BoundOutputSink`, the stage omits the compile fallout in the Core contract test, AppKit output doubles, and every `deliverBatch(text:)` test callsite.  
**Suggested fix**: Decide the API home before implementation, then enumerate every `deliverBatch` caller/double/test in the same stage.

### 2. `currentBoundRecipe()` does not plumb through as written
**Severity**: critical  
**Where**: `IMPLEMENTATION.md:202-254`; `Sources/PersonalScribeSession/Pipeline/Orchestrator/SessionPipelineOrchestrator.swift:5,16-21`; `Sources/PersonalScribeSession/SessionCoordinator.swift:6,20`; `Sources/PersonalScribeAppKit/MenuBar/MenuBarSceneModel.swift:13,151-152`  
**Issue**: `SessionCoordinator` owns `pipeline`, not `orchestrator`, and both types are actors. C.3’s synchronous `orchestrator.currentBoundRecipe()` accessor needs a cross-actor `await`, so C.3/C.6 do not compile verbatim. Also, current code never clears `boundRecipe`, so “nil between sessions” is not defined by the existing lifecycle.  
**Suggested fix**: Make the coordinator accessor `async`, call the actual `pipeline`, and explicitly lock the bound-recipe lifetime semantics.

### 3. The rename audit misses live `setActive` survivors, and the grep gate won’t catch them
**Severity**: major  
**Where**: `IMPLEMENTATION.md:180-193,362-366`; `Sources/PersonalScribeAppKit/Composition/PersonalScribeAppMain.swift:204,271`; `Tests/PersonalScribeCoreTests/AppStore/AppStoreTests.swift:132`; `Tests/PersonalScribeSessionTests/WorkflowMode/WorkflowModeStoreTests.swift:104`; `Tests/PersonalScribeSessionTests/WorkflowMode/WorkflowModeRegistryTests.swift:30,44,72,128,140,165`  
**Issue**: B.2 says “10 callsites” but misses load-bearing `setActive(id:)` uses in app composition and non-deleted tests. I.2.5 greps `activeMode*` and `mutateActiveOrFork`, but not `setActive(id:)`, so the promised pre-commit audit would miss these survivors.  
**Suggested fix**: Expand both the evidence table and grep gate to include `setActive(id:)` / `setCurrent(id:)` and all non-deleted tests.

## Verified claims
- ✓ `boundRecipe` is a stored property on the orchestrator today: `Sources/PersonalScribeSession/Pipeline/Orchestrator/SessionPipelineOrchestrator.swift:16-21`.
- ✓ `MenuBarSceneModel` already injects `SessionCoordinator`: `Sources/PersonalScribeAppKit/MenuBar/MenuBarSceneModel.swift:13,29-33`.
- ✓ `SessionCoordinator` already holds the orchestrator via `private let pipeline`: `Sources/PersonalScribeSession/SessionCoordinator.swift:20`.
- ✓ All three GeneralTab setters funnel into the single `mutateActiveOrFork` bridge: `Sources/PersonalScribeAppKit/Settings/GeneralTab.swift:723-831`.
- ✗ “`currentBoundRecipe()` is nil between sessions” is not backed by current code; I found `bindRecipeForNextSession` setting `boundRecipe` at `SessionPipelineOrchestrator.swift:138-139`, but no corresponding clear.
- ✗ I.1’s manual-runbook path is stale; runbooks now live under `Tests/ManualVerifications/` per `Package.swift:115-118`.

## Build-sequence drift
- H.1 expects stale-`defaultModeID` auto-clear + `store.save`, but B.1’s `resolveDefaultLocked()` sketch only falls back to `.dictation`; no write path is specified: `IMPLEMENTATION.md:108-145,334-335`.
- F.5/F.7 depend on registry streams for create/edit UI updates, but B.1 only names `broadcastCustomModes()` on reorder/delete; it does not say `saveCustom(_:)` broadcasts after create/edit. Current `saveCustom` is silent: `Sources/PersonalScribeCore/WorkflowMode/WorkflowModeRegistry.swift:102-121`.
- C.4/C.5 omit the direct `deliverBatch(text:)` fallout in `ClipboardBatchOutputTests.swift:69-545`.

## Missing test coverage
- `C.2` VAD enabled gate: worth adding. Existing VAD suites already exercise this seam (`Tests/PersonalScribeSessionTests/Pipeline/VadOrchestratorIntegrationTests.swift:319-353`).
- `C.5` “no `.clipboard` sink means no clipboard write”: worth adding. Current AppKit tests pin the opposite always-write behavior (`Tests/PersonalScribeAppKitTests/Output/ClipboardBatchOutputTests.swift:467-492`).
- `D.1`/`D.2` collision detection and `D.3` hotkey fire -> `setCurrent` + recording: worth adding. `HotkeyRecorderTests.swift` and `GlobalHotkeyMonitorTests.swift` already provide seams.
- Manual scope is missing explicit diarization-toggle and successful Realtime-toggle checks; `MV-MODES-6` only covers the streaming-warning path: `IMPLEMENTATION.md:351-355`.

## No-objection items
- No objection — the A.1 -> A.4 -> A.6 -> A.7 -> C.1 -> C.2 seam is ordered coherently for an end-only compile.
- No objection — Stage E’s simplification is real; all three cited setters route through the single helper at `GeneralTab.swift:723-831`.

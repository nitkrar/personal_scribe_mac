# #089 CHECKLIST review 1 — codex

## Summary
Built-in fallback VAD is not actually specified: the checklist removes the only shape-mutation path, but VAD enablement is `.vad` presence, not a parameter. Also, L-24 weakens session immutability by allowing delivery to read the current recipe instead of the session-bound recipe.

## Objections (ranked, strongest first)

### 1. Built-in fallback VAD has no wiring
**Severity**: critical
**Where**: L-1, L-18, L-29
**Issue**: `WorkflowMode.dictation` has no `.vad` (`Sources/PersonalScribeCore/WorkflowMode/WorkflowMode.swift:60-72`). Today GeneralTab enables VAD by inserting/removing `.vad` (`Sources/PersonalScribeAppKit/Settings/GeneralTab.swift:786-815`), and the orchestrator only wires VAD when the bound recipe contains that controller (`Sources/PersonalScribeSession/Pipeline/Orchestrator/SessionPipelineOrchestrator.swift:798-805,842-865`; `Sources/PersonalScribeCore/WorkflowMode/CaptureControllerSpec.swift:17-22`). With built-in fallback never editable and `mutateActiveOrFork` gone, the GeneralTab VAD toggle loses its built-in path.
**Suggested fix**: Lock how built-in fallback gains/loses `.vad`, or keep the existing bridge for that setting.

### 2. L-24 allows the wrong recipe to drive final delivery
**Severity**: major
**Where**: L-24, L-25
**Issue**: The pipeline freezes one `boundRecipe` per session (`Sources/PersonalScribeSession/Pipeline/Orchestrator/SessionPipelineOrchestrator.swift:16-21,138-142`), and `SessionCoordinator` reads the mode once at start (`Sources/PersonalScribeSession/SessionCoordinator.swift:355-392`). L-24 says delivery may read the session pipeline *or* the registry-resolved current recipe. If current mode changes during transcription, that fallback can apply the wrong paste/restore settings to the finished session.
**Suggested fix**: Lock final delivery to the session’s bound recipe; only fall back when no session recipe exists.

### 3. Output-setting default keys are missing from the locked contract
**Severity**: major
**Where**: L-4, L-26
**Issue**: L-4/L-26 rely on `.setting(.autoPasteEnabled)` and `.setting(.clipboardRestoreDelay)`, but `PreferenceKeys` currently exposes only `vad*` and `clipboardRestoreEnabled` (`Sources/PersonalScribeCore/Preferences/PreferenceKeys.swift:16-43`). The checklist never locks those new `SettingKey`s, so the contract is incomplete and the implementation does not compile as written.
**Suggested fix**: Explicitly lock the required `PreferenceKeys` additions and their raw keys/defaults.

## Verified claims
- ✓ `Parameter.swift`: `.setting/.override` exists; eager cascade is real (`Sources/PersonalScribeCore/WorkflowMode/Parameter.swift:14-18,37-39`). `.setting` decode is strict via `settingDefault` (`:60-86`).
- ✓ `OutputSinkSpec.swift`: `.clipboard(restoreEnabled: Parameter<Bool>)` exists; `.frontmostPaste` is parameterless (`Sources/PersonalScribeCore/WorkflowMode/OutputSinkSpec.swift:19-22,35-49`).
- ✓ `RecipeBuilder.swift`: output sinks build through `buildOutputSink`; clipboard resolves via `ParameterResolver` (`Sources/PersonalScribeSession/WorkflowMode/RecipeBuilder.swift:39,89-99`).
- ✓ `BoundRecipe.swift`: `BoundOutputSink.clipboard(restoreEnabled: Bool)` exists (`Sources/PersonalScribeSession/WorkflowMode/BoundRecipe.swift:62-65`).
- ✓ `ClipboardBatchOutput.swift`: delivery reads defaults directly (`Sources/PersonalScribeAppKit/Output/ClipboardBatchOutput.swift:71-79`).
- ✓ `AppStore.swift`: cited hits exist at `63,104-106,170-172,256`; inventory misses extra rename fallout in `Sources/PersonalScribeCore/WorkflowMode/WorkflowModeDocument.swift:13-27`, `Tests/PersonalScribeSessionTests/WorkflowMode/WorkflowModeRegistryTests.swift:14-34`, and `Tests/PersonalScribeAppKitTests/UnifiedWindow/Tabs/ModesTabViewModelTests.swift:43-56`.

## Locks-to-feature audit
Covered: drag-reorder L-13, `+` preset popover L-14, autosave L-17, validity chip L-9, hotkey collision L-23.
Orphan/missing: built-in fallback VAD enablement has no lock; the output-setting `PreferenceKeys` additions are implicit, not locked.

## No-objection items
- No objection — L-8’s “active + ready” direction matches runtime binding, which resolves only the active descriptor for each `ModelKind` (`Sources/PersonalScribeSession/WorkflowMode/RecipeBuilder.swift:102-107`).
- No objection — `mutateActiveOrFork` has one live production caller, `Sources/PersonalScribeAppKit/Settings/GeneralTab.swift:831`; the other hits are registry internals/tests.
- No objection — system-level shortcut protection already exists for recorder reuse (`Sources/PersonalScribeAppKit/Settings/SystemHotkeyRegistry.swift:101-118,141-165`; `Sources/PersonalScribeAppKit/Settings/HotkeyRecorder.swift:21-23,225-237,258-260`).

# Verdict

REQUEST-CHANGES — the `.idle` consumer swap itself is correct, but this slice leaves the app-entry/test seam on a dead `PasteInjecting` path and adds a compatibility shim that can still misreport clipboard-only fallback as a successful paste.

# Scope reviewed

- Commit reviewed: `2d560dc89132d2fcccc122403530afe328958e65` (`trunk: step output.2 — Layer 5 Stage 2 consumer swap (auto-paste → OutputService.deliverBatch)`)
- Files touched by the reviewed commit:
  - `Sources/SeshatAppKit/Composition/SeshatAppMain.swift`
  - `Sources/SeshatAppKit/MenuBar/MenuBarSceneModel.swift`
- Plan of record reviewed: `plans/central/LAYER_5_output.md` as cleaned by `1ac9f98` (`trunk: plans/central — Layer 5 plan-doc cleanup (remove stale OutputService.copy / CopyOutputService references)`)

# Findings

## Blocker

None.

## Major

- `Sources/SeshatAppKit/Composition/SeshatAppMain.swift:40-60,84-88`; `Tests/SeshatAppKitTests/AppEntryPointTests.swift:17-25`; `Tests/SeshatAppKitTests/MenuBarFlowIntegrationTests.swift:116-124`; `plans/central/LAYER_5_output.md:308-311`
  Observation: `SeshatAppMain` still accepts the legacy `pasteInjector` seam, but the reviewed change now constructs `ClipboardBatchOutput()` unconditionally at `:60` and injects it into `MenuBarSceneModel` at `:84-88`; there is no `outputService` parameter to replace the dead seam. The integration tests still instantiate `SeshatAppMain` with `pasteInjector: SilentPaster()`. That conflicts with the current plan text: "Integration tests: update `Tests/SeshatAppKitTests/MenuBarFlowIntegrationTests.swift:17-50,104-140` and `Tests/SeshatAppKitTests/AppEntryPointTests.swift:9-31` so the live composition path uses the new output service." and "Fakes for the new protocols: add `RecordingOutputService` and `FailingOutputService` test doubles that return `OutputResult`".
  Why it matters: Observed fact: the app-entry path is no longer injectable through the new Layer 5 protocol even though Stage 2 is supposed to move callers onto that seam. Hypothesis: any future app-entry test that exercises auto-paste will be unable to stub delivery and may hit live clipboard / AX behavior instead of a recording fake.
  Suggested fix: Add `outputService: (any OutputService)? = nil` to `SeshatAppMain.init`, default it to a `ClipboardBatchOutput` built from injectable dependencies, and migrate the app-entry / integration tests to `RecordingOutputService` or `FailingOutputService`; then remove the now-dead `pasteInjector` parameter in the planned delete step.

## Minor

- `Sources/SeshatAppKit/MenuBar/MenuBarSceneModel.swift:7-27`; `Sources/SeshatAppKit/Paste/PasteInjector.swift:211-230`; `plans/central/LAYER_5_output.md:7-9`
  Observation: the new private `LegacyPasteInjectorOutputService` maps every legacy `.pasteAtCursor` result to `.delivered(target: .frontmostApp, delivery: .paste)`. `PasteInjector` still returns `.pasteAtCursor` when the pasteboard write fails, when Accessibility is missing, and when synthetic `Cmd+V` cannot be posted, even though those paths are clipboard-only or no-op. The plan explicitly calls that out as a problem to eliminate: "`PasteInjector.paste(_:)` returns `.pasteAtCursor` even when Accessibility is missing and the text only lands on the clipboard ... Layer 5 is the cleanup boundary for that."
  Why it matters: Observed fact: any compatibility caller that comes through this shim can still receive a false "paste succeeded" `OutputResult` on failure / clipboard-only fallback paths, so the shimmed path does not provide the stronger Layer 5 outcome semantics.
  Suggested fix: Prefer injecting a real `OutputService` on any path that cares about `OutputResult`, or fence this shim to narrowly-scoped compatibility tests and do not rely on its return value for user-visible behavior.

## Nit

None.

# Plan fidelity check

1. `Pass` — `MenuBarSceneModel` now routes the `.idle` auto-paste path through `outputService.deliverBatch(text:)` instead of calling the old `pasteInjector` closure directly (`Sources/SeshatAppKit/MenuBar/MenuBarSceneModel.swift:181-201` in the reviewed snapshot).
2. `Pass` — `SeshatAppMain` constructs `ClipboardBatchOutput()` and injects it (`Sources/SeshatAppKit/Composition/SeshatAppMain.swift:60,84-88`), and `copyLatestTranscript()` remains deliberately unmigrated on the raw clipboard writer path (`Sources/SeshatAppKit/MenuBar/MenuBarSceneModel.swift:166-174`), matching the plan’s deferred-note for manual copy helper cleanup.
3. `Fail` — the slice is source-only and does not delete `PasteInjector`, but it misses the plan’s explicit Stage 2 test-seam migration. The current plan says: "Integration tests: update `Tests/SeshatAppKitTests/MenuBarFlowIntegrationTests.swift:17-50,104-140` and `Tests/SeshatAppKitTests/AppEntryPointTests.swift:9-31` so the live composition path uses the new output service." and "Fakes for the new protocols: add `RecordingOutputService` and `FailingOutputService` test doubles that return `OutputResult`" (`plans/central/LAYER_5_output.md:308-311`). No test files were touched in `2d560dc`, the tests still pass `pasteInjector: SilentPaster()`, and `SeshatAppMain` exposes no `OutputService` injection point.
4. `Pass` — the reviewed commit does not re-introduce `copy(text:)` or any public streaming surface. `OutputService` remains batch-only (`Sources/SeshatCore/Output/OutputService.swift:1-4`), and the reviewed files only call `deliverBatch(text:)`.

# Cross-layer / API discipline check

Yes at the public Layer 5 API boundary: `Sources/SeshatCore/Output/OutputService.swift:1-4` still exposes only `deliverBatch(text:) async -> OutputResult`, and the reviewed commit adds no `copy(text:)`, `beginStream()`, or other streaming-facing API.

The remaining caveat is local to compatibility code, not the public contract: `Sources/SeshatAppKit/MenuBar/MenuBarSceneModel.swift:7-27` adds a private adapter from `PasteInjecting` to `OutputService`. That preserves batch-only API shape, but it also preserves some legacy outcome ambiguity until those fallback paths are migrated or deleted.

# Summary

- Finding counts: Blocker `0`, Major `1`, Minor `1`, Nit `0`
- Recommended next action: wire an injectable `OutputService` seam through `SeshatAppMain`, migrate the app-entry / integration tests to that seam, and avoid relying on `LegacyPasteInjectorOutputService` for accurate delivery results.

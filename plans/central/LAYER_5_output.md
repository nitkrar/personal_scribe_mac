# Layer 5 — Output

## Critical discipline
> **Do NOT diverge from this plan. Silent divergence is the cardinal sin. To deviate, surface the proposed divergence in a commit-message comment AND in the hand-off report; wait for main-session confirmation. Paraphrasing the contract is divergence. Renaming a protocol the plan specifies is divergence. Choosing a different storage format than the plan specifies is divergence.**

## Why this layer exists
`PasteInjector` currently owns batch-only output, `MenuBarSceneModel` decides when to auto-paste or copy, and `SeshatAppMain` plus `SeshatApp` each keep their own raw `NSPasteboard` writer. That split duplicates routing logic, keeps clipboard behavior outside the session boundary, and makes later streaming output work harder than it should.

The refactor needs one `@MainActor` output layer that preserves the current batch semantics, centralizes clipboard writes, and makes streaming a first-class contract without wiring streaming into consumers yet. The current trunk also leaks an outcome mismatch: `PasteInjector.paste(_:)` returns `.pasteAtCursor` even when Accessibility is missing and the text only lands on the clipboard (`Sources/SeshatAppKit/Paste/PasteInjector.swift:168-174`), so callers cannot reliably distinguish "synthetic paste happened" from "clipboard-only fallback". Layer 5 is the cleanup boundary for that.

## Observed current spread
| File | Line(s) | What lives there |
|---|---|---|
| `Sources/SeshatAppKit/Paste/PasteInjector.swift` | `7-227` | Batch-only paste routing, frontmost-app detection, clipboard save/restore, AX prompt fallback, and synthetic `Cmd+V`. |
| `Sources/SeshatAppKit/MenuBar/MenuBarSceneModel.swift` | `16-17`, `24-27`, `64-79`, `120-144` | Stores ad-hoc `clipboardWriter` and `pasteInjector` closures, auto-pastes on `.idle`, dedupes with `lastAutoPastedTranscript`, and exposes `copyLatestTranscript()`. |
| `Sources/SeshatAppKit/Composition/SeshatAppMain.swift` | `25-26`, `39-40`, `75-82`, `90-92`, `197-200` | Composes `PasteInjector`, passes clipboard and paste closures into `MenuBarSceneModel`, and triggers the pill clipboard-only notice. |
| `Sources/SeshatAppKit/SeshatApp.swift` | `19-20`, `37-38`, `56-60` | Alternate injectable shell repeats the raw clipboard-writer seam. |
| `Sources/SeshatSession/SessionCoordinator.swift` | `28-38`, `99-101`, `200-214` | Owns successful transcript completion and `mostRecentResult`, but has no output hook. |
| `Sources/SeshatCore/SeshatPasteMode.swift` | `3-27` | User preference that chooses paste-at-cursor vs clipboard-only output. |
| `Sources/SeshatCore/PasteRestoreDelay.swift` | `3-62` | User preference that sets clipboard restore delay for paste-at-cursor. |
| `Sources/SeshatCore/IntentClassifier.swift` | `20-51` | Command-mode classifier stub only; no output consumer yet. |
| `Sources/SeshatAppKit/Overlay/ResponseCard.swift` | `21-146` | Command-mode response-card panel stub only; no output call site yet. |
| `Sources/SeshatAppKit/Components/ResponseCardView.swift` | `3-72` | Command-mode response-card view only; no output call site yet. |
| `Tests/SeshatAppKitTests/PasteInjectorTests.swift` | `20-203` | Current regression suite for AX fallback, clipboard-only routing, empty-input no-op, and restore-delay reads. |
| `Tests/SeshatAppKitTests/MenuBarSceneModelTests.swift` | `242-424` | Current regression suite for idle-transition auto-paste, clipboard-only notice, and `copyLatestTranscript()`. |
| `Tests/SeshatAppKitTests/MenuBarFlowIntegrationTests.swift` | `17-50`, `104-140` | Current end-to-end menu-bar observation path and app-entry wiring. |
| `Tests/SeshatAppKitTests/ManualSettingsVerification.md` | `8-13` | Manual runbook for clipboard restore delay. |
| `Tests/SeshatAppKitTests/ManualPillOverlayVerification.md` | `84-96` | Manual runbook for self-frontmost and clipboard-only fallback notice. |

## Proposed API / contracts
### Types (enums, structs)
- `OutputMode`
  `batch`, `streaming`.
  Consumer-facing policy enum from the locked master prompt. Stage 1 only ships the batch path, but the streaming vocabulary stays reserved so future work does not silently rename the surface again.
- `OutputTarget`
  `frontmostApp`, `clipboardOnly`, `selfFrontmost`.
  Routing result produced by the batch path after evaluating frontmost app and paste preferences. `selfFrontmost` means "route to clipboard instead of synthetic paste."
- `OutputDelivery`
  `paste`, `typeEvents`, `clipboardOnly`.
  Delivery descriptor. Stage 1 uses `paste` and `clipboardOnly`; `typeEvents` remains reserved vocabulary for future streaming work.
- `OutputResult`
  Batch delivery outcome returned by `deliverBatch(text:)`.
  Stage 1 carries the actual delivery result (`delivered(target:delivery:)`), empty-input no-op, and hard pasteboard-write failure.
- `OutputError`
  Stage 1 keeps only `clipboardWriteFailed` as the explicit hard failure for batch output.

### Protocols
- `OutputService: Sendable`
  `@MainActor` class surface owned by this layer.
  Required entry point: `deliverBatch(text: String) async -> OutputResult`.

### Implementations
- `ClipboardBatchOutput`
  Writes the pasteboard, posts synthetic `Cmd+V`, restores after the configured delay, and returns an `OutputResult` that distinguishes pasted vs clipboard-only delivery.
- `StreamedTypingOutput`
  Deferred. Not shipped in Stage 1.

### Deferred streaming note
- Streaming API intentionally deferred — see `plans/backlog/pipeline-streaming-defer.md`. Layer 5 does not expose `beginStream()` or `OutputStreamHandle` in Stage 1.
- Any dormant partial-delivery surface remains outside Layer 5 until the stream-build slice resolves ownership and transport.

## Proposed live implementation
`ClipboardBatchOutput` is the only live `OutputService` conformer in Stage 1. It absorbs the old `PasteOutputService` plus `CopyOutputService` split, keeps the current clipboard save or restore behavior, keeps `PasteMode` plus `PasteRestoreDelay` reads inside the batch path, and restores the prior clipboard contents if a clipboard-only write fails.

`SessionCoordinator` becomes the owner of batch post-transcript output in Stage 2. The coordinator already owns "transcription succeeded, `mostRecentResult` is ready, persistence is done" at `Sources/SeshatSession/SessionCoordinator.swift:200-214`; Layer 5 should move the primary output hook there so output does not depend on `MenuBarSceneModel` observation timing. Output delivery remains best-effort: successful transcription must still publish `.idle` and keep `mostRecentResult` even if output falls back to clipboard or returns `.failed(.clipboardWriteFailed)`.

### New files (explicit Stage 1 list)
- `Sources/SeshatCore/Output/OutputMode.swift`
- `Sources/SeshatCore/Output/OutputTarget.swift`
- `Sources/SeshatCore/Output/OutputDelivery.swift`
- `Sources/SeshatCore/Output/OutputError.swift`
- `Sources/SeshatCore/Output/OutputResult.swift`
- `Sources/SeshatCore/Output/OutputService.swift`
- `Sources/SeshatAppKit/Output/ClipboardBatchOutput.swift`

## Migration of existing call sites
### Stage 1 — Build in parallel
| Stage step | Depends on | Can run in parallel with | Summary |
|---|---|---|---|
| `1.1` | none | layers `1`, `2`, `3`, `4`, `6`, `7`, `8`, `9` Stage 1 | Add `Sources/SeshatCore/Output/*` contracts and core tests only. |
| `1.2` | `1.1` | layers `1`, `2`, `3`, `4`, `6`, `7`, `8`, `9` Stage 1 | Add `ClipboardBatchOutput` and batch output tests in `Sources/SeshatAppKit/Output/*`; no consumer touches. |
| `1.3` | `1.1`, `1.2` | layers `1`, `2`, `3`, `4`, `6`, `7`, `8`, `9` Stage 1 | Update the Layer 5 plan to record the locked batch-only Stage 1 contract and the streaming deferral note. |

### Step 1.1 — Define the core output contracts in new `SeshatCore/Output` files
| Change | Before | After |
|---|---|---|
| Contract ownership | No dedicated output contract in `SeshatCore`; output semantics leak from `PasteInjector` and menu-bar closures. | `SeshatCore` owns the output vocabulary: `OutputMode`, `OutputTarget`, `OutputDelivery`, `OutputResult`, `OutputError`, and `OutputService`. |
| Batch surface | Batch paste exists only as `PasteInjecting.paste(_:)`. | One `@MainActor` service exposes `deliverBatch(text:) async -> OutputResult`. |
| Streaming surface | Layer 5 had no approved batch result type, and the prompt drift was unresolved. | Layer 5 keeps streaming vocabulary only; it does not expose a public streaming handle in Stage 1. |

#### Files touched (exhaustive) — path:line-range — what changes
- `Sources/SeshatCore/Output/OutputMode.swift` — lock the enum to `batch` and `streaming`.
- `Sources/SeshatCore/Output/OutputTarget.swift` — keep the routing vocabulary that replaces `PasteRoutingDecision` after consumer migration.
- `Sources/SeshatCore/Output/OutputDelivery.swift` — keep `paste`, `typeEvents`, and `clipboardOnly`.
- `Sources/SeshatCore/Output/OutputError.swift` — keep `clipboardWriteFailed` as the Stage 1 hard failure.
- `Sources/SeshatCore/Output/OutputResult.swift` — add the batch outcome type.
- `Sources/SeshatCore/Output/OutputService.swift` — add the `@MainActor` `deliverBatch(text:)` contract.
- `Tests/SeshatCoreTests/Output/OutputContractsTests.swift` — pin the enum cases, `OutputResult`, and the single-method `OutputService` surface.

#### Scope — IN
- Define the public and internal layer vocabulary only.
- Preserve the locked `OutputMode` spelling exactly.
- Keep the streaming vocabulary without exposing a Layer 5 streaming API in Stage 1.

#### Scope — OUT
- No AppKit implementation yet.
- No consumer migration yet.
- No edits outside `Sources/SeshatCore/Output/*` and `Tests/SeshatCoreTests/Output/*`.

#### Acceptance tests — Tests/... — test name + what it asserts + clause it ties to
- `Tests/SeshatCoreTests/Output/OutputContractsTests.swift` — `testOutputModeHasBatchAndStreaming`; ties to `Proposed API / contracts > Types`.
- `Tests/SeshatCoreTests/Output/OutputContractsTests.swift` — `testOutputResultRepresentsDeliveredFailedAndIgnoredInputOutcomes`; ties to `Proposed API / contracts > Types`.
- `Tests/SeshatCoreTests/Output/OutputContractsTests.swift` — `testOutputServiceExposesDeliverBatchOnly`; ties to `Proposed API / contracts > Protocols`.

#### Validation checklist (implementer ticks box-by-box)
- [ ] `Sources/SeshatCore/Output/OutputMode.swift` declares exactly `batch` and `streaming`, matching `Proposed API / contracts > Types`.
- [ ] `Sources/SeshatCore/Output/OutputService.swift` exposes only `deliverBatch(text:) async -> OutputResult`, matching `Proposed API / contracts > Protocols`.
- [ ] No `Sources/SeshatCore/Output/OutputStreamHandle.swift` file exists in Stage 1, matching `Deferred streaming note`.
- [ ] `Tests/SeshatCoreTests/Output/OutputContractsTests.swift` pins the contract without importing AppKit behavior, matching `Test strategy` unit-test bullet 1.

### Step 1.2 — Add `ClipboardBatchOutput` in new `SeshatAppKit/Output` files
| Change | Before | After |
|---|---|---|
| Batch paste implementation | `PasteInjector` is the only batch output surface and sits outside a layer contract. | `ClipboardBatchOutput` wraps the current batch behavior behind the Layer 5 contract. |
| Clipboard-only delivery | Clipboard-only behavior is split between paste routing and a separate copy service. | One batch implementation handles both pasted and clipboard-only outcomes via `OutputResult`. |
| Regression coverage | Paste behavior is tested only through `PasteInjectorTests`. | New output tests port those cases to the Layer 5 surface before any consumer swap. |

#### Files touched (exhaustive) — path:line-range — what changes
- `Sources/SeshatAppKit/Output/ClipboardBatchOutput.swift` — add the `PasteInjector` wrapper with the same routing, restore-delay, and AX-prompt behavior, plus clipboard restore on write failure.
- `Tests/SeshatAppKitTests/Output/ClipboardBatchOutputTests.swift` — port the current paste regression cases from `Tests/SeshatAppKitTests/PasteInjectorTests.swift` and add the clipboard-only write-failure restore case.

#### Scope — IN
- Preserve current batch behavior exactly before any consumer changes.
- Keep `PasteInjector.swift` untouched in Stage 1; the new wrapper lands beside it.
- Fold the old copy-only path into the batch implementation instead of shipping a separate public copy service.

#### Scope — OUT
- No edits to `MenuBarSceneModel`, `SeshatAppMain`, `SeshatApp`, or `SessionCoordinator` yet.
- No Layer 5 streaming implementation.
- No command-mode wiring yet.

#### Acceptance tests — Tests/... — test name + what it asserts + clause it ties to
- `Tests/SeshatAppKitTests/Output/ClipboardBatchOutputTests.swift` — `testPromptsAccessibilityWhenNotTrustedAndLeavesTranscriptOnClipboard`; ties to `Sources/SeshatAppKit/Paste/PasteInjector.swift:168-171` and `Why this layer exists` paragraph 2.
- `Tests/SeshatAppKitTests/Output/ClipboardBatchOutputTests.swift` — `testDeliverBatchReturnsClipboardOnlyWhenModeIsClipboardOnly`; ties to `Sources/SeshatCore/SeshatPasteMode.swift:3-27`.
- `Tests/SeshatAppKitTests/Output/ClipboardBatchOutputTests.swift` — `testDeliverBatchReadsRestoreDelayPreferencePerCall`; ties to `Sources/SeshatCore/PasteRestoreDelay.swift:3-62` and `Tests/SeshatAppKitTests/ManualSettingsVerification.md:8-13`.
- `Tests/SeshatAppKitTests/Output/ClipboardBatchOutputTests.swift` — `testClipboardOnlyWriteFailureRestoresExistingPasteboardContents`; ties to the Stage 1 review finding about clipboard preservation on batch-write failure.

#### Validation checklist (implementer ticks box-by-box)
- [ ] `Sources/SeshatAppKit/Output/ClipboardBatchOutput.swift` preserves the existing batch routing semantics without modifying `Sources/SeshatAppKit/Paste/PasteInjector.swift`, matching `Proposed live implementation`.
- [ ] `Tests/SeshatAppKitTests/Output/ClipboardBatchOutputTests.swift` covers the behaviors currently pinned by `Tests/SeshatAppKitTests/PasteInjectorTests.swift`, matching `Test strategy` regression-guard bullets.
- [ ] No `Sources/SeshatAppKit/Output/CopyOutputService.swift`, `Sources/SeshatAppKit/Output/AppKitOutputService.swift`, or `Sources/SeshatAppKit/Output/StreamingOutputHandle.swift` file exists in Stage 1, matching `Deferred streaming note`.

### Step 1.3 — Update the plan and defer note
| Change | Before | After |
|---|---|---|
| Layer 5 API section | The plan diverges from the locked master prompt. | The plan records the `deliverBatch(text:) async -> OutputResult` contract and the `ClipboardBatchOutput` implementation. |
| Streaming note | Layer 5 still claims a public `beginStream()` surface. | The plan explicitly records that streaming is deferred and not exposed by Layer 5 in Stage 1. |

#### Files touched (exhaustive) — path:line-range — what changes
- `plans/central/LAYER_5_output.md` — replace the divergent API description with the locked batch-only Stage 1 contract.

#### Scope — IN
- Align the plan with the locked master prompt and the Stage 1 review.
- Keep the streaming deferral note pointed at `plans/backlog/pipeline-streaming-defer.md`.

#### Scope — OUT
- No new code.
- No change to the backlog's unresolved stream-build ownership question.

#### Validation checklist (implementer ticks box-by-box)
- [ ] The API section matches `plans/CENTRAL_LAYERS_PROMPT.md:268-276` for `OutputMode`, `OutputTarget`, `OutputDelivery`, `OutputService.deliverBatch(text:)`, and `ClipboardBatchOutput`.
- [ ] The plan states that Layer 5 does not expose `beginStream()` or `OutputStreamHandle` in Stage 1, matching `plans/backlog/pipeline-streaming-defer.md`.

> Note: the Stage 2 / Stage 3 migration tables below predate this Stage 1 contract correction. Until those sections are rewritten, interpret `OutputService` as the batch-only `deliverBatch(text:)` surface, `ClipboardBatchOutput` as the sole Stage 1 live implementation, and any references to `copy(text:)`, `beginStream()`, `OutputStreamHandle`, `PasteOutputService`, `CopyOutputService`, or `AppKitOutputService` as stale.

### Stage 2 — Swap
| Stage step | Depends on | Summary |
|---|---|---|
| `2.1` | `1.3`, layer `1` Stage 2, layer `3` Stage 2 | Move the main post-transcript output hook into `SessionCoordinator` and remove menu-bar observation-driven auto-paste. |
| `2.2` | `2.1`, layer `3` Stage 2 | Replace the menu-bar copy or paste-last helper and app-entry clipboard seams with `OutputService.copy(text:)`. |
| `2.3` | `2.1` | Audit command-mode stubs; swap to `OutputService` only if a real trunk call site exists when execution begins. |

### Step 2.1 — Move the main post-transcript output hook into `SessionCoordinator`
| Change | Before | After |
|---|---|---|
| Post-transcript output ownership | `MenuBarSceneModel` observes `stateStream()`, waits for `.idle`, reads `lastResult()`, and calls the paste closure. | `SessionCoordinator` owns the batch output hook immediately after successful transcription and persistence. |
| Auto-paste dedupe | `MenuBarSceneModel` keeps `lastAutoPastedTranscript` and dedupes by observation timing. | The output hook dedupes at the producer boundary, where `mostRecentResult` is set. |
| Clipboard-only notice | `MenuBarSceneModel` can only react to the limited legacy route result. | The new output path surfaces clipboard-only fallback from the Layer 5 service and keeps the pill notice reachable without relying on observation timing. |

#### Files touched (exhaustive) — path:line-range — what changes
- `Sources/SeshatSession/SessionCoordinator.swift:5-38,200-216` — inject `OutputService` and invoke it from the successful transcription path after `mostRecentResult` and persistence are complete.
- `Sources/SeshatAppKit/Composition/AppComposition.swift:9-25,44-46` — build the shared live output service and pass it into the live coordinator.
- `Sources/SeshatAppKit/MenuBar/MenuBarSceneModel.swift:24-27,64-79,135-144` — remove observation-driven auto-paste, `lastAutoPastedTranscript`, and the legacy paste closure.
- `Tests/SeshatSessionTests/SessionCoordinatorOutputTests.swift:1-200` — add focused output-hook tests.
- `Tests/SeshatSessionTests/SessionCoordinatorHappyPathTests.swift:7-45` — extend the happy path to prove output fires once on success.
- `Tests/SeshatSessionTests/SessionCoordinatorErrorTests.swift:7-182` — assert failed, too-short, and error paths do not invoke output.
- `Tests/SeshatAppKitTests/DevelopmentComposition.swift:8-25` — pass a fake or recording output service into test coordinators.
- `Tests/SeshatAppKitTests/MenuBarSceneModelTests.swift:264-384` — delete or rewrite the old idle-transition auto-paste tests to assert the new coordinator-owned seam instead.

#### Scope — IN
- Move the primary batch output hook to the session boundary.
- Keep successful transcription state semantics intact.
- Preserve the clipboard-only notice path without making `MenuBarSceneModel` responsible for deciding when output happens.

#### Scope — OUT
- No direct clipboard-write swap yet. That is Step 2.2.
- No command-mode adoption yet. That is Step 2.3.
- No streaming consumer adoption.

#### Acceptance tests — Tests/... — test name + what it asserts + clause it ties to
- `Tests/SeshatSessionTests/SessionCoordinatorOutputTests.swift` — `testSuccessfulTranscriptionInvokesPasteOnceAfterResultIsStored`; ties to `Sources/SeshatSession/SessionCoordinator.swift:200-214`.
- `Tests/SeshatSessionTests/SessionCoordinatorOutputTests.swift` — `testClipboardOnlyFallbackDoesNotDiscardResultOrIdleTransition`; ties to `Why this layer exists` paragraph 2 and `Proposed live implementation` paragraph 4.
- `Tests/SeshatSessionTests/SessionCoordinatorOutputTests.swift` — `testRepeatedIdenticalResultDoesNotInvokePasteTwice`; ties to `Tests/SeshatAppKitTests/MenuBarSceneModelTests.swift:352-384`.
- `Tests/SeshatSessionTests/SessionCoordinatorErrorTests.swift` — existing error tests plus `testShortRecordingPublishesRecordingTooShortErrorWithoutInvokingOutput`; ties to `Sources/SeshatSession/SessionCoordinator.swift:191-196`.
- `Tests/SeshatAppKitTests/MenuBarFlowIntegrationTests.swift` — `testRecordStopTranscribeIdleFlowPublishesLatestResult`; ties to the regression that `MenuBarSceneModel` still observes coordinator state even after it stops owning the paste call.

#### Validation checklist (implementer ticks box-by-box)
- [ ] `Sources/SeshatSession/SessionCoordinator.swift:200-216` invokes Layer 5 output from the success path instead of relying on `MenuBarSceneModel` observation, matching `Proposed live implementation` paragraph 4 and `Stage 2` step `2.1`.
- [ ] `Sources/SeshatAppKit/MenuBar/MenuBarSceneModel.swift:24-27,64-79,135-144` no longer stores `lastAutoPastedTranscript` or calls the legacy paste closure, matching `Stage 2` step `2.1`.
- [ ] `Tests/SeshatSessionTests/SessionCoordinatorOutputTests.swift:1-200` proves success calls output once, repeated identical results do not double-paste, and error paths do not output, matching `Test strategy` unit-test bullet 5.
- [ ] `Tests/SeshatAppKitTests/MenuBarSceneModelTests.swift:264-384` no longer treats idle-state observation as the source of truth for output delivery, matching `Why this layer exists` paragraph 1.
- [ ] The touched surface is limited to `Sources/SeshatSession/SessionCoordinator.swift:5-38,200-216`, `Sources/SeshatAppKit/Composition/AppComposition.swift:9-25,44-46`, `Sources/SeshatAppKit/MenuBar/MenuBarSceneModel.swift:24-27,64-79,135-144`, `Tests/SeshatSessionTests/SessionCoordinatorOutputTests.swift:1-200`, `Tests/SeshatSessionTests/SessionCoordinatorHappyPathTests.swift:7-45`, `Tests/SeshatSessionTests/SessionCoordinatorErrorTests.swift:7-182`, `Tests/SeshatAppKitTests/DevelopmentComposition.swift:8-25`, and `Tests/SeshatAppKitTests/MenuBarSceneModelTests.swift:264-384`, matching `Stage 2 — Swap`.

### Step 2.2 — Replace the menu-bar copy or paste-last helper and app-entry clipboard seams with `OutputService.copy(text:)`
| Change | Before | After |
|---|---|---|
| Manual copy helper | `MenuBarSceneModel.copyLatestTranscript()` calls `clipboardWriter(lastResultText)`. | `MenuBarSceneModel.copyLatestTranscript()` uses `try await outputService.copy(text:)`. |
| App entry seam | `SeshatAppMain` and `SeshatApp` pass raw `clipboardWriter` closures. | Both shells inject the shared Layer 5 service instead of ad-hoc pasteboard writers. |
| Test seam | Entry-point and menu-bar tests build `SilentPaster` or raw clipboard closures. | Tests use `RecordingOutputService` and `ThrowingOutputService` fakes. |

#### Files touched (exhaustive) — path:line-range — what changes
- `Sources/SeshatAppKit/MenuBar/MenuBarSceneModel.swift:16-18,29-54,120-128` — replace the stored clipboard writer with `OutputService`.
- `Sources/SeshatAppKit/Composition/SeshatAppMain.swift:25-26,39-40,75-82,197-200` — stop constructing raw clipboard writers and inject the shared output service instead.
- `Sources/SeshatAppKit/SeshatApp.swift:19-20,37-38,56-60` — stop constructing the alternate raw clipboard writer and inject the shared output service instead.
- `Tests/SeshatAppKitTests/MenuBarSceneModelTests.swift:386-424` — rewrite the copy helper tests against `OutputService.copy(text:)`.
- `Tests/SeshatAppKitTests/AppEntryPointTests.swift:9-31,46-50` — replace `SilentPaster` with an output-service fake.
- `Tests/SeshatAppKitTests/MenuBarFlowIntegrationTests.swift:17-25,116-125,171-175` — replace old output fakes with the Layer 5 fake surface.

#### Scope — IN
- Swap every current menu-bar and app-entry clipboard seam to `OutputService.copy(text:)`.
- Preserve `copyLatestTranscript()` behavior even though trunk currently has no status-menu dispatch to it.
- Keep this step limited to the current helper and entry shells unless main-session explicitly resolves the missing dispatch as part of the same execution.

#### Scope — OUT
- Do not invent a new status-item action if the dispatch still does not exist on trunk.
- Do not change command-mode stubs here.
- Do not re-open the output service contract.

#### Acceptance tests — Tests/... — test name + what it asserts + clause it ties to
- `Tests/SeshatAppKitTests/MenuBarSceneModelTests.swift` — `testCopyLatestTranscriptWritesCurrentTranscriptToOutputService`; ties to `Sources/SeshatAppKit/MenuBar/MenuBarSceneModel.swift:120-128`.
- `Tests/SeshatAppKitTests/MenuBarSceneModelTests.swift` — `testCopyLatestTranscriptDoesNothingWhenTranscriptIsMissing`; ties to the current no-op behavior at `Sources/SeshatAppKit/MenuBar/MenuBarSceneModel.swift:121-124`.
- `Tests/SeshatAppKitTests/AppEntryPointTests.swift` — `testSeshatAppMainBuildsSceneModelFromComposition`; ties to `Sources/SeshatAppKit/Composition/SeshatAppMain.swift:75-93`.

#### Validation checklist (implementer ticks box-by-box)
- [ ] `Sources/SeshatAppKit/MenuBar/MenuBarSceneModel.swift:120-128` uses `OutputService.copy(text:)` instead of a raw pasteboard closure, matching `Stage 2` step `2.2`.
- [ ] `Sources/SeshatAppKit/Composition/SeshatAppMain.swift:25-26,39-40,75-82,197-200` and `Sources/SeshatAppKit/SeshatApp.swift:19-20,37-38,56-60` no longer contain raw `NSPasteboard.general` writes, matching `Proposed live implementation` paragraph 3.
- [ ] `Tests/SeshatAppKitTests/AppEntryPointTests.swift:9-31,46-50` and `Tests/SeshatAppKitTests/MenuBarFlowIntegrationTests.swift:116-125,171-175` use Layer 5 output fakes rather than `PasteInjecting`, matching `Stage 3 delete inventory`.
- [ ] `Tests/SeshatAppKitTests/MenuBarSceneModelTests.swift:386-424` still proves missing-transcript no-op behavior, matching `Observed current spread` row for `MenuBarSceneModel`.
- [ ] The touched surface is limited to `Sources/SeshatAppKit/MenuBar/MenuBarSceneModel.swift:16-18,29-54,120-128`, `Sources/SeshatAppKit/Composition/SeshatAppMain.swift:25-26,39-40,75-82,197-200`, `Sources/SeshatAppKit/SeshatApp.swift:19-20,37-38,56-60`, `Tests/SeshatAppKitTests/MenuBarSceneModelTests.swift:386-424`, `Tests/SeshatAppKitTests/AppEntryPointTests.swift:9-31,46-50`, and `Tests/SeshatAppKitTests/MenuBarFlowIntegrationTests.swift:17-25,116-125,171-175`, matching `Stage 2` step `2.2`.

### Step 2.3 — Audit command-mode stub wiring and swap only if a real output call site exists
| Change | Before | After |
|---|---|---|
| Command-mode output | Trunk has classifier and response-card stubs only. | Layer 5 records the current state as "no live output consumer" unless a real call site has landed before execution begins. |
| Future adoption rule | A future output call site could bypass Layer 5. | Any real command-mode output seam must inject `OutputService`, not raw pasteboard writes or legacy `PasteInjecting` seams. |

#### Files touched (exhaustive) — path:line-range — what changes
- `Sources/SeshatCore/IntentClassifier.swift:20-51` — audit only; no edit unless a real output consumer landed here before execution starts.
- `Sources/SeshatAppKit/Overlay/ResponseCard.swift:21-146` — audit only; no edit unless a real output consumer landed here before execution starts.
- `Sources/SeshatAppKit/Components/ResponseCardView.swift:3-72` — audit only; no edit unless a real output consumer landed here before execution starts.
- `Tests/...` — touch only the tests that cover the real command-mode call site, if one exists by execution time.

#### Scope — IN
- Explicitly document that trunk has no live command-mode output consumer today.
- Swap only a real, already-landed call site if it exists by the time implementation starts.

#### Scope — OUT
- Do not invent a command-mode output flow.
- Do not wire streaming output into command mode in this refactor.
- Do not edit command-mode UI stubs just to make Layer 5 look more complete.

#### Acceptance tests — Tests/... — test name + what it asserts + clause it ties to
- If no command-mode output consumer exists, this step has no code changes and no commit.
- If a command-mode output consumer exists, add a focused test proving it reaches `OutputService` and not a raw clipboard or paste seam; tie it to `Observed current spread` command-mode rows.

#### Validation checklist (implementer ticks box-by-box)
- [ ] If the trunk surface still matches `Sources/SeshatCore/IntentClassifier.swift:20-51`, `Sources/SeshatAppKit/Overlay/ResponseCard.swift:21-146`, and `Sources/SeshatAppKit/Components/ResponseCardView.swift:3-72`, this step was recorded as a no-op in the hand-off report, matching `Observed current spread`.
- [ ] If a real command-mode output call site existed by execution time, only that call site and its tests were modified, and the dependency is `OutputService`, matching `Stage 2` step `2.3`.
- [ ] `Sources/SeshatCore/IntentClassifier.swift:20-51`, `Sources/SeshatAppKit/Overlay/ResponseCard.swift:21-146`, and `Sources/SeshatAppKit/Components/ResponseCardView.swift:3-72` still contain no streaming-output consumer after this step, matching `Streaming hook design notes` bullet 5.

### Stage 3 — Delete
| Stage step | Depends on | Summary |
|---|---|---|
| `3.1` | `2.1`, `2.2`, `2.3` | Delete legacy `PasteInjector` call sites, ad-hoc clipboard-writer seams, and the old test surface. |

### Stage 3 delete inventory
| Legacy surface | Current file:line | Delete in Stage 3 because |
|---|---|---|
| Direct `PasteInjector()` construction | `Sources/SeshatAppKit/Composition/SeshatAppMain.swift:26`, `Sources/SeshatAppKit/Composition/SeshatAppMain.swift:40` | Stage 2 should already inject the shared Layer 5 service. |
| Direct `pasteInjector.paste(text)` closure bridge | `Sources/SeshatAppKit/Composition/SeshatAppMain.swift:80-82` | The coordinator and menu-bar model should no longer know about `PasteInjecting`. |
| Legacy paste closure storage and use | `Sources/SeshatAppKit/MenuBar/MenuBarSceneModel.swift:17`, `Sources/SeshatAppKit/MenuBar/MenuBarSceneModel.swift:34`, `Sources/SeshatAppKit/MenuBar/MenuBarSceneModel.swift:46`, `Sources/SeshatAppKit/MenuBar/MenuBarSceneModel.swift:140-143` | Replaced by Layer 5 output ownership in Stage 2.1. |
| Observation-driven auto-paste state | `Sources/SeshatAppKit/MenuBar/MenuBarSceneModel.swift:26`, `Sources/SeshatAppKit/MenuBar/MenuBarSceneModel.swift:77`, `Sources/SeshatAppKit/MenuBar/MenuBarSceneModel.swift:135-144` | Output should no longer depend on menu-bar observation timing. |
| Raw clipboard writer injection and implementation | `Sources/SeshatAppKit/Composition/SeshatAppMain.swift:25`, `Sources/SeshatAppKit/Composition/SeshatAppMain.swift:39`, `Sources/SeshatAppKit/Composition/SeshatAppMain.swift:79`, `Sources/SeshatAppKit/Composition/SeshatAppMain.swift:197-200` | `CopyOutputService` is the only clipboard writer after Stage 2.2. |
| Alternate shell raw clipboard writer | `Sources/SeshatAppKit/SeshatApp.swift:19`, `Sources/SeshatAppKit/SeshatApp.swift:37`, `Sources/SeshatAppKit/SeshatApp.swift:56-60` | Same reason as `SeshatAppMain`; delete the duplicate seam. |
| Legacy protocol and type surface | `Sources/SeshatAppKit/Paste/PasteInjector.swift:7-52` | `PasteRoutingDecision` and `PasteInjecting` should not survive after Layer 5 owns output. |
| Legacy test seam `SilentPaster` | `Tests/SeshatAppKitTests/AppEntryPointTests.swift:47-50`, `Tests/SeshatAppKitTests/MenuBarFlowIntegrationTests.swift:172-175` | Tests should use Layer 5 fakes instead of the deleted protocol. |
| Legacy `PasteInjectorTests` file | `Tests/SeshatAppKitTests/PasteInjectorTests.swift:1-209` | Coverage has moved to `Tests/SeshatAppKitTests/Output/ClipboardBatchOutputTests.swift`. |

### Step 3.1 — Delete legacy output surfaces after every consumer has swapped
| Change | Before | After |
|---|---|---|
| Output protocol surface | `PasteInjecting`, `PasteRoutingDecision`, and direct paste closures remain reachable. | Only Layer 5 types remain reachable from production and tests. |
| Clipboard seams | `SeshatAppMain` and `SeshatApp` still carry raw pasteboard helpers. | Only `CopyOutputService` writes to the clipboard from app code. |
| Test surface | Tests still reference the pre-Layer-5 output seam. | Tests use only Layer 5 output fakes and output-specific test files. |

#### Files touched (exhaustive) — path:line-range — what changes
- `Sources/SeshatAppKit/Paste/PasteInjector.swift:1-227` — delete the file once `ClipboardBatchOutput` fully owns the behavior.
- `Sources/SeshatAppKit/MenuBar/MenuBarSceneModel.swift:16-18,24-27,120-144` — remove any leftover old output state or helper code.
- `Sources/SeshatAppKit/Composition/SeshatAppMain.swift:25-26,39-40,75-82,197-200` — remove the old output seam from composition.
- `Sources/SeshatAppKit/SeshatApp.swift:19-20,37-38,56-60` — remove the alternate-shell clipboard seam.
- `Tests/SeshatAppKitTests/PasteInjectorTests.swift:1-209` — delete once the new output tests are authoritative.
- `Tests/SeshatAppKitTests/AppEntryPointTests.swift:17-26,46-50` — remove `PasteInjecting`-based fakes.
- `Tests/SeshatAppKitTests/MenuBarFlowIntegrationTests.swift:116-125,171-175` — remove `PasteInjecting`-based fakes.
- `Tests/SeshatAppKitTests/MenuBarSceneModelTests.swift:264-424` — remove any remaining references to the deleted seam.

#### Scope — IN
- Remove every legacy direct `PasteInjector` call site listed in `Stage 3 delete inventory`.
- Remove every ad-hoc clipboard writer seam listed in `Stage 3 delete inventory`.
- Delete legacy test-only protocol fakes once the new Layer 5 tests are live.

#### Scope — OUT
- No new behavior.
- No silent "keep the old helper around just in case" exception.
- No additional consumer changes beyond the explicit delete inventory.

#### Acceptance tests — Tests/... — test name + what it asserts + clause it ties to
- `Tests/SeshatAppKitTests/Output/ClipboardBatchOutputTests.swift` — ported batch output coverage remains green after the old file disappears.
- `Tests/SeshatAppKitTests/MenuBarSceneModelTests.swift` — copy helper tests remain green without raw clipboard closures.
- `Tests/SeshatSessionTests/SessionCoordinatorOutputTests.swift` — post-transcript output remains green after the legacy seam deletion.
- `Tests/SeshatAppKitTests/ManualPillOverlayVerification.md` — keep `MV-B1-7` and `MV-B1-8` passing after the delete step.
- `Tests/SeshatAppKitTests/ManualSettingsVerification.md` — keep the clipboard restore delay checks passing after the delete step.

#### Validation checklist (implementer ticks box-by-box)
- [ ] The delete sweep removed the production legacy surfaces in `Sources/SeshatAppKit/Paste/PasteInjector.swift:1-227`, `Sources/SeshatAppKit/MenuBar/MenuBarSceneModel.swift:16-18,24-27,120-144`, `Sources/SeshatAppKit/Composition/SeshatAppMain.swift:25-26,39-40,75-82,197-200`, and `Sources/SeshatAppKit/SeshatApp.swift:19-20,37-38,56-60`, matching `Stage 3 delete inventory`.
- [ ] `Sources/SeshatAppKit/Paste/PasteInjector.swift:1-227` is deleted, and no public `PasteInjecting` or `PasteRoutingDecision` surface remains, matching `Proposed live implementation` paragraph 2.
- [ ] `Sources/SeshatAppKit/Composition/SeshatAppMain.swift:25-26,39-40,75-82,197-200` and `Sources/SeshatAppKit/SeshatApp.swift:19-20,37-38,56-60` contain no raw `NSPasteboard.general` writes, matching `Stage 3 delete inventory`.
- [ ] `Tests/SeshatAppKitTests/PasteInjectorTests.swift:1-209` is deleted, and the replacement coverage lives under `Tests/SeshatAppKitTests/Output/*`, matching `Test strategy`.
- [ ] After deleting `Sources/SeshatAppKit/Paste/PasteInjector.swift:1-227`, `Tests/SeshatAppKitTests/PasteInjectorTests.swift:1-209`, `Tests/SeshatAppKitTests/AppEntryPointTests.swift:17-26,46-50`, and `Tests/SeshatAppKitTests/MenuBarFlowIntegrationTests.swift:116-125,171-175`, `rg -n '\\bPasteInjector\\b|\\bPasteInjecting\\b|\\bPasteRoutingDecision\\b|clipboardWriter' Sources Tests` returns zero hits outside historical plan docs, matching `Stage 3 delete inventory`.

## Test strategy
- Unit tests: add `Tests/SeshatCoreTests/Output/OutputContractsTests.swift` to pin the Layer 5 contract; add `Tests/SeshatAppKitTests/Output/ClipboardBatchOutputTests.swift` to pin batch behavior and the clipboard-preservation failure case; add `Tests/SeshatSessionTests/SessionCoordinatorOutputTests.swift` to pin the new post-transcript hook.
- Integration tests: update `Tests/SeshatAppKitTests/MenuBarFlowIntegrationTests.swift:17-50,104-140` and `Tests/SeshatAppKitTests/AppEntryPointTests.swift:9-31` so the live composition path uses the new output service.
- Fakes for the new protocols: add `RecordingOutputService` and `FailingOutputService` test doubles that return `OutputResult`; do not keep `PasteInjecting` fakes after Stage 3.
- Regression guards the layer must preserve: port the current behaviors from `Tests/SeshatAppKitTests/PasteInjectorTests.swift:20-203`; preserve `Tests/SeshatAppKitTests/MenuBarSceneModelTests.swift:264-424` semantics for exactly-once output and missing-transcript no-op; keep `Tests/SeshatAppKitTests/ManualSettingsVerification.md:8-13` and `Tests/SeshatAppKitTests/ManualPillOverlayVerification.md:84-96` current checks live.
- Manual verification additions: extend `Tests/SeshatAppKitTests/ManualPillOverlayVerification.md` with an explicit AX-untrusted clipboard-only fallback case, because the current runbook covers self-frontmost and clipboard-only mode but not the missing-AX route at `Sources/SeshatAppKit/Paste/PasteInjector.swift:168-171`.

## Open design questions (surface — do not resolve)
- [QUESTION] The locked Stage 1 contract is `deliverBatch(text:) async -> OutputResult`, but trunk still has an unused manual `copyLatestTranscript()` helper. If a future explicit copy action must bypass paste-at-cursor preferences, does Layer 5 need an approved caller-specified clipboard-only API, or should that remain out of scope for this layer?
- [QUESTION] The brief names a `MenuBarSceneModel` "paste-last-transcript" consumer, but trunk only has an unused `copyLatestTranscript()` helper at `Sources/SeshatAppKit/MenuBar/MenuBarSceneModel.swift:120-128` and no status-item dispatch for it in `Sources/SeshatAppKit/MenuBar/StatusItemController.swift:114-130` and `Sources/SeshatAppKit/MenuBar/StatusItemMenuModel.swift:39-45,112-133`. Should Layer 5 swap only the helper, or is a new menu action expected in the same slice?
- [QUESTION] Streaming ownership remains deferred by `plans/backlog/pipeline-streaming-defer.md`. When the stream build lands, should the live partial-output implementation sit alongside `ClipboardBatchOutput` in Layer 5 or stay exclusively in Layer 7?

## Validation checklist (implementer ticks box-by-box)
- [ ] Every file in `New files (explicit Stage 1 list)` exists under `Sources/SeshatCore/Output/*` or `Sources/SeshatAppKit/Output/*`, matching `Stage 1 — Build in parallel`.
- [ ] Stage 2 touched only the consumers listed in `Stage 2 — Swap` and the explicit test and composition files required to support them.
- [ ] Every entry in `Stage 3 delete inventory` is gone by the end of Stage 3.
- [ ] No files outside the explicit per-step inventories were modified.
- [ ] No `Color(hex:` outside `Theme/*`.
- [ ] No direct `UserDefaults.standard.*` — typed resolvers only.
- [ ] No `type` / `kind` / `intent` column added to SQLite.
- [ ] `swift build --build-tests` green (main session).
- [ ] All acceptance tests named in this plan pass.

## Backlog tickets authored
- `plans/backlog/pipeline-streaming-defer.md` — authoritative Stage 1 defer note for streaming output ownership and public API scope. Layer 5 stays batch-only until the stream-build slice resolves it.

## Inter-layer dependencies
- **Requires**: layer `1` because the paste path should consume the centralized permission story instead of keeping raw AX and TCC branching forever.
- **Requires**: layer `3` because the live paste path must read the centralized `PasteMode` and `PasteRestoreDelay` preferences.
- **Blocks**: none inside layers `1`-`9`; any future streaming-transcription slice should first resolve `plans/backlog/pipeline-streaming-defer.md` instead of inventing a second output seam.

## Commit style
`trunk: layer 5.<n>: <verb-led subject>`. Test + fix in same commit.

Recommended mapping for this layer:
- `1.1` -> `trunk: layer 5.1: define output service contracts`
- `1.2` -> `trunk: layer 5.2: add batch paste and copy output services`
- `1.3` -> `trunk: layer 5.3: add live output facade and streaming seam`
- `2.1` -> `trunk: layer 5.4: move post-transcript output into session coordinator`
- `2.2` -> `trunk: layer 5.5: swap menu bar copy path to output service`
- `2.3` -> `trunk: layer 5.6: adopt output service in command-mode call site` if non-no-op
- `3.1` -> `trunk: layer 5.7: delete legacy paste and clipboard seams`

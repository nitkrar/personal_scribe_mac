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
  `paste`, `copy`, `both`.
  Consumer-facing policy enum. Stage 2 uses `paste` for the post-transcript hook and `copy` for the current `MenuBarSceneModel.copyLatestTranscript()` helper. `both` is part of the locked public contract but is not consumed on trunk today.
- `OutputTarget`
  `frontmostApp`, `clipboardOnly`, `selfFrontmost`.
  Internal routing result produced by the paste path after evaluating frontmost app and paste preferences. This replaces the legacy `PasteRoutingDecision` shape once Stage 3 lands.
- `OutputDelivery`
  `paste`, `typeEvents`, `clipboardOnly`.
  Internal transport descriptor. `paste` covers the current batch clipboard-plus-`Cmd+V` path. `typeEvents` is reserved for the still-deferred streaming transport choice. `clipboardOnly` records a successful non-pasted fallback.
- `OutputError`
  Layer-owned error domain for the `async throws` contract.
  Minimum cases: `clipboardWriteFailed`, `clipboardOnlyFallback`, `streamingTransportDecisionRequired`, `copyUnavailable`.
  `clipboardOnlyFallback` is explicitly non-fatal to the session pipeline: it means the text was copied successfully, but a synthetic paste did not occur.

### Protocols
- `OutputService: Sendable`
  `@MainActor` surface owned by this layer.
  Required entry points: `paste(text:) async throws`, `copy(text:) async throws`, `beginStream() -> any OutputStreamHandle`.
  `paste(text:)` is the batch post-transcript path.
  `copy(text:)` is the direct clipboard-write path for manual copy or paste-last style actions.
  `beginStream()` reserves the streaming hook now even though no consumer adopts it in this refactor.
- `OutputStreamHandle: Sendable`
  `append(_ chunk: String)` and `finalize()`.
  One handle instance represents one streaming output session. `append(_:)` consumes partial text updates; `finalize()` closes the session and releases any retained clipboard or transport state.

### Errors
- `OutputError`
  `clipboardWriteFailed` is the hard failure for pasteboard writes.
  `clipboardOnlyFallback` is the handled fallback case when batch paste becomes clipboard-only.
  `streamingTransportDecisionRequired` is the guardrail until the backlog decision is approved.
  `copyUnavailable` is reserved for any future pasteboard-unavailable path that should not be silently swallowed.

## Proposed live implementation
`AppKitOutputService` should be the only public live conformer and should be a `@MainActor final class`. It owns one `PasteOutputService`, one `CopyOutputService`, and one streaming-handle factory. Stage 1 keeps all of that in `Sources/SeshatAppKit/Output/*` so other layer Stage 1 work can land in parallel without collisions.

`PasteOutputService` is the temporary bridge from Layer 5 to the existing batch behavior. In Stage 1 it wraps the current `PasteInjector` semantics instead of editing current consumers. In Stage 2 it becomes the only batch paste path that `SessionCoordinator` and `MenuBarSceneModel` can reach. In Stage 3 the legacy `PasteInjector` surface and call sites disappear; either its logic has been fully absorbed into `PasteOutputService`, or `PasteInjector.swift` is deleted after the wrapper no longer needs it.

`CopyOutputService` is the only raw pasteboard writer after Stage 2. No menu-bar or composition file should retain its own `NSPasteboard.general` write closure once the swap is done. `CopyOutputService` remains small and synchronous internally, but the protocol stays `async throws` so consumers see one consistent interface.

`SessionCoordinator` becomes the owner of batch post-transcript output in Stage 2. The coordinator already owns "transcription succeeded, `mostRecentResult` is ready, persistence is done" at `Sources/SeshatSession/SessionCoordinator.swift:200-214`; Layer 5 should move the primary output hook there so output does not depend on `MenuBarSceneModel` observation timing. Output delivery remains best-effort: successful transcription must still publish `.idle` and keep `mostRecentResult` even if output falls back to clipboard or throws a non-fatal output error.

### New files (explicit Stage 1 list)
- `Sources/SeshatCore/Output/OutputMode.swift`
- `Sources/SeshatCore/Output/OutputTarget.swift`
- `Sources/SeshatCore/Output/OutputDelivery.swift`
- `Sources/SeshatCore/Output/OutputError.swift`
- `Sources/SeshatCore/Output/OutputStreamHandle.swift`
- `Sources/SeshatCore/Output/OutputService.swift`
- `Sources/SeshatAppKit/Output/PasteOutputService.swift`
- `Sources/SeshatAppKit/Output/CopyOutputService.swift`
- `Sources/SeshatAppKit/Output/AppKitOutputService.swift`
- `Sources/SeshatAppKit/Output/StreamingOutputHandle.swift`

### Streaming hook design notes
- The streaming hook is first-class in the public contract now, not a later additive patch. Stage 1 must land `beginStream()` and a concrete handle type even though Stage 2 does not wire a streaming consumer yet.
- The live transport decision remains deferred exactly as the master prompt requires. The plan must carry both options forward: incremental synthetic typing via `CGEvent`, and incremental clipboard updates plus repeated `Cmd+V`.
- Incremental `CGEvent` typing avoids clipboard churn and may produce cleaner "typed text" undo behavior, but it is the riskier Unicode and input-method path and depends more heavily on AX and event-synthesis reliability.
- Repeated clipboard and `Cmd+V` preserves arbitrary Unicode through the pasteboard and reuses existing batch logic, but it churns clipboard state, complicates restore timing, and likely creates chunk-level undo groups.
- The implementation must author `plans/backlog/streaming-output-delivery-mechanism.md` during Stage 1.3. That ticket is the required decision gate before any live streaming consumer is allowed to adopt `beginStream()`.

## Migration of existing call sites
### Stage 1 — Build in parallel
| Stage step | Depends on | Can run in parallel with | Summary |
|---|---|---|---|
| `1.1` | none | layers `1`, `2`, `3`, `4`, `6`, `7`, `8`, `9` Stage 1 | Add `Sources/SeshatCore/Output/*` contracts and core tests only. |
| `1.2` | `1.1` | layers `1`, `2`, `3`, `4`, `6`, `7`, `8`, `9` Stage 1 | Add `PasteOutputService` and `CopyOutputService` in `Sources/SeshatAppKit/Output/*` with wrapper tests; no consumer touches. |
| `1.3` | `1.1`, `1.2` | layers `1`, `2`, `3`, `4`, `6`, `7`, `8`, `9` Stage 1 | Add `AppKitOutputService`, concrete stream handle, and backlog handoff; still no consumer touches. |

### Step 1.1 — Define the core output contracts in new `SeshatCore/Output` files
| Change | Before | After |
|---|---|---|
| Contract ownership | No dedicated output contract in `SeshatCore`; output semantics leak from `PasteInjector` and menu-bar closures. | `SeshatCore` owns the output vocabulary: `OutputMode`, `OutputTarget`, `OutputDelivery`, `OutputError`, `OutputStreamHandle`, and `OutputService`. |
| Batch vs streaming surface | Batch paste exists only as `PasteInjecting.paste(_:)`; streaming has no seam. | One `@MainActor` service exposes `paste(text:)`, `copy(text:)`, and `beginStream()`. |
| Consumer policy | `SeshatPasteMode` only models paste-at-cursor vs clipboard-only. | Layer 5 adds `OutputMode` for consumer policy while still reading the Layer 3-managed paste preferences inside the live paste path. |

#### Files touched (exhaustive) — path:line-range — what changes
- `Sources/SeshatCore/Output/OutputMode.swift:1-20` — add the locked `paste`, `copy`, `both` enum.
- `Sources/SeshatCore/Output/OutputTarget.swift:1-25` — add the internal route enum that replaces `PasteRoutingDecision` after Stage 3.
- `Sources/SeshatCore/Output/OutputDelivery.swift:1-25` — add the internal transport enum with `paste`, `typeEvents`, `clipboardOnly`.
- `Sources/SeshatCore/Output/OutputError.swift:1-40` — add the layer-owned error domain for non-fatal clipboard-only fallback and real failures.
- `Sources/SeshatCore/Output/OutputStreamHandle.swift:1-30` — add the stream-handle contract.
- `Sources/SeshatCore/Output/OutputService.swift:1-30` — add the `@MainActor` `OutputService` protocol with the locked methods.
- `Tests/SeshatCoreTests/Output/OutputContractsTests.swift:1-140` — add contract tests that pin enum cases, protocol surface, and the stream-handle method names.

#### Scope — IN
- Define the public and internal layer vocabulary only.
- Preserve the locked `OutputMode` spelling exactly.
- Reserve the streaming hook now even though no trunk consumer adopts it in Stage 2.

#### Scope — OUT
- No AppKit implementation yet.
- No consumer migration yet.
- No edits outside `Sources/SeshatCore/Output/*` and `Tests/SeshatCoreTests/Output/*`.

#### Acceptance tests — Tests/... — test name + what it asserts + clause it ties to
- `Tests/SeshatCoreTests/Output/OutputContractsTests.swift` — `testOutputModeHasPasteCopyBoth`; ties to `Proposed API / contracts > Types`.
- `Tests/SeshatCoreTests/Output/OutputContractsTests.swift` — `testOutputServiceExposesPasteCopyAndBeginStreamOnly`; ties to `Proposed API / contracts > Protocols`.
- `Tests/SeshatCoreTests/Output/OutputContractsTests.swift` — `testOutputStreamHandleSupportsAppendAndFinalize`; ties to `Streaming hook design notes` bullet 1.

#### Validation checklist (implementer ticks box-by-box)
- [ ] `Sources/SeshatCore/Output/OutputMode.swift:1-20` declares exactly `paste`, `copy`, and `both`, matching `Proposed API / contracts > Types`.
- [ ] `Sources/SeshatCore/Output/OutputService.swift:1-30` exposes `paste(text:) async throws`, `copy(text:) async throws`, and `beginStream() -> any OutputStreamHandle`, matching `Proposed API / contracts > Protocols`.
- [ ] `Sources/SeshatCore/Output/OutputStreamHandle.swift:1-30` keeps `append(_ chunk: String)` and `finalize()`, matching `Streaming hook design notes` bullet 1.
- [ ] `Tests/SeshatCoreTests/Output/OutputContractsTests.swift:1-140` pins the contract without importing AppKit behavior, matching `Test strategy` unit-test bullet 1.
- [ ] The touched surface is limited to `Sources/SeshatCore/Output/OutputMode.swift:1-20`, `Sources/SeshatCore/Output/OutputTarget.swift:1-25`, `Sources/SeshatCore/Output/OutputDelivery.swift:1-25`, `Sources/SeshatCore/Output/OutputError.swift:1-40`, `Sources/SeshatCore/Output/OutputStreamHandle.swift:1-30`, `Sources/SeshatCore/Output/OutputService.swift:1-30`, and `Tests/SeshatCoreTests/Output/OutputContractsTests.swift:1-140`, matching `Stage 1 — Build in parallel`.

### Step 1.2 — Add `PasteOutputService` and `CopyOutputService` in new `SeshatAppKit/Output` files
| Change | Before | After |
|---|---|---|
| Batch paste implementation | `PasteInjector` is the only batch output surface and sits outside a layer contract. | `PasteOutputService` wraps the current `PasteInjector` behavior behind the Layer 5 contract. |
| Clipboard writes | `SeshatAppMain` and `SeshatApp` own raw `NSPasteboard.general` closures. | `CopyOutputService` becomes the only new direct pasteboard writer. |
| Regression coverage | Paste behavior is tested only through `PasteInjectorTests`. | New output tests port those cases to the Layer 5 surface before any consumer swap. |

#### Files touched (exhaustive) — path:line-range — what changes
- `Sources/SeshatAppKit/Output/PasteOutputService.swift:1-180` — add the `PasteInjector` wrapper with the same routing, restore-delay, and AX-prompt behavior.
- `Sources/SeshatAppKit/Output/CopyOutputService.swift:1-60` — add the pasteboard writer wrapper used by `copy(text:)`.
- `Tests/SeshatAppKitTests/Output/PasteOutputServiceTests.swift:1-240` — port the current paste regression cases from `Tests/SeshatAppKitTests/PasteInjectorTests.swift:20-203`.
- `Tests/SeshatAppKitTests/Output/CopyOutputServiceTests.swift:1-120` — add copy-path tests for clipboard writes and empty-input behavior.

#### Scope — IN
- Preserve current batch behavior exactly before any consumer changes.
- Keep `PasteInjector.swift` untouched in Stage 1; the new wrapper lands beside it.
- Make `CopyOutputService` the only new raw pasteboard writer introduced by Layer 5.

#### Scope — OUT
- No edits to `MenuBarSceneModel`, `SeshatAppMain`, `SeshatApp`, or `SessionCoordinator` yet.
- No output-service composition file yet. That is Step 1.3.
- No command-mode wiring yet.

#### Acceptance tests — Tests/... — test name + what it asserts + clause it ties to
- `Tests/SeshatAppKitTests/Output/PasteOutputServiceTests.swift` — `testPromptsAccessibilityWhenNotTrustedAndLeavesTranscriptOnClipboard`; ties to `Sources/SeshatAppKit/Paste/PasteInjector.swift:168-171` and `Why this layer exists` paragraph 2.
- `Tests/SeshatAppKitTests/Output/PasteOutputServiceTests.swift` — `testPasteReturnsClipboardOnlyWhenModeIsClipboardOnly`; ties to `Sources/SeshatCore/SeshatPasteMode.swift:3-27`.
- `Tests/SeshatAppKitTests/Output/PasteOutputServiceTests.swift` — `testPasteReadsRestoreDelayPreferencePerCall`; ties to `Sources/SeshatCore/PasteRestoreDelay.swift:3-62` and `Tests/SeshatAppKitTests/ManualSettingsVerification.md:8-13`.
- `Tests/SeshatAppKitTests/Output/CopyOutputServiceTests.swift` — `testCopyWritesPlainStringToPasteboard`; ties to `Proposed live implementation` paragraph 3.

#### Validation checklist (implementer ticks box-by-box)
- [ ] `Sources/SeshatAppKit/Output/PasteOutputService.swift:1-180` preserves the existing batch routing semantics without modifying `Sources/SeshatAppKit/Paste/PasteInjector.swift:7-227`, matching `Proposed live implementation` paragraph 2 and `Stage 1 — Build in parallel`.
- [ ] `Sources/SeshatAppKit/Output/CopyOutputService.swift:1-60` is the only new direct `NSPasteboard` writer, matching `Proposed live implementation` paragraph 3.
- [ ] `Tests/SeshatAppKitTests/Output/PasteOutputServiceTests.swift:1-240` covers the behaviors currently pinned by `Tests/SeshatAppKitTests/PasteInjectorTests.swift:20-203`, matching `Test strategy` regression-guard bullets.
- [ ] `Tests/SeshatAppKitTests/Output/CopyOutputServiceTests.swift:1-120` proves direct copy behavior without requiring `MenuBarSceneModel`, matching `Stage 1 — Build in parallel`.
- [ ] The touched surface is limited to `Sources/SeshatAppKit/Output/PasteOutputService.swift:1-180`, `Sources/SeshatAppKit/Output/CopyOutputService.swift:1-60`, `Tests/SeshatAppKitTests/Output/PasteOutputServiceTests.swift:1-240`, and `Tests/SeshatAppKitTests/Output/CopyOutputServiceTests.swift:1-120`, matching `Stage 1 — Build in parallel`.

### Step 1.3 — Add the live facade and stream-handle seam without wiring any consumer
| Change | Before | After |
|---|---|---|
| Live service composition | No single live output service exists. | `AppKitOutputService` composes paste, copy, and streaming responsibilities behind one `OutputService`. |
| Streaming hook | No trunk type can consume partial text updates. | `StreamingOutputHandle` exists now and is testable before any streaming transcription slice lands. |
| Transport decision | Transport choice is implicit and untracked. | The refactor carries a concrete backlog ticket and an explicit decision gate. |

#### Files touched (exhaustive) — path:line-range — what changes
- `Sources/SeshatAppKit/Output/AppKitOutputService.swift:1-140` — add the public live `OutputService` conformer that delegates to paste and copy units.
- `Sources/SeshatAppKit/Output/StreamingOutputHandle.swift:1-120` — add the concrete handle implementation and the transport-decision seam.
- `Tests/SeshatAppKitTests/Output/AppKitOutputServiceTests.swift:1-160` — add facade-level tests.
- `Tests/SeshatAppKitTests/Output/StreamingOutputHandleTests.swift:1-180` — add append and finalize sequencing tests and "not wired to a live consumer yet" guards.
- `plans/backlog/streaming-output-delivery-mechanism.md:1-80` — author the required decision ticket comparing incremental `CGEvent` typing vs repeated clipboard and `Cmd+V`.

#### Scope — IN
- Land a concrete live facade in the new `Output/` directory.
- Reserve the live stream handle now.
- Author the backlog ticket during implementation as the transport-decision gate.

#### Scope — OUT
- No modifications to current call sites yet.
- No streaming consumer adoption.
- No silent transport choice; the backlog ticket is mandatory.

#### Acceptance tests — Tests/... — test name + what it asserts + clause it ties to
- `Tests/SeshatAppKitTests/Output/AppKitOutputServiceTests.swift` — `testPasteDelegatesToPasteOutputService`; ties to `Proposed live implementation` paragraph 1.
- `Tests/SeshatAppKitTests/Output/AppKitOutputServiceTests.swift` — `testCopyDelegatesToCopyOutputService`; ties to `Proposed live implementation` paragraph 3.
- `Tests/SeshatAppKitTests/Output/StreamingOutputHandleTests.swift` — `testAppendConsumesPartialChunksInOrderUntilFinalize`; ties to `Streaming hook design notes` bullets 1-4.
- `Tests/SeshatAppKitTests/Output/StreamingOutputHandleTests.swift` — `testLiveStreamPathRequiresBacklogDecisionBeforeConsumerAdoption`; ties to `Streaming hook design notes` bullet 5.

#### Validation checklist (implementer ticks box-by-box)
- [ ] `Sources/SeshatAppKit/Output/AppKitOutputService.swift:1-140` is the only public live conformer, matching `Proposed live implementation` paragraph 1.
- [ ] `Sources/SeshatAppKit/Output/StreamingOutputHandle.swift:1-120` accepts partial chunks before `finalize()`, matching `Streaming hook design notes` bullet 1.
- [ ] `plans/backlog/streaming-output-delivery-mechanism.md:1-80` compares both transport options and records the decision gate, matching `Streaming hook design notes` bullets 2-5.
- [ ] `Tests/SeshatAppKitTests/Output/StreamingOutputHandleTests.swift:1-180` proves append and finalize ordering without wiring a live consumer, matching `Stage 1 — Build in parallel`.
- [ ] The touched surface is limited to `Sources/SeshatAppKit/Output/AppKitOutputService.swift:1-140`, `Sources/SeshatAppKit/Output/StreamingOutputHandle.swift:1-120`, `Tests/SeshatAppKitTests/Output/AppKitOutputServiceTests.swift:1-160`, `Tests/SeshatAppKitTests/Output/StreamingOutputHandleTests.swift:1-180`, and `plans/backlog/streaming-output-delivery-mechanism.md:1-80`, matching `Stage 1 — Build in parallel`.

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
| Future adoption rule | A future output call site could bypass Layer 5. | Any real command-mode output seam must inject `OutputService`, not `PasteOutputService`, `CopyOutputService`, or raw pasteboard writes. |

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
| Legacy `PasteInjectorTests` file | `Tests/SeshatAppKitTests/PasteInjectorTests.swift:1-209` | Coverage has moved to `Tests/SeshatAppKitTests/Output/PasteOutputServiceTests.swift`. |

### Step 3.1 — Delete legacy output surfaces after every consumer has swapped
| Change | Before | After |
|---|---|---|
| Output protocol surface | `PasteInjecting`, `PasteRoutingDecision`, and direct paste closures remain reachable. | Only Layer 5 types remain reachable from production and tests. |
| Clipboard seams | `SeshatAppMain` and `SeshatApp` still carry raw pasteboard helpers. | Only `CopyOutputService` writes to the clipboard from app code. |
| Test surface | Tests still reference the pre-Layer-5 output seam. | Tests use only Layer 5 output fakes and output-specific test files. |

#### Files touched (exhaustive) — path:line-range — what changes
- `Sources/SeshatAppKit/Paste/PasteInjector.swift:1-227` — delete the file once `PasteOutputService` fully owns the behavior.
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
- `Tests/SeshatAppKitTests/Output/PasteOutputServiceTests.swift` — ported batch output coverage remains green after the old file disappears.
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
- Unit tests: add `Tests/SeshatCoreTests/Output/OutputContractsTests.swift` to pin the Layer 5 contract; add `Tests/SeshatAppKitTests/Output/PasteOutputServiceTests.swift`, `Tests/SeshatAppKitTests/Output/CopyOutputServiceTests.swift`, and `Tests/SeshatAppKitTests/Output/StreamingOutputHandleTests.swift` to pin batch and streaming behavior; add `Tests/SeshatSessionTests/SessionCoordinatorOutputTests.swift` to pin the new post-transcript hook.
- Integration tests: update `Tests/SeshatAppKitTests/MenuBarFlowIntegrationTests.swift:17-50,104-140` and `Tests/SeshatAppKitTests/AppEntryPointTests.swift:9-31` so the live composition path uses the new output service.
- Fakes for the new protocols: add `RecordingOutputService`, `ThrowingOutputService`, and `RecordingOutputStreamHandle` test doubles; do not keep `PasteInjecting` fakes after Stage 3.
- Regression guards the layer must preserve: port the current behaviors from `Tests/SeshatAppKitTests/PasteInjectorTests.swift:20-203`; preserve `Tests/SeshatAppKitTests/MenuBarSceneModelTests.swift:264-424` semantics for exactly-once output and missing-transcript no-op; keep `Tests/SeshatAppKitTests/ManualSettingsVerification.md:8-13` and `Tests/SeshatAppKitTests/ManualPillOverlayVerification.md:84-96` current checks live.
- Manual verification additions: extend `Tests/SeshatAppKitTests/ManualPillOverlayVerification.md` with an explicit AX-untrusted clipboard-only fallback case, because the current runbook covers self-frontmost and clipboard-only mode but not the missing-AX route at `Sources/SeshatAppKit/Paste/PasteInjector.swift:168-171`.

## Open design questions (surface — do not resolve)
- [QUESTION] The locked public signature is `paste(text:) async throws`, but the current pill notice path needs to distinguish clipboard-only fallback from a true paste. Should Layer 5 surface that as a handled `OutputError.clipboardOnlyFallback`, or does main-session want a different approved outcome channel before implementation starts?
- [QUESTION] `OutputMode.both` is locked in, but trunk has no current consumer for it. What is the required sequencing and final clipboard state when `both` interacts with `PasteRestoreDelay`?
- [QUESTION] The brief names a `MenuBarSceneModel` "paste-last-transcript" consumer, but trunk only has an unused `copyLatestTranscript()` helper at `Sources/SeshatAppKit/MenuBar/MenuBarSceneModel.swift:120-128` and no status-item dispatch for it in `Sources/SeshatAppKit/MenuBar/StatusItemController.swift:114-130` and `Sources/SeshatAppKit/MenuBar/StatusItemMenuModel.swift:39-45,112-133`. Should Layer 5 swap only the helper, or is a new menu action expected in the same slice?
- [QUESTION] `beginStream()` is locked to exist, but the master prompt leaves the transport choice deferred. Must the first live `beginStream()` implementation stay intentionally unreachable until `plans/backlog/streaming-output-delivery-mechanism.md` is reviewed, or may it ship behind a compile-time or internal decision gate so long as Stage 2 still keeps all consumers batch-only?

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
- `plans/backlog/streaming-output-delivery-mechanism.md` — document incremental `CGEvent` typing vs repeated clipboard and `Cmd+V`, including undo grouping, rate limiting, Unicode fidelity, clipboard churn, and AX or event-synthesis constraints.

## Inter-layer dependencies
- **Requires**: layer `1` because the paste path should consume the centralized permission story instead of keeping raw AX and TCC branching forever.
- **Requires**: layer `3` because the live paste path must read the centralized `PasteMode` and `PasteRestoreDelay` preferences.
- **Blocks**: none inside layers `1`-`9`; the streaming-transcription slice outside this refactor should build on the Stage 1 stream handle instead of inventing a second output seam.

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

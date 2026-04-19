# Layer 5 Stage 1 Code Review

Verdict: NEEDS REVISION

Finding summary: Critical 0, High 2, Medium 2, Low 0.

## Critical
- None.

## High
1. The Stage 1 implementation hardens a public contract that still diverges from the locked master prompt. The master prompt requires `OutputMode` = `.batch` / `.streaming`, `OutputService.deliverBatch(text:) async -> OutputResult`, and concrete `ClipboardBatchOutput` / `StreamedTypingOutput` implementations (`plans/CENTRAL_LAYERS_PROMPT.md:268-276`). Commit `23247a6` instead lands `OutputMode` = `.paste` / `.copy` / `.both`, `OutputService.paste(text:) async throws` plus `copy(text:)`, and `PasteOutputService` / `CopyOutputService` / `AppKitOutputService` (`Sources/SeshatCore/Output/OutputMode.swift:1-4`, `Sources/SeshatCore/Output/OutputService.swift:1-5`, `Sources/SeshatAppKit/Output/PasteOutputService.swift:6-12`, `Sources/SeshatAppKit/Output/CopyOutputService.swift:5-11`, `Sources/SeshatAppKit/Output/AppKitOutputService.swift:6-40`). The prior Layer 5 plan review already flagged this unresolved prompt mismatch (`plans/central/reviews/LAYER_5_review.md:11`), so Stage 1 should not have converted it into live API without an explicit approval path.
2. The previously flagged Layer 5 ↔ Layer 7 ownership conflict is not resolved. Layer 5 exposes streaming through `OutputService.beginStream()` and `OutputStreamHandle` (`Sources/SeshatCore/Output/OutputService.swift:1-5`, `Sources/SeshatCore/Output/OutputStreamHandle.swift:1-5`), while current Layer 7 trunk code delivers output through a separate `PipelineOutputSink` plus `PipelineContextSnapshot.streamingOutputEnabled` (`Sources/SeshatSession/Pipeline/Contracts/PipelineOutputSink.swift:3-6`, `Sources/SeshatSession/Pipeline/Contracts/PipelineContextSnapshot.swift:3-18`, `Sources/SeshatSession/Pipeline/Orchestrator/SessionPipelineOrchestrator.swift:335-343`, `Sources/SeshatSession/Pipeline/Orchestrator/SessionPipelineOrchestrator.swift:367-371`). The defer backlog still leaves the owner open instead of resolving it (`plans/backlog/pipeline-streaming-defer.md:9-24`), and the Layer 7 review called out the same duplication (`plans/central/reviews/LAYER_7_review.md:23`, `plans/central/reviews/LAYER_7_review.md:39`). The result is two competing output surfaces on trunk with no adapter between them.

## Medium
1. `CopyOutputService` can destroy the user’s existing clipboard contents on write failure. It clears the pasteboard before attempting `setString`, then throws if the write fails without restoring the prior contents (`Sources/SeshatAppKit/Output/CopyOutputService.swift:23-30`). The batch paste path explicitly snapshots and restores the clipboard on the equivalent failure (`Sources/SeshatAppKit/Output/PasteOutputService.swift:63-70`). If a manual copy action hits a pasteboard failure, this implementation loses clipboard data instead of leaving the old clipboard intact.
2. The stream-build decision gate is not observable through the public streaming contract. `OutputStreamHandle.finalize()` returns `Void` (`Sources/SeshatCore/Output/OutputStreamHandle.swift:1-5`), and `StreamingOutputHandle.live()` records `.streamingTransportDecisionRequired` only in a concrete-type test hook (`Sources/SeshatAppKit/Output/StreamingOutputHandle.swift:15-18`, `Sources/SeshatAppKit/Output/StreamingOutputHandle.swift:42-54`). Because `AppKitOutputService.beginStream()` returns `any OutputStreamHandle` (`Sources/SeshatAppKit/Output/AppKitOutputService.swift:38-40`), a future caller using only the public protocol cannot detect that the live stream path is intentionally blocked. The current test reaches into `StreamingOutputHandle` internals rather than proving an observable contract-level guard (`Tests/SeshatAppKitTests/Output/StreamingOutputHandleTests.swift:31-42`).

## Low
- None.

## Cross-layer concerns
### Layer 5 ↔ Layer 7 ownership resolution
- Status: unresolved.
- The prior Layer 5 review explicitly flagged that Layer 5 wanted output owned by `SessionCoordinator` while Layer 7 wanted output owned by `SessionPipelineOrchestrator` (`plans/central/reviews/LAYER_5_review.md:37`).
- Current trunk still has both surfaces: Layer 5 owns `OutputService.beginStream()` / `OutputStreamHandle`, while Layer 7 owns `PipelineOutputSink.deliverPartial(_:)` / `deliverFinal(_:)` and `streamingOutputEnabled` gating (`Sources/SeshatCore/Output/OutputService.swift:1-5`, `Sources/SeshatSession/Pipeline/Contracts/PipelineOutputSink.swift:3-6`, `Sources/SeshatSession/Pipeline/Contracts/PipelineContextSnapshot.swift:3-18`).
- The deferral backlog explicitly leaves open whether the streaming sink should live in Layer 5 or Layer 7 (`plans/backlog/pipeline-streaming-defer.md:21-24`).
- Conclusion: the ownership conflict called out in the prior plan review has not been resolved.

### Other cross-layer notes
- Stage 1 scope is respected. Commit `23247a6` changes only the new `Sources/SeshatCore/Output/*`, `Sources/SeshatAppKit/Output/*`, matching test files, and `plans/backlog/streaming-output-delivery-mechanism.md` (`git show --name-only 23247a6^..23247a6`). It does not migrate the existing `PasteInjector` consumers: `MenuBarSceneModel` still owns `clipboardWriter` / `pasteInjector` seams (`Sources/SeshatAppKit/MenuBar/MenuBarSceneModel.swift:13-18`, `Sources/SeshatAppKit/MenuBar/MenuBarSceneModel.swift:120-143`), `SeshatAppMain` still injects raw clipboard and paste closures (`Sources/SeshatAppKit/Composition/SeshatAppMain.swift:23-27`, `Sources/SeshatAppKit/Composition/SeshatAppMain.swift:75-82`, `Sources/SeshatAppKit/Composition/SeshatAppMain.swift:197-200`), `SeshatApp` still carries the raw clipboard writer (`Sources/SeshatAppKit/SeshatApp.swift:15-20`, `Sources/SeshatAppKit/SeshatApp.swift:33-39`, `Sources/SeshatAppKit/SeshatApp.swift:55-60`), and `SessionCoordinator` still has no output hook (`Sources/SeshatSession/SessionCoordinator.swift:198-215`).
- Swift 6 actor / `Sendable` boundaries in this slice look acceptable. The public contracts are `@MainActor`, and the AppKit-facing classes are isolated the same way (`Sources/SeshatCore/Output/OutputService.swift:1-5`, `Sources/SeshatCore/Output/OutputStreamHandle.swift:1-5`, `Sources/SeshatAppKit/Output/AppKitOutputService.swift:6-40`, `Sources/SeshatAppKit/Output/PasteOutputService.swift:6-128`, `Sources/SeshatAppKit/Output/CopyOutputService.swift:5-31`, `Sources/SeshatAppKit/Output/StreamingOutputHandle.swift:4-55`). I did not find a Swift 6 isolation violation in the reviewed commit.

## Test gaps
- `CopyOutputServiceTests` cover only success and empty input, not the write-failure path that currently clears the clipboard before throwing (`Tests/SeshatAppKitTests/Output/CopyOutputServiceTests.swift:12-35`).
- `PasteOutputServiceTests` do not cover the `pasteShortcutPoster == false` branch, even though that branch is part of the clipboard-only fallback behavior (`Sources/SeshatAppKit/Output/PasteOutputService.swift:84-86`).
- `StreamingOutputHandleTests` prove the concrete type records `finalizationError`, but they do not prove that a caller holding only `any OutputStreamHandle` can observe the deferral gate (`Tests/SeshatAppKitTests/Output/StreamingOutputHandleTests.swift:31-42`).

## Summary
- Stage 1 stays within its intended scope and the batch wrapper largely preserves the old paste flow, including restore-delay reads and clipboard save/restore on the paste path.
- The slice still needs revision because it codifies an unapproved master-prompt contract change, the Layer 5 ↔ Layer 7 streaming-output ownership split remains unresolved, `CopyOutputService` can wipe the clipboard on failure, and the stream-build gate is not exposed through the public streaming protocol.

# Layer 5 Stage 1 Re-review

## 1. Verdict on the fix-forward
NEEDS REVISION

`624f91f` fixes all four findings from the original Stage 1 review: the public API is batch-shaped, the Layer 5 streaming handle is gone, and the clipboard-wipe / stream-gate issues are no longer present. I still cannot approve because the same fix-forward only partially rewrote `plans/central/LAYER_5_output.md`; Stage 2 and Stage 3 still instruct follow-on work to use `OutputService.copy(text:)` / `CopyOutputService`, which no longer exist in the reviewed API.

## 2. Per-finding status table

| Original finding | Status | Evidence |
|---|---|---|
| High #1 — API realigned to the reviewed master-prompt shape | Resolved | `624f91f:Sources/SeshatCore/Output/OutputMode.swift:1-4` now declares only `.batch` / `.streaming`; `624f91f:Sources/SeshatCore/Output/OutputService.swift:1-4` exposes only `deliverBatch(text:) async -> OutputResult`; `624f91f:Sources/SeshatCore/Output/OutputResult.swift:1-5` and `624f91f:Sources/SeshatAppKit/Output/ClipboardBatchOutput.swift:8-104` provide the batch result and concrete implementation; `plans/central/LAYER_5_output.md:30-60,84-151` was rewritten to the same batch-oriented surface. |
| High #2 — Streaming surface removed from Layer 5 | Resolved | `624f91f` deletes `Sources/SeshatCore/Output/OutputStreamHandle.swift`, `Sources/SeshatAppKit/Output/StreamingOutputHandle.swift`, and `Sources/SeshatAppKit/Output/AppKitOutputService.swift`; the rewritten plan says Layer 5 does not expose `beginStream()` / `OutputStreamHandle` in Stage 1 at `plans/central/LAYER_5_output.md:58-60,117-118,151,171-172`. |
| Medium #1 — Clipboard wipe on failure | Resolved | The old failing surface was removed in `624f91f:Sources/SeshatAppKit/Output/CopyOutputService.swift`; `ClipboardBatchOutput` now restores saved pasteboard contents before returning `.failed(.clipboardWriteFailed)` at `624f91f:Sources/SeshatAppKit/Output/ClipboardBatchOutput.swift:73-79,132-137`, and the regression is pinned by `624f91f:Tests/SeshatAppKitTests/Output/ClipboardBatchOutputTests.swift:237-265`. |
| Medium #2 — Stream-build gate becomes moot once the public stream surface is removed | Resolved | The public stream-handle path is gone in `624f91f` (deleted `Sources/SeshatCore/Output/OutputStreamHandle.swift` and `Sources/SeshatAppKit/Output/StreamingOutputHandle.swift`), and the defer note now records streaming as out of Layer 5 Stage 1 scope at `plans/central/LAYER_5_output.md:58-60,153-174` and `plans/backlog/pipeline-streaming-defer.md:8-24`. |

## 3. New findings introduced by the fix-forward

- Medium — The plan rewrite is internally inconsistent with the new batch-only API. `624f91f:Sources/SeshatCore/Output/OutputService.swift:1-4` removes `copy(text:)`, but `plans/central/LAYER_5_output.md:174-180,224-259` still tells Stage 2 to migrate `MenuBarSceneModel.copyLatestTranscript()` to `OutputService.copy(text:)`, `plans/central/LAYER_5_output.md:303-313` still says `CopyOutputService` is the only clipboard writer after Stage 2.2, and `plans/central/LAYER_5_output.md:384-387` still recommends Stage 1 commit subjects for “copy output services” and a “streaming seam.” The code is batch-only now, but the plan is no longer executable verbatim.

## 4. Plan file alignment check

Not fully. The Stage 1 API section now matches the batch-oriented shape the re-review was looking for at `plans/central/LAYER_5_output.md:30-60,84-151`, but the document as a whole does not: its own stale-note at `plans/central/LAYER_5_output.md:174` admits later tables were not rewritten, and those later sections still describe removed `copy(text:)`, `CopyOutputService`, and streaming-oriented commit mapping at `plans/central/LAYER_5_output.md:224-259,303-313,384-387`.

## 5. Cross-layer ownership check

Batch ownership is improved enough for this slice. Layer 5 now exposes only the batch service at `624f91f:Sources/SeshatCore/Output/OutputService.swift:1-4`, while the Layer 7 defer note forces production Stage 2 consumers to call only `PipelineOutputSink.deliverFinal(_:)` with `streamingOutputEnabled == false` at `plans/backlog/pipeline-streaming-defer.md:8-12`.

Future streaming ownership is still not finally resolved. Layer 7 still carries `PipelineOutputSink.deliverPartial(_:)` and `PipelineContextSnapshot.streamingOutputEnabled` at `Sources/SeshatSession/Pipeline/Contracts/PipelineOutputSink.swift:3-6` and `Sources/SeshatSession/Pipeline/Contracts/PipelineContextSnapshot.swift:3-19`, and Layer 5 still records the stream-build owner as an open question at `plans/central/LAYER_5_output.md:360`. That is a tracked open design question, not a new Stage 1 regression.

## 6. Stage 2 readiness signal

YES

The actual batch API needed to migrate PasteInjector-owned post-transcript delivery is now small and explicit: `deliverBatch(text:) -> OutputResult` plus `ClipboardBatchOutput` carries target / delivery information without a competing Layer 5 streaming surface (`624f91f:Sources/SeshatCore/Output/OutputService.swift:1-4`; `624f91f:Sources/SeshatAppKit/Output/ClipboardBatchOutput.swift:64-104`). The remaining revision is plan cleanup around the separate dead manual-copy helper, not instability in the PasteInjector migration contract itself.

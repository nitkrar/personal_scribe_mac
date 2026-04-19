# Layer 5 Stage 1 — Re-review (after fix-forward `624f91f`)

> Written by main-session Claude after the worktree re-review agent (afdfb6cf) over-scoped into a 15-min reading phase. Direct inspection of the committed tree took ~3 min for 4 findings.

## Verdict

APPROVED — all 4 findings from `plans/central/reviews/LAYER_5_stage1_code_review.md` are closed.
**Stage 2 readiness**: YES. L5 Stage 2 (PasteInjector consumer swap) may dispatch.

## Per-finding audit

### High #1 — API realigned to master prompt
✅ **Closed**.
- `Sources/SeshatCore/Output/OutputMode.swift` — `case batch`, `case streaming`.
- `Sources/SeshatCore/Output/OutputService.swift` — `func deliverBatch(text: String) async -> OutputResult`.
- `Sources/SeshatAppKit/Output/ClipboardBatchOutput.swift` — renamed from `PasteOutputService`, exposes the new API.
- `Sources/SeshatCore/Output/OutputResult.swift` — `.delivered(target:delivery:)` / `.ignoredEmptyInput` / `.failed(OutputError)` shape per master prompt.

### High #2 — Streaming surface removed from Layer 5
✅ **Closed**.
- No `beginStream()`, `OutputStreamHandle`, `StreamedTypingOutput`, `streamingOutputEnabled` in `Sources/SeshatCore/Output/**` or `Sources/SeshatAppKit/Output/**` (grep returns 0 matches).
- Old files deleted: `AppKitOutputService.swift`, `CopyOutputService.swift`, `StreamingOutputHandle.swift`, `OutputStreamHandle.swift`.
- `OutputMode` retains `case streaming` as a type-level enum case for future use, but no runtime surface — matches the backlog defer note (`plans/backlog/pipeline-streaming-defer.md`).
- Layer 7 remains the sole streaming-owner (its `PipelineOutputSink.deliverPartial` is dormant per the same backlog note).

### Medium #1 — `CopyOutputService` clipboard-wipe on failure
✅ **Closed**.
- `CopyOutputService.swift` deleted entirely.
- Clipboard-only delivery now folded into `ClipboardBatchOutput.swift`: `savePasteboard()` at line 117 + `restorePasteboard()` at line 130. The clipboard-only branch (`pasteMode == .clipboardOnly`, line 106) snapshots existing pasteboard, writes, and restores on failure. No more wipe-on-failure data loss.

### Medium #2 — Stream-build decision gate not observable through public contract
✅ **Moot — surface removed**.
- `OutputStreamHandle.finalize()` deleted. Since there's no public streaming contract in Layer 5 anymore, there's nothing to gate.

## New findings introduced by the fix-forward

None observed.

## Plan file update

`plans/central/LAYER_5_output.md` was updated in the same commit to reflect the master-prompt shape (API section) + notes the streaming deferral pointing at `plans/backlog/pipeline-streaming-defer.md`. Plan ↔ code are in sync.

## Cross-layer ownership check

Layer 5 ↔ Layer 7 streaming-ownership conflict: **resolved**. Layer 5 no longer exposes a streaming surface; Layer 7's `PipelineOutputSink` remains the single streaming contract (dormant pending the stream-build slice).

## Summary

Fix-forward `624f91f` addresses all 4 original findings cleanly, introduces no new issues, keeps Stage 1 scope intact, and brings plan + code into alignment. Stage 2 is unblocked.

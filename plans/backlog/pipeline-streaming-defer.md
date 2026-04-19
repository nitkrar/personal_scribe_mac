# Pipeline streaming output — deferred to stream build

## Status
**Deferred.** Layer 7 Stage 1 (commit `f395327`) introduced streaming-output API (`PipelineOutputSink.deliverPartial(_:)`, `TranscriptProgress`, `PipelineContextSnapshot.streamingOutputEnabled`) per `plans/central/LAYER_7_pipeline.md:9`, which intentionally overrode the finalize-only wording in `plans/CENTRAL_LAYERS_PROMPT.md:334-339`.

User override (2026-04-19): stick to batch behaviour + batch-only public API surface for now. Streaming will be revisited as its own slice ("stream build") where the partial transcript → output path gets end-to-end design (ASR streaming, undo semantics, rate limiting, UI affordances).

## What this means for Stage 2 consumer migration (Layer 7 Stage 2)
- Consumers MUST call only `PipelineOutputSink.deliverFinal(_:)`.
- Consumers MUST NOT call `PipelineOutputSink.deliverPartial(_:)` from production code. Tests may exercise partial delivery in isolation to keep the protocol compiling.
- `PipelineContextSnapshot.streamingOutputEnabled` stays `false` in every production construction site.
- The Layer 7 orchestrator's partial-delivery pathway stays in place but is unreachable from production until the stream-build slice wires it.

## What happens during the stream build
When streaming dictation (FluidAudio `StreamingAsrManager` or successor) lands, this slice:
- Revisits `PipelineOutputSink` surface and decides the partial-delivery contract (undo grouping, rate-limit, EOU semantics).
- Decides `streamingOutputEnabled` ownership — preference? mode property? derived from transcriber capability?
- Wires the partial path end-to-end and writes the integration tests.
- Removes this deferral note once the stream build lands.

## Open questions for the stream build (do NOT resolve now)
- Undo grouping granularity (per-chunk vs per-session).
- Delivery mechanism: CGEvent synthetic keypresses vs incremental Cmd+V. (Already flagged in `plans/backlog/streaming-output-delivery-mechanism.md` from Layer 5 if that file exists.)
- Whether a `StreamingOutputSink` implementation lives alongside `ClipboardBatchOutput` in Layer 5 or is a separate Layer 7 artefact.

## Related
- `plans/central/LAYER_5_output.md` — Output layer (batch) plan.
- `plans/central/LAYER_7_pipeline.md` — Pipeline layer plan; §"Why this layer exists" declares partial-transcript carriage in scope.
- Layer 7 Stage 1 commit: `f395327`.

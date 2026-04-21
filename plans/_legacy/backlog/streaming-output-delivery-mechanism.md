# Streaming Output Delivery Mechanism

## Status
- Stage 1 contract landed.
- Transport decision intentionally deferred.
- No live streaming consumer may adopt `beginStream()` until this ticket is reviewed and closed.

## Context
Layer 5 locks `OutputService.beginStream()` into the public output contract before trunk has a streaming transcript consumer. That keeps the API stable, but it also means the live delivery mechanism must stay behind an explicit decision gate instead of silently inheriting the batch-only paste path.

## Candidate A
### Incremental `CGEvent` typing
- Delivery: synthesize per-chunk typing events directly into the frontmost app.
- Undo grouping: likely produces more natural "typed text" undo behavior than repeated paste, but chunk boundaries and modifier timing still need proof.
- Rate limiting: requires explicit throttling and back-pressure rules so the event tap is not flooded by fast chunk arrival.
- Unicode fidelity: highest risk area. Input methods, composed characters, dead keys, emoji, and non-Latin scripts may not survive key-event synthesis cleanly.
- Clipboard churn: none.
- AX / event constraints: depends heavily on Accessibility trust and event-synthesis reliability for every chunk.

## Candidate B
### Repeated clipboard updates plus synthetic `Cmd+V`
- Delivery: write each chunk to the pasteboard and post `Cmd+V` repeatedly.
- Undo grouping: likely creates chunk-level undo groups unless the destination app coalesces them.
- Rate limiting: still required so pasteboard updates and synthetic pastes do not race each other.
- Unicode fidelity: strongest option because the pasteboard already preserves arbitrary Unicode in the current batch path.
- Clipboard churn: highest risk area. Frequent overwrite and restore behavior could clobber user clipboard history or create visible flicker in clipboard managers.
- AX / event constraints: still requires synthetic paste permission, but reuses the current batch transport instead of inventing a new text-entry path.

## Comparison
| Concern | `CGEvent` typing | Clipboard + `Cmd+V` |
|---|---|---|
| Unicode fidelity | High risk | Low risk |
| Clipboard churn | None | High |
| Undo grouping | Probably better | Probably worse |
| Implementation reuse | Low | High |
| AX dependency | High | High |
| Input-method complexity | High | Low |

## Required Decision Gate
Before any Stage 2 or later consumer adopts `beginStream()`, review must approve:

1. The transport choice: `OutputDelivery.typeEvents` vs chunked paste delivery.
2. The chunk pacing model: max chunk rate, coalescing rules, and final flush behavior.
3. The clipboard restoration policy if chunked paste is chosen.
4. The failure semantics: whether partial delivery should surface as `OutputError.streamingTransportDecisionRequired`, `OutputError.clipboardOnlyFallback`, or a new approved outcome.
5. The verification plan: manual AX-untrusted fallback, Unicode coverage, undo behavior, clipboard restoration, and self-frontmost handling.

## Open Questions
- Can chunked paste ever coexist with `OutputMode.both` without leaving the wrong final clipboard contents behind after restore?
- If synthetic delivery fails mid-stream, should the handle stop immediately, continue buffering, or switch to a clipboard-only terminal fallback?
- Does a streaming path need a dedicated "self frontmost" rule, or is the batch rule sufficient once command-mode consumers arrive?

## Exit Criteria
- A follow-up implementation plan names the approved transport.
- Tests cover chunk ordering, finalize behavior, and the selected failure semantics.
- Manual verification covers Unicode, undo, clipboard restoration, and missing-AX fallback.
- `beginStream()` remains consumer-free on trunk until the decision above is complete.

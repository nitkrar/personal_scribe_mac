# Instrumentation principles

**Status**: ratified 2026-05-24. Applies to all new diagnostic logging in this project (atlas + delegated agents).
**Scope**: file-based diagnostic logs read by users / engineers post-incident. Does not cover Crashlytics-style remote telemetry (we have none).

---

## TL;DR

| Concern | Rule |
|---|---|
| What goes where | Errors → `errors.log` · info/notice → `diagnostics.log` · debug → `debug.log` |
| Retention | `errors.log` + `diagnostics.log`: **14 days** · `debug.log`: **3 days** |
| Frequency budget | A single log line must not exceed **~100 fires per session** — anything higher is debug, not info |
| Summary vs per-event | Prefer one summary log at a boundary (session end, processor completion, state change) over N per-event logs |
| Privacy | Log shapes and counts, never user content |

---

## The three log files

| File | Levels routed here | Retention | Rotation |
|---|---|---|---|
| `errors.log` | `.error` only | 14 days | Daily at local midnight (or first launch after midnight) |
| `diagnostics.log` | `.info` + `.notice` (NOT debug) | 14 days | Same as above |
| `debug.log` | `.debug` only | 3 days | Same as above |

Path: `~/Library/Application Support/personal_scribe/logs/`

Rationale:
- **errors.log** stays small (small per-file budget) so post-incident review starts with real failures, not noise. Today's count: 4 entries.
- **diagnostics.log** is the production signal — recipe choices, session lifecycle, summaries. Stays grep-able for typical users.
- **debug.log** is per-engineer-investigation noise — buffer-level loops, per-chunk traces, manager-callback floods. 3-day retention because debug bursts are episodic; we never want 14 days of per-buffer logs taking 400 MB of disk.

---

## The 11 principles

### 1. Prefer summary-at-boundary over per-event logs

Log once at a natural session boundary (session start, session end, processor completion, state transition) carrying **aggregated counts**, not once per buffer / chunk / sample.

```swift
// Good — one log per session
logger.info("streaming_adapter_summary — buffers=\(n) partialCallbacks=\(p) eouCallbacks=\(e) finalTextChars=\(c)")

// Bad — per-buffer info log
logger.info("processed buffer \(idx) frameCount=\(buf.frameCount)")  // would be ~4/sec during recording
```

### 2. Log absences as much as presences

If a path can fail silently, the success path also needs a log. "X didn't happen" is invisible if only the failure branch logs. Symmetric coverage is what makes silent-failure debuggable later.

### 3. Carry just enough data to localize, not reproduce

Counts and shapes (`partialCallbacks=12 partialEmpty=12`), not payloads (`partial text="hello world"`). Smaller log files, privacy-by-construction, better signal-to-noise.

### 4. Tag with session/recipe ID when present

Lets engineers grep one session out of a noisy log. Existing pattern: `streaming_session_summary session=<uuid>`. New logs in the streaming/pipeline path should inherit `StreamingDiagnosticsSession.current?.sessionID`.

### 5. Audit existing high-frequency logs before adding new ones

Before adding a log near a noisy area, count current fire rate. Don't add neighbors to high-frequency lines (current top: `PillOverlayPresenter visibility-sink` at ~135/file). New logs should stay clear of those rate clusters.

### 6. Errors go to errors.log; everything else to diagnostics.log or debug.log

This is enforced by the sink contracts:
- `ErrorFileDiagnosticsSink` accepts only `.error` events
- `VerboseFileDiagnosticsSink` accepts `.info` + `.notice` only (NOT `.error`, NOT `.debug`)
- `DebugFileDiagnosticsSink` accepts only `.debug`

### 7. Never log inside hot loops at info level

Anything that fires inside an audio-buffer loop, per-chunk processing path, per-render frame, per-keystroke handler, etc. is **debug**, never info. Hot-loop logs must use `.debug` so they're filtered out of production files.

If you're not sure whether a path is hot:
- During a typical 30s recording session, count: ~4 audio buffers/sec → ~120 buffers
- Multiplied across all callsites in the loop: easily hundreds per session
- That's debug territory by default

### 8. Per-log-line budget: ~100 fires per session max

Quantitative discipline:
- A log line that fires more than ~100x per session is wrong for `.info` — make it `.debug`, OR add a counter-gate (log every Nth call), OR aggregate into a session-end summary
- Exception: state-change-bounded logs (fire once per actual transition) are OK even if the underlying event is high-frequency (because the gate IS the transition)

### 9. Match existing logger surface, don't invent new ones

Use existing categories:
- `PersonalScribeLogCategory.transcription` — adapter / manager / chunk-level
- `PersonalScribeLogCategory.session` — orchestrator / session lifecycle / pipeline
- `PersonalScribeLogCategory.ui` — overlay / status item / SwiftUI render
- `PersonalScribeLogCategory.app` — composition / startup / maintenance

Don't add new categories without explicit justification. Downstream filtering and retention settings are keyed on categories.

### 10. Log level discipline

- `info` — production signal anyone reading `diagnostics.log` cares about. Session start, recipe decisions, summary counts.
- `notice` — rarely used; reserved for "default-on-but-rare" signal (e.g. fallback path taken, migration ran). Currently lives in diagnostics.log alongside info.
- `error` — only things that warrant `errors.log` + `operationObserver.record(.failed)`. Real failures, not expected lifecycle (e.g. `CancellationError` is NOT an error — fix `cf4d184`).
- `debug` — anything inside a loop, per-buffer, per-chunk, per-frame, per-keystroke. Bursty investigation traces. Per-callback floods. Goes to `debug.log` with 3-day retention.

### 11. Avoid temporary-debug logs in production-level files

If you add a temporary debug log during a bug hunt:
- Use `.debug` level so it lands in `debug.log` (3-day retention, lower stakes)
- If you genuinely need it at `.info` for a few releases (rare), mark it `// TEMP-DIAG <ticket>:` with a removal trigger (ticket close, commit hash, etc.)
- Clean up when the trigger fires. The `9eba15e` aftermath had several `TEMP-DIAG #056-vad-bug` lines that lingered after the bug was closed.

### 12. Don't log user-typed content

Don't log clipboard contents, transcript text, audio buffer values, dictation utterances, mode picker choices that include user input, etc. Privacy-by-construction:
- Log `chars=<n>` not the text
- Log `utteranceCount=<n>` not the utterances
- Log enum tags (`event=speechStart`) not the data feeding the decision
- The `PIIRedactor` exists for defense-in-depth, but the first line of defense is "don't put PII in the log in the first place"

---

## How to enforce

- **Review gate** (atlas, manual): every new log line is reviewed against principles 1, 7, 8, 10, 12 before commit. Single-line PRs are fine — the principle review is fast.
- **Hermes briefs**: when delegating instrumentation work, the brief MUST include "follow `docs/INSTRUMENTATION_PRINCIPLES.md`" and call out the per-log-line budget.
- **Self-check before commit**: "If this fires every audio buffer, is it `.debug`?" "If this is `.info`, will it produce more than ~100 lines per session?"

---

## What's NOT enforced (yet)

- No automated lint / build check for log-level discipline (would need to AST-parse the logger surface and count callsites in known hot paths). Could be added later if violations recur.
- No per-file size cap or alerting. Daily rotation + 14d / 3d retention is the only quantitative gate.

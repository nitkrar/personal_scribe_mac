# Diagnostics System — Design Notes

Design note for the 2026-04-30 discussion about consolidating error logging and on-disk reporting into one structured diagnostics system.

This is an architecture note, not an implementation plan. It records the ask, the follow-up decisions, and the target model for future refactors.

Implementation plan: `plans/diagnostics-system-implementation.md`

---

## Why this exists

Ninimma currently has two adjacent diagnostics mechanisms:

- `Sources/PersonalScribeCore/Logger.swift`
  `PersonalScribeLogger` wraps `os.Logger` for `debug / info / error`.
- `Sources/PersonalScribeCore/SessionErrorReporter.swift`
  `SessionErrorReporter` writes structured session failures to `logs/errors.log` and returns `ReportedError` for the response-card path.

That split is workable for the immediate error-display fix, but it is not the right long-term architecture. We want one diagnostics system with one event model, while still keeping user-facing response-card policy separate from generic logging.

---

## User ask and follow-ups

### Original ask

> yes to consolidating logger + file reporter into one structured diagnostics system

### Follow-up decisions from the discussion

1. Do **not** make the generic logger directly own ResponseCard behavior.
2. Avoid inventing a second subsystem or a parallel API like `errorWithUserReport(...)`.
3. Add debug logging controls to **Advanced settings**.
4. Support a way to see live diagnostics on screen while the app is running, but do that through a dedicated debug surface, not the normal user-facing ResponseCard.

---

## Locked decisions

### D1 — One diagnostics system, one event model

The target architecture is a single diagnostics system that emits one structured event type and fans it out to multiple sinks:

- macOS `os.Logger`
- on-disk log file(s)
- optional in-memory ring buffer for debug UI

There should not be two unrelated systems where "logger" means OSLog and "reporter" means file + user-facing payload.

### D2 — User-facing reporting is metadata on the event, not a second API

We do **not** want two primary error methods such as:

- `error(...)`
- `errorWithUserReport(...)`

Instead, one diagnostics API should accept optional user-facing metadata.

Example shape:

```swift
diagnostics.error(
    "Post-processing failed",
    error: error,
    category: .session,
    metadata: ["stage": "postProcessing"],
    userFacing: .sessionError(mapped: .transcriptionFailure)
)
```

Most call sites will pass `userFacing: nil`.

### D3 — Diagnostics emission and UI presentation remain separate

The diagnostics system should **not** reach into AppKit and show a ResponseCard by itself.

Instead:

- the diagnostics system emits an event
- interested consumers decide whether to surface it
- the session pipeline / snapshot layer remains responsible for converting relevant diagnostics into `SessionSnapshot.reportedError`
- the ResponseCard remains one consumer of that snapshot payload

This preserves a clean boundary between:

- observability
- state propagation
- UI presentation policy

### D4 — Error file logging stays on by default

The user-facing settings must **not** disable error logging.

At minimum:

- error-level diagnostics always go to disk
- error-level diagnostics always go to OSLog

Settings may widen capture to `debug / info / notice`, but they should not turn off error persistence.

### D5 — Advanced settings own verbose logging and live diagnostics

The debug controls belong in **Advanced settings**, not in normal output settings and not in the ResponseCard surface.

Proposed controls:

- `Diagnostic Logging`
  - `Errors Only` (default)
  - `Verbose`
- `Show Live Diagnostics Overlay`
  - off by default
  - only enabled when `Diagnostic Logging = Verbose`

The live diagnostics surface should be a dedicated debug overlay/panel, not the normal response card.

### D6 — Module boundaries

- `DiagnosticsReporter`, `DiagnosticsEvent`, `DiagnosticsSink`,
  `DiagnosticsLevel`, `UserFacingDiagnostic`, and `PIIRedactor` live in
  `PersonalScribeCore`.
- The live diagnostics overlay UI lives in `PersonalScribeAppKit` and
  consumes a public Core diagnostics store/ring buffer API.
- Core never imports AppKit. The diagnostics layer does not reach into
  UI components directly.

### D7 — Reporter is injected, not a singleton

`DiagnosticsReporter` is constructed at app boot in `AppComposition`
with the production sinks and passed through the existing DI chain.
Tests inject a reporter configured with test sinks. There is no
`Diagnostics.shared`. Compatibility wrappers such as
`PersonalScribeLogger` must also receive the reporter through
construction; they do not discover it through hidden global state.

---

## Non-goals

- Do not make every `logger.error(...)` user-visible.
- Do not reuse the ResponseCard as a scrolling live debug console.
- Do not couple general diagnostics emission to AppKit imports.
- Do not introduce a second permanently-supported API just to handle user-facing errors.

---

## Proposed model

### Event type

Target a single structured event model, roughly:

```swift
public struct DiagnosticsEvent: Sendable {
    public let level: DiagnosticsLevel
    public let category: String
    public let message: String
    public let timestamp: Date
    public let underlyingError: (any Error & Sendable)?
    public let metadata: [String: String]
    public let userFacing: UserFacingDiagnostic?
}
```

Supporting types:

```swift
public enum DiagnosticsLevel: String, Sendable, Equatable {
    case debug
    case info
    case notice
    case error
}

public enum UserFacingDiagnostic: Sendable, Equatable {
    case sessionError(
        mapped: PersonalScribeError,
        messageOverride: String? = nil,
        autoDismissAfter: TimeInterval = 4.0
    )
}
```

Notes:

- `category` can continue using the existing string constants from `PersonalScribeLogCategory`.
- `underlyingError` stays typed until sink render time so sinks can
  apply consistent redaction and formatting rules.
- `message` must not contain user-controlled content. Free-form user
  content belongs only in metadata fields that are explicitly safe to
  persist after redaction.
- `userFacing` remains optional and explicit.

### Reporter API

One diagnostics reporter should own event creation and fan-out.

Illustrative shape:

```swift
public struct DiagnosticsReporter: Sendable {
    public func debug(
        _ message: String,
        category: String,
        metadata: [String: String] = [:]
    )

    public func info(
        _ message: String,
        category: String,
        metadata: [String: String] = [:]
    )

    public func notice(
        _ message: String,
        category: String,
        metadata: [String: String] = [:]
    )

    @discardableResult
    public func error(
        _ message: String,
        error: (any Error)? = nil,
        category: String,
        metadata: [String: String] = [:],
        userFacing: UserFacingDiagnostic? = nil,
        file: StaticString = #fileID,
        function: StaticString = #function,
        line: UInt = #line
    ) -> DiagnosticsEvent
}
```

This gives us one method family, not separate systems.

---

## Sink model

The reporter should emit to multiple sinks.

### S1 — OSLog sink

This replaces the direct specialness of `PersonalScribeLogger`.

- still writes to `os.Logger`
- still uses existing subsystem/category vocabulary
- now receives a normalized `DiagnosticsEvent`

`PersonalScribeLogger` may remain as a thin compatibility wrapper over
`DiagnosticsReporter` for existing `logger.debug/info/error(...)` call
sites, but only if it is constructed with an injected reporter.

Not allowed:

- a bare `init(category:)` that finds the reporter through global state
- a static shared reporter hidden behind the logger facade

### S2 — File sinks (two)

The structured file sinks replace the current special-case ownership of
`SessionErrorReporter`.

Requirements:

- error-level events always write to disk
- rotation remains bounded
- line format stays plain text and grep-friendly

- `ErrorFileSink` writes error-level events to `logs/errors.log`.
  Always on, regardless of verbosity setting.
- `VerboseFileSink` writes `debug / info / notice` events to
  `logs/diagnostics.log` when `Diagnostic Logging = Verbose`.
  Error-level events stay in `errors.log` only and are not duplicated.

Each file rotates independently with a 1 MB cap and head truncation.

### S3 — In-memory ring buffer

The live diagnostics overlay should not tail files directly.

Instead, the diagnostics system should keep a bounded in-memory buffer, for example:

- last 200 events
- newest first
- filtered by current verbosity setting

This buffer becomes the data source for the Advanced-settings debug overlay/panel.

---

## UI routing policy

This is the critical boundary.

### What the diagnostics system does

- emits structured events
- writes to OSLog
- writes to file
- optionally stores recent events in memory

### What the diagnostics system does **not** do

- directly show ResponseCards
- directly mutate `SessionState`
- directly push UI overlays

### How ResponseCard fits

For session failures:

1. session code emits a diagnostics error with `userFacing: .sessionError(...)`
2. session/orchestrator code derives or forwards `ReportedError`
3. `SessionSnapshot.reportedError` carries the payload
4. ResponseCard reads `reportedError`

That keeps the diagnostics system general-purpose while preserving the existing snapshot-driven UI architecture.

---

## Relationship to the current implementation

The current `SessionErrorReporter` work is a valid intermediate step, not throwaway work.

It already proved three important pieces:

- structured file logging is useful
- response-card copy should come from a richer payload than raw `errorDescription`
- pill error UI should not own the main failure message

The next consolidation step should absorb that design into the broader diagnostics model, rather than reintroducing two independent mechanisms.

### Immediate migration target

The next refactor should fold these concepts together:

- `PersonalScribeLogger`
- `SessionErrorReporter`
- `ReportedError` generation for session failures

### Call sites that should eventually join the same diagnostics system

These currently log real failures without going through the session reporter path:

- `Sources/PersonalScribeAppKit/MenuBar/MenuBarSceneModel.swift`
  post-session output delivery failures
- `Sources/PersonalScribeSession/SessionCoordinator.swift`
  transcript repository append failures
- `Sources/PersonalScribeSession/Pipeline/Orchestrator/SessionPipelineOrchestrator.swift`
  background prepare/prewarm failures

Those should all emit through the same diagnostics reporter, even if they remain non-user-facing.

---

## Advanced settings design

### Setting 1 — Diagnostic Logging

Location:

- `Advanced` settings tab

Values:

- `Errors Only` default
- `Verbose`

Behavior:

- `Errors Only`
  - error events go to OSLog
  - error events go to `logs/errors.log`
  - in-memory buffer may keep errors only
- `Verbose`
  - error events still go everywhere above
  - debug/info/notice events also flow to the in-memory buffer
  - debug/info/notice events also go to `logs/diagnostics.log`

### Setting 2 — Show Live Diagnostics Overlay

Location:

- `Advanced` settings tab

Behavior:

- disabled unless `Diagnostic Logging = Verbose`
- shows a dedicated live debug surface
- intended for local debugging and dogfooding, not normal end-user UX

Suggested content:

- timestamp
- level
- category
- message
- key metadata like stage, mode, output target

Notably absent:

- no use of the normal ResponseCard component
- no auto-paste of diagnostic text

---

## Recommended migration shape

### Phase 1 — Core diagnostics model

- introduce `DiagnosticsEvent`
- introduce `DiagnosticsReporter`
- introduce sink protocol + OSLog/file/in-memory sinks
- introduce `PIIRedactor`
- keep `errors.log` contract intact

### Phase 2 — Session-error integration

- migrate `SessionErrorReporter` semantics into the new diagnostics reporter
- keep `SessionSnapshot.reportedError`
- keep ResponseCard routing explicit in session/UI layers

### Phase 3 — Remaining blind spots

- move post-session output delivery failures onto the same diagnostics reporter
- move transcript persistence fallback logging onto the same diagnostics reporter
- move background prepare/prewarm failures onto the same diagnostics reporter

### Phase 4 — Advanced settings + live diagnostics UI

- add `Diagnostic Logging` setting
- add `Show Live Diagnostics Overlay`
- wire the overlay to the in-memory buffer

---

## PII redaction

The diagnostics system can leak content if metadata or rendered errors
contain user-controlled values. Concrete risk sources include:

1. transcript content or user-supplied prompt text
2. filesystem paths under `/Users/<name>/...`
3. device names like `John's AirPods Pro`
4. future app/window focus titles captured during output routing
5. recording filenames and timestamps that can identify the user

### v1 redaction rules

- Always-safe metadata keys:
  `level`, `category`, `mappedError`, `stage`, `mode`,
  `descriptorID`, `pipelineShape`, `errorType`.
- Always-redacted metadata keys:
  keys matching
  `transcript|path|deviceName|windowTitle|appName|audioFile|userMessage`.
  Preserve the key, replace the value with `<redacted>`.
- Value-pattern redaction:
  `/Users/[^/]+` becomes `/Users/<redacted>`.
- `underlyingError` is never rendered with `String(describing: error)`
  by default. Sinks render only the error type and case name unless a
  call site explicitly opts into a safe custom detail field.
- `message` must not contain user content.

A `PIIRedactor` applies these rules at the sink boundary before
human-readable serialization or append.

## Open implementation questions

These are follow-up questions, not blockers for the architectural direction.

1. Should the live diagnostics surface be a floating panel, a unified-window debug pane, or both?
2. Which non-session errors, if any, should ever attach `userFacing` metadata?
3. How aggressively should the in-memory ring buffer truncate very large but otherwise safe metadata values?

---

## Bottom line

The right end state is:

- one diagnostics system
- one shared event model
- multiple sinks
- optional user-facing metadata on the event
- ResponseCard policy kept outside the generic logger
- Advanced settings control verbose/debug visibility, not whether errors are persisted

That satisfies the original ask without creating a second long-term "special error reporter" API.

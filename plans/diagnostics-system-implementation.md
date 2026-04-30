# Diagnostics System — Implementation Plan

Execution plan for `plans/diagnostics-system-design.md`.

This plan is intentionally more concrete than the design note: it names the migration order, likely file touch points, test expectations, and the point at which the current split (`PersonalScribeLogger` + `SessionErrorReporter`) is considered fully consolidated.

The stages below are execution order inside one refactor branch, not
incremental release checkpoints. The migration lands as one commit
after full verification.

---

## Goal

Move Ninimma to one structured diagnostics backend that:

- emits one shared event model
- writes error diagnostics to `logs/errors.log`
- routes all existing `PersonalScribeLogger` traffic through that backend
- still allows only explicitly-marked events to become user-facing response-card errors
- adds Advanced-settings controls for verbose diagnostics and a live diagnostics overlay

This is **not** a request to make every error user-visible. UI policy stays separate.

---

## Current baseline

As of the current repo state:

- `Sources/PersonalScribeCore/Logger.swift`
  still exposes `PersonalScribeLogger`
- `Sources/PersonalScribeCore/SessionErrorReporter.swift`
  exists and is already used for session-failure file logging + `ReportedError`
- `Sources/PersonalScribeCore/SessionSnapshot.swift`
  already carries `reportedError`
- the pill no longer owns the main error message; the ResponseCard does

So this ticket is a **consolidation refactor**, not a greenfield build.

---

## Constraints

### C1 — Keep user-facing routing explicit

The generic diagnostics backend must not show the ResponseCard directly.

Allowed:

- diagnostics event carries optional `userFacing` metadata
- session/UI layers convert that metadata into `SessionSnapshot.reportedError`

Not allowed:

- `DiagnosticsReporter` importing AppKit or mutating UI state

### C2 — Preserve the `errors.log` contract

Error diagnostics must continue to land at:

- `<base dir>/logs/errors.log`

That path is already useful for real debugging and should remain stable.

### C3 — Do not break current logger call sites during the migration

There are many existing `logger.debug/info/error(...)` call sites across `Core`, `Session`, and `AppKit`. The migration should preserve the public `PersonalScribeLogger` call surface until the backend cutover is complete.

This constraint applies to call semantics, not construction semantics.
Logger construction sites may change so the underlying
`DiagnosticsReporter` is injected explicitly.

### C4 — Keep `SessionSnapshot.reportedError`

The snapshot-level payload is already the right UI seam. Do not replace it with direct UI calls from the diagnostics layer.

### C5 — TDD where logic is testable

Per repo policy:

- new diagnostics core logic gets failing unit tests first
- UI-only overlay work gets the maximum testable presenter/store coverage plus manual verification notes

---

## Proposed rollout

Six implementation stages. These stages define sequencing only; they
do not imply staged merges or staged shipping.

### Stage A — Core diagnostics primitives

Add a new `PersonalScribeCore/Diagnostics/` group with the shared event model and sink interfaces.

#### New files

- `Sources/PersonalScribeCore/Diagnostics/DiagnosticsLevel.swift`
- `Sources/PersonalScribeCore/Diagnostics/DiagnosticsEvent.swift`
- `Sources/PersonalScribeCore/Diagnostics/UserFacingDiagnostic.swift`
- `Sources/PersonalScribeCore/Diagnostics/DiagnosticsSink.swift`
- `Sources/PersonalScribeCore/Diagnostics/DiagnosticsReporter.swift`
- `Sources/PersonalScribeCore/Diagnostics/DiagnosticsStore.swift`
- `Sources/PersonalScribeCore/Diagnostics/PIIRedactor.swift`
- `Sources/PersonalScribeCore/Diagnostics/VerboseFileDiagnosticsSink.swift`
- `Sources/PersonalScribeCore/Diagnostics/InMemoryTestSink.swift`

#### Exact work

**A.1** Define:

- `DiagnosticsLevel`
- `DiagnosticsEvent`
- `UserFacingDiagnostic`

Keep the event model close to the design note:

- `level`
- `category`
- `message`
- `timestamp`
- `underlyingError`
- `metadata`
- `userFacing`

**A.2** Add sink protocols / implementations:

- `OSLogDiagnosticsSink`
- `ErrorFileDiagnosticsSink`
- `VerboseFileDiagnosticsSink`
- `RingBufferDiagnosticsSink`
- `InMemoryTestSink`

**A.3** Add a bounded in-memory store for live diagnostics.

Requirements:

- ring buffer, e.g. 200 events
- newest-first retrieval or ordered append with cheap snapshot reads
- actor-backed for thread safety

**A.4** Build `DiagnosticsReporter` as the single event-emission entry point.

Methods:

- `debug`
- `info`
- `notice`
- `error`

`error(...)` returns the emitted `DiagnosticsEvent`.

**A.5** Sink registration + file policy:

- `DiagnosticsReporter` is constructed in `AppComposition` with sinks
  injected. There is no singleton reporter.
- Error-level events write to `logs/errors.log` via
  `ErrorFileDiagnosticsSink`. Always on.
- When `Diagnostic Logging = Verbose`, `debug / info / notice` events
  also write to `logs/diagnostics.log` via
  `VerboseFileDiagnosticsSink`.
- Error-level events are not duplicated into `diagnostics.log`; they
  live in `errors.log` only.
- All events flow to OSLog. The ring buffer receives events according
  to the current verbosity filter.
- `PIIRedactor` is applied before any sink renders or stores
  human-readable event content.

**A.6** Add `PIIRedactor.swift`.

Implement the v1 whitelist and value-pattern rules from the design
doc. File sinks, the ring-buffer sink, and any string-form OSLog
rendering use the redacted view of the event.

**A.7** Add `InMemoryTestSink` as a first-class test sink.

The production ring buffer remains bounded and optimized for UI
consumption. The test sink stays ordered and unbounded for assertion
ergonomics.

#### Tests

Add:

- `Tests/PersonalScribeCoreTests/Diagnostics/DiagnosticsReporterTests.swift`
- `Tests/PersonalScribeCoreTests/Diagnostics/ErrorFileDiagnosticsSinkTests.swift`
- `Tests/PersonalScribeCoreTests/Diagnostics/VerboseFileDiagnosticsSinkTests.swift`
- `Tests/PersonalScribeCoreTests/Diagnostics/InMemoryDiagnosticsSinkTests.swift`
- `Tests/PersonalScribeCoreTests/Diagnostics/PIIRedactorTests.swift`

Pin:

- sink fan-out
- `errors.log` persistence
- verbose file enable/disable behavior
- no duplication of error events into `diagnostics.log`
- metadata rendering
- redaction of sensitive keys and `/Users/<name>` path segments
- safe rendering of `underlyingError`
- ring-buffer truncation
- test assertions via `InMemoryTestSink`

---

### Stage B — Cut over `PersonalScribeLogger` and retire the backend split

This is the key consolidation step.

#### Existing files

- `Sources/PersonalScribeCore/Logger.swift`
- `Sources/PersonalScribeCore/SessionErrorReporter.swift`

#### Exact work

**B.1** Reimplement `PersonalScribeLogger` as a thin injected facade
over `DiagnosticsReporter`.

The public API stays source-compatible:

- `debug(...)`
- `info(...)`
- `error(...)`

But under the hood it now emits `DiagnosticsEvent`s through the shared reporter and sinks.

This unifies the existing logger call sites without mechanical churn
across `Sources/`.

Required shape:

- store `category`
- store injected `DiagnosticsReporter`
- remove any logger initializer that can manufacture or discover a
  reporter implicitly

Allowed:

- `PersonalScribeLogger(category: ..., reporter: diagnostics)`

Not allowed:

- `PersonalScribeLogger(category: ...)` if it reaches for a hidden
  shared reporter

**B.2** Keep `PersonalScribeLogCategory` unchanged.

Do not churn category names in this ticket.

**B.3** Delete `SessionErrorReporter`.

Session code migrates directly to
`DiagnosticsReporter.error(... userFacing: ...)` or to local helpers
that wrap that API. There is no second reporting backend after this
migration.

**B.4** Re-home the current `ReportedError` creation logic.

Use one helper such as:

- `ReportedError.init?(event: DiagnosticsEvent)`

or

- `DiagnosticsEvent.reportedErrorPayload`

This keeps the session/UI layer explicit without preserving a separate reporting system.

**B.5** Do not mechanically rewrite every existing `logger.debug/info/error`
call site in this migration.

Retaining `PersonalScribeLogger` as a compatibility facade is an
intentional API choice, not a second backend. Backend consolidation is
complete once the facade routes into `DiagnosticsReporter` and
`SessionErrorReporter` is gone.

Do rewrite:

- constructor injection sites
- default logger arguments that currently allocate a logger internally
- static/file-local loggers that cannot receive DI cleanly

Those sites should either take an injected `PersonalScribeLogger` or
take `DiagnosticsReporter` directly and bind the category locally.

#### Tests

Update:

- `Tests/PersonalScribeCoreTests/PersonalScribeLoggerTests.swift`
- replace `Tests/PersonalScribeCoreTests/SessionErrorReporterTests.swift`
  with `DiagnosticsReporter` coverage that asserts the same
  `errors.log` contract and `ReportedError` mapping

---

### Stage C — Session failure path migration

This stage preserves the current user-facing behavior while switching the backend to the unified diagnostics system.

#### Existing files

- `Sources/PersonalScribeCore/SessionSnapshot.swift`
- `Sources/PersonalScribeSession/Pipeline/Contracts/PipelineStageFailure.swift`
- `Sources/PersonalScribeSession/Pipeline/Orchestrator/SessionPipelineOrchestrator.swift`
- `Sources/PersonalScribeAppKit/Overlay/RecordingStatusCardDriver.swift`
- `Sources/PersonalScribeAppKit/Overlay/PillOverlayController.swift`

#### Exact work

**C.1** In orchestrator failure sites, emit diagnostics via:

```swift
diagnostics.error(
    "Post-processing failed",
    error: error,
    category: PersonalScribeLogCategory.session,
    metadata: ["stage": "postProcessing"],
    userFacing: .sessionError(mapped: .transcriptionFailure)
)
```

**C.2** Convert the event’s `userFacing` payload into `ReportedError` at the snapshot seam.

Keep:

- `SessionSnapshot.reportedError`

Do not move ResponseCard logic into the diagnostics backend.

**C.3** Keep `PipelineStageFailure` focused on stage/mapped error/detail.

Avoid turning it into a second diagnostics object. If carrying a temporary `ReportedError?` or `DiagnosticsEvent?` materially reduces duplicate work, that is acceptable, but the file should not become the long-term diagnostics model.

**C.4** Preserve current UI semantics:

- pill stays on idle/hidden fallback
- ResponseCard uses `reportedError`
- error card auto-dismisses after ~4s

#### Tests

Update or retain green:

- `Tests/PersonalScribeSessionTests/Pipeline/SessionPipelineOrchestratorTests.swift`
- `Tests/PersonalScribeAppKitTests/Overlay/RecordingStatusCardDriverTests.swift`
- `Tests/PersonalScribeCoreTests/AppStore/AppStoreTests.swift`

Key assertions:

- a session failure produces an error log line
- a session failure produces a `ReportedError`
- the pill still does **not** surface an error chip

---

### Stage D — Migrate non-session operational failures onto the same backend

This stage closes the current blind spots where failures are logged but not flowing through the same structured event backend.

#### Existing files

- `Sources/PersonalScribeAppKit/MenuBar/MenuBarSceneModel.swift`
- `Sources/PersonalScribeSession/SessionCoordinator.swift`
- `Sources/PersonalScribeSession/Pipeline/Orchestrator/SessionPipelineOrchestrator.swift`
- plus any other `logger.error(...)` sites worth attaching metadata to

#### Exact work

Because `PersonalScribeLogger` is already routed through `DiagnosticsReporter` after Stage B, most call sites will be unified automatically. This stage is about enriching the highest-value failures with useful metadata.

**D.1** `MenuBarSceneModel` output delivery failure:

- keep `userFacing: nil`
- add metadata like `deliveryPhase=postSession` and output target if available

**D.2** `SessionCoordinator` transcript persistence fallback:

- keep `userFacing: nil`
- add metadata like `persistenceTarget=TranscriptRepository`

**D.3** Background prepare/prewarm failure:

- keep `userFacing: nil`
- add metadata like `preparePhase=background`

#### Tests

Add focused coverage only where the metadata is mechanically testable. Do not overfit unit tests to log formatting beyond what the sink contract guarantees.

---

### Stage E — Advanced settings for diagnostics

This stage adds the user-visible controls requested in the follow-up discussion.

#### New or updated files

- `Sources/PersonalScribeCore/Preferences/PreferenceKeys.swift`
- `Sources/PersonalScribeCore/Preferences/` new diagnostics preference types
- `Sources/PersonalScribeAppKit/Settings/AdvancedTab.swift`
- `Sources/PersonalScribeAppKit/Composition/AppComposition.swift`

#### Exact work

**E.1** Add a new core preference enum:

```swift
public enum DiagnosticLoggingMode: String, CaseIterable, Sendable {
    case errorsOnly
    case verbose
}
```

**E.2** Add a bool preference:

- `showLiveDiagnosticsOverlay`

**E.3** Advanced tab UI:

- `Diagnostic Logging`
  - `Errors Only`
  - `Verbose`
- `Show Live Diagnostics Overlay`
  - disabled unless verbose is selected

**E.4** Wire the settings into the diagnostics reporter/store configuration.

Behavior:

- `Errors Only`
  - no debug/info/notice events in live overlay
- `Verbose`
  - include debug/info/notice in the live overlay buffer

Error-level disk logging remains always on.

**E.5** Construct the reporter in `AppComposition`.

Illustrative shape:

```swift
let mode = DiagnosticLoggingMode.resolve(from: defaults)

let sinks: [any DiagnosticsSink] = [
    OSLogDiagnosticsSink(),
    ErrorFileDiagnosticsSink(storageLocator: storageLocator),
    mode == .verbose
        ? VerboseFileDiagnosticsSink(storageLocator: storageLocator)
        : nil,
    RingBufferDiagnosticsSink(
        store: diagnosticsStore,
        minimumLevel: mode.minimumLevel
    ),
].compactMap { $0 }

let diagnostics = DiagnosticsReporter(
    sinks: sinks,
    redactor: PIIRedactor()
)

func makeLogger(_ category: String) -> PersonalScribeLogger {
    PersonalScribeLogger(category: category, reporter: diagnostics)
}
```

Pass this reporter through the existing DI chain. Do not add
`Diagnostics.shared`. Any retained `PersonalScribeLogger` instances are
constructed from this injected reporter rather than from hidden global
state.

#### Tests

Add:

- `Tests/PersonalScribeCoreTests/Preferences/DiagnosticLoggingPreferenceTests.swift`
- `Tests/PersonalScribeAppKitTests/AdvancedTabDiagnosticsTests.swift`

Pin:

- persistence of both settings
- overlay toggle disabled when not verbose

---

### Stage F — Live diagnostics overlay

This is the on-screen debug surface requested by the user.

#### New files

- `Sources/PersonalScribeAppKit/Diagnostics/LiveDiagnosticsOverlayController.swift`
- `Sources/PersonalScribeAppKit/Diagnostics/LiveDiagnosticsOverlayPresenter.swift`
- `Sources/PersonalScribeAppKit/Diagnostics/LiveDiagnosticsOverlayView.swift`

#### Implementation choice

Use a dedicated non-activating floating panel, separate from the pill and separate from the ResponseCard.

Why:

- it can remain visible while testing other apps
- it avoids polluting the normal pill UX
- it matches the “see things on screen as things are happening” requirement

#### Behavior

- enabled only when:
  - `DiagnosticLoggingMode == .verbose`
  - `showLiveDiagnosticsOverlay == true`
- shows a bounded rolling list of recent diagnostics events
- no input focus theft
- no mutation of normal session state

#### Suggested first-pass UI

Per row:

- timestamp
- level
- category
- message

Optional small metadata footer:

- `stage=...`
- `mode=...`
- `target=...`

No editing, no filtering UI in v1.

#### Tests

Keep this mostly presenter/store tested:

- `Tests/PersonalScribeAppKitTests/Diagnostics/LiveDiagnosticsOverlayPresenterTests.swift`
- `Tests/PersonalScribeAppKitTests/Diagnostics/LiveDiagnosticsOverlayControllerTests.swift`

Use manual verification for the final visual/runtime proof.

---

### Stage G — Cleanup and close-out

This stage only happens once the diagnostics backend is stable.

#### Cleanup goals

- remove any remaining “second system” semantics from `SessionErrorReporter`
- make `PersonalScribeLogger` explicitly documented as a facade over `DiagnosticsReporter`
- ensure no new direct file-writing helpers exist outside diagnostics sinks

#### Documentation

Update:

- `plans/diagnostics-system-design.md`
- `Tests/ManualVerifications/ManualPillOverlayVerification.md`
- add `Tests/ManualVerifications/ManualDiagnosticsVerification.md`

#### Manual verification runbook

Create at least these checks:

- `MV-DIAG-1`
  real session error creates a fresh line in `logs/errors.log`
- `MV-DIAG-2`
  session error still surfaces via ResponseCard, not the pill
- `MV-DIAG-3`
  `Errors Only` mode does not show live debug noise
- `MV-DIAG-4`
  `Verbose` + overlay shows debug/info/error events live without stealing focus
- `MV-DIAG-5`
  turning overlay off removes the panel immediately

---

## Landing strategy

Implement in the stage order above, but land the full migration as one
commit once every stage is complete.

Expected workflow:

1. add failing tests for each logic-heavy sub-area as work begins
2. execute the staged refactor locally in the order above
3. keep testing throughout development, but do not merge or release
   partial stages
4. land one final commit containing the full diagnostics migration,
   tests, settings, overlay, and docs

Per repo policy, logic-heavy changes still follow TDD even though the
migration ships as one commit.

---

## Exit criteria

The diagnostics-system refactor is complete when all of the following are true:

1. Every `PersonalScribeLogger` call goes through the shared diagnostics backend.
2. Error-level diagnostics always land in `logs/errors.log`.
3. Session failures still surface through `SessionSnapshot.reportedError` and the ResponseCard.
4. The diagnostics backend itself never reaches into AppKit to show UI directly.
5. Advanced settings expose `Errors Only / Verbose` and the live-overlay toggle.
6. The live diagnostics overlay can be enabled during testing without stealing focus.
7. The old “logger vs file reporter” split is no longer a real architectural split.
8. `SessionErrorReporter` no longer exists in production code.
9. PII redaction is enforced at sink-render time.
10. Reporter construction happens through DI in `AppComposition`, not a singleton.
11. Tests can assert diagnostics emission via `InMemoryTestSink`.
12. No production `PersonalScribeLogger` initializer discovers a
    reporter implicitly.

---

## Explicit deferrals

These are intentionally **not** required for v1 of this refactor:

- searchable/filterable diagnostics console UI
- exporting diagnostics logs from the app UI
- automatic telemetry upload

Those can land later if the unified diagnostics backend proves useful.

# Diagnostics System — Review Suggestions

Sense-check + apply to both `plans/diagnostics-system-design.md` and `plans/diagnostics-system-implementation.md`. Suggestions below as concrete edits. If a suggestion materially conflicts with something the docs already lock, push back; otherwise fold them in.

---

## `plans/diagnostics-system-design.md` — additions

### Add: New section "PII redaction" (insert before "Open implementation questions")

The Q4 decision wasn't captured in the design doc. Add as a new section locking the v1 approach:

```
## PII redaction

The diagnostics system can leak content if metadata or rendered errors
contain user-controlled values. Concrete sources today:

1. Transcript content snippets — current ASR errors don't carry text,
   but `String(describing: error)` for an enum with associated values
   could leak content if a future case adds `(text: String)`.
2. Filesystem paths — `/Users/<username>/...` identifies the machine.
3. Audio device names — "John's AirPods Pro," etc.
4. App / window focus titles — auto-paste's PID probe doesn't capture
   them today, but if anything later logs "Mail.app: Re: confidential
   proposal," title text is sensitive.
5. Recording filenames + timestamps — identifying when correlated.

### v1 redaction rules

- **Always-safe metadata keys**: `level`, `category`, `mappedError`,
  `stage`, `mode`, `descriptorID`, `pipelineShape`, `errorType`
  (the case name, not `String(describing:)`).
- **Always-redacted metadata keys**: keys matching
  `transcript|path|deviceName|windowTitle|appName|audioFile|userMessage`.
  Value replaced with `<redacted>`; key preserved so the structure
  stays grep-able.
- **Value-pattern redaction**: regex against value strings for
  `/Users/[^/]+` → `/Users/<redacted>`.
- **`underlyingError`**: never log `String(describing: error)`. Sinks
  render `String(describing: type(of: error))` + the case name only.
  Free-form `localizedDescription` is opt-in per call site.
- **`message: String`** (the diagnostics call's first arg): caller's
  responsibility. Document in the API doc that the message must not
  contain user content.

A `PIIRedactor` helper applies the whitelist + value-pattern rules
at the sink boundary, before file write or ring-buffer append.
```

### Lock D6 — Module boundaries

Add as a new locked decision after D5:

```
### D6 — Module boundaries

- `DiagnosticsReporter`, `DiagnosticsEvent`, `DiagnosticsSink`,
  `DiagnosticsLevel`, `UserFacingDiagnostic`, `PIIRedactor` live in
  `PersonalScribeCore`.
- The live diagnostics overlay UI lives in `PersonalScribeAppKit`
  and consumes the in-memory ring buffer through the public Core API.
- The Core layer never imports AppKit. The diagnostics layer never
  reaches into UI components.
```

### Lock D7 — Sink registration via dependency injection

Add as a new locked decision:

```
### D7 — Reporter is injected, not a singleton

`DiagnosticsReporter` is constructed at app boot in `AppComposition`
with the production sinks (`OSLogSink`, `ErrorFileSink`,
`VerboseFileSink`, `RingBufferSink`) and threaded through the
existing dependency-injection chain. Tests inject a reporter
configured with `InMemoryTestSink`. There is no `Diagnostics.shared`.
```

### Update §"Proposed model" → "Event type"

Change `underlyingError: String?` to `underlyingError: (any Error & Sendable)?` (Sendable-boxed if needed). Sinks render to string at sink-time. Preserves type fidelity for future telemetry/analytics sinks. Add one sentence to the field comment.

### Update §"Sink model" → S2

Replace the "S2 — File sink" section to clarify the **two-file** model that follows from Q1 (verbose-to-disk):

```
### S2 — File sinks (two)

- `ErrorFileSink` writes error-level events to `logs/errors.log`.
  Always on, regardless of verbosity setting.
- `VerboseFileSink` writes debug/info/notice/error events to
  `logs/diagnostics.log` when `Diagnostic Logging = Verbose`.
  Off otherwise. Errors are NOT duplicated into `diagnostics.log`
  (already in `errors.log`).

Each file rotates independently with a 1MB cap + head truncation.
```

### Update Open implementation questions

Q1 is no longer open — verbose-to-disk is the locked decision. Remove Q1 from the open list; carry the substance forward in S2.

---

## `plans/diagnostics-system-implementation.md` — additions

### Stage A — A.5 revision

Replace A.5 with:

```
**A.5** Sink registration + file policy:

- Reporter constructed in AppComposition with sinks injected, not as
  a singleton (D7).
- Error-level events write to `logs/errors.log` via `ErrorFileSink`.
  Always on.
- When `Diagnostic Logging = Verbose`, debug/info/notice/error events
  also write to `logs/diagnostics.log` via `VerboseFileSink`. Errors
  are NOT duplicated — they live only in `errors.log`.
- All events flow to OSLog and the in-memory ring buffer (subject to
  the verbosity filter for the latter).
- `PIIRedactor` is applied at the sink boundary before file write or
  ring-buffer append. Whitelist + regex per the design doc's PII
  section.
```

### Stage A — add A.6, A.7

```
**A.6** Add `Sources/PersonalScribeCore/Diagnostics/PIIRedactor.swift`.

Implements the v1 whitelist + value-pattern rules from the design
doc. Sinks call `PIIRedactor.redact(_:)` on the event before
serializing.

**A.7** Add `InMemoryTestSink: DiagnosticsSink` as a first-class part
of the model, distinct from the production ring buffer.

The production `RingBufferSink` is bounded + cyclic; the test sink is
unbounded + ordered for assertion ergonomics. Test code injects an
`InMemoryTestSink` into a test-only `DiagnosticsReporter` to assert
"this code path emitted an event with `userFacing:
.sessionError(...)`."
```

### Stage A — files list update

Add to the new-files list:

```
- `Sources/PersonalScribeCore/Diagnostics/PIIRedactor.swift`
- `Sources/PersonalScribeCore/Diagnostics/VerboseFileDiagnosticsSink.swift`
- `Sources/PersonalScribeCore/Diagnostics/InMemoryTestSink.swift`
```

Rename `ErrorFileDiagnosticsSink` if you'd like (the doc currently has it). Keep the test sink separate from the production ring buffer per A.7.

### Stage A — tests addition

Add:

```
- `Tests/PersonalScribeCoreTests/Diagnostics/PIIRedactorTests.swift`
- `Tests/PersonalScribeCoreTests/Diagnostics/VerboseFileDiagnosticsSinkTests.swift`

Pin:

- whitelist enforcement (safe keys preserved, sensitive keys
  redacted)
- value-pattern regex (`/Users/<username>/...` → `/Users/<redacted>/...`)
- `underlyingError` rendered as type + case name, never `String(describing:)`
- verbose file is empty when `Errors Only`; populated when `Verbose`
- errors are NOT duplicated into `diagnostics.log`
```

### Stage B — pick a path on `PersonalScribeLogger`

The current B.1 keeps `PersonalScribeLogger` as a permanent facade. Two options worth picking explicitly rather than leaving open:

**Option α (preferred — full retirement)**:

```
**B.1** Mechanically migrate all `PersonalScribeLogger` call sites to
`DiagnosticsReporter`. Roughly:

  logger.error("...", error: e)
    → diagnostics.error("...", error: e, category: .ui)

  logger.info("...")
    → diagnostics.info("...", category: .ui)

Same for `.debug`. Use IDE/sed; expect ~100 sites in `Sources/`.
After migration, delete `Sources/PersonalScribeCore/Logger.swift` and
`PersonalScribeLogCategory` becomes the input to `category:` (still
String constants).

**B.2** Stage G's "make `PersonalScribeLogger` documented as a facade"
item is removed — there's no logger to document.
```

**Option β (smaller-Stage-B — keep facade, rename later)**:

```
**B.1** Reimplement `PersonalScribeLogger` as a thin facade over
`DiagnosticsReporter` to unify the backend without touching call
sites. Stage G adds a new item: mechanically migrate the 100 call
sites + delete `PersonalScribeLogger` and `Logger.swift`.
```

**Recommendation: Option α** in this plan, since it puts the consolidation work where it logically belongs (Stage B, the cutover). Option β is acceptable if the plan calls out the migration as a hard-required Stage G item, not optional polish.

### Stage E — explicit DI wiring

Add a new sub-step to Stage E:

````
**E.5** AppComposition wires the reporter:

```swift
let mode = DiagnosticLoggingMode.resolve(from: defaults)
let showOverlay = ShowLiveDiagnosticsOverlayPreference.resolve(from: defaults)

let sinks: [any DiagnosticsSink] = [
    OSLogSink(),
    ErrorFileSink(storageLocator: storageLocator),
    mode == .verbose ? VerboseFileSink(storageLocator: storageLocator) : nil,
    RingBufferSink(capacity: 200, minimumLevel: mode.minimumLevel),
].compactMap { $0 }

let diagnostics = DiagnosticsReporter(sinks: sinks)
```

The reporter is then passed down the existing DI chain (same path
`PersonalScribeLogger` instances flow today).
````

### Explicit deferrals — update

Remove `logs/diagnostics.log` from "explicit deferrals" — it's in Stage A now.

Keep:
- searchable/filterable diagnostics console UI
- exporting diagnostics logs from the app UI
- automatic telemetry upload

### Exit criteria — add

```
8. No production code uses `PersonalScribeLogger.error/info/debug` —
   all logging flows through `DiagnosticsReporter` (assumes Option α).
9. PII redaction whitelist + regex applies at sink boundary; sensitive
   metadata keys never reach disk in raw form.
10. Tests can assert on emitted diagnostics via `InMemoryTestSink`.
```

---

## Suggested commit slicing — minor adjustment

The plan's commit slicing is fine. Stage B becomes one of:

- **Option α**: split into B.1 (`DiagnosticsReporter` ships, `PersonalScribeLogger` removed) and Stage G's no-op since the migration already happened.
- **Option β**: B.1 ships the facade, Stage G adds the rename pass.

Option α merges Stage B + part of Stage G into one larger commit. Option β keeps the rename as a separate commit. Either is fine; pick based on commit-size preference.

---

Sense-check each suggestion. Anything that materially conflicts with a constraint already locked, push back. Otherwise apply both files in one revision.

# Security Audit — Lane 3: Logs & Telemetry (Claude reviewer)

Date: 2026-04-26
Lane scope: every logging callsite + analytics/telemetry imports under `/Sources/`. Read-only audit.

## 1. Threat-model framing

Ninimma is a local-only macOS dictation app. Its sensitive payload is the **transcribed text** the user produces, plus secondary signals: filesystem paths (which inevitably embed `/Users/<unixname>/…`), recording UUIDs, model identifiers, and selected device IDs.

All logging in this codebase routes through Apple's unified-logging system (`os.Logger`) under subsystem `AppBrand.logSubsystem`. macOS unified logging persists messages to disk under `/var/db/diagnostics`, surfaces them live in Console.app, and includes them in `sysdiagnose` bundles. Anything emitted is therefore:

- visible to any local process running as the same user who can attach Console (no extra entitlement);
- captured by `log collect` / `log show` after the fact;
- shipped wholesale into a `sysdiagnose` archive that users routinely upload to vendors.

`os.Logger` redacts string interpolations by default *only when the value is a non-string scalar*. **Plain `String` interpolations into `os.Logger` are public by default** unless an explicit `privacy: .private` (or `.sensitive` / `.auto`) marker is attached. So "no marker" on a string interpolation = leaked.

Threat scenarios in scope:
1. Sensitive content (transcript text, file paths with usernames, recording IDs, environment values) emitted in the clear into the unified log → anyone with local Console access or any sysdiagnose recipient sees it.
2. An analytics / crash-reporter SDK forwarding usage data off-device.
3. A custom telemetry endpoint POSTing usage data anywhere.

## 2. Files audited

223 Swift sources under `/Sources/`. Targeted reads:

- `Sources/PersonalScribeCore/Logger.swift` (central wrapper; defines `PersonalScribeLogger` + categories).
- `Sources/PersonalScribeCore/Metrics/{MetricsModels,MetricsProtocols,MetricsSnapshotStore,SQLiteMetricsService}.swift`.
- `Sources/PersonalScribeCore/BaseDirectoryMigrator.swift` (only `NSLog` callsite).
- `Sources/PersonalScribeAudio/AudioEngineDriver.swift` (only `print(` callsite).
- `Sources/PersonalScribeAudio/{AVAudioCaptureService,AudioResampler}.swift`.
- `Sources/PersonalScribeSession/SessionCoordinator.swift`.
- `Sources/PersonalScribeSession/Pipeline/Orchestrator/SessionPipelineOrchestrator.swift`.
- `Sources/PersonalScribeSession/Models/Selection/ActiveModelService.swift`.
- `Sources/PersonalScribeTranscription/FluidAudioTranscriber.swift`.
- `Sources/PersonalScribeTranscription/Models/Selection/ModelAwareFluidAudioTranscriber.swift`.
- `Sources/PersonalScribeAppKit/MenuBar/{MenuBarSceneModel,StatusItemController}.swift`.
- `Sources/PersonalScribeAppKit/Hotkeys/{HotkeyEventTap,GlobalHotkeyMonitor}.swift`.
- `Sources/PersonalScribeAppKit/Output/ClipboardBatchOutput.swift`.
- `Sources/PersonalScribeAppKit/Composition/{AppComposition,AppStartupCoordinator,PersonalScribeAppMain}.swift`.
- `Sources/PersonalScribeAppKit/Settings/AppRelauncher.swift`.
- `Sources/PersonalScribeAppKit/Overlay/PillOverlayPresenter.swift`.
- `Sources/PersonalScribeCore/Errors.swift` (verifying `errorDescription` isn't user content).
- `Package.swift` (dependency surface).

Patterns searched globally across `/Sources/`:
- `Logger`, `os_log`, `os.Logger`, `print(`, `NSLog`, `debugPrint`.
- `.error(`, `.info(`, `.debug(`, `.warning(`, `.notice(`, `.trace(`, `.fault(`.
- Analytics SDK imports: `Firebase`, `Sentry`, `Bugsnag`, `Crashlytics`, `AppCenter`, `Mixpanel`, `Amplitude`, `Segment`, `Datadog`, `NewRelic`, `Rollbar`, `TelemetryDeck`, `PostHog`, `Flurry`, `HockeyApp`, `Instabug`.
- Network primitives: `URLSession`, `URLRequest`, `dataTask`, `uploadTask`, `webSocket`, `http://`, `https://`.

## 3. Findings

### Finding L3-1 — MEDIUM — `PersonalScribeLogger` forces `privacy: .public` on every message

- **File:** `Sources/PersonalScribeCore/Logger.swift:20, 30, 42`.
- **What:** The central wrapper unconditionally interpolates the caller's message string with `, privacy: .public`:
  ```swift
  logger.debug("\(renderedMessage, privacy: .public) [\(renderedFile, privacy: .public):\(line)]")
  logger.info ("\(renderedMessage, privacy: .public) [\(renderedFile, privacy: .public):\(line)]")
  logger.error("\(renderedMessage, privacy: .public)\(detail, privacy: .public) [\(renderedFile, privacy: .public):\(line)]")
  ```
  Every `PersonalScribeLogger.{debug,info,error}` callsite is therefore *guaranteed* to emit its message in the clear into the unified log, regardless of what the caller passes. There is no opt-in path for `.private`/`.sensitive`/`.auto` redaction.
- **Why it matters:** Today's call sites happen to interpolate only safe values (numerics, error contract names, non-PII enum cases — see audit of every interpolated callsite below). But the design **bakes in** that any future caller who interpolates `result.text`, `entry.text`, `audioURL.path`, or any other transcript/PII-bearing value will silently leak it into Console / sysdiagnose. A sensitivity-aware log API is the kind of thing you want to get right *before* you have many call sites, because retro-fitting privacy markers at every call is harder than retro-fitting at the wrapper. This is also a regression magnet during code review: reviewers won't notice a problem because the wrapper "looks safe".
- **Mitigation:** Either (a) drop the `privacy: .public` markers and let `os.Logger`'s default behavior apply (default for `String` is still public, so this only helps if combined with caller-side markers); preferably (b) extend the API so callers must opt in to public — e.g. `log.info(public: "static string", private: dynamicValue)` — and assert (or static-analyze) that interpolated values are never directly inlined; or (c) at minimum add a code-review rule + test that no caller interpolates `String` arguments without going through a redaction helper.

### Finding L3-2 — LOW/MEDIUM — Filesystem path with username leaked in BaseDirectoryMigrator

- **File:** `Sources/PersonalScribeCore/BaseDirectoryMigrator.swift:101`.
- **What:**
  ```swift
  logger.info("BaseDirectoryMigrator: moved \(legacy.path) → \(current.path)")
  ```
  `legacy.path` and `current.path` are absolute paths under `~/Library/Application Support/{Seshat,personal_scribe}`, which expand to `/Users/<unixname>/Library/Application Support/...`. Combined with L3-1 (`privacy: .public`), the user's macOS short-name is published into the unified log on every legacy-→-current migration.
- **Why:** Username is a weak PII signal but is still PII; it's exactly the kind of value that should travel as `privacy: .private` (auto-redacted in non-debug logs unless the reader has the right entitlement). Path leakage is also a known anti-pattern in Apple's own privacy guidance.
- **Mitigation:** Log only the directory *names* (`Seshat → personal_scribe`) — the absolute paths are deterministic from `appSupportProvider()` and don't aid debugging. Alternatively, when L3-1 is fixed, mark the path components `.private`.

### Finding L3-3 — LOW — `print(` in `AudioEngineDriver.applyInputDeviceLive`

- **File:** `Sources/PersonalScribeAudio/AudioEngineDriver.swift:130`.
- **What:**
  ```swift
  print("[PersonalScribeAudio] Selected input device UID \(uid) not found; using system default")
  ```
  `print` writes to stderr (which is captured by the unified log under the process's stdio category and is always public). The interpolated `uid` is a CoreAudio device UID — not user content, but this is the only `print` in the entire `Sources/` tree and bypasses the central logger.
- **Why:** Inconsistency with the rest of the codebase makes this the "easy place" for someone to add an interpolation that *is* sensitive later. Also, `print` output is uncategorized in Console — harder to suppress in release builds.
- **Mitigation:** Route through `PersonalScribeLogger(category: .audio).info(...)`. Drop the bracketed prefix; the unified-log subsystem/category already provides that.

### Finding L3-4 — INFO (no action needed) — `NSLog` in BaseDirectoryMigrator rollback

- **File:** `Sources/PersonalScribeCore/BaseDirectoryMigrator.swift:207`.
- **What:** `NSLog("BaseDirectoryMigrator rollback failed for %@: %@", subdirectory.pathComponent, error.localizedDescription)`. Reached only on a double-failure (move failed, then rollback also failed) — extremely cold path. `pathComponent` is a static `ManagedDirectory` rawValue (e.g. `"recordings"`); `error.localizedDescription` is a `FileManager` error string.
- **Why:** Not flagged as a bug — `NSLog` is a known route into the unified log and the values here are not sensitive — but noted for completeness so the next reviewer doesn't have to re-derive it. Worth migrating to `PersonalScribeLogger.error` for consistency once L3-1 is addressed.
- **Mitigation:** Optional cleanup; no security action.

### Finding L3-5 — POSITIVE (no finding) — No analytics / crash-reporter SDKs

Searched `/Sources/` and `Package.swift` for `Firebase`, `Sentry`, `Bugsnag`, `Crashlytics`, `AppCenter`, `Mixpanel`, `Amplitude`, `Segment`, `Datadog`, `NewRelic`, `Rollbar`, `TelemetryDeck`, `PostHog`, `Flurry`, `HockeyApp`, `Instabug`. **Zero matches.** Package dependencies are exactly two: `FluidAudio` (model runtime; downloads `.mlmodelc` artifacts from HuggingFace — known and expected) and `GRDB.swift` (local SQLite). Neither phones home with usage data.

### Finding L3-6 — POSITIVE (no finding) — No custom telemetry endpoint

Searched for `URLSession`, `URLRequest`, `dataTask`, `uploadTask`, `webSocket`, `http://`, `https://` across `/Sources/`. The only HTTPS string is `https://mythlok.com/ninimma/` in `AppBrand.swift:15` (doc comment) and `AboutSubTab.swift:84` (a SwiftUI `Link` for the user-clickable About page — not a programmatic POST). **No code performs an outbound network request from the app.**

### Finding L3-7 — POSITIVE (no finding) — Transcript text never reaches a logger

Walked every interpolated `logger.{info,error,debug}` callsite (10 total, see grep at audit time). None of them interpolate transcript text, audio data, recording metadata, or environment values. Specifically verified the suspicious-by-name sites:

- `MenuBarSceneModel.copyTranscript` (`MenuBarSceneModel.swift:129, 133`) logs only static strings ("Copy transcript skipped because no transcript is available", "Copying latest transcript to clipboard"); the transcript itself is *never* interpolated. Good.
- `ClipboardBatchOutput` (`ClipboardBatchOutput.swift:82, 102, 118, 125, 141, 148, 152`) — every line logs static strings describing the *control-flow branch*, never the transcript content. Good.
- `SessionCoordinator.swift:351` — `logger.error("Failed to persist transcript to TranscriptRepository", error: error)`. Static string + GRDB-error description. No transcript text. Good.
- `FluidAudioTranscriber.swift:237`, `ModelAwareFluidAudioTranscriber.swift:276` — interpolate `error.localizedDescription` into a static `message` template. Errors here come from FluidAudio model loading / inference; no transcript content surfaces. Good.

Interpolated values in scope of L3-1 today are: `status.rawValue` (Int enum), `inputSampleRate` (Double), `outcome.finalStatus == .granted` (Bool), `modeID` (workflow-mode identifier, not user content), `kind.rawValue` + `id` (model-kind enum + registered model id — not PII), and `legacy.path` / `current.path` (the username-leaking case in L3-2).

### Finding L3-8 — INFO — `logSink` parameters in `FluidAudioTranscriber` / `ModelAwareFluidAudioTranscriber` / `GlobalHotkeyMonitor`

These types accept a `(@Sendable (level, message) -> Void)?` `logSink` for in-process fan-out (e.g. ResponseCard surfacing). Inspected: only static strings + `error.localizedDescription` are dispatched; no transcript or audio content is forwarded. Not a finding — flagged so the next reviewer doesn't re-ask. The shape *would* enable a future caller to pipe the sink to a network endpoint; that's an architectural concern to flag the moment any caller wires it cross-process.

## 4. Coverage gaps

- **Tests directory not audited.** Lane scope said `/Sources/`, so `Tests/` is out of scope. Tests can hold harmless `print` calls but could in principle exfil via custom test hooks. If desired, a follow-up pass over `Tests/` is cheap.
- **Bundled assets not audited for embedded telemetry SDKs.** Package.resolved had no analytics deps, but I did not crack open `.mlmodelc` artifacts or vendored binaries to check for embedded native telemetry. Out of scope for a static-text audit; flagging as a known gap.
- **No verification of unified-log volume per session.** Even without sensitive content, log spam can be a privacy signal (e.g. `logger.info("Record button tapped")` in `MenuBarSceneModel.swift:108` — every record press is timestamped in Console). Not classified as a finding because the values are non-sensitive, but worth a future "log-noise / quiet by default" review separate from this lane.
- **`PillOverlayPresenter.diagnosticLogger`** (`PillOverlayPresenter.swift:295`) is declared but its callsites were not exhaustively walked. Spot-checked: present as a private property; if it logs presenter state with transcript content, that would be a finding. Recommend follow-up read of any `.error(` / `.info(` calls on `diagnosticLogger` specifically.
- **Subsystem string** (`AppBrand.logSubsystem`) — not inspected for whether it inadvertently embeds a developer team identifier; treated as out of scope but trivially worth a glance.
- **Codex reviewer** is auditing the same lane independently per instructions. No coordination; conflicts (if any) should be reconciled at synthesis time.

# 2026-04-26 Security Audit — Lane 3 Logs & telemetry (Codex retry)

## 1. Threat-model framing
This lane treats local logging as a quiet exfil path: anything sent to `Logger`, `NSLog`, or `print` must be assumed collectible outside the immediate UI. I audited the shared logger, migration and metrics code, the lone `print(` site, then repository-wide log callsites to determine whether dynamic fields can carry transcript text, file URLs or paths, environment-derived values, or recording IDs, and I separately checked for telemetry or crash-reporting SDKs plus POST-style usage collection.

## 2. Files audited
- `plans/codex-heartbeat-contract.md`
- `Sources/PersonalScribeCore/Logger.swift`
- `Sources/PersonalScribeCore/BaseDirectoryMigrator.swift`
- `Sources/PersonalScribeCore/Metrics/MetricsModels.swift`
- `Sources/PersonalScribeCore/Metrics/MetricsProtocols.swift`
- `Sources/PersonalScribeCore/Metrics/MetricsSnapshotStore.swift`
- `Sources/PersonalScribeCore/Metrics/SQLiteMetricsService.swift`
- `Sources/PersonalScribeCore/Database/TranscriptRepository.swift`
- `Sources/PersonalScribeAudio/AudioEngineDriver.swift`
- `Sources/PersonalScribeAudio/AVAudioCaptureService.swift`
- `Sources/PersonalScribeAudio/AudioResampler.swift`
- `Sources/PersonalScribeSession/Pipeline/Orchestrator/SessionPipelineOrchestrator.swift`
- `Sources/PersonalScribeSession/Models/Selection/ActiveModelService.swift`
- `Sources/PersonalScribeSession/SessionCoordinator.swift`
- `Sources/PersonalScribeTranscription/FluidAudioTranscriber.swift`
- `Sources/PersonalScribeTranscription/Models/Selection/ModelAwareFluidAudioTranscriber.swift`
- `Sources/PersonalScribeAppKit/Settings/AppRelauncher.swift`
- `Sources/PersonalScribeAppKit/MenuBar/StatusItemController.swift`
- `Sources/PersonalScribeAppKit/MenuBar/MenuBarSceneModel.swift`
- `Sources/PersonalScribeAppKit/Hotkeys/GlobalHotkeyMonitor.swift`
- `Sources/PersonalScribeAppKit/Composition/AppComposition.swift`
- `Sources/PersonalScribeAppKit/Composition/PersonalScribeAppMain.swift`
- `Sources/PersonalScribeAppKit/Overlay/PillOverlayPresenter.swift`
- `Package.swift`
- `Package.resolved`

## 3. Findings
- high — `Sources/PersonalScribeCore/Logger.swift:18-20`, `Sources/PersonalScribeCore/Logger.swift:28-30`, `Sources/PersonalScribeCore/Logger.swift:39-42`: `renderedMessage`, `renderedFile`, and `detail = error.localizedDescription` are logged with `.public`. Why: this disables redaction at the logging primitive, so every downstream dynamic field is explicitly non-private. Representative public-error callsites include `Sources/PersonalScribeAppKit/Composition/AppComposition.swift:22`, `Sources/PersonalScribeAppKit/Composition/AppComposition.swift:67`, `Sources/PersonalScribeAppKit/Composition/AppComposition.swift:193`, `Sources/PersonalScribeAppKit/Settings/AppRelauncher.swift:30`, `Sources/PersonalScribeCore/Database/TranscriptRepository.swift:150`, `Sources/PersonalScribeCore/Database/TranscriptRepository.swift:209`, `Sources/PersonalScribeCore/Metrics/MetricsSnapshotStore.swift:71`, `Sources/PersonalScribeSession/SessionCoordinator.swift:395`, `Sources/PersonalScribeSession/Pipeline/Orchestrator/SessionPipelineOrchestrator.swift:1023`, `Sources/PersonalScribeTranscription/FluidAudioTranscriber.swift:237`, and `Sources/PersonalScribeTranscription/Models/Selection/ModelAwareFluidAudioTranscriber.swift:276`; those errors can plausibly carry model, database, or bundle paths plus raw parse details. Mitigation: default log payloads to `.private`, remove file IDs from production logs, and map thrown errors to redacted enums or codes before logging.
- medium — `Sources/PersonalScribeCore/BaseDirectoryMigrator.swift:101`, `Sources/PersonalScribeCore/BaseDirectoryMigrator.swift:207-210`: direct path-bearing migration logging. Variables: `legacy.path`, `current.path`, `subdirectory.pathComponent`, and `error.localizedDescription`. Why: `legacy.path` and `current.path` expose absolute user-library paths, and rollback failures may echo more filesystem detail. Mitigation: replace paths with fixed event names or hashed tokens, and never feed filesystem errors straight into public logs.
- medium — `Sources/PersonalScribeAudio/AudioEngineDriver.swift:130`: `print` logs the missing audio-device `uid` verbatim. Why: this is not transcript text, file URLs, environment values, or a recording ID, but it is still a stable hardware identifier emitted on a warning path. Mitigation: drop the UID from the message or log only that the persisted device was unavailable.
- info — `Sources/PersonalScribeAudio/AVAudioCaptureService.swift:54`, `Sources/PersonalScribeAudio/AudioResampler.swift:69`, `Sources/PersonalScribeSession/Models/Selection/ActiveModelService.swift:404`, `Sources/PersonalScribeAppKit/MenuBar/StatusItemController.swift:403`, `Sources/PersonalScribeAppKit/MenuBar/MenuBarSceneModel.swift:122`, `Sources/PersonalScribeAppKit/Composition/PersonalScribeAppMain.swift:246`, `Sources/PersonalScribeAppKit/Overlay/PillOverlayPresenter.swift:346`, `Sources/PersonalScribeAppKit/Overlay/PillOverlayPresenter.swift:481`, `Sources/PersonalScribeAppKit/Overlay/PillOverlayPresenter.swift:565`: the other interpolated variables I found were `status.rawValue`, `inputSampleRate`, `AppConfig.sampleRate`, `kind.rawValue`, `id`, `modeID`, `outcome.finalStatus == .granted`, `text.count`, `visibility`, `isVisible`, `panelExisted`, `panel.frame`, `panel.isVisible`, and a `"nil"/"exists"` sentinel. I did not see these carrying transcript text, file URLs, environment values, or recording IDs in the audited code. `text.count` still leaks transcript-length metadata and `panel.frame` leaks screen-geometry metadata; both also inherit the logger's `.public` behavior. Mitigation: keep only low-cardinality state or counter logs that are operationally necessary.
- info — `Package.swift:31-40`, `Package.resolved:1-24`: no listed analytics or crash-reporting SDKs are present in declared dependencies, and repository-local searches found no `import Firebase|Sentry|...`, no `URLSession` or `URLRequest` plus POST-style usage collection in `Sources/`, and no production wiring of the optional `logSink` callbacks beyond tests. Mitigation: keep telemetry absent; if networking is introduced later, explicitly re-review usage-data paths against this threat model.

## 4. Coverage gaps
- Read-only audit only: I did not run the app, inspect the live unified log store, or capture runtime `os_log` output.
- I did not audit third-party dependency internals (`FluidAudio`, `GRDB`) beyond `Package.swift` and `Package.resolved`.
- I did not inspect files outside this repo or Claude's prior lane report, per instruction.

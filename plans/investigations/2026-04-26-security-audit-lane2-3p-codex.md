# 2026-04-26 Security Audit — Lane 2: 3p dep API boundary (Codex)

## 1) Threat-model framing

- Scope: local-only static audit of app-side boundaries into `FluidAudio` and `GRDB`. No build, test, runtime capture, or network access.
- Allowed by brief:
  - `FluidAudio`: audio / PCM payloads only.
  - `GRDB`: local SQLite access; DB file path is allowed only if pinned under the app data dir.
- Forbidden by brief: file URLs, absolute paths, env-derived values, user IDs, or unrelated user data crossing into third-party code.
- Evaluation note: I still enumerate every parameter below. Findings focus on policy violations and broader-than-declared boundaries, not on ordinary local SQL literals.

| Dependency | URL | `Package.swift` constraint | `Package.resolved` |
| --- | --- | --- | --- |
| `FluidAudio` | `https://github.com/FluidInference/FluidAudio.git` | `exact: "0.13.6"` | `version 0.13.6`, `revision 57551cd90e0bbec342766244358bcf08afb05290` |
| `GRDB.swift` | `https://github.com/groue/GRDB.swift.git` | `exact: "7.10.0"` | `version 7.10.0`, `revision 36e30a6f1ef10e4194f6af0cff90888526f0c115` |

## 2) Files audited

- Lane scope, `Sources/PersonalScribeSession/Models/Selection/`:
  - `ActiveModelService.swift`, `AdapterRecord.swift`, `ModelBoundProcessorProvider.swift`, `ModelBoundProcessorProviding.swift`, `ModelBoundTranscriberProvider.swift`, `ModelBoundTranscriberProviding.swift`
- Lane scope, `Sources/PersonalScribeTranscription/`:
  - `Adapters/FluidAudioOfflineDiarizerAdapter.swift`, `Adapters/FluidAudioParakeetTranscriberAdapter.swift`, `Adapters/FluidAudioQwenTranscriberAdapter.swift`, `Adapters/FluidAudioStreamingTranscriberAdapter.swift`, `FluidAudioInferenceClient.swift`, `FluidAudioTranscriber.swift`, `Models/Selection/FluidAudioRuntimeVariant.swift`, `Models/Selection/ModelAwareFluidAudioInferenceClient.swift`, `Models/Selection/ModelAwareFluidAudioTranscriber.swift`, `PersonalScribeTranscriptionModule.swift`
- Lane scope, `Sources/PersonalScribeVAD/`:
  - `FluidAudioVadProvider.swift`, `FluidAudioVadSession.swift`, `VadMonitoring.swift`
- Lane scope, `Sources/PersonalScribeCore/Database/`:
  - `AppDatabase.swift`, `DatabaseOperationStatus.swift`, `Migrations/TranscriptsMigrator.swift`, `RuntimeGateFailure.swift`, `TranscriptOrder.swift`, `TranscriptRepository.swift`, `TranscriptStorageError.swift`
- Additional file required to fully enumerate GRDB row payloads:
  - `Sources/PersonalScribeCore/TranscriptStore.swift`
- Supporting provenance files for path origin and dependency resolution:
  - `Package.swift`, `Package.resolved`, `Sources/PersonalScribeCore/Storage/AppConfig.swift`, `Sources/PersonalScribeCore/Storage/AppStorageLocator.swift`, `Sources/PersonalScribeCore/Storage/StorageLocator.swift`, `Sources/PersonalScribeCore/Storage/FixedBaseDirectoryStorageLocator.swift`, `Sources/PersonalScribeCore/Storage/ManagedDirectory.swift`, `Sources/PersonalScribeAppKit/Composition/AppComposition.swift`

## 3) Findings

- `High` — `Sources/PersonalScribeTranscription/FluidAudioInferenceClient.swift:43`, `Sources/PersonalScribeTranscription/Models/Selection/ModelAwareFluidAudioInferenceClient.swift:39`, `Sources/PersonalScribeTranscription/Adapters/FluidAudioQwenTranscriberAdapter.swift:149`, `Sources/PersonalScribeTranscription/Adapters/FluidAudioStreamingTranscriberAdapter.swift:53`, `Sources/PersonalScribeTranscription/Adapters/FluidAudioParakeetTranscriberAdapter.swift:299`, `Sources/PersonalScribeTranscription/Adapters/FluidAudioOfflineDiarizerAdapter.swift:138`
  - What: `FluidAudio` receives absolute model/cache `URL`s during ASR/Qwen/streaming/diarization model preparation.
  - Why: the brief forbids file URLs / absolute paths into third-party code. The path source is not fixed: `Sources/PersonalScribeCore/Storage/AppConfig.swift:101-110` allows `PERSONAL_SCRIBE_BASE_DIR` and `BaseDirectoryPath`, and `Sources/PersonalScribeCore/Storage/AppStorageLocator.swift:35-38` appends managed subdirectories onto that resolved base path. That means env- or user-default-derived filesystem locations can cross into `FluidAudio`.
  - Mitigation: if the threat model is hard, the current path-based `FluidAudio` load/prep APIs are unacceptable. Replace or vendor those APIs so first-party code resolves model artifacts and `FluidAudio` receives only opaque in-memory objects; otherwise insert a trusted broker layer and hard-ban env / `UserDefaults` base-dir overrides before any `FluidAudio` call.

- `Medium` — `Sources/PersonalScribeAppKit/Composition/AppComposition.swift:20`, `Sources/PersonalScribeCore/Database/AppDatabase.swift:41-58`
  - What: `GRDB` database opening is not pinned to the app data dir.
  - Why: `AppDatabase` builds `databaseURL` from `locator.url(for: .recordings)` and passes `databaseURL.path` to `DatabaseQueue(path:)`. `AppConfig.liveStorageLocator()` inherits the same override chain described above, so `GRDB` can be pointed at arbitrary absolute paths outside the default app-support tree. The brief allows a DB path only under app data dir.
  - Mitigation: split dev/test overrides from production, canonicalize the path before `DatabaseQueue(path:)`, and reject any database location outside the intended app-support root.

- `Low` — `Sources/PersonalScribeTranscription/FluidAudioInferenceClient.swift:52`, `Sources/PersonalScribeTranscription/Models/Selection/ModelAwareFluidAudioInferenceClient.swift:48`, `Sources/PersonalScribeTranscription/Adapters/FluidAudioStreamingTranscriberAdapter.swift:23`, `Sources/PersonalScribeTranscription/Adapters/FluidAudioStreamingTranscriberAdapter.swift:133`, `Sources/PersonalScribeTranscription/Adapters/FluidAudioStreamingTranscriberAdapter.swift:136`, `Sources/PersonalScribeVAD/FluidAudioVadProvider.swift:70`, `Sources/PersonalScribeVAD/FluidAudioVadProvider.swift:97`
  - What: the `FluidAudio` runtime boundary is broader than "PCM only". The app also passes source/category enums, model-selection enums, chunk-size enums, VAD state, VAD config, callback closures, and a preloaded `MLModel`.
  - Why: I found no user IDs, env dictionaries, or arbitrary user metadata on these callsites, and the values appear functionally required, but they are still broader than the literal "audio/PCM bytes only" boundary.
  - Mitigation: either narrow the integration so `FluidAudio` owns these control inputs internally, or explicitly amend the threat model to allow non-sensitive operational metadata while continuing to ban paths / env-derived values / identifiers.

### FluidAudio callsite inventory

| File:line | Direct 3p API | Parameters crossing into 3p | Assessment |
| --- | --- | --- | --- |
| `FluidAudioInferenceClient.swift:33` | `AsrManager(config:)` | `config: .default` | Non-audio operational config only |
| `FluidAudioInferenceClient.swift:43-48` | `AsrModels.load(from:version:progressHandler:)`, `AsrManager.loadModels(_:)` | `from: directory URL`, `version: runtimeVariant.asrModelVersion`, `progressHandler: closure`, `models: object derived from directory` | `directory URL` is a forbidden path; other params are operational |
| `FluidAudioInferenceClient.swift:52` | `AsrManager.transcribe(_:source:)` | `samples: [Float]`, `source: .microphone` | PCM plus non-sensitive source metadata |
| `ModelAwareFluidAudioInferenceClient.swift:29` | `AsrManager(config:)` | `config: .default` | Non-audio operational config only |
| `ModelAwareFluidAudioInferenceClient.swift:39-44` | `AsrModels.load(from:version:progressHandler:)`, `AsrManager.loadModels(_:)` | `from: directory URL`, `version: runtimeVariant.asrModelVersion`, `progressHandler: closure`, `models: object derived from directory` | Same path leak as legacy client |
| `ModelAwareFluidAudioInferenceClient.swift:48` | `AsrManager.transcribe(_:source:)` | `samples: [Float]`, `source: .microphone` | PCM plus non-sensitive source metadata |
| `FluidAudioQwenTranscriberAdapter.swift:146` | `Qwen3AsrManager()` | no parameters | No data crosses |
| `FluidAudioQwenTranscriberAdapter.swift:149` | `Qwen3AsrManager.loadModels(from:)` | `directory: URL` | Forbidden path crosses |
| `FluidAudioQwenTranscriberAdapter.swift:153` | `Qwen3AsrManager.transcribe(audioSamples:)` | `audioSamples: [Float]` | PCM only |
| `FluidAudioStreamingTranscriberAdapter.swift:23` | `StreamingEouAsrManager(chunkSize:)` | `chunkSize: StreamingChunkSize` | Non-sensitive operational metadata |
| `FluidAudioStreamingTranscriberAdapter.swift:53` | `StreamingEouAsrManager.loadModels(modelDir:)` | `modelDir: URL` | Forbidden path crosses |
| `FluidAudioStreamingTranscriberAdapter.swift:133-151` | `setPartialCallback`, `setEouCallback`, `process(audioBuffer:)` | callback closures, `audioBuffer: AVAudioPCMBuffer` | Audio plus callback plumbing; no path / ID seen here |
| `FluidAudioStreamingTranscriberAdapter.swift:132`, `168`, `223-225` | `reset()`, `finish()`, `reset()` | no parameters / callback reset closures | No sensitive data observed |
| `FluidAudioParakeetTranscriberAdapter.swift:289` | `AsrManager(config:)` | `config: .default` | Non-audio operational config only |
| `FluidAudioParakeetTranscriberAdapter.swift:299-304` | `AsrModels.load(from:version:progressHandler:)`, `AsrManager.loadModels(_:)` | `from: directory URL`, `version: AsrModelVersion`, `progressHandler: closure`, `models: object derived from directory` | Forbidden path crosses |
| `FluidAudioParakeetTranscriberAdapter.swift:308` | `AsrManager.transcribe(_:source:)` | `samples: [Float]`, `source: .microphone` | PCM plus non-sensitive source metadata |
| `FluidAudioOfflineDiarizerAdapter.swift:203` | `OfflineDiarizerManager()` | no parameters | No data crosses |
| `FluidAudioOfflineDiarizerAdapter.swift:208` | `OfflineDiarizerManager.prepareModels(directory:)` | `directory: URL?` | Forbidden path crosses |
| `FluidAudioOfflineDiarizerAdapter.swift:212` | `OfflineDiarizerManager.process(audio:)` | `audio: [Float]` | PCM only |
| `FluidAudioVadProvider.swift:70` | `VadManager.processStreamingChunk(_:state:config:)` | `chunk: [Float]`, `state: VadStreamState`, `config: VadSegmentationConfig(minSilenceDuration)` | Audio plus non-sensitive operational state/config |
| `FluidAudioVadProvider.swift:97` | `VadManager(config:vadModel:)` | `config: VadConfig.default`, `vadModel: MLModel` | No path crosses here; still broader than PCM-only |

### GRDB callsite inventory

| File:line | Direct 3p API | Parameters crossing into 3p | Assessment |
| --- | --- | --- | --- |
| `AppDatabase.swift:57` | `DatabaseQueue(path:)` | `path: databaseURL.path` | Allowed only if pinned under app data dir; current path source is override-capable |
| `AppDatabase.swift:63` | `DatabaseMigrator.migrate(_:)` | `dbQueue: DatabaseQueue already opened on databaseURL.path` | No new payload beyond the already-flagged DB path |
| `AppDatabase.swift:78`, `85` | `DatabaseWriter.write(_:)`, `DatabaseWriter.read(_:)` | closure blocks only; concrete payloads are below | Dispatch layer only |
| `AppDatabase.swift:163-189` | `DatabaseQueue.read`, `String.fetchOne`, `Int.fetchOne` | literal SQL strings, `transcriptsFTSTableName` argument | Runtime metadata only; no user IDs / env values passed |
| `TranscriptsMigrator.swift:20-64` | `DatabaseMigrator`, `registerMigration`, `db.execute`, `db.create(virtualTable:using:)`, `FTS5()` | migration names, literal DDL / PRAGMA SQL, table names, tokenizer config | Schema-only GRDB usage |
| `TranscriptRepository.swift:57-59` with `TranscriptStore.swift:65-70` | `entry.insert(db)` | `id.uuidString`, `timestamp.timeIntervalSince1970`, `text`, `audioDuration`, `processingDuration` | Local DB row payload only |
| `TranscriptRepository.swift:76-80` | `db.execute` | SQL literal, `id.uuidString` | Local DB row deletion only |
| `TranscriptRepository.swift:98-103` | `db.execute` | SQL literal, `text`, `id.uuidString` | Local DB row update only |
| `TranscriptRepository.swift:130-145` | `TranscriptEntry.fetchAll` | SQL literal, `limit` | Local query only |
| `TranscriptRepository.swift:159-160` | `Int.fetchOne` | SQL literal | Local query only |
| `TranscriptRepository.swift:182-204` | `db.makeFTS5Pattern`, `TranscriptEntry.fetchAll` | `rawPattern: trimmedQuery`, `forTable: transcripts_fts`, SQL literal, `pattern` | Local query only |
| `TranscriptRepository.swift:218-231` | `TranscriptEntry.fetchAll` | SQL literal | Local query only |
| `TranscriptRepository.swift:259-274` | `TranscriptEntry.fetchAll` | SQL literal, `lowerBound`, `upperBound` | Local query only |

### Summary judgment

- `FluidAudio`: deny the claim as written. Multiple model-loading/prep paths cross into `FluidAudio`, and those paths can be env- or `UserDefaults`-derived. I found no user IDs and no direct env dictionary/object being passed, but the file-path boundary is already outside policy.
- `GRDB`: mostly within the intended local-SQL shape, but deny strict compliance because the DB path is not forced to remain under the app data dir. Once open, the GRDB payloads are ordinary local SQLite schema/query data only.

## 4) Coverage gaps

- This is an app-side boundary audit only. I did not inspect `FluidAudio` or `GRDB` internals, so I cannot prove what those libraries do with the data once received.
- I did not execute the app, so I cannot prove whether `PERSONAL_SCRIBE_BASE_DIR` / `BaseDirectoryPath` are set in production deployments; the finding is based on reachable code paths.
- I audited all repo-local `import FluidAudio` and `import GRDB` sites plus the requested directories. I did not inspect unrelated packages outside this repo checkout.
- No build/test/runtime verification was performed, per brief.

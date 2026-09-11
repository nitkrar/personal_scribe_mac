# Security Audit — Lane 2: 3p dep API boundary (Claude)

Date: 2026-04-26
Reviewer: Claude (Opus 4.7)
Mode: READ-ONLY. No build, no test, no edits.

---

## 1. Threat-model framing

**In-scope dependencies** (per `Package.swift`): `FluidAudio` and `GRDB`.

**Allowed data crossing the boundary**:
- **FluidAudio**: raw audio PCM samples (`[Float]` at 16kHz mono per `AppConfig`), `AVAudioPCMBuffer` for streaming, plus the on-disk model cache directory URL FluidAudio needs to resolve/load CoreML model artifacts. CoreML config (compute units, low-precision flag) and segmentation config (silence threshold, chunk size).
- **GRDB**: a single local SQLite file path under the app's `recordings/` directory; transcript rows (UUID, timestamp, text, audio/processing durations).

**Forbidden** crossing the boundary:
- Personally-identifying user IDs / account handles.
- Process environment values (`PERSONAL_SCRIBE_BASE_DIR`, `HOME`, etc.) passed verbatim to a 3p call.
- Raw filesystem URLs unrelated to model cache or DB file (transcript text files, clipboard payloads, log files).
- Auth tokens, OAuth secrets, HuggingFace tokens, etc.

The threat is exfiltration via parameter overreach: a 3p with valid intent (e.g. "load model") receiving a parameter that lets it observe data outside the functional scope (e.g. an absolute home path, a user identifier, or a populated environment dict).

The audit walks every callsite into FluidAudio and GRDB symbols and inventories every parameter.

---

## 2. Files audited

### Production sources (in scope)

| File | 3p touched |
| --- | --- |
| `Sources/PersonalScribeTranscription/FluidAudioTranscriber.swift` | FluidAudio (legacy single-model path) |
| `Sources/PersonalScribeTranscription/FluidAudioInferenceClient.swift` | FluidAudio: `AsrManager`, `AsrModels.load` |
| `Sources/PersonalScribeTranscription/Models/Selection/FluidAudioRuntimeVariant.swift` | FluidAudio: `AsrModelVersion` enum (no calls, just enum bridge) |
| `Sources/PersonalScribeTranscription/Models/Selection/ModelAwareFluidAudioInferenceClient.swift` | FluidAudio: `AsrManager`, `AsrModels.load` |
| `Sources/PersonalScribeTranscription/Models/Selection/ModelAwareFluidAudioTranscriber.swift` | FluidAudio (orchestrator only — delegates calls) |
| `Sources/PersonalScribeTranscription/Adapters/FluidAudioParakeetTranscriberAdapter.swift` | FluidAudio: `AsrManager`, `AsrModels.load`, `AsrModelVersion` |
| `Sources/PersonalScribeTranscription/Adapters/FluidAudioQwenTranscriberAdapter.swift` | FluidAudio: `Qwen3AsrManager` (macOS 15+) |
| `Sources/PersonalScribeTranscription/Adapters/FluidAudioStreamingTranscriberAdapter.swift` | FluidAudio: `StreamingEouAsrManager`, `StreamingChunkSize`, `EouCallback`, `PartialCallback` |
| `Sources/PersonalScribeTranscription/Adapters/FluidAudioOfflineDiarizerAdapter.swift` | FluidAudio: `OfflineDiarizerManager`, `DiarizationResult` |
| `Sources/PersonalScribeVAD/FluidAudioVadProvider.swift` | FluidAudio: `VadManager(config:vadModel:)`, `VadConfig`, `VadSegmentationConfig` |
| `Sources/PersonalScribeVAD/FluidAudioVadSession.swift` | FluidAudio: `VadStreamState`, `VadStreamResult`, `VadSegmentationConfig` (closure-driven, no direct call) |
| `Sources/PersonalScribeCore/Database/AppDatabase.swift` | GRDB: `DatabaseQueue(path:)`, `DatabaseWriter`, `Database` |
| `Sources/PersonalScribeCore/Database/TranscriptRepository.swift` | GRDB: `Database.execute`, `db.makeFTS5Pattern`, `TranscriptEntry.fetchAll/insert` |
| `Sources/PersonalScribeCore/Database/Migrations/TranscriptsMigrator.swift` | GRDB: `DatabaseMigrator`, `FTS5`, `db.create(virtualTable:)` |
| `Sources/PersonalScribeCore/TranscriptStore.swift` | GRDB: `FetchableRecord`, `PersistableRecord` conformance for `TranscriptEntry` |
| `Sources/PersonalScribeSession/Models/Selection/AdapterRecord.swift` | none (value type, no 3p calls) |
| `Sources/PersonalScribeSession/Models/Selection/ActiveModelService.swift` | none direct (composes provider; no FluidAudio/GRDB call) |
| `Sources/PersonalScribeSession/Models/Selection/ModelBoundTranscriberProvider.swift` | none direct (composes adapters; just FileManager + URL composition) |
| `Sources/PersonalScribeSession/Models/Selection/ModelBoundProcessorProvider.swift` | none direct (factory composition; stub adapters in this file are placeholders) |
| `Sources/PersonalScribeSession/Models/Selection/ModelBoundTranscriberProviding.swift` | (not read — pure protocol) |
| `Sources/PersonalScribeSession/Models/Selection/ModelBoundProcessorProviding.swift` | (not read — pure protocol) |

### Package manifests

`/Package.swift`, `/Package.resolved` — both read.

### Tests
Skimmed only for the import-graph completeness check (Lane 2 is production-boundary-focused; tests use the same APIs through the seams). No findings flagged in tests.

---

## 3. Findings

### Severity legend
- **Critical**: confirmed exfiltration of forbidden data (user ID, env, secrets) crossing into 3p.
- **High**: parameter shape carries data the 3p does not need and could observe.
- **Medium**: defensible boundary, but worth a follow-up tightening.
- **Low**: cosmetic / docstring drift; no security impact.

---

### F-1 (Medium) — Absolute filesystem URL passed to FluidAudio model loaders

**File / lines:**
- `Sources/PersonalScribeTranscription/FluidAudioInferenceClient.swift:43-47` — `AsrModels.load(from: directory, version: …, progressHandler: …)`
- `Sources/PersonalScribeTranscription/Models/Selection/ModelAwareFluidAudioInferenceClient.swift:39-43` — same
- `Sources/PersonalScribeTranscription/Adapters/FluidAudioParakeetTranscriberAdapter.swift:299-303` — same
- `Sources/PersonalScribeTranscription/Adapters/FluidAudioStreamingTranscriberAdapter.swift:53` — `manager.loadModels(modelDir: modelDirectory)`
- `Sources/PersonalScribeTranscription/Adapters/FluidAudioQwenTranscriberAdapter.swift:148-149` — `manager.loadModels(from: directory)` (live path); also `:131-141` for the directory builder
- `Sources/PersonalScribeTranscription/Adapters/FluidAudioOfflineDiarizerAdapter.swift:138-140` — `manager.prepareModels(directory: storageLocator.url(for: .models).standardizedFileURL)`
- `Sources/PersonalScribeVAD/FluidAudioVadProvider.swift:94-97` — `MLModel(contentsOf: url, ...)` then `VadManager(config:vadModel:)` (CoreML, not FluidAudio per se, but the `url` is the bundled `.mlmodelc` in `Bundle.module` — already the right shape).

**What:** Each adapter passes the absolute on-disk path to its model cache. For ASR adapters this is `<base>/models/<repoFolderName>/`; for the diarizer this is `<base>/models/` (manager appends its own folder); the VAD path is the bundled `.mlmodelc` URL inside the app bundle.

`<base>` resolves via `AppConfig.baseDirectory` in this priority (per `AppConfig.swift:46-50`, `:89-111`):
1. testing override (XCTest only)
2. `PERSONAL_SCRIBE_BASE_DIR` env var
3. `BaseDirectoryPath` UserDefaults
4. `~/Library/Application Support/personal_scribe/`

**Why this is the right call (not a finding upgrade):**
- The model loader functionally needs an on-disk directory — it reads/writes CoreML compiled artifacts there. There is no smaller-surface API.
- The path leaks the user's home username into the 3p (default is `~/Library/Application Support/...`, which expands to `/Users/<unixname>/...`) — but that is unavoidable: CoreML / FluidAudio work by file path, not by file handle. This matches the threat-model's "what the dep functionally needs."
- No env values, no UserDefaults dictionary, and no user identifier are passed; only the resolved URL.

**Mitigation (defensive, not blocking):** If we ever want to scrub the username from logs/telemetry that FluidAudio internally emits, the lever is to set the base directory via `setBaseDirectoryOverride` to a path under `/private/tmp/` for tests, or document a Sandbox container path in production. Not actionable from this lane.

**Verdict:** No real finding. Recorded as Medium-noted to acknowledge the deliberate path-leak surface.

---

### F-2 (Medium) — `FluidAudioOfflineDiarizerAdapter` passes the **parent** models directory, not a model-specific subdirectory

**File / lines:** `Sources/PersonalScribeTranscription/Adapters/FluidAudioOfflineDiarizerAdapter.swift:131-141`

```swift
func performPrepare() async throws {
    guard descriptor.engine == .diarization else { … }
    try storageLocator.ensureDirectoriesExist()
    // `OfflineDiarizerManager` expects the models root directory and
    // appends FluidAudio's diarizer repo folder internally.
    try await manager.prepareModels(
        directory: storageLocator.url(for: .models).standardizedFileURL
    )
}
```

**What:** This adapter (uniquely among ASR adapters) hands FluidAudio the *root* `models/` directory. FluidAudio is then trusted to append its own subfolder name. Every other adapter scopes the URL down to a specific `models/<repoFolderName>/` subdirectory before calling the 3p.

**Why this matters:** the diarizer manager has read/write authority over the *entire* models root, including sibling Parakeet / Qwen artifacts, on the trust assumption that it will write only into its declared folder. This is a wider blast radius than the other adapters offer their respective managers. If FluidAudio's diarizer ever changes its internal folder selection (e.g. a version bump renames it) it could collide with another adapter's files. Note: per the bundled-model trap memory (`project_fluidaudio_model_bundling`), FluidAudio managers have historically silently re-downloaded under unfamiliar layouts — a wider-scoped directory amplifies that risk.

**Mitigation:** create the diarizer's `<repoFolderName>` subdirectory locally and pass that URL — matching every other adapter. The descriptor already declares `repoFolderName: "speaker-diarization"` (`Sources/PersonalScribeCore/Models/Selection/BuiltInModelCatalog.swift:258`), so this is mechanical. Requires confirming `OfflineDiarizerManager.prepareModels(directory:)` accepts a leaf directory — the inline comment claims it expects the parent, so this would need a small upstream check / a wrapper that lies about parentage.

**Verdict:** Worth a follow-up ticket. Not a current data-exfiltration finding (the diarizer model is a 3p artifact under our own filesystem; we're not handing it sensitive data, just wider write authority over our own cache).

---

### F-3 (Low) — VAD load is constrained to `Bundle.module` URL by design

**File / lines:** `Sources/PersonalScribeVAD/FluidAudioVadProvider.swift:46-57, 87-103`

The VAD provider deliberately avoids `VadManager(modelDirectory:)` (which would silently download from HuggingFace per the inline comment at lines 11-15 and the `project_fluidaudio_model_bundling` memory). It compiles the bundled `silero-vad.mlmodelc` via `MLModel(contentsOf:)` and hands the materialized `MLModel` to `VadManager(config:vadModel:)`. Network is never invoked for VAD.

**What's passed to FluidAudio**: `VadConfig.default` (with `computeUnits` and `allowLowPrecisionAccumulationOnGPU = true`) and the loaded `MLModel`. Per session: `VadSegmentationConfig(minSilenceDuration:)` and the streaming inference closure invoked over PCM chunks.

**Verdict:** No finding. This is the defensive shape we want. Recorded for Lane 1 / Lane 3 to confirm the network audit picks up that VAD has no `VadManager(modelDirectory:)` call anywhere.

---

### F-4 (Low) — GRDB receives only the local SQLite file path; no env, no user IDs

**File / lines:**
- `Sources/PersonalScribeCore/Database/AppDatabase.swift:42-57` — constructs `databaseURL` from `locator.url(for: .recordings) + filename`, then `DatabaseQueue(path: databaseURL.path)`. Standardized URL only.
- `:75-86` — `database.write` / `database.read` accept `@Sendable (Database) throws -> T` closures. The closure bodies (in `TranscriptRepository.swift`) execute SQL with parameter binding (`arguments: [id.uuidString]`, `[text, id.uuidString]`, etc.). All bound values are transcript-scoped: UUID string, transcript text, timestamp, audio/processing duration.
- `Sources/PersonalScribeCore/Database/TranscriptRepository.swift` — every `db.execute` / `fetchAll` callsite I inspected uses parameter binding; no string interpolation of user-supplied values into SQL. The `entries(in:orderedBy:)` builds an `ORDER BY` direction from a sealed `TranscriptOrder` enum (`ASC` / `DESC`), not from caller text — safe.
- `Sources/PersonalScribeCore/Database/Migrations/TranscriptsMigrator.swift` — DDL is static literals; no caller-supplied values reach the DDL.
- `Sources/PersonalScribeCore/TranscriptStore.swift:42-72` — `init(row:)` and `encode(to:)` map only the five canonical columns.

**What FTS5 receives** (`TranscriptRepository.search`, lines 175-213): `db.makeFTS5Pattern(rawPattern: trimmedQuery, forTable: ...)`. Using GRDB's pattern builder rather than raw concatenation; the search query is the user's own typed query against their own DB — by definition not a privacy boundary issue.

**Verdict:** No finding. GRDB's surface is the smallest functionally possible: a local SQLite path + parameterized SQL.

---

### F-5 (Informational) — `ProcessInfo.processInfo.environment` is read inside `AppConfig.resolvedBaseDirectory` but only the `PERSONAL_SCRIBE_BASE_DIR` value is consulted

**File / lines:** `Sources/PersonalScribeCore/Storage/AppConfig.swift:53-65, 89-111`

The full env dict is passed *into* `AppConfig.baseDirectory(...)`'s parameter, but only `environment[baseDirectoryEnvironmentVariableName]` (i.e. `PERSONAL_SCRIBE_BASE_DIR`) is read. The dict is never forwarded to FluidAudio or GRDB.

**Verdict:** No finding. Recorded so Lane 1 reviewers don't double-count this on the boundary side.

---

### F-6 (Informational) — `physicalMemory` is read for default-model heuristic; never sent to 3p

**File / lines:** `Sources/PersonalScribeSession/Models/Selection/ActiveModelService.swift:70`

`Int64(ProcessInfo.processInfo.physicalMemory)` is consulted to pick a lightweight vs baseline ASR model on first launch. Stays inside our own decision logic; not passed to FluidAudio or GRDB.

**Verdict:** No finding.

---

### Summary of findings

- **Critical / High: none.**
- **Medium**: 1 acknowledged-by-design (F-1: model-cache URL leaks `/Users/<unixname>/...` to FluidAudio, unavoidable given CoreML's path-based contract). 1 worth a follow-up (F-2: diarizer adapter passes the parent `models/` directory rather than a scoped subdirectory).
- **Low / Informational**: 3 (F-3 VAD shape is defensive; F-4 GRDB shape is minimal; F-5/F-6 environment + RAM probes stay local).

No data classified as forbidden by the threat model (user IDs, secrets, env dicts, unrelated absolute paths) is observed crossing into FluidAudio or GRDB.

---

## 3a. Package manifest inventory

Per `Package.swift` (lines 40-49) and `Package.resolved`:

| Identity | URL | Constraint | Resolved version | Resolved revision |
| --- | --- | --- | --- | --- |
| `fluidaudio` | https://github.com/FluidInference/FluidAudio.git | `.exact("0.13.6")` | `0.13.6` | `57551cd90e0bbec342766244358bcf08afb05290` |
| `grdb.swift` | https://github.com/groue/GRDB.swift.git | `.exact("7.10.0")` | `7.10.0` | `36e30a6f1ef10e4194f6af0cff90888526f0c115` |

Both deps are pinned to **exact** versions (no range, no branch, no revision-only). `Package.resolved` `originHash` = `d5091654bb52355ee4f5ca9547ff42b5dd9cbe9a91f3b32346ce5b142a473298`. The exact-pin posture means a CI or contributor re-resolve cannot silently roll either dep forward.

---

## 4. Coverage gaps

1. **FluidAudio internals not audited.** This lane proves what *we hand to* FluidAudio. It does not prove FluidAudio doesn't perform out-of-band network calls (e.g., telemetry, HuggingFace cache repair) once it has the model directory. That's the network/Lane-1 lane's job. The relevant evidence handed to the network lane: every `AsrModels.load` / `loadModels(from:)` / `prepareModels(directory:)` call passes only an on-disk URL — but FluidAudio's `VadManager(modelDirectory:)` is documented (in `FluidAudioVadProvider.swift:11-15` and the `project_fluidaudio_model_bundling` memory) to silently fetch from HuggingFace on layout mismatch, so the network lane should grep upstream FluidAudio for similar download fall-throughs in `AsrModels.load`, `OfflineDiarizerManager.prepareModels`, `Qwen3AsrManager.loadModels`, and `StreamingEouAsrManager.loadModels`.

2. **`StreamingEouAsrManager` callbacks.** `setEouCallback` and `setPartialCallback` are set with closures that capture an `AsyncThrowingStream.Continuation` (`FluidAudioStreamingTranscriberAdapter.swift:133-138`). The closures forward only `text: String` from the manager into our pipeline — the boundary is *return* shape, not parameter shape, so it doesn't widen the exfiltration surface. Worth a glance from the network lane to confirm no FluidAudio-internal context (e.g. logging hooks) is wired through.

3. **Reflection-based result extraction in `FluidAudioParakeetResultExtractor`** (`FluidAudioParakeetTranscriberAdapter.swift:323-561`) reads from FluidAudio's result type via `Mirror`. This is *consumption*, not *passing-in*, so it's outside Lane 2 scope, but it does mean any field FluidAudio adds to its result type is silently visible to us; the converse (us writing into FluidAudio) is not at risk.

4. **`Tests/` callsites not enumerated parameter-by-parameter.** Tests use the same FluidAudio/GRDB seams. Not a security gap (test-time data is synthetic), but if a future test introduces a real-data fixture path that points outside the test temp dir, the lane would not catch it. Out of scope.

5. **`AppKit` target imports of FluidAudio/GRDB.** None found via the import grep — `PersonalScribeAppKit` consumes only the `PersonalScribe*` modules. Confirmed.

6. **`ModelBoundProcessorProvider.swift` contains private stub adapter classes** (`FluidAudioParakeetTranscriberAdapter`, `FluidAudioQwenTranscriberAdapter`, `FluidAudioStreamingTranscriberAdapter`, `FluidAudioOfflineDiarizerAdapter` at lines 390-569 — same names but private to the file). These are placeholder/stub implementations that materialize fake artifacts (`coremldata.bin = 0x01`, `*.json = "{}"`) for the in-progress #078 work. They do not import or call FluidAudio symbols themselves; the live adapters with the same names live in the `Adapters/` subfolder. Worth a follow-up to disambiguate the naming so a future reviewer doesn't conflate them, but no security implication today.

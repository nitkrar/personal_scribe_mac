# A — FluidAudio silent second download verification

Research verifies the hypothesis: after our `PrivateModelDownloader` drops 5 stub files into the model directory and we call `AsrModels.load(from:version:)`, FluidAudio's first load fails (MLModel can't compile a mlmodelc missing `weights/weight.bin`), FluidAudio silently wipes the cache, and its internal `DownloadUtils.downloadRepo` refetches the entire ~450MB payload from HuggingFace via its own `URLSession`. Our code does not pass any progress handler, so those bytes fly by invisible to our UI while the pill sits on `.loading`.

Pinned version: `FluidAudio 0.13.6` (revision `57551cd90e0bbec342766244358bcf08afb05290`) per `Package.resolved:9-10`.

## FluidAudio source location

- Checked out at `/Users/nitinkum/Projects/nitkrar/personal_scribe/.build/checkouts/FluidAudio/`.
- Library sources under `.../FluidAudio/Sources/FluidAudio/`.
- Relevant files:
  - `Sources/FluidAudio/ASR/Parakeet/AsrModels.swift`
  - `Sources/FluidAudio/ASR/Parakeet/AsrManager.swift`
  - `Sources/FluidAudio/DownloadUtils.swift`
  - `Sources/FluidAudio/ModelRegistry.swift`
  - `Sources/FluidAudio/ModelNames.swift`

## AsrModels.load behavior

`AsrModels.load(from:configuration:version:progressHandler:)` delegates to `DownloadUtils.loadModels` once for preprocessor+encoder and once more for decoder+joint:

```
// .build/checkouts/FluidAudio/Sources/FluidAudio/ASR/Parakeet/AsrModels.swift:177-200
public static func load(
    from directory: URL,
    configuration: MLModelConfiguration? = nil,
    version: AsrModelVersion = .v3,
    progressHandler: DownloadUtils.ProgressHandler? = nil
) async throws -> AsrModels {
    ...
    let parentDirectory = directory.deletingLastPathComponent()
    let specs = createModelSpecs(using: config, version: version)
    ...
    for spec in specs {
        let models = try await DownloadUtils.loadModels(
            version.repo,
            modelNames: [spec.fileName],
            directory: parentDirectory,        // <-- NB: uses parent, not directory
            computeUnits: spec.computeUnits,
            progressHandler: progressHandler
        )
```

Inside `DownloadUtils.loadModels` (wrapping `loadModelsOnce`), a corrupt-model `catch` deletes the whole repo folder and reruns `loadModelsOnce`, which will then fall through the missing-files branch and call `downloadRepo`:

```
// .build/checkouts/FluidAudio/Sources/FluidAudio/DownloadUtils.swift:127-143
do {
    return try await loadModelsOnce(...)
} catch {
    logger.warning("First load failed: \(error.localizedDescription)")
    logger.info("Deleting cache and re-downloading…")
    let repoPath = directory.appendingPathComponent(repo.folderName)
    try? FileManager.default.removeItem(at: repoPath)

    return try await loadModelsOnce(...)
}
```

`loadModelsOnce` decides whether to download purely on `FileManager.default.fileExists(atPath:)` for each model name — which returns true for any directory that exists, even an empty one:

```
// .build/checkouts/FluidAudio/Sources/FluidAudio/DownloadUtils.swift:191-199
let requiredModels = ModelNames.getRequiredModelNames(for: repo, variant: variant)
let allModelsExist = requiredModels.allSatisfy { model in
    let modelPath = repoPath.appendingPathComponent(model)
    return FileManager.default.fileExists(atPath: modelPath.path)
}

if !allModelsExist {
    logger.info("Models not found in cache at \(repoPath.path)")
    try await downloadRepo(repo, to: directory, variant: variant, progressHandler: progressHandler)
}
```

`getRequiredModelNames(for: .parakeet, variant: nil)` returns `ModelNames.ASR.requiredModels` = `{Preprocessor.mlmodelc, Encoder.mlmodelc, Decoder.mlmodelc, JointDecision.mlmodelc}` (`ModelNames.swift:220-225, 658-659`).

### What happens if `weights/weight.bin` is missing but `coremldata.bin` exists

Given the scenario in the prompt (our downloader has dropped `coremldata.bin` into each `.mlmodelc` directory but the weight payload is missing):

1. First pass through `loadModelsOnce` sees all 4 `.mlmodelc` directories exist → `allModelsExist == true` → skips `downloadRepo`.
2. Emits progress `0.5 / .downloading(completedFiles: 0, totalFiles: 0)` as a no-op marker (`DownloadUtils.swift:202-203`).
3. The per-model directory check + `coremldata.bin` guard (`DownloadUtils.swift:213-244`) passes (we have those files).
4. Emits `phase: .compiling(modelName:)` (`DownloadUtils.swift:246-250`), then calls `MLModel(contentsOf: modelPath, configuration: config)` (`DownloadUtils.swift:253`).
5. CoreML throws because `weights/weight.bin` is missing.
6. The outer `catch` in `loadModels` (`DownloadUtils.swift:132-142`) fires: logs `"First load failed"`, removes the entire `repoPath` (wiping our 5 stub files), calls `loadModelsOnce` again.
7. Second pass: all directories have been deleted → `allModelsExist == false` → enters `downloadRepo` branch.
8. `downloadRepo` lists the HF tree via `https://huggingface.co/api/models/<repo>/tree/main` and downloads every matching file (`DownloadUtils.swift:295-465`) — the real ~450MB payload.

`AsrModels.load` runs this cycle twice (once for preprocessor+encoder, once for decoder+joint — `AsrModels.swift:193-225`), so in the worst case we re-enter the `loadModels` retry path twice.

## AsrManager.loadModels behavior

`AsrManager.loadModels(_:)` is a pure assignment — no disk I/O, no network:

```
// .build/checkouts/FluidAudio/Sources/FluidAudio/ASR/Parakeet/AsrManager.swift:112-128
public func loadModels(_ models: AsrModels) async throws {
    logger.info("Initializing AsrManager with provided models")
    self.asrModels = models
    self.preprocessorModel = models.preprocessor
    self.encoderModel = models.encoder
    self.decoderModel = models.decoder
    self.jointModel = models.joint
    self.vocabulary = models.vocabulary

    let layers = models.version.decoderLayers
    self.microphoneDecoderState = TdtDecoderState.make(decoderLayers: layers)
    self.systemDecoderState = TdtDecoderState.make(decoderLayers: layers)
    ...
}
```

All network happens earlier inside `AsrModels.load` → `DownloadUtils.loadModels`. `AsrManager.loadModels` itself is purely in-memory.

## Progress hook availability

A progress hook **does** exist, and it is plumbed through every public entry point on `AsrModels`:

- Type alias: `DownloadUtils.ProgressHandler` (closure).
- Callback signature:

  ```
  // .build/checkouts/FluidAudio/Sources/FluidAudio/DownloadUtils.swift:80-106
  public enum DownloadPhase: Sendable {
      case listing
      case downloading(completedFiles: Int, totalFiles: Int)
      case compiling(modelName: String)
  }

  public struct DownloadProgress: Sendable {
      public let fractionCompleted: Double   // 0...1
      public let phase: DownloadPhase
  }

  public typealias ProgressHandler = @Sendable (DownloadProgress) -> Void
  ```
- Accepting entry points all expose the same handler parameter:
  - `AsrModels.load(from:configuration:version:progressHandler:)` — `AsrModels.swift:177-182`
  - `AsrModels.loadFromCache(configuration:version:progressHandler:)` — `AsrModels.swift:332-336`
  - `AsrModels.loadWithAutoRecovery(from:configuration:progressHandler:)` — `AsrModels.swift:344-348`
  - `AsrModels.download(to:force:version:progressHandler:)` — `AsrModels.swift:399-403`
  - `AsrModels.downloadAndLoad(to:configuration:version:progressHandler:)` — `AsrModels.swift:460-465`
  - `DownloadUtils.loadModels(_:modelNames:directory:computeUnits:variant:progressHandler:)` — `DownloadUtils.swift:118-124`
  - `DownloadUtils.downloadRepo(_:to:variant:progressHandler:)` — `DownloadUtils.swift:268-273`
- Byte-level progress lives in `DownloadUtils.downloadWithProgress` (`DownloadUtils.swift:489-509`) backed by a `URLSessionDownloadDelegate` (`DownloadUtils.swift:665-689`), and `downloadRepo` emits `.downloading(completedFiles:totalFiles:)` + `fractionCompleted` events in the 0.0–0.5 band (`DownloadUtils.swift:411-464`).

So FluidAudio does expose a full progress stream for its second download — we're just not wired to it.

## Our wiring — are we passing progress?

No. Both entry points call `AsrModels.load(from:version:)` with no `progressHandler:` argument:

```
// Sources/PersonalScribeTranscription/Models/Selection/ModelAwareFluidAudioInferenceClient.swift:24-33
func loadModel(
    from directory: URL,
    runtimeVariant: FluidAudioRuntimeVariant
) async throws {
    let models = try await AsrModels.load(
        from: directory,
        version: runtimeVariant.asrModelVersion
    )
    try await resolvedManager().loadModels(models)
}
```

```
// Sources/PersonalScribeTranscription/FluidAudioInferenceClient.swift:28-37
func loadModel(
    from directory: URL,
    runtimeVariant: FluidAudioRuntimeVariant
) async throws {
    let models = try await AsrModels.load(
        from: directory,
        version: runtimeVariant.asrModelVersion
    )
    try await resolvedManager().loadModels(models)
}
```

Callsite context confirms the pill flips to `.loading` *before* the FluidAudio call is made, then sits there until `AsrModels.load` returns:

```
// Sources/PersonalScribeTranscription/Models/Selection/ModelAwareFluidAudioTranscriber.swift:225-248
progressBroadcaster.update(
    .init(phase: .loading, fractionCompleted: 1, receivedBytes: 0, expectedBytes: nil)
)

do {
    ...
    try await inference.loadModel(
        from: modelDirectory,
        runtimeVariant: runtimeVariant
    )
    ...
}
```

### Why `PrivateModelDownloader` produces the stub that triggers this

Our descriptor ships the minimum set of paths needed for our own `modelArtifactsAreValid` check:

```
// Sources/PersonalScribeCore/Models/Selection/BuiltInModelCatalog.swift:4-17
private static let splitFrontendRequiredPaths = [
    "Preprocessor.mlmodelc/coremldata.bin",
    "Encoder.mlmodelc/coremldata.bin",
    "Decoder.mlmodelc/coremldata.bin",
    "JointDecision.mlmodelc/coremldata.bin",
    "parakeet_vocab.json",
]
```

`PrivateModelDownloader.ensureModelAvailable` (`Sources/PersonalScribeTranscription/FluidAudioModelDownloader.swift:37-94`) downloads exactly those 5 paths and nothing else. And `modelArtifactsAreValid` (`Sources/PersonalScribeTranscription/Models/Selection/ModelAwareFluidAudioTranscriber.swift:328-360`) verifies `coremldata.bin > 0 bytes` + vocab JSON parses — it never checks for `weights/weight.bin` or `model.mil`. So from our side the download looks "complete" and we advance to `.loading`; FluidAudio then takes over and pulls the rest.

Secondary issue: our `ModelDescriptor.resolveURL` uses `revision: "ee09c569f73759e6d44c9bd16766f477b2b36d39"` for parakeet v2 (`BuiltInModelCatalog.swift:22`), but `ModelRegistry.resolveModel` hard-codes `resolve/main/` (`ModelRegistry.swift:56-62`). FluidAudio's silent redownload therefore ignores our pinned revision and pulls whatever `main` currently points at.

## Conclusion

Yes, with caveat: FluidAudio's `AsrModels.load` downloads missing weights from HuggingFace when the `.mlmodelc` directories exist but their interiors (`weights/weight.bin`, `model.mil`) are missing — not by explicit "missing weight" detection, but via a corrupt-model retry path where the first `MLModel(contentsOf:)` throws, `DownloadUtils.loadModels` wipes the repo folder, and the second pass hits the missing-directories branch and invokes `downloadRepo` from `huggingface.co/.../resolve/main/<path>`. The progress stream exists (`DownloadUtils.ProgressHandler`), but neither `PrivateModelAwareFluidAudioInferenceClient` nor `FluidAudioInferenceClient` passes one in, so the ~450MB second fetch runs silently while our UI shows `.loading`.

# D — Phase-emission trace + pinning tests

Research-only. All citations file:line.

---

## Step-by-step verification

### Step 1 — `BuiltInModelCatalog.swift:4–17` declares only 5 required paths ✅

`/Users/nitinkum/Projects/nitkrar/personal_scribe/Sources/PersonalScribeCore/Models/Selection/BuiltInModelCatalog.swift:4-17` defines two `requiredRelativePaths` lists, both listing **only** `coremldata.bin` files plus `parakeet_vocab.json`:

- `splitFrontendRequiredPaths` (BuiltInModelCatalog.swift:4–10) — 5 items: `Preprocessor/Encoder/Decoder/JointDecision.mlmodelc/coremldata.bin` + `parakeet_vocab.json`. Applied to `parakeet-tdt-0.6b-v2` (line 24) and `parakeet-tdt-0.6b-v3` (line 51).
- `fusedFrontendRequiredPaths` (BuiltInModelCatalog.swift:12–17) — 4 items (no Encoder). Applied to `parakeet-tdt-ctc-110m` (line 38).

No `weights/weight.bin`, no `model.mil`, no `.mlmodelc/metadata.json`, no `.mlmodelc/analytics/coremldata.bin`. **Hypothesis Step 1 confirmed.**

### Step 2 — `PrivateModelDownloader.ensureModelAvailable` iterates only descriptor paths ✅

`/Users/nitinkum/Projects/nitkrar/personal_scribe/Sources/PersonalScribeTranscription/FluidAudioModelDownloader.swift:37`:

```swift
for (index, relativePath) in descriptor.requiredRelativePaths.enumerated() {
```

The loop body (FluidAudioModelDownloader.swift:37–94) fetches exactly the listed paths and emits `.downloading` with `fractionCompleted = (Double(index) + fileFraction) / Double(descriptor.requiredRelativePaths.count)` (FluidAudioModelDownloader.swift:66–69). Per-file progress inside the loop uses `response.expectedContentLength` bytes (line 53), so *within* a file the fraction is byte-based — but the *overall* fraction is file-count-based across only the 5 items. On a warm, unthrottled network, 5 tiny `coremldata.bin` files (all bytes-trivial — the real weights live in `.mil` / `weight.bin` which are NOT in the list) complete in well under a second. Final per-file emission at FluidAudioModelDownloader.swift:86–93 pushes `fractionCompleted = (index + 1) / 5`. **Hypothesis Step 2 confirmed.**

Minor correction to the hypothesis phrasing: the intra-file progress *is* byte-based (it's not purely file-count — per-file increments track `receivedContentLength`). But the **overall fraction denominator is `requiredRelativePaths.count`**, so the net macro behaviour (quickly fills to 1.0 because the 5 listed files are tiny) matches the hypothesis.

### Step 3 — `.loading` emitted as soon as `ensureValidDownloadedModel` returns ✅

`/Users/nitinkum/Projects/nitkrar/personal_scribe/Sources/PersonalScribeTranscription/Models/Selection/ModelAwareFluidAudioTranscriber.swift:221-227`:

```swift
if !Self.modelArtifactsAreValid(in: modelDirectory, descriptor: descriptor) {
    try await ensureValidDownloadedModel(at: modelDirectory, externalProgress: nil)
}

progressBroadcaster.update(
    .init(phase: .loading, fractionCompleted: 1, receivedBytes: 0, expectedBytes: nil)
)
```

Claude cited lines 225–227; the update call actually starts at line 225 and ends at 227, and the gating block is 221–223. Emit happens unconditionally after the (possibly-skipped) download. **Hypothesis Step 3 confirmed** (cite corrected to 221–227).

### Step 4 — `AsrModels.load(from:version:)` is the `.loading` dwell ✅ (with a note)

`/Users/nitinkum/Projects/nitkrar/personal_scribe/Sources/PersonalScribeTranscription/Models/Selection/ModelAwareFluidAudioInferenceClient.swift:28-31`:

```swift
let models = try await AsrModels.load(
    from: directory,
    version: runtimeVariant.asrModelVersion
)
```

Called from `performPrepare` (ModelAwareFluidAudioTranscriber.swift:233–236) **after** the `.loading` emission. `AsrModels` is an external `FluidAudio` package symbol (imported at ModelAwareFluidAudioInferenceClient.swift:1); we cannot read its source from this repo, so the claim that it "downloads the missing real weights silently" is **plausible but not directly verifiable here**. What *is* verifiable:

- No pre-`loadModel` validation in our code inspects `weight.bin` / `model.mil` presence (see next section).
- The only files our downloader ever writes under `modelDirectory` are the 5 listed in `requiredRelativePaths`.
- Therefore, for `AsrManager.loadModels(models)` (ModelAwareFluidAudioInferenceClient.swift:32) to actually run Parakeet end-to-end, *something* must materialise the weight files between `.loading` emission and first `transcribe(_:)` call. No code path in this repo does that except `AsrModels.load`.

**Hypothesis Step 4 confirmed by elimination.** Exact "silent download" attribution belongs to FluidAudio; what's in-repo is the **absence** of weight-file handling on our side.

### Step 5 — Net symptom: short `.downloading` → long `.loading` ✅

Follows from Steps 1–4. The progress broadcaster (ModelAwareFluidAudioTranscriber.swift:362–404) emits `.downloading` snapshots during the 5-file loop (seconds at most on a decent link), then one `.loading` snapshot, then nothing until `AsrModels.load` returns — which for a first-run ~450MB download is minutes. **Hypothesis Step 5 confirmed.**

---

## `modelArtifactsAreValid` — stub-permissive?

**Yes, confirmed stub-permissive.** Two copies exist, both with identical permissive logic.

### Copy 1 — `ModelArtifactStaging.modelArtifactsAreValid` (authoritative, public)

`/Users/nitinkum/Projects/nitkrar/personal_scribe/Sources/PersonalScribeTranscription/ModelArtifactStaging.swift:37-71`:

```swift
public static func modelArtifactsAreValid(
    in directory: URL,
    descriptor: ModelDescriptor
) -> Bool {
    guard modelsExist(in: directory, descriptor: descriptor) else {
        return false
    }
    ...
    for path in requiredModelPaths(in: directory, descriptor: descriptor)
    where path.lastPathComponent == "coremldata.bin" {
        guard
            let attributes = try? fileManager.attributesOfItem(atPath: path.path),
            let size = attributes[.size] as? NSNumber,
            size.intValue > 0
        else {
            return false
        }
    }
    ...
}
```

Three checks only:
1. `modelsExist` (ModelArtifactStaging.swift:15–19) — plain `fileExists` for each path in `requiredRelativePaths`. Only the 5 listed paths, no weights.
2. For each `coremldata.bin` in that list — file exists + size > 0.
3. `parakeet_vocab.json` — non-empty, first non-whitespace char is `{` or `[`.

**Weight files (`weights/weight.bin`, `model.mil`) are never checked.** A 1-byte `coremldata.bin` per directory + `{}` vocab passes — exactly what `TestModelArtifacts.writeValid` produces (Tests/PersonalScribeTranscriptionTests/Support/TranscriptionTestSupport.swift:7–27).

### Copy 2 — `ModelAwareFluidAudioTranscriber.modelArtifactsAreValid` (private, duplicate)

`/Users/nitinkum/Projects/nitkrar/personal_scribe/Sources/PersonalScribeTranscription/Models/Selection/ModelAwareFluidAudioTranscriber.swift:328-359`:

```swift
static func modelArtifactsAreValid(in directory: URL, descriptor: ModelDescriptor) -> Bool {
    guard ModelArtifactStaging.modelsExist(in: directory, descriptor: descriptor) else {
        return false
    }
    ...
    for path in ModelArtifactStaging.requiredModelPaths(in: directory, descriptor: descriptor)
    where path.lastPathComponent == "coremldata.bin" {
        ...
    }
    let vocabURL = directory.appendingPathComponent("parakeet_vocab.json", isDirectory: false)
    ...
    first == "{" || first == "["
    ...
}
```

**Identical logic, not drifted.** Only cosmetic diff: this copy names the string variable `first` directly, while the public copy in ModelArtifactStaging.swift names it `contents`. Same three checks, same permissiveness. Calls `ModelArtifactStaging.modelsExist` / `.requiredModelPaths` for the file-list half but reimplements the coremldata size + vocab checks.

---

## Relaunch-after-partial-download flow trace

Scenario: first launch starts. The downloader writes the 5 listed files into the final `modelDirectory` (via stage-and-move at FluidAudioModelDownloader.swift:96–97). `AsrModels.load` then begins its silent weight download, but the user force-quits (or the OS reaps) before it finishes.

On relaunch:

1. `PersonalScribeSession/Models/Selection/ModelBoundTranscriberProvider.swift:16` constructs a new `ModelAwareFluidAudioTranscriber`.
2. First `prepare()` call reaches `performPrepare` → `ModelAwareFluidAudioTranscriber.swift:221`:

   ```swift
   if !Self.modelArtifactsAreValid(in: modelDirectory, descriptor: descriptor) {
       try await ensureValidDownloadedModel(at: modelDirectory, externalProgress: nil)
   }
   ```

3. `modelArtifactsAreValid` runs the three permissive checks above. Because the staged-and-moved 5 files (ModelAwareFluidAudioTranscriber.swift:328–359) are on disk — our downloader wrote them in step 1 of the prior run — **the guard returns `true`** and `ensureValidDownloadedModel` is **skipped entirely**.
4. Control falls through to the `.loading` emit (ModelAwareFluidAudioTranscriber.swift:225–227) immediately, then `inference.loadModel(...)` → `AsrModels.load(from:version:)` (ModelAwareFluidAudioInferenceClient.swift:28–31).
5. `AsrModels.load` finds the 5 stub files but **no weights**, and re-runs whatever fetch logic it has internally to materialise the real weights.

**Consequence:** on relaunch after a partial first download, the user sees **no `.downloading` phase at all** — the UI jumps straight from `.idle` to `.loading`, and then sits there for minutes while FluidAudio silently downloads the weights our code never fetched. Our broadcaster emits zero `.downloading` snapshots because our code believes the model is valid. The entire "download the big weights" responsibility has leaked into FluidAudio, which has no hook into our `ModelDownloadProgress` stream.

This also means **the progress bar can never accurately reflect the real first-run download** — the 450MB that matters for UX is invisible to our broadcaster by construction.

---

## Tests that pin current behavior

These tests will fail if we expand `requiredRelativePaths` to include the real weights, or if we make `modelArtifactsAreValid` check weight files. They encode the "5 listed paths + permissive validation" contract.

| Test | File:line | What it pins |
|---|---|---|
| `testPrepareOnCachedModelEmitsLoadingWithoutDownloading` | `Tests/PersonalScribeTranscriptionTests/ModelDownloadProgressTests.swift:74-102` | Pre-seeds `TestModelArtifacts.writeValid` (stub 1-byte `coremldata.bin` + `{}` vocab). Asserts `snapshots.map(\.phase) == [.idle, .loading, .finished]` and `!snapshots.contains { $0.phase == .downloading }`. Pins "stub artifacts are accepted as valid" — if we tighten validation, this fails because the pre-seed won't satisfy the stricter check. |
| `testPrepareSkipsDownloadWhenModelAlreadyOnDisk` | `Tests/PersonalScribeTranscriptionTests/FluidAudioTranscriberAlreadyDownloadedTests.swift:43-55` | Same setup, records URL requests, asserts `requests.isEmpty`. Directly relies on permissive validation returning `true` after `TestModelArtifacts.writeValid` — the exact "stub files = valid" assumption. |
| `TestModelArtifacts.writeValid` | `Tests/PersonalScribeTranscriptionTests/Support/TranscriptionTestSupport.swift:7-27` | Shared fixture: writes a 1-byte `coremldata.bin` in each of the 4 `.mlmodelc` dirs plus `{}` vocab. Not a test itself but every test that asserts "model is valid after this fixture runs" transitively pins permissive validation. |
| `testCorruptDownloadRetriesOnceThenSucceeds` | `Tests/PersonalScribeTranscriptionTests/ModelIntegrityTests.swift:6-17` | Uses `RetryingStubModelDownloader` where `.corrupt` calls `writeCorrupt` (empty vocab, no `.mlmodelc` dirs) and `.valid` calls `writeValid`. Defines "corrupt" as *missing the 5 files or empty vocab* — any stricter definition of corrupt would need the fixtures updated. |

---

## Tests that are fix-compatible

These tests don't assume anything about which paths are in `requiredRelativePaths` or whether validation inspects weights; they'd keep passing if we expanded the path list and/or made validation strict.

| Test | File:line | Why it survives |
|---|---|---|
| `testDownloaderUsesPinnedRevision` | `Tests/PersonalScribeTranscriptionTests/ModelDownloadTests.swift:6-16` | Iterates whatever `requiredRelativePaths` contains and asserts each URL uses the pinned revision. Adding weight paths just adds more URLs — all still pinned. |
| `testPrepareEmitsIdleDownloadingLoadingFinishedExactlyOnce` | `Tests/PersonalScribeTranscriptionTests/ModelDownloadProgressTests.swift:6-40` | Uses `StubModelDownloader` with scripted progress (bypasses real file list). Asserts the phase sequence contains `.idle`, some `.downloading`, `.loading`, exactly one `.finished`, and monotonic fractions. Works regardless of which files the real downloader would fetch. |
| `testDownloadProgressAllowsNilExpectedBytesWhenContentLengthMissing` | `Tests/PersonalScribeTranscriptionTests/ModelDownloadProgressTests.swift:42-72` | Same — scripted stub, asserts nil-expected-bytes tolerance. No real-file-list dependency. |
| `testPrepareMapsDownloadFailureToSharedError` | `Tests/PersonalScribeTranscriptionTests/ModelDownloadFailureTests.swift:6-20` | Stub throws `.notConnectedToInternet`; asserts `PersonalScribeError.modelDownloadFailure`. Path-list-agnostic. |
| `testPrepareResetsProgressToIdleAfterDownloadFailure` | `Tests/PersonalScribeTranscriptionTests/ModelDownloadFailureTests.swift:22-55` | Asserts idle-reset on failure. Path-list-agnostic. |
| `testPrepareIsNoOpAfterSuccessfulFirstLoad` | `Tests/PersonalScribeTranscriptionTests/PrepareIdempotenceTests.swift:6-21` | Asserts `ensureCallCount == 1 && loadCount == 1` across two `prepare()` calls. Stub-driven; agnostic to path list. |
| `testConcurrentPrepareCallsShareOneTask` | `Tests/PersonalScribeTranscriptionTests/PrepareIdempotenceTests.swift:23-39` | Same; concurrent call coalescing. Agnostic. |
| `testCorruptDownloadTwiceThrowsModelDownloadFailure` | `Tests/PersonalScribeTranscriptionTests/ModelIntegrityTests.swift:19-34` | Uses retrying stub writing corrupt both times. Still pins "corrupt on both attempts → throw" regardless of how we define corrupt, as long as `writeCorrupt` stays aligned with the new validation. |

---

## Tests that assert something we'd break

These tests either directly pin the buggy phase sequence or are so tightly coupled to the stub-permissive contract that fixing the hypothesis'd bug will force a behaviour change they'd observe. They are the mirror of the "pin current behaviour" table — listed separately because *any* hypothesised fix (expanded path list OR strict validation OR surfacing the FluidAudio-internal download as `.downloading`) would break them:

1. `testPrepareOnCachedModelEmitsLoadingWithoutDownloading` (ModelDownloadProgressTests.swift:74–102). If we expand the path list to include real weights, the fixture won't pre-seed them, so `modelArtifactsAreValid` returns false, the test harness's `StubModelDownloader` runs, and a `.downloading` phase appears — violating the `XCTAssertFalse(snapshots.contains(where: { $0.phase == .downloading }))` assertion. Fix requires updating `TestModelArtifacts.writeValid` to seed the expanded file set, **or** accepting that cached-model prepare may briefly show `.downloading`.

2. `testPrepareSkipsDownloadWhenModelAlreadyOnDisk` (FluidAudioTranscriberAlreadyDownloadedTests.swift:43–55). Same failure mode: expanded path list → pre-seed no longer satisfies validation → downloader runs → `requests.isEmpty` fails.

3. `testPrepareEmitsIdleDownloadingLoadingFinishedExactlyOnce` (ModelDownloadProgressTests.swift:6–40). **Partially** in this bucket: if the fix is "surface FluidAudio's internal download as a second `.downloading` run", this test's `.finished` count assertion (`filter { $0.phase == .finished }.count == 1`) would still hold because `.finished` is only emitted after `loadModel` returns — but the implicit "one `.downloading` run between `.idle` and `.loading`" mental model would change. The test itself survives because it only asserts ordering, not run-count of `.downloading`.

4. `TestModelArtifacts.writeValid` fixture (TranscriptionTestSupport.swift:7–27). Not a test, but a pinning dependency. Any fix to the path list must co-update this fixture or every test that depends on "post-writeValid state counts as valid" will flip. This is the single largest radius change.

### Higher-level tests — no phase-pinning assertions that block the fix

- `PillOverlayViewModelTests` (Tests/PersonalScribeAppKitTests/PillOverlayViewModelTests.swift) — builds synthetic `ModelDownloadProgress` values (e.g. lines 67–78, 96–107) and asserts the view-model mapping `.downloading → .downloading(fractionCompleted:)`, `.loading → .loading`, `.finished → .hidden`. **Fix-compatible** — the mapping semantics are unchanged by any hypothesised backend fix.
- `PillOverlayPillAppearanceTests` (Tests/PersonalScribeAppKitTests/Overlay/PillOverlayPillAppearanceTests.swift) — panel appearance only, **no** `ModelDownloadProgress` assertions. Fix-agnostic.
- `AppStoreTests.testSnapshotRepublishesSessionStateAndModelDownloadProgress` (Tests/PersonalScribeCoreTests/AppStore/AppStoreTests.swift:6-56) — emits a synthetic `.downloading` snapshot via `FakeAppStoreSessionProvider`, asserts the store republishes it and that `.finished` clears `modelDownloadProgress`. **Fix-compatible** — doesn't care how many real `.downloading` rounds happen upstream.

---

## Summary

- All 5 hypothesis steps verified in-repo, modulo Step 4's "AsrModels.load downloads silently" which is FluidAudio-internal and verified here only by elimination.
- `modelArtifactsAreValid` is stub-permissive — exactly two copies, byte-identical logic, only cosmetic drift (`first` vs `contents` variable name).
- Relaunch-after-partial-download is **worse than the described bug**: the user sees no `.downloading` at all, straight to `.loading`-for-minutes.
- 3 tests directly pin current behaviour and 1 fixture pins it transitively — all 4 live in `Tests/PersonalScribeTranscriptionTests/`. 8+ tests are fix-compatible. No higher-level test blocks the fix.

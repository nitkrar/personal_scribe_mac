# #098 — Whisper via whisper.cpp — DESIGN (revision 1)

Status: drafting (claude-atlas/codex-hermes, 2026-05-18). Scope: BACKLOG #098 "parallel Whisper runtime via whisper.cpp". This phase is docs-only; no code changes are part of this document.

Revision history:
- rev 1 → first design draft, derived from `plans/098_whispercpp/SPIKE.md`, `plans/098_whispercpp/SPIKE-pool-claude.md`, and the shipped `#095` WhisperKit architecture.

Companion rollout plan: `IMPLEMENTATION.md`.

## 1. Goal

Add `whisper.cpp` as a second Whisper runtime in Ninimma, parallel to `#095`'s WhisperKit adapter, while keeping the existing adapter/provider/catalog architecture intact.

What this design is trying to prove:
- a `whisper.cpp` runtime can fit the existing `Transcriber` + `ModelLifecycle` seam cleanly
- the download/store story can stay simpler than WhisperKit's bundle/tokenizer flow
- the initial catalog can be small, explicit, and reversible

Non-goals for v1:
- replacing WhisperKit or migrating existing WhisperKit descriptors
- streaming / partial-segment delivery
- ANE/CoreML encoder sidecars as a required part of the design
- new `ModelDescriptor` schema fields
- token timings, word timings, segment timings, log-prob reporting, or confidence mapping

## 2. Verified facts

### 2.1 whisper.cpp runtime and packaging facts

| Claim | Verified state | Source |
| --- | --- | --- |
| Upstream Swift consumption path | `ggml-org/whisper.cpp` release XCFramework via SwiftPM `.binaryTarget` is the upstream-recommended Apple path | `plans/098_whispercpp/SPIKE.md`, `plans/098_whispercpp/SPIKE-pool-claude.md` |
| `whisper.spm` | Deprecated by upstream and explicitly redirected to `whisper.cpp` proper | same |
| `SwiftWhisper` | Stale and pinned to an old vendored whisper.cpp snapshot | same |
| Core runtime API | Stable surface is the C API in `whisper.h`; upstream ships a Swift example that wraps it with an `actor` | same |
| Base model layout | Plain whisper.cpp uses a single `ggml-*.bin` file per model; tokenizer data is embedded in the bin | same |
| CoreML/ANE path | Optional encoder sidecar only; field evidence is mixed enough that it should not be a v1 design assumption | same |

### 2.2 Ninimma codebase facts

| Claim | Verified state | File / note |
| --- | --- | --- |
| Existing descriptor schema already has the needed fields | `ModelDescriptor` already exposes `repoFolderName`, `requiredRelativePaths`, `repository`, `revision`, `tokenizerSource`, `requiredChipFamily`, and `auxiliaryRepoFolderNames` | `Sources/PersonalScribeCore/Models/Selection/ModelDescriptor.swift` |
| Direct HF resolve URLs already exist | `ModelDescriptor.resolveURL(for:)` already builds `https://huggingface.co/<repo>/resolve/<revision>/<path>` | same |
| Validation stays generic | `ModelArtifactFilesystem.modelArtifactsAreValid(...)` only checks required file presence plus lightweight special cases; a single `.bin` file fits without changes | `Sources/PersonalScribeSession/Models/Selection/ModelBoundProcessorProvider.swift` |
| Audio wire format already matches whisper.cpp | current capture/resample pipeline produces `16 kHz mono Float32` `PCMBuffer` values | `Sources/PersonalScribeAudio/AVAudioCaptureService.swift`, `Sources/PersonalScribeAudio/AudioResampler.swift` |
| Adapter/provider seam already exists | `ModelBoundProcessorProvider` already routes vendor-specific adapters by `descriptor.engine`, and existing adapters implement `prepare` / `downloadIfNeeded` / `modelDownloadProgress` / `cleanup` | `Sources/PersonalScribeSession/Models/Selection/ModelBoundProcessorProvider.swift` |
| Chip gating is already centralized | `ActiveModelService` already has `canActivate(...)` and descriptor-level chip gating from `#095`; whisper.cpp v1 does not need new service work | `Sources/PersonalScribeSession/Models/Selection/ActiveModelService.swift` |
| WhisperKit establishes the pattern to mirror | `WhisperKitTranscriberAdapter` already demonstrates the adapter lifecycle, progress broadcasting, and manager seam this design can parallel | `Sources/PersonalScribeTranscription/Adapters/WhisperKitTranscriberAdapter.swift` |

## 3. Locked decisions

### D1 — Engine case: `.whisperCpp`

Add a new vendor-bound transcription-engine case, `.whisperCpp`.

Why vendor-bound instead of family-bound:
- Ninimma already routes by runtime/vendor (`.parakeetTDT`, `.qwen3ASR`, `.whisperKit`, `.parakeetEOU`)
- this ticket is explicitly about a second Whisper runtime, not a replacement of `whisperKit`
- future transcript history, persisted active IDs, and settings rows need the runtime identity to stay explicit

Expected supporting changes:
- `TranscriptionEngine+Kind` maps `.whisperCpp -> .asr`
- `TranscriptionEngine+Codable` adds `case whisperCpp = "whisperCpp"`
- `ModelBoundProcessorProvider` gets a `.whisperCpp` branch

### D2 — Package integration uses the upstream XCFramework via `.binaryTarget`

The package shape is locked: whisper.cpp enters the repo through a pinned release XCFramework, not a source-package fork.

Expected `Package.swift` shape:

```swift
.binaryTarget(
    name: "<upstream target name>",
    url: "https://github.com/ggml-org/whisper.cpp/releases/download/<tag>/whisper-<tag>-xcframework.zip",
    checksum: "<sha256>"
)
```

and `PersonalScribeTranscription` depends on that binary target directly.

What is locked here:
- use the upstream release asset path
- pin by URL + checksum
- keep the dependency additive beside WhisperKit, not a replacement

What is intentionally not locked here:
- exact release tag
- exact binary target name/module import name
- exact checksum value and whether a mirror is needed

Those stay open in §6 because they depend on the concrete release asset chosen at implementation time.

### D3 — Adapter shape mirrors WhisperKit: public actor + private runtime seam

Add `Sources/PersonalScribeTranscription/Adapters/WhisperCppTranscriberAdapter.swift` as the public adapter.

Shape:
- public `actor WhisperCppTranscriberAdapter: Transcriber`
- lifecycle mirrors existing adapters: `prepare()`, `downloadIfNeeded()`, `modelDownloadProgress()`, `cleanup()`, `transcribe(_:)`
- keep `prepareTask` deduping so repeated `prepare()` calls coalesce
- one live whisper.cpp context per adapter instance / descriptor

The raw C surface stays behind a private seam:
- either `WhisperCppManaging` or a similarly small runtime protocol
- live implementation owns the `whisper_context`
- unit tests use a stub library/runtime instead of loading the real XCFramework

Ownership rule:
- the whisper.cpp context is created during `prepare()`
- reused across transcriptions while the descriptor stays active
- freed in `cleanup()` and on model eviction
- no `OpaquePointer` or whisper.cpp structs escape to higher layers

### D4 — Download path is a single direct GET into the canonical model leaf

whisper.cpp v1 does not use HubApi, no snapshot matching, no tokenizer repo, and no staging tree.

Locked download flow:
1. Canonical leaf remains `<modelsRoot>/<repoFolderName>/`.
2. `requiredRelativePaths` contains exactly one literal `.bin` filename.
3. `downloadIfNeeded()` builds the HF URL with `descriptor.resolveURL(for: binFilename)`.
4. Download writes to a sibling temp file inside the canonical leaf, e.g. `<binFilename>.download`.
5. On success, the temp file is atomically renamed or replaced into `<modelsRoot>/<repoFolderName>/<binFilename>`.
6. On failure, the temp file is removed and the adapter throws `PersonalScribeError.modelLoadFailure`.

Why this is the right shape:
- it preserves the existing "descriptor leaf is canonical" invariant
- it keeps delete / cache-hit logic unchanged
- it avoids repeating WhisperKit's bundle-root/staging complexity where it is not needed

### D5 — `requiredRelativePaths` stays literal validation data; validator remains unchanged

The `#095` download-bug lesson is preserved here: `requiredRelativePaths` is not redefined as a download-selector API.

For whisper.cpp v1:
- each descriptor has exactly one literal entry in `requiredRelativePaths`
- that entry is the final file name expected on disk, e.g. `ggml-small-q5_1.bin`
- no globs, no folder-root patterns, no implicit tokenizer expansion

The download path happens to read that same literal filename because whisper.cpp's base artifact is a single file. That does not change the contract of `requiredRelativePaths`; it remains the validator's source of truth, and `ModelArtifactFilesystem.modelArtifactsAreValid(...)` stays unchanged.

Descriptor implications:
- `tokenizerSource = nil`
- `auxiliaryRepoFolderNames = []`
- no new schema fields

### D6 — Capabilities are all false in v1

`whisper.cpp` v1 surfaces only final transcript text.

```swift
TranscriberCapabilities(
    providesTokenTimings: false,
    providesConfidence: false,
    providesPerformanceMetrics: false,
    providesCustomVocabulary: false
)
```

Reasoning:
- token / word timing plumbing is out of scope
- log-probs exist in whisper.cpp, but mapping them into Ninimma's current confidence surface is extra work with no load-bearing consumer
- runtime-internal timing is not needed to ship the adapter
- custom vocabulary is not part of whisper.cpp's base path

### D7 — Catalog tier v1 is exactly three descriptors, disabled in Stage A and flipped atomically in Stage B

The initial catalog is locked to these three rows:

| `id` | Display name | Required file | Approx size | Languages |
| --- | --- | --- | --- | --- |
| `whispercpp-tiny` | `Whisper Tiny (whisper.cpp)` | `ggml-tiny.bin` | ~75 MB | multilingual |
| `whispercpp-small-q5_1` | `Whisper Small q5_1 (whisper.cpp)` | `ggml-small-q5_1.bin` | ~190 MB | multilingual |
| `whispercpp-large-v3-turbo-q5_0` | `Whisper Large v3 Turbo q5_0 (whisper.cpp)` | `ggml-large-v3-turbo-q5_0.bin` | ~547 MB | multilingual |

Per-descriptor invariants:
- `engine = .whisperCpp`
- `repository = "ggerganov/whisper.cpp"`
- `tokenizerSource = nil`
- `requiredChipFamily = nil`
- `requiredRelativePaths = [<literal bin filename>]`
- `isEnabled = false` in Stage A

Stage safety rule:
- Stage A introduces the descriptors with `isEnabled = false`
- Stage B flips all three to `isEnabled = true` in the same commit that swaps the provider from `NoOpDisabledTranscriber` to the real whisper.cpp adapter

That keeps the rollout atomic and prevents a user-visible row from existing before the adapter is real.

Open by design:
- the exact `repoFolderName` convention is not locked yet; see §6.3
- the exact `revision` strings ride the existing catalog field and are chosen when the descriptors land; no schema work is needed either way

### D8 — Transcription is one-shot `whisper_full`, returning text only

whisper.cpp v1 is a batch adapter.

Runtime behavior:
- `prepare()` loads the `.bin` file into a whisper.cpp context
- `transcribe(_ audio: PCMBuffer)` runs a single `whisper_full(...)` over `audio.samples`
- language stays auto-detect because `#091` language hints are still out of scope
- translation stays off

Result shape:
- build final transcript text by iterating whisper.cpp segments and concatenating their text
- return `TranscriptionResult(text:, segments: [], audioDuration:, processingDuration:)`
- leave `confidence`, `tokenTimings`, `performanceMetrics`, and other optional metadata `nil`

Explicitly out of scope for v1:
- partial results
- per-segment `TranscriptionResult.Segment` population
- token timings, word timings, or log-prob exposure

### D9 — Failure mapping stays on the existing two adapter-level errors

No new error enum is introduced.

Map into existing errors as follows:

| Failure class | Result |
| --- | --- |
| invalid descriptor contract (`requiredRelativePaths.count != 1`, empty file name, bad URL) | `PersonalScribeError.modelLoadFailure` |
| download failure, temp-file write failure, atomic rename failure | `PersonalScribeError.modelLoadFailure` |
| whisper.cpp context init returns `nil` / model file cannot be loaded | `PersonalScribeError.modelLoadFailure` |
| `whisper_full(...)` failure or post-run segment extraction failure | `PersonalScribeError.transcriptionFailure` |
| cleanup failure after a successful remove/free path | warn-only logging; do not invent a new surfaced error |

### D10 — Logging stays quiet and contains no user audio or transcript content

Allowed log fields:
- descriptor id
- engine name
- selected model file name
- byte counts / download fraction
- high-level lifecycle transitions (`download start`, `download complete`, `model loaded`, `model freed`)
- high-level error category (`download failed`, `context init failed`, `transcription failed`)

Disallowed log fields:
- transcript text
- segment text
- raw audio samples
- absolute user data paths outside the model leaf
- pointer addresses or whisper.cpp internal buffers

### D11 — Test plan summary includes a Stage A safety stub

Automated coverage expected from the code phase:
- engine enum tests for `.whisperCpp` kind/codable wiring
- catalog tests for the three descriptors, their file names, and the Stage A disabled state
- provider tests proving `.whisperCpp` resolves to `NoOpDisabledTranscriber` in Stage A and the real adapter in Stage B
- new adapter tests for direct-download URL construction, temp-file cleanup, atomic rename, prepare dedupe, text stitching, error mapping, and cleanup

Safety seam required in Stage A:
- `ModelBoundProcessorProvider` gets a temporary `NoOpDisabledTranscriber` branch for `.whisperCpp`
- it exists only to keep the code compiling while the descriptors remain hidden
- Stage B removes that stub in the same change that enables the catalog rows

Manual coverage expected from Stage C:
- `MV-WHISPERCPP-*` additions to the existing manual runbooks
- offline re-activation after download
- delete / redownload path
- at least one cross-runtime comparison against the shipped WhisperKit rows

### D12 — Concurrency: raw-pointer ownership is serialized and blocking C work stays off the cooperative executor

Upstream's contract is clear: one `whisper_context` must not be used concurrently.

The concurrency shape is therefore locked:
- the public adapter stays an `actor`
- the live runtime owns the raw whisper.cpp context and serializes all pointer-touching calls
- blocking C calls such as `whisper_init_*`, `whisper_full`, and `whisper_free` run on a dedicated serial queue owned by the live runtime, not directly on the cooperative actor executor

Why this matters:
- it prevents concurrent use of one context
- it avoids blocking Swift's cooperative executor with a long-running C call
- it lets `cleanup()` and `transcribe(_:)` serialize cleanly even if they are called close together

Boundary rule:
- raw `OpaquePointer` values, `whisper_full_params`, and other C-owned state never cross the runtime boundary
- the adapter only sees Swift value types such as `String`, `Duration`, and `TranscriptionResult`

### D13 — Audio prep stays outside the adapter

No whisper.cpp-specific resampler or channel mixer is added.

Reasoning:
- Ninimma's current audio pipeline already normalizes to `16 kHz mono Float32`
- whisper.cpp accepts float PCM directly
- adding an adapter-local resampler would duplicate logic that already exists in `PersonalScribeAudio`

v1 adapter behavior:
- pass `audio.samples` straight into whisper.cpp
- use the existing `PCMBuffer.duration` / metadata already computed by the shared core types

If a future caller violates the `PCMBuffer` wire-format contract, the fix belongs before the adapter boundary, not inside whisper.cpp's adapter.

### D14 — Prefer direct XCFramework module import; fall back to a tiny C shim target only if the release asset forces it

The packaging question is intentionally narrow:
- if the upstream XCFramework exposes a usable Clang module to Swift, import it directly
- if it does not, add a tiny local C target that re-exports `whisper.h` and gives Swift a stable import surface

What is not planned:
- app-level bridging headers
- vendoring a hand-maintained copy of `whisper.h`
- a thick custom wrapper layer that duplicates whisper.cpp's C API wholesale

This keeps the integration close to upstream while leaving one packaging escape hatch if the release zip's module map is not sufficient.

## 4. Code surfaces touched

Expected code-phase files:
- `Package.swift`
- `Sources/PersonalScribeCore/Models/Selection/ModelDescriptor.swift`
- `Sources/PersonalScribeCore/Models/Selection/TranscriptionEngine+Kind.swift`
- `Sources/PersonalScribeCore/Models/Selection/TranscriptionEngine+Codable.swift`
- `Sources/PersonalScribeCore/Models/Selection/BuiltInModelCatalog.swift`
- `Sources/PersonalScribeSession/Models/Selection/ModelBoundProcessorProvider.swift`
- `Sources/PersonalScribeTranscription/Adapters/WhisperCppTranscriberAdapter.swift`
- existing core/session tests plus a new whisper.cpp adapter test file
- `Tests/ManualVerifications/ManualSettingsVerification.md`
- `Tests/ManualVerifications/ManualTranscriptionVerification.md`

Code surfaces explicitly expected to stay unchanged:
- `ModelDescriptor` schema beyond the new engine case
- `ModelArtifactFilesystem.modelArtifactsAreValid(...)`
- `ActiveModelService` chip-gating logic
- `StorageLocator` and model-root directory layout

## 5. Architecture parallel with #095

The shape intentionally mirrors WhisperKit where that buys consistency:
- descriptor-driven catalog rows
- one adapter instance per descriptor
- `prepare` / `downloadIfNeeded` / `cleanup` lifecycle
- same canonical model leaf under `modelsRoot`
- provider-owned adapter cache and eviction

The places whisper.cpp is simpler than WhisperKit:
- one primary artifact instead of a bundle tree
- no tokenizer repo
- no HubApi snapshot/staging/copy flow
- no chip gating in v1
- text-only result surface

The place whisper.cpp is more complex than WhisperKit:
- the runtime boundary is synchronous C code, so we need explicit queue ownership and pointer management instead of a pure Swift async library object

## 6. Remaining risks and open questions

### 6.1 Exact XCFramework release tag

The spike points at `v1.8.4` as the likely starting pin, but the exact release must be chosen at implementation time.

Selection criteria:
- release asset exists for the XCFramework zip
- no known packaging regression for Apple Silicon
- still aligns with the spike's conclusions about `large-v3-turbo` support

### 6.2 Checksum source and mirror strategy

The checksum will come from the exact zip selected in §6.1, but the delivery choice is still open:
- direct GitHub release URL plus `swift package compute-checksum`
- mirrored binary with the repo/team's preferred artifact host, if GitHub release availability is considered too brittle

This is a packaging decision, not an adapter-design decision, so it stays open here.

### 6.3 `repoFolderName` convention

One naming choice still needs to be made before the descriptors land:

Option A:
- `repoFolderName` namespaced to the runtime, e.g. `whispercpp-tiny`

Option B:
- `repoFolderName` mirrors the upstream bin stem, e.g. `ggml-tiny`

Trade-off:
- Option A is clearer when multiple runtimes or manual downloads coexist under `modelsRoot`
- Option B is closer to the upstream file naming and keeps the leaf visually tied to the artifact

The required file name stays literal either way:
- `ggml-tiny.bin`
- `ggml-small-q5_1.bin`
- `ggml-large-v3-turbo-q5_0.bin`

### 6.4 Exact Swift import/module name from the XCFramework

The upstream docs and examples suggest the answer is probably straightforward, but the actual module name still needs confirmation from the chosen release asset.

Implementation-time outcome:
- if the module imports directly, D14 stays on the happy path
- if it does not, Stage A adds the tiny C shim target and moves on

## 7. Effort estimate

Estimated implementation effort after design approval: about 2 to 3 days of code work plus user-run manual verification.

Rough split:
- scaffold/package/catalog/provider work: ~0.5 day
- adapter/runtime/download implementation + tests: ~1 to 1.5 days
- manual runbook additions and close-out: ~0.5 day

## 8. Dependencies and blockers

Dependencies:
- user approval of this design and `IMPLEMENTATION.md` before code phase starts
- one concrete XCFramework release asset and checksum
- one concrete `repoFolderName` convention

No blocker is currently expected from:
- model schema shape
- validator semantics
- chip gating
- audio preprocessing

Shipping blocker remains unchanged from the rest of the project:
- the adapter is not "done" until Stage C runbooks exist and the user performs the manual verification pass in the canonical repo path

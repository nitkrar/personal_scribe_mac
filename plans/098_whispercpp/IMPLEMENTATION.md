# #098 — Whisper via whisper.cpp — IMPLEMENTATION

Status: drafting (claude-atlas/codex-hermes, 2026-05-18). Companion to `DESIGN.md` revision 1.

Pre-flight:
- read `DESIGN.md` first; this rollout assumes D1-D14 are accepted
- this plan is intentionally capped at four stages
- if implementation happens in a broker worktree, lane-close with `swift build --build-tests`; run `swift test` only from the canonical repo path after cherry-picking, per project guidance

## Stage map

| Stage | Outcome | Effort | Expected automated test delta | Exit gate |
| --- | --- | --- | --- | --- |
| A | Scaffold: engine case, XCFramework pin, disabled catalog rows, provider safety stub | ~0.5 day | `+8` | package resolves, targeted tests green, whisper.cpp rows still hidden |
| B | Real adapter: direct download, runtime ownership, atomic enable, adapter tests | ~1 to 1.5 days | `+16` | adapter compiles, targeted tests green, provider routes to live adapter |
| C | Manual-verification runbooks for whisper.cpp | ~0.25 day | `+0` | `MV-WHISPERCPP-*` entries added to both runbooks |
| D | User-run manual pass and close-out | ~0.5 day | `+0` | manual checks complete, any defects filed, close-out recorded |

Total expected work: about 2.25 to 2.75 days, excluding any follow-up bug fixing that manual verification might uncover.

## Stage A — Scaffold + disabled catalog + package pin

Goal:
- land the package/dependency scaffolding
- add the new engine and catalog metadata
- keep the feature non-user-reachable while the real adapter does not exist yet

### Files

Expected touched files:
- `Package.swift`
- `Sources/PersonalScribeCore/Models/Selection/ModelDescriptor.swift`
- `Sources/PersonalScribeCore/Models/Selection/TranscriptionEngine+Kind.swift`
- `Sources/PersonalScribeCore/Models/Selection/TranscriptionEngine+Codable.swift`
- `Sources/PersonalScribeCore/Models/Selection/BuiltInModelCatalog.swift`
- `Sources/PersonalScribeSession/Models/Selection/ModelBoundProcessorProvider.swift`
- existing engine/catalog/provider test files

Potentially touched in this stage if D14 requires it:
- a tiny local C shim target under `Sources/` strictly for import/module-map packaging

Expected untouched files:
- `ActiveModelService.swift`
- `ModelArtifactFilesystem.modelArtifactsAreValid(...)`
- manual verification docs

### Work

1. Resolve the packaging decisions that are purely prerequisites:
   - choose the whisper.cpp XCFramework release tag
   - compute/record the checksum for the exact zip
   - confirm whether Swift can import the binary target directly or needs the small C shim target
2. Add `TranscriptionEngine.whisperCpp` and wire it through kind/codable helpers.
3. Add the three `whispercpp-*` catalog descriptors exactly as locked in `DESIGN.md`, with:
   - `requiredRelativePaths = [<literal .bin filename>]`
   - `tokenizerSource = nil`
   - `requiredChipFamily = nil`
   - `isEnabled = false`
4. Add a temporary `NoOpDisabledTranscriber` branch in `ModelBoundProcessorProvider` for `.whisperCpp`.
5. Keep the catalog rows hidden by leaving them disabled. Do not flip them live in this stage.

### Expected automated test delta

Approximate additions: `+8`

Likely breakdown:
- `+2` engine kind/codable coverage
- `+4` catalog metadata/disabled-state coverage
- `+2` provider safety-stub coverage

### Exit criteria

Required before Stage B starts:
- `swift package resolve` succeeds with the pinned binary target
- targeted automated tests for engine/catalog/provider are green in the canonical repo path
- whisper.cpp rows are still not user-selectable because all three descriptors remain `isEnabled = false`
- no schema or validator changes have been introduced to make whisper.cpp fit

## Stage B — Real adapter + direct download + atomic enable

Goal:
- replace the Stage A safety stub with the real adapter
- implement the full disk-only download path and in-memory model lifecycle
- enable the three catalog rows atomically at the end of the stage

### Files

Expected touched files:
- `Package.swift` if the direct-import vs shim result from Stage A needs a final dependency adjustment
- `Sources/PersonalScribeSession/Models/Selection/ModelBoundProcessorProvider.swift`
- `Sources/PersonalScribeTranscription/Adapters/WhisperCppTranscriberAdapter.swift`
- optional small import shim target, if Stage A proved it necessary
- `Sources/PersonalScribeCore/Models/Selection/BuiltInModelCatalog.swift`
- `Tests/PersonalScribeTranscriptionTests/Adapters/WhisperCppTranscriberAdapterTests.swift`
- existing engine/catalog/provider test files

### Work

1. Implement `WhisperCppTranscriberAdapter` with the same public lifecycle shape as WhisperKit:
   - `prepare()` with in-flight dedupe
   - `downloadIfNeeded()` as disk-only
   - `modelDownloadProgress()`
   - `cleanup()`
   - `transcribe(_:)`
2. Add the live whisper.cpp runtime seam:
   - own the whisper.cpp context privately
   - serialize blocking C calls on a dedicated serial queue
   - keep all raw pointers and C structs inside the runtime boundary
3. Implement the direct single-file download flow:
   - ensure `<modelsRoot>/<repoFolderName>/`
   - build the HF URL with `descriptor.resolveURL(for: requiredRelativePaths[0])`
   - download to `<filename>.download`
   - atomically rename/replace into the final `.bin`
   - remove temp files on failure
4. Implement one-shot transcription:
   - load the `.bin` during `prepare()`
   - call `whisper_full(...)`
   - merge segment text into one final `TranscriptionResult.text`
   - leave `segments` and optional metadata empty / `nil`
5. Replace the Stage A provider stub with the real adapter and delete `NoOpDisabledTranscriber`.
6. In the same commit as step 5, flip the three whisper.cpp descriptors from `isEnabled = false` to `isEnabled = true`.

That final atomic step is load-bearing. Do not enable the catalog rows earlier.

### Expected automated test delta

Approximate additions: `+16`

Likely breakdown:
- `+10` to `+12` adapter-focused tests
- `+2` provider routing / atomic-enable assertions
- `+2` catalog assertions updated from disabled to enabled
- `+2` failure-mapping / cleanup edge cases

### Exit criteria

Required before Stage C starts:
- targeted automated coverage is green in the canonical repo path, at minimum around whisper.cpp adapter + catalog + provider + engine wiring
- if work happened in a broker worktree, the worktree lane closes with `swift build --build-tests`, then the canonical repo path runs the targeted `swift test` pass after cherry-pick
- the provider returns the real whisper.cpp adapter for `.whisperCpp`
- the three catalog rows are now visible/selectable because they were enabled in the same commit as the provider swap
- no tokenizer-specific download code or validator changes were introduced

## Stage C — Manual-verification runbooks

Goal:
- add the explicit user-run verification steps needed before the adapter can be called shipped

### Files

Expected touched files:
- `Tests/ManualVerifications/ManualSettingsVerification.md`
- `Tests/ManualVerifications/ManualTranscriptionVerification.md`

### Work

Add `MV-WHISPERCPP-*` coverage in the two existing runbooks.

Recommended runbook set:
- `MV-WHISPERCPP-1` — download `whispercpp-tiny` from Settings, activate it, confirm the row state and on-disk bytes look correct
- `MV-WHISPERCPP-2` — repeat for `whispercpp-small-q5_1`
- `MV-WHISPERCPP-3` — repeat for `whispercpp-large-v3-turbo-q5_0`
- `MV-WHISPERCPP-4` — transcribe a known sample with whisper.cpp after download, verify text appears and the app does not hit the network on activation
- `MV-WHISPERCPP-5` — disable network after predownload, relaunch or switch back to the model, and confirm offline activation/transcription still works
- `MV-WHISPERCPP-6` — delete the downloaded model from Settings, confirm bytes are removed, then redownload successfully
- `MV-WHISPERCPP-7` — switch between WhisperKit and whisper.cpp descriptors and confirm both runtimes remain independently activatable

Notes:
- no ANE/CoreML sidecar verification belongs in v1
- if the user wants runtime-performance comparison later, that should be a separate explicit benchmark follow-up, not silently folded into these runbooks

### Expected automated test delta

`+0`

This stage is docs/manual coverage only.

### Exit criteria

Required before Stage D starts:
- both manual-verification docs contain whisper.cpp coverage
- the steps are specific enough that the user can run them without reading implementation code
- the runbooks match the actual shipped descriptor IDs and display names

## Stage D — User-run manual pass and close-out

Goal:
- execute the Stage C runbooks on the canonical repo path
- capture any defects as follow-up work
- close the implementation phase cleanly

### Files

Usually no code files should change here unless manual verification finds a real issue.

Potential artifacts:
- a small follow-up patch if manual verification uncovers a bug
- broker close-out notes

Explicitly not required by default:
- `BACKLOG.md` edits, unless the user explicitly asks for them

### Work

1. Run the `MV-WHISPERCPP-*` cases from Stage C on the canonical repo path.
2. If a case fails:
   - stop the close-out
   - file/fix the concrete defect
   - rerun the failed manual case
3. If all cases pass:
   - record the successful manual pass
   - close the broker request / implementation phase

### Expected automated test delta

`+0`

### Exit criteria

The work is only done when:
- the user-run Stage C manual checks pass from the canonical repo path
- any defects found during manual verification are either fixed or filed as explicit follow-ups
- the final state is recorded without leaving the feature half-enabled or partially documented

## Notes on things this rollout should not do

Do not expand scope during implementation:
- do not add streaming
- do not add CoreML encoder-sidecar support
- do not add new descriptor schema fields
- do not change `ModelArtifactFilesystem.modelArtifactsAreValid(...)`
- do not overload `requiredRelativePaths` with glob or folder-pattern semantics

If one of those becomes necessary, stop and reopen the design rather than letting Stage B drift.

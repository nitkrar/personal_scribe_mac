> **Do NOT diverge from this plan. Silent divergence is the cardinal sin. To deviate, surface the proposed divergence in a commit-message comment AND in the hand-off report; wait for main-session confirmation. Paraphrasing the contract is divergence. Renaming a protocol the plan specifies is divergence. Choosing a different storage format than the plan specifies is divergence.**

# Layer 2 — Storage / paths

## Critical discipline
> **Do NOT diverge from this plan. Silent divergence is the cardinal sin. To deviate, surface the proposed divergence in a commit-message comment AND in the hand-off report; wait for main-session confirmation. Paraphrasing the contract is divergence. Renaming a protocol the plan specifies is divergence. Choosing a different storage format than the plan specifies is divergence.**

## Why this layer exists
Path construction and app-owned filesystem rules are currently scattered across `SeshatConfig`, both transcript stores, the base-directory migrator, the model downloader, app composition, and the Advanced settings tab. The codebase has no single contract that answers three basic questions: which subdirectories Seshat owns, which call site is allowed to create them, and where atomic rename/write helpers live.

Layer 2 centralizes those invariants without re-implementing `FileManager`. It gives downstream work a stable base-directory contract, moves storage ownership out of ad hoc helpers, and unblocks Layer 3 (`UserDefaults` suite/path work), Layer 6 (`models/`), Layer 7 (`modes/`), and Layer 8 (`recordings/` metrics and `DiskSpaceSnapshot`) from building on top of duplicate path logic.

## Locked decisions
- `ManagedDirectory enum cases: models, modes, recordings, logs, cache`
- `StorageLocator protocol surface: url(for:), baseDirectory, ensureDirectoriesExist()`
- `AtomicFileWriter protocol`
- `DiskSpaceSnapshot value type for the Metrics layer (future About tab)`
- `Migrate these existing sites onto the new layer: SeshatConfig, TranscriptStoreJSONL, SQLiteTranscriptStore, BaseDirectoryMigrator, FluidAudioModelDownloader`
- `Rename SeshatConfig → AppConfig OR integrate its responsibilities into StorageLocator (call out the choice in the plan)`
- `Do NOT touch FluidAudio's own checkout cache`
- `Do NOT re-implement FileManager; build on top of it`
- `Stage 1 introduces new directory Sources/SeshatCore/Storage/`
- `This layer blocks Layers 3 (defaults suite path), 6 (models/), 7 (modes/), 8 (recordings/ for metrics)`

Choice for the locked rename decision: use `SeshatConfig -> AppConfig`. `AppConfig` remains the canonical namespace for non-storage constants and override plumbing (`sampleRate`, `channelCount`, `modelId` shim, test/base-directory override state). All path lookup moves to `StorageLocator`. `SeshatConfig` becomes a deprecated compatibility shim during Stage 2 and is deleted in Stage 3 after downstream layers stop depending on it.

## Observed current spread
| File | Line(s) | What lives there |
|---|---|---|
| `Sources/SeshatCore/Config.swift` | `13-106` | Base-directory resolution precedence, base override persistence, lazy creation of `models/`, `modes/`, `recordings/`, and model-specific subdirectories all live in one static enum. |
| `Sources/SeshatCore/TranscriptStore.swift` | `30-75` | `TranscriptStoreJSONL` turns a recordings root into `transcripts.jsonl`, bootstraps the file, enforces `0600`, and appends directly through `FileHandle`. |
| `Sources/SeshatCore/SQLiteTranscriptStore.swift` | `33-60`, `204-229` | `SQLiteTranscriptStore` derives SQLite, JSONL, and `.tmp` paths from `recordingsDirectory`, creates the recordings directory itself, and performs tmp-file bootstrap/rename inline. |
| `Sources/SeshatCore/BaseDirectoryMigrator.swift` | `58-126`, `174-193` | Hard-coded managed subdirectory list, base-directory override writes, writability probe, byte counting, and rollback logic all live inside the migrator. |
| `Sources/SeshatTranscription/FluidAudioTranscriber.swift` | `54-56`, `239-250` | The transcriber defines model staging naming and resolves the final model root through `SeshatConfig.directory(for:)`. |
| `Sources/SeshatTranscription/FluidAudioModelDownloader.swift` | `13-95` | The downloader computes its own staging directory from the model root, creates destination parents, writes files atomically one-by-one, and renames the staged model directory into place. |
| `Sources/SeshatAppKit/Composition/AppComposition.swift` | `27-38` | Production composition resolves `recordings/` directly when constructing the app's `SQLiteTranscriptStore`. |
| `Sources/SeshatAppKit/Composition/SeshatAppMain.swift` | `184-190` | Notes/history composition resolves `recordings/` a second time when constructing `SQLiteTranscriptReader`. |
| `Sources/SeshatAppKit/Settings/AdvancedTab.swift` | `10-23`, `77-103`, `137-186` | The Advanced tab reads the base directory directly from `SeshatConfig`, owns user-facing copy about migrated subdirectories, and assumes only `models`, `modes`, and `recordings` exist. |
| `Sources/SeshatCore/Logger.swift` | `4-52` | Logging is still `OSLog`-only; the app owns no `logs/` path today even though this layer must reserve one. |

## Proposed API / contracts
### Types
- `ManagedDirectory`: fixed app-owned roots directly under `StorageLocator.baseDirectory`. The case names and path components are identical: `models`, `modes`, `recordings`, `logs`, `cache`. `logs/` and `cache/` are created now even if they have no writer yet, so downstream layers can depend on a stable directory set.
- `DiskSpaceSnapshot`: value type for future metrics/About-tab storage reporting. Fields: `capturedAt`, `baseDirectory`, `usedBytesByDirectory: [ManagedDirectory: Int64]`, `totalUsedBytes`, and `volumeAvailableBytes`. The type is storage-only; no formatting or UI strings live here.
- `AppConfig`: canonical non-storage config facade. It keeps `sampleRate`, `channelCount`, the temporary `modelId` shim, `testingBaseDirectoryOverride`, the existing override key/env-var names, and a factory for the live `StorageLocator`.

### Protocols
- `StorageLocator: Sendable`
  - `url(for: ManagedDirectory) -> URL`
  - `baseDirectory: URL`
  - `ensureDirectoriesExist() throws`
  - `baseDirectory` is pure resolution only. It does not create directories or throw. All directory creation happens through `ensureDirectoriesExist()`.
- `AtomicFileWriter: Sendable`
  - `replaceItem(at destinationURL: URL, permissions: Int?, writeToTemporaryURL: (URL) throws -> Void) throws`
  - The writer creates a sibling temporary URL, asks the caller to materialize the full replacement there, applies permissions when requested, renames atomically into place, and cleans up temporary artifacts on failure.

### Errors
- No new public storage error enum is needed in Layer 2. `StorageLocator` and `AtomicFileWriter` should surface underlying `FileManager`/`CocoaError` failures. `BaseDirectoryMigrationError` remains the public migration error surface.

## Proposed live implementation
`AppStorageLocator` lives in `Sources/SeshatCore/Storage/` as a value type so core, transcription, and test code can use it without dragging `@MainActor` isolation into non-UI paths. It wraps `FileManager`, `UserDefaults`, and environment values rather than re-implementing them. Resolution precedence stays exactly what `Sources/SeshatCore/Config.swift:13-106` does today: `testingBaseDirectoryOverride`, then `SESHAT_BASE_DIR`, then `SeshatBaseDirectoryPath`, then `~/Library/Application Support/Seshat/`. The difference is ownership: `baseDirectory` only resolves; `ensureDirectoriesExist()` bootstraps the base directory plus all five `ManagedDirectory` roots idempotently.

`FileManagerAtomicFileWriter` is the only new concrete atomic-write helper in this layer. It handles the tmp-write-then-rename flow currently split between `SQLiteTranscriptStore` and the model downloader. It must stay thin: use `FileManager.createDirectory`, `moveItem`, and `replaceItemAt` directly, not a custom filesystem abstraction.

`AppConfig` becomes the canonical place for process-global override state and compatibility constants. `SeshatConfig` remains only as a forwarding compatibility shim during the swap so Layers 3, 6, 7, and 8 can move independently. Storage-specific helpers (`baseDirectory()`, `modelsDirectory()`, `recordingsDirectory()`, `directory(for:)`) leave `SeshatConfig` in Stage 2 and are deleted in Stage 3.

`DiskSpaceSnapshot` should be backed by an internal byte-counting helper extracted from `BaseDirectoryMigrator.totalBytes(in:)`. That avoids duplicating recursive size-walk logic when Layer 8 starts reading `recordings/` and total managed storage usage.

## Stage 1 — Build in parallel
Parallel Stage 1 with: Layers 1, 4, 5, and 9.

Do not start Layers 3, 6, 7, or 8 Stage 1 until this stage has landed, because they all need the `StorageLocator` and `ManagedDirectory` contracts.

Depends on: none.

### Step 2.1 — Create the new storage namespace
| Change | Before | After |
|---|---|---|
| Add `Sources/SeshatCore/Storage/ManagedDirectory.swift`, `StorageLocator.swift`, `AppStorageLocator.swift`, `AtomicFileWriter.swift`, `FileManagerAtomicFileWriter.swift`, `DiskSpaceSnapshot.swift`, and `AppConfig.swift` in the new `Sources/SeshatCore/Storage/` directory. | Path contracts are implicit and spread across `Config.swift`, transcript stores, migrator, and downloader. | Layer 2 has a single namespace for managed roots, base resolution, and atomic replacement without touching existing consumers or `Package.swift`. |

Stage 1 test-first requirement: add new failing tests under `Tests/SeshatCoreTests/Storage/` before adding any production implementation. Cover resolution precedence, `ensureDirectoriesExist()` creating all five managed roots, atomic replacement cleanup on failure, and `DiskSpaceSnapshot` byte accounting.

### Step 2.2 — Lock down pure-resolution vs bootstrap behavior
| Change | Before | After |
|---|---|---|
| Split "resolve the base path" from "create directories on disk" in the new layer, then prove that split with characterization tests. | `SeshatConfig.baseDirectory()` both resolves and creates, which forces UI and app-startup callers to pay for the same side effect. | `StorageLocator.baseDirectory` is cheap and non-throwing, while `ensureDirectoriesExist()` is the only directory-creation entry point. |

This stage must also lock in eager ownership of empty `logs/` and `cache/` directories. Do not defer them to a later layer once the `ManagedDirectory` contract exists.

### Step 2.3 — Introduce `AppConfig` without moving callers yet
| Change | Before | After |
|---|---|---|
| Add the canonical `AppConfig` facade in Stage 1, but leave every current `SeshatConfig` caller untouched. | `SeshatConfig` mixes unrelated constants (`sampleRate`, `channelCount`) with storage path logic. | Stage 2 can rename storage ownership cleanly without forcing unrelated audio/transcription callers to move in the same commit. |

`AppConfig` must preserve the existing key/env names in this layer. Renaming `SeshatBaseDirectoryPath` belongs to Layer 3, not Layer 2.

## Stage 2 — Swap
Depends on: Layer 2 Stage 1 complete. No other layer's Stage 2 is required before this swap starts.

Downstream layers unblocked after this stage: Layer 3 can plan around a real base-path owner, Layer 6 can claim `models/`, Layer 7 can claim `modes/`, and Layer 8 can claim `recordings/` plus `DiskSpaceSnapshot`.

### Step 2.4 — SeshatConfig
| Change | Before | After |
|---|---|---|
| Move storage ownership out of `Sources/SeshatCore/Config.swift` and make `SeshatConfig` a deprecated compatibility shim. | `SeshatConfig` is the real owner of base resolution and directory creation. | `AppConfig` is the canonical config type; `SeshatConfig` only forwards temporarily so downstream layers can finish their swaps independently. |

This step is the seam that prevents unrelated `SeshatConfig.sampleRate` and `SeshatConfig.channelCount` call sites from being dragged into Layer 2.

### Step 2.5 — AppComposition.makeTranscriptStore
| Change | Before | After |
|---|---|---|
| Replace the direct `SeshatConfig.recordingsDirectory()` call in `Sources/SeshatAppKit/Composition/AppComposition.swift:33-38` with a shared live locator. | App composition resolves and creates `recordings/` itself. | App composition obtains `let storage = AppConfig.liveStorageLocator()`, calls `try storage.ensureDirectoriesExist()` once at launch, and constructs `SQLiteTranscriptStore` from the locator. |

Keep the current failure posture: storage/bootstrap errors are logged and swallowed so the app still launches without history if the path is unwritable.

### Step 2.6 — SeshatAppMain.defaultTranscriptReader
| Change | Before | After |
|---|---|---|
| Replace the second direct `SeshatConfig.recordingsDirectory()` call in `Sources/SeshatAppKit/Composition/SeshatAppMain.swift:184-190`. | Notes/history composition re-resolves the storage root separately from app composition. | The Notes reader uses the same locator-based construction path as production composition, so `recordings/` ownership is defined in one layer. |

If `AppComposition` already exposes a shared live locator, reuse it here rather than constructing another ad hoc path helper.

### Step 2.7 — TranscriptStoreJSONL
| Change | Before | After |
|---|---|---|
| Add a locator-based designated initializer to `TranscriptStoreJSONL` and migrate production call sites to it. | `TranscriptStoreJSONL` takes a raw `recordingsDirectory` URL and owns both root-path choice and file bootstrap. | `TranscriptStoreJSONL` derives `recordings/transcripts.jsonl` from `StorageLocator.url(for: .recordings)` and keeps its existing `0600` file-permission behavior. |

Keep a direct-URL initializer only if it is narrowed to an internal/test seam. Do not leave a public second root-path API around once production callers have moved.

### Step 2.8 — SQLiteTranscriptStore
| Change | Before | After |
|---|---|---|
| Add a locator-based designated initializer to `SQLiteTranscriptStore` and route tmp-file bootstrap through `AtomicFileWriter`. | `SQLiteTranscriptStore` derives `transcripts.sqlite`, `transcripts.jsonl`, and `.tmp` inline from a raw recordings URL. | `SQLiteTranscriptStore` owns only SQLite-specific filenames and schema; the recordings root comes from `StorageLocator`, and tmp-write-then-rename lives behind `AtomicFileWriter`. |

Preserve all current SQLite invariants: same schema, same JSONL sidecar import behavior, same `0600` permissions, and still no `type`, `kind`, or `intent` column.

### Step 2.9 — BaseDirectoryMigrator
| Change | Before | After |
|---|---|---|
| Replace the hard-coded `["models", "modes", "recordings"]` list and duplicate byte-counting logic in `BaseDirectoryMigrator`. | The migrator has its own managed-directory list, its own recursive sizer, and writes the override through `SeshatConfig`. | The migrator derives managed roots from `ManagedDirectory`, updates the override through `AppConfig`, reuses Layer 2 byte-counting for future `DiskSpaceSnapshot`, and calls `ensureDirectoriesExist()` after a successful switch to create any still-empty managed roots. |

Rollback semantics and the destination writability probe must remain unchanged. If `logs/` and `cache/` already exist, they move too; if they do not, `ensureDirectoriesExist()` creates them after the switch.

### Step 2.10 — AdvancedTab / AdvancedTabViewModel
| Change | Before | After |
|---|---|---|
| Stop resolving the base directory through `Result { try SeshatConfig.baseDirectory() }` and stop hard-coding copy that assumes only three managed directories exist. | The Advanced tab treats base-path resolution as throwable and its user-facing copy names only `models`, `modes`, and `recordings`. | The Advanced tab reads from a locator or `AppConfig.liveStorageLocator()`, re-reads `storageLocator.baseDirectory` after migration instead of trusting the picker URL, and uses generic copy like "Seshat managed data" so `logs/` and `cache/` do not make the UI stale. |

Update `Tests/SeshatAppKitTests/ManualSettingsVerification.md` in this step, including both the success path and the existing failure-path gaps for non-writable or conflicting destinations.

### Step 2.11 — FluidAudioTranscriber
| Change | Before | After |
|---|---|---|
| Replace `SeshatConfig.directory(for:)` in `Sources/SeshatTranscription/FluidAudioTranscriber.swift:239-242` with locator-derived model roots. | The transcriber reaches into the legacy config type for model paths. | The transcriber derives `storageLocator.url(for: .models).appendingPathComponent(descriptor.id, isDirectory: true)` locally and leaves model-specific subdirectory creation to transcription/model code, not the locator. |

Do not teach `StorageLocator` about model descriptors. Layer 2 owns only fixed managed roots.

### Step 2.12 — FluidAudioModelDownloader
| Change | Before | After |
|---|---|---|
| Move the downloader onto locator-owned app storage without changing dependency-owned caches. | The downloader computes staging from the final model directory's parent and implicitly relies on whatever its caller passed in. | The downloader operates only on app-owned roots derived from Layer 2 and explicitly does not touch `.build/checkouts/FluidAudio` or any dependency-owned checkout/cache path. |

Do not move model staging into `cache/` in Layer 2. Create `cache/` now, but leave model-staging policy to Layer 6 so this layer does not silently pre-decide cleanup semantics.

## Stage 3 — Delete
Depends on: this layer's Stage 2, plus Layer 3 Stage 2, Layer 6 Stage 2, Layer 7 Stage 2, and Layer 8 Stage 2. Execute deletion only during `plans/central/INDEX.md`'s global deletion pass.

### Step 2.13 — Remove legacy storage helpers and duplicate path builders
| Change | Before | After |
|---|---|---|
| Delete the legacy storage helpers from `SeshatConfig`, any public raw-URL initializers kept only for compatibility, the hard-coded managed-subdirectory array in `BaseDirectoryMigrator`, and the scaffolding test that only keeps `SeshatConfig` alive. | Compatibility shims still exist so downstream layers can finish migrating. | Storage/path ownership lives only under `Sources/SeshatCore/Storage/`, with no duplicate root-path APIs left in production code. |

Concrete deletion targets: `SeshatConfig.baseDirectory()`, `modelsDirectory()`, `modesDirectory()`, `recordingsDirectory()`, `directory(for:)`, `BaseDirectoryMigrator.managedSubdirectories`, and `Tests/SeshatCoreTests/SeshatConfigScaffoldingTests.swift`.

## Test strategy
- Unit tests: add failing-first tests in `Tests/SeshatCoreTests/Storage/StorageLocatorTests.swift`, `AtomicFileWriterTests.swift`, `DiskSpaceSnapshotTests.swift`, and `AppConfigTests.swift` before any production implementation. Cover resolution precedence, eager creation of all five managed roots, atomic replacement rollback, and byte-accounting snapshots.
- Integration tests: preserve and update `Tests/SeshatCoreTests/SeshatConfigTests.swift:8-74`, `Tests/SeshatCoreTests/TranscriptStoreTests.swift:15-156`, `Tests/SeshatCoreTests/SQLiteTranscriptStoreTests.swift:34-199`, `Tests/SeshatCoreTests/BaseDirectoryMigratorTests.swift:8-164`, `Tests/SeshatTranscriptionTests/ModelPathTests.swift:6-22`, `Tests/SeshatTranscriptionTests/FluidAudioTranscriberAlreadyDownloadedTests.swift:43-55`, `Tests/SeshatAppKitTests/Notes/TranscriptReaderTests.swift:32-50`, and `Tests/SeshatAppKitTests/Settings/AdvancedTabViewModelTests.swift:8-60`.
- Fakes for the new protocols: add `FixedStorageLocator` and `FailingAtomicFileWriter` test doubles in core test support. Use them to remove process-global override mutation from tests that only need an isolated storage root.
- Regression guards the layer must preserve: base-directory precedence from `Tests/SeshatCoreTests/SeshatConfigTests.swift:8-74`; JSONL append/perms from `Tests/SeshatCoreTests/TranscriptStoreTests.swift:15-156`; SQLite bootstrap/search/runtime guards from `Tests/SeshatCoreTests/SQLiteTranscriptStoreTests.swift:34-199`; migration rollback/no-op/non-writable behavior from `Tests/SeshatCoreTests/BaseDirectoryMigratorTests.swift:8-164`; model-root placement and cached-model reuse from `Tests/SeshatTranscriptionTests/ModelPathTests.swift:6-22` and `Tests/SeshatTranscriptionTests/FluidAudioTranscriberAlreadyDownloadedTests.swift:43-55`; base-directory UX from `Tests/SeshatAppKitTests/Settings/AdvancedTabViewModelTests.swift:8-60` and `Tests/SeshatAppKitTests/ManualSettingsVerification.md:19-23`.
- Manual verification: keep `Tests/SeshatCoreTests/ManualConfigVerification.md:1-10` for packaged-app override behavior and extend `Tests/SeshatAppKitTests/ManualSettingsVerification.md:19-23` so the Advanced tab still proves successful migration, old-root cleanup, restart persistence, and both failure paths.

## Open design questions (surface — do not resolve)
- [QUESTION] Should Layer 6 keep model download staging adjacent to `models/<descriptor>` or intentionally move staging into `cache/` once Layer 2 lands? Layer 2 should create `cache/`, but it should not pre-decide model cleanup policy that belongs to Layer 6.
- [QUESTION] Is `logs/` only a reserved managed root in this refactor, or should a later diagnostics lane commit to a file-backed logger plus rotation policy? Layer 2 should establish ownership of the directory without inventing logging behavior beyond `Sources/SeshatCore/Logger.swift:4-52`.

## Validation checklist
- [ ] `Sources/SeshatCore/Storage/ManagedDirectory.swift:1` defines exactly `models`, `modes`, `recordings`, `logs`, and `cache`; satisfies `Locked decisions` bullet 1 and `Stage 1 Step 2.1`.
- [ ] `Sources/SeshatCore/Storage/StorageLocator.swift:1` exposes only `url(for:)`, `baseDirectory`, and `ensureDirectoriesExist()`; satisfies `Locked decisions` bullet 2 and `Stage 1 Steps 2.1-2.2`.
- [ ] `Sources/SeshatCore/Storage/AppStorageLocator.swift:1` preserves today's precedence from `Sources/SeshatCore/Config.swift:13-106` and `ensureDirectoriesExist()` creates all five managed roots idempotently; satisfies `Stage 1 Steps 2.1-2.2`.
- [ ] `Sources/SeshatCore/Storage/AtomicFileWriter.swift:1` and `Sources/SeshatCore/Storage/FileManagerAtomicFileWriter.swift:1` implement tmp-write-then-rename on top of `FileManager`; satisfies `Locked decisions` bullets 3 and 8 and `Stage 1 Step 2.1`.
- [ ] `Sources/SeshatCore/Storage/DiskSpaceSnapshot.swift:1` exists as a pure value type with no UI formatting logic; satisfies `Locked decisions` bullet 4 and `Stage 1 Step 2.1`.
- [ ] `Sources/SeshatCore/Storage/AppConfig.swift:1` is the canonical owner of override plumbing, while `Sources/SeshatCore/Config.swift:3` is only a temporary compatibility shim; satisfies `Locked decisions` bullets 5 and 6 and `Stage 2 Step 2.4`.
- [ ] `Sources/SeshatCore/TranscriptStore.swift:30` still persists JSONL at `recordings/transcripts.jsonl` with `0600` permissions, and `Tests/SeshatCoreTests/TranscriptStoreTests.swift:108-138` still pass; satisfies `Stage 2 Step 2.7`.
- [ ] `Sources/SeshatCore/SQLiteTranscriptStore.swift:33` uses the locator-owned `recordings/` root, `Sources/SeshatCore/SQLiteTranscriptStore.swift:171` still defines the same five-column schema with no `type`, `kind`, or `intent`, and `Tests/SeshatCoreTests/SQLiteTranscriptStoreTests.swift:86-129` still prove JSONL bootstrap is single-shot; satisfies `Stage 2 Step 2.8`.
- [ ] `Sources/SeshatCore/BaseDirectoryMigrator.swift:58` derives moved roots from `ManagedDirectory` instead of a string array, and `Sources/SeshatAppKit/Settings/AdvancedTab.swift:83`, `101`, and `179` no longer hard-code only `models`, `modes`, and `recordings`; satisfies `Stage 2 Steps 2.9-2.10`.
- [ ] `Sources/SeshatTranscription/FluidAudioTranscriber.swift:239` and `Sources/SeshatTranscription/FluidAudioModelDownloader.swift:13` derive model paths from `StorageLocator.url(for: .models)` and do not reference `.build/checkouts/FluidAudio`; satisfies `Locked decisions` bullets 5 and 7 and `Stage 2 Steps 2.11-2.12`.
- [ ] Only files in the `Observed current spread` table, new files under `Sources/SeshatCore/Storage/`, and matching tests/runbooks are touched; spot-check `Sources/SeshatCore/Config.swift:3`, `Sources/SeshatCore/BaseDirectoryMigrator.swift:58`, and `Sources/SeshatTranscription/FluidAudioModelDownloader.swift:4`; satisfies the Stage 1 collision rules and `Stage 3 Step 2.13`.
- [ ] No new production `UserDefaults.standard.*` call site appears outside `Sources/SeshatCore/Storage/AppConfig.swift:1`; verify `Sources/SeshatCore/BaseDirectoryMigrator.swift:65` and `Sources/SeshatAppKit/Settings/AdvancedTab.swift:137` stay on injected config/locator seams; satisfies the house rule and `Stage 2 Steps 2.4, 2.9, and 2.10`.
- [ ] `Sources/SeshatAppKit/Settings/AdvancedTab.swift:28` remains a copy/layout-only edit and introduces no `Color(hex:` outside `Theme/*`; satisfies the house rule and `Stage 2 Step 2.10`.
- [ ] `swift build --build-tests` is green in the main session after touching `Sources/SeshatCore/Storage/AppStorageLocator.swift:1`, `Sources/SeshatCore/Storage/FileManagerAtomicFileWriter.swift:1`, `Sources/SeshatCore/SQLiteTranscriptStore.swift:33`, and `Sources/SeshatTranscription/FluidAudioModelDownloader.swift:13`; satisfies the Stage 1 and Stage 2 completion gates.
- [ ] Acceptance tests and runbooks named in this plan all pass or are checked: `Tests/SeshatCoreTests/SeshatConfigTests.swift:8`, `Tests/SeshatCoreTests/BaseDirectoryMigratorTests.swift:8`, `Tests/SeshatCoreTests/TranscriptStoreTests.swift:15`, `Tests/SeshatCoreTests/SQLiteTranscriptStoreTests.swift:34`, `Tests/SeshatTranscriptionTests/ModelPathTests.swift:6`, `Tests/SeshatTranscriptionTests/FluidAudioTranscriberAlreadyDownloadedTests.swift:43`, `Tests/SeshatAppKitTests/Settings/AdvancedTabViewModelTests.swift:8`, `Tests/SeshatAppKitTests/Notes/TranscriptReaderTests.swift:32`, `Tests/SeshatCoreTests/ManualConfigVerification.md:1`, and `Tests/SeshatAppKitTests/ManualSettingsVerification.md:19`; satisfies the `Test strategy` section and every Stage 2 swap step.

## Backlog tickets authored
- None. This planning-only lane intentionally authors no additional `plans/backlog/*.md` file because the user limited the deliverable to `plans/central/LAYER_2_storage.md`; the two deferred points remain surfaced as `[QUESTION]` markers instead.

## Inter-layer dependencies
- **Requires**: none for Stage 1. Stage 2 requires Layer 2 Stage 1 only. Stage 3 additionally requires Layers 3, 6, 7, and 8 Stage 2 to stop depending on the `SeshatConfig` storage shim before deletion.
- **Blocks**: Layer 3 (defaults suite path and any future base-directory persistence move), Layer 6 (`models/` ownership), Layer 7 (`modes/` ownership), Layer 8 (`recordings/` metrics and `DiskSpaceSnapshot`).

## Commit style
`phase-N step 2.N: <verb-led subject>`. Test + fix in the same commit.

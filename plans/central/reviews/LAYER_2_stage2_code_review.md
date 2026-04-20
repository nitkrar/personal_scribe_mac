# Verdict

NEEDS REVISION

# Scope reviewed

- Commit: `90b137fd61068da352d3dba24435e49658956d9c` (`trunk: step storage.2 — Layer 2 Stage 2 consumer swap`)
Files touched:
- `Sources/SeshatCore/BaseDirectoryMigrator.swift`
- `Sources/SeshatCore/Config.swift`
- `Sources/SeshatCore/SQLiteTranscriptStore.swift`
- `Sources/SeshatCore/TranscriptStore.swift`
- `Sources/SeshatTranscription/FluidAudioModelDownloader.swift`

# Findings by severity

## Blocker

None.

## Major

- `Sources/SeshatCore/BaseDirectoryMigrator.swift:116-121` (`Stage 2 Step 2.9 — BaseDirectoryMigrator`) Description: the new post-switch `ensureDirectoriesExist()` call can now throw after every managed directory has already been moved and after the base-directory override has already been persisted. Evidence: the success path calls `AppConfig.setBaseDirectoryOverride(destinationBase, defaults: defaults)` and only then executes `try destinationStorageLocator.ensureDirectoriesExist()`, with no rollback or override restoration around that new throwing work. That changes the pre-existing migration semantics the plan explicitly says must remain unchanged: a late failure now returns an error even though the data and override have already switched to the destination. Suggested fix: either make the post-switch bootstrap non-fatal, or wrap it in rollback logic that restores both the moved directories and the prior override if creating empty managed roots fails.

- `Sources/SeshatTranscription/FluidAudioModelDownloader.swift:18-25` and `Sources/SeshatTranscription/FluidAudioModelDownloader.swift:107-121` (`Stage 2 Step 2.12 — FluidAudioModelDownloader`) Description: the downloader still does not own a real Layer 2 root; it reverse-engineers `.models` from the caller-supplied `directory` URL and then rebuilds the destination from that derived parent. Evidence: `DownloaderModelStorageLocator(modelDirectory: directory)` sets `modelsDirectory` to `modelDirectory.deletingLastPathComponent()`, and `ensureModelAvailable` uses that derived parent to choose both staging and final output. That means the downloader still accepts arbitrary caller-chosen roots instead of operating only on app-owned storage derived from Layer 2, which is the exact behavior Step 2.12 says to remove. Suggested fix: inject a real `StorageLocator` (or the resolved `.models` root) from the caller path that owns storage resolution, and build both `modelDirectory` and the staging directory from `storageLocator.url(for: .models)` rather than reconstructing them from the incoming destination URL.

## Minor

- `Tests/SeshatCoreTests/BaseDirectoryMigratorTests.swift:8-163` (`Stage 2 Step 2.9 — BaseDirectoryMigrator`) Description: the Stage 2 migrator changes are not covered by updated regression tests. Evidence: the existing suite still only exercises `models`, `modes`, and `recordings`, and it has no characterization for the new post-switch `ensureDirectoriesExist()` path or for moving already-present `logs/` and `cache/` directories. Because this commit changed the migration contract without adding those failing-first checks, the new late-failure bug above is not guarded. Suggested fix: add tests for moving pre-existing `logs/` and `cache/`, and add a failing-first regression that simulates `ensureDirectoriesExist()` failing after the move sequence to prove rollback/override semantics stay intact.

## Nit

None.

# Plan fidelity audit

- `SeshatConfig` — Migrated: yes, as a compatibility shim. `baseDirectory()`, managed-directory helpers, and `testingBaseDirectoryOverride` now forward through `AppConfig` / `StorageLocator`, which matches `Step 2.4`.
- `TranscriptStore` — Migrated: yes, with a locator-based designated initializer added per `Step 2.7`. Behavior around `recordings/transcripts.jsonl` and `0600` permissions appears preserved in source.
- `SQLiteTranscriptStore` — Migrated: yes, with locator-based path derivation and `AtomicFileWriter` bootstrap wiring per `Step 2.8`. Schema and JSONL bootstrap logic remain unchanged in source.
- `BaseDirectoryMigrator` — Migrated: partial. It now derives roots from `ManagedDirectory`, updates overrides through `AppConfig`, and reuses `ManagedDirectoryByteCounter`, but the new post-switch bootstrap path violates `Step 2.9`'s requirement that rollback semantics remain unchanged.
- `FluidAudioModelDownloader` — Migrated: partial. It now names `.models` through `StorageLocator` / `ManagedDirectory`, but the actual root is still reconstructed from the caller-provided URL rather than owned by a real Layer 2 locator as required by `Step 2.12`.

# Cross-layer bleed audit

- No forbidden cross-layer edits are present in this commit. The diff stays inside the five scoped Layer 2 consumers and does not spill into AppKit/MenuBar/Overlay/Composition code or unrelated layers.
- `AppComposition`, `SeshatAppMain`, `AdvancedTab`, and `FluidAudioTranscriber` still contain open Stage 2 work from `Steps 2.5`, `2.6`, `2.10`, and `2.11`, but those files were not part of this commit's write set. I am not counting their untouched state as bleed from this diff.
- The downloader change does not pre-decide Layer 6 staging cleanup policy (`cache/` is still unused here), so there is no Layer 6 policy bleed beyond the Step 2.12 fidelity issue above.

# Summary

- The swap is narrow and source-only: only the five scoped production files changed, with no unrelated refactors or CI/test churn in the diff.
- `SeshatConfig`, `TranscriptStore`, and `SQLiteTranscriptStore` mostly match the intended Layer 2 direction in source.
- `BaseDirectoryMigrator` introduces a new late-failure path after the override has already switched, which is a real semantic regression against `Step 2.9`.
- `FluidAudioModelDownloader` now uses Layer 2 names, but it still derives its root from the caller URL instead of truly owning an app-managed locator path, so `Step 2.12` is only partially complete.
- Regression coverage for the new migrator behavior was not updated, leaving the most important new failure mode unguarded.

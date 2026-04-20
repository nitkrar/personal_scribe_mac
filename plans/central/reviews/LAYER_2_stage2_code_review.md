# Layer 2 Stage 2 Code Review

## Verdict

NEEDS REVISION

## Findings

1. Major - `Sources/SeshatCore/TranscriptStore.swift:31-38` and `Sources/SeshatCore/SQLiteTranscriptStore.swift:34-45`: the new `StorageLocator` initializers are module-internal, while the raw `recordingsDirectory` initializers remain the only public cross-module API. That means the app-layer consumers called out by the plan still cannot swap to `StorageLocator`; `AppComposition` and `SeshatAppMain` remain on `SeshatConfig.recordingsDirectory()`, so Stage 2 does not complete the consumer migration.
2. Major - `Sources/SeshatTranscription/FluidAudioModelDownloader.swift:18-25`, `Sources/SeshatTranscription/FluidAudioModelDownloader.swift:93-95`, and `Sources/SeshatTranscription/FluidAudioModelDownloader.swift:103-111`: the downloader still derives a private locator from the caller-provided `directory` URL instead of accepting app-owned storage from `AppConfig` or an injected `StorageLocator`. It also normalizes the final destination to `models/<descriptor.id>`, so `ensureModelAvailable(at:)` no longer guarantees it will use the caller-supplied path. This is not the Step 2.12 consumer swap and it changes the API contract.
3. Major - `Sources/SeshatCore/BaseDirectoryMigrator.swift:116-118`: `AppConfig.setBaseDirectoryOverride(...)` now runs before `ensureDirectoriesExist()`. If creating `logs/` or `cache/` fails after existing directories have been moved, `migrate(to:)` throws with the override already pointed at the new base and without rolling the moved directories back. The previous implementation had no throwing work after the override write, so this regresses the plan requirement to preserve rollback semantics.

## Summary

The commit is source-only and the refactors inside `SeshatConfig`, `TranscriptStoreJSONL`, and `SQLiteTranscriptStore` mostly preserve their existing path and permission behavior, but the overall Stage 2 swap is incomplete and `BaseDirectoryMigrator` gains a new partial-failure mode. I did not run any swift commands.

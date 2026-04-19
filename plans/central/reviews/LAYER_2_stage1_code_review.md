## 1. Verdict

NEEDS REVISION

## 2. Findings by severity

### critical

None.

### major

- `Sources/SeshatCore/Storage/FileManagerAtomicFileWriter.swift:26-40` — `try applyPermissionsIfRequested(permissions, to: destinationURL)` — `replaceItem(at:permissions:writeToTemporaryURL:)` still performs a throwing permissions update after the temporary item has already been moved/replaced into place. If that final `setAttributes` call throws, the catch block can only delete the now-gone temporary URL, so callers observe an error after the destination contents have already changed. Suggested fix shape: make the staged item's metadata final before the rename and use a replacement path that preserves that metadata, or otherwise remove any throwing work after the atomic move/replace step; add a regression test that forces the post-rename permissions path to fail.

### minor

None.

### nit

- `Sources/SeshatCore/Storage/DiskSpaceSnapshot.swift:51-55` — `static func totalBytes(in directories: [URL], fileManager: FileManager) throws -> Int64` — this overload is unused in the Stage 1 commit; `capture(from:)` only calls the single-directory variant. Suggested fix shape: delete the dead helper until a real multi-directory caller exists, or route the snapshot aggregation through it.

## 3. Cross-layer concerns

No cross-layer stepping observed. `8cfc844` stays within the new Stage 1 storage namespace under `Sources/SeshatCore/Storage/` and `Tests/SeshatCoreTests/Storage/`, and it does not migrate `TranscriptStoreJSONL`, `SQLiteTranscriptStore`, `BaseDirectoryMigrator`, `FluidAudioModelDownloader`, or `SeshatConfig`.

## 4. Test coverage gaps

- `Tests/SeshatCoreTests/Storage/AtomicFileWriterTests.swift:12-79` — the suite covers create, replace, and write-closure failure, but it never drives the failure path after `replaceItemAt`/`moveItem` has already succeeded. The plan's atomic-replacement invariant is therefore unproven on the exact path that currently has the correctness bug.
- `Tests/SeshatCoreTests/Storage/DiskSpaceSnapshotTests.swift:8-47` — snapshot coverage only exercises an existing base directory with populated managed roots. There is no characterization for the missing-base-directory case, even though Stage 1 is supposed to define that behavior cleanly for future metrics consumers.

## 5. Summary

Stage 1 is otherwise close to the plan: the managed-directory contract, locator surface, `AppConfig` facade, atomic-writer abstraction, and disk-snapshot type are all present, and the diff stays isolated to the new storage namespace plus dedicated tests. The blocking issue is in `FileManagerAtomicFileWriter`, where a post-rename permissions failure can surface an error after the destination has already been mutated. Test coverage is solid for the basic happy paths and the pure-resolution/bootstrap split, but it does not yet characterize the post-rename failure path or the missing-base-directory snapshot path. I did not run `swift build` or `swift test`, per the brief.

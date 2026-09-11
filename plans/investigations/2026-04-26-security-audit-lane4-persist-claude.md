# Security Audit — Lane 4: Persistence (DB + Filesystem)

**Date:** 2026-04-26
**Reviewer:** Claude (independent of Codex Lane 4)
**Scope:** Disk-write surfaces under `Sources/PersonalScribeCore/Database`, `Sources/PersonalScribeCore/Storage`, `TranscriptStore.swift`, `BaseDirectoryMigrator.swift`, `TranscriptReader.swift`, `*/AppStore/`. Read-only audit.

---

## 1. Threat-model framing

Anything Ninimma writes to disk is a privacy surface. Concrete leak vectors considered:

- **Time-Machine backups** — files in `~/Library/Application Support/` are included in TM backups by default unless `URLResourceKey.isExcludedFromBackup` is set.
- **Spotlight indexing** — text-bearing files indexed by `mdimporter` end up in `~/Library/Metadata/CoreSpotlight/`, queryable from any user process.
- **GRDB sibling files** — WAL mode leaves `*-wal` and `*-shm` files alongside the DB; they survive process death and contain unflushed pages of plaintext content.
- **Rollback journal** — DELETE/TRUNCATE journal modes leave an ephemeral `*-journal` during transactions; if the process crashes mid-TX, the file persists with rollback content.
- **Temp/cache dirs** — files in `NSTemporaryDirectory()` / `~/Library/Caches/` survive process death and are world-readable by the user account.
- **`.DS_Store`** — Finder writes these into any directory the user navigates; informational, not actionable from the app.
- **POSIX permissions** — default file mode is 0644 in non-sandboxed apps; for single-user-secret data, 0600 is the standard.
- **macOS unified logging** — `os.Logger` strings flagged `privacy: .public` are persistent and harvestable via `log show` / `log collect`, including by other admin users on the box.
- **Migration orphans** — moves that don't cover all subdirs leave plaintext shards at the old path.

Ninimma is **NOT App-Sandboxed** (no `com.apple.security.app-sandbox` in the production bundle entitlements; the Info.plist at `Ninimma.app/Contents/Info.plist` declares no sandbox; the only `.entitlements` files in-tree are GRDB's bundled test fixtures). That widens the threat surface — there is no per-app container; writes go to the user's real `~/Library/...`.

---

## 2. Files audited

### Persistence (in scope)
- `Sources/PersonalScribeCore/Database/AppDatabase.swift`
- `Sources/PersonalScribeCore/Database/TranscriptRepository.swift`
- `Sources/PersonalScribeCore/Database/Migrations/TranscriptsMigrator.swift`
- `Sources/PersonalScribeCore/Database/DatabaseOperationStatus.swift`
- `Sources/PersonalScribeCore/Database/RuntimeGateFailure.swift`
- `Sources/PersonalScribeCore/Database/TranscriptOrder.swift`
- `Sources/PersonalScribeCore/Database/TranscriptStorageError.swift`
- `Sources/PersonalScribeCore/Storage/AppConfig.swift`
- `Sources/PersonalScribeCore/Storage/AppStorageLocator.swift`
- `Sources/PersonalScribeCore/Storage/AtomicFileWriter.swift`
- `Sources/PersonalScribeCore/Storage/FileManagerAtomicFileWriter.swift`
- `Sources/PersonalScribeCore/Storage/FixedBaseDirectoryStorageLocator.swift`
- `Sources/PersonalScribeCore/Storage/StorageLocator.swift`
- `Sources/PersonalScribeCore/Storage/ManagedDirectory.swift`
- `Sources/PersonalScribeCore/Storage/DiskSpaceSnapshot.swift`
- `Sources/PersonalScribeCore/TranscriptStore.swift` (`TranscriptEntry` GRDB record)
- `Sources/PersonalScribeCore/TranscriptReader.swift` (read protocols)
- `Sources/PersonalScribeCore/BaseDirectoryMigrator.swift`
- `Sources/PersonalScribeCore/AppStore/*.swift` (in-memory only — confirmed)
- `Sources/PersonalScribeAppKit/AppStore/AppKitVisibilityModeProvider.swift` (in-memory)
- `Sources/PersonalScribeSession/AppStore/SessionCoordinator+AppStore.swift` (in-memory)
- `Sources/PersonalScribeCore/Logger.swift` (os.Logger — relevant to privacy of unified logging)

### Adjacent disk-write surfaces (followed because in-scope)
- `Sources/PersonalScribeAppKit/Composition/AppComposition.swift` (DB composition)
- `Sources/PersonalScribeAppKit/Composition/PersonalScribeAppMain.swift` (startup migration call sites)
- `Sources/PersonalScribeSession/SessionCoordinator.swift` (persistence handler)
- `Sources/PersonalScribeSession/WorkflowMode/WorkflowModeStore.swift` (JSON sidecar)
- `Sources/PersonalScribeSession/Models/Selection/ModelBoundProcessorProvider.swift` (model-artifact filesystem)
- `Sources/PersonalScribeSession/Models/Selection/ActiveModelService.swift` (UserDefaults persistence)
- `Sources/PersonalScribeCore/Preferences/*.swift` (UserDefaults)
- `Ninimma.app/Contents/Info.plist` (sandbox status)

### Inventory of writes (semantic, not keyword)

| What | Where on disk | Encrypted? | Cleanup? |
|---|---|---|---|
| `transcripts.sqlite` (transcript text + metadata) | `<base>/recordings/transcripts.sqlite` (default `~/Library/Application Support/personal_scribe/recordings/`) | No (plaintext SQLite) | Per-row delete API only; no cap, no expiry |
| `transcripts.sqlite-journal` (rollback, ephemeral) | sibling of DB | No | SQLite removes on commit; persists on crash |
| `workflow-modes.json` (mode names + system prompts) | `<base>/workflow-modes.json` | No | Overwritten via `Data.write(.atomic)`; no cap |
| Model artifacts (`.mlmodelc`, `coremldata.bin`, vocab JSON) | `<base>/models/<repo>/...` | No | `removeDownloadedFiles(_:)` API |
| Model-artifact stub files (test/dev) | same | No | same |
| Migration probe file | `<destinationBase>/.personal_scribe-migration-probe-<uuid>` | No | Removed immediately by migrator |
| Atomic-write temp files | `<dest-parent>/.<name>.<uuid>.tmp` | No | Removed on success (replace) or on failure (cleanup) |
| UserDefaults | `~/Library/Preferences/com.nitkrar.personal_scribe.plist` | No | UserDefaults API |
| Unified-logging entries | OSLog system store (`~/Library/Logs`/`/var/db/diagnostics`) | No | OS-managed rolling buffer |

**Audio:** **NOT persisted.** `PCMBuffer` is in-memory only; the capture pipeline streams PCM through `AVAudioCaptureService → SessionCoordinator → Transcriber` without ever writing audio bytes. `bufferedAudio: [PCMBuffer]` in `SessionPipelineOrchestrator` is in-memory and `removeAll()`'d on every session end (orchestrator lines 280, 341, 365, 425, 430). Confirmed by grep: zero occurrences of `AVAudioFile`, `AVAudioRecorder`, `.wav`, `.caf`, `.m4a` in `Sources/`.

**AppStore family:** Pure in-memory. `AppStore.snapshot` is `@Published`; nothing in `Sources/PersonalScribeCore/AppStore/`, `Sources/PersonalScribeAppKit/AppStore/`, or `Sources/PersonalScribeSession/AppStore/` calls `Data.write`, `FileManager.createFile`, `OutputStream`, or any DB API. (Verified by full-tree grep.)

### GRDB configuration
- `AppDatabase.swift:57` constructs `DatabaseQueue(path:)` with the **default** `Configuration` (no custom journal mode, no passphrase).
- GRDB default `Configuration.journalMode = .default` (`.build/checkouts/GRDB.swift/GRDB/Core/Configuration.swift:322`); for `DatabaseQueue` (`DatabaseQueue.swift:50-60`), `.default` skips the WAL switch entirely. SQLite's journal mode therefore stays at its built-in default (DELETE / rollback-journal). **No `-wal` / `-shm` sibling files are produced.**
- No `passphrase`, `SQLCipher`, or `Configuration` field for at-rest encryption is set anywhere.
- DB file is chmod'd to `0o600` immediately after migrations (`AppDatabase.swift:192-204`). Good.
- FTS5 virtual table `transcripts_fts` is content-synchronized to `transcripts` via GRDB's `synchronize(withTable:)` (`TranscriptsMigrator.swift:41`). The FTS index also stores plaintext token data inside the same SQLite file — no separate sidecar.

### Logger privacy posture
`PersonalScribeLogger` (Logger.swift:13-44) interpolates **every** message component as `privacy: .public`. The macOS unified logging system persists these strings (rotated, but durable for hours/days). Call sites that include user-derived strings:
- `MenuBarSceneModel.swift:129,133` — "Copy transcript skipped…" / "Copying latest transcript to clipboard" (no transcript content interpolated).
- `ClipboardBatchOutput.swift:82,102,118,125,141,148` — log strings reference "transcript" by concept; payload not interpolated.
- `SessionCoordinator.swift:351` — "Failed to persist transcript to TranscriptRepository" — error description is `error.localizedDescription`, which for GRDB can include SQL fragments but not the bound transcript text (parameters are placeholders).
- `ActiveModelService.swift:404` — interpolates a model id string. Not user content.

I did not find any log line that interpolates transcript text, audio metadata, or the contents of clipboard snapshots into a public-flagged log string. The blanket `privacy: .public` is still a defense-in-depth concern (see Findings F-3).

---

## 3. Findings

### F-1 — Transcripts stored plaintext, included in Time-Machine backups (HIGH)

**File:** `Sources/PersonalScribeCore/Database/AppDatabase.swift:42-69`, `Sources/PersonalScribeCore/Storage/AppConfig.swift:109-110`, `Sources/PersonalScribeCore/Storage/AppStorageLocator.swift:26-39`

**What:** All transcripts (text, timestamp, audio/processing duration) live in a plaintext SQLite database at `~/Library/Application Support/personal_scribe/recordings/transcripts.sqlite`. `~/Library/Application Support/` is included in Time Machine and in iCloud Drive's "Backups" surface where applicable. No code in the project sets `URLResourceKey.isExcludedFromBackup` on the recordings directory or the DB file — verified by grep across all of `Sources/`: zero hits for `isExcludedFromBackup` / `kCFURLIsExcludedFromBackupKey`.

**Why it matters:** Anyone with access to the user's Time Machine target (network NAS, attached drive, second admin on the Mac) can read the entire transcript history. The 0600 file mode protects against same-machine non-admin readers but does not propagate into the backup.

**Mitigation:** Set `URLResourceKey.isExcludedFromBackup = true` on the `recordings/` directory at `AppDatabase.init` (one extra `setResourceValues(_:)` call after `createDirectory`). The same flag should be applied to `<base>/models/` (large CoreML artifacts users would not want re-uploaded by TM anyway) and `<base>/workflow-modes.json`. Per-volume — does not affect functionality.

---

### F-2 — Transcripts stored plaintext, indexable by Spotlight (HIGH)

**File:** Same surfaces as F-1.

**What:** SQLite databases are not indexed by Spotlight by default (no built-in `.sqlite` mdimporter), so the DB body is safe from `mdfind`. **But** there is no defensive `com.apple.metadata:kMDItemSupportFileType = MDSystemFile` or equivalent xattr set, and any future feature that exports transcripts (e.g. a `.txt` / `.json` dump under the same base directory) will be auto-indexed unless the directory carries a `.metadata_never_index` marker. Today's `workflow-modes.json` IS subject to Spotlight indexing of its content — it is plain JSON containing user-authored mode names and system prompts.

**Why it matters:** `~/Library/Application Support/personal_scribe/workflow-modes.json` text appears in Spotlight global search. Today it only contains mode/prompt strings (low sensitivity), but the directory has no general "do not index" marker, so this gets worse if any future write under `<base>/` ever lands a transcript export, log dump, or scratch file.

**Mitigation:** Drop a zero-byte `.metadata_never_index` file at `<base>/` during `AppStorageLocator.ensureDirectoriesExist()` — Spotlight respects this marker for the whole directory subtree. One-line addition; no behavior impact.

---

### F-3 — Logger interpolates every value as `privacy: .public` (MEDIUM)

**File:** `Sources/PersonalScribeCore/Logger.swift:20, 30, 42`

**What:** `PersonalScribeLogger` hard-codes `privacy: .public` on the rendered message, the file path, and the line number for every log emission (debug, info, error). Any caller that ever interpolates user-derived data into the message string has its content persisted to the unified logging store and accessible via `log show` / `log collect` to any admin on the machine and in any sysdiagnose bundle the user submits.

**Why it matters:** Today's call sites (audited above in §2 inventory) do not interpolate transcript text or clipboard payloads — but the contract is "trust every caller to never put PII in the format string." That's a per-caller pattern instead of a central guarantee, which violates the project's own §9 engineering disposition ("strong central layer over per-caller patterns"). One forgetful future log line leaks. There is no "redacted by default for unknown values" knob.

**Why this is medium not high:** No current call site demonstrably leaks user content. The risk is forward — every new logger.info/.error call has to be hand-audited.

**Mitigation:** Switch the logger to take a static format string + Swift's structured `OSLogMessage` interpolation, with `privacy: .private` (or `.sensitive`) as the default for any untrusted interpolation, and `privacy: .public` only opt-in for known-safe components like categories and line numbers. This is the standard `os.Logger` posture.

---

### F-4 — `migrateFromLegacyBrandDirectoryIfNeeded` defined but never called (LOW)

**File:** `Sources/PersonalScribeCore/BaseDirectoryMigrator.swift:88-102`

**What:** `migrateFromLegacyBrandDirectoryIfNeeded` moves `~/Library/Application Support/Seshat/` to `~/Library/Application Support/personal_scribe/`. It is a `public` method and has tests, but **no production call site invokes it** — verified by full-tree grep (only definition, doc comment, and worktree copies). The startup path in `PersonalScribeAppMain.init` (line 48) only runs `PreferenceMigrator.migrate(...)` (UserDefaults rename), not the directory rename.

**Why it matters:** Any user who upgraded from a pre-rename `Seshat/` build keeps a plaintext orphan at `~/Library/Application Support/Seshat/transcripts.sqlite` (and JSONL, models, etc.) forever. The new build writes to `personal_scribe/` and does not touch / clean up / migrate the old plaintext data. From a privacy lens this is a stale-data leak: the user thinks they uninstalled the old version, but their full transcript history persists at the legacy path with the old (likely 0644) permissions.

**Why low not medium:** This only affects users whose machines had a `Seshat/` Application Support directory at the time of the rename. New installs are clean. The data sits inside the user's account; not exposed network-wise.

**Mitigation:** Either (a) call `migrateFromLegacyBrandDirectoryIfNeeded()` from `PersonalScribeAppMain.init` next to `PreferenceMigrator.migrate`, or (b) delete the dead method if the project has decided legacy users must manually migrate. Status quo (defined-but-unused) is the worst of both.

---

### F-5 — Atomic-write temp files inherit creating-process umask (LOW)

**File:** `Sources/PersonalScribeCore/Storage/FileManagerAtomicFileWriter.swift:38-50`

**What:** `replaceItem(at:permissions:writeToTemporaryURL:)` writes content to a `.<name>.<uuid>.tmp` file in the destination's parent directory, then `replaceItemAt` / `moveItem`s it into place. POSIX permissions are applied to the **temporary** file before the replace (line 40). That ordering is correct in steady state. **However:** if the caller passes `permissions: nil`, the temp file lands at the process umask default (typically 0644 in a non-sandboxed app), and the destination ends up at 0644. There is no callsite today that uses this writer for transcript text — but `WorkflowModeStore.save` writes `workflow-modes.json` via plain `Data.write(to:options:.atomic)` (which has the same umask issue) at `WorkflowModeStore.swift:72`.

**Why it matters:** `workflow-modes.json` ends up world-readable by other accounts on the machine. Mode names and system prompts are user-authored text; not maximum-sensitivity, but the same machine policy that demands DB at 0600 should apply.

**Why low:** Same-machine multi-user threat is not the dominant lane-4 concern (TM/Spotlight are). Single-user laptops are unaffected.

**Mitigation:** Either (a) route `WorkflowModeStore` through `FileManagerAtomicFileWriter` with `permissions: 0o600`, or (b) add a `chmod 0600` step after `data.write(...)` in `WorkflowModeStore.save`. Apply the same 0600 to the recordings/ models/ workflow-modes.json files at directory creation in `AppStorageLocator.ensureDirectoriesExist`.

---

### F-6 — Crash-time rollback journal can persist plaintext page deltas (LOW)

**File:** `Sources/PersonalScribeCore/Database/AppDatabase.swift:55-60` (DatabaseQueue construction with default journal mode)

**What:** SQLite's default rollback-journal mode (DELETE) creates a sibling `transcripts.sqlite-journal` file during transactions. On clean commit, the journal is removed. On process crash mid-TX, the journal persists with rollback-required pages (plaintext fragments of transcript text + metadata) until SQLite's recovery runs at the next open. The journal file inherits parent dir permissions; we do not chmod it. F-1 / F-2 backup + Spotlight concerns extend to it.

**Why it matters:** The window is small and bounded (only between BEGIN and COMMIT), and the data is identical to what the DB already holds, but the journal file does not get the 0600 treatment that `setPermissionsIfPresent` applies to `transcripts.sqlite`. After a crash, the journal can sit on disk for an arbitrarily long time before next app launch.

**Mitigation:** Apply `URLResourceKey.isExcludedFromBackup` to the entire `recordings/` directory (covers F-1 and F-6 together), and tighten the parent dir mode to 0700 so the journal inherits restricted access.

---

## 4. Coverage gaps

- **GRDB itself:** I read the bundled GRDB checkout's `DatabaseQueue.init` to confirm the default journal mode is not WAL. I did NOT audit GRDB internals for incidental disk writes (e.g. recovery-mode temp paths, cache spilling). Out of scope per lane brief.
- **Live-disk inspection:** Cannot inspect actual filesystem state on this machine (no `ls ~/Library/Application Support/personal_scribe/` requested per read-only constraint). All findings are derived from source.
- **OSLog spillover:** The exact retention of `privacy: .public` strings in unified logging is OS-version-dependent. I confirmed the call sites do not interpolate transcript text today; I did not verify what `error.localizedDescription` produces for GRDB errors at runtime (could in principle include row-level data for some error classes — I assume it does not from reading GRDB's `DatabaseError` source, but did not exercise it).
- **Non-production code paths:** `ModelBoundProcessorProvider.swift` lines 209-234 is a `materializeArtifacts` stub that writes `Data([0x1])` / `Data("{}".utf8)` / `Data("stub".utf8)` to model artifact paths. This is a test/dev shim referenced by `ProcessorProviderStubAdapterSupport` — not user data, not a privacy leak, but worth flagging that it bypasses `FileManagerAtomicFileWriter` and uses `data.write(to:)` directly without any permission tightening (line 232). Not raised as a finding because the data is non-sensitive constants; flagged here for completeness.
- **Tests directories:** Out of scope per brief (lane is `Sources/`).
- **Audio capture:** I confirmed no audio is persisted to disk in production, but did not exhaustively read every line of `PersonalScribeAudio/` — based on grep + spot-reads of `AVAudioCaptureService.swift` and `AudioResampler.swift`, the boundary is `AsyncThrowingStream<PCMBuffer, Error>` which is an in-memory channel. If a future feature adds an `AVAudioFile` writer for raw audio retention, this lane's threat model needs re-running.
- **Co-installed CLI/helper tools:** No evidence of any helper binary writing under `<base>/`. Lane is silent on XPC services / Spotlight importers; none observed.

---

## Summary

The architecture is in good shape on the structural axes: audio is in-memory only, AppStore is in-memory only, the DB uses rollback-journal not WAL (no `-wal` / `-shm` siblings), the DB file is chmod'd 0600, and no encryption-at-rest sleight-of-hand is being claimed. The TDD-clean repository pattern keeps writes funneled.

The main gaps are **macOS-platform integration** rather than code defects: no Time-Machine exclusion, no Spotlight directory marker, no chmod on the JSON sidecar, a logger that defaults every value to `privacy: .public`, and a legacy-directory migrator that's defined but never wired into startup.

F-1 and F-2 are the actionable high-priority items. Both are one-line fixes per directory, no behavior change, no test surface to disturb beyond verifying the resource-key flag persists.

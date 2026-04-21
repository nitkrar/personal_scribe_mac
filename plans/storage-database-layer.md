# Storage / Database Layer

> **Do NOT diverge from this plan. Silent divergence is the cardinal sin. To deviate, surface the proposed divergence in a commit-message comment AND in the hand-off report; wait for main-session confirmation.**

---

## 1. Intent

Consolidate Ninimma's SQLite ownership under **one `AppDatabase`** that opens exactly one `DatabaseQueue` on `recordings/transcripts.sqlite`, and **one `TranscriptRepository`** that hides raw SQL + GRDB record protocols from every caller. Today the same file is opened by three different types, each deriving its own path; this layer ends that.

This plan **absorbs Phase 3.D**. GRDB and FTS5 already landed via Phase 3.D; what's missing is the ownership contract. `StorageLocator` (Layer 2) owns filesystem paths and is consumed unchanged — this layer owns database connections and query surfaces on top of it.

---

## 2. Current scatter

Four open `DatabaseQueue` handles on the same `transcripts.sqlite` file today:

| Handle | Opened by | Mode |
|---|---|---|
| 1 | `AppComposition.makeTranscriptStore()` → `SQLiteTranscriptStore` (`AppComposition.swift:45-54`, `SQLiteTranscriptStore.swift:29-76`) | writable |
| 2 | `PersonalScribeAppMain.defaultTranscriptReader()` → **second** `SQLiteTranscriptStore` (`PersonalScribeAppMain.swift:303-314`) | writable |
| 3 | `AppComposition.makeMetricsReader()` → `SQLiteMetricsReader` directly (`AppComposition.swift:76-86`, `SQLiteMetricsReader.swift:14`) | read-only |
| 4 | `AppComposition.makeMetricsService()` → internal `SQLiteMetricsReader` inside `SQLiteMetricsService` (`AppComposition.swift:60-71`, `SQLiteMetricsService.swift:18`, `SQLiteMetricsReader.swift:14`) | read-only |

Four independent path derivations of `recordings/transcripts.sqlite`:

- `SQLiteTranscriptStore.swift:5` (filename constant `transcripts.sqlite`)
- `AppComposition.swift:9-16` (duplicated filename constant)
- `AppComposition.swift:60-71` (`makeMetricsService` — string-appends `transcripts.sqlite`)
- `AppComposition.swift:76-86` (`makeMetricsReader` — string-appends again)

Silent schema coupling: `SQLiteMetricsReader` (`SQLiteMetricsReader.swift:18-119`) runs `SELECT … FROM transcripts …` directly against the shared file, and `MetricsTranscriptRow` (`SQLiteMetricsReader.swift:141-175`) is a semantic duplicate of `PersistedTranscriptEntry` (`SQLiteTranscriptStore.swift:428-462`) — two places that must agree on the schema by convention only.

Legacy raw-URL inits (`SQLiteTranscriptStore.swift:33-39`, `TranscriptStore.swift:30-36`) keep a parallel path-construction surface alive inside a `FixedBaseDirectoryStorageLocator` adapter.

Current schema today (`SQLiteTranscriptStore.swift:177-214`): four migrations under GRDB's `DatabaseMigrator` — `v1_transcripts_table` (5 columns: `id`, `timestamp`, `text`, `audio_duration`, `processing_duration`), `v2_fts_search` (FTS5 virtual table + triggers, `unicode61(diacritics: .remove)` tokenizer), `v3_jsonl_bootstrap` (loads `transcripts.jsonl` sidecar and inserts each row — **not a no-op**, per review correction), `v4_runtime_guard_marker`. Schema-mismatch posture is **throw, never DROP** (three `OpenError` cases at `SQLiteTranscriptStore.swift:17-21`).

GRDB is already pinned at `7.10.0` (`Package.swift:41-44`).

---

## 3. Target architecture

### Locked decisions

- **`AppDatabase` is the canonical database owner.** Exactly one instance per app process, held as a shared reference inside `AppComposition` — **never re-constructed by callers** (including `PersonalScribeAppMain.defaultTranscriptReader`; it consumes the shared instance, it does not call a factory that opens a second queue). No caller outside `Sources/PersonalScribeCore/Database/` opens a `DatabaseQueue` or `DatabasePool`.
- **`AppDatabase` is a `struct` wrapping `any DatabaseWriter`**, not an `actor`. GRDB serializes internally; an actor wrapper would add `await` cost without a new guarantee. *(Q-A1 locked.)*
- **Underlying handle is `DatabaseQueue`**, not `DatabasePool`. Write rate is ≈ 1/minute; re-evaluate only if profiling under Phase 3.B surfaces read contention. *(Q-A2 locked.)*
- **`AppDatabase.write` and `read` closures are `public`**, governed by a code-review rule: no `write` / `read` call sites outside `Sources/PersonalScribeCore/Database/` and test targets. *(Q-C1 locked.)*
- **`TranscriptRepository` is the only CRUD surface.** Raw SQL + GRDB record types do not escape the `Database/` module. Init signature is `TranscriptRepository.init(database: AppDatabase)` — makes "construct via owner" a compile-time contract; no raw `DatabaseReader`/`DatabaseWriter` injection. *(Q-F1 locked.)*
- **`TranscriptEntry` adopts `FetchableRecord` + `PersistableRecord` directly**, with snake_case `CodingKeys` aligned to the SQLite schema. Today's two shadow-struct decoders (`PersistedTranscriptEntry`, `MetricsTranscriptRow`) are deleted — one decode path, one `CodingKeys` block, one UUID-validation site. *(Q-E1 locked: Option A.)*
- **Single SQLite file**: `recordings/transcripts.sqlite`. No split. Metrics reads move onto the shared `AppDatabase` — they already share the file today.
- **Paths via `StorageLocator.url(for: .recordings)` only.** String-concatenation of `transcripts.sqlite` outside `Database/` is forbidden (grep-enforced in §7).
- **JSONL sidecar is dead.** `TranscriptStoreJSONL` and `transcripts.jsonl` writes are deleted outright in Pass 2 — no shim, no backward-compat, no sidecar-import for fresh installs. Users who somehow only have a sidecar (never opened a post-Phase-3.D build) start with an empty history on next launch; explicit accepted loss.
- **Read-error posture: non-throwing.** `recent(limit:)`, `count()`, `search(query:)`, `all()`, and `entries(in:orderedBy:)` return empty results on internal failure rather than throwing. Failures are logged via `PersonalScribeLogger` only; the health-observable surface (`AsyncStream<StorageHealth>` + Advanced Settings "Database health" row + top-level banner) is **extracted to #043** and unblocks after this plan's Pass 1 lands the core `AppDatabase` instance. `TranscriptReading` protocol stays non-throwing as it is today — zero call-site churn across the 3 view-model read sites (`CopyLastTranscriptAction`, `TranscriptionsTabViewModel`, `HomeTabViewModel`). *(Q-B1 locked; storageHealth surface split out.)*
- **Write-error posture preserved**: `append(_:)` still throws — writes can fail in ways the caller must act on (session pipeline re-queue, UI toast). Publishing thrown-write failures into the banner/Settings row is part of **#043**, not this plan.
- **Metrics compat shim: none.** `MetricsSnapshotStore.init(databaseURL:)` (`MetricsSnapshotStore.swift:26-48`) is deleted in Pass 2 — no gradual transition. Every caller (including test harnesses) switches to `init(appDatabase:)` in the same commit series. *(Q-Metrics-Shim locked.)*
- **`PRAGMA user_version = N` kept**: each migration still writes its version number into `user_version` alongside GRDB's own `grdb_migrations` table. GRDB doesn't read it, but external `sqlite3` CLI inspection does. Zero runtime cost. *(Q-UserVersion locked.)*
- **`PLAN_PHASES.md` Phase 3.D absorbed**: one-line edit replacing the Phase 3.D bullet with a pointer to `plans/storage-database-layer.md` (#026), landing alongside this plan's first Pass-1 commit. *(Q-Phase3D locked.)*
- **Schema preserved byte-identically for v1, v2, v4**: existing DDL reproduced exactly. Opening an existing `transcripts.sqlite` with the new migrator is a no-op. **`v3_jsonl_bootstrap` migration stays registered** so `grdb_migrations` rows on existing DBs stay consistent, but its body is a pure `PRAGMA user_version = 3` marker — no JSONL import in the new code path.
- **5-column invariant on `transcripts`**: `id`, `timestamp`, `text`, `audio_duration`, `processing_duration`. No `type`, `kind`, `intent`, `modeId`, or `trigger` in this layer — Phase 4 only.
- **Schema-mismatch posture preserved**: throw, never DROP.
- **Swift 6 strict concurrency**: all new public types `Sendable`. `@Sendable` on every crossing closure.
- **TDD**: every production change ships with a failing test first. Test + fix in the same commit.
- **No test-only hooks on production types.** Protocol seams for fakes.
- **Commit tag**: `storage-layer step N.M:`. No `phase-N`, `sprint-N`, or `layer-N` prefixes.

### Non-goals

- No `notes` table — Phase 3 stores every transcription in `transcripts`.
- No embeddings or vector columns — Phase 4.
- No `UserDefaults` / preferences touched — Layer 3 owns that.
- No redesign of `StorageLocator` / `ManagedDirectory` / `AtomicFileWriter` — Layer 2 owns those; this layer consumes them.
- No graduation of modes metadata into SQLite — modes stay as JSON in `modes/`.

### API sketch

```swift
// Sources/PersonalScribeCore/Database/AppDatabase.swift
public struct AppDatabase: Sendable {
    public init(locator: some StorageLocator,
                filename: String = "transcripts.sqlite") throws
    public func write<T: Sendable>(_ block: @Sendable (Database) throws -> T) async throws -> T
    public func read<T: Sendable>(_ block: @Sendable (Database) throws -> T) async throws -> T
}
// `storageHealth: AsyncStream<StorageHealth>` + StorageHealth / StorageHealthError types are
// scope-split to #043 (follow-up landing after Pass 1).

// Sources/PersonalScribeCore/Database/TranscriptRepository.swift
public struct TranscriptRepository: Sendable {
    public init(database: AppDatabase)
    public func append(_ entry: TranscriptEntry) async throws
    public func recent(limit: Int) async -> [TranscriptEntry]
    public func count() async -> Int
    public func search(query: String) async -> [TranscriptEntry]
    public func all() async -> [TranscriptEntry]
    public func entries(in window: ClosedRange<Date>,
                        orderedBy order: TranscriptOrder) async -> [TranscriptEntry]
}

public enum TranscriptOrder: Sendable { case timestampAscending, timestampDescending }

// Thrown at init + write paths only (reads never throw).
public enum TranscriptStorageError: Error, Sendable {
    case openFailed(underlying: Error)
    case runtimeUnsupported(RuntimeGateFailure)
    case migrationFailed(version: String, underlying: Error)
    case decodingFailed(underlying: Error)
    case queryFailed(underlying: Error)
}
public enum RuntimeGateFailure: Sendable, Equatable {
    case unsupportedSQLiteVersion(current: String, minimum: String)
    case missingFTS5CompileOption
    case invalidFTSTokenizerConfiguration(sql: String?)
}
```

`RuntimeGateFailure` is a 1:1 re-home of today's `SQLiteTranscriptStore.OpenError` cases (`SQLiteTranscriptStore.swift:17-21`). Row decoding lives on `TranscriptEntry` itself via `FetchableRecord` + `PersistableRecord` conformance — today's `PersistedTranscriptEntry` (`SQLiteTranscriptStore.swift:428-462`) and `MetricsTranscriptRow` (`SQLiteMetricsReader.swift:141-175`) shadow structs are deleted; snake_case `CodingKeys` move onto `TranscriptEntry` (safe because JSONL is being deleted in the same pass).

---

## 4. Approach

Not a gated workflow. Three passes, each squashed into a handful of commits:

1. **Build in parallel.** Add `Sources/PersonalScribeCore/Database/{AppDatabase,TranscriptRepository,Migrations/...}.swift` alongside the existing stores. Port v1, v2, v4 verbatim; `v3_jsonl_bootstrap` registers as a no-op PRAGMA-only marker in the new code path (keeps `grdb_migrations` rows consistent on existing DBs). `TranscriptEntry` gains `FetchableRecord` + `PersistableRecord` conformance with snake_case `CodingKeys`. Nothing swapped yet; existing code keeps compiling and passing tests. Characterization tests pin the schema via `sqlite_master` before the swap lands.

2. **Swap composition + delete JSONL in one pass.** Rewire both composition roots (`AppComposition` and `PersonalScribeAppMain.defaultTranscriptReader`) and every caller (metrics service, metrics reader, session coordinator, pipeline orchestrator, notes tab, menu-bar copy-last action) to consume the shared `AppDatabase` / `TranscriptRepository`. `SQLiteTranscriptStore` becomes a thin forwarding shim so Pass-2 tests keep compiling. **`TranscriptStoreJSONL` is deleted outright** (no shim) along with its tests and the sidecar-writing code path in the session pipeline — no backward-compat for the JSONL format. **No per-file choreography** — the swap is one coherent change; squash locally and land when trunk is green.

3. **Delete.** Remove the `SQLiteTranscriptStore` shim, `SQLiteTranscriptReader`, **`SQLiteMetricsReader` (its queries + shadow-struct row decoder + `executeWriteForTesting` seam all collapse into `TranscriptRepository` + `TranscriptEntry`)**, the legacy raw-URL inits, the duplicated filename constant in `AppComposition`, **`AppComposition.makeMetricsService()` + `makeMetricsReader()` path-factory methods** (metrics wiring consumes the shared `AppDatabase` directly), and the convenience `init(databaseURL:)` on `SQLiteMetricsService` / `MetricsSnapshotStore`. Update any imports.

Test discipline every pass: in-memory `DatabaseQueue(path: ":memory:")` for unit fakes. Fresh DB per test — no `setUp` leakage, no singletons. Protocol seams for injection, never `#if DEBUG` knobs. New tests **bypass `AppConfig.testingBaseDirectoryOverride`** (process-global, leaks across parallel test classes); inject a `FixedBaseDirectoryStorageLocator` or an in-memory queue directly.

---

## 5. Schema & migrations

- Pass 1 ports `v1_transcripts_table`, `v2_fts_search`, `v4_runtime_guard_marker` **verbatim** from `SQLiteTranscriptStore.swift:177-214`. `v3_jsonl_bootstrap` registers with the migrator (keeps `grdb_migrations` consistent on existing DBs) but its body is a pure `PRAGMA user_version = 3` marker — the JSONL-load-and-insert loop is deleted with the JSONL store. Fresh installs run v3 as a no-op; existing DBs see their already-applied v3 row untouched.
- A characterization test pins the DDL by asserting `sqlite_master.sql` for `transcripts` + `transcripts_fts` + each trigger — byte-identical match. Suggested file: `Tests/PersonalScribeCoreTests/Database/AppDatabaseMigrationTests.swift`, class `AppDatabaseMigrationTests`.
- Each `registerMigration` body is wrapped in do/catch that re-throws as `TranscriptStorageError.migrationFailed(version:, underlying:)` — GRDB's `DatabaseMigrator` does not surface the failed migration name in the thrown error, so the identifier has to be preserved at wrap time.
- Existing `transcripts.sqlite` files already carry `grdb_migrations` (since Phase 3.D), so the new migrator is a no-op on upgrade. Any install with only a `transcripts.jsonl` sidecar (no well-formed SQLite file) gets a fresh empty DB — JSONL is not imported, per the JSONL-nuke locked decision.
- **No new columns or tables in this layer.** Phase 3.B (Notes window — per `PLAN_PHASES.md:371`, covers auto-ingest, manual edit, tagging, FTS search) and Phase 4 (Command Mode / trigger metadata — preview in `plans/backlog/transcript-trigger-context.md`) each land their additive migrations through this migrator, in their own plans. Column names and null/backfill semantics are **not** pre-committed here; `transcript-trigger-context.md` is still marked "for discussion, not approved."

---

## 6. Open questions

None outstanding. All 10 originally-surfaced markers resolved and folded into §3 Locked decisions over two review passes.

---

## 7. Validation

Each bullet is a literal check after the swap lands.

- [ ] `grep -rE 'DatabaseQueue\(|DatabasePool\(' Sources/ | grep -v Sources/PersonalScribeCore/Database/` returns empty.
- [ ] Exactly **one** `AppDatabase(` construction site in production code: `AppComposition`. Verify `grep -rn 'AppDatabase(' Sources/ | grep -v Sources/PersonalScribeCore/Database/` returns one hit in `AppComposition.swift`; every other caller consumes the shared instance.
- [ ] `grep -rn 'transcripts\.sqlite' Sources/ | grep -v Sources/PersonalScribeCore/Database/` returns empty.
- [ ] `Sources/PersonalScribeAppKit/Composition/AppComposition.swift` has no `transcriptDatabaseFileName` constant.
- [ ] `Sources/PersonalScribeAppKit/Composition/PersonalScribeAppMain.swift:303-314` no longer constructs its own `SQLiteTranscriptStore`; it consumes the `AppDatabase` built in `AppComposition`.
- [ ] `Sources/PersonalScribeCore/Metrics/SQLiteMetricsReader.swift` is deleted; `MetricsTranscriptRow` and `executeWriteForTesting` gone with it.
- [ ] `AppComposition.makeMetricsService()` and `AppComposition.makeMetricsReader()` are gone; metrics wiring consumes `AppDatabase` directly.
- [ ] `SQLiteTranscriptStore`, `SQLiteTranscriptReader`, `TranscriptStoreJSONL`, and `FixedBaseDirectoryStorageLocator`-as-legacy-adapter usages are deleted.
- [ ] `grep -rn 'transcripts\.jsonl' Sources/` returns empty — no code reads or writes the sidecar any more.
- [ ] `TranscriptEntry` conforms to `FetchableRecord` + `PersistableRecord` directly. `PersistedTranscriptEntry` and `MetricsTranscriptRow` are both deleted.
- [ ] `Tests/PersonalScribeCoreTests/Database/AppDatabaseMigrationTests.swift` pins `sqlite_master.sql` byte-for-byte for `transcripts`, `transcripts_fts`, and each trigger.

(Health-observable validation — `AppDatabase.storageHealth` stream + Advanced Settings "Database health" row + top-level banner subscriber wiring — belongs to **#043**, not this plan's acceptance gate.)
- [ ] `swift test` green on the main repo path (not a worktree — per project CLAUDE.md).
- [ ] `plans/PLAN_PHASES.md` marks Phase 3.D as absorbed.

---

## Commit style

`storage-layer step N.M: <verb-led subject>`. Test + fix in the same commit.

## Inter-plan coordination

- **Consumes**: Layer 2 `StorageLocator` (unchanged).
- **Coordinates with**: Layer 8 metrics — the metrics-reader boundary closes when this plan lands. Flag a follow-up `[QUESTION]` on `plans/central/LAYER_8_metrics.md` after this plan is approved.
- **Blocks**: Phase 3.B Notes window (consumes `TranscriptRepository`), Phase 4 Command Mode (schema evolution via this migrator).

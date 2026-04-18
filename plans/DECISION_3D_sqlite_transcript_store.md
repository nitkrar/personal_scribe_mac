# Decision 3.D: SQLite Transcript Store

## 1. Constraints and chosen stack

Phase 3 Group 3.D replaces the JSONL-backed `TranscriptStore` with a
SQLite-backed store in `SeshatCore`. The locked choices are:

- Wrapper: `GRDB.swift`, not raw SQLite and not another wrapper.
- SQLite build: the macOS system `libsqlite3`, not a vendored build.
- Encryption: none in this slice. Do not add SQLCipher or an extra link
  step. Keep the design narrow enough that encryption can be retrofitted
  later.
- Full-text search: FTS5 only, with an explicit
  `unicode61 remove_diacritics 2` tokenizer.
- Deployment floor: package baseline remains `.macOS(.v14)`.
- Migration: first-launch cutover from `transcripts.jsonl` must be
  atomic; on failure, JSONL remains authoritative and
  `transcripts.jsonl` stays in place as the rollback artifact.

`SQLiteTranscriptStore` will keep the existing API shape
(`init(recordingsDirectory:ringCapacity:)`, `append(_:)`, `recent(limit:)`,
`count()`) so the call-site swap is small. The `ringCapacity` parameter
becomes a compatibility shim only: SQLite is the authoritative store of
full history, so the in-memory ring and its silent eviction semantics are
removed in this slice.

## 2. Schema

Primary table:

```sql
CREATE TABLE transcripts (
    id TEXT PRIMARY KEY NOT NULL,
    timestamp REAL NOT NULL,
    text TEXT NOT NULL,
    audio_duration REAL NOT NULL,
    processing_duration REAL NOT NULL
);
```

Rationale:

- `id` stores `TranscriptEntry.id` as a UUID string.
- `timestamp` stores `TranscriptEntry.timestamp` as Unix seconds (`REAL`)
  to avoid date-format drift in the DB layer while staying lossless
  enough for app use.
- Durations stay `REAL` because the Swift surface already uses
  `TimeInterval`.

FTS table:

```sql
CREATE VIRTUAL TABLE transcripts_fts USING fts5(
    text,
    content='transcripts',
    content_rowid='rowid',
    tokenize='unicode61 remove_diacritics 2'
);
```

Notes:

- `transcripts.id` remains `TEXT PRIMARY KEY` exactly as required.
  FTS synchronization uses the content table's hidden `rowid`, not the
  text UUID.
- GRDB will build the external-content FTS table with
  `t.synchronize(withTable: "transcripts")`, which emits the required
  insert/delete/update triggers:
  `__transcripts_fts_ai`, `__transcripts_fts_ad`, and
  `__transcripts_fts_au`.

## 3. Migration algorithm

On open, if `transcripts.sqlite` already exists, open it and skip JSONL
migration. Otherwise, if `transcripts.jsonl` exists:

1. Remove any stale `transcripts.sqlite.tmp` left by an interrupted prior
   attempt.
2. Create `transcripts.sqlite.tmp` beside `transcripts.jsonl`.
3. Open the tmp DB through GRDB and run the schema migrator there.
4. In a single write transaction, stream every JSONL line, decode the
   supported legacy/current entry shapes, insert valid rows, and log each
   corrupt line that is skipped.
5. Set the schema marker with `PRAGMA user_version = 1`.
6. Close the tmp DB and atomically rename
   `transcripts.sqlite.tmp` to `transcripts.sqlite`.
7. Leave `transcripts.jsonl` untouched as the rollback artifact.

Failure policy:

- Any failure during tmp DB creation, schema setup, import, guard checks,
  or rename deletes the tmp DB and aborts cutover.
- The session then continues with JSONL as the authoritative store. No
  partial `transcripts.sqlite` is left behind.

## 4. Runtime open-time guards

`SQLiteTranscriptStore` performs these guards when opening the DB:

1. Version floor: `SELECT sqlite_version()` must be `>= 3.38.0`.
   This is comfortably above the `3.27.0` minimum needed for
   `remove_diacritics=2`, while still conservative for macOS 14-era
   system SQLite builds.
2. FTS5 compile option: execute
   `SELECT sqlite_compileoption_used('ENABLE_FTS5')` and fail fast unless
   it returns `1`.
3. Explicit tokenizer: schema creation must use
   `tokenize='unicode61 remove_diacritics 2'`; do not rely on SQLite's
   implicit tokenizer default.
4. Golden corpus smoke test: on open, run a small fixed FTS5 corpus/query
   check using the configured tokenizer to catch behavioral drift across
   macOS point releases.

## 5. Test plan

- Round-trip append to SQLite and fetch via `recent(limit:)`.
- Ring semantics: the ring is removed post-migration; verify that
  `ringCapacity` is compatibility-only and does not evict persisted rows.
- JSONL migration: import a mixed-schema fixture containing one corrupt
  line; valid rows survive, the corrupt line is skipped with a log entry,
  and a second open is a no-op because `transcripts.sqlite` already
  exists.
- FTS5 golden corpus: five transcript fixtures and 4-6 queries covering
  exact token match, prefix search, quoted phrase search,
  diacritic-folded search, and a deliberate non-match.
- Open-time guards: unit tests for version-floor rejection,
  `ENABLE_FTS5` rejection, explicit-tokenizer assertion, and
  golden-corpus failure surfacing.

## 6. Deferred

This slice explicitly defers:

- SQLCipher / encryption at rest.
- Vector / semantic index.
- Pinned or vendored SQLite source builds.
- `NotesWindow` UI work from Group 3.B.

## 7. File-name decision

Choose `transcripts.sqlite`.

Reasoning: this slice is a direct migration from `transcripts.jsonl`, and
the database currently owns transcript history only. Keeping the file name
transcript-specific minimizes migration ambiguity and preserves a clear
rollback story (`transcripts.jsonl` -> `transcripts.sqlite`). Phase 3.B
can still add more tables to the same SQLite file later if the Notes
surface expands beyond transcript rows; if a future slice truly needs a
broader `notes.sqlite` container, that can be an explicit follow-on
migration instead of being smuggled into 3.D.

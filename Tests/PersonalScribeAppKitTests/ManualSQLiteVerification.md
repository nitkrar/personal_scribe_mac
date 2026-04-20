# Manual SQLite Verification

## MV-SQLite-1 First-Launch Migration

1. Start from a clean `transcripts.sqlite` state with an existing `transcripts.jsonl` that contains a known number of valid lines.
2. Launch the app and allow startup to finish.
3. Inspect `<base>/recordings/transcripts.sqlite` and confirm it now exists.
4. Query the SQLite database row count and confirm it matches the number of valid JSONL lines.
5. Confirm `<base>/recordings/transcripts.jsonl` still exists as a rollback artifact.

Expected result: the SQLite database is created on first launch, valid JSONL rows are imported exactly once, and the JSONL file remains on disk.

## MV-SQLite-2 Second-Launch Idempotence

1. With both `transcripts.sqlite` and `transcripts.jsonl` present from MV-SQLite-1, relaunch the app.
2. Re-check the SQLite row count.
3. Confirm the row count is unchanged from the first launch.

Expected result: the second launch does not re-import JSONL data or duplicate rows.

## MV-SQLite-3 Interrupted Migration Rollback

1. Prepare a large enough `transcripts.jsonl` fixture that the first-launch migration takes noticeable time.
2. Launch the app and terminate it during the migration window.
3. Inspect `<base>/recordings/`.
4. Confirm there is no committed `transcripts.sqlite` cutover file containing partial data.
5. Relaunch the app and confirm JSONL remains authoritative until a full migration completes successfully.

Expected result: an interrupted migration never leaves a partial `transcripts.sqlite` as the authoritative store, and a subsequent launch can retry safely.

## MV-SQLite-4 Live FTS Query

1. Launch the app with several known transcript texts that include an exact token, a prefix target, a quoted phrase, and a diacritic example.
2. Run a small live search for each of these queries: exact token, prefix with `*`, quoted phrase, and a diacritic-folded query such as `cafe` against `Café`.
3. Confirm the expected transcript rows are returned and an unrelated query returns no matches.

Expected result: FTS5 search returns the expected rows for exact, prefix, phrase, and diacritic-folded queries.

# Ticket #013 Stage B — Editor + Persist

Editable title and body in the NotesWindow center pane, with debounced writes back to the shared SQLite store. Consumes Stage A's shell/sidebar/view-model scaffolding and prepares the persistent surface that Stages C (search), D (tags), and E (toolbar) extend.

## 1. Goal

After Stage B lands, the user can click into the title field or body text of a selected transcript, edit it, and see the change persist within ~1s of stopping typing — surviving window close/reopen and full app restart. Title auto-derives from the first line of transcript text when the user has never explicitly edited it; a user-edited title sticks thereafter. No format toolbar, tag editing, or search changes are in scope.

## 2. Approach

**Debounce strategy.** Use Combine `.debounce(for: .seconds(0.8), scheduler: DispatchQueue.main)` on the view-model's `$draftTitle` and `$draftBody` publishers, feeding a single `Task { try await save() }` sink. Rationale: the codebase already uses Combine in `TranscriptionsTabViewModel`; `Debouncer`-style timers don't appear in `Sources/` (confirmed via grep — only `GlobalHotkeyMonitor`'s tap-debounce counter, not a reusable debouncer). `DispatchQueue.main` is acceptable for `@MainActor` view-model state — the sink hops into the actor before touching the repo. 0.8s chosen to balance "feels instant on stop-typing" against SQLite write rate under rapid editing.

**Save atomicity.** One row-level `UPDATE transcripts SET title = ?, text = ?, is_user_edited = 1, updated_at = ? WHERE id = ?` per debounce fire. Both fields write together even if only one is dirty — simpler than tracking per-column dirty bits, and SQLite cost is trivial. No optimistic concurrency token: single-window app, no cross-process writers. `is_user_edited` clamps to 1 unconditionally inside the UPDATE so a background auto-ingest path can never flip it back to 0.

**Conflict strategy.** If `#011`'s delete runs against the selected row while the user is mid-edit, the update targets a missing row. Repo method inspects `db.changesCount` after `db.execute`; 0 changes → throw a dedicated `TranscriptUpdateError.notFound` sentinel (wrapped in `TranscriptStorageError.queryFailed(underlying:)` to keep the envelope uniform per `TranscriptRepository` §3 posture). View-model treats that as "selection gone" → clears drafts silently, reloads the list, no user-visible error. A `MetricsNotification.transcriptCommit` post on successful update keeps `HomeTabViewModel` / `MetricsSnapshotStore` observers in sync with the delete path's existing post (`TranscriptRepository.delete` line 82).

**Selection-change semantics.** When the user selects a different row while drafts are dirty, flush pending debounce synchronously (fire the save immediately, `await` it) before loading the new row. Prevents the "I typed, clicked away, came back, my text was gone" failure mode. This is the mockup's implicit contract — users never see a "save" button. Implementation captures the old row's id in the flush closure so a late timer firing can't write to the new selection's id.

## 3. Schema / migration strategy

Add one migration to `TranscriptsMigrator`:

```
registerMigration("v5_notes_editable_fields") { db in
    ALTER TABLE transcripts ADD COLUMN title TEXT;
    ALTER TABLE transcripts ADD COLUMN is_user_edited INTEGER NOT NULL DEFAULT 0;
    ALTER TABLE transcripts ADD COLUMN updated_at REAL;
    PRAGMA user_version = 5;
}
```

Column rationale:
- `title TEXT` (nullable): NULL means "never set explicitly; UI derives from `text`". Nullable — not `NOT NULL DEFAULT ''` — so the view-model can distinguish "auto-derived" from "user typed an empty title on purpose".
- `is_user_edited INTEGER NOT NULL DEFAULT 0`: set to 1 the first time the user commits a title or body edit to a given row. Auto-ingested transcripts keep 0. Gives Stage D/E a cheap filter for "user-curated notes" without scanning `updated_at`.
- `updated_at REAL` (nullable): unix epoch seconds of last write. NULL for pre-Stage-B rows. Used by Stage C for sort-by-modified and by future sync if any.

**Backward compatibility** (`nitkrar/CLAUDE.md`: "APIs must always be backward-compatible — new fields/columns are optional, queries must not fail if a migration hasn't been run"):
- `TranscriptEntry.init(row:)` reads new columns via `row[…] as String?` / `Double?` so if a client somehow opens a v1–v4 database without migrating (e.g. staged binary rollback), decoding still succeeds with `nil`s. The existing `init(row:)` (`TranscriptStore.swift` line 45) uses subscripted reads — extend that pattern, don't switch to `row.decode(...)` which would fail on missing columns.
- `SELECT` queries in `TranscriptRepository.recent / all / search / entries(in:)` add `title, is_user_edited, updated_at` to the projection. Since those are new columns in a newer migration, any DB reaching the repo has already been migrated through `AppDatabase.init` (line 63: `try TranscriptsMigrator.makeMigrator().migrate(dbQueue)`), so in practice the nullable read is belt-and-braces. Still worth doing per the global rule.
- FTS5 virtual table (`v2_fts_search`) currently indexes only `text`. Stage B does NOT add `title` to the FTS index — that's a Stage C concern (search UX will decide whether title should be searched separately or coalesced). Leaving the `transcripts_fts` table shape alone keeps Stage B small and means Stage C doesn't inherit a half-designed FTS update.
- Existing `v1_transcripts_table` DDL stays untouched. `v5` is an additive `ALTER TABLE` migration, matching the pattern set by the already-empty `v3_jsonl_bootstrap` and `v4_runtime_guard_marker` bookmark migrations in `TranscriptsMigrator.swift`.

**`TranscriptEntry` struct changes** (`Sources/PersonalScribeCore/TranscriptStore.swift`):
- Add `let title: String?`, `let isUserEdited: Bool`, `let updatedAt: Date?` with defaults in the memberwise init (`title: nil`, `isUserEdited: false`, `updatedAt: nil`).
- Extend `CodingKeys` (`title`, `isUserEdited = "is_user_edited"`, `updatedAt = "updated_at"`).
- `init(row:)` reads new columns as `row["title"] as String?`, `(row["is_user_edited"] as Int?).map { $0 != 0 } ?? false`, `(row["updated_at"] as Double?).map(Date.init(timeIntervalSince1970:))`.
- `encode(to container:)` writes the inverse.
- `TranscriptEntryRecordTests` gains round-trip cases for all three fields plus one "legacy row shape still decodes" case using raw SQL that only supplies the v1–v4 columns.

## 4. Repository API additions

Extend `TranscriptRepository` with:

```swift
public func update(
    id: UUID,
    title: String?,
    text: String,
    updatedAt: Date
) async throws
```

Behavior:
- One GRDB `database.write` block with a single `UPDATE ... WHERE id = ?`.
- If `db.changesCount == 0`, throw `TranscriptStorageError.queryFailed(underlying: TranscriptUpdateError.notFound)` (new nested error type, or reuse a sentinel `NSError` — decide in review).
- On success: post `MetricsNotification.transcriptCommit`, record `.writeSucceeded` on the operation observer, mirroring `delete(id:)` shape exactly.
- Sets `is_user_edited = 1` unconditionally (every call is a user action; auto-ingest path never calls this method).

**Protocol.** Add a new `TranscriptUpdating` protocol in `Sources/PersonalScribeCore/TranscriptReader.swift` alongside `TranscriptReading` / `TranscriptDeleting`. `TranscriptRepository` conforms. NotesWindow view-model takes `any TranscriptUpdating` (same optional-adapter pattern as `deleter` in `TranscriptionsTabViewModel` line 27–33).

**Thread-safety.** GRDB's `database.write` serializes via the writer queue; concurrent calls from the view-model's debounce sink and an external deleter can't interleave mid-UPDATE. No additional locking needed.

**Does not add:** `fetch(id:)`. The view-model already has the full `TranscriptEntry` from its cached list; a targeted fetch would be noise. If Stage C search proves to need it, that stage adds it.

**Error type sketch.** Add (internal to the repo file, or nested on `TranscriptStorageError`):

```swift
enum TranscriptUpdateError: Error, Sendable { case notFound }
```

Kept distinct from `queryFailed(underlying:)` so the view-model's "silent clear on missing row" branch can key on the nested type without string-matching. Public surface remains `TranscriptStorageError` — `TranscriptUpdateError` is only ever seen as the `underlying:` payload.

## 5. View model design

New `NotesWindowViewModel` (or whatever Stage A names it — consume it; do not rename). Stage B adds:

```swift
@Published var draftTitle: String = ""
@Published var draftBody: String = ""
@Published private(set) var isDirty: Bool = false
@Published private(set) var lastSaveError: TranscriptStorageError?
```

Pipeline:
1. On `selectedEntry` change (published from Stage A): cancel in-flight debounce, flush if dirty, then reset `draftTitle = entry.displayTitle` (new computed: `entry.title ?? Self.autoDerivedTitle(from: entry.text)`) and `draftBody = entry.text`. Set `isDirty = false`.
2. On `$draftTitle` or `$draftBody` change: set `isDirty = true`, feed into a shared debounce publisher.
3. Debounced sink: call `updater.update(id: entry.id, title: draftTitle.isEmpty ? nil : draftTitle, text: draftBody, updatedAt: clock())`. On success, reload the entry from `reader.recent(...)` (to pick up the new row from SQLite's perspective) and set `isDirty = false`. On failure, publish `lastSaveError` — UI shows a subtle footer toast (Stage B can leave that as a `TODO-UI` comment since the mockup doesn't show error chrome).

**Auto-derived title.** Static helper `autoDerivedTitle(from text: String) -> String`:
- Trim whitespace.
- Take up to first 48 chars, cut at last word boundary if available.
- Fallback `"Untitled"` if text is empty.

Behavior is NOT cached in the DB — it's a pure function of `text`. This avoids a "regenerate titles on schema upgrade" path.

**Revert-on-selection-change.** Covered by step 1 above: flush dirty drafts before swapping selection. No explicit revert button; "revert" is just "select the row again after an auto-save" which is a null-op.

## 6. TDD test strategy

### Repo-level (`TranscriptRepositoryTests.swift` — extend existing file)

1. `test_update_persistsTitleAndText` — insert, update, fetch, assert new values.
2. `test_update_setsIsUserEditedFlag` — insert (flag=0), update, assert `is_user_edited == 1` via raw `SELECT`.
3. `test_update_writesUpdatedAt` — assert `updated_at` matches the passed `Date` within 1ms.
4. `test_update_missingId_throwsQueryFailed` — assert specific error case.
5. `test_update_withNilTitle_storesNull` — assert auto-derived-title semantics at the column level.
6. `test_update_postsTranscriptCommitNotification` — observer count check, parity with delete path.
7. `test_update_concurrentWrites_serialize` — fire 10 `update()` tasks via `withTaskGroup`, assert final value is one of them (no partial-row tearing).
8. `test_recent_returnsNewColumns` — assert fetched entry carries `title`, `isUserEdited`, `updatedAt` when present.

### Migration (`AppDatabaseMigrationTests.swift` — extend)

9. `test_v5Migration_addsNotesColumns` — open DB, assert `PRAGMA table_info(transcripts)` lists the three new columns with correct types/nullability.
10. `test_v5Migration_preservesExistingRows` — seed v4 DB with a row, run migrator, assert row still readable with nil title / 0 flag / nil updated_at.
11. `test_v5Migration_userVersionBump` — assert `PRAGMA user_version` returns `5` after migration, matching the v1–v4 bookmark pattern.
12. `test_v5Migration_ftsTableUnchanged` — assert `transcripts_fts` column list and tokenizer config did not change (guard against Stage C accidentally landing via Stage B).

### View-model (`NotesWindowViewModelEditTests.swift` — new file)

Inject a fake clock (`FakeScheduler` from Combine or a `DispatchQueue(label:)` with `VirtualTimeScheduler`-style shim — check what the codebase already provides). Tests:

11. `test_editingTitle_debouncedSaveFires` — set `draftTitle`, advance virtual clock 0.8s, assert updater called once.
12. `test_rapidEdits_debounceCollapsesToOneSave` — 5 edits in 0.5s, advance 0.8s, assert updater called once with final value.
13. `test_selectionChange_flushesDirtyDrafts` — set dirty drafts, change `selectedEntry`, assert updater called synchronously with old-row id.
14. `test_selectionChange_cleanDrafts_noSave` — change selection without editing, assert no save call.
15. `test_autoDerivedTitle_usedWhenTitleNil` — selected entry with `title == nil`, assert `draftTitle == autoDerived(text)`.
16. `test_autoDerivedTitle_firstLineEllided` — multi-line text, assert first-line truncation behavior.
17. `test_updateFailure_setsLastSaveError` — stubbed updater throws, assert `lastSaveError` published.
18. `test_updateSuccess_clearsDirtyFlag` — assert `isDirty` returns to false.
19. `test_selectedEntryDeletedExternally_silentFailure` — updater throws `notFound`; view-model clears drafts, does NOT surface error.

### SwiftUI binding (manual only — `Tests/PersonalScribeAppKitTests/ManualNotesVerification.md`)

Add new section `## Editing title and body` with runbook entries:

- `MV-NOTES-EDIT-01`: Click into title, type, wait 2s, close window, reopen — title persists.
- `MV-NOTES-EDIT-02`: Edit body, quit app (Cmd-Q), relaunch, open History — body persists.
- `MV-NOTES-EDIT-03`: With row A edited and dirty, click row B immediately; click back to A — A's edits are present.
- `MV-NOTES-EDIT-04`: Record a new dictation, open History, confirm auto-derived title matches first words of transcript.
- `MV-NOTES-EDIT-05`: Clear title to empty string, wait 2s, reopen — title re-derives from body (stored as NULL).
- `MV-NOTES-EDIT-06`: Delete a transcript via the sidebar context menu (#011) while its editor fields are dirty — window gracefully clears fields, no crash, no error dialog.

## 7. Commit shape

Tag prefix `#013 step 2.N:`. Proposed sequence:

- `2.1`: migration + schema tests (`TranscriptsMigrator` v5 + `AppDatabaseMigrationTests` cases 9–10)
- `2.2`: `TranscriptEntry` struct gains `title: String?`, `isUserEdited: Bool`, `updatedAt: Date?` + record conformance + `TranscriptEntryRecordTests` updates
- `2.3`: `TranscriptRepository.update` + `TranscriptUpdating` protocol + `TranscriptRepositoryTests` cases 1–8
- `2.4`: `NotesWindowViewModel` editor state + debounce pipeline + view-model tests 11–19
- `2.5`: SwiftUI `TextField`/`TextEditor` bindings into the NotesWindow editor pane (view layer only)
- `2.6`: `ManualNotesVerification.md` entries MV-NOTES-EDIT-01..06

Six commits. Each tagged with the test method names it covers, per project TDD discipline ("reference the test name in the commit message").

## 8. Dependencies on other stages

- **Blocks on Stage A** (shell + sidebar + selection state + view-model skeleton). If Stage A's plan lands a different view-model name or selection-state shape, fold those names into Stage B without drift — surface the divergence, don't silently rename.
- **Coexists with #011 delete** (`slate` agent, in-flight; delete method already merged per commits `bd5ceff / 30b13f3 / 68ece00`). Stage B's `update` method is orthogonal — no shared code paths. The "deleted row becomes un-editable" case is handled in the view-model (test 19). Do not modify `delete` or its tests.
- **Does NOT block Stage C** (FTS search) — Stage B deliberately does not touch `transcripts_fts`.
- **Does NOT block Stage D** (tags) or **Stage E** (toolbar) — independent surfaces, share only the view model they extend.

## 9. Open questions

1. **Auto-derived title formula.** Current proposal: first 48 chars, cut at word boundary, `"Untitled"` fallback. The mockup shows `"Q3 Budget Review"` — that's clearly user-edited. For auto-derived, should we prefer first sentence (split on `. ? !`) over first-N-chars? First-sentence is more human-readable but fails on dictations with no punctuation. **Default proposal:** start with first-N-chars-cut-at-word-boundary; bump to first-sentence later if user reports ugliness. Flag for user.
2. **Selection-change save semantics.** Flush-before-switch (proposed) vs save-in-background-while-switching. Flush is simpler and matches "it saved before I clicked away" user mental model. Background-save risks the user editing row B, then row A's save silently overwriting B because the view-model got confused. **Default proposal:** flush synchronously. Flag for user if they want the async variant.
3. **Edit history / undo beyond NSTextView's built-in.** Stage B gets SwiftUI `TextEditor`'s system undo for free within a session. No custom undo stack, no edit-history table. Is that enough for #013, or should #013 spec include per-note undo across sessions? **Default proposal:** out of scope for all of #013 — split to a separate ticket if desired.

## 10. Scope cuts within Stage B

- Format toolbar (bold/italic/list) — Stage E.
- Tag chip row under the title — Stage D.
- Search integration / FTS index update for `title` — Stage C.
- Right-panel "Related" and "Action Items" content — separate tickets.
- Linked recording audio player — separate ticket (#069 owns audio sidecar lifecycle per `TranscriptRepository.delete` comment line 72).
- Error toast UI for save failures — leave `TODO-UI` comment; error plumbed to `@Published lastSaveError` but no visible affordance.
- Markdown rendering inside the editor — rich-text is a separate design call.
- Conflict resolution between two editor windows — single-window app invariant holds.
- Per-column dirty tracking — row-level write is cheap enough.

## 11. Risks

1. **Swift 6 strict concurrency + Combine debounce.** `.debounce(for: scheduler:)` sinks run off-main; the view-model is `@MainActor`. Must hop via `Task { @MainActor in ... }` before touching actor-isolated state. Pattern exists in the codebase (search for `Task { @MainActor` in `UnifiedWindow/`), but Combine `AnyCancellable` is not `Sendable` — store cancellables on `@MainActor`-isolated properties to keep the checker happy.
2. **GRDB schema change breaking unrelated test suites.** `MetricsSnapshotStore` observes `transcriptCommit` (line 86–92) and may re-query via `TranscriptRepository.count`. Not a schema concern per se, but the `recent/all/search` projection widening to include new columns could break tests that snapshot row column order. Audit `Tests/PersonalScribeCoreTests/Database/` and `Tests/PersonalScribeCoreTests/Metrics/` for such snapshots before 2.2 lands.
3. **`#011` in-flight delete path.** Already merged (commits `bd5ceff / 30b13f3 / 68ece00`). Stage B's `update` must coexist; risk is the integration of "delete mid-edit" showing a transient inconsistent UI. Test 19 + MV-NOTES-EDIT-06 cover it, but that's the one path most likely to surface a weird race at runtime-verify time.
4. **Stage C (FTS) lands after and will want to index `title`.** If we don't design the `v5` migration to be extended cleanly by a later `v6` FTS update, Stage C inherits pain. Mitigation: keep Stage B's migration pure-DDL, no FTS rebuild — Stage C owns that migration outright.
5. **Debounce + selection-change race.** User edits, selects new row, debounce timer fires on the old drafts against the new selection's id. Mitigated by "flush on selection change" synchronously and by capturing the entry id in the debounce closure (not reading `selectedEntry` at save time).
6. **`TranscriptEntry` is `public` and `Codable`.** Adding fields with sensible defaults is source-compatible for Swift callers using the memberwise init explicitly — but any call site using positional init will break. Audit call sites before 2.2. Default parameter values on the new fields mitigate.

# Ticket #013 — NotesWindow · Stage D · Tagging (absorbs #014)

**Parent:** `BACKLOG.md` #013 (NotesWindow) · absorbs #014 (Tags on transcripts/notes) on landing.
**Depends on:** Stage A (sidebar shell), Stage B (editor chip row), Stage C (FTS5 search composition), #011 (repository delete cascade).
**Downstream:** none — Stage D is terminal for #013 tagging scope.
**Date:** 2026-04-22

---

## 1. Goal

After Stage D lands, the user can DO the following inside NotesWindow:

- See a **TAGS** section in the left sidebar showing every tag that exists in the database, rendered as pills. Mockup canon: `meeting`, `action-item`, `idea` (`plans/seshat_agent_bundle/03_Surfaces/NotesWindow/notes_surface.png`).
- **Click a tag pill** to filter the RECENT list to notes carrying that tag. The filter AND-composes with Stage C's `searchQuery` — a user typing "roadmap" after clicking `meeting` sees only `meeting`-tagged notes whose body matches `roadmap`.
- **⌘-click a tag pill** to toggle it into a multi-tag selection. Multi-select defaults to AND (match-all), per the mockup's single-pill-at-a-time visual but with keyboard power-use on top.
- In the **editor's status-chip row**, see a tag chip (mockup: `meeting` inline next to `Auto-transcribed` and the timestamp) plus a `+` button for adding tags.
- **Add a tag** via the `+` popover: text field with inline autocomplete against existing tags. Enter commits; a new name creates a new tag.
- **Remove a tag** from the active note via an `x` affordance on the chip (hover-revealed) or right-click → "Remove tag".
- **Rename or delete a tag globally** via right-click context menu on a sidebar pill. Rename updates every note atomically; global delete removes the tag from every note (note bodies and transcripts survive).

Tags are content-agnostic labels applied to the single `transcripts` table (= notes; policy `project_phase3_notes_equals_history`). No separate `note_type` column. No LLM auto-tagging (that's Phase 4, #020).

---

## 2. Schema choice — junction table, not TEXT column

**Decision: `tags` + `transcript_tags` junction tables.** Reject the comma-separated TEXT column approach.

Justification:

- **Global rename is one UPDATE.** With a junction, `UPDATE tags SET name = ? WHERE id = ?` propagates to every tagged note. With a TEXT column we'd string-split and rewrite every row (racy, slow, whitespace-fragile).
- **Global delete is one DELETE.** With a junction + `ON DELETE CASCADE`, `DELETE FROM tags WHERE id = ?` removes every junction row. TEXT column needs per-row string surgery.
- **Filter-by-tag is an index seek.** `WHERE tag_id = ?` hits a B-tree index. TEXT column needs `LIKE '%tag%'` which is O(rows) and false-positive prone (`"action"` matches `"action-item"`).
- **Multi-tag AND-composition is straightforward JOIN logic** (§5). TEXT column AND-matching needs LIKE stacking with even worse selectivity.
- **Usage count for sidebar sort** is `COUNT(*) GROUP BY tag_id` on the junction. On TEXT it requires tokenizing every row.
- **GRDB ergonomics:** a `Tag` record with `FetchableRecord` + `PersistableRecord` mirrors the existing `TranscriptEntry` pattern. TEXT-column tokenization would leak string-splitting into the repository layer.

The junction is marginally more migration work (one extra `CREATE TABLE` and one index). The ongoing API and maintenance savings dominate.

### DDL sketch (migration `v5_tags_tables`)

```sql
CREATE TABLE tags (
    id TEXT PRIMARY KEY NOT NULL,          -- UUID
    name TEXT NOT NULL UNIQUE COLLATE NOCASE,
    created_at REAL NOT NULL                -- epoch seconds, matches transcripts.timestamp style
);

CREATE INDEX idx_tags_name ON tags(name COLLATE NOCASE);

CREATE TABLE transcript_tags (
    transcript_id TEXT NOT NULL
        REFERENCES transcripts(id) ON DELETE CASCADE,
    tag_id TEXT NOT NULL
        REFERENCES tags(id) ON DELETE CASCADE,
    created_at REAL NOT NULL,
    PRIMARY KEY (transcript_id, tag_id)
);

CREATE INDEX idx_transcript_tags_tag ON transcript_tags(tag_id);
CREATE INDEX idx_transcript_tags_transcript ON transcript_tags(transcript_id);

PRAGMA user_version = 5;
```

### Cascade semantics (collision with #011)

- `ON DELETE CASCADE` on `transcript_tags.transcript_id` — when #011 deletes a transcript row (via `TranscriptRepository.delete(id:)`), every junction row referencing it vanishes in the same implicit transaction. No app code change needed in the delete path; the FK carries the contract.
- `ON DELETE CASCADE` on `transcript_tags.tag_id` — global tag delete clears junctions automatically.
- **GRDB note:** `foreign_keys` PRAGMA must be ON for CASCADE to fire. GRDB enables it by default via `Configuration.foreignKeysEnabled`; add an assertion at migration time (`try db.execute("PRAGMA foreign_keys = ON")`) as belt-and-braces.

### Case sensitivity

`COLLATE NOCASE` on `tags.name` + the unique index means `Meeting`, `meeting`, `MEETING` collapse to one row. Autocomplete (§4) matches case-insensitively. Storage preserves whatever casing the user first typed (cosmetic); lookup is case-insensitive.

---

## 3. Migration plan

**Next migration number:** `v5_tags_tables`. Current chain in `TranscriptsMigrator.swift` ends at `v4_runtime_guard_marker` (verified: `Sources/PersonalScribeCore/Database/Migrations/TranscriptsMigrator.swift:58`).

Migration body:

1. `CREATE TABLE tags` (DDL above).
2. `CREATE TABLE transcript_tags` (DDL above).
3. `CREATE INDEX` × 3 (name, tag_id, transcript_id).
4. `PRAGMA user_version = 5`.

Wrapped in `wrapMigration(version:"v5_tags_tables")` so failures surface as `TranscriptStorageError.migrationFailed(version: "v5_tags_tables", underlying: error)` — identical error envelope to v1/v2/v4.

### Backward-compat rule (from `nitkrar/CLAUDE.md`)

- New tables only; no changes to the `transcripts` shape. Every existing query on `transcripts` keeps working untouched.
- Repository reads that pre-date Stage D (e.g. `recent(limit:)`, `search(query:)`) MUST NOT JOIN on the new tables implicitly. New tag-aware methods are **additive**: `transcripts(withTag:)`, `transcripts(withTags:matchAll:)` (§4). A caller on an un-migrated DB is not a supported state post-Stage D, but the old method signatures keep the same SQL.
- Pre-dogfood solo (memory `feedback_pre_dogfood_no_legacy_users`) — no data back-fill needed. Junction starts empty; autocomplete list is empty until the user tags a note.

---

## 4. Repository API

New type `TagRepository` in `Sources/PersonalScribeCore/Database/TagRepository.swift`, same shape as `TranscriptRepository` (§Pass-1 envelope: writes throw, reads log-and-empty).

```swift
public struct Tag: Codable, Sendable, Equatable, Hashable {
    public let id: UUID
    public let name: String
    public let createdAt: Date
}

public struct TagUsage: Sendable, Equatable {
    public let tag: Tag
    public let count: Int
}

public struct TagRepository: Sendable {
    public init(database: AppDatabase, ...)

    // MARK: - Tag CRUD

    /// Create-or-fetch by case-insensitive name. Returns the existing tag
    /// if `name` already exists (idempotent for autocomplete-commit path).
    public func upsert(name: String) async throws -> Tag

    /// Rename in place. Throws if `newName` collides with a different tag.
    public func rename(id: UUID, to newName: String) async throws

    /// Delete the tag row; `ON DELETE CASCADE` clears every junction row.
    public func deleteGlobally(id: UUID) async throws

    /// All tags, sorted by usage count DESC then name ASC. Non-throwing.
    public func listAllWithUsage() async -> [TagUsage]

    // MARK: - Transcript ↔ Tag junction

    /// Idempotent: repeated calls with the same pair are no-ops (PK dedupe).
    public func addTag(tagID: UUID, to transcriptID: UUID) async throws

    /// Idempotent: missing pair is a no-op.
    public func removeTag(tagID: UUID, from transcriptID: UUID) async throws

    /// Tags attached to a single transcript, ordered by created_at.
    public func tags(for transcriptID: UUID) async -> [Tag]
}
```

### TranscriptRepository extension

New tag-aware read methods on `TranscriptRepository` (co-located because they return `TranscriptEntry`):

```swift
extension TranscriptRepository {
    /// Transcripts carrying `tagID`, newest first. Non-throwing.
    public func transcripts(withTag tagID: UUID) async -> [TranscriptEntry]

    /// Transcripts carrying tags.
    /// * `matchAll == true`  → AND (must carry every id in `tagIDs`).
    /// * `matchAll == false` → OR (carries any id in `tagIDs`).
    /// Empty `tagIDs` → empty result (do not silently drop the filter).
    public func transcripts(withTags tagIDs: [UUID], matchAll: Bool) async -> [TranscriptEntry]
}
```

### Error shapes

Writes throw `TranscriptStorageError.queryFailed(underlying:)` — same envelope as existing write path. Two new cases added to `TranscriptStorageError`:

```swift
case tagNameConflict(name: String)          // upsert/rename hit UNIQUE violation on a different row
case tagNameInvalid(reason: String)         // empty, whitespace-only, too long, reserved char
```

Reads: log + empty. No banner by policy (`#043` owns read-failure surfacing; Stage D does not expand that surface).

### Name validation

- Trim leading/trailing whitespace before persistence.
- Reject empty after trim → `tagNameInvalid(reason: "empty")`.
- Reject names containing newlines or NUL → `tagNameInvalid(reason: "illegal character")`.
- Soft cap 64 chars (display-space bound; not a schema constraint, reject in validator).
- Case-insensitive collision → `tagNameConflict(name:)`.

---

## 5. Search composition with Stage C

Stage C supplies `NotesSidebarViewModel.searchQuery` + the FTS5 query path (`TranscriptRepository.search(query:)`). Stage D adds `selectedTagIDs: Set<UUID>` and `tagMatchAll: Bool` to the same view-model.

**Decision: SQL push-down via JOIN, not post-hoc Swift-side ID intersection.**

Justification:

- Intersection in Swift requires materializing both result sets — `search(query:)` returns every FTS hit; `transcripts(withTag:)` returns every tagged row. On a dogfood DB with 10k entries and a common tag, both sets could each be multi-thousand rows. Intersecting in Swift wastes allocations and loses the DB's query planner.
- JOIN push-down is one SQL statement and the planner picks the right index (FTS rowid join + junction tag_id index).
- AND vs OR multi-tag is trivially expressible in SQL (`INTERSECT` / `IN`).

### Composed query shapes

**Text-only (Stage C unchanged):** existing `search(query:)` SQL.

**Tags-only (Stage D new):** `transcripts(withTags:matchAll:)`.

- AND: `SELECT * FROM transcripts WHERE id IN (SELECT transcript_id FROM transcript_tags WHERE tag_id IN (?,?,…) GROUP BY transcript_id HAVING COUNT(DISTINCT tag_id) = ?) ORDER BY timestamp DESC`
- OR: `SELECT * FROM transcripts WHERE id IN (SELECT DISTINCT transcript_id FROM transcript_tags WHERE tag_id IN (?,?,…)) ORDER BY timestamp DESC`

**Text + Tags (Stage D new, replaces the two individual queries when both are active):**

New method `TranscriptRepository.search(query:tagIDs:matchAll:) async -> [TranscriptEntry]` that composes FTS5 MATCH with the `IN` subquery:

```sql
SELECT transcripts.id, transcripts.timestamp, transcripts.text,
       transcripts.audio_duration, transcripts.processing_duration
FROM transcripts
JOIN transcripts_fts ON transcripts_fts.rowid = transcripts.rowid
WHERE transcripts_fts MATCH ?
  AND transcripts.id IN (
    SELECT transcript_id FROM transcript_tags
    WHERE tag_id IN (?, ?, …)
    GROUP BY transcript_id
    HAVING COUNT(DISTINCT tag_id) = ?   -- AND mode
  )
ORDER BY transcripts.timestamp DESC
```

OR mode drops the `HAVING` clause and the `DISTINCT` in `GROUP BY`.

The view-model dispatches to one of three repository methods based on `(searchQuery.isEmpty, selectedTagIDs.isEmpty)`:

| searchQuery | selectedTagIDs | Call |
|---|---|---|
| empty | empty | `recent(limit:)` (unchanged from today) |
| non-empty | empty | `search(query:)` (Stage C) |
| empty | non-empty | `transcripts(withTags:matchAll:)` |
| non-empty | non-empty | `search(query:tagIDs:matchAll:)` (new composed) |

No ID-set intersection in Swift. No stale-result races from two async reads finishing out of order.

---

## 6. UI surfaces

### (a) Sidebar TAGS section

- Position: directly below RECENT, above the "+ New Note" footer (mockup canon).
- Header: static text `TAGS`, same typography as `RECENT` (Typography.caption, secondary text).
- Content: flow-layout of tag pills, one pill per row in the mockup but wrap-to-next-line if the sidebar is narrow.
- **Sort order:** usage count DESC, ties broken by name ASC. Matches "most-used surfaces first" intuition; alphabetical is a worse default when there are 30+ tags.
- **Empty state:** section is hidden entirely when `listAllWithUsage()` returns empty. No "no tags yet" placeholder — the `+` flow in the editor is the on-ramp.
- **Selection state:** selected pill uses brand accent fill (`Palette.brandChampagne.opacity(…)`); unselected uses the muted pill style already in the design system.
- **Click:** single-select replace. Sets `selectedTagIDs = [tag.id]`.
- **⌘-click:** toggles the tag in/out of `selectedTagIDs`. Multi-select defaults to match-all (`tagMatchAll = true`); a future affordance (not Stage D) could expose AND/OR toggle.
- **Right-click menu:** `Rename tag…` → inline text-field overlay; `Delete tag…` → confirmation sheet ("Remove `meeting` from 12 notes? Notes are kept."). Both actions go through `TagRepository.rename` / `deleteGlobally`.
- **Clear filter:** clicking the already-selected pill removes it from the selection (single-click acts as toggle for that pill).

### (b) Editor status-chip row

Existing row (Stage B owns its baseline) shows `Auto-transcribed`, wall-clock timestamp, and sub-title elements. Stage D appends:

- Zero or more **tag chips** rendered with the same pill visual as the sidebar (slightly smaller if needed for line-height parity).
- A trailing **`+` button** (circle outline) that presents a popover on click.

**Add-tag popover:**

- 240pt-wide SwiftUI popover, arrow anchored to `+`.
- `TextField` with placeholder `"Add tag…"`, autofocus on present.
- Inline filtered list (max 6 rows) of existing tags whose `name` case-insensitively contains the current text.
- Keyboard: arrow keys move the highlight; Return commits the highlighted row or creates a new tag if the text matches nothing.
- On commit: dispatch to `TagRepository.upsert(name:)` → `addTag(tagID:to:)` against the active transcript. Popover dismisses, chip appears.

**Remove-tag:**

- Chip shows an `x` on hover (mirrors the delete-on-hover pattern already used in `TranscriptRow` detail style, `TranscriptRow.swift:220-226`).
- Right-click menu on the chip: `Remove tag` as primary item. No "rename from here" — rename is sidebar-only to keep the editor chip row focused on the current note.
- Dispatches to `TagRepository.removeTag(tagID:from:)`.

### (c) Chip component reuse

Grep confirms `TranscriptRow.swift` is the only status-chip rendering today, and it renders plain `Text` labels inside the row, not reusable chips. There is **no existing `Chip` SwiftUI type** in `Sources/PersonalScribeAppKit/`. Stage D builds one: `TagChip` in `Sources/PersonalScribeAppKit/Components/TagChip.swift`, driven by:

```swift
struct TagChip: View {
    let name: String
    let isSelected: Bool
    let onTap: () -> Void
    let onRemove: (() -> Void)?   // hover-x; nil = sidebar pill variant
    // body: RoundedRectangle fill + Text + conditional × button
}
```

Both sidebar pills and editor chips render via `TagChip` with different `isSelected`/`onRemove` wiring — no duplicate visual code paths.

---

## 7. TDD test strategy

### Repository tests (`Tests/PersonalScribeCoreTests/TagRepositoryTests.swift`)

One XCTestCase class per concern so filter-runs are cheap (`--filter TagRepository…` per `feedback_filtered_tests`).

- `TagRepositoryCRUDTests`
  - `test_upsert_createsNewTag_whenNameIsUnique`
  - `test_upsert_returnsExistingTag_whenNameMatchesCaseInsensitively`
  - `test_upsert_trimsWhitespace`
  - `test_upsert_throwsTagNameInvalid_onEmptyAfterTrim`
  - `test_upsert_throwsTagNameInvalid_onNewlineInName`
  - `test_rename_updatesName_andReflectsInAllTranscripts`
  - `test_rename_throwsTagNameConflict_whenTargetExists`
  - `test_deleteGlobally_removesFromAllTranscripts` (prove by querying junction count pre/post)
  - `test_deleteGlobally_leavesTranscriptRowsIntact`
  - `test_listAllWithUsage_sortsByUsageCountDescendingThenNameAscending`
- `TagJunctionTests`
  - `test_addTag_isIdempotent`
  - `test_addTag_createsPairingWhenBothExist`
  - `test_removeTag_isIdempotent`
  - `test_tagsFor_transcriptOrdersByCreatedAt`
- `TranscriptRepositoryTagFilterTests`
  - `test_transcriptsWithTag_returnsOnlyTagged`
  - `test_transcriptsWithTags_matchAll_returnsIntersection`
  - `test_transcriptsWithTags_matchAny_returnsUnion`
  - `test_transcriptsWithTags_emptyIDs_returnsEmpty`
  - `test_search_withTags_andComposesFTSAndTagFilter_matchAll`
  - `test_search_withTags_andComposesFTSAndTagFilter_matchAny`
- `TranscriptDeleteCascadesToTagsTests`
  - `test_deleteTranscript_cascadesJunctionRows` (covers #011 collision; inserts transcript + 2 tags + 2 junction rows; calls `TranscriptRepository.delete`; asserts `transcript_tags` count drops by 2 and tags themselves persist).

### Migration tests (`Tests/PersonalScribeCoreTests/TagsMigrationTests.swift`)

- `test_migrate_v4_to_v5_createsTagsAndJunctionTables`
- `test_migrate_v5_tagsTable_hasUniqueCaseInsensitiveIndexOnName`
- `test_migrate_v5_junctionForeignKeysEnforceCascade`
- `test_migrate_v5_userVersionIs5`

### View-model tests (`Tests/PersonalScribeAppKitTests/NotesSidebarTagFilterTests.swift`, `Tests/PersonalScribeAppKitTests/NotesEditorTagChipsTests.swift`)

- Sidebar pill selection:
  - `test_clickTagPill_setsSelectedTagIDsToSingletonSet`
  - `test_cmdClickTagPill_togglesMembership`
  - `test_clickSelectedPill_clearsSelection`
- Search composition:
  - `test_selectedTagsAndSearchQuery_dispatchesToComposedSearchMethod`
  - `test_emptyTagsAndEmptyQuery_dispatchesToRecent`
- Editor chips:
  - `test_addTagFromPopover_callsUpsertAndAddTag`
  - `test_removeTagFromChip_callsRemoveTag`
  - `test_popoverAutocomplete_filtersByCaseInsensitiveContains`
  - `test_popoverAutocomplete_newNameAtTopWhenNoExactMatch`
- `TagChip` render:
  - `test_tagChip_showsRemoveButton_onlyWhenOnRemoveProvided`

### Manual verification entries (runbook `Tests/PersonalScribeAppKitTests/ManualNotesTagsVerification.md`)

- `MV-NOTES-TAGS-001`: sidebar TAGS section visually matches mockup with 3 tags present.
- `MV-NOTES-TAGS-002`: clicking `meeting` pill filters RECENT; selected pill reads as active.
- `MV-NOTES-TAGS-003`: ⌘-clicking `action-item` while `meeting` is selected shows AND-composed results.
- `MV-NOTES-TAGS-004`: editor `+` popover presents, autocomplete matches typed text, Enter commits.
- `MV-NOTES-TAGS-005`: right-click sidebar pill → Rename updates the chip in the open note without closing it.
- `MV-NOTES-TAGS-006`: right-click sidebar pill → Delete removes the chip from every open note in the session.
- `MV-NOTES-TAGS-007`: deleting a transcript via #011 trash removes its tag associations (sidebar usage counts update).

---

## 8. Commit shape

Target 6 commits under `#013 step 4.N:` (4 = Stage D index in #013; N = sub-step).

1. `#013 step 4.1:` — migration v5 + `Tag` / `TagUsage` records + `TagRepository` CRUD + migration tests + CRUD tests. (Schema + records foundation.)
2. `#013 step 4.2:` — `TagRepository` junction methods + `TranscriptRepository.transcripts(withTag:)` + `transcripts(withTags:matchAll:)` + filter + cascade tests.
3. `#013 step 4.3:` — `TranscriptRepository.search(query:tagIDs:matchAll:)` composed query + composition tests.
4. `#013 step 4.4:` — `TagChip` component + rendering tests.
5. `#013 step 4.5:` — `NotesSidebarViewModel` tag-selection state + view-model tests + sidebar TAGS section SwiftUI wiring.
6. `#013 step 4.6:` — editor chip row integration + add-tag popover + view-model tests + right-click rename/delete menus + manual-verify runbook entries.

Rename #014 to closed + BACKLOG pointer update lands as part of commit 4.6 (not a separate commit — #014 closeout is tightly coupled to Stage D landing).

---

## 9. Dependencies on other stages

| Stage | What Stage D consumes |
|---|---|
| A (sidebar shell) | `NotesSidebar` container view with RECENT section + "+ New Note" footer; Stage D inserts the TAGS section between them. |
| B (editor chip row) | Status-chip HStack shell in the editor pane; Stage D appends tag chips + `+` button into the same row. |
| C (FTS5 search) | `NotesSidebarViewModel.searchQuery` published property + the existing `TranscriptRepository.search(query:)` call path. Stage D extends, not replaces. |
| #011 (repo delete) | `TranscriptRepository.delete(id:)` already in place on trunk; Stage D adds only the FK CASCADE on the migration — no delete-path code change. |

If Stage A/B/C land without Stage D, the sidebar simply lacks a TAGS section and the editor lacks tag chips. No schema drift, no broken state.

---

## 10. Open questions

1. **Max tags per note** — hard cap, soft nudge, or unlimited? Suggest **unlimited** (let the user discover what feels right) with a soft UI warning if count > 10 to avoid chip-row wrap explosions. DECIDE before 4.6.
2. **Tag sort order in sidebar** — locked to usage-DESC-then-name-ASC by §6(a). Revisit if dogfood shows "popular tag churn" (same tag bouncing between position 1 and 3 feels noisy) — fallback is pure alphabetical.
3. **Zero-note tags** — when the last note carrying a tag is deleted, auto-GC the tag row or keep it? Suggest **keep** (the user may re-tag into it later; autocomplete still surfaces it). Sidebar pill for a zero-usage tag is visually allowed (count suffix `(0)` optional). DECIDE before 4.5.
4. **Reserved tag names** — do we reserve `meeting`, `action-item`, `idea` as system seeds? Suggest **no** (they're mockup illustrations only; if the user types them, they're normal tags). Keeps the schema empty until the user acts.
5. **Tag chip color** — flat accent per §(Scope cuts) is the locked default, but the mockup uses a single brand accent for all pills. Confirm no per-tag color is acceptable. (Answer is expected-yes given scope cuts.)

---

## 11. Scope cuts within Stage D

- **No auto-tag suggestion** from transcript content — Phase 4 (`#020` intent classification).
- **No per-tag color / icon** — mockup is flat; keep the visual system simple.
- **No hierarchical / nested tags** (`meeting/weekly/planning`) — not in mockup, not in #014.
- **No drag-to-reorder sidebar pills** — sort is data-driven (usage DESC); manual reorder is a different UX contract.
- **No tag-aware export** — export surfaces are downstream (#022 / Phase 4 "Related"); Stage D writes to SQLite only.
- **No UI for AND/OR toggle on multi-select** — default AND only. Power-user OR mode is a backlog idea if anyone asks.
- **No "untagged" pseudo-filter pill** — can add later if dogfood demands; not in mockup.
- **No keyboard shortcut to add tag from editor** (`⌘T` etc.) — `+` button is the only entry point in Stage D.

---

## 12. Risks

- **SwiftUI `Chip` component does not exist** — confirmed by grep; Stage D builds `TagChip` in 4.4. Low risk (small component, pure render). Mitigation: land 4.4 before 4.5/4.6 so both callers use the same type.
- **FTS5 + tag JOIN performance** — composed `search(query:tagIDs:matchAll:)` on a pathological DB (50k transcripts, 200 tags) is untested. Mitigation: benchmark tests in 4.3 against a 10k-row fixture; accept up to 50ms on a MacBook as the bar. If it exceeds, fall back to query-plan inspection and add covering indexes.
- **Foreign-key CASCADE requires PRAGMA foreign_keys=ON** — GRDB enables by default, but any future config-change that disables it breaks the #011 collision contract. Mitigation: assertion in `AppDatabase` init + migration test `test_migrate_v5_junctionForeignKeysEnforceCascade` that explicitly checks cascade behavior, not just the DDL.
- **Autocomplete popover racing against background tag-writes** — two back-to-back `+` adds could race. Mitigation: popover is single-instance (tied to editor's focused note); `upsert` is idempotent so worst case is "tag already existed, returns existing" — no duplicate row.
- **No legacy user migration risk** — project is pre-dogfood solo (memory `feedback_pre_dogfood_no_legacy_users`: "don't flag JSONL/SQLite/preference wire-format changes as risky 'because existing users'"). On-disk state is disposable; running a fresh migration on a dev box is the happy path.
- **Stage A/B/C not yet landed** — Stage D consumes published properties that don't exist yet. Mitigation: commit 4.1–4.3 are repo/storage only (no UI dependency); 4.4 is a leaf component (no dependency); 4.5/4.6 require A/B/C on trunk before they land. Gate 4.5 on A being on trunk.

---

## 13. Ticket #014 closeout

When Stage D (commit 4.6) lands on trunk:

- Update `BACKLOG.md` #014 block:
  - Status `open` → `done`.
  - Append: `**Landed as:** #013 Stage D. See plans/013_notes_window/stage_D_tagging.md.`
  - Move #014 to the closed section of BACKLOG (or apply whatever conventions the `feedback_backlog_row_ownership` and BACKLOG structure rules require at closeout time).
- The BACKLOG edit is the user's to do or explicitly request — per `feedback_backlog_not_in_commits`, Stage D commits do NOT stage `./BACKLOG.md`. Closeout is a separate, user-initiated step.
- #014's "schema choice" open question is answered here in §2; no loose ends remain after Stage D.

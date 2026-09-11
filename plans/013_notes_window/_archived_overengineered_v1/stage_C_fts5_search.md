# #013 NotesWindow — Stage C: FTS5 Search

## 1. Goal

Wire the new NotesWindow sidebar search field (built in Stage A) to a debounced FTS5-backed query so the RECENT list filters as the user types. After Stage C lands the user can:

- Type into the sidebar search field; after ~200 ms of quiet the list narrows to rows whose `text` matches the query.
- Use multi-word AND (`budget review` matches rows with BOTH terms), quoted phrases (`"budget review"` exact phrase), and prefix matching (`bud*` matches `budget`, `buddy`).
- Clear the field to return to the unfiltered RECENT list.
- See results ordered by FTS5 rank with `timestamp DESC` tiebreaker so two equally-ranked hits show newest-first.

Not in Stage C: tag-scoped search (Stage D composes on this query shape), snippet rendering, semantic / embedding search (Phase 4 via #022).

## 2. Prior art check — FTS5 is already live

Grep confirms #026 (storage layer) shipped the FTS5 infrastructure. **Stage C adds zero DDL.** The observable surface the brief anticipated (`a5a841a` + `91ea8fa`) turned out to be the `DatabaseOperationStatus` observer for #043, not an FTS5 observer — but it already emits `.readSucceeded` / `.readFailed` for every `search(query:)` call, which Stage C inherits for free.

What is in the tree today:

- Virtual table created in `Sources/PersonalScribeCore/Database/Migrations/TranscriptsMigrator.swift:38-47` under migration key `v2_fts_search`. DDL: `CREATE VIRTUAL TABLE "transcripts_fts" USING fts5(text, tokenize='''unicode61'' ''remove_diacritics'' ''2''', content='transcripts')`.
- External-content mode (`content='transcripts'`) — FTS5 stores no duplicate text, just the inverted index. Authoritative text lives in `transcripts.text`; the FTS table is a projection.
- GRDB auto-generated AD / AI / AU triggers (verified verbatim in `Tests/PersonalScribeCoreTests/Database/AppDatabaseSchemaEquivalenceTests.swift:64-78`) keep the index in sync on INSERT / UPDATE / DELETE against `transcripts`. `slate`'s #011 delete path uses `DELETE FROM transcripts WHERE id = ?` at `TranscriptRepository.swift:74-91`; the `__transcripts_fts_ad` trigger fires automatically — no Stage C change required.
- `TranscriptReading.search(query:) async -> [TranscriptEntry]` declared at `Sources/PersonalScribeCore/TranscriptReader.swift:5`, implemented at `Sources/PersonalScribeCore/Database/TranscriptRepository.swift:149-187`, including `db.makeFTS5Pattern(rawPattern:forTable:)` input sanitization (shields against `"""` / lone `*`).
- Repo happy-path tests already exist at `Tests/PersonalScribeCoreTests/Database/TranscriptRepositoryTests.swift:173-202` (`test_search_findsFTSMatches`, `test_search_emptyQuery_returnsEmpty`), plus the induced-failure case at `Tests/PersonalScribeCoreTests/Database/DatabaseOperationStatusTests.swift:55-74` which forces the catch branch with `"""`.

What is missing:

- No NotesWindow view-model consumes `search(query:)`. The legacy `TranscriptionsTabViewModel.filteredEntries` at `Sources/PersonalScribeAppKit/UnifiedWindow/Tabs/TranscriptionsTabViewModel.swift:72-80` does in-memory case-insensitive `.contains(lowercased())` — Stage C does not touch it.
- No debounce layer on any `searchQuery: String` Published property.
- No rank ordering — the existing `search` orders by `transcripts.timestamp DESC` only, ignoring FTS5 rank. Stage C needs a second call shape ordered by `bm25(transcripts_fts), timestamp DESC`.
- No pagination cap on `search(query:)`. Stage C adds a `limit:` overload so the sidebar never has to paginate itself.

What Stage C adds: (1) a `search(query:limit:)` overload on `TranscriptReading` ordered by BM25 then timestamp, (2) a `NotesSidebarSearchModel` Combine debounce wrapper, (3) wiring from Stage A's sidebar `TextField` through the debounce into the RECENT list binding, (4) tests per §7.

## 3. Approach

**Index strategy.** Keep the existing external-content FTS5 table (`content='transcripts'`). Do not switch to a content-less or own-content table — the storage-layer review committed to "FTS as projection" and Stage B's editor will write into `transcripts.text`, not a parallel FTS column. Keep `synchronize(withTable: "transcripts")` as the trigger source. The AD trigger already covers `slate`'s delete path. Stage B may introduce a `title` column; that's indexed separately in a follow-up, flagged in §12.

**Query shape.** Sidebar input is a `@Published searchQuery: String` on the Stage A sidebar view model (produced by Stage A; assumed name `NotesSidebarViewModel`). Stage C introduces `NotesSidebarSearchModel` (Combine) which observes `$searchQuery`, applies `.debounce(for: .milliseconds(200), scheduler: DispatchQueue.main)` + `.removeDuplicates()`, trims whitespace, and emits either `reader.recent(limit: 100)` (empty after trim) or `reader.search(query: trimmed, limit: 100)` (non-empty). The debounce runs on main; the downstream `await reader.search(...)` hops to whatever actor the repository's `database.read { ... }` requires. Cancellation: each debounce tick spawns a `Task` and stores its handle; the next tick cancels the previous task so a slow in-flight query can't overwrite a newer result (last-write-wins).

**Triggers.** Nothing to do — `synchronize(withTable:)` emits the three triggers verbatim. Flag to Stage B: do your editor save as `UPDATE transcripts SET text = ? WHERE id = ?`, not DELETE-then-INSERT, or you'll churn rowids and break FTS rank history.

**Debounce window.** 200 ms. 150 ms is edgy on slow typists mid-word; 300 ms feels laggy. 200 ms matches Spotlight / Safari smart field. Open question §10.

## 4. Schema / migration

**No new migration.** Confirmed against `TranscriptsMigrator.swift:38-47`:

```swift
migrator.registerMigration("v2_fts_search") { db in
    try db.create(virtualTable: "transcripts_fts", using: FTS5()) { table in
        table.synchronize(withTable: "transcripts")
        table.tokenizer = .unicode61(diacritics: .remove)
        table.column("text")
    }
    try db.execute(sql: "PRAGMA user_version = 2")
}
```

Latest registered version is `v4_runtime_guard_marker`. Stage C registers no `v5_*` migration (no columns, no indices, no triggers). If open question §10(d) resolves to "switch tokenizer", that becomes a follow-up ticket.

## 5. Repository API

Existing protocol (unchanged, see `Sources/PersonalScribeCore/TranscriptReader.swift`):

```swift
public protocol TranscriptReading: Sendable {
    func recent(limit: Int) async -> [TranscriptEntry]
    func search(query: String) async -> [TranscriptEntry]
    func all() async -> [TranscriptEntry]
}
```

Stage C keeps the existing `search(query:)` untouched so the two extant tests keep passing and the legacy Transcriptions tab can migrate later. Stage C addition — ranked + limited overload:

```swift
func search(query: String, limit: Int) async -> [TranscriptEntry]  // NEW
```

Semantics: trim whitespace, return `[]` if empty (matches existing), guard `limit <= 0 → []` (matches `recent`'s guard at lines 98-101). SQL sketch:

```sql
SELECT transcripts.id, transcripts.timestamp, transcripts.text,
       transcripts.audio_duration, transcripts.processing_duration
  FROM transcripts
  JOIN transcripts_fts ON transcripts_fts.rowid = transcripts.rowid
  WHERE transcripts_fts MATCH ?
  ORDER BY bm25(transcripts_fts), transcripts.timestamp DESC
  LIMIT ?
```

Return shape: `[TranscriptEntry]` — same as existing `search`. No snippets, no highlight ranges. Rank is used for ordering only; callers do not see a score. Pagination is out of scope; the sidebar caps at 100.

## 6. Query syntax rules

| Input | Behaviour |
|---|---|
| `budget` | Token-boundary match via `unicode61` |
| `budget review` | AND (both terms present) — FTS5 default operator |
| `"budget review"` | Exact phrase, double-quote delimited |
| `bud*` | Prefix match; `*` suffix passed through by `makeFTS5Pattern` |
| `café` | Matches `cafe` + `café` via `diacritics: .remove` |
| `it's` | Apostrophe = token separator; matches `its` |
| `"""` / lone `*` | Pattern compile fails → catch → returns `[]`, logs readFailed |
| empty / whitespace | Guard returns `[]` → caller falls back to RECENT |

Sanitization is already handled by `makeFTS5Pattern(rawPattern:forTable:)` at line 157 of `TranscriptRepository.swift`. It validates and compiles; invalid patterns throw, the repository catches and returns `[]`. Stage C does NOT strip backslashes, `*`, or other FTS5 metacharacters manually — introducing a second sanitizer risks double-escaping and breaks the existing `DatabaseOperationStatusTests` failure-injection contract.

## 7. TDD test strategy

**Repository level (`PersonalScribeCoreTests/Database/TranscriptRepositoryTests.swift`):**

- `test_searchWithLimit_ordersByRankThenTimestamp` — three entries at ts 100/200/300 with varying term frequency; top-ranked row first regardless of timestamp, timestamp tiebreak for equal ranks.
- `test_searchWithLimit_multiWordANDMatchesIntersection` — two rows, one containing both terms, one with only one; only intersection comes back.
- `test_searchWithLimit_phraseMatchRequiresExactOrder` — `"budget review"` matches `"the Q3 budget review goes well"` but NOT `"review the budget"`.
- `test_searchWithLimit_prefixWildcardMatchesPrefixes` — `bud*` matches `budget`, `buddy`; does not match `review`.
- `test_searchWithLimit_capsResultsAtLimit` — 10 matching rows, `limit: 3` returns 3.
- `test_searchWithLimit_nonPositiveLimitReturnsEmpty` — matches `recent`'s guard.
- `test_searchWithLimit_punctuationOnlyReturnsEmpty` — `"!!!"` / `"..."` return `[]` without raising (piggybacks on the `DatabaseOperationStatusTests` pattern).

Existing `test_search_findsFTSMatches` + `test_search_emptyQuery_returnsEmpty` left untouched; the new tests exercise the overload.

**View-model level (new `Tests/PersonalScribeAppKitTests/NotesSidebarSearchModelTests.swift`):** drive Combine with an injected scheduler (prefer a `TestScheduler` over `ImmediateScheduler` so we can assert on debounce timing).

- `test_emptyQuery_publishesRecent` — initial state, no input → downstream receives `recent` result.
- `test_nonEmptyQuery_afterDebounce_publishesSearchResults` — advance 200 ms → downstream receives `search` result.
- `test_rapidTyping_onlyLastQueryExecutes` — emit `"b"`, `"bu"`, `"bud"` inside the window; only `"bud"` hits the recording spy reader.
- `test_clearAfterSearch_revertsToRecent` — non-empty → tick → clear → tick; downstream returns to `recent` result.
- `test_whitespaceOnlyTreatedAsEmpty` — `"   "` must not call `search`; falls through to the empty-query branch.
- `test_inFlightSearchCancelledWhenQueryChanges` — slow fake reader; emit A, tick, emit B (newer), tick, resolve A last; downstream shows B, not A. Verifies last-write-wins.

**Manual verification — append to `Tests/PersonalScribeAppKitTests/ManualNotesVerification.md`:**

- `MV-NOTES-SEARCH-01` — type `budget` in a history with matching + non-matching rows; non-matching rows disappear after ~200 ms.
- `MV-NOTES-SEARCH-02` — multi-word `budget review`; only rows with BOTH words appear.
- `MV-NOTES-SEARCH-03` — quoted `"budget review"`; only rows with that exact phrase appear.
- `MV-NOTES-SEARCH-04` — paste `"""`; app does not crash, list goes empty or stays put.
- `MV-NOTES-SEARCH-05` — clear field; full RECENT list returns without visible flicker.
- `MV-NOTES-SEARCH-06` — delete a row that matches an active query; it disappears from results (validates AD trigger + #011 delete path end-to-end).

FTS5 rank-ordering feeling "natural" for real English is subjective; manual-verify only. Sidebar row highlight rendering, if ever added, is out of scope (§11(a)).

## 8. Commit shape

Locked tag: `#013 step 3.N:`. Three to five commits (test + source together, rigid TDD):

1. `#013 step 3.1:` repo overload — add `search(query:limit:)` with BM25 ordering + repo-level tests. No callers yet.
2. `#013 step 3.2:` introduce `NotesSidebarSearchModel` + its tests (Combine debounce + last-write-wins). No integration yet.
3. `#013 step 3.3:` wire the Stage A sidebar view model to `NotesSidebarSearchModel`; delete any placeholder in-memory filter. View-model tests exercising the wired behaviour.
4. `#013 step 3.4:` manual-verification runbook entries (`MV-NOTES-SEARCH-*` IDs) appended to `ManualNotesVerification.md`.
5. (optional) `#013 step 3.5:` polish / tiebreaker hardening if review surfaces a ranking edge case.

## 9. Dependencies on other stages

- **Stage A (sidebar shell)** — must produce a `NotesSidebarViewModel` with `@Published searchQuery: String` and a `@Published filteredEntries: [TranscriptEntry]` (or equivalent) so Stage C has a binding point. Stage C does not change the SwiftUI shell, only the view-model innards + downstream behaviour.
- **Stage B (editor + persist)** — if Stage B introduces `title`, FTS5 should eventually index it. Stage C skips that (§12); a Stage B follow-up owns the `v5_fts_title` migration. Also: Stage B must save edits as `UPDATE`, not DELETE-then-INSERT, to keep FTS rank coherent.
- **Stage D (tag filter)** — composes `tag_filter AND fts_query`. Stage C's ranked overload returns `[TranscriptEntry]`, so Stage D can filter client-side first pass or push the tag join into SQL via a later `search(query:limit:tagIDs:)` overload. Stage C does NOT pre-bake that parameter — keep the contract narrow.
- **#011 delete (slate)** — no contract change required. `MV-NOTES-SEARCH-06` verifies delete + live-search interaction.

## 10. Open questions

1. **Debounce duration** — 200 ms proposed; options 150 / 200 / 250. Pick during MV round based on feel.
2. **Highlight matched term** — rank-only proposed. Adding `highlight()` SQL + NSAttributedString-per-row is a complexity bump; defer unless MV reports "I can't tell what matched".
3. **Persist query across window close** — proposal: no, blank on each open (matches Finder). Confirm.
4. **Tokenizer choice** — `unicode61 + diacritics: .remove` is live. For CJK, `trigram` or `icu` are stronger. User base is English-first; revisit only on real-user complaint. Not a Stage C change.
5. **Ranked overload vs replace** — keep both `search(query:)` and `search(query:limit:)` to avoid touching the legacy Transcriptions tab in this ticket.

## 11. Scope cuts within Stage C

- (a) Snippet / highlight rendering — rank-order only. Adding means `[(TranscriptEntry, snippetRange)]` return shape + attributed-string plumbing. Revisit after MV.
- (b) Pagination — sidebar caps at 100. Users with >100 matching transcripts won't see all; acceptable pre-dogfood.
- (c) Search-scope toggles (all vs recent vs by-date) — needs mockup work.
- (d) `title` / `tags` indexing — Stage B's column and Stage D's join table are out of scope; follow-up migrations own those indices.
- (e) Fuzzy / typo-tolerant match — not in FTS5; belongs with Phase 4 embeddings (#022).
- (f) Autocomplete / search suggestions — separate feature, not a Stage C line.

## 12. Risks

1. **Pre-existing FTS5 infra conflicts with new overload** — low. The new method adds a parameter; existing callers of `search(query:)` are untouched. Contract-widening, not breaking. Verify with existing `test_search_findsFTSMatches` + new `…_ordersByRankThenTimestamp` running side-by-side.
2. **Swift 6 concurrency on the debounce model** — medium. Combine on `DispatchQueue.main` + detached `Task` for the async repo call is an area we've been bitten by (memory: `swift6_sendable_boundary`). Mitigation: main-actor isolate the debounce class, mark state `@MainActor`, capture only `Sendable` values across the Task boundary, store the `Task<Void, Never>` handle on main.
3. **FTS5 input edge cases** — medium. Users typing a lone `*`, trailing unterminated quote, or `\\` will hit `makeFTS5Pattern` compile failures. Current empty-result + log is correct but silent; if MV reveals "I typed a star and got nothing" confusion, add a hint. Deferred to open question / MV.
4. **Stage B `title` column not indexed** — high if Stage B lands first. If users edit titles before the follow-up migration, FTS5 won't search them. Mitigation: Stage C plan flags it explicitly; Stage B briefs note the same. No Stage C change blocks Stage B.
5. **Worktree cherry-pick drift** — medium. The `TranscriptReading` protocol addition may conflict with `slate`'s #011 edits if both land from worktrees. Mitigation: keep the protocol change small + surgical, cherry-pick first, resolve on the overload signature only.
6. **Legacy `TranscriptionsTabViewModel.filteredEntries` divergence** — low. The legacy unified-window Transcriptions tab keeps its in-memory `.contains` filter. Two search behaviours in the app is a minor UX inconsistency, but both are intentional: NotesWindow is the new FTS5 surface, the legacy tab is untouched until a later deletion pass. Document in the `#013 step 3.3` commit message.

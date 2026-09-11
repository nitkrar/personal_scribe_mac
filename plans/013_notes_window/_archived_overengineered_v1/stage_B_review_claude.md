# Stage B review (claude)

Reviewed against `plans/013_notes_window/stage_B_editor_and_persist.md`, current trunk (`9d1dfb1`), and cross-stage plans C/D/E. Scope: editable title + body with debounced persist to the shared SQLite store.

## Verdict

**Rework required — block pending cross-stage resolution.** Stage B is directionally correct and most of the plumbing is right: the repo-envelope shape, the `UPDATE` row-level atomicity, `is_user_edited` clamp semantics, and the pre-dogfood "FTS indexing of title = out of scope" instinct all match the existing code's posture. But three blockers must land before code starts:
1. A migration-number collision with Stage D (both claim `v5`) that both plans are currently silent about — and the tie-breaker logic argues for Stage B = v5, Stage D = v6, but the plans don't say so.
2. The plan leaves the Stage E contract underspecified — `@Published draftTitle/draftBody` is not enough; Stage E's plan literally states it needs `@Published body: String` and `@Published selection: NSRange` (or a Range) plus `@Published isEditorFocused: Bool`. Stage B needs to either widen its view-model surface to expose those, or explicitly defer them to Stage E with a named extension point.
3. The Combine debounce "flush synchronously on selection change" pattern (§2, §5 step 1) is not a supported Combine operator — `.debounce` has no flush API, and the fix is architecturally meaningful (shift to a Task-based debouncer, or hold the pending-value + timer explicitly). The plan waves at this without acknowledging it.
4. The plan is silent about `AppDatabaseSchemaEquivalenceTests.swift`, which pins the `transcripts` DDL byte-identically — Stage B's migration will break this test unless the `expectedSchemaDump` is updated in the same commit. That's not a "might need auditing" risk; it's a deterministic red test in step 2.1.

After those four land, the rest is straightforward.

## Critical issues

### 1. Migration v5 double-claim (plan §3 vs Stage D §3)

`plans/013_notes_window/stage_D_tagging.md:81` claims `v5_tags_tables` (next migration after `v4_runtime_guard_marker`, verified against `Sources/PersonalScribeCore/Database/Migrations/TranscriptsMigrator.swift:58`). Stage B's §3 also claims `v5`. Only one can be v5.

**Recommendation:** **B = v5, D = v6.** Rationale:
- Stage B blocks Stage E (editor API surface) and is on the ticket's critical path.
- Stage D is deferred until after FTS Stage C lands; it has time to renumber.
- Stage D's migration body is self-contained (new tables only, no transcripts-column touch), so renumbering to `v6_tags_tables` + `PRAGMA user_version = 6` is a two-line diff in one plan with no ripple.
- Resolution must be recorded in both plans before execution. Without it, whichever stage lands second will silently conflict: GRDB keys migrations by the registered key string, so two different migrations both keyed `v5_…` would not collide on name (they'd both execute), but the `PRAGMA user_version = 5` line in each would stomp the other. And `AppDatabaseSchemaEquivalenceTests` would fail with a different schema than either plan expects.

Action items:
- Stage B plan §3: change `registerMigration("v5_notes_editable_fields")` to remain v5 but add an explicit "Coordination: Stage D renumbers to v6_tags_tables" line.
- Stage D plan §3: renumber to `v6_tags_tables`, `PRAGMA user_version = 6`, and rewrite the "verified against trunk ends at v4" sentence to "verified against trunk ends at v5 after Stage B lands".
- Migration test `test_v5Migration_userVersionBump` in Stage B stays as-is; Stage D's test `test_migrate_v5_userVersionIs5` renames to `_v6`.

### 2. FTS-title indexing: absorb into v5, don't punt to Stage C or a future v7

Stage C `stage_C_fts5_search.md:156,173,182` explicitly declines ownership of the `title`-in-FTS index and calls it "a Stage B follow-up … owns the `v5_fts_title` migration." Stage C's reviewer flagged this unacceptable. Stage B's §3 bullet 3 currently agrees with Stage C ("Stage B does NOT add `title` to the FTS index").

**Position: Stage B should absorb the FTS-title update into its v5 migration.** Reasons:
- The FTS table (`v2_fts_search`) was created via `table.synchronize(withTable: "transcripts")` which auto-generated AD / AI / AU triggers on `text` only (visible in `AppDatabaseSchemaEquivalenceTests.swift:64-78`). Adding `title` to FTS requires: (a) dropping the virtual table + triggers, (b) recreating with both `text` and `title` columns, (c) regenerating triggers, (d) `INSERT INTO transcripts_fts(rowid, text, title) SELECT rowid, text, title FROM transcripts` to backfill.
- Doing (a)–(d) inside v5 keeps "search indexes what the user sees" as an invariant from the moment the `title` column exists. If Stage B ships title-editable without search covering title, users will type an edited title, fail to find it, and file a bug before Stage C lands.
- Waiting until a future v7 means two FTS rebuilds (one at v5 → text-only, one at v7 → text+title). Rebuilds on a multi-thousand-row `transcripts` table are cheap, but the plan complexity is not — two migrations duplicate the trigger-drop + rebuild logic.
- Pre-dogfood solo context (memory `feedback_pre_dogfood_no_legacy_users`) says "on-disk state is disposable." Doing the v5 FTS rebuild now costs nothing on the dev box.

Concrete shape for v5:

```
v5_notes_editable_fields:
    ALTER TABLE transcripts ADD COLUMN title TEXT;
    ALTER TABLE transcripts ADD COLUMN is_user_edited INTEGER NOT NULL DEFAULT 0;
    ALTER TABLE transcripts ADD COLUMN updated_at REAL;
    DROP TABLE transcripts_fts;                       -- drops the three triggers with it
    CREATE VIRTUAL TABLE transcripts_fts USING FTS5(
        title, text,
        tokenize='unicode61 remove_diacritics 2',
        content='transcripts'
    );
    INSERT INTO transcripts_fts(rowid, title, text)
        SELECT rowid, title, text FROM transcripts;
    PRAGMA user_version = 5;
```

Stage B's search callsite in `TranscriptRepository.search(query:)` does NOT need to change in v5 — the search projection still pulls from `transcripts` (joined on rowid), and `MATCH ?` against the multi-column FTS table queries both columns by default. Stage C will own ranking / highlighting changes. So this stays a migration-only absorption.

**If the reviewer team rejects this scope widening**, the fallback is: Stage B ships text-only FTS, Stage C's plan is amended to own the title-FTS migration in its own step (v6 if B=v5/D=v6 path, or a later v7 otherwise). Either way, "punt to an unscheduled follow-up" is not acceptable.

### 3. Stage E unblock: view-model API surface is insufficient

Stage E (`plans/013_notes_window/stage_E_format_toolbar.md:120`) explicitly requires:
- `@Published var body: String`
- `@Published var selection: NSRange` (or `Range<String.Index>`)
- `@Published var isEditorFocused: Bool` (Stage E says it can add this itself)
- Method hooks: `applyBold()`, `applyItalic()`, `toggleBullet()`, `insertLink(url:text:)`

Stage B §5 exposes only `@Published draftTitle`, `@Published draftBody`, `@Published isDirty`, `@Published lastSaveError`. Missing:
- **Selection state.** SwiftUI `TextEditor` does not expose `NSRange` selection as a binding — you need `NSViewRepresentable` wrapping `NSTextView` to get it. Stage B's commit 2.5 ("SwiftUI `TextField`/`TextEditor` bindings") punts on this entirely. Stage E's §recommendation is literally "NSViewRepresentable wrapping NSTextView (recommended) … Precedent: `Overlay/VisualEffectBlur.swift` already does NSViewRepresentable in this project." Stage B cannot ship with plain `TextEditor` and leave Stage E to retrofit; that's a structural rewrite of the editor, not an extension.
- **Focus state.** `@Published isEditorFocused: Bool` — same dependency: only recoverable from `NSTextView` via `becomeFirstResponder` bridging.
- **Formatting method hooks.** Stage E can add these itself in its own commits, but they mutate `body` + re-emit `selection`; the VM's debounce pipeline must treat those mutations identically to user typing (trigger debounce, set dirty). Not exposed as a contract in Stage B.

**Action items:**
- Stage B's §5 view-model must expose (at minimum) `@Published var body: String` (rename `draftBody`) and `@Published var selection: NSRange`. Adding `isEditorFocused: Bool` is optional (Stage E can add it) as long as the view-model is structured to accept new @Published props without re-plumbing debounce.
- Stage B's commit 2.5 must use `NSViewRepresentable` over `NSTextView`, not `TextEditor`. The additional scope is ~100 LOC (a `NotesTextEditor` representable, selection coordinator, focus bridge). Worth it — Stage E's plan says the alternative is "the bullet Enter-interception becomes best-effort, and the 'active-trait highlight' on B/I buttons may flicker with selection latency" which is a user-visible regression.
- Stage B's tests §6 case 11–12 must cover selection-range emission from the bridge, not just `draftTitle` mutation. Without selection emission being tested, Stage E will discover the bridge is broken at Stage E 5.x runtime-verify time.
- Alternative if the reviewer team rejects the scope widening: Stage B ships plain SwiftUI `TextEditor`; Stage E's first commit (step 5.0, already flagged in its §7 "if Stage B ships late") refactors to `NSViewRepresentable`. That's workable but brittle — changing the editor surface after saves are wired to it risks introducing save-path regressions that Stage B's tests won't catch. Prefer the wider Stage B scope.

### 4. Combine `.debounce` has no flush — §2 "flush synchronously on selection change" does not compose

Stage B §2 "Selection-change semantics" says: "flush pending debounce synchronously (fire the save immediately, `await` it) before loading the new row." §5 pipeline step 1 repeats the same idea. This cannot be implemented with `.debounce(for:scheduler:)` — that operator delays emissions and has no public "fire now" API. The stored `AnyCancellable` can be cancelled, but cancelling discards the pending value rather than firing it.

The codebase has **no existing `.debounce(` usage** (`grep -rn "\.debounce(" Sources/` returns zero hits — only `GlobalHotkeyMonitor`'s custom tap-debounce counter). So "we already do this" is not available.

**Viable patterns, ordered by fit:**
1. **Manual debouncer (recommended).** Store the pending `(title, body)` tuple + a `Task` with `try await Task.sleep(for: .milliseconds(800))`. On each edit: cancel the prior task, store new pending value, spawn new sleep-then-save task. On selection change: cancel the task AND synchronously run the save body with the captured pending value. This is the only pattern that supports "flush." ~30 LOC. Pure Swift concurrency, no Combine, matches Stage B's declared `@MainActor` view-model isolation cleanly.
2. **Combine `.throttle(latest: true)` over `.debounce`.** Throttle emits the latest within a window; combined with a `PassthroughSubject` you can drive-flush by sending a synthetic "urgent" value. Awkward, leaks the pending-value abstraction into the publisher plumbing.
3. **`CurrentValueSubject` + timer.** Similar to (1) but through Combine's value machinery; doesn't buy anything over the raw Task approach and makes selection-change flush an imperative `.send()` + manual timer-invalidate.

**Action items:**
- Rewrite §2 and §5 pipeline to name the debouncer pattern explicitly. Current text ("Combine `.debounce(for: .seconds(0.8), scheduler: DispatchQueue.main)` on the view-model's `$draftTitle` and `$draftBody` publishers, feeding a single `Task { try await save() }` sink") cannot do flush.
- Swift 6 strict-concurrency implication: `Task` captures `self` (@MainActor); inside the task, `await repository.update(...)` hops off-main fine. `AnyCancellable` → gone. Nothing crosses a Sendable boundary.
- Related: the "capture the entry id in the flush closure" risk in §2 and §5 step 1 needs explicit code pattern. With a stored pending-value tuple, the struct/tuple can carry `(id: UUID, title: String?, body: String)`, so the save task reads from the captured value, not from `selectedEntry` which may have changed. Worth spelling out.

### 5. `AppDatabaseSchemaEquivalenceTests` byte-identical DDL pin (not mentioned in plan)

`Tests/PersonalScribeCoreTests/Database/AppDatabaseSchemaEquivalenceTests.swift:17` runs `test_appDatabase_schemaDumpMatchesPinnedDDL` which diffs `sqlite_master` DDL against a pinned string literal `expectedSchemaDump` (lines 39–79). The current pin declares the transcripts DDL with exactly the v1 columns (id, timestamp, text, audio_duration, processing_duration) and no triggers / FTS schema changes beyond v2.

Stage B's v5 `ALTER TABLE` will add `title`, `is_user_edited`, `updated_at`, which shows up in sqlite_master differently from a fresh `CREATE TABLE` (SQLite preserves the original `CREATE TABLE` statement and records altered columns only by their effect, not by appending to the pinned DDL). Either way, the schema dump diff WILL change. If Stage B also absorbs the FTS-title migration (per Critical issue #2), the `transcripts_fts` virtual-table DDL + triggers change too.

**Action items:**
- Step 2.1 (migration + schema tests) MUST update `expectedSchemaDump` in `AppDatabaseSchemaEquivalenceTests.swift` in the same commit. Plan §6 omits this entirely.
- Add to Stage B's §6 commit shape: "2.1: migration + schema tests (`TranscriptsMigrator` v5 + `AppDatabaseMigrationTests` cases 9–10 + `AppDatabaseSchemaEquivalenceTests.expectedSchemaDump` pin update)".
- Worth adding a Stage B risk entry: "Schema pin is load-bearing — anyone running `swift test` after v5 merges will red the suite if the pin isn't updated in lockstep."

## Medium concerns

### 6. Projection-widening: scope is small, but plan over-estimates the risk

§11 risk #2 flags: "the `recent/all/search` projection widening to include new columns could break tests that snapshot row column order. Audit `Tests/PersonalScribeCoreTests/Database/` and `Tests/PersonalScribeCoreTests/Metrics/`."

Actual audit:
- `TranscriptRepositoryTests.swift` has 25 references to the reader methods. These all construct `TranscriptEntry` via the public memberwise init or fetch and compare by `id` / `text`. None snapshot row column order.
- `Metrics/MetricsContractTests.swift` + `SQLiteMetricsServiceTests.swift` — the metrics pipeline goes through `MetricsSnapshotStore` which observes `MetricsNotification.transcriptCommit` and calls `repository.count()`. Column order is not touched.
- `TranscriptEntryRecordTests.swift:14-22` reproduces the v1 DDL inline (see its comment: "does not depend on any future migrator surface"). Adding `title`/`is_user_edited`/`updated_at` to `TranscriptEntry` WILL break this test's round-trip because the inline DDL doesn't declare the new columns, so `encode(to:)` writing them will fail the persist step.

**Action item:** `TranscriptEntryRecordTests.swift:14-22` must be updated in step 2.2 (the `TranscriptEntry` record conformance commit). Either (a) update the inline DDL to v5-shape and keep the "does not depend on migrator surface" decoupling, or (b) switch the test helper to use `TranscriptsMigrator.makeMigrator()`. Option (a) is closer to the file's stated intent. Plan should name this explicitly, not hand-wave.

The rest of the "snapshot row column order" risk is overstated. The real risk is `TranscriptEntryRecordTests` plus `AppDatabaseSchemaEquivalenceTests` (#5 above), both deterministic red tests.

### 7. Repository API signature — `update(id:title:text:updatedAt:)` is fine; one edge to consider

§4 signature:
```swift
public func update(id: UUID, title: String?, text: String, updatedAt: Date) async throws
```

Well-chosen vs. the "separate updateTitle / updateBody" alternative: row-level UPDATE is a single `await database.write`, cheaper than two transactions. No optimistic concurrency is fine for a single-window app. `String?` for title with NULL semantics matches the §3 column design.

One concern: **the caller computes `updatedAt`**. That forces the view-model or its clock abstraction to be passed around. Cleaner would be for the repo to set `updated_at = ?` with an injected clock at repo-construct time (GRDB has no `datetime('now')` that matches epoch-seconds REAL — you'd have to multiply `julianday('now') - 2440587.5` by 86400, which is gross). Counter-argument: the view-model already has a `clock() -> Date` dependency for testability of debounce, so carrying it to `updatedAt` is a single extra argument. Fine to keep as specified. **No action — just flag: make sure step 2.4 injects the clock into the view-model, not `Date()` inline.**

Minor: `TranscriptUpdateError.notFound` as a nested internal error inside `queryFailed(underlying:)` (§4) is the right call — matches the `TranscriptStorageError` envelope pattern at `TranscriptRepository.swift:61-68`. The alternative of widening the public enum to a new `.notFound` case would be a breaking API change to `TranscriptStorageError`.

### 8. Collision with #011 delete path — plan's story is correct; one test gap

§2 "Conflict strategy" and §11 risk #3 describe the pending-update-on-deleted-row case well: repo throws `TranscriptUpdateError.notFound` via `db.changesCount == 0`, view-model treats as "selection gone," silently clears drafts.

Verified against trunk: `TranscriptRepository.swift:74-91` (`delete(id:)`) posts `MetricsNotification.transcriptCommit` on success and swallows `CASCADE` FK work (Stage D relevant). No lockfile, no optimistic token. Stage B's update method is orthogonal at the SQL layer — no shared CTE, no ordering issue.

Test gap: Stage B §6 case 19 (`test_selectedEntryDeletedExternally_silentFailure`) tests only the view-model's silent-clear behavior. There's no test that asserts the **repository** returns `TranscriptUpdateError.notFound` for a deleted id. Case 4 (`test_update_missingId_throwsQueryFailed`) covers "never existed" which tests the same code path but doesn't name the delete-race scenario, so it's easy to read Stage B and assume there IS a delete-race test. Rename / split case 4 to cover both naming cases explicitly, or add case 4b (`test_update_afterDelete_throwsNotFound`) that inserts then deletes then updates. Cheap test, high confidence payoff.

### 9. `TranscriptEntry` positional init risk is overstated

§11 risk #6: "any call site using positional init will break." Verified:
- `Sources/PersonalScribeSession/Pipeline/Orchestrator/SessionPipelineOrchestrator.swift:454-460` uses **named arguments** (`id:timestamp:text:audioDuration:processingDuration:`). Adding new trailing optional parameters with defaults is source-compatible.
- No positional uses of `TranscriptEntry(` in `Sources/`.
- 8 uses in `Tests/` — need to audit, but these are test fixtures and cheap to fix.

Not a blocker. Remove the risk entry or downgrade to a test-fixture audit (grep is enough, ~15 min of work).

### 10. §9 open question (a) — auto-derived title formula — is premature and already answered

`Sources/PersonalScribeAppKit/UnifiedWindow/Tabs/HomeTab.swift:139-153` already has `static func title(for entry: TranscriptEntry) -> String` with the "first non-empty line, trimmed, fallback to date stamp" rule used by HomeTab today. Stage A's review (`stage_A_review_claude.md` Medium concern #1) already flagged this as a duplication risk: two divergent title rules in two windows is the smell.

Stage B §5 proposes a **third** rule: "up to first 48 chars, cut at last word boundary." That's a silent divergence from both Stage A's 40-char rule (already contested in Stage A review) AND `HomeTab.title(for:)`'s first-line-trimmed rule.

**Recommendation:**
- Promote `HomeTab.title(for:)` to a shared helper (`TranscriptEntry.displayTitle` computed property, or `TranscriptTitle.derive(from:)` free function in `PersonalScribeCore/`). Stage A review already argues this.
- Stage B's view-model uses it. `autoDerivedTitle(from:)` as a private static helper disappears.
- §9 (a) "first 48 chars at word boundary vs first sentence" becomes moot — the shared helper's first-line-trimmed rule wins.
- If the mockup demands ~48-char truncation, that's a *row-rendering* concern owned by `TranscriptRow`'s `Formatters.truncate(title, maxLength: Layout.titleMaxLength = 60)` already, not the title derivation itself.

### 11. Selection-change save semantics: flush-synchronously is right; say why `await` doesn't deadlock

§9 open question (b): "Flush-before-switch (proposed) vs save-in-background-while-switching." Correct answer: flush. Stage B should commit to this without leaving it as a "flag for user" — the background variant has the exact race the plan mentions ("row A's save silently overwriting B because the view-model got confused"), and swapping defaults on the user's word would require retest of every selection-change case.

One technical note the plan doesn't address: `@MainActor` view-model calling `await updater.update(...)` inside a selection-change setter is fine — `update` is declared `async throws`, not `@MainActor`, so the await hops off. But `didSet` on a `@Published` property is *synchronous*; you can't `await` from it. The flush must happen in an explicit method the SwiftUI binding calls (e.g. `selectEntry(_:)`) that can be `async`. Plan should name that method. Alternative: the view-model observes `$selection` via its own `sink` with `.sink { [weak self] newID in Task { @MainActor in await self?.handleSelectionChange(to: newID) } }` — same effect but keeps the binding ergonomic.

### 12. `is_user_edited` column — load-bearing, but plan's rationale is thin

§3 says `is_user_edited` gives "Stage D/E a cheap filter for 'user-curated notes' without scanning `updated_at`." That's weak — neither Stage D's plan nor Stage E's plan actually asks for such a filter. Rechecked both: Stage D filters by tag, Stage E doesn't query transcripts at all.

Real reason to keep the column: **`title IS NOT NULL OR body != original` can't be computed** — the DB doesn't store `original`. Once the user types into the body, there's no before-state to diff against. So `is_user_edited` is the only record that the body was ever touched by a human vs. left as auto-ingested.

Use case where that matters: Stage B's own §5 step 1 semantics. When a user blanks the title to empty string, we want "re-derive from body" (§3 bullet 1 rationale for nullable). That's about `title IS NULL`, not about `is_user_edited`. The flag is redundant for Stage B itself.

**Recommendation:** Either keep the column and name a concrete Stage 4+ consumer (future "prune auto-ingested-but-never-read transcripts" maintenance?), OR cut it and re-add in a future migration if a consumer materializes. Cutting removes a column + simplifies the `UPDATE` by one field + saves a test case. Pre-dogfood solo, cutting is cheap. **Lean: cut.** Flag for user if they want to keep it.

### 13. `updated_at REAL` — check consistency with existing timestamp style

Verified: `transcripts.timestamp` is `REAL NOT NULL` (epoch seconds), stored via `timestamp.timeIntervalSince1970` at `TranscriptStore.swift:67`. `TranscriptsMigrator.swift:28` DDL confirms `timestamp REAL NOT NULL`. Stage B's `updated_at REAL` (nullable because pre-Stage-B rows don't have it) matches that convention exactly. Good.

Stage D's `tags.created_at REAL NOT NULL` (plans/013_notes_window/stage_D_tagging.md:47) also matches. No mixed REAL/INTEGER epoch storage in the project. No action — just a confirmation that the plan's choice is right.

## Minor nits

- **§6 commit 2.1 landing schema without code reading it.** Safe — SQLite `ALTER TABLE … ADD COLUMN` is atomic and backward-compat for existing `SELECT id, timestamp, text, audio_duration, processing_duration` queries. Step 2.2 and later add the new columns to projection. No cross-commit test-red.
- **§6 commit 2.4 view-model tests 11–19 numbering collision.** The plan lists repo tests 1–8, migration tests 9–12, and view-model tests starting at 11 — overlapping with migration test 11. Renumber view-model to start at 13 (or renumber migration to 9–12 + separate range). Purely cosmetic but will trip up the `Tests/` grep during code review.
- **§4 `TranscriptUpdating` protocol** — should be `@Sendable`? Matches `TranscriptReading: Sendable` at `TranscriptReader.swift:3` and `TranscriptDeleting: Sendable` at `:9`. Plan §4 doesn't say. Add for consistency; costs nothing given GRDB's `Configuration.defaultLabel`-style safety.
- **Manual runbook `MV-NOTES-EDIT-06` is the one that catches delete-during-edit race** — good. Strengthen the runbook text to say "do not just click delete and immediately check the window; also try: edit → click delete → wait 2s → observe (should confirm flush fired against the now-missing row and silently cleared)."
- **§8 "Does NOT block Stage C"** — false if Stage B absorbs the FTS-title migration per Critical issue #2. With absorption, Stage B enables FTS of the title column, which Stage C uses for ranking/highlight. Update §8 to "Coexists with Stage C: Stage B's v5 migration establishes FTS-over-title; Stage C extends search UX on that foundation."

## Scope / approach disagreements

- **Silent-error policy for save failures.** §5 says "on failure, publish `lastSaveError` — UI shows a subtle footer toast (Stage B can leave that as a `TODO-UI` comment since the mockup doesn't show error chrome)." Pre-dogfood this is fine, but a TODO that never surfaces UI means failures are silent from the user's POV. Stage B's manual-verify runbook has no entry like "MV-NOTES-EDIT-07: save fails (simulated), user sees clear-to-dismiss error affordance." Add it, even if the affordance is a console log for now. Otherwise "flexible TDD" gets stretched to "no verify at all."
- **"No fetch(id:)"** (§4). Agree for now. If Stage E's formatting mutations need to round-trip through the repo for an up-to-date body after an external writer (Stage D's tag-CASCADE can't touch body, but audio-sidecar re-ingestion could eventually), revisit then. Not a Stage B blocker.

## What the plan does well

- **Envelope parity with `delete(id:)`** (§4). Posting `MetricsNotification.transcriptCommit` on successful update + mirroring the operation-observer `.writeSucceeded`/`.writeFailed` shape keeps the subscriber contract uniform. `MetricsSnapshotStore.swift:86-92` will pick it up without changes.
- **Clamp `is_user_edited = 1` unconditionally** (§2). Removes an entire class of "did the auto-ingest path reset it?" bugs by making the update SQL idempotent with respect to user intent.
- **Nullable title semantics** (§3 bullet 1). "NULL = derive, empty-string = user typed empty on purpose" is the right distinction; dropping to `NOT NULL DEFAULT ''` would have forced a uglier "re-derive if equals auto-derived" check on every read.
- **"Capture entry id in flush closure"** (§2, §11 risk #5). The debounce-timer-fires-on-stale-selection race is real and the mitigation is correct in principle. Just needs the Combine-flush fix (Critical #4) to actually deliver it.
- **Pre-dogfood disposable-on-disk posture honored.** §3 "pre-migration DB shape is not a backward-compat concern, only the `init(row:)` nullable reads are" matches `feedback_pre_dogfood_no_legacy_users`. Plan doesn't over-engineer a data-migration path.
- **Commit split granularity** (§6, pre-fix). Six commits, each tagged with its test names, is right-sized — small enough to review, large enough to test as units. After the fixes (AppDatabaseSchemaEquivalence pin update in 2.1, renumbering of test case 11 in 2.4, split of step 2.4 if widened for NSTextView bridge), still probably 6 commits total.

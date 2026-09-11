# Stage D review (codex)

## Verdict
ship with minor fixes

## Critical issues (if any)
- None.

## Medium concerns
- §5 drops Stage C's ranked-search contract when tags are active. Stage C says FTS results order by `bm25(transcripts_fts), timestamp DESC`; the composed SQL in §5 orders by `timestamp DESC` only. That would make tagged search behave differently from plain search. Preserve BM25 in the composed query.
- §6(c), §8, and §12 are stale against the repo. `Sources/PersonalScribeAppKit/Components/TagChip.swift` already exists, has neutral/accent variants, and there is already `Tests/PersonalScribeAppKitTests/Components/TagChipTests.swift`. Reframe `#013 step 4.4` as extending/reusing the existing chip instead of "build TagChip".
- §8 and §13 contradict each other on #014 closeout. §8 says the BACKLOG pointer update lands in commit 4.6; §13 says BACKLOG edits are separate and not staged in Stage D commits. Per the project rule cited in the task, §13 is the correct policy. Fix the commit plan.
- §4 puts the new tag-aware transcript reads on concrete `TranscriptRepository` only. That weakens the current test seam from `TranscriptReading` and will push NotesWindow tests toward concrete-temp-DB setup. Add a narrow protocol for the tag-aware read surface or widen `TranscriptReading` intentionally.
- §6(b) and §8.6 undercount the autocomplete popover work. I found no existing `.popover(` or `NSPopover` usage under `Sources/PersonalScribeAppKit/`; the only popover-related file I found was `Sources/PersonalScribeAppKit/Settings/ModelInfoPopoverPresenter.swift`, which is presenter logic, not a reusable popover implementation. Split 4.6 or explicitly budget bespoke UI plumbing.
- §10's "unlimited with soft warning at >10" is still a punt. The actual v1 problem is row-wrap/overflow behavior in the editor chip row, and a warning does not solve it. Decide now between a hard cap, explicit wrap behavior, or an overflow menu; if unlimited ships first, any later cap becomes a data-cleanup decision.
- §12's 10k-row / 50 ms benchmark reads as defensive over-engineering for a pre-dogfood local app, and a timing threshold is a brittle test target anyway. Keep the junction if you want it, but justify it from semantics; use `EXPLAIN QUERY PLAN` or an ad hoc perf note instead of a hard timing gate.
- §3 is too loose against the backward-compat rule. The repo does auto-migrate on `AppDatabase.init`, so pre-migration DBs should upgrade in practice, but the plan should lean on that invariant rather than say "an un-migrated DB is not a supported state post-Stage D."

## Minor nits
- §2's usage-count justification says sidebar sorting is just `COUNT(*) GROUP BY tag_id` on the junction. That only works if zero-usage tags are dropped. If §10 keeps zero-note tags, `listAllWithUsage()` needs a `LEFT JOIN` from `tags` to `transcript_tags`.
- §2 calls delete-cascade basically "free". The current path is solid enough: `TranscriptRepository.delete(id:)` does `database.write { DELETE FROM transcripts WHERE id = ? }` in `Sources/PersonalScribeCore/Database/TranscriptRepository.swift`, and `AppDatabase.write` forwards to `writer.write` in `Sources/PersonalScribeCore/Database/AppDatabase.swift`. But I did not find any explicit `foreign_keys=ON` setup in repo code, so the plan is right to keep the assertion / migration test.
- §6(a) makes rename/delete sidebar-only via right-click. That is acceptable macOS UX, but it is still low-discoverability. Treat it as something to validate in dogfood, not as obviously settled.

## Scope / approach disagreements
- I would keep the junction tables from §2. For this exact feature set, a TEXT column is not actually simpler once you include case-insensitive canonical names, global rename/delete, usage counts, autocomplete over existing tags, and multi-tag AND filtering. A trigger-maintained secondary index on TEXT/JSON mostly recreates the normalization you were trying to avoid.
- If I wanted a simpler v1, I would cut scope, not denormalize. The first things to drop would be global rename/delete or unused OR-mode plumbing, not the junction schema.

## What the plan does well
- §3 is grounded: `Sources/PersonalScribeCore/Database/Migrations/TranscriptsMigrator.swift` does end at `v4_runtime_guard_marker`, and it is registered at line 58 as claimed.
- §5's choice to push tag filtering into SQL is directionally right; Stage C already leaves room for a later composed `search(...tagIDs...)` overload, so there is no inherent Stage C/D contract clash beyond the missing BM25 ordering.
- §7 has the right kinds of repository tests, and the #011 collision story is credible because the current delete path already routes through `database.write` rather than bypassing the DB layer.
- The plan mostly uses the pre-dogfood / disposable-state context correctly: no backfill theatrics, no invented legacy-user constraints, and the migration is additive.

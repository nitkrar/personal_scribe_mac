# Layer 8 — Metrics Stage 1 Code Review

## Verdict
CHANGES REQUIRED. The rollup math and Stage-1 isolation are mostly correct, but the public `MetricsService` contract does not match the locked query API and the reader does not actually enforce read-only SQLite access.

## Scope
- Reviewed `git show` for `ab402c3` (`trunk: step metrics.1 — Layer 8 Stage 1 parallel-build`) and `5a2ea99` (`trunk: wave-b fix-forward — unblock build + Swift 6 compile fixes`).
- Inspected in full: all files under `Sources/SeshatCore/Metrics/` and `Tests/SeshatCoreTests/Metrics/`.
- Supporting contract/context read in full: `plans/central/LAYER_8_metrics.md`, `plans/central/reviews/LAYER_8_review.md`, `plans/CENTRAL_LAYERS_PROMPT.md`, `Sources/SeshatCore/SQLiteTranscriptStore.swift`, `plans/central/LAYER_2_storage.md`, `Sources/SeshatCore/Storage/AppConfig.swift`, `Sources/SeshatCore/Storage/AppStorageLocator.swift`, `Sources/SeshatCore/Storage/StorageLocator.swift`, `Sources/SeshatAppKit/Composition/AppComposition.swift`, and `Sources/SeshatAppKit/Composition/SeshatAppMain.swift`.
- Out of scope: non-Metrics fixes bundled into `5a2ea99`, except where needed to confirm they do not change Layer 8 behavior.

## Findings by severity
### BLOCKER
None.

### MAJOR
- `MetricsService` exposes the wrong public contract — `Sources/SeshatCore/Metrics/MetricsProtocols.swift:10-19`, `plans/CENTRAL_LAYERS_PROMPT.md:349-358`, `plans/central/LAYER_8_metrics.md:48-57`. Load-bearing text: `"public protocol MetricsService: ObservableObject, Sendable"` with `var rollups`, `var recentTranscriptions`, `func refresh(reason:)`, `func startObserving()`, and `func stopObserving()`, while the locked master prompt requires `recordingsThisWeek()`, `wordsThisWeek()`, `minsSavedThisWeek()`, `wpmAverageThisWeek()`, and `recentTranscriptions(limit:)`. Why it matters: this implementation follows the revised Layer 8 plan, but it no longer satisfies the user-locked master prompt contract that Stage 2 consumers are supposed to target, and the mismatch is already blessed by `Tests/SeshatCoreTests/Metrics/MetricsContractTests.swift:28-49`. Suggested fix: restore the query-method surface on `MetricsService`; if the published-snapshot model is still desired, keep it in a separate UI-facing adapter instead of changing the core protocol.
- `SQLiteMetricsReader` does not enforce read-only database access — `Sources/SeshatCore/Metrics/SQLiteMetricsReader.swift:8-13`, `plans/central/LAYER_8_metrics.md:63-65`, `plans/CENTRAL_LAYERS_PROMPT.md:346-355,361-363`. Load-bearing text: `"self.dbQueue = try DatabaseQueue(path: databaseURL.path)"`. Why it matters: Stage 1 is explicitly a read-only metrics layer, but this initializer does not configure GRDB for read-only access, so the storage invariant is not enforced at the connection boundary. That leaves the reader able to open the database in writable mode and weakens Layer 2's ownership of bootstrap/path side effects. Suggested fix: open the queue with a read-only GRDB configuration and add a characterization test for missing or unwritable database paths, or inject an already-open read-only database handle from the storage-owned seam.

### MINOR
- The Unicode tokenization tests would still pass after a whitespace-split regression — `Tests/SeshatCoreTests/Metrics/SQLiteMetricsReaderTests.swift:21-57`, `plans/central/LAYER_8_metrics.md:107-108,157-158`. Load-bearing text: the current corpus is `"alpha beta"`, `"Café déjà vu"`, and `"delta echo foxtrot"`, which all produce the same count under `.byWords` and simple whitespace splitting. Why it matters: the implementation in `Sources/SeshatCore/Metrics/SQLiteMetricsReader.swift:120-128` is correct today, but the tests do not actually lock the plan's "Unicode word boundaries, not simple whitespace split" requirement. Suggested fix: add punctuation/apostrophe/CJK or emoji-boundary cases so the suite fails if `enumerateSubstrings(..., .byWords)` is replaced with whitespace tokenization.

### QUESTION
None.

### NIT
None.

## Cross-layer concerns
- Criterion 1, plan/defaults fidelity: no issues observed on the rolling-window default or WPM constant. `MetricsWindow.rollingSevenDays(...)` is implemented at `Sources/SeshatCore/Metrics/MetricsModels.swift:12-19`, and `assumedTypingWPM = 40` is present at `Sources/SeshatCore/Metrics/SQLiteMetricsService.swift:6`. The only fidelity issue is the public `MetricsService` surface called out above.
- Criterion 2, correctness: no issues observed on the core math. Word counting uses `.byWords` at `Sources/SeshatCore/Metrics/SQLiteMetricsReader.swift:120-128`, and minutes saved uses `max((words / 40) - audioMinutes, 0)` at `Sources/SeshatCore/Metrics/SQLiteMetricsReader.swift:72-76`. I also found no telemetry/upload code in the inspected Metrics source or test files.
- Criterion 3, Stage-1 scope / locked decision #7: no issues observed. The transcript schema remains the existing five-column shape with no `type` / `kind` / `intent` field at `Sources/SeshatCore/SQLiteTranscriptStore.swift:170-179`; `ab402c3` added only the new Metrics files; and no Home/UI consumer is wired yet, with `Sources/SeshatAppKit/Composition/SeshatAppMain.swift:170-195` still exposing only the empty `Settings` scene plus direct Notes reader construction.
- Criterion 4, Swift 6 concurrency: no issues observed after `5a2ea99`. `dbQueue.read` is now awaited at `Sources/SeshatCore/Metrics/SQLiteMetricsReader.swift:20` and `Sources/SeshatCore/Metrics/SQLiteMetricsReader.swift:99`, the service stays `@MainActor` at `Sources/SeshatCore/Metrics/SQLiteMetricsService.swift:4-5`, and observer teardown is present at `Sources/SeshatCore/Metrics/SQLiteMetricsService.swift:109-145`.
- Criterion 6, Layer 2 / Layer 6-7 alignment: Stage 1 intentionally still injects a raw `databaseURL` per `plans/central/LAYER_8_metrics.md:63-65`, and I found no Layer 6/7 production consumer of Metrics on trunk. Stage 2 will still need locator-based wiring from Layer 2; the remaining open issue is read-only enforcement at the reader boundary, not current consumer coupling.

## Test gaps
- Criterion 5, test coverage vs plan: one gap observed. The suite does cover rolling seven days explicitly in `Tests/SeshatCoreTests/Metrics/MetricsContractTests.swift:52-61`, and the service tests also construct rolling windows via `MetricsWindow.rollingSevenDays(...)` at `Tests/SeshatCoreTests/Metrics/SQLiteMetricsServiceTests.swift:11-12`, `Tests/SeshatCoreTests/Metrics/SQLiteMetricsServiceTests.swift:98-99`, and `Tests/SeshatCoreTests/Metrics/SQLiteMetricsServiceTests.swift:151-152`, so I did not find ISO-week semantics in Stage 1.
- Missing characterization: there is no test proving the reader refuses a missing or unwritable database path once the read-only open mode is fixed.
- Missing characterization: the current Unicode word-count tests do not distinguish `.byWords` from whitespace splitting; see Minor #1.

## Summary
- BLOCKER: 0 MAJOR: 2 MINOR: 1 QUESTION: 0 NIT: 0
- Criterion 7, code quality: no additional issues observed beyond the findings above. Naming is consistent, `SQLiteMetricsService.refresh` preserves the last good snapshot on read failure at `Sources/SeshatCore/Metrics/SQLiteMetricsService.swift:89-101`, and the fix-forward commit corrected the Swift 6 `await dbQueue.read` issue without changing the intended metrics behavior.
- Verdict rationale: the implementation gets the rolling 7-day window, 40-WPM math, no-telemetry scope, no-UI Stage-1 isolation, and the Swift 6 `await dbQueue.read` fix right. I am still calling for changes because the exported `MetricsService` API does not satisfy the locked query contract and the SQLite reader is not enforced read-only at the connection level.

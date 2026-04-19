> **Do NOT diverge from this plan. Silent divergence is the cardinal sin. To deviate, surface the proposed divergence in a commit-message comment AND in the hand-off report; wait for main-session confirmation. Paraphrasing the contract is divergence. Renaming a protocol the plan specifies is divergence. Choosing a different storage format than the plan specifies is divergence.**

**Do-not-diverge.** Derives stats the Home tab needs (Words this week, Recordings, Mins saved, WPM avg) from the transcript store; no duplicate write-path from the pipeline. Consumer is the Manus-designed Home tab in the unified window (see plans/App UI design/Seshat UI Polish & Unified Window Implementation.md §3.A). The core `MetricsService` contract is the locked read-only query API from `plans/CENTRAL_LAYERS_PROMPT.md`; any `@MainActor` `ObservableObject` snapshot model for UI binding lives in a separate adapter store. Refresh on window focus + on transcript-commit notification (no polling). Stage 2 consumers: the Home tab view; any existing debug counter UI that displays overlapping stats. Stage 3 deletes: scattered ad-hoc word-count/duration computations in views or session code — enumerate from current code.

# Layer 8 - Metrics

## Why this layer exists
Seshat now has a durable SQLite transcript store and a Notes read path, but it still has no single read-only service that computes the Home tab's weekly stat cards from stored transcripts. The current app composition builds raw `SQLiteTranscriptStore` and `SQLiteTranscriptReader` instances directly, so any Home implementation added on top of trunk would otherwise have to duplicate SQL, tokenization, and refresh logic inside UI code.

Layer 8 centralizes that read model into one read-only query service. The service stays strictly downstream of transcript persistence, derives everything from the existing transcript store fields, and can be wrapped by a separate `@MainActor` observable store that gives the eventual unified-window Home tab a direct binding surface for rollups plus the recent-transcriptions list.

## Observed current spread
| File | Line(s) | What lives there |
|---|---|---|
| `plans/CENTRAL_LAYERS_PROMPT.md` | 344-369 | Layer 8 scope: read-only metrics service, word-tokenization rule, 40 WPM baseline, recent list, and Layer 2 dependency. |
| `plans/App UI design/Seshat UI Polish & Unified Window Implementation.md` | 39-57 | Unified-window architecture plus the Home tab contract: 4 stat cards and a 3-item recent list. |
| `Sources/SeshatCore/TranscriptStore.swift` | 3-22 | `TranscriptEntry` fields the metrics layer can derive from: `timestamp`, `text`, `audioDuration`, `processingDuration`. |
| `Sources/SeshatCore/SQLiteTranscriptStore.swift` | 66-129 | Current append/recent/count API over SQLite; no aggregate metrics API and no commit notification. |
| `Sources/SeshatCore/SQLiteTranscriptStore.swift` | 170-197 | Current `transcripts` schema and migrator; there is no `type` / `kind` / `intent` column. |
| `Sources/SeshatCore/TranscriptReader.swift` | 3-41 | Current read-only adapter for Notes. It exposes `recent`, `search`, and `all`, but no rollups. |
| `Sources/SeshatSession/SessionCoordinator.swift` | 220-241 | Single transcript persistence path after transcription succeeds. This is the seam the metrics layer must observe, not replace. |
| `Sources/SeshatAppKit/Composition/AppComposition.swift` | 27-42 | Shared app composition creates the live `SQLiteTranscriptStore` from `SeshatConfig.recordingsDirectory()`. |
| `Sources/SeshatAppKit/Composition/SeshatAppMain.swift` | 184-195 | The Notes window constructs a second raw `SQLiteTranscriptStore` and `SQLiteTranscriptReader` directly. |
| `Sources/SeshatAppKit/Composition/SeshatAppMain.swift` | 170-180 | Current app scene body has no unified window or Home tab yet; it still returns an empty SwiftUI `Settings` scene shell for the LSUIElement app. |
| `Sources/SeshatAppKit/Notes/NotesWindowController.swift` | 37-51 | Standalone Notes window refreshes on `showWindow`, which is the current closest analogue to a future window-focus refresh. |
| `Sources/SeshatAppKit/Notes/NotesViewModel.swift` | 26-45 | Current transcript consumer loads all entries and search results only; there is no summary-rollup state. |

## Proposed API / contracts
### Contract anchors
- `Contract C1`: Metrics are read-only and derive only from transcripts already persisted through `SessionCoordinator.persistTranscript` and `SQLiteTranscriptStore.append(_:)`.
- `Contract C2`: The public `MetricsService` surface is the locked read-only query API. If UI needs published rollups plus recent transcripts, that lives in a separate `@MainActor` adapter store backed by `MetricsService`.
- `Contract C3`: Refresh triggers are `windowFocus` and `transcriptCommit` only. No polling, timer loop, or pipeline-side shadow cache.
- `Contract C4`: Word counting uses Unicode word boundaries (`String.enumerateSubstrings(..., .byWords)`), `minsSaved` uses a 40 WPM typing baseline and clamps at zero, and WPM is computed from total words divided by total audio minutes in the active window.
- `Contract C5`: Home tab and any overlapping debug stats surface bind the same adapter-store snapshot backed by `MetricsService`. No consumer does its own weekly word-count or duration math once Layer 8 Stage 2 is complete.

### Types (enums, structs)
- `MetricsWindow`: value type describing the active rollup window. Initial shape is a rolling 7-day window anchored at refresh time.
- `MetricsRollups`: value type with `recordingsThisWeek`, `wordsThisWeek`, `minutesSavedThisWeek`, `averageWPMThisWeek`, `sampleCount`, `windowStart`, and `windowEnd`.
- `MetricsSnapshot`: value type with `rollups`, `recentTranscriptions`, `lastUpdatedAt`, and `lastRefreshReason`.
- `MetricsRefreshReason`: enum with `.initialLoad`, `.windowFocus`, and `.transcriptCommit`.
- `MetricsNotification`: namespace or enum owning the single transcript-commit notification name used by Stage 2 wiring.

### Protocols
- `MetricsReading: Sendable`
  Signature surface:
  `loadSnapshot(window: MetricsWindow, recentLimit: Int) async throws -> MetricsSnapshot`
  `recentTranscriptions(limit: Int) async throws -> [TranscriptEntry]`
- `MetricsService: Sendable`
  Signature surface:
  `recordingsThisWeek() async throws -> Int`
  `wordsThisWeek() async throws -> Int`
  `minsSavedThisWeek() async throws -> Duration`
  `wpmAverageThisWeek() async throws -> Double`
  `recentTranscriptions(limit: Int) async throws -> [TranscriptEntry]`
- `MetricsSnapshotStore`
  Separate `@MainActor` `ObservableObject` UI adapter store for published rollups, recent transcripts, refresh metadata, and observation triggers.

### Errors
- No new public error enum. Query methods can throw underlying read errors. The separate UI adapter store should log read failures, preserve the last good snapshot, and surface empty-state or stale-data UI through published state rather than forcing Home-tab consumers to catch errors.

## Proposed live implementation
`SQLiteMetricsService` should live in `Sources/SeshatCore/Metrics/` as a final class implementing the locked query-method `MetricsService`. Stage 1 keeps it self-contained by injecting a `databaseURL`, `Calendar`, and clock/reference-date provider. That lets the new layer build and test in isolation before Layer 2 Stage 2 rewires production composition around `StorageLocator`.

`MetricsSnapshotStore` is the separate `@MainActor` `ObservableObject` adapter used for UI binding. It consumes `any MetricsService`, owns refresh coalescing plus observation state, and publishes rollups plus recent transcriptions for the Home tab.

`SQLiteMetricsService` should delegate actual query work to a small `SQLiteMetricsReader` in the same new directory. That reader stays read-only, opens the existing `transcripts.sqlite` file, and uses the current table shape from `Sources/SeshatCore/SQLiteTranscriptStore.swift:170-197`. It should query the rolling window rows once per refresh, then derive:

- recordings: row count in the window
- recent transcriptions: newest-first `LIMIT 3`
- words: Swift-side Unicode tokenization over the fetched `text` values
- audio minutes: sum of `audio_duration`
- mins saved: `max((words / 40) - audioMinutes, 0)`
- WPM average: `words / audioMinutes` when audioMinutes is positive, else `0`

The UI adapter store should serialize refreshes, coalesce overlapping triggers, and only update its published `rollups`, `recentTranscriptions`, and refresh metadata after a full successful read. It should not observe the pipeline directly. Stage 2 introduces a single transcript-commit notification source and a single window-focus observer; both feed `refresh(reason:)` and nothing else.

## Migration of existing call sites
### Stage 1.1 - Define the isolated metrics contracts in new directories
Dependency arrows: `Stage 1.1` has no Stage 2 prerequisite. It can run in parallel with Layer 1 Stage 1, Layer 2 Stage 1, Layer 3 Stage 1, Layer 5 Stage 1, Layer 6 Stage 1, Layer 7 Stage 1, and Layer 9 Stage 1 because this work is confined to new `Sources/SeshatCore/Metrics/` and `Tests/SeshatCoreTests/Metrics/` directories. Layer 4 Stage 1 stays gated by its own decision step.

| Change | Before | After |
|---|---|---|
| Metrics surface | `TranscriptReader` is the only read abstraction and it only supports Notes-style history/search reads (`Sources/SeshatCore/TranscriptReader.swift:3-41`). | New files under `Sources/SeshatCore/Metrics/` define `MetricsWindow`, `MetricsRollups`, `MetricsSnapshot`, `MetricsRefreshReason`, `MetricsReading`, `MetricsService`, and the transcript-commit notification name without touching existing consumers. |

Validation checklist:
- [ ] All Stage 1 source additions live only in new `Sources/SeshatCore/Metrics/` and `Tests/SeshatCoreTests/Metrics/` directories, satisfying `plans/CENTRAL_LAYERS_PROMPT.md:42-59` and `Contract C2`.
- [ ] The public metrics surface is expressible entirely from `TranscriptEntry` fields already defined at `Sources/SeshatCore/TranscriptStore.swift:3-22`, satisfying the top-of-file do-not-diverge sentence 1 and `Contract C1`.
- [ ] No existing consumer is touched in Stage 1. `Sources/SeshatAppKit/Notes/NotesWindowController.swift:37-51` and `Sources/SeshatAppKit/Notes/NotesViewModel.swift:26-45` remain unchanged while the new layer is built.

### Stage 1.2 - Implement the SQLite-backed query service and UI adapter store
Dependency arrows: `Stage 1.1 -> Stage 1.2`. No Layer 2 Stage 2 dependency is introduced yet; Stage 1 remains isolated by injecting a database URL instead of wiring production composition.

| Change | Before | After |
|---|---|---|
| Live implementation | `SQLiteTranscriptStore` exposes append/recent/count/search only (`Sources/SeshatCore/SQLiteTranscriptStore.swift:66-163`). | New `SQLiteMetricsReader` and `SQLiteMetricsService` query the same `transcripts.sqlite` read-only, and a separate `MetricsSnapshotStore` publishes rollups plus the recent list for UI binding. |

Validation checklist:
- [ ] The reader consumes the existing SQLite schema at `Sources/SeshatCore/SQLiteTranscriptStore.swift:170-197`; no `type` / `kind` / `intent` column is added, satisfying `plans/CENTRAL_LAYERS_PROMPT.md:69`, `plans/CENTRAL_LAYERS_PROMPT.md:361-363`, and `Contract C1`.
- [ ] Word counting uses Unicode word boundaries per `plans/CENTRAL_LAYERS_PROMPT.md:356`, satisfying `Contract C4`.
- [ ] `minsSaved` uses the 40 WPM baseline and clamps at zero per `plans/CENTRAL_LAYERS_PROMPT.md:357`, satisfying `Contract C4`.
- [ ] Stage 1 still does not touch `Sources/SeshatSession/SessionCoordinator.swift:220-241`, so transcript persistence remains the only write path, satisfying the top-of-file do-not-diverge sentence 1 and `Contract C1`.

### Stage 1.3 - Add isolated tests for rollup math and refresh behavior
Dependency arrows: `Stage 1.1 -> Stage 1.2 -> Stage 1.3`. This step still parallelizes with other layers' Stage 1 work because it only adds tests under the new metrics test directory.

| Change | Before | After |
|---|---|---|
| Test coverage | Existing tests cover transcript persistence, SQLite bootstrap/search, and Notes read-model wiring, but there is no rollup-math coverage (`Tests/SeshatCoreTests/SQLiteTranscriptStoreTests.swift:34-199`, `Tests/SeshatSessionTests/SessionCoordinatorTranscriptStoreTests.swift:7-27`, `Tests/SeshatAppKitTests/Notes/TranscriptReaderTests.swift:32-50`). | New tests lock the rolling window, Unicode word tokenization, `minsSaved` clamp, WPM calculation, recent-list ordering, and non-polling refresh/coalescing semantics. |

Validation checklist:
- [ ] Metrics tests reuse the transcript persistence guarantees already covered by `Tests/SeshatCoreTests/SQLiteTranscriptStoreTests.swift:34-199` rather than duplicating SQLite bootstrap logic, satisfying `Contract C1`.
- [ ] At least one characterization test proves rollups derive from transcripts appended through the current pipeline seam already covered by `Tests/SeshatSessionTests/SessionCoordinatorTranscriptStoreTests.swift:7-27`, satisfying the top-of-file do-not-diverge sentence 1.
- [ ] A service-state test proves refresh happens from explicit triggers only, not polling, using the current explicit-refresh analogue at `Sources/SeshatAppKit/Notes/NotesWindowController.swift:37-51` as the baseline to avoid timer-driven drift, satisfying the top-of-file do-not-diverge sentence 4 and `Contract C3`.

### Stage 2.1 - Swap the unified-window Home tab to bind `MetricsSnapshotStore` backed by `MetricsService`
Dependency arrows: `Stage 1.3 -> Stage 2.1`. Requires Layer 2 Stage 2 complete for centralized recordings-path wiring. Does not require Layer 4 Stage 2 because the user explicitly locked direct Home-tab binding to the metrics service. External prerequisite: the Phase 2 unified-window Home tab must exist before this step starts.

| Change | Before | After |
|---|---|---|
| Home-tab consumer | Current trunk has no checked-in Home tab. The app still ships a standalone Notes window and direct Notes reader wiring (`Sources/SeshatAppKit/Composition/SeshatAppMain.swift:170-195`, `Sources/SeshatAppKit/Notes/NotesWindowController.swift:37-51`), while the design spec expects 4 Home cards and a 3-item recent list (`plans/App UI design/Seshat UI Polish & Unified Window Implementation.md:54-57`). | The actual Home-tab file introduced by the unified-window lane binds to a `MetricsSnapshotStore` backed by `any MetricsService`, using the store's `rollups`, `recentTranscriptions`, and `isRefreshing`; refresh comes from window focus plus the single transcript-commit notification, with no direct SQLite reads or local rollup math in the view. |

Validation checklist:
- [ ] The swapped Home tab consumes the published metrics surface instead of repeating the direct store-opening pattern currently used by `Sources/SeshatAppKit/Composition/SeshatAppMain.swift:184-195` or aggregating raw `TranscriptEntry` arrays in view code, satisfying the top-of-file do-not-diverge sentences 1-4 and `Contract C1` through `Contract C5`.
- [ ] The focus refresh is attached to the unified window lifecycle, replacing the current standalone-window one-shot refresh pattern visible in `Sources/SeshatAppKit/Notes/NotesWindowController.swift:37-51`, and no polling loop is introduced, satisfying the top-of-file do-not-diverge sentence 4 and `Contract C3`.
- [ ] A single transcript-commit notification is posted only after successful persistence at the same seam currently represented by `Sources/SeshatSession/SessionCoordinator.swift:229-239`; it must not fire before the append succeeds, satisfying the top-of-file do-not-diverge sentence 4 and `Contract C3`.
- [ ] The Home tab still renders the exact Manus content contract from `plans/App UI design/Seshat UI Polish & Unified Window Implementation.md:54-57`: Words this week, Recordings, Mins saved, WPM avg, and the recent 3 transcriptions.

### Stage 2.2 - Sweep for overlapping debug-counter UI consumers
Dependency arrows: `Stage 1.3 -> Stage 2.2`. If a real debug stats surface exists when execution begins, it can migrate independently of `Stage 2.1`; otherwise this step is an explicit no-op and should not invent a consumer.

| Change | Before | After |
|---|---|---|
| Debug / diagnostic stats consumer | Current trunk inspection found no shipped AppKit or SwiftUI surface showing weekly counts or aggregate durations. The only checked-in `counter` hit is the test helper in `Tests/SeshatAppKitTests/AppStartupCoordinatorTests.swift:28-53` and `Tests/SeshatAppKitTests/AppStartupCoordinatorTests.swift:89-111`. | Any real debug stats UI that exists at execution time binds the same `MetricsSnapshotStore` snapshot as Home, backed by `MetricsService`. If no such UI exists, record a no-op in the hand-off report and make no code changes. |

Validation checklist:
- [ ] No shipped source surface outside the Home tab duplicates weekly rollup math after the swap. The currently checked-in app surfaces remain the standalone Notes flow in `Sources/SeshatAppKit/Composition/SeshatAppMain.swift:170-195` and `Sources/SeshatAppKit/Notes/NotesView.swift:43-71`, neither of which is a debug stats surface today.
- [ ] Test-only counters such as `Tests/SeshatAppKitTests/AppStartupCoordinatorTests.swift:28-53` and `Tests/SeshatAppKitTests/AppStartupCoordinatorTests.swift:89-111` stay test-only and are not treated as Layer 8 consumers.
- [ ] If an overlapping debug UI exists when implementation starts, it must satisfy `Contract C2` and `Contract C5`; if none exists, the hand-off report must say "no existing debug stats UI found on trunk" and cite the absence of any such shipped surface in `Sources/SeshatAppKit/Composition/SeshatAppMain.swift:170-195` plus the test-only nature of `Tests/SeshatAppKitTests/AppStartupCoordinatorTests.swift:28-53` and `Tests/SeshatAppKitTests/AppStartupCoordinatorTests.swift:89-111`.

### Stage 3.1 - Delete verified ad-hoc weekly rollup math and keep non-rollup duration logic
Dependency arrows: `Stage 2.1 -> Stage 3.1`. `Stage 2.2` also must be complete if a real debug stats consumer exists. This step is the Layer 8 delete pass and should remain empty if no qualifying ad-hoc rollup math exists.

Current-code enumeration for this delete pass:
- `Sources/SeshatAppKit/Notes/NotesContextPanel.swift:32-55` formats `selectedEntry.audioDuration` and `selectedEntry.processingDuration` for per-entry metadata. This is not weekly metrics math and stays.
- `Sources/SeshatSession/SessionCoordinator.swift:191-247` computes `bufferedDuration` for the recording-too-short guard and converts `Duration` to `TimeInterval` before persistence. This is session correctness logic and stays.
- No checked-in Home-tab or debug-counter weekly rollup code exists on trunk today.

| Change | Before | After |
|---|---|---|
| Delete pass | There is no verified pre-existing Home-stats rollup code on current trunk. The only inspected view/session duration calculations are per-entry metadata formatting and recording guards. | Delete only weekly word-count or duration rollup math introduced during Stage 2 consumer swaps. Do not delete unrelated per-entry duration formatting or recording guard logic. |

Validation checklist:
- [ ] The deletion set is limited to verified weekly/home-rollup code paths. `Sources/SeshatAppKit/Notes/NotesContextPanel.swift:32-55` stays because it formats per-entry durations, not layer-wide metrics, satisfying the top-of-file do-not-diverge sentence 6.
- [ ] `Sources/SeshatSession/SessionCoordinator.swift:191-247` stays because it enforces recording validity and transcript persistence, not Home metrics, satisfying the top-of-file do-not-diverge sentence 1.
- [ ] If Stage 2 introduced any local word-count or duration aggregation in the Home tab or a debug UI, those computations are removed in favor of `MetricsService`, leaving only the non-rollup computations already enumerated at `Sources/SeshatAppKit/Notes/NotesContextPanel.swift:32-55` and `Sources/SeshatSession/SessionCoordinator.swift:191-247`, satisfying `Contract C5`.
- [ ] If no qualifying ad-hoc weekly rollup code exists, Stage 3 records an empty delete set in the hand-off report and explicitly cites the current non-delete inventory at `Sources/SeshatAppKit/Notes/NotesContextPanel.swift:32-55` and `Sources/SeshatSession/SessionCoordinator.swift:191-247` rather than deleting unrelated duration code.

## Test strategy
- Unit tests: add `Tests/SeshatCoreTests/Metrics/*` coverage for rolling-window boundaries, Unicode word tokenization, `minsSaved` clamp, WPM calculation, recent-list limit/order, and refresh coalescing. Seed data should continue to use the existing `TranscriptEntry` contract at `Sources/SeshatCore/TranscriptStore.swift:3-22`.
- Integration tests: add a Stage 2 Home-tab view-model or presenter test in the unified-window lane, patterned after the current Notes read-model tests in `Tests/SeshatAppKitTests/Notes/NotesViewModelTests.swift:7-79` and `Tests/SeshatAppKitTests/Notes/TranscriptReaderTests.swift:32-50`.
- Fakes: provide a scripted `MetricsReading` fake for core tests and a scripted `MetricsService` fake for the eventual Home-tab UI tests.
- Regression guards the layer must preserve: `Tests/SeshatCoreTests/SQLiteTranscriptStoreTests.swift:34-199`, `Tests/SeshatSessionTests/SessionCoordinatorTranscriptStoreTests.swift:7-27`, `Tests/SeshatAppKitTests/ManualSQLiteVerification.md:3-37`, and the Notes metadata contract in `Tests/SeshatAppKitTests/Notes/NotesContextPanelTests.swift:6-35`.
- Manual verification: because the Home tab is SwiftUI UI work, extend the unified-window manual runbook with a Home-metrics checklist when Stage 2 lands. Until that runbook exists, `Tests/SeshatAppKitTests/ManualNotesVerification.md:11-29` is the closest checked-in pattern for transcript-history UI verification.

## Validation checklist
- [ ] Stage 1 additions are confined to new `Sources/SeshatCore/Metrics/*` and `Tests/SeshatCoreTests/Metrics/*` directories, satisfying `plans/CENTRAL_LAYERS_PROMPT.md:42-59` and `Stage 1.1`.
- [ ] No duplicate transcript write path is introduced. Persistence still flows through `Sources/SeshatSession/SessionCoordinator.swift:220-241` and `Sources/SeshatCore/SQLiteTranscriptStore.swift:66-87`, satisfying the top-of-file do-not-diverge sentence 1 and `Contract C1`.
- [ ] Home refresh is focus plus transcript-commit notification only, satisfying the top-of-file do-not-diverge sentence 4, `Contract C3`, and `plans/App UI design/Seshat UI Polish & Unified Window Implementation.md:54-57`.
- [ ] No `type` / `kind` / `intent` column is added to SQLite, anchored at `Sources/SeshatCore/SQLiteTranscriptStore.swift:170-197`.
- [ ] No existing files outside the observed spread and the explicit new metrics directories are modified.
- [ ] `swift build --build-tests` green (main session).
- [ ] All acceptance tests and manual checks named in this plan pass.

## Backlog tickets authored
- None in this planning-only commit. The implementation lane should author `plans/backlog/home-stats-metrics.md` during Stage 1 only if the placeholder contingency from `plans/CENTRAL_LAYERS_PROMPT.md:359` still needs explicit backlog tracking.

## Inter-layer dependencies
- Requires: Layer 2 Stage 2, because live composition should resolve the SQLite path through the centralized recordings-path owner before the app wires `SQLiteMetricsService`.
- Blocks: none of Layers 1-9 directly. This layer instead unblocks the real Home-tab stats swap in the unified-window work once Layer 2 Stage 2 is complete.

## Commit style
`trunk: layer 8.M: <verb-led subject>`. Test + fix in the same commit.

## Open design questions
- [QUESTION] Current trunk does not contain a checked-in Home-tab file or unified-window shell. The closest live surfaces are `Sources/SeshatAppKit/Composition/SeshatAppMain.swift:170-195` and `Sources/SeshatAppKit/Notes/NotesWindowController.swift:37-51`. Which concrete file should `Stage 2.1` target once the Phase 2 unified window lands?
- [QUESTION] The brief requires refresh on transcript-commit notification, but trunk has no such notification today. Should the single notification owner be `SessionCoordinator.persistTranscript` immediately after `try await transcriptStore.append(entry)` succeeds (`Sources/SeshatSession/SessionCoordinator.swift:229-239`), or `SQLiteTranscriptStore.append(_:)` itself (`Sources/SeshatCore/SQLiteTranscriptStore.swift:66-87`)? Pick one owner so Stage 2 does not create two notification sources.
- [QUESTION] The prompt suggests a rolling 7-day window (`plans/CENTRAL_LAYERS_PROMPT.md:365-367`), while the Home card copy says "this week" (`plans/App UI design/Seshat UI Polish & Unified Window Implementation.md:54-57`). Should the UI copy be adjusted to "last 7 days" when Layer 8 lands, or is the product intent a calendar week despite the prompt default?
- [QUESTION] The brief mentions "any existing debug counter UI that displays overlapping stats," but current trunk inspection found no such shipped source surface. If main session knows of an intended debug consumer outside current trunk, identify it before `Stage 2.2`; otherwise that step remains a documented no-op.

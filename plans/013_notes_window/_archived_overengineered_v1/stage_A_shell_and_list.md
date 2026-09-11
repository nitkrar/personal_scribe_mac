# #013 Stage A — NotesWindow Shell + Sidebar List

**Ticket #013** — NotesWindow (sidebar + editor + context panel, auto-ingested transcripts, tagging, FTS5 search).
**Stage A scope:** window shell + left sidebar list of existing transcripts + read-only center editor pane. No editing, no search wiring, no tags, no right context panel behavior, no format toolbar.

## 1. Goal

After Stage A lands, the user can open a dedicated **Ninimma Notes** window (via the existing menu-bar `History` row, which currently routes to the Transcriptions tab), see every persisted transcript in a left sidebar ordered newest-first, click any row to load its full text read-only in the center pane, and close the window. Auto-ingest is already happening upstream (pipeline → `TranscriptRepository.append`); Stage A only adds a new surface that reads the same store.

## 2. Approach

**Standalone `NSWindowController`, not a nested tab.** Mirror `UnifiedWindowController`'s `NSHostingController<RootView>` wrapped in `NSWindow` pattern so we plug into the same status-item routing without adding a SwiftUI `Scene`. Reasons: (a) Stage E adds a format toolbar + right panel that want full window chrome, (b) the mockup is visibly not a tab-in-a-tab, (c) `UnifiedWindowController`'s bug-#041 space/frame reconciliation code is the canonical pattern worth reusing verbatim.

**SwiftUI `NavigationSplitView`** (sidebar + detail) inside the hosted root view. Two columns in Stage A; the 220px right context panel is a follow-up (Stage C+). Stage A MAY reserve the third column as a `nil` detail slot so Stage C adds content without restructuring the outer split.

**New view model, `NotesWindowViewModel`.** Does NOT extend `TranscriptionsTabViewModel`. The Transcriptions tab keeps shipping; #013 ticket body explicitly positions NotesWindow as the new home for transcript history (BUG-06 in UX_Audit_Notes.md), but forking vs. deprecating the Transcriptions tab is an Open Question (§8 below) — Stage A must not regress it. New VM keeps a `@Published` entry list + `@Published selection: UUID?`; the reader dependency is `any TranscriptReading` (same protocol the Transcriptions tab uses — read-only, already wired through composition).

**Read path.** `TranscriptReading.recent(limit:)` — the protocol already used by the Transcriptions tab. No changes to `TranscriptRepository`. Stage A calls `recent(limit: 500)` or similar (larger than the 100 default since the Notes window is "the" transcript surface); actual limit + eventual pagination is a follow-up, not Stage A scope.

**Row reuse.** Reuse `Components/TranscriptRow.swift` in its existing `.detail` style. It already renders timestamp + 2-line preview and accepts an `onDelete` closure (the path #011 lands). Do NOT fork it for the sidebar in Stage A; if the sidebar-specific rendering diverges later (title derivation, selection affordance beyond list-row highlight), fork then. Derived title = first ~40 chars of text, trimmed; matches the existing `ManualNotesVerification.md` runbook phrasing.

## 3. File map

**New files (under `Sources/PersonalScribeAppKit/NotesWindow/`):**
- `/Users/nitinkum/Projects/nitkrar/personal_scribe/Sources/PersonalScribeAppKit/NotesWindow/NotesWindowController.swift` — `NSWindowController` host, bug-#041 frame reconciliation, `WindowTint` + `AppTheme` observation (copy from `UnifiedWindowController`, don't extract a shared base in Stage A).
- `/Users/nitinkum/Projects/nitkrar/personal_scribe/Sources/PersonalScribeAppKit/NotesWindow/NotesWindowControllerHost.swift` — `@MainActor ObservableObject` wrapper, factory lambda, `showWindow()` entry point — mirrors `UnifiedWindowControllerHost`.
- `/Users/nitinkum/Projects/nitkrar/personal_scribe/Sources/PersonalScribeAppKit/NotesWindow/NotesWindowView.swift` — root `NavigationSplitView(sidebar:detail:)`, reads `NotesWindowViewModel`, injects `WindowTint` env value matching Unified.
- `/Users/nitinkum/Projects/nitkrar/personal_scribe/Sources/PersonalScribeAppKit/NotesWindow/NotesWindowViewModel.swift` — `@MainActor ObservableObject`, `@Published entries`, `@Published selection: UUID?`, `load(limit:)` async, `selectedEntry: TranscriptEntry?` computed, derived-title helper.
- `/Users/nitinkum/Projects/nitkrar/personal_scribe/Sources/PersonalScribeAppKit/NotesWindow/NotesSidebarList.swift` — extracted sidebar subview (rows via `TranscriptRow` in `.detail` style, bound selection).
- `/Users/nitinkum/Projects/nitkrar/personal_scribe/Sources/PersonalScribeAppKit/NotesWindow/NotesReadOnlyEditor.swift` — center pane: title (derived) + read-only `ScrollView` of body text. Placeholder when selection is nil: "Select a transcript to view its text."

**Modified files:**
- `/Users/nitinkum/Projects/nitkrar/personal_scribe/Sources/PersonalScribeAppKit/Composition/PersonalScribeAppMain.swift` — instantiate `NotesWindowControllerHost`, rebind the existing `openTranscriptions` lambda the `History` menu-bar row dispatches to so it opens `NotesWindow` instead of selecting the Transcriptions tab. Rename closure → `openHistory` in a follow-up step within this stage's commits; keep the `AppTab.transcriptions` case reachable (Open Question §8b).

**Tests (new):**
- `/Users/nitinkum/Projects/nitkrar/personal_scribe/Tests/PersonalScribeAppKitTests/NotesWindow/NotesWindowViewModelTests.swift` — rigid TDD: load order, selection, derived title, empty state.
- `/Users/nitinkum/Projects/nitkrar/personal_scribe/Tests/PersonalScribeAppKitTests/NotesWindow/NotesWindowControllerTests.swift` — frame reconciliation parity (reuse `UnifiedWindowController.reconciledFrame` test pattern if code is duplicated; or only test the host's lazy-create + reuse contract).
- `/Users/nitinkum/Projects/nitkrar/personal_scribe/Tests/PersonalScribeAppKitTests/ManualNotesVerification.md` — UPDATE existing runbook: the current file describes the aspirational full window (sidebar + editor + right panel). Add a Stage A block with MV-NOTES-A-* IDs covering just shell + list + read-only select. Do not delete the existing rows (they describe later stages).

## 4. Navigation / window lifecycle

- **Entry points (Stage A):** the existing status-item `History` row. The menu action is `ActionID.openTranscriptions` (keep the enum case name for now; renaming is a scope cut). The dispatch in `PersonalScribeAppMain` flips from `unifiedWindowControllerHost.showWindow(selecting: .transcriptions)` to `notesWindowControllerHost.showWindow()`.
- **Keyboard shortcut:** defer. ⌘-shortcut wiring goes with the `History` rename + hotkey customization ticket. Stage A explicitly does not add a key equivalent.
- **Closing:** standard window chrome close button. `NSWindow.isReleasedWhenClosed = false` (same as Unified), controller held by `NotesWindowControllerHost` — reopens reuse the same instance.
- **State persistence:** NSWindow automatic frame save using `setFrameAutosaveName("PersonalScribeNotesWindow")`. Selection persistence across launches = follow-up (not Stage A).
- **Space/frame:** copy `UnifiedWindowController`'s `.moveToActiveSpace, .fullScreenAuxiliary` collection behavior and `reconciledFrame` logic verbatim to avoid bug-#041 regression on a new window.

## 5. TDD test strategy

**Rigid TDD (XCTest-coverable):**
- `NotesWindowViewModelTests`
  - `test_load_populatesEntriesNewestFirst` — stub `TranscriptReading` returns 3 entries; assert VM `entries` equals stub in newest-first order.
  - `test_load_withEmptyStore_publishesEmptyArray` — empty stub → empty entries, no crash.
  - `test_selection_setsSelectedEntry` — after load, set `selection = entries[1].id`, assert `selectedEntry?.id == entries[1].id`.
  - `test_selectedEntry_whenIdMismatch_returnsNil` — `selection` points at an id not in entries → `selectedEntry == nil`.
  - `test_derivedTitle_trimsAndTruncates` — body "hello world this is a very long transcript..." → title is first ~40 chars trimmed, no trailing space.
  - `test_derivedTitle_emptyText_returnsPlaceholder` — empty body → `"Untitled"` or similar.
- `NotesWindowControllerTests`
  - `test_controllerHost_reuseSameInstanceAcrossShowCalls` — two `showWindow()` calls → factory invoked once.
  - (Frame reconciliation — only add if we duplicate the helper; if we can `@testable import` the `reconciledFrame` static from UnifiedWindowController without dupe, skip.)

**Manual-verify-only (flexible TDD, runbook entries):** SwiftUI `NavigationSplitView` rendering, sidebar resize behavior, row selection highlight, read-only text scroll, title bar shows "Ninimma Notes" (or brand-name-derived), dark/light appearance parity, WindowTint forwarding, menu-bar `History` opens the new window not the old tab.

**Manual runbook filename:** `/Users/nitinkum/Projects/nitkrar/personal_scribe/Tests/PersonalScribeAppKitTests/ManualNotesVerification.md` — reuses existing file; new rows prefixed `MV-NOTES-A-01` through `MV-NOTES-A-06` (matches existing MV-PUX/MV-* conventions). Proposed rows:
- MV-NOTES-A-01: Menu `History` opens the new NotesWindow (not Transcriptions tab).
- MV-NOTES-A-02: Sidebar lists all persisted transcripts newest-first.
- MV-NOTES-A-03: Empty-state placeholder in sidebar and center pane.
- MV-NOTES-A-04: Clicking a row loads its full text in the center pane (read-only).
- MV-NOTES-A-05: Closing and reopening the window preserves frame + reuses the controller.
- MV-NOTES-A-06: Dark/Light/Warm/Neutral tint parity matches the UnifiedWindow.

## 6. Commit shape

Tag prefix: `#013 step 1.N:` (Stage A is step 1). Target 4 commits:

1. **`#013 step 1.1: NotesWindowViewModel + unit tests`** — VM + `NotesWindowViewModelTests`. Red-green-green (tests + impl together; file ManualNotes entry stub).
2. **`#013 step 1.2: NotesWindowController + host`** — controller, host wrapper, duplicate frame-reconcile helper if needed, controller tests. No menu wiring yet.
3. **`#013 step 1.3: NotesWindow SwiftUI shell + sidebar + read-only editor`** — `NotesWindowView`, `NotesSidebarList`, `NotesReadOnlyEditor`. No automated tests (SwiftUI rendering).
4. **`#013 step 1.4: route History menu to NotesWindow + manual runbook`** — edit `PersonalScribeAppMain` dispatch, update `ManualNotesVerification.md` with MV-NOTES-A-*.

If step 1.2 gets bulky (controller + host + tests > ~250 lines), split into 1.2a (controller) + 1.2b (host + tests) → 5 commits total.

## 7. Dependencies on other stages

- **Upstream:** none. #013 depends on #026 (SQLite — done) and Phase 3.A Modes (done). Stage A adds no new dependency.
- **#011 (delete path) coupling:** Stage A plan assumes #011 is merged before execution. `TranscriptRow` already carries `onDelete: (() -> Void)?`; Stage A passes `nil` for it in the sidebar OR forwards a VM delete closure that mirrors `TranscriptionsTabViewModel.delete(id:)`. Decision: **pass `nil` in Stage A** — deletion surfaces in Stage B+ alongside editing affordances. Rationale: keeps Stage A collision-surface with `slate` smaller.
- **Downstream stages built on Stage A's scaffolding:**
  - Stage B: editing (swap `NotesReadOnlyEditor` for an editable surface; VM gains `save(entry:)`).
  - Stage C: search field wiring + right context panel (add third `NavigationSplitView` column).
  - Stage D: tagging UI (sidebar sections, pill chips in editor).
  - Stage E: format toolbar.

## 8. Open questions

**(a) Right context panel in Stage A: empty 220px pane, or omit entirely?**
Recommendation: **omit**. Keep Stage A as a 2-column `NavigationSplitView`. Adding an empty right column reserves screen real estate for a feature that blocks on #020/#022/#069 (Phase 4), and `NavigationSplitView` can be restructured 2→3 columns cleanly in Stage C. Dissent-worthy; confirm before Stage A starts.

**(b) What happens to the Transcriptions tab once NotesWindow ships?**
Stage A keeps it alive (reachable via `AppTab.transcriptions` in the unified window, just no longer wired to the menu-bar `History` row). Longer-term: deprecate + delete. Need a small follow-up ticket (or a later Stage of #013) to actually remove it. Recommendation: **do not delete in Stage A** — it's the fallback if the new window regresses during dogfood.

**(c) Window-restore-on-relaunch behavior.**
NSWindow auto-save restores frame but not selection. Stage A: frame only. Selection restore = follow-up. Acceptable?

## 9. Scope cuts within Stage A

- **Sidebar sections beyond RECENT:** flat list only. No "TAGS" section (Stage D), no "PINNED" (future), no date-bucketed headers. Just a `List` bound to `viewModel.entries` with `selection:`.
- **Search field placeholder:** do NOT render a search `TextField` in Stage A, even as a non-functional stub. Prevents user confusion + avoids a UI surface that then needs Stage C rewiring.
- **"+ New Note" button:** not in Stage A. Transcripts arrive via auto-ingest from the pipeline; a blank-new-note affordance is a manual-edit feature (Stage B+).
- **Related / Action Items / Linked Recordings / Ask Ninimma pane:** deferred as §8a above.
- **Format toolbar + Auto-transcribed / meeting chips:** mockup shows these; defer to Stages D/E.
- **"Source: Voice recording" footer:** deferred (needs audio-sidecar wiring, ticket #069).

## 10. Risks

- **Swift 6 strict concurrency on NSWindow.** `UnifiedWindowController` already solved the `@MainActor` boundary + `isolated deinit` pattern; duplicating it should be mechanical, but `NSHostingController<NotesWindowView>` re-render on `WindowTint` changes needs the same observer pattern as `UnifiedWindowController.applyWindowTint()` (rebuilds the root view). Easy to forget.
- **SwiftUI `NavigationSplitView` quirks on macOS 14.** Sidebar collapse behavior, initial-focus mistakes, and `List` selection binding with `UUID?` all have known Sonoma edge cases. Mitigation: keep the split-view naive; manual runbook covers resize/collapse paths.
- **Menu-bar `History` collision with `AppTab.transcriptions` case name.** The `ActionID.openTranscriptions` enum case now dispatches to a non-Transcriptions surface — confusing for future readers. Scope cut: don't rename in Stage A; leave a `// TODO: rename to .openHistory in #013 Stage B` comment.
- **Worktree/cherry-pick collision with #011 (owner `slate`).** #011 touches `TranscriptRepository.swift` + `TranscriptionsTabViewModel.swift` + `TranscriptRow` (adds hover-delete). Stage A does NOT touch any of these in its modified-files list — only `PersonalScribeAppMain.swift` (routing). Brief Stage A implementer: read `slate`'s latest trunk before executing; cherry-pick replays cleanly as long as we don't also edit `TranscriptRow`.
- **`ManualNotesVerification.md` pre-existing content.** The file currently describes the aspirational full NotesWindow. Stage A must append a "Stage A" section rather than replace — the existing rows are contracts for Stages B-E.
- **NSWindow autosave name collision.** Choose a unique name (`"PersonalScribeNotesWindow"`); do not reuse `"PersonalScribeUnifiedWindow"` or similar — autosave clashes silently overwrite frames across windows.

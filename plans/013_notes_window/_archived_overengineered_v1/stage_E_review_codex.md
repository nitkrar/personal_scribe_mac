# Stage E review (codex)

## Verdict
block pending Stage B

## Critical issues (if any)
- §5 Editor bridging and §8 Dependencies assume Stage B will expose stable selection/focus APIs and likely move to an `NSViewRepresentable`/`NSTextView` editor, but Stage B §5 only defines `draftTitle`, `draftBody`, `isDirty`, and `lastSaveError`, and Stage B §7 still plans a `TextField`/`TextEditor` view layer. That is not a stable substrate for Enter-to-continue-list, active-format highlighting, or selection-aware toggles. Grep in `Sources/` found only one `NSViewRepresentable` (`Overlay/VisualEffectBlur.swift`), and it is a trivial blur wrapper, not reusable text-system infrastructure. Reconcile Stage B first, then lock Stage E to that concrete editor contract.
- §3 Enabled-state logic, §4 Formatting semantics, and §5 Editor bridging never explain how toolbar clicks preserve the current editor selection. In a SwiftUI/AppKit bridge, clicking `B` or opening the link popover can steal first-responder status from `NSTextView` before the action runs, which collapses the very selection the formatter is meant to mutate. Add an explicit selection snapshot/restore strategy and a non-focus-stealing toolbar interaction model before implementation.

## Medium concerns
- §2 Storage-format decision overstates "human-readable on disk" as user value. In this app the note lives in SQLite, so that argument is mostly developer convenience. If Markdown stays, justify it on backward compatibility and export/interchange, not disk legibility.
- §2 and §8 acknowledge FTS coupling, but the mitigation is loose relative to Stage C §2, §4, and §6, which already fix FTS5 to raw `transcripts.text` with `unicode61`. The real search leak is not the `**` punctuation itself, which tokenizes away, but raw Markdown payloads such as link destinations. Spell out whether Stage E accepts source-mode URL hits, or explicitly schedule the Stage C follow-up instead of calling it "cheap to fix later."
- §4.2 Bullet-list semantics will behave badly on mixed multi-line selections because the current rule toggles each line independently. A selection containing one bullet line and one plain line will invert into zebra state. The plan should define the standard all-or-none rule: if all selected lines are bulleted, unbullet all; otherwise bullet all.
- §6 TDD strategy is too ASCII-happy for string/range surgery. There is no coverage for emoji, combining marks, or IME/marked-text composition, yet §4 and §5 rely on precise selection math after inserting Markdown markers. Add formatter tests for extended grapheme clusters and a manual IME case in §11.
- §6 points Stage E at `Tests/PersonalScribeAppKitTests/ManualNotesWindowVerification.md`, but the repo already has `Tests/PersonalScribeAppKitTests/ManualNotesVerification.md`, and Stage B §6 and Stage C §7 use that existing file. Fix the runbook path now to avoid needless churn.

## Minor nits
- §2 and §4 talk about a `body` TEXT column / `body: String`, but Stage B and Stage C use `text` for the persisted field. Tighten the naming before implementation so the formatter API does not drift from the repository contract.
- §7 uses `#013 step 5.N:` tags, which does not match the repo commit convention in the project guidance (`phase-N step N.M:`).
- §7 is slightly mis-ordered. The pure formatter engine is the most stable part of the work; the toolbar chrome in `5.1` depends on the unresolved Stage B focus/selection contract and is likely to churn first.

## Scope / approach disagreements
- I would split the boundary differently: first land a pure Markdown formatter/command layer with tests, then add toolbar UI once the Stage B editor bridge is real. §3 through §5 currently bundle storage choice, text-system bridge, keyboard routing, active-state detection, and popover UX into one stage on top of an editor substrate that is still in flux.

## What the plan does well
- §1 and §10 keep the feature cut disciplined. Excluding headings, tables, colours, strikethrough, and live-preview is the right restraint for a first formatting pass.
- §4 and §6 keep formatter logic out of storage writes and point toward pure string/range transforms, which is the right shape for rigid TDD.
- §3 uses live theme tokens that exist in the current tree (`Palette.surface`, `Palette.brandChampagne`, `Radius.sm`) instead of blindly following the informational `SeshatTheme.swift` bundle.
- The keyboard-collision audit is directionally fine: grep in `Sources/` found no existing in-app `⌘K` binding, so the real shortcut risk is responder routing, not a repo-local conflict.

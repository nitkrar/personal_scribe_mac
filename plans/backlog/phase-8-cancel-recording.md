# Phase 8 — true cancel-without-transcribe for active recording

**Status**: Open, brainstorm pending
**Raised**: 2026-04-21 session (after pill UX Phase 6 ship)
**Depends on**: Pill UX Phases 1-6 (all on trunk, commits `8095ed4`…`e412bf8`)

## Context

Pill UX spec §3 says pressing Esc or clicking ✕ during a recording should "Discard audio; enter `.cancelled`; show Cancel Card" — the audio captured so far is thrown away, no transcription runs, nothing is pasted. The user's pre-recording clipboard is then restored by the Cancel Card's Undo button (already working via `PasteboardSnapshotService`, Phase 5).

**What shipped in Phase 6 instead**: Esc calls `SessionCoordinator.toggle()`, which stops capture via the normal transcribe path. The audio IS transcribed and auto-pasted. Cancel Card shows for 4 seconds; Undo restores the user's pre-recording clipboard, effectively undoing the paste. Worst-case UX: transcript got pasted into the user's target app, Undo puts their original clipboard back but doesn't un-type what was pasted into the app's text field. User needs to Cmd+Z in the target app separately.

## Reason for deferral

`SessionCoordinator` only exposes `toggle()`. No cancel path. True cancel means threading a new method through:

1. `SessionCoordinator.cancelRecording()` — public entry point.
2. `SessionPipelining` protocol — new `cancelCapture()` contract.
3. `SessionPipelineOrchestrator.cancelCapture()` — stops the audio capture actor, discards the buffer, transitions straight to `.idle` (NOT `.transcribing`).
4. Tests for every layer.

Estimated effort: half a day for the plumbing + tests. Small enough to do in a focused session, too disruptive to bundle with the existing pill-UX phase sequence without a clean checkpoint.

## User's comment (2026-04-21)

> "Does it require a lot of work. I think this is a choice. Esc still transcribes (gives us undo option) the cross button on the [pill]. Actually lets brain storm it later."

## Brainstorm seed — Esc / ✕ semantic split

One option on the table that would accept the current Phase 6 behaviour as shipped:

- **Esc** = "cancel but keep the transcript in case I change my mind" → current Phase 6 behaviour: transcribe + paste + Cancel Card with Undo. Friendly, low-stakes.
- **✕ (cross button on the recording pill)** = "I mean it, throw the audio away" → true discard via `SessionCoordinator.cancelRecording()`. Strong destructive action, matched by its direct-click affordance.

Advantages:
- Esc is often hit accidentally; pasting + offering Undo is forgiving.
- ✕ requires a deliberate pointer gesture; true discard is less likely to surprise.
- Phase 6 doesn't need to be rewritten — only ✕'s wiring changes.

Disadvantages:
- Mental model is split; two "cancel" affordances behaving differently needs discoverable wording / tooltips.
- Doesn't match the spec §3 table as literally written.

Alternative: implement true discard everywhere (spec-literal), accepting the bigger change set.

## Minimum implementation surface for true discard

If we decide to do it:

1. `Sources/PersonalScribeSession/Pipeline/Contracts/SessionPipelining.swift` — add `func cancelCapture() async`.
2. `Sources/PersonalScribeSession/Pipeline/Orchestrator/SessionPipelineOrchestrator.swift` — implement: stop capture actor, drop in-memory buffer, transition state machine directly from `.recording → .idle` without going through `.transcribing`.
3. `Sources/PersonalScribeSession/SessionCoordinator.swift` — expose `public func cancelRecording() async` that calls `pipeline.cancelCapture()` and applies the snapshot.
4. `Sources/PersonalScribeAppKit/Composition/PersonalScribeAppMain.swift` — Esc (and ✕ if we go that way) wires to `coordinator.cancelRecording()` instead of `coordinator.toggle()`.
5. Tests in `Tests/PersonalScribeSessionTests/` for the orchestrator path; tests in `Tests/PersonalScribeAppKitTests/` for the composition wiring.
6. `ManualPillOverlayVerification.md` — update MV-PUX-10 / 11 / 14 to assert "no transcript is pasted" as part of the Cancel Card flow.

Keep this backlog entry until the brainstorm happens.

# Investigation brief — 3 dogfood regressions, post-2026-05-19 work

**Type**: Investigation only (no code changes). Identify root causes + propose fixes.
**Project**: nitkrar/personal_scribe (Ninimma)
**Trunk HEAD**: `05fe679` (as of dispatch)
**Mode**: Independent investigation — surface root cause + 1-2 fix candidates per bug. Do NOT implement.

---

## Symptoms reported (verbatim from user)

### Bug 1 — Parakeet streaming mode: live stream broken

> "for parkeet streaming mode we broke the live stream. nothing is working now as part of fixes we did today we broker something"

User believes today's commits caused the break. Need to verify the suspicion or rule it out.

### Bug 2 — WhisperKit live cursor + final paste

User dictated; system pasted special tokens during live cursor stream, then a different (duplicated) final text at the end.

**Live paste** (what landed in the cursor while speaking):
```
[COUGHING]Let's see what's happening.This is actually the case.
[Pause] [Unintelligible]
```

**Final paste** (what landed at session end):
```
I don't know what's happening. This is actually the case. I don't know what's happening. I don't know what's happening. I don't know what's happening.
```

Two distinct concerns:
- Special tokens (`[COUGHING]`, `[Pause]`, `[Unintelligible]`) leaking into live paste despite the strip logic in commit `30afc64`.
- Final-paste text is partially correct but heavily duplicated.

### Bug 3 — whisper.cpp: phantom "Thank you" + duplication

User dictated; system inserted "Thank you" prefix even when no audio was being said, and duplicated chunks across live + final paste.

**Live paste**:
```
Thank you. I don't know why it always starts late. I don't know why it always starts with thank youI don't know why it always starts late. Thank you. ʰἀἀἀἀI don't know why I've been pasting this time to multiple times.
```

**Final paste**:
```
I don't know why it always starts with thank you I don't know why I've been tasting this thank you multiple times.
```

Two concerns:
- Phantom "Thank you" prefix (classic whisper hallucination on silent/near-silent audio).
- Duplication across live + final.

---

## What changed recently (commit history is ground truth)

### Today (2026-05-19) — atlas + hermes on #069 + #094 chunk 1

- `4c0e09a` ManagedDirectory.db + transcripts.sqlite relocation
- `f2d2bb9` v6 audio_filename column + TranscriptEntry field
- `4cf2ade` RecordingFileWriter
- `a31cff0` pref-gated audio persistence in orchestrator ← **only commit touching `SessionPipelineOrchestrator`**
- `571f0ea` cascade audio delete in TranscriptRepository
- `ac6b49d` Recordings card in AdvancedTab
- `3ed36d3` RecordingRetentionSweeper
- `8ccba69` MV-REC entries
- `40ee1da` locked-contract test fixup
- `580a6d0` BACKLOG + AppConfig comment
- `15ff9f3` archive #010 + #027 + #033
- `05fe679` FileSourceAudioStream (chunk 1 of #094)

### Yesterday + before — streaming work

- `c167155` separate FluidAudio EOU pastes (testSubsequentEndOfUtterancePrependsLeadingSpace)
- `364851d` gate silent whispercpp decodes and dedupe regrouped replay
- `30afc64` strip WhisperKit streaming special tokens
- `00c9b4c` add whispercpp streaming adapter
- `5a0df9e` add WhisperKit streaming adapter

Read these via `git log` / `git show <hash>` in the canonical repo path.

---

## What you need to do

For each of the 3 bugs:

1. **Find the most likely root cause.** Use commit history + code reading. Don't speculate without evidence.
2. **Identify the suspect commit(s) and lines.** Cite `file:line` or commit hash. Concrete.
3. **Propose 1-2 fix candidates** with tradeoffs. Don't write the fix — describe what would need to change.
4. **Flag if it's actually stale-install user error.** Several of these symptoms (special tokens, "Thank you" hallucination, duplication) match bugs the recent streaming commits explicitly fixed. If your evidence suggests the user is running an older binary that pre-dates those fixes, say so directly — "rebuild + reinstall" is a valid root cause to surface.

### Specific things to consider

**For Bug 1 (Parakeet streaming break):**
- The only commit today that touches `SessionPipelineOrchestrator.swift` is `a31cff0` (chunk 4 of #069). It added `recordingFileWriter`, `recordAudioEnabled`, `recordingsDirectory` injection + a new `persist(_:replayBuffers:)` body that runs the WAV write before `persistenceHandler(entry)`.
- Did that change accidentally block, stall, or break a code path that streaming sessions depend on?
- Streaming sessions go through `runBoundProcessing` with `replayBuffers + finishedLiveStreamingState`. Does the new `persist()` signature/path affect that?
- Could the new `recordingsDirectory` default closure (`try AppConfig.recordingsDirectory()`) be throwing for a reason that didn't matter before?
- Compare `persist()` before + after `a31cff0`. Is there any behavioral difference for streaming-path callers?
- Also worth checking: did the `audioFilename: audioFilename` new field on `TranscriptEntry.init` accidentally swap a positional arg in any test or call site?

**For Bug 2 (WhisperKit special-token leak + duplication):**
- Commit `30afc64` (`phase-6 step 6.5: strip WhisperKit streaming special tokens`) added the strip logic. Read it. Does the strip cover ALL the special tokens shown (`[COUGHING]`, `[Pause]`, `[Unintelligible]`), or only some subset (e.g. `<|...|>` token markers)?
- Bracket-style tokens (`[COUGHING]`) are *transcription content* WhisperKit emits, distinct from `<|...|>` model control tokens. Different strip path.
- For the final-paste duplication: look at where final text is produced for streaming sessions. There's a `secondPass` path (#056 design) — does it overlap with already-streamed text in a way that duplicates?
- Check `Sources/PersonalScribeTranscription/Adapters/WhisperKit*Adapter*.swift` for the strip logic.

**For Bug 3 (whisper.cpp "Thank you" + duplication):**
- Commit `5504f51` removed `params.detect_language = true` to fix an empty-transcript bug; documented as fixing whisper.cpp's exit-after-language-detect behavior.
- But "Thank you" hallucination on silent audio is a known whisper.cpp / Whisper-model artifact when the decoder runs on silence. The fix is usually a VAD pre-gate or a no-speech-probability check.
- Commit `364851d` added "gate silent whispercpp decodes". Does that gate actually fire for the silence at the very start of recording? Read the gating logic + check the threshold.
- For duplication: same question as Bug 2 — second pass vs streamed text overlap.

### Investigation deliverable format

Return a single message structured like:

```
## Bug 1 — Parakeet streaming
**Verdict**: <real bug | stale install | inconclusive>
**Evidence**: <file:line, commit hash, what you observed in the code>
**Root cause**: <one paragraph>
**Fix candidates**:
- A. <description + tradeoff>
- B. <description + tradeoff>

## Bug 2 — WhisperKit
<same structure>

## Bug 3 — whisper.cpp
<same structure>

## Cross-cutting observations
<anything that affects 2 or 3 of the bugs together, e.g. a shared streaming path>
```

Keep it tight — no rambling. Atlas needs to act on this.

---

## Constraints

- **Read-only**. No code changes. No commits. No file writes outside your own scratch notes (don't ship them to atlas).
- Read the actual code at `/Users/nitinkum/Projects/nitkrar/personal_scribe/`. Don't rely on memory or training data for what the code does.
- Cite commit hashes + file:line for everything. "I think" without a citation is not useful.
- If you're inconclusive on a bug, say so — don't guess.
- **You and a peer investigator have been dispatched in parallel on this same brief. Don't coordinate. Independent investigations are the point.**

## What atlas will do with your findings

I'll compare your investigation against the parallel investigator's. Differences in verdict / root-cause / fix candidates are exactly the value of dual-investigation. I synthesize, choose a fix path, and either fix in this session or file a new ticket.

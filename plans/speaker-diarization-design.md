# Speaker Diarization — Design Notes

Background + Q&A for the speaker-ID / diarization cluster: #058, #059, #060, #061. Captures the 2026-04-22 design session that locked the scope reshape (merged #049 into #060).

This is a design doc, not a plan. No step-by-step. Tickets carry the actual work.

---

## The four tickets in this cluster

| Ticket | Mechanism | Answers |
|---|---|---|
| **#058** Speaker diarization (LS-EEND) | Single end-to-end model. Streaming. | "Different voices, count them 1–N. Who? Don't know." |
| **#059** Dual-track recording | Hardware: mic on one channel, system audio on another. | "Me vs everything-else-on-the-call" — in remote meetings only. |
| **#060** Voice identification + speaker DB *(absorbed #049 on 2026-04-22)* | Voiceprint matching (Pyannote / WeSpeaker). | "That's Alice. That's Bob. That's me." |
| **#061** Meeting mode | Composition of the above. | "Transcribe a Zoom call with everyone labeled by name." |

---

## Q&A from the design session

### Q1 — Do #049 (me-vs-other) and #058 (LS-EEND) do the same thing, just differently?

They cover overlapping problem space but use **different models with different capabilities.** Not one feature at two speeds.

- **#049** plugged into FluidAudio's classical Pyannote pipeline: voice-activity detection → segmentation → speaker-embedding model (WeSpeaker) → agglomerative clustering. The pipeline has a `initializeKnownSpeakers()` seam — hand it a pre-recorded voiceprint, and clustering anchors one cluster to "me."
- **#058** is an end-to-end neural model — one forward pass, no separate embedding/clustering stages. Streaming-capable. No native enrollment-for-"me" mechanism in the same sense.

So #058 is not "realtime me-vs-other." They're different toolchains with different strengths. #058 wins for unnamed-cluster meeting-mode UX; #049-style voiceprint enrollment wins for reliably anchoring "me."

### Q2 — Doesn't dual-track (#059) give me "me vs others" for free?

Partially. Dual-track separates audio at the hardware level: your mic on one channel, system audio on another. If you're in a Zoom/Teams call, mic ≈ "me" and system ≈ "everyone else on the call." No model cost.

But it only works in **remote-meeting topology**:

| Scenario | Does dual-track identify me? |
|---|---|
| Zoom / Teams call, you alone at your mic | Yes |
| In-person meeting (multiple people speak into your mic) | No — everyone's on the mic channel |
| Solo dictation with someone walking in and interrupting | No — interrupter on mic channel |
| Dictating notes while a podcast plays | Yes — you on mic, podcast on system |

Dual-track says "whoever talks into this mic is me." Voiceprint matching says "whoever's voice matches this signature is me, regardless of which mic." Different anchors, different failure modes.

### Q3 — So what does voice-based identification (the #049/#060 family) add over dual-track?

- Works in-person (one mic, multiple bodies).
- Works for pure-mic recordings with no system audio.
- Works for solo-dictation-plus-interruption.
- Voiceprint is portable — future recordings also know "me" without relying on channel topology.
- Scales to named others (Alice, Bob) across sessions — not just a binary.

### Q4 — If #049 already stores my voiceprint, what was #060 supposed to add?

**#049** stored ONE voiceprint (mine) for a binary label: `me` vs `other` (everyone else lumped together).

**#060** was the same plumbing scaled up to N voiceprints with named labels: `me` / `Alice` / `Bob` / `unknown`.

The only real difference was the scope of the voiceprint DB: 1 vs N. The enrollment code, the matching code, the diarizer seeding — all identical.

### Q5 — Then what's the point of keeping them separate?

No good reason. Hence the reshape.

---

## Locked decision (2026-04-22)

**#049 is superseded by #060.** One ticket for all voiceprint-based speaker identification, whether the user is tagging "me" or "Alice."

### Why this is cleaner

- Same plumbing: storing 1 voiceprint and storing N voiceprints is the same code. Splitting into two tickets duplicates the design + the test matrix.
- No dedicated "Enroll my voice" ceremony: voice registration for "me" can happen via any existing recording. User records something → diarizer clusters the audio → user tags a cluster "me" → voiceprint saved. Same flow as tagging Alice.
- Clearer mental model for the product: "Ninimma learns your voices as you go." Not two features, one feature.

### UX shape under the merged ticket

**Stage A (minimum):**

- After any recording where diarization found > 1 cluster (or duration exceeds a threshold), show a post-stop prompt: *"Tag speakers for this recording?"*
- User sees each cluster represented by a short audio snippet. Types a name for each (or skips).
- On save: voiceprint saved to `<AppConfig.baseDirectory()>/speakers.json` as `{ name, embedding, enrolledAt, source }`.
- On subsequent recordings: diarizer seeded with all stored voiceprints via `initializeKnownSpeakers`. Matched clusters auto-label. Unmatched → `speaker 2` / `speaker 3` etc., user can retroactively tag.
- Solo-dictation (1 cluster) doesn't prompt — too noisy.

**Stage B (dogfood-gated):**

- Settings UI for DB management: rename, delete, merge speakers.
- Threshold tuning for match confidence.
- Low-confidence warnings ("this doesn't strongly match any known speaker — re-enroll?").
- Optional auto-label first-time "me" if there's one very frequent solo-speaker cluster.

### What's NOT in scope

- Realtime / streaming voice ID. #060's diarizer runs post-stop (Pyannote pipeline is batch). If we want streaming named-speaker labeling in the pill, that's separate — would layer LS-EEND (#058) or a streaming WeSpeaker variant on top.
- Full meeting-mode UX (Zoom/Teams auto-detect, dual-track capture, etc). That's #061.

---

## Final sequencing + dependencies

```
          #060  Voice ID + speaker DB (ABSORBS #049)
              │    voiceprint enrollment, Pyannote pipeline
              │    tag-from-recording UX, no enrollment ceremony
              │    P2 open, standalone
              │
              ▼ enables named-speaker labels across sessions
              │
          #061  Meeting mode
              ▲    Zoom/Teams auto-detect + dual-track + diarization + naming
              │    composes the cluster
              │    P3 parked
              │
              ├── depends on #060 (voice IDs)
              ├── depends on #058 (cluster count inside system-audio track)
              └── depends on #059 (hardware channel split)

          #058  LS-EEND diarization
              │    P3 parked. Used by #061 on the system-audio track to split
              │    "remote participants collective" into individual speakers.

          #059  Dual-track recording
              │    P2 open. Cheap me-vs-system split for remote meetings.
              │    Standalone — doesn't need #060 or #058 to be useful.
```

### Dependency notes

- **#060 is standalone.** Can ship independently; gives voiceprint-based naming for any recording (meeting or solo-with-interruption or in-person).
- **#058 is standalone.** Gives unnamed clusters. Only really shines when composed with #059 (for meeting mode) or as a precursor to streaming named-speaker UX later.
- **#059 is standalone.** Hardware separation alone gives useful me-vs-others for remote meetings without any ML.
- **#061 composes all three** but none of them block each other. #061 ships last.

### Why this sequencing makes sense

1. **Ship #060 first** because it's the most self-contained voice-identification primitive and directly serves the Memory/Learning pillar of `COMPETITIVE.md`. No `ScreenCaptureKit`, no streaming-model complexity, just "know whose voice is whose across recordings."
2. **Ship #059 next** when meeting mode is actually a priority — it's small, hardware-based, gives a big UX win in remote-meeting scenarios.
3. **Ship #058** when either (a) the meeting mode scope demands N-speaker-per-track clustering, or (b) streaming realtime speaker labels become a desired UX upgrade on top of #060.
4. **Ship #061** last — it's the product-facing feature that makes the previous three visible.

---

## Open unknowns (carry into #060 implementation planning)

- **Pyannote pipeline size + peak RAM** on disk. Measure by downloading `FluidInference/speaker-diarization-coreml` once; log the numbers in `plans/_legacy/BACKLOG_pre_migration.md`'s successor.
- **Speaker-threshold tuning.** Default `0.65` in FluidAudio docs — may be too permissive or too strict for 1-voice DBs. Test with a handful of real voiceprints.
- **Prompt noise.** How often does the "tag speakers?" post-stop prompt actually fire, and how annoying is it? Duration threshold + cluster-count threshold both tune this. Settle defaults during dogfood.
- **Solo-dictation heuristic.** If >90% of sessions are solo, should we auto-label the dominant speaker as "me" after the first N sessions without asking? That's a Stage B call.
- **Clustering anchor vs auto-match.** Pyannote's `initializeKnownSpeakers` biases clustering — but if a new speaker's voice is close-enough to an enrolled one, will it wrongly merge? Worth a confusion-matrix pass before trusting auto-labels.

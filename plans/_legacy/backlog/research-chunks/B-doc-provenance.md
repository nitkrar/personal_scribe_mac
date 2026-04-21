# B — Documented provenance of `PrivateModelDownloader`

Research-only. Sweeping the checked-in docs (proposals, decision logs, review bundles,
plans, backlog, explorations) for any written claim that `PrivateModelDownloader`
exists to support whisper.cpp / multilingual / a second engine.

## Hits by file

### The downloader's design rationale (the one file that actually specifies it)

`plans/SPEC_model_registry_and_base_dir.md` — the document that authored the
descriptor-driven `PrivateModelDownloader` in its current shape.

- `plans/SPEC_model_registry_and_base_dir.md:1` — title: "Spec: Model Registry +
  Configurable Base Directory".
- `plans/SPEC_model_registry_and_base_dir.md:9` — "**Multi-model support.**
  Current code hardcodes `parakeet-tdt-0.6b-v2` in three places … Adding a second
  model (e.g. `parakeet-tdt-110m` for lower-RAM devices) requires parallel editing
  + drift risk."
- `plans/SPEC_model_registry_and_base_dir.md:10` — "**Configurable storage root.**
  Users who want their models under `~/Documents/Seshat/` … should be able to
  override the default."
- `plans/SPEC_model_registry_and_base_dir.md:38-42` — stubs
  `enum TranscriptionEngine { case parakeetTDT ; // Reserve shape for future
  engines (parakeetCTC, whisper, etc.). // Do not implement them now. }`.
- `plans/SPEC_model_registry_and_base_dir.md:193-223` — the body that literally
  declares `internal struct PrivateModelDownloader: ModelDownloading`. The
  stated goal of this MODIFY is "descriptor-driven downloader" — same logic,
  "replace every `ParakeetArtifact.X` with `descriptor.X`." No whisper mention
  in the downloader section.
- `plans/SPEC_model_registry_and_base_dir.md:223` — "Acceptance: downloader
  behaves identically for the existing parakeet model. Swapping `descriptor` to
  a hypothetical second model changes only the URL/filename set, not the logic."

### Step-level plan describing the downloader change

- `plans/PLAN_PHASES.md:133-142` — "Step 1.7 — `FluidAudioTranscriber` + downloader
  take `ModelDescriptor` … Delete `enum ParakeetArtifact`; replace with
  descriptor-driven flow." Names `FluidAudio*` as the types that take the
  descriptor; no whisper framing.

### Central-layers refactor — where the downloader is catalogued as scope

- `plans/CENTRAL_LAYERS_PROMPT.md:296` (Layer 6 Why) — "`ModelRegistry` has one
  descriptor. `FluidAudioInferenceClient.swift:26` hardcodes `version: .v2`.
  Parked 3.F work (parakeet-tdt-110m second descriptor) blocked on adapter
  refactor. User wants multi-model + active selection + swap."
- `plans/CENTRAL_LAYERS_PROMPT.md:304` — "`download(_ descriptor: ModelDescriptor,
  progress:) async throws` — wraps existing `FluidAudioModelDownloader`."
- `plans/CENTRAL_LAYERS_PROMPT.md:306-307` — second/third descriptors named are
  `parakeet-tdt-ctc-110m` and `parakeet-tdt-0.6b-v3-coreml`. Both Parakeet; no
  whisper.
- `plans/central/LAYER_2_storage.md:35` — downloader row: "The downloader computes
  its own staging directory from the model root, creates destination parents,
  writes files atomically one-by-one, and renames the staged model directory
  into place."
- `plans/central/LAYER_2_storage.md:158-163` (Step 2.12) — "FluidAudioModelDownloader
  … The downloader operates only on app-owned roots … and explicitly does not
  touch `.build/checkouts/FluidAudio`."
- `plans/central/LAYER_6_model_selection.md:20` — "Downloader is descriptor-bound
  and writes model artifacts into the descriptor directory."

### Where whisper.cpp is discussed in plan/proposal docs (NOT tied to the downloader)

- `PROPOSAL.md:59` — v0.2 Pillar-1 item: "whisper.cpp fallback for non-English
  languages".
- `PROPOSAL.md:152` — architecture box labelled "whisper.cpp (fallback) — For
  non-English languages (v0.2+)".
- `PROPOSAL.md:195` — tech stack: "**STT Fallback** | whisper.cpp (v0.2+) |
  Non-English languages, GGML models".
- `PROPOSAL.md:212` — data layout: "whisper-ggml/ (v0.2+, downloaded on demand)".
- `PROPOSAL.md:232` — Premium tier: "Parakeet + whisper.cpp large … Multi-language
  + LLM simultaneous".
- `PROPOSAL.md:318` — Phase 4 checklist: "whisper.cpp fallback for non-English".
- `PROPOSAL.md:330` — decisions table: "STT Engine | Parakeet-TDT 0.6B v2 via
  FluidAudio; whisper.cpp fallback | Confirmed".
- `DECISIONS.md:9` — Decision #3 same: "Parakeet-TDT 0.6B v2 via FluidAudio
  (primary), whisper.cpp fallback for unsupported languages".
- `BACKLOG.md:224` — "Non-English ASR → existing `whisper.cpp integration for
  non-English` (Future). Parakeet v3 already covers 25 European languages as an
  alternative."
- `BACKLOG.md:240` — Future list: "whisper.cpp integration for non-English".
- `plans/seshat_stt_eval-claude.md:20` / `:41` — ranks whisper.cpp as option #5;
  explicitly says shipping whisper.cpp directly is "Pure cost, no benefit for a
  3-week v0.1."
- `plans/seshat_stt_eval-codex.md:18` / `:27` — ranks whisper.cpp as option #3;
  "materially higher effort".

### Where a `TranscriptionEngine` swap protocol was explicitly rejected

- `DECISIONS.md:51` — Rejected Alternatives row: "`TranscriptionEngine protocol
  (swap engines)` | Different APIs, model formats; adds complexity for no v0.1
  payoff".
- `REVIEW.md:9-44` — §1 "The Protocol-Based WhisperKit-to-whisper.cpp Swap … Do
  not plan for the swap. Pick one engine and commit to it."
- `REVIEW.md:353` — risk table: "WhisperKit -> whisper.cpp swap | HIGH".
- `REVIEW.md:371` — "Kill the engine swap. Pick WhisperKit or whisper.cpp and
  commit. The protocol abstraction is not worth the engineering cost for an app
  at this stage."
- `REVIEW_SYNTHESIS.md:70-72` — "### The Engine Swap Protocol Is Premature …
  Every technical reviewer flagged this."
- `REVIEW_SYNTHESIS.md:159` — removed-from-v0.1 list: "Engine swap protocol
  (commit to WhisperKit)".
- `REVIEW_SYNTHESIS.md:172` — "Drop the TranscriptionEngine protocol."
- `REVIEW_SYNTHESIS.md:213` — "Engine swap protocol premature (4/5) | Commit to
  WhisperKit, no protocol abstraction".

### How FluidAudio's own downloader API is framed in the exploration docs

- `explorations/voiceink_claude.md:176` — VoiceInk "Download state tracked in
  UserDefaults (`ParakeetModelDownloaded_<name>`). Cache directory managed by
  `AsrModels.defaultCacheDirectory(for:)`." (VoiceInk delegates the cache to
  FluidAudio — contrast with Ninimma.)
- `explorations/voiceink_claude.md:350` — "`AsrModels.downloadAndLoad(version:)`
  for download".
- `explorations/voiceink_claude.md:536-539` — "Download: `AsrModels.downloadAndLoad(
  version:)` — managed by FluidAudio SDK … SDK doesn't provide real progress".
- `plans/seshat_stt_eval-claude.md:9` — "the working loop is ~4 lines
  (`AsrModels.downloadAndLoad` → `AsrManager(config:)` → `loadModels` →
  `transcribe(samples)`)".
- `plans/seshat_stt_eval-codex.md:8` — "a small `AsrModels.downloadAndLoad()`
  plus `AsrManager.transcribe(...)` loop".

None of those docs contain a written reason for why Ninimma replaced
`AsrModels.downloadAndLoad` with its own `PrivateModelDownloader`.

### Adjacent research chunk (parallel B/C split — read for completeness)

- `plans/backlog/research-chunks/C-git-engine-design.md:1-7` — "Research-only.
  Answers whether the custom downloader can be reused for a future whisper.cpp
  / multilingual engine, or whether whisper.cpp will need its own downloader
  regardless …"
- `plans/backlog/research-chunks/C-git-engine-design.md:34-37` — "No commit
  ever proposed turning `PrivateModelDownloader` into an engine-abstract
  pipeline. The refactors since step 1.7 have been about Stage-2 injection /
  dependency-inversion (so tests can substitute a fake) — not about swapping
  the download medium."
- `plans/backlog/research-chunks/C-git-engine-design.md:59-62` — "No commit
  body mentions whisper, ggml, gguf, llama.cpp, multilingual, or a future
  non-HF fetch medium."
- `plans/backlog/research-chunks/C-git-engine-design.md:232-234` —
  "`PrivateModelDownloader` was designed to be **descriptor-driven, not
  engine-agnostic.**"

## Classification

**Absent → with a tilt toward Contradictory.**

- No document I found says the custom downloader exists because whisper.cpp /
  multilingual / a second engine is coming. The two places that actually specify
  the downloader (`plans/SPEC_model_registry_and_base_dir.md:193-223` and
  `plans/PLAN_PHASES.md:133-142`) motivate it entirely as:
  1. un-hardcoding `parakeet-tdt-0.6b-v2` so a **second Parakeet** variant
     (`parakeet-tdt-110m`, `parakeet-tdt-0.6b-v3-coreml`) can drop in;
  2. supporting a configurable base directory so model artifacts live under
     a user-chosen root (`~/Documents/Seshat/` etc.).
  Both are "multi-model within the same engine family" motivations — not
  multi-engine.
- **Contradictory tilt:** the `TranscriptionEngine` swap protocol — which would
  be the natural home for "second engine" reasoning — was explicitly rejected
  in `DECISIONS.md:51`, `REVIEW.md:371`, and `REVIEW_SYNTHESIS.md:70-172` before
  the downloader was even written. whisper.cpp in `PROPOSAL.md` / `BACKLOG.md`
  is catalogued as a v0.2+ / "Future" item, never linked to the downloader.
- The `TranscriptionEngine { case parakeetTDT ; // Reserve shape for future
  engines (parakeetCTC, whisper, etc.) }` comment at
  `plans/SPEC_model_registry_and_base_dir.md:40-42` (also reproduced in the
  committed source per research chunk C) is the only written hint of future
  engines. It reserves **enum shape**, not downloader behaviour, and both
  chunk C and every plan doc emphasise "Do not implement them now."

## Direct quotes most relevant to user question

1. `plans/SPEC_model_registry_and_base_dir.md:9`
   > "Multi-model support. Current code hardcodes `parakeet-tdt-0.6b-v2` in
   > three places (Config.swift:6, FluidAudioModelDownloader.swift:5-7,
   > FluidAudioTranscriber.swift:44-48). Adding a second model (e.g.
   > parakeet-tdt-110m for lower-RAM devices) requires parallel editing + drift
   > risk."

2. `plans/SPEC_model_registry_and_base_dir.md:223`
   > "Acceptance: downloader behaves identically for the existing parakeet
   > model. Swapping `descriptor` to a hypothetical second model changes only
   > the URL/filename set, not the logic."

3. `DECISIONS.md:51`
   > "TranscriptionEngine protocol (swap engines) | Different APIs, model
   > formats; adds complexity for no v0.1 payoff"

4. `REVIEW.md:371`
   > "Kill the engine swap. Pick WhisperKit or whisper.cpp and commit. The
   > protocol abstraction is not worth the engineering cost for an app at this
   > stage."

5. `plans/CENTRAL_LAYERS_PROMPT.md:296, 306-307`
   > "ModelRegistry has one descriptor. FluidAudioInferenceClient.swift:26
   > hardcodes version: .v2. Parked 3.F work (parakeet-tdt-110m second
   > descriptor) blocked on adapter refactor. User wants multi-model + active
   > selection + swap … Migrate: register a second parakeet-tdt-ctc-110m
   > descriptor … Manus v3 upgrade: register parakeet-tdt-0.6b-v3-coreml …"

## Conclusion

The documented rationale for `PrivateModelDownloader` is **multi-Parakeet-model
support and a configurable base directory**, not whisper.cpp / multilingual /
a second engine. The two load-bearing specs (`SPEC_model_registry_and_base_dir.md`
and `PLAN_PHASES.md` Step 1.7) motivate the downloader entirely through the
Parakeet 0.6B v2 → 0.6B v3 → CTC-110m progression, and Layer 6 of the central
refactor keeps that frame (same three Parakeet descriptors, explicit `version:
.v2` unhardcoding). Where whisper.cpp appears in `PROPOSAL.md`, `DECISIONS.md`,
`BACKLOG.md`, and the STT-eval notes it is framed as a v0.2+ / Future non-English
fallback engine — never tied to the downloader — and the `TranscriptionEngine`
swap protocol that would have justified an engine-agnostic downloader was
explicitly rejected in `DECISIONS.md:51`, `REVIEW.md:371`, and
`REVIEW_SYNTHESIS.md:70-172`. The user's recollection that the downloader was
written to enable whisper.cpp / multilingual is therefore an unwritten
rationale; the written record says it exists to support a second Parakeet
variant and a user-overridable `models/` directory.

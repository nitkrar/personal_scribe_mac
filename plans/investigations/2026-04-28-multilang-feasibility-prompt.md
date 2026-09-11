# Multi-language voice model feasibility — Codex prompt

**Use**: paste this into a fresh codex CLI session at the repo root, or hand to a fresh codex-rescue subagent. Output target: `plans/investigations/2026-04-28-multilang-feasibility-codex.md` (overwrite if exists).

---

**Research-only task — no code changes, no builds, no tests.** Output a markdown report at `/Users/nitinkum/Projects/nitkrar/personal_scribe/plans/investigations/2026-04-28-multilang-feasibility-codex.md`. Stop conditions: report written + path printed. Hard cap: 15 minutes wall-clock — if FluidAudio source isn't quickly findable, report that and stop.

# Goal
Determine the feasibility and effort of wiring per-mode language selection through to the FluidAudio batch ASR adapters for our multilingual descriptors (Parakeet TDT 0.6B v3 — 25 EU languages; Qwen3 0.6B ASR f32 + int8 — 16 languages incl. EN/ZH/JA/KO/VI/TH/ID/MS/HI/AR/TR/RU/DE/FR/ES).

# Context
The Ninimma project (this repo at `/Users/nitinkum/Projects/nitkrar/personal_scribe`) is building a Modes editor where each Mode (recipe) can target a specific language. Today our `Transcriber` protocol takes only `PCMBuffer`:

```swift
// Sources/PersonalScribeCore/Transcription/Transcriber.swift
public protocol Transcriber: ModelLifecycle, Sendable {
    var capabilities: TranscriberCapabilities { get }
    func transcribe(_ audio: PCMBuffer) async throws -> TranscriptionResult
}
```

The four FluidAudio adapters live at `Sources/PersonalScribeTranscription/Adapters/`:
- `FluidAudioParakeetTranscriberAdapter.swift` (batch, parakeet-tdt-0.6b-v2 + v3)
- `FluidAudioQwenTranscriberAdapter.swift` (batch, qwen3-asr f32 + int8)
- `FluidAudioStreamingTranscriberAdapter.swift` (streaming, parakeet-realtime)
- `FluidAudioDiarizerAdapter.swift` (diarization)

Model descriptors (with `worksWith` strings hinting at language coverage) are in `Sources/PersonalScribeCore/Models/Selection/BuiltInModelCatalog.swift`.

FluidAudio is a Swift package dependency. Find its checkout (likely under `.build/checkouts/FluidAudio`, `~/Library/Developer/Xcode/DerivedData/.../SourcePackages/checkouts/FluidAudio`, or look at `Package.resolved` for the resolved version) and read the source for:
- `AsrManager` / `AsrModels.transcribe(...)` — Parakeet path
- `Qwen3AsrManager.transcribe(...)` — Qwen3 path
- Any `language` / `locale` / `targetLanguage` parameters or model-loading variants per language

# Required output

1. **API support — does FluidAudio accept a per-call language hint?**
   - For Parakeet TDT v3: yes/no, exact API signature, what values it accepts (BCP-47 strings? enum cases?), default.
   - For Qwen3 ASR: same.
   - For streaming Parakeet (parakeet-realtime): yes/no.
   - If it's a model-load-time parameter (not per-call), say so — that has very different cost.

2. **What languages each model supports.** Cite the model card / FluidAudio source enums. Confirm Parakeet v3 = 25 EU langs (enumerate which ones), Qwen3 = 16 langs (enumerate). Note Parakeet v2 (English-only) and any monolingual descriptors that should hide the picker.

3. **Required schema/protocol changes in our codebase**, ranked by blast radius:
   - `ModelDescriptor` — add `supportedLanguages: [String]?` (BCP-47, nil = monolingual)?
   - `Transcriber` / `StreamingTranscriber` protocol — extend `transcribe(_:language:)` (default = primary)?
   - The four adapters — what code changes are needed to plumb the hint?
   - Recipe schema (`WorkflowMode` / `ProcessorSpec`) — add a `language: String?` field on the transcriber processor?
   - `RecipeBuilder` / `BoundRecipe` — how does the bound language reach the adapter at session start?

4. **Effort estimate**: S (≤ ½ day) / M (½ – 1.5 day) / L (> 1.5 day), with the breakdown.

5. **Blockers / unknowns**: anything that could surprise us (e.g. FluidAudio loads language-specific weights only when constructed with a language code, so changing language = full model reload + re-prepare; or: the language hint is only consulted when calling a specific decode variant; or: streaming model doesn't support language hints at all).

6. **Recommendation**: should this land bundled with the Modes editor ticket, or split into a follow-up?

# Constraints
- Read-only. Do not run `swift build`, do not modify files, do not write tests.
- If FluidAudio source isn't accessible, say so and stop — do not infer from API names alone.
- Keep the report under ~500 lines. Lead with the recommendation, then the evidence.
- Cite file paths + line numbers for every claim about FluidAudio internals.
- **Hard cap: 15 minutes.** If you're past 5 grep/read iterations and still don't have the FluidAudio source, write a "FluidAudio source not found at expected paths" report and stop.

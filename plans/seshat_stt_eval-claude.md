# STT Engine Recommendation — Claude's evaluation

## Primary recommendation
**Engine**: **Parakeet-TDT 0.6B v2 via FluidAudio**

**Why** (3 sentences):
1. On English dictation — the only language v0.1 ships — Parakeet-TDT v2 is objectively the most accurate open model available today: ~1.69% WER on LibriSpeech test-clean and the #1 slot on the HF Open ASR leaderboard at 6.05% avg WER, ahead of every Whisper variant WhisperKit can ship (NVIDIA model card; HF leaderboard).
2. FluidAudio runs it entirely on the Apple Neural Engine with roughly 66 MB working RAM and an RTF near 0.005 on M-series silicon, which easily fits the 8 GB tier with headroom and gives sub-500 ms toggle-mode latency trivially (MacParakeet; FluidAudio README).
3. Integration cost is minimal and MIT-compatible: FluidAudio is Apache-2.0, a first-party Swift 6 SwiftPM package, and the working loop is ~4 lines (`AsrModels.downloadAndLoad` → `AsrManager(config:)` → `loadModels` → `transcribe(samples)`); the underlying NVIDIA weights are CC-BY-4.0, which permits MIT app distribution with attribution.

## Biggest honest caveat
FluidAudio is a young, small-team project (v0.12.x as of April 2026, ~48 releases in its first year) and the Parakeet-v2 CoreML conversion is maintained by that same team on HuggingFace. A solo dev shipping in 3 weeks is betting on a dependency that could churn its API, break CoreML compatibility on a future macOS point release, or stop being maintained. Mitigation: pin the exact FluidAudio minor version and vendor the CoreML `.mlmodelc` artifacts in a versioned release rather than relying on first-run HF downloads at runtime. Also verify disk size on the HF repo before shipping — the MLX variant is ~2.5 GB, and while the ANE CoreML build is much smaller, I could not find a published exact MB figure and the 300 MB budget is a hard constraint; if the CoreML package exceeds ~400 MB, fall back to WhisperKit distil-small.en.

## Alternatives considered, ranked
| Rank | Engine | Rejection reason |
|---|---|---|
| 2 | **WhisperKit (distil-small.en or large-v3-turbo)** | Strong fallback and more mature (v0.18, MIT, 35 releases). But distil-small.en is ~3–4% WER behind Parakeet-v2 on leaderboard benchmarks, and Argmax's best ANE result (2.2% WER) requires large-v3-turbo at ~600 MB, which violates the 500 MB download cap. Keep as Plan B. |
| 3 | **Apple SpeechAnalyzer / DictationTranscriber (iOS 26 / macOS 26 API)** | Would be the obvious choice if the app targeted macOS 26+, but v0.1 targets macOS 14 Sonoma+. Not available. |
| 4 | **Apple SFSpeechRecognizer (on-device)** | Available on macOS 14, zero install, zero disk — but Apple explicitly documents on-device accuracy is worse than server, 1000 req/hr rate limit, known bugs where pauses wipe transcripts on `isFinal=false`, and the API is effectively deprecated in favor of SpeechAnalyzer. Unacceptable for a product whose core value prop is dictation quality. |
| 5 | **whisper.cpp directly (ggml-org/whisper.spm)** | MIT, mature, CoreML encoder on ANE is real. But you end up rebuilding what WhisperKit already gives you (model download UX, Swift ergonomics, streaming buffers) for no accuracy or latency win over WhisperKit, and strictly worse accuracy than Parakeet. Pure cost, no benefit for a 3-week v0.1. |
| 6 | **parakeet-mlx** | Same model as pick #1 but runs on GPU/MLX: ~2 GB RAM vs 66 MB on ANE, no Swift SDK, Python-oriented. Strictly dominated by FluidAudio for this app. |

## Evidence summary
- **Accuracy (English)**: Parakeet-v2 1.69% clean / 6.05% avg (HF Open ASR leaderboard, May 2025). Whisper large-v3-turbo via WhisperKit ANE-tuned = 2.2% WER (Argmax ICML 2025). distil-small.en ≈ within 3–4% WER of large-v2. SFSpeechRecognizer: Apple documents on-device mode as less accurate than server; no public benchmark.
- **Latency**: FluidAudio Parakeet reports ~0.13 s end-to-end dictation latency, ~80 ms compute on M-series (MacParakeet, Apr 2026). WhisperKit 150–300 ms. Both clear the sub-500 ms bar; FluidAudio has margin.
- **Integration cost**: FluidAudio Swift API is 4 lines; WhisperKit is 3 lines. whisper.cpp via whisper.spm is ~30–50 lines for equivalent UX. SFSpeechRecognizer ~20 lines but with permission plumbing.
- **License**: FluidAudio Apache-2.0 + Parakeet CC-BY-4.0 → MIT-compatible with attribution. WhisperKit MIT. whisper.cpp MIT. Apple Speech = Apple SDK license (fine). All candidates pass.
- **Model size**: Parakeet CoreML (ANE) — MB figure unverified but significantly smaller than 2.5 GB MLX build; needs confirmation. WhisperKit distil-small.en ~166M params ≈ ~200 MB GGML/CoreML. tiny ~75 MB. large-v3-turbo ~600 MB (over budget).
- **Runtime RAM**: Parakeet on ANE ≈ 66 MB working (MacParakeet). WhisperKit base ≈ 180 MB loaded + 100–200 MB activations. Both fit 8 GB tier; Parakeet is notably lighter.
- **Apple Silicon opt**: FluidAudio runs ANE-only (no GPU/MPS), which is optimal for always-on dictation power draw. WhisperKit uses ANE + GPU. whisper.cpp ANE encoder + CPU decoder.

Sources:
- [FluidInference/FluidAudio](https://github.com/FluidInference/FluidAudio)
- [FluidInference/parakeet-tdt-0.6b-v2-coreml](https://huggingface.co/FluidInference/parakeet-tdt-0.6b-v2-coreml)
- [nvidia/parakeet-tdt-0.6b-v2 model card](https://huggingface.co/nvidia/parakeet-tdt-0.6b-v2)
- [MacParakeet: Whisper to Parakeet on Neural Engine](https://macparakeet.com/blog/whisper-to-parakeet-neural-engine/)
- [argmaxinc/WhisperKit](https://github.com/argmaxinc/WhisperKit)
- [distil-whisper/distil-small.en](https://huggingface.co/distil-whisper/distil-small.en)
- [Apple SFSpeechRecognizer docs](https://developer.apple.com/documentation/speech/sfspeechrecognizer)
- [WWDC25: SpeechAnalyzer](https://developer.apple.com/videos/play/wwdc2025/277/)
- [ggerganov/whisper.cpp](https://github.com/ggerganov/whisper.cpp)

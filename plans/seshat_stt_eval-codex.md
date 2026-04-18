# STT Engine Recommendation — Codex's evaluation

## Primary recommendation
**Engine**: Parakeet-TDT 0.6B v2 via FluidAudio
**Why** (3 sentences):
1. It has the best directly published English accuracy I could verify here: 1.69% WER on LibriSpeech test-clean, 3.19% on test-other, plus punctuation/capitalization built in (https://huggingface.co/nvidia/parakeet-tdt-0.6b-v2).
2. For toggle-mode dictation on Apple Silicon, the CoreML port is explicitly ANE-optimized and vendor-reported at about 110x real time on M4 Pro, which makes sub-500ms post-stop text plausible for short utterances on modern Macs (https://github.com/FluidInference/FluidAudio, https://huggingface.co/FluidInference/parakeet-tdt-0.6b-v2-coreml; inference).
3. Integration is still solo-dev-friendly: Swift Package Manager, macOS 14+, a small `AsrModels.downloadAndLoad()` plus `AsrManager.transcribe(...)` loop, and about 442 MiB of primary model weights, which stays under your hard pain threshold (https://github.com/FluidInference/FluidAudio, https://huggingface.co/FluidInference/parakeet-tdt-0.6b-v2-coreml; artifact-size inference).

## Biggest honest caveat
You need to pin the exact shipping artifact and notices before release: the FluidAudio SDK is Apache-2.0, but the v2 CoreML model card is CC-BY-4.0, so MIT app distribution is workable only if you carry attribution obligations with the model. Also, the best speed number I found is vendor-reported on M4 Pro, while the model card lists about 800MB peak RAM, so v0.1 should be smoke-tested on the 8GB floor before freezing the choice (https://github.com/FluidInference/FluidAudio/blob/main/LICENSE, https://huggingface.co/FluidInference/parakeet-tdt-0.6b-v2-coreml).

## Alternatives considered, ranked
| Rank | Engine | Rejection reason |
|---|---|---|
| 1 | WhisperKit | Excellent Swift/MIT fit, but the current OSS docs recommend `large-v3-v20240930_626MB`; even distil variants in the model repo are ~594-600MB, and OSS docs do not publish comparable WER/RAM for English dictation (https://github.com/argmaxinc/argmax-oss-swift, https://huggingface.co/argmaxinc/whisperkit-coreml). |
| 2 | Apple Speech framework | Lowest integration cost, but Apple explicitly says on-device recognition is less accurate, and availability is locale/device dependent through `supportsOnDeviceRecognition` (https://developer.apple.com/documentation/speech/sfspeechrecognitionrequest/requiresondevicerecognition, https://developer.apple.com/documentation/speech/sfspeechrecognizer/supportsondevicerecognition). |
| 3 | whisper.cpp directly | MIT and well documented, but Swift integration is materially higher effort and strong Whisper configs push size/RAM up fast (`small.en` 466 MiB/~852 MB; `large-v3-turbo-q5_0` 547 MiB) (https://github.com/ggml-org/whisper.cpp, https://github.com/ggml-org/whisper.cpp/blob/master/models/README.md). |
| 4 | Moonshine Voice | Viable surfaced option for English-only MIT use, but the public macOS path looks more release-example-oriented than SPM-native, and its biggest advantage is streaming, not stop-then-insert dictation (https://github.com/moonshine-ai/moonshine). |
| 5 | Vosk | Very small offline models, but I found no convincing current Apple-Silicon optimization or modern English dictation evidence versus Parakeet/Whisper-class systems (https://github.com/alphacep/vosk-api; inference). |

## Evidence summary
- Accuracy: Parakeet v2 has the strongest directly reported English numbers in this set: LS clean 1.69%, LS other 3.19%, AMI 11.16%, Earnings-22 11.15%, plus punctuation/capitalization (https://huggingface.co/nvidia/parakeet-tdt-0.6b-v2). WhisperKit/whisper.cpp docs do not report equivalent engine-level WER (https://github.com/argmaxinc/argmax-oss-swift, https://github.com/ggml-org/whisper.cpp).
- Latency: FluidAudio reports about 110x RTF on M4 Pro for Parakeet CoreML; sub-500ms after stop is therefore plausible for short dictation, but that last claim is inference, not a published E2E benchmark (https://huggingface.co/FluidInference/parakeet-tdt-0.6b-v2-coreml; inference).
- Integration cost: Apple is simplest, WhisperKit next, FluidAudio still manageable, whisper.cpp highest-complexity because of C/C++ bridging and optional CoreML generation steps (Apple docs, https://github.com/argmaxinc/argmax-oss-swift, https://github.com/FluidInference/FluidAudio, https://github.com/ggml-org/whisper.cpp).
- License: FluidAudio SDK Apache-2.0; WhisperKit MIT; whisper.cpp MIT; Parakeet v2 model CC-BY-4.0; Apple framework is platform SDK, so no separate OSS engine license blocker surfaced (LICENSE files and Apple docs; Apple point is inference).
- Size: Parakeet v2 primary weights total about 442 MiB from published artifact headers; WhisperKit recommends a 626MB large-v3 model; whisper.cpp spans 75 MiB `tiny(.en)` to 547 MiB `large-v3-turbo-q5_0` (https://huggingface.co/FluidInference/parakeet-tdt-0.6b-v2-coreml, https://github.com/argmaxinc/argmax-oss-swift, https://github.com/ggml-org/whisper.cpp/blob/master/models/README.md).
- Peak RAM: Fluid v2 model card says about 800MB peak; whisper.cpp publishes ~388MB for `base`, ~852MB for `small`, ~3.9GB for `large`; WhisperKit OSS docs do not report RAM (https://huggingface.co/FluidInference/parakeet-tdt-0.6b-v2-coreml, https://github.com/ggml-org/whisper.cpp).
- Apple Silicon optimization: FluidAudio explicitly targets ANE; whisper.cpp supports Metal plus Core ML/ANE encoder offload; WhisperKit is CoreML-based on macOS 14+; Apple Speech is native but hardware details are opaque (https://github.com/FluidInference/FluidAudio, https://github.com/ggml-org/whisper.cpp, https://github.com/argmaxinc/argmax-oss-swift, Apple docs).

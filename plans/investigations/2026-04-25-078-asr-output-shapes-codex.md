## 1. AsrManager.transcribe(_:source:)
`source` is `AudioSource` with cases `.microphone` and `.system`; `AsrManager` uses it to select/reset separate decoder state, not to change `ASRResult`'s shape (`Shared/AudioSource.swift:3`, `Shared/AudioSource.swift:4`, `Shared/AudioSource.swift:5`, `ASR/Parakeet/AsrManager.swift:37`, `ASR/Parakeet/AsrManager.swift:42`, `ASR/Parakeet/AsrManager.swift:50`, `ASR/Parakeet/AsrManager.swift:445`).

| field | type | notes | file:line |
|---|---|---|---|
| `text` | `String` | transcript text | `ASR/Parakeet/AsrTypes.swift:42` |
| `confidence` | `Float` | overall confidence; computed from mean token-level softmax probabilities | `ASR/Parakeet/AsrTypes.swift:43`, `ASR/Parakeet/AsrManager+TokenProcessing.swift:5`, `ASR/Parakeet/AsrManager+TokenProcessing.swift:22` |
| `duration` | `TimeInterval` | audio duration | `ASR/Parakeet/AsrTypes.swift:44` |
| `processingTime` | `TimeInterval` | wall-clock processing time | `ASR/Parakeet/AsrTypes.swift:45` |
| `tokenTimings` | `[TokenTiming]?` | token-level timing only. `TokenTiming` fields: `token`, `tokenId`, `startTime`, `endTime`, `confidence`; no word/segment struct in this return type | `ASR/Parakeet/AsrTypes.swift:46`, `ASR/Parakeet/AsrTypes.swift:94`, `ASR/Parakeet/AsrTypes.swift:95`, `ASR/Parakeet/AsrTypes.swift:96`, `ASR/Parakeet/AsrTypes.swift:97`, `ASR/Parakeet/AsrTypes.swift:98`, `ASR/Parakeet/AsrTypes.swift:99` |
| `performanceMetrics` | `ASRPerformanceMetrics?` | optional. Nested fields: `preprocessorTime`, `encoderTime`, `decoderTime`, `totalProcessingTime`, `rtfx`, `peakMemoryMB`, `gpuUtilization` | `ASR/Parakeet/AsrTypes.swift:47`, `Shared/PerformanceMetrics.swift:4`, `Shared/PerformanceMetrics.swift:5`, `Shared/PerformanceMetrics.swift:6`, `Shared/PerformanceMetrics.swift:7`, `Shared/PerformanceMetrics.swift:8`, `Shared/PerformanceMetrics.swift:9`, `Shared/PerformanceMetrics.swift:10`, `Shared/PerformanceMetrics.swift:11` |
| `ctcDetectedTerms` | `[String]?` | optional vocabulary-boosting metadata | `ASR/Parakeet/AsrTypes.swift:48` |
| `ctcAppliedTerms` | `[String]?` | optional vocabulary-boosting metadata | `ASR/Parakeet/AsrTypes.swift:49` |

## 2. StreamingEouAsrManager
| field | type | notes | file:line |
|---|---|---|---|
| `process(audioBuffer:)` return | `String` | always returns `""`; chunk decoding updates internal state/callbacks instead | `ASR/Parakeet/Streaming/EOU/StreamingEouAsrManager.swift:355`, `ASR/Parakeet/Streaming/EOU/StreamingEouAsrManager.swift:381`, `ASR/Parakeet/Streaming/EOU/StreamingEouAsrManager.swift:382` |
| `finish()` return | `String` | final transcript from `tokenizer.decode(ids: accumulatedTokenIds)` | `ASR/Parakeet/Streaming/EOU/StreamingEouAsrManager.swift:385`, `ASR/Parakeet/Streaming/EOU/StreamingEouAsrManager.swift:408`, `ASR/Parakeet/Streaming/EOU/StreamingEouAsrManager.swift:413` |
| `partial` event | `@Sendable (String) -> Void` | `PartialCallback`; emits current accumulated partial transcript when new tokens arrive | `ASR/Parakeet/Streaming/EOU/StreamingEouAsrManager.swift:157`, `ASR/Parakeet/Streaming/EOU/StreamingEouAsrManager.swift:159`, `ASR/Parakeet/Streaming/EOU/StreamingEouAsrManager.swift:245`, `ASR/Parakeet/Streaming/EOU/StreamingEouAsrManager.swift:517`, `ASR/Parakeet/Streaming/EOU/StreamingEouAsrManager.swift:518`, `ASR/Parakeet/Streaming/EOU/StreamingEouAsrManager.swift:519` |
| `EOU` event | `@Sendable (String) -> Void` | `EouCallback`; fires after debounce with transcript-so-far | `ASR/Parakeet/Streaming/EOU/StreamingEouAsrManager.swift:153`, `ASR/Parakeet/Streaming/EOU/StreamingEouAsrManager.swift:155`, `ASR/Parakeet/Streaming/EOU/StreamingEouAsrManager.swift:239`, `ASR/Parakeet/Streaming/EOU/StreamingEouAsrManager.swift:542`, `ASR/Parakeet/Streaming/EOU/StreamingEouAsrManager.swift:543`, `ASR/Parakeet/Streaming/EOU/StreamingEouAsrManager.swift:547`, `ASR/Parakeet/Streaming/EOU/StreamingEouAsrManager.swift:548`, `ASR/Parakeet/Streaming/EOU/StreamingEouAsrManager.swift:549` |
| `eouDetected` | `Bool` | public flag for confirmed EOU | `ASR/Parakeet/Streaming/EOU/StreamingEouAsrManager.swift:194` |
| internal chunk result | `DecodeResult` | not returned by manager; fields are `tokenIds: [Int]` and `eouDetected: Bool`. No timestamps, confidences, or segment objects | `ASR/Parakeet/Streaming/RnntDecoder.swift:5`, `ASR/Parakeet/Streaming/RnntDecoder.swift:7`, `ASR/Parakeet/Streaming/RnntDecoder.swift:9`, `ASR/Parakeet/Streaming/RnntDecoder.swift:143` |

## 3. Qwen3AsrManager
| field | type | notes | file:line |
|---|---|---|---|
| value | `String` | all public `transcribe` overloads return plain transcript text. The manager decodes generated token IDs to `text` and `return text`; timing breakdown is logged internally, not returned. No timestamps, confidences, token probabilities, or segment metadata are surfaced | `ASR/Qwen3/Qwen3AsrManager.swift:45`, `ASR/Qwen3/Qwen3AsrManager.swift:58`, `ASR/Qwen3/Qwen3AsrManager.swift:71`, `ASR/Qwen3/Qwen3AsrManager.swift:122`, `ASR/Qwen3/Qwen3AsrManager.swift:125`, `ASR/Qwen3/Qwen3AsrManager.swift:129` |

Common subset across all three: no shared named fields; the only common datum is transcript text.

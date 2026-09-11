1. Verdict: yes streaming

2. Part A — Source Evidence

File/class search results:
- Exact name heuristic: I found no file basename or declared type name that simultaneously contains one of `Streaming|Online` and one of `Diarization|Speaker`. The shipped streaming diarization surface is instead exposed under `SortformerDiarizer`, `LSEENDDiarizer`, and `LSEENDStreamingSession`.
- `Sources/FluidAudio/Diarizer/Sortformer/SortformerDiarizer.swift:6-12` declares `public final class SortformerDiarizer: Diarizer` and documents it as `/// Streaming speaker diarization using NVIDIA's Sortformer model.`
- `Sources/FluidAudio/Diarizer/LS-EEND/LSEENDDiarizer.swift:5-9` declares `public final class LSEENDDiarizer: Diarizer` and documents it as `/// Speaker diarization using LS-EEND (Linear Streaming End-to-End Neural Diarization).` plus `/// Supports both streaming and offline processing, matching the 'SortformerDiarizer' API`.
- `Sources/FluidAudio/Diarizer/LS-EEND/LSEENDModelInference.swift:176-183,455-540` exposes a stateful streaming engine: `public func createSession(inputSampleRate: Int) throws -> LSEENDStreamingSession`, then `LSEENDStreamingSession.pushAudio(_:)` and `finalize()`.
- `Sources/FluidAudio/Diarizer/DiarizerTimeline.swift:9-15,28-52,65-90` defines `public protocol Diarizer: AnyObject` with both streaming methods (`addAudio`, `process`) and whole-buffer methods (`processComplete`).
- `Sources/FluidAudio/Diarizer/DiarizerTimeline.swift:594-640,1260-1273` defines the streaming output shape already in source: `DiarizerChunkResult` carries `finalizedPredictions` plus `tentativePredictions`, and `DiarizerTimelineUpdate` carries `finalizedSegments`, `tentativeSegments`, and the underlying `chunkResult`.
- The streaming paths are exercised in tests, not just sketched in docs: `Tests/FluidAudioTests/Diarizer/Sortformer/SortformerStreamingIntegrationTests.swift:22-50` and `Tests/FluidAudioTests/Diarizer/LS-EEND/LSEENDIntegrationTests.swift:65-113,207-220`.

LS-EEND / EEND reference search results:
- `Documentation/README.md:24` links LS-EEND explicitly: `- [LS-EEND](Diarization/LS-EEND.md)`.
- `Documentation/API.md:78-86` says `SortformerDiarizer` and `LSEENDDiarizer` provide `a unified streaming and offline API`; `Documentation/API.md:125-136` describes `LSEENDDiarizer` as `Streaming diarization using LS-EEND`.
- `Documentation/Models.md:44-45` says both `LS-EEND` and `Sortformer` `Supports both streaming and complete-buffer inference`.
- `README.md:345-347` says LS-EEND is the `Default choice for online diarization` and `Supports both streaming and complete-buffer processing.`
- `Documentation/Diarization/LS-EEND.md:1-5` titles the feature `LS-EEND Streaming Speaker Diarization` and describes an `online attractor decoder`.
- The implementation lives under `Sources/FluidAudio/Diarizer/LS-EEND/`: `LSEENDDiarizer.swift`, `LSEENDModelInference.swift`, `LSEENDPreprocessor.swift`, and `LSEENDDatatypes.swift` (`Documentation/Diarization/LS-EEND.md:148-153` lists the same module layout).
- The local LS-EEND docs cite the research paper directly: `Documentation/Diarization/LS-EEND.md:642` references `Di Liang, Xiaofei Li. LS-EEND: Long-Form Streaming End-to-End Neural Diarization with Online Attractor Extraction.`

OfflineDiarizerManager public API (verbatim signatures):
- `OfflineDiarizerManager` itself is batch-oriented. In `Sources/FluidAudio/Diarizer/Offline/Core/OfflineDiarizerManager.swift:15-119`, the public surface is:

```swift
public init(config: OfflineDiarizerConfig = .default)

public func initialize(models: OfflineDiarizerModels)

public func prepareModels(
    directory: URL? = nil,
    configuration: MLModelConfiguration? = nil,
    forceRedownload: Bool = false
) async throws

public func process(audio: [Float]) async throws -> DiarizationResult

public func process(_ url: URL) async throws -> DiarizationResult

public func process(
    audioSource: AudioSampleSource,
    audioLoadingSeconds: TimeInterval
) async throws -> DiarizationResult
```

- I found no public `addAudio`, `feed`, `incremental`, `processChunk`, session, or `finalize` method on `OfflineDiarizerManager`; its outward contract is “return one `DiarizationResult` at the end.”
- `OfflineDiarizerManager.process(_ url: URL)` does use disk-backed / memory-mapped streaming internally for input efficiency, and `process(audioSource:audioLoadingSeconds:)` builds an `AsyncThrowingStream<SegmentationChunk, Error>` internally (`Sources/FluidAudio/Diarizer/Offline/Core/OfflineDiarizerManager.swift:98-119,131-179`), but callers still receive only a final batch result, not incremental speaker-turn output.

3. Part B — Architectural Reasoning (not source-derived; literature-grounded, 200 words or fewer)

LS-EEND-style streaming diarization is naturally revision-capable: as audio arrives, the system emits provisional speaker activity over recent frames, then promotes older frames into finalized turns once enough future context/state makes them stable. So the native streaming shape is primarily (a) partial turns that later finalize, and often also (c) continuous per-speaker/current-speaker confidence over the active window; (b) finalized-only turns is a higher-latency derived view, not the fundamental stream. Grounding: Di Liang and Xiaofei Li, *LS-EEND: Long-Form Streaming End-to-End Neural Diarization with Online Attractor Extraction* (arXiv:2410.06670 / IEEE TASLP). For backbone design, one protocol can carry both batch and streaming cleanly if it is update-oriented: provisional segment updates, finalized segment updates, and a terminal complete snapshot/list. If the protocol shape is only “give me `[Turn]` once at completion,” it cannot represent streaming revisions cleanly, and you need a second streaming protocol.

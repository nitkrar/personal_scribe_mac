import FluidAudio
import Foundation
import PersonalScribeCore

/// Inference function injected at session construction. Production wires
/// directly to `VadManager.processStreamingChunk`; tests supply a scripted
/// closure so session behavior (accumulator, event mapping) is verifiable
/// without loading a real CoreML model.
typealias StreamingVadInference = @Sendable (
    _ chunk: [Float],
    _ state: VadStreamState,
    _ config: VadSegmentationConfig
) async throws -> VadStreamResult

/// Per-capture VAD session. Actor isolation is defensive — the pipeline
/// orchestrator is the only caller today, but isolating here means a future
/// concurrent consumer can't corrupt streaming state. State fields are
/// reset by construction; nothing persists across sessions.
actor FluidAudioVadSession {
    private let inference: StreamingVadInference
    private let config: VadSegmentationConfig
    private var streamState: VadStreamState = .initial()
    private var pendingSamples: [Float] = []
    /// Tracks whether this session has already emitted a `.speechEnded`.
    /// Gates the `.speechResumed` emission: Silero's state machine emits
    /// a fresh `speechStart` when `triggered` flips `false → true`, but
    /// the very first `.speechStart` at session open is NOT a "resumed"
    /// event — it's the first detection. Only subsequent transitions
    /// after a prior `.speechEnd` count as resumed speech.
    private var hasEmittedSpeechEnded: Bool = false
    // TEMP-DIAG #056-vad-bug: per-chunk counters for instrumentation.
    // Remove with the rest of the TEMP-DIAG block once the Parakeet
    // streaming silent-VAD bug is closed.
    private let logger: PersonalScribeLogger?
    private var chunkIndex: Int = 0

    init(
        inference: @escaping StreamingVadInference,
        config: VadSegmentationConfig,
        logger: PersonalScribeLogger? = nil
    ) {
        self.inference = inference
        self.config = config
        self.logger = logger
    }

    /// Feed samples. Accumulates into `VadManager.chunkSize` (4096) windows,
    /// runs each through the Silero streaming state machine. Returns
    /// `.speechEnded` on `speechEnd`, `.speechResumed` on `speechStart`
    /// AFTER a prior `.speechEnded`, or nil. Inference errors are swallowed
    /// — a single bad CoreML call shouldn't tear down a recording.
    func ingest(_ samples: [Float]) async -> VadEvent? {
        pendingSamples.append(contentsOf: samples)
        while pendingSamples.count >= VadManager.chunkSize {
            let chunk = Array(pendingSamples.prefix(VadManager.chunkSize))
            pendingSamples.removeFirst(VadManager.chunkSize)
            // TEMP-DIAG #056-vad-bug: log inference failures (previously
            // swallowed silently) and per-chunk Silero event kind so we
            // can tell "VAD model didn't load" from "VAD ran but never
            // emitted .speechEnd" from "VAD ran and emitted events the
            // gate dropped." Remove this entire block when bug closes.
            chunkIndex += 1
            let result: VadStreamResult
            do {
                result = try await inference(chunk, streamState, config)
            } catch {
                logger?.error(
                    "vad_inference_failed chunkIndex=\(chunkIndex) hasEmittedSpeechEnded=\(hasEmittedSpeechEnded)",
                    error: error
                )
                continue
            }
            streamState = result.state
            let kindLabel: String
            switch result.event?.kind {
            case .some(.speechStart): kindLabel = "speechStart"
            case .some(.speechEnd): kindLabel = "speechEnd"
            case .none: kindLabel = "none"
            }
            logger?.info(
                "vad_chunk_processed chunkIndex=\(chunkIndex) event=\(kindLabel) hasEmittedSpeechEnded=\(hasEmittedSpeechEnded) triggered=\(result.state.triggered) probability=\(String(format: "%.3f", result.probability))"
            )
            // END TEMP-DIAG block
            switch result.event?.kind {
            case .speechEnd:
                hasEmittedSpeechEnded = true
                return .speechEnded
            case .speechStart where hasEmittedSpeechEnded:
                return .speechResumed
            default:
                continue
            }
        }
        return nil
    }
}

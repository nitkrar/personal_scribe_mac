import FluidAudio
import Foundation

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

    init(inference: @escaping StreamingVadInference, config: VadSegmentationConfig) {
        self.inference = inference
        self.config = config
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
            guard let result = try? await inference(chunk, streamState, config) else {
                continue
            }
            streamState = result.state
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

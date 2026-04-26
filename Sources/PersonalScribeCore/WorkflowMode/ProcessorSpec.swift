import Foundation

/// Recipe-level declaration of a pipeline processor (#078 L20).
///
/// `ProcessorSpec` cases reference `ModelKind` — **never** a specific
/// `ModelDescriptor.id` (per L23). Runtime late-binds the spec to the
/// active descriptor for the named Kind via
/// `ActiveModelService.activeDescriptor(for:)` at session start
/// (eager, per L25). Recipes survive model swaps: changing the active
/// ASR model in the AI Models tab updates the bound descriptor on the
/// next session without rewriting the recipe.
///
/// Cases:
/// - `.transcriber(kind:)` — batch ASR processor; consumes a finalized
///   audio buffer, emits a single `TranscriptionResult`. The bound
///   adapter conforms `Transcriber2`.
/// - `.streamingTranscriber(kind:)` — chunked streaming ASR; consumes
///   an audio stream, emits `StreamingTranscriptionEvent` events. The
///   bound adapter conforms `StreamingTranscriber`. Validator pins
///   that recipes containing this case use `pipelineShape == .streaming`.
/// - `.diarizedTurns(diarizerKind:transcriberKind:)` — fused processor
///   that diarizes, slices per-turn audio, and ASRs each finalized
///   turn end-to-end. The bound adapters conform `SpeakerDiarizer` and
///   `Transcriber2`. Validator pins `transcriberKind ∈ {.asr, .streamingASR}`.
public enum ProcessorSpec: Codable, Equatable, Sendable {
    case transcriber(kind: ModelKind)
    case streamingTranscriber(kind: ModelKind)
    case diarizedTurns(diarizerKind: ModelKind, transcriberKind: ModelKind)

    private enum Discriminator: String, Codable {
        case transcriber
        case streamingTranscriber
        case diarizedTurns
    }

    private enum CodingKeys: String, CodingKey {
        case type
        case kind
        case diarizerKind
        case transcriberKind
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let type = try container.decode(Discriminator.self, forKey: .type)
        switch type {
        case .transcriber:
            let kind = try container.decode(ModelKind.self, forKey: .kind)
            self = .transcriber(kind: kind)
        case .streamingTranscriber:
            let kind = try container.decode(ModelKind.self, forKey: .kind)
            self = .streamingTranscriber(kind: kind)
        case .diarizedTurns:
            let diarizerKind = try container.decode(
                ModelKind.self,
                forKey: .diarizerKind
            )
            let transcriberKind = try container.decode(
                ModelKind.self,
                forKey: .transcriberKind
            )
            self = .diarizedTurns(
                diarizerKind: diarizerKind,
                transcriberKind: transcriberKind
            )
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .transcriber(let kind):
            try container.encode(Discriminator.transcriber, forKey: .type)
            try container.encode(kind, forKey: .kind)
        case .streamingTranscriber(let kind):
            try container.encode(Discriminator.streamingTranscriber, forKey: .type)
            try container.encode(kind, forKey: .kind)
        case .diarizedTurns(let diarizerKind, let transcriberKind):
            try container.encode(Discriminator.diarizedTurns, forKey: .type)
            try container.encode(diarizerKind, forKey: .diarizerKind)
            try container.encode(transcriberKind, forKey: .transcriberKind)
        }
    }
}

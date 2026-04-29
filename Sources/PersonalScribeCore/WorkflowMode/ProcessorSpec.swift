import Foundation

/// Recipe-level declaration of a pipeline processor (#078 L20, revised
/// for #090).
///
/// Each case carries a `ModelKind` plus an optional `descriptorID`
/// override:
///
/// - `descriptorID == nil` (unpinned, default): runtime late-binds to
///   the active descriptor for the named Kind via
///   `ActiveModelService.activeDescriptor(for:)` at session start
///   (eager, per L25). Recipes survive model swaps: changing the active
///   model in the AI Models tab updates the bound descriptor on the
///   next session without rewriting the recipe. This is the pre-#090
///   behavior and the default when a recipe is loaded from a document
///   that pre-dates #090.
/// - `descriptorID != nil` (pinned): the recipe pins the specific
///   `ModelDescriptor` for this processor. Switching the globally
///   active model has no effect on this processor. Validator checks the
///   pin references a registered descriptor of the matching `kind`.
///
/// Cases:
/// - `.transcriber(kind:descriptorID:)` — batch ASR processor; consumes a
///   finalized audio buffer, emits a single `TranscriptionResult`. The
///   bound adapter conforms `Transcriber`.
/// - `.streamingTranscriber(kind:descriptorID:)` — chunked streaming ASR;
///   consumes an audio stream, emits `StreamingTranscriptionEvent`
///   events. The bound adapter conforms `StreamingTranscriber`.
///   Validator pins that recipes containing this case use
///   `pipelineShape == .streaming`.
/// - `.diarizedTurns(diarizerKind:transcriberKind:transcriberDescriptorID:)`
///   — fused processor that diarizes, slices per-turn audio, and ASRs
///   each finalized turn end-to-end. The bound adapters conform
///   `SpeakerDiarizer` and `Transcriber`. Validator pins
///   `transcriberKind ∈ {.asr, .streamingASR}`. Only the ASR leg accepts
///   a descriptor pin in #090; the diarizer leg adds its own pin field
///   if/when a second diarizer descriptor lands in the catalog.
public enum ProcessorSpec: Codable, Equatable, Sendable {
    case transcriber(kind: ModelKind, descriptorID: String? = nil)
    case streamingTranscriber(kind: ModelKind, descriptorID: String? = nil)
    case diarizedTurns(
        diarizerKind: ModelKind,
        transcriberKind: ModelKind,
        transcriberDescriptorID: String? = nil
    )

    private enum Discriminator: String, Codable {
        case transcriber
        case streamingTranscriber
        case diarizedTurns
    }

    private enum CodingKeys: String, CodingKey {
        case type
        case kind
        case descriptorID
        case diarizerKind
        case transcriberKind
        case transcriberDescriptorID
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let type = try container.decode(Discriminator.self, forKey: .type)
        switch type {
        case .transcriber:
            let kind = try container.decode(ModelKind.self, forKey: .kind)
            let descriptorID = try container.decodeIfPresent(
                String.self,
                forKey: .descriptorID
            )
            self = .transcriber(kind: kind, descriptorID: descriptorID)
        case .streamingTranscriber:
            let kind = try container.decode(ModelKind.self, forKey: .kind)
            let descriptorID = try container.decodeIfPresent(
                String.self,
                forKey: .descriptorID
            )
            self = .streamingTranscriber(kind: kind, descriptorID: descriptorID)
        case .diarizedTurns:
            let diarizerKind = try container.decode(
                ModelKind.self,
                forKey: .diarizerKind
            )
            let transcriberKind = try container.decode(
                ModelKind.self,
                forKey: .transcriberKind
            )
            let transcriberDescriptorID = try container.decodeIfPresent(
                String.self,
                forKey: .transcriberDescriptorID
            )
            self = .diarizedTurns(
                diarizerKind: diarizerKind,
                transcriberKind: transcriberKind,
                transcriberDescriptorID: transcriberDescriptorID
            )
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .transcriber(let kind, let descriptorID):
            try container.encode(Discriminator.transcriber, forKey: .type)
            try container.encode(kind, forKey: .kind)
            try container.encodeIfPresent(descriptorID, forKey: .descriptorID)
        case .streamingTranscriber(let kind, let descriptorID):
            try container.encode(Discriminator.streamingTranscriber, forKey: .type)
            try container.encode(kind, forKey: .kind)
            try container.encodeIfPresent(descriptorID, forKey: .descriptorID)
        case .diarizedTurns(let diarizerKind, let transcriberKind, let transcriberDescriptorID):
            try container.encode(Discriminator.diarizedTurns, forKey: .type)
            try container.encode(diarizerKind, forKey: .diarizerKind)
            try container.encode(transcriberKind, forKey: .transcriberKind)
            try container.encodeIfPresent(
                transcriberDescriptorID,
                forKey: .transcriberDescriptorID
            )
        }
    }
}

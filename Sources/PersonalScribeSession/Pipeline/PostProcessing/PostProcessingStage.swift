/// One transformation step in the post-processing pipeline.
///
/// Stages receive a single line at a time — `DefaultPostProcessingPipeline.run`
/// splits multi-line input on `\n` (e.g. inter-turn separators emitted by
/// the diarized fusion processor) and applies every stage to each line
/// before rejoining. Concretely, a stage MUST NOT introduce `\n` in its
/// output, and conversely doesn't need to defend against `\s+`-style
/// regexes eating line breaks — the pipeline owns that boundary.
public protocol PostProcessingStage: Sendable {
    var name: String { get }
    func apply(_ text: String, context: PostProcessingContext) async throws -> String
}

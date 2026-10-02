import PersonalScribeCore
import PersonalScribeSession

/// The pipeline's output stage — delivery is the recipe's last step and
/// the orchestrator runs it (`PipelineOutputSink.deliverFinal`) only for
/// sessions that produced a result. Cancelled / short-exit / failed
/// sessions never reach it, so they deliver nothing.
///
/// Composes the two delivery surfaces:
/// * `live` — live cursor streaming (partials during the session; its
///   `endSession` restores the clipboard it borrowed).
/// * `batch` — final delivery to the recipe's sinks (clipboard, paste).
///
/// Replaces the former UI-side auto-paste in `MenuBarSceneModel`, which
/// fired on every return to idle and re-pasted the previous transcript
/// after an Esc cancel.
public final class SessionOutputStage: PipelineOutputSink, @unchecked Sendable {
    private let live: any PipelineOutputSink
    private let batch: any OutputService
    private let logger: PersonalScribeLogger

    /// Raised when final delivery fell back to clipboard-only (e.g. Ninimma
    /// frontmost) so the UI can show "Copied to clipboard · ⌘V to paste".
    /// Set by the app after construction.
    @MainActor public var onClipboardOnlyCopy: @MainActor () -> Void = {}

    public init(
        live: any PipelineOutputSink,
        batch: any OutputService,
        logger: PersonalScribeLogger
    ) {
        self.live = live
        self.batch = batch
        self.logger = logger
    }

    public func deliverPartial(_ revision: TranscriptProgress) async throws {
        try await live.deliverPartial(revision)
    }

    public func deliverFinal(_ result: TranscriptionResult, sinks: [BoundOutputSink]) async throws {
        // End the live session first: it restores the clipboard it
        // borrowed for streamed chunks and records the live paste count
        // the batch paste reads (#098 newline). Pasting before that would
        // be clobbered by the restore. `endSession` is idempotent, so the
        // orchestrator's later session-end call is a no-op.
        await live.endSession()

        let outcome = await batch.deliverBatch(text: result.text, sinks: sinks)
        switch outcome {
        case .delivered(let target, _):
            if target == .clipboardOnly || target == .selfFrontmost {
                await MainActor.run { onClipboardOnlyCopy() }
            }
        case .failed(let error):
            logger.error("Final transcript delivery failed", error: error)
        case .ignoredEmptyInput:
            break
        }
    }

    public func resetForNewSession() async {
        await live.resetForNewSession()
    }

    public func endSession() async {
        await live.endSession()
    }
}

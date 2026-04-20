import Foundation
import PersonalScribeCore

/// Encapsulates the menu-bar "Paste Last Transcript" action so the
/// handler is testable without a running `NSApplication`. Reads the
/// single most-recent transcript via `TranscriptReading` and delivers
/// it through the shared `OutputService` pipeline — which already
/// honors the user's `PasteMode` preference (paste-at-cursor vs
/// clipboard-only) and falls back gracefully when Accessibility is
/// not trusted.
///
/// Marked `Sendable` + `public` so it can cross actor hops (e.g. a
/// `@MainActor` closure at the wiring site can stash an instance and
/// invoke `perform()` from a detached `Task`).
public struct PasteLastTranscriptAction: Sendable {
    private let transcriptReader: any TranscriptReading
    private let outputService: any OutputService

    public init(
        transcriptReader: any TranscriptReading,
        outputService: any OutputService
    ) {
        self.transcriptReader = transcriptReader
        self.outputService = outputService
    }

    /// Reads the single most-recent transcript and delivers it through
    /// the output pipeline. Returns the delivery `OutputResult` (or
    /// `nil` when no transcripts exist yet). Silent no-op on empty
    /// history — surfacing a user-visible "nothing to paste" notice
    /// is a UX polish deferred to a later milestone.
    @discardableResult
    public func perform() async -> OutputResult? {
        let recents = await transcriptReader.recent(limit: 1)
        guard let entry = recents.first else { return nil }
        return await outputService.deliverBatch(text: entry.text)
    }
}

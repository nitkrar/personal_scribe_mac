import AppKit
import Foundation
import PersonalScribeCore

/// Outcome of a single `CopyLastTranscriptAction.perform()` call.
/// Surfaced via the injected `onCompleted` callback so the composition
/// layer can log, show a toast, or otherwise give the user feedback
/// — silent no-op was the root cause of bug #9 (2026-04-21 dogfood).
public enum CopyLastTranscriptOutcome: Equatable, Sendable {
    case copied(text: String)
    case emptyHistory
}

/// Menu-bar "Copy Last Transcript" handler. Strict copy-to-clipboard
/// contract: read the single most-recent transcript via
/// `TranscriptReading`, write it to the injected clipboard writer,
/// and report the outcome. No auto-paste, no AX focused-element
/// probe, no `PasteMode` branching.
///
/// This is deliberately *not* the same as `ClipboardBatchOutput.deliverBatch`:
/// the paste-at-cursor flow is served by the hotkey / pill path where
/// the user's original cursor context is preserved. Clicking the menu
/// bar always steals focus, so the menu-bar action is best modeled as
/// "grab the text, I'll paste it manually" — matching user intent in
/// the #9 dogfood report.
public struct CopyLastTranscriptAction: Sendable {
    public typealias ClipboardWriter = @MainActor @Sendable (String) -> Void
    public typealias CompletionHandler = @MainActor @Sendable (CopyLastTranscriptOutcome) -> Void

    private let transcriptReader: any TranscriptReading
    private let clipboardWriter: ClipboardWriter
    private let onCompleted: CompletionHandler

    /// Initializer. `clipboardWriter` has no default because the
    /// default `NSPasteboard.general` writer is `@MainActor`-isolated
    /// and can't sit as a default in a non-isolated init. Callers
    /// should pass `CopyLastTranscriptAction.defaultClipboardWriter`
    /// from a `@MainActor` context, or supply a test spy.
    public init(
        transcriptReader: any TranscriptReading,
        clipboardWriter: @escaping ClipboardWriter,
        onCompleted: @escaping CompletionHandler = { _ in }
    ) {
        self.transcriptReader = transcriptReader
        self.clipboardWriter = clipboardWriter
        self.onCompleted = onCompleted
    }

    /// Reads the single most-recent transcript and writes it to the
    /// clipboard. On empty history, does NOT clear the pasteboard —
    /// leaves the user's existing clipboard contents intact and reports
    /// `.emptyHistory` so the caller can surface a notice.
    public func perform() async {
        let recents = await transcriptReader.recent(limit: 1)
        guard let entry = recents.first else {
            await MainActor.run { onCompleted(.emptyHistory) }
            return
        }
        let text = entry.text
        await MainActor.run {
            clipboardWriter(text)
            onCompleted(.copied(text: text))
        }
    }

    /// Default `NSPasteboard.general` writer — `clearContents()` plus
    /// `setString(_:forType:.string)`. Injected for tests via the
    /// initializer's `clipboardWriter` parameter.
    @MainActor
    public static let defaultClipboardWriter: ClipboardWriter = { text in
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(text, forType: .string)
    }
}

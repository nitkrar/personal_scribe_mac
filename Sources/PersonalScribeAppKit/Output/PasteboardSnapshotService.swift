import AppKit
import Foundation

/// Snapshot + restore of the system pasteboard's plain-text contents,
/// used by the pill UX's Cancel Card Undo affordance (spec §2f + §4).
///
/// # Rationale
///
/// When the user cancels a recording via ✕ / Esc the transcript is
/// discarded. The user's clipboard, however, may have been overwritten
/// by a prior transcription (auto-paste always writes the transcript
/// to the pasteboard before posting Cmd+V). If they click Undo on the
/// Cancel Card, they expect their pre-recording clipboard contents
/// restored.
///
/// `PasteboardSnapshotService` decouples this from `SessionCoordinator`
/// (which lives in PersonalScribeSession, no AppKit access) and from
/// the output pipeline. The composition layer owns a single instance
/// and calls `snapshotCurrentContents()` when a new recording begins;
/// `restoreLastSnapshot()` is invoked from the view model's
/// `onUndoCancelledRecording` hook.
///
/// # Contract
///
/// * `snapshotCurrentContents()` captures the current pasteboard string
///   (or `nil` if empty / non-string). Only the most recent snapshot is
///   retained — a second snapshot overwrites the first.
/// * `restoreLastSnapshot()` writes the saved string back to the
///   pasteboard, then clears the stored snapshot so a subsequent Undo
///   is a no-op. Returns `true` if a snapshot existed and was restored,
///   `false` otherwise.
/// * `clearSnapshot()` discards the stored snapshot without writing it.
///   Used when a recording completes successfully (the snapshot is
///   no longer needed; future cancels should snapshot fresh contents).
///
/// # Test seams
///
/// The reader + writer closures are injected with `NSPasteboard.general`
/// defaults so tests can drive the service with an in-memory backing
/// store without touching the real system pasteboard.
@MainActor
public final class PasteboardSnapshotService {
    public typealias StringReader = @MainActor () -> String?
    public typealias StringWriter = @MainActor (String) -> Void

    private let read: StringReader
    private let write: StringWriter
    private var savedString: String?

    public convenience init() {
        self.init(
            read: { NSPasteboard.general.string(forType: .string) },
            write: { string in
                let pasteboard = NSPasteboard.general
                pasteboard.clearContents()
                pasteboard.setString(string, forType: .string)
            }
        )
    }

    init(
        read: @escaping StringReader,
        write: @escaping StringWriter
    ) {
        self.read = read
        self.write = write
    }

    public func snapshotCurrentContents() {
        savedString = read()
    }

    @discardableResult
    public func restoreLastSnapshot() -> Bool {
        guard let savedString else {
            return false
        }
        write(savedString)
        self.savedString = nil
        return true
    }

    public func clearSnapshot() {
        savedString = nil
    }

    /// Exposed for tests only.
    internal var currentSnapshot: String? {
        savedString
    }
}

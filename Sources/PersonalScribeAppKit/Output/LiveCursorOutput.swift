import AppKit
import ApplicationServices
import Foundation
import PersonalScribeCore
import PersonalScribeSession

/// #033 — live cursor stream output for streaming dictation sessions.
///
/// Implements `PipelineOutputSink` so the orchestrator's
/// `consumeLiveStreamingEvent` flow can deliver each EOU chunk as a
/// pasteboard write + synthetic ⌘V to the user's frontmost text field
/// while a streaming session is still recording.
///
/// Lifecycle:
/// - `resetForNewSession()` is called at session start by the
///   orchestrator before any chunks arrive. Captures the user's
///   pre-recording clipboard once per session so restore semantics are
///   anchored to session start, not first-chunk timing.
/// - `deliverPartial(_:)` is called on every EOU chunk. It overwrites
///   the clipboard with the new chunk and posts `Cmd+V` if AX trust +
///   externality probe agree.
/// - `endSession()` is called on every termination path (success,
///   cancel, error, short-exit). Restores the captured snapshot only
///   if this sink actually wrote at least one live chunk; otherwise it
///   discards the unused session snapshot so unrelated clipboard
///   changes made during dormant sessions survive.
/// - `deliverFinal(_:)` is a no-op. Authoritative second-pass output
///   travels through `MenuBarSceneModel` + `ClipboardBatchOutput`'s
///   stop-time path — not this sink. Per #056 DESIGN: when live cursor
///   streaming is on, there is never an extra stop-time cursor write
///   from this sink, and `RecipeBuilder` filters the
///   `.frontmostPaste` output sink out of the bound recipe.
///
/// Failure policy: each `deliverPartial` failure is logged and
/// swallowed. A transient pasteboard write failure or an AX probe
/// flake should not tear down the live session — the chunk is
/// effectively lost (the second-pass authoritative final at session
/// end will recover it).
@MainActor
public final class LiveCursorOutput: PipelineOutputSink, @unchecked Sendable {
    typealias FocusedElementExternalityProbe = @MainActor () -> Bool
    typealias PasteShortcutPoster = @MainActor () -> Bool

    private let logger: PersonalScribeLogger
    private let snapshotService: PasteboardSnapshotService
    private let isAccessibilityTrusted: @MainActor () -> Bool
    private let pasteShortcutPoster: PasteShortcutPoster
    private let focusedElementIsInAnotherApp: FocusedElementExternalityProbe

    private var sessionSnapshotHandle: PasteboardSnapshotService.Handle?
    private var didWriteChunkThisSession = false

    init(
        logger: PersonalScribeLogger,
        snapshotService: PasteboardSnapshotService = PasteboardSnapshotService(),
        isAccessibilityTrusted: @escaping @MainActor () -> Bool = { AXIsProcessTrusted() },
        pasteShortcutPoster: @escaping PasteShortcutPoster = LiveCursorOutput.postPasteShortcut,
        focusedElementIsInAnotherApp: @escaping FocusedElementExternalityProbe
            = LiveCursorOutput.liveFocusedElementIsInAnotherApp
    ) {
        self.logger = logger
        self.snapshotService = snapshotService
        self.isAccessibilityTrusted = isAccessibilityTrusted
        self.pasteShortcutPoster = pasteShortcutPoster
        self.focusedElementIsInAnotherApp = focusedElementIsInAnotherApp
    }

    public func deliverPartial(_ revision: TranscriptProgress) async throws {
        let chunk = revision.text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !chunk.isEmpty else { return }

        if sessionSnapshotHandle == nil {
            // Defensive fallback for direct unit tests or future callers
            // that invoke `deliverPartial` without a preceding
            // `resetForNewSession()`. Production flow snapshots at
            // session start.
            sessionSnapshotHandle = snapshotService.captureTransientSnapshot()
        }

        guard snapshotService.replaceContents(with: chunk) != nil else {
            logger.error("LiveCursorOutput: failed to write chunk to clipboard; skipping paste for this EOU")
            return
        }
        didWriteChunkThisSession = true

        guard isAccessibilityTrusted() else {
            logger.info("LiveCursorOutput: Accessibility not trusted; chunk left on clipboard, skipping ⌘V")
            return
        }

        guard focusedElementIsInAnotherApp() else {
            logger.info("LiveCursorOutput: focused element is in self; chunk left on clipboard, skipping ⌘V")
            return
        }

        _ = pasteShortcutPoster()
    }

    public func deliverFinal(_ result: TranscriptionResult) async throws {
        // Live cursor mode does not stop-time deliver via this sink.
        // The authoritative second-pass writes through MenuBarSceneModel
        // + ClipboardBatchOutput, and `RecipeBuilder` filters the
        // `.frontmostPaste` sink when live cursor is on so no double
        // paste lands at session end.
    }

    public func resetForNewSession() async {
        // Drop any stale handle left behind by an unexpected caller
        // pattern, then snapshot the clipboard immediately so restore
        // semantics are anchored to session start.
        if let handle = sessionSnapshotHandle {
            snapshotService.discardSnapshot(handle)
        }
        didWriteChunkThisSession = false
        sessionSnapshotHandle = snapshotService.captureTransientSnapshot()
    }

    public func endSession() async {
        guard let handle = sessionSnapshotHandle else { return }
        sessionSnapshotHandle = nil
        let shouldRestore = didWriteChunkThisSession
        didWriteChunkThisSession = false
        if shouldRestore {
            snapshotService.restoreSnapshot(handle)
        } else {
            snapshotService.discardSnapshot(handle)
        }
    }

    // MARK: - Live AX probe + paste poster

    /// Mirrors `ClipboardBatchOutput.liveFocusedElementIsInAnotherApp`
    /// — the same PID-based externality check the stop-time path uses.
    /// Reuses `ClipboardBatchOutput.focusedElementIsInAnotherApp(...)`
    /// pure helper so the comparison logic stays single-sourced.
    static func liveFocusedElementIsInAnotherApp() -> Bool {
        ClipboardBatchOutput.focusedElementIsInAnotherApp(
            systemWideFocusedPID: liveSystemWideFocusedPID
        )
    }

    private static func liveSystemWideFocusedPID() -> pid_t? {
        let systemWide = AXUIElementCreateSystemWide()
        var focusedRef: CFTypeRef?
        let status = AXUIElementCopyAttributeValue(
            systemWide,
            kAXFocusedUIElementAttribute as CFString,
            &focusedRef
        )
        guard status == .success, let focusedRef else {
            return nil
        }
        // swiftlint:disable:next force_cast
        let focused = focusedRef as! AXUIElement
        var focusedPID: pid_t = 0
        guard AXUIElementGetPid(focused, &focusedPID) == .success else {
            return nil
        }
        return focusedPID
    }

    static func postPasteShortcut() -> Bool {
        guard let source = CGEventSource(stateID: .combinedSessionState) else {
            return false
        }
        let vKey: CGKeyCode = 9
        guard let down = CGEvent(keyboardEventSource: source, virtualKey: vKey, keyDown: true),
              let up = CGEvent(keyboardEventSource: source, virtualKey: vKey, keyDown: false) else {
            return false
        }
        down.flags = .maskCommand
        up.flags = .maskCommand
        down.post(tap: .cghidEventTap)
        up.post(tap: .cghidEventTap)
        return true
    }
}

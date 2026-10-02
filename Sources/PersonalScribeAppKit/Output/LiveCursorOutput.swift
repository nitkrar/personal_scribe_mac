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
    typealias PasteTargetProbe = @MainActor () -> PasteTarget
    typealias PasteShortcutPoster = @MainActor () -> Bool

    private let logger: PersonalScribeLogger
    private let snapshotService: PasteboardSnapshotService
    private let isAccessibilityTrusted: @MainActor () -> Bool
    private let pasteShortcutPoster: PasteShortcutPoster
    private let pasteTarget: PasteTargetProbe
    private let selfBundleIdentifier: String

    private var sessionSnapshotHandle: PasteboardSnapshotService.Handle?
    private var didWriteChunkThisSession = false
    private var didLogAccessibilityTrustSkipThisCycle = false
    private var pasteSessionID: String?
    private var pasteAccumulator = PasteSessionAccumulator()

    /// #098: last completed session's live-paste attempt count. Read by
    /// `ClipboardBatchOutput.deliverBatch` to decide whether to prepend
    /// a newline before the authoritative final paste. Set in
    /// `endSession()` immediately before the accumulator is wiped.
    /// Resets to 0 at the start of every new session.
    public private(set) var lastSessionLivePasteAttempts: Int = 0

    init(
        logger: PersonalScribeLogger,
        snapshotService: PasteboardSnapshotService = PasteboardSnapshotService(),
        isAccessibilityTrusted: @escaping @MainActor () -> Bool = { AXIsProcessTrusted() },
        pasteShortcutPoster: @escaping PasteShortcutPoster = LiveCursorOutput.postPasteShortcut,
        pasteTarget: @escaping PasteTargetProbe = { PasteTarget.live() },
        selfBundleIdentifier: String = AppBrand.bundleIdentifier
    ) {
        self.logger = logger
        self.snapshotService = snapshotService
        self.isAccessibilityTrusted = isAccessibilityTrusted
        self.pasteShortcutPoster = pasteShortcutPoster
        self.pasteTarget = pasteTarget
        self.selfBundleIdentifier = selfBundleIdentifier
    }

    public func deliverPartial(_ revision: TranscriptProgress) async throws {
        let chunk = revision.text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !chunk.isEmpty else { return }

        let sessionID = ensurePasteSessionStarted()
        // #098: subsequent chunks within the same session prepend a
        // single space so consecutive EoU pastes don't concatenate
        // (`"hello world" + "how are you"` was landing as
        // `"hello worldhow are you"` pre-fix). First chunk pastes as
        // is; from chunk N+1 onward we prepend " " before the
        // clipboard write. Accumulator counts the actual written
        // length so cumulativeCharsWritten reflects bytes-on-clipboard.
        let chunkToWrite = didWriteChunkThisSession ? " \(chunk)" : chunk
        pasteAccumulator.recordLiveAttempt(chars: chunkToWrite.count)

        guard snapshotService.replaceContents(with: chunkToWrite) != nil else {
            pasteAccumulator.recordLiveFailed(reason: .pasteboardWriteFailed)
            logger.error(
                pasteFailedLogLine(
                    sink: .live,
                    stage: "live",
                    reason: .pasteboardWriteFailed,
                    attemptedChars: chunkToWrite.count,
                    sessionID: sessionID
                )
            )
            return
        }
        didWriteChunkThisSession = true

        guard isAccessibilityTrusted() else {
            pasteAccumulator.recordLiveClipboardWrite(chars: chunkToWrite.count)
            pasteAccumulator.recordLiveSkipped()
            logAccessibilityTrustSkipIfNeeded()
            return
        }
        didLogAccessibilityTrustSkipThisCycle = false

        let target = pasteTarget()
        guard target.permitsPaste(selfBundleID: selfBundleIdentifier) else {
            pasteAccumulator.recordLiveClipboardWrite(chars: chunkToWrite.count)
            pasteAccumulator.recordLiveSkipped()
            logger.info("LiveCursorOutput: not pasting (\(target.logDescription)); chunk left on clipboard, skipping ⌘V")
            return
        }

        // Surface paste-poster failures (e.g. CGEventSource creation
        // returning nil) — otherwise this is a silent live-paint loss
        // path: the chunk landed on the clipboard but no ⌘V actually
        // posted, and the user sees nothing in the target app.
        if !pasteShortcutPoster() {
            pasteAccumulator.recordLiveClipboardWrite(chars: chunkToWrite.count)
            pasteAccumulator.recordLiveFailed(reason: .eventPostFailed)
            logger.error(
                pasteFailedLogLine(
                    sink: .live,
                    stage: "live",
                    reason: .eventPostFailed,
                    attemptedChars: chunkToWrite.count,
                    sessionID: sessionID
                )
            )
            return
        }

        pasteAccumulator.recordLiveSucceeded(chars: chunkToWrite.count)
        recordObservedTarget(target)
    }

    public func deliverFinal(_ result: TranscriptionResult, sinks: [BoundOutputSink]) async throws {
        // Live cursor mode does not stop-time deliver via this sink.
        // The authoritative second-pass writes through
        // `ClipboardBatchOutput` when `.frontmostPaste` is in the
        // bound recipe sinks. Pre-#098 RecipeBuilder filtered that
        // sink out under liveCursor=true to avoid double-paste; #098
        // restored it so the user can opt into both surfaces. The
        // newline separator before the final paste is owned by
        // ClipboardBatchOutput using #097's accumulator signal.
    }

    public func resetForNewSession() async {
        // Drop any stale handle left behind by an unexpected caller
        // pattern, then snapshot the clipboard immediately so restore
        // semantics are anchored to session start.
        if let handle = sessionSnapshotHandle {
            snapshotService.discardSnapshot(handle)
        }
        didWriteChunkThisSession = false
        didLogAccessibilityTrustSkipThisCycle = false
        pasteSessionID = UUID().uuidString
        pasteAccumulator = PasteSessionAccumulator()
        pasteAccumulator.startedSession()
        sessionSnapshotHandle = snapshotService.captureTransientSnapshot()
    }

    public func endSession() async {
        guard let handle = sessionSnapshotHandle else { return }
        let sessionID = pasteSessionID ?? UUID().uuidString
        logger.info(pasteAccumulator.summary(sink: .live, sessionID: sessionID).formatLogLine())
        // #098: snapshot the live-session paste count BEFORE wiping
        // the accumulator. ClipboardBatchOutput reads this to decide
        // whether to prepend a newline before the final paste — if
        // live cursor pasted ≥1 chunk and the recipe also wants
        // final-paste, the newline avoids running the last live chunk
        // into the first word of the authoritative final.
        lastSessionLivePasteAttempts = pasteAccumulator.livePasteAttempts
        sessionSnapshotHandle = nil
        let shouldRestore = didWriteChunkThisSession
        didWriteChunkThisSession = false
        didLogAccessibilityTrustSkipThisCycle = false
        pasteSessionID = nil
        pasteAccumulator = PasteSessionAccumulator()
        if shouldRestore {
            snapshotService.restoreSnapshot(handle)
        } else {
            snapshotService.discardSnapshot(handle)
        }
    }

    private func logAccessibilityTrustSkipIfNeeded() {
        guard !didLogAccessibilityTrustSkipThisCycle else {
            return
        }

        didLogAccessibilityTrustSkipThisCycle = true
        logger.info("LiveCursorOutput: Accessibility not trusted; chunk left on clipboard, skipping ⌘V")
    }

    private func ensurePasteSessionStarted() -> String {
        if sessionSnapshotHandle == nil {
            // Defensive fallback for direct unit tests or future callers
            // that invoke `deliverPartial` without a preceding
            // `resetForNewSession()`. Production flow snapshots at
            // session start.
            sessionSnapshotHandle = snapshotService.captureTransientSnapshot()
        }

        if pasteSessionID == nil {
            pasteSessionID = UUID().uuidString
        }

        if pasteAccumulator.startedAt == nil {
            pasteAccumulator.startedSession()
        }

        return pasteSessionID ?? "unknown"
    }

    private func recordObservedTarget(_ target: PasteTarget) {
        guard case .frontmost(let bundleID, let pid) = target else { return }
        pasteAccumulator.recordTarget(pid: pid, bundleID: bundleID)
    }

    private func pasteFailedLogLine(
        sink: PasteSessionAccumulator.SinkKind,
        stage: String,
        reason: PasteFailureReason,
        attemptedChars: Int,
        sessionID: String
    ) -> String {
        "paste_failed — sink=\(sink.rawValue) stage=\(stage) reason=\(reason.rawValue) attemptedChars=\(attemptedChars) sessionID=\(sessionID)"
    }

    // MARK: - Live AX probe + paste poster


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

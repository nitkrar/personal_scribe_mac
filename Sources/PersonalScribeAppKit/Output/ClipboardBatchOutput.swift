import AppKit
import ApplicationServices
import Foundation
import PersonalScribeCore

/// Probe returning `true` when the system-wide AX focused element is owned
/// by a different process (another app). Paste is safe when focus is outside
/// Ninimma. Injected as a dependency so tests can stub the result without
/// touching the real AX APIs.
typealias PasteTargetProbe = @MainActor () -> PasteTarget

@MainActor
public final class ClipboardBatchOutput: OutputService, @unchecked Sendable {
    typealias RestoreScheduler = @MainActor (
        _ delay: TimeInterval,
        _ action: @escaping @MainActor () -> Void
    ) -> Void
    typealias PasteShortcutPoster = @MainActor (_ logger: PersonalScribeLogger) -> Bool

    private let logger: PersonalScribeLogger
    private let defaults: UserDefaults
    private let frontmostAppProvider: any FrontmostAppProviding
    private let selfBundleIdentifier: String
    private let snapshotService: PasteboardSnapshotService
    private let scheduleRestore: RestoreScheduler
    private let isAccessibilityTrusted: @MainActor () -> Bool
    private let pasteShortcutPoster: @MainActor () -> Bool
    private let pasteTarget: PasteTargetProbe
    /// Live chunks successfully pasted in the last streaming session; when
    /// non-zero and paste is enabled, the final paste starts on a new line.
    private let liveCursorPasteSnapshot: @MainActor () -> Int

    init(
        logger: PersonalScribeLogger,
        defaults: UserDefaults = .standard,
        frontmostAppProvider: any FrontmostAppProviding = WorkspaceFrontmostAppProvider(),
        selfBundleIdentifier: String = AppBrand.bundleIdentifier,
        snapshotService: PasteboardSnapshotService = PasteboardSnapshotService(),
        scheduleRestore: @escaping RestoreScheduler = { delay, action in
            DispatchQueue.main.asyncAfter(deadline: .now() + delay) {
                Task { @MainActor in
                    action()
                }
            }
        },
        isAccessibilityTrusted: @escaping @MainActor () -> Bool = { AXIsProcessTrusted() },
        pasteShortcutPoster: @escaping PasteShortcutPoster = ClipboardBatchOutput.postPasteShortcut,
        pasteTarget: @escaping PasteTargetProbe = { PasteTarget.live() },
        liveCursorPasteSnapshot: @escaping @MainActor () -> Int = { 0 }
    ) {
        self.logger = logger
        self.defaults = defaults
        self.frontmostAppProvider = frontmostAppProvider
        self.selfBundleIdentifier = selfBundleIdentifier
        self.snapshotService = snapshotService
        self.scheduleRestore = scheduleRestore
        self.isAccessibilityTrusted = isAccessibilityTrusted
        self.pasteShortcutPoster = {
            pasteShortcutPoster(logger)
        }
        self.pasteTarget = pasteTarget
        self.liveCursorPasteSnapshot = liveCursorPasteSnapshot
    }

    public func deliverBatch(text: String, sinks: [BoundOutputSink]) async -> OutputResult {
        guard !text.isEmpty else {
            return .ignoredEmptyInput
        }

        let sessionID = UUID().uuidString
        var pasteAccumulator = PasteSessionAccumulator()
        pasteAccumulator.startedSession()
        defer {
            logger.info(pasteAccumulator.summary(sink: .batch, sessionID: sessionID).formatLogLine())
        }

        // #089 L-24: sink presence is the feature gate. No `.clipboard`
        // entry → skip clipboard write + restore + paste entirely. No
        // `.frontmostPaste` entry → skip Cmd+V even when clipboard
        // wrote successfully. The associated `restoreEnabled` /
        // `enabled` booleans are already resolved by RecipeBuilder
        // (eager L-25), so we consume them as-is.
        let clipboardRestoreEnabled: Bool? = sinks.lazy.compactMap { sink -> Bool? in
            if case .clipboard(let restore) = sink {
                return restore
            }
            return nil
        }.first

        let pasteEnabled: Bool = sinks.lazy.compactMap { sink -> Bool? in
            if case .frontmostPaste(let enabled) = sink {
                return enabled
            }
            return nil
        }.first ?? false

        guard let restoreEnabled = clipboardRestoreEnabled else {
            // No clipboard sink → nothing to write. The frontmost-paste
            // path requires a clipboard write to land first; without
            // it, paste cannot synthesize the right key sequence.
            // Surface as ignoredEmptyInput-shape: the orchestrator
            // already persisted the transcript via
            // `.transcriptHistorySQLite`; clipboard absence is a
            // deliberate config, not an error.
            return .delivered(target: .clipboardOnly, delivery: .clipboardOnly)
        }

        pasteAccumulator.recordFinalAttempted(chars: text.count)

        // When live cursor pasted at least one chunk and final paste is
        // enabled, put the authoritative final on a new line. Clipboard-
        // only delivery is unaffected.
        let textToWrite: String =
            liveCursorPasteSnapshot() > 0 && pasteEnabled
                ? "\n\(text)"
                : text

        let restoreDelay = ClipboardRestoreDelay.resolve(from: defaults).seconds
        let handle = snapshotService.captureTransientSnapshot()

        guard let writeToken = snapshotService.replaceContents(with: textToWrite) else {
            pasteAccumulator.recordFinalFailed(reason: .pasteboardWriteFailed)
            logger.error(
                pasteFailedLogLine(
                    sink: .batch,
                    stage: "final",
                    reason: .pasteboardWriteFailed,
                    attemptedChars: textToWrite.count,
                    sessionID: sessionID
                )
            )
            snapshotService.restoreSnapshot(handle)
            return .failed(.clipboardWriteFailed)
        }
        pasteAccumulator.recordFinalClipboardWrite(chars: textToWrite.count)

        // Schedules the user's pre-transcript clipboard to be restored after
        // `restoreDelay` seconds, but only if nothing has written to the
        // pasteboard since our transcript landed (changeCount guard — the
        // `restoreSnapshotIfUnchanged` checks against `writeToken`). Runs for
        // both the paste-at-cursor branch and the clipboard-only branch
        // (AutoPasteEnabledPreference off, or AX untrusted, or externality
        // probe says focus-is-in-self) — restore is orthogonal to paste mode.
        let maybeScheduleRestore: @MainActor () -> Void = { [snapshotService, scheduleRestore] in
            guard restoreEnabled else {
                snapshotService.discardSnapshot(handle)
                return
            }
            scheduleRestore(restoreDelay) {
                snapshotService.restoreSnapshotIfUnchanged(handle, token: writeToken)
            }
        }

        if !pasteEnabled {
            pasteAccumulator.recordFinalClipboardOnlyDelivery(chars: text.count)
            logger.info("ClipboardBatchOutput: paste sink absent or disabled; leaving transcript on clipboard for manual paste")
            maybeScheduleRestore()
            return .delivered(target: .clipboardOnly, delivery: .clipboardOnly)
        }

        // Flow (2026-04-22 — #042 fix + #072):
        //   Transcription finished → copy to clipboard (always, above) → post
        //   Cmd+V only if AX permission is granted AND the AX focused element
        //   is owned by a different process. Otherwise return `.clipboardOnly`
        //   so the existing "Copied to clipboard · ⌘V to paste" notice fires.
        //
        //   #042: earlier 2026-04-20 design probed for text-role / cursor
        //   attributes directly; that under-included custom-drawn editors
        //   (Sublime, VS Code, Electron). PID check trusts the focus owner.

        guard isAccessibilityTrusted() else {
            pasteAccumulator.recordFinalFailed(reason: .accessibilityNotTrusted)
            logger.error(
                pasteFailedLogLine(
                    sink: .batch,
                    stage: "final",
                    reason: .accessibilityNotTrusted,
                    attemptedChars: text.count,
                    sessionID: sessionID
                )
            )
            // No prompt here: asking for permission belongs to Settings /
            // onboarding. Delivery just falls back to the clipboard and
            // the notice tells the user why.
            logger.info("ClipboardBatchOutput: Accessibility permission not granted; leaving transcript on clipboard for manual Cmd+V")
            maybeScheduleRestore()
            return .delivered(target: .clipboardNeedsAccessibility, delivery: .clipboardOnly)
        }

        let target = pasteTarget()
        guard target.permitsPaste(selfBundleID: selfBundleIdentifier) else {
            pasteAccumulator.recordFinalFailed(reason: .noTargetCursor)
            logger.error(
                pasteFailedLogLine(
                    sink: .batch,
                    stage: "final",
                    reason: .noTargetCursor,
                    attemptedChars: text.count,
                    sessionID: sessionID
                )
            )
            logger.info("ClipboardBatchOutput: not pasting (\(target.logDescription)); leaving transcript on clipboard")
            maybeScheduleRestore()
            return .delivered(target: .clipboardOnly, delivery: .clipboardOnly)
        }

        logger.info("ClipboardBatchOutput: pasting into \(target.logDescription)")
        recordObservedTarget(target, into: &pasteAccumulator)

        guard pasteShortcutPoster() else {
            pasteAccumulator.recordFinalFailed(reason: .eventPostFailed)
            logger.error(
                pasteFailedLogLine(
                    sink: .batch,
                    stage: "final",
                    reason: .eventPostFailed,
                    attemptedChars: text.count,
                    sessionID: sessionID
                )
            )
            maybeScheduleRestore()
            return .delivered(target: .frontmostApp, delivery: .clipboardOnly)
        }

        pasteAccumulator.recordFinalSucceeded(chars: text.count)
        maybeScheduleRestore()
        return .delivered(target: .frontmostApp, delivery: .paste)
    }

    private static func postPasteShortcut(logger: PersonalScribeLogger) -> Bool {
        guard let source = CGEventSource(stateID: .combinedSessionState) else {
            logger.info("ClipboardBatchOutput: failed to create CGEventSource; leaving transcript on clipboard as fallback")
            return false
        }

        let vKey: CGKeyCode = 9
        guard let down = CGEvent(keyboardEventSource: source, virtualKey: vKey, keyDown: true),
              let up = CGEvent(keyboardEventSource: source, virtualKey: vKey, keyDown: false) else {
            logger.info("ClipboardBatchOutput: failed to create CGEvent; leaving transcript on clipboard as fallback")
            return false
        }

        logger.info("ClipboardBatchOutput: posting synthetic Cmd+V to the frontmost app")
        down.flags = .maskCommand
        up.flags = .maskCommand
        down.post(tap: .cghidEventTap)
        up.post(tap: .cghidEventTap)
        return true
    }

    private func recordObservedTarget(_ target: PasteTarget, into accumulator: inout PasteSessionAccumulator) {
        guard case .frontmost(let bundleID, let pid) = target else { return }
        accumulator.recordTarget(pid: pid, bundleID: bundleID)
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

}

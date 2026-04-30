import AppKit
import ApplicationServices
import Foundation
import PersonalScribeCore

/// Probe returning `true` when the system-wide AX focused element is owned
/// by a different process (another app). Paste is safe when focus is outside
/// Ninimma. Injected as a dependency so tests can stub the result without
/// touching the real AX APIs.
typealias FocusedElementExternalityProbe = @MainActor () -> Bool

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
    private let requestAccessibilityPrompt: @MainActor () -> Void
    private let pasteShortcutPoster: @MainActor () -> Bool
    private let focusedElementIsInAnotherApp: FocusedElementExternalityProbe

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
        requestAccessibilityPrompt: @escaping @MainActor () -> Void = {
            let options = ["AXTrustedCheckOptionPrompt": true] as CFDictionary
            _ = AXIsProcessTrustedWithOptions(options)
        },
        pasteShortcutPoster: @escaping PasteShortcutPoster = ClipboardBatchOutput.postPasteShortcut,
        focusedElementIsInAnotherApp: @escaping FocusedElementExternalityProbe
            = ClipboardBatchOutput.liveFocusedElementIsInAnotherApp
    ) {
        self.logger = logger
        self.defaults = defaults
        self.frontmostAppProvider = frontmostAppProvider
        self.selfBundleIdentifier = selfBundleIdentifier
        self.snapshotService = snapshotService
        self.scheduleRestore = scheduleRestore
        self.isAccessibilityTrusted = isAccessibilityTrusted
        self.requestAccessibilityPrompt = requestAccessibilityPrompt
        self.pasteShortcutPoster = {
            pasteShortcutPoster(logger)
        }
        self.focusedElementIsInAnotherApp = focusedElementIsInAnotherApp
    }

    public func deliverBatch(text: String, sinks: [BoundOutputSink]) async -> OutputResult {
        guard !text.isEmpty else {
            return .ignoredEmptyInput
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

        let restoreDelay = ClipboardRestoreDelay.resolve(from: defaults).seconds
        let handle = snapshotService.captureTransientSnapshot()

        guard let writeToken = snapshotService.replaceContents(with: text) else {
            logger.info("ClipboardBatchOutput: failed to write transcript to pasteboard; restoring previous clipboard contents")
            snapshotService.restoreSnapshot(handle)
            return .failed(.clipboardWriteFailed)
        }

        // Schedules the user's pre-transcript clipboard to be restored after
        // `restoreDelay` seconds, but only if nothing has written to the
        // pasteboard since our transcript landed (changeCount guard — the
        // `restoreSnapshotIfUnchanged` checks against `writeToken`). Runs for
        // both the paste-at-cursor branch and the clipboard-only branch
        // (AutoPasteEnabledPreference off, or AX untrusted, or externality
        // probe says focus-is-in-self) — restore is orthogonal to paste mode.
        let maybeScheduleRestore: @MainActor () -> Void = { [snapshotService, scheduleRestore] in
            guard restoreEnabled else { return }
            scheduleRestore(restoreDelay) {
                snapshotService.restoreSnapshotIfUnchanged(handle, token: writeToken)
            }
        }

        if !pasteEnabled {
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
            logger.info("ClipboardBatchOutput: Accessibility permission not granted; triggering system prompt and leaving transcript on clipboard for manual Cmd+V")
            requestAccessibilityPrompt()
            maybeScheduleRestore()
            return .delivered(target: .clipboardOnly, delivery: .clipboardOnly)
        }

        guard focusedElementIsInAnotherApp() else {
            logger.info("ClipboardBatchOutput: AX focused element is owned by Ninimma (or not readable); leaving transcript on clipboard")
            maybeScheduleRestore()
            return .delivered(target: .clipboardOnly, delivery: .clipboardOnly)
        }

        guard pasteShortcutPoster() else {
            maybeScheduleRestore()
            return .delivered(target: .frontmostApp, delivery: .clipboardOnly)
        }

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

    /// Pure PID-comparison helper. Returns `true` iff the closure-supplied
    /// focused-element PID is non-nil AND differs from the current-process PID.
    /// Used by the live probe and directly by unit tests.
    static func focusedElementIsInAnotherApp(
        systemWideFocusedPID: () -> pid_t?,
        currentProcessPID: () -> pid_t = { ProcessInfo.processInfo.processIdentifier }
    ) -> Bool {
        guard let focusedPID = systemWideFocusedPID() else {
            return false
        }
        return focusedPID != currentProcessPID()
    }

    /// Live AX-based externality probe. Queries the system-wide focused UI
    /// element, reads its owning process PID via `AXUIElementGetPid`, and
    /// returns `true` when that PID is not this process. Any AX failure
    /// (untrusted process, missing focused element, PID read error) returns
    /// `false` — the safe default is to skip paste and leave the transcript
    /// on the clipboard.
    private static func liveFocusedElementIsInAnotherApp() -> Bool {
        focusedElementIsInAnotherApp(
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
}

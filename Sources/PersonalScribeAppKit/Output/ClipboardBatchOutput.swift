import AppKit
import ApplicationServices
import Foundation
import PersonalScribeCore

typealias PasteboardStringWriter = @MainActor (NSPasteboard, String) -> Bool

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
    private let pasteboard: NSPasteboard
    private let defaults: UserDefaults
    private let frontmostAppProvider: any FrontmostAppProviding
    private let selfBundleIdentifier: String
    private let scheduleRestore: RestoreScheduler
    private let isAccessibilityTrusted: @MainActor () -> Bool
    private let requestAccessibilityPrompt: @MainActor () -> Void
    private let pasteShortcutPoster: @MainActor () -> Bool
    private let writeString: PasteboardStringWriter
    private let focusedElementIsInAnotherApp: FocusedElementExternalityProbe

    public convenience init() {
        self.init(logger: PersonalScribeLogger(category: PersonalScribeLogCategory.ui))
    }

    init(
        logger: PersonalScribeLogger = PersonalScribeLogger(category: PersonalScribeLogCategory.ui),
        pasteboard: NSPasteboard = .general,
        defaults: UserDefaults = .standard,
        frontmostAppProvider: any FrontmostAppProviding = WorkspaceFrontmostAppProvider(),
        selfBundleIdentifier: String = AppBrand.bundleIdentifier,
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
        writeString: @escaping PasteboardStringWriter = { pasteboard, text in
            pasteboard.setString(text, forType: .string)
        },
        focusedElementIsInAnotherApp: @escaping FocusedElementExternalityProbe
            = ClipboardBatchOutput.liveFocusedElementIsInAnotherApp
    ) {
        self.logger = logger
        self.pasteboard = pasteboard
        self.defaults = defaults
        self.frontmostAppProvider = frontmostAppProvider
        self.selfBundleIdentifier = selfBundleIdentifier
        self.scheduleRestore = scheduleRestore
        self.isAccessibilityTrusted = isAccessibilityTrusted
        self.requestAccessibilityPrompt = requestAccessibilityPrompt
        self.pasteShortcutPoster = {
            pasteShortcutPoster(logger)
        }
        self.writeString = writeString
        self.focusedElementIsInAnotherApp = focusedElementIsInAnotherApp
    }

    public func deliverBatch(text: String) async -> OutputResult {
        guard !text.isEmpty else {
            return .ignoredEmptyInput
        }

        let restoreDelay = PasteRestoreDelay.resolve(from: defaults).seconds
        let pasteMode = PasteMode.resolve(from: defaults)
        let savedItems = savePasteboard()

        pasteboard.clearContents()

        guard writeString(pasteboard, text) else {
            logger.info("ClipboardBatchOutput: failed to write transcript to pasteboard; restoring previous clipboard contents")
            restorePasteboard(savedItems)
            return .failed(.clipboardWriteFailed)
        }

        // Flow (2026-04-22 — #042 fix):
        //   Transcription finished → copy to clipboard (always, above) → paste
        //   only if the user hasn't opted into clipboard-only mode, AX
        //   permission is granted, AND the AX focused element is owned by a
        //   different process (another app). Otherwise return `.clipboardOnly`
        //   so the existing "Copied to clipboard · ⌘V to paste" notice UI
        //   continues to fire.
        //
        //   The earlier 2026-04-20 design probed for text-role / cursor
        //   attributes directly; that under-included custom-drawn editors
        //   (Sublime, VS Code, Electron) whose focused elements report
        //   `AXGroup` / `AXUnknown` without exposing text attributes. The
        //   PID check trusts the focus owner instead — if it's not us,
        //   paste is intended.

        if pasteMode == .clipboardOnly {
            logger.info("ClipboardBatchOutput: user selected clipboard-only paste mode; leaving transcript on clipboard")
            return .delivered(target: .clipboardOnly, delivery: .clipboardOnly)
        }

        guard isAccessibilityTrusted() else {
            logger.info("ClipboardBatchOutput: Accessibility permission not granted; triggering system prompt and leaving transcript on clipboard for manual Cmd+V")
            requestAccessibilityPrompt()
            return .delivered(target: .clipboardOnly, delivery: .clipboardOnly)
        }

        guard focusedElementIsInAnotherApp() else {
            logger.info("ClipboardBatchOutput: AX focused element is owned by Ninimma (or not readable); leaving transcript on clipboard")
            return .delivered(target: .clipboardOnly, delivery: .clipboardOnly)
        }

        guard pasteShortcutPoster() else {
            return .delivered(target: .frontmostApp, delivery: .clipboardOnly)
        }

        scheduleRestore(restoreDelay) { [pasteboard] in
            pasteboard.clearContents()
            if !savedItems.isEmpty {
                pasteboard.writeObjects(savedItems)
            }
        }

        return .delivered(target: .frontmostApp, delivery: .paste)
    }

    private func savePasteboard() -> [NSPasteboardItem] {
        let items = pasteboard.pasteboardItems ?? []
        return items.map { source in
            let copy = NSPasteboardItem()
            for type in source.types {
                if let data = source.data(forType: type) {
                    copy.setData(data, forType: type)
                }
            }
            return copy
        }
    }

    private func restorePasteboard(_ items: [NSPasteboardItem]) {
        pasteboard.clearContents()
        if !items.isEmpty {
            pasteboard.writeObjects(items)
        }
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

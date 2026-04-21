import AppKit
import ApplicationServices
import Foundation
import PersonalScribeCore

typealias PasteboardStringWriter = @MainActor (NSPasteboard, String) -> Bool

/// Probe returning `true` when the system-wide AX focused element looks like a
/// text-input control that can receive a paste (has a cursor / insertion
/// point). Injected as a dependency so tests can stub the result without
/// touching the real AX APIs.
typealias FocusedElementCursorProbe = @MainActor () -> Bool

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
    private let focusedElementHasCursor: FocusedElementCursorProbe

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
        focusedElementHasCursor: @escaping FocusedElementCursorProbe
            = ClipboardBatchOutput.liveFocusedElementHasCursor
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
        self.focusedElementHasCursor = focusedElementHasCursor
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

        // Flow (2026-04-20 redesign):
        //   Transcription finished → copy to clipboard (always, above) → paste
        //   only if the user hasn't opted into clipboard-only mode, AX
        //   permission is granted, AND the AX focused element has a cursor.
        //   Otherwise return `.clipboardOnly` so the existing
        //   "Copied to clipboard · ⌘V to paste" notice UI continues to fire.

        if pasteMode == .clipboardOnly {
            logger.info("ClipboardBatchOutput: user selected clipboard-only paste mode; leaving transcript on clipboard")
            return .delivered(target: .clipboardOnly, delivery: .clipboardOnly)
        }

        guard isAccessibilityTrusted() else {
            logger.info("ClipboardBatchOutput: Accessibility permission not granted; triggering system prompt and leaving transcript on clipboard for manual Cmd+V")
            requestAccessibilityPrompt()
            return .delivered(target: .clipboardOnly, delivery: .clipboardOnly)
        }

        guard focusedElementHasCursor() else {
            logger.info("ClipboardBatchOutput: AX focused element has no cursor; leaving transcript on clipboard")
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

    // MARK: - Rollback fallback (previous bundle-ID proxy check)
    //
    // Until 2026-04-20 we resolved the paste target by comparing
    // `NSWorkspace.frontmostApplication.bundleIdentifier` against our own
    // bundle ID via `resolveTarget()`. When the user clicked Ninimma's pill
    // or a menu item to stop a recording, Ninimma briefly became frontmost at
    // the app level, so this check returned `OutputTarget.selfFrontmost`, the
    // paste path was skipped, and the user saw the clipboard-only notice even
    // though their actual text cursor was still sitting in Slack / VS Code /
    // etc.
    //
    // We replaced it with a stronger AX focused-element query
    // (`focusedElementHasCursor`, implemented below in
    // `liveFocusedElementHasCursor()`) that inspects the true focused UI
    // element system-wide rather than the frontmost NSRunningApplication.
    //
    // If the AX approach regresses (e.g. focus lost during transcription,
    // false-negative paste skips), delete the `focusedElementHasCursor` probe
    // from the `deliverBatch` flow and restore the block below verbatim, then
    // gate the paste branch on `target == .frontmostApp`. The enum case
    // `OutputTarget.selfFrontmost` is retained for that rollback.
    //
    // private func resolveTarget() -> OutputTarget {
    //     let pasteMode = PasteMode.resolve(from: defaults)
    //     if pasteMode == .clipboardOnly {
    //         return .clipboardOnly
    //     }
    //
    //     if frontmostAppProvider.frontmostApplicationBundleIdentifier == selfBundleIdentifier {
    //         return .selfFrontmost
    //     }
    //
    //     return .frontmostApp
    // }

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

    /// Live AX-based cursor probe. Queries the system-wide focused UI element
    /// and returns `true` when it exposes any of the attributes we treat as
    /// "has a cursor / insertion point":
    ///
    /// - `kAXInsertionPointLineNumberAttribute` readable
    /// - `kAXSelectedTextAttribute` readable
    /// - `kAXRoleAttribute` equal to `kAXTextFieldRole`, `kAXTextAreaRole`,
    ///   or `kAXComboBoxRole`
    ///
    /// Callers must have already confirmed Accessibility permission is
    /// granted; otherwise this will return `false` (AX queries on an
    /// untrusted process return errors / nil refs).
    private static func liveFocusedElementHasCursor() -> Bool {
        let systemWide = AXUIElementCreateSystemWide()
        var focusedRef: CFTypeRef?
        let status = AXUIElementCopyAttributeValue(
            systemWide,
            kAXFocusedUIElementAttribute as CFString,
            &focusedRef
        )
        guard status == .success, let focusedRef else {
            return false
        }
        // swiftlint:disable:next force_cast
        let focused = focusedRef as! AXUIElement

        if attributeIsReadable(focused, kAXInsertionPointLineNumberAttribute as CFString) {
            return true
        }
        if attributeIsReadable(focused, kAXSelectedTextAttribute as CFString) {
            return true
        }

        var roleRef: CFTypeRef?
        let roleStatus = AXUIElementCopyAttributeValue(
            focused,
            kAXRoleAttribute as CFString,
            &roleRef
        )
        if roleStatus == .success, let role = roleRef as? String {
            switch role {
            case kAXTextFieldRole as String,
                 kAXTextAreaRole as String,
                 kAXComboBoxRole as String:
                return true
            default:
                break
            }
        }

        return false
    }

    private static func attributeIsReadable(
        _ element: AXUIElement,
        _ attribute: CFString
    ) -> Bool {
        var value: CFTypeRef?
        let status = AXUIElementCopyAttributeValue(element, attribute, &value)
        return status == .success && value != nil
    }
}

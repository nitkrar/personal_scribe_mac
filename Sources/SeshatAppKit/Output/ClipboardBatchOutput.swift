import AppKit
import ApplicationServices
import Foundation
import SeshatCore

typealias PasteboardStringWriter = @MainActor (NSPasteboard, String) -> Bool

@MainActor
public final class ClipboardBatchOutput: OutputService, @unchecked Sendable {
    typealias RestoreScheduler = @MainActor (
        _ delay: TimeInterval,
        _ action: @escaping @MainActor () -> Void
    ) -> Void
    typealias PasteShortcutPoster = @MainActor (_ logger: SeshatLogger) -> Bool

    private let logger: SeshatLogger
    private let pasteboard: NSPasteboard
    private let defaults: UserDefaults
    private let frontmostAppProvider: any FrontmostAppProviding
    private let selfBundleIdentifier: String
    private let scheduleRestore: RestoreScheduler
    private let isAccessibilityTrusted: @MainActor () -> Bool
    private let requestAccessibilityPrompt: @MainActor () -> Void
    private let pasteShortcutPoster: @MainActor () -> Bool
    private let writeString: PasteboardStringWriter

    public convenience init() {
        self.init(logger: SeshatLogger(category: SeshatLogCategory.ui))
    }

    init(
        logger: SeshatLogger = SeshatLogger(category: SeshatLogCategory.ui),
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
        }
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
    }

    public func deliverBatch(text: String) async -> OutputResult {
        guard !text.isEmpty else {
            return .ignoredEmptyInput
        }

        let restoreDelay = PasteRestoreDelay.resolve(from: defaults).seconds
        let target = resolveTarget()
        let savedItems = savePasteboard()

        pasteboard.clearContents()

        guard writeString(pasteboard, text) else {
            logger.info("ClipboardBatchOutput: failed to write transcript to pasteboard; restoring previous clipboard contents")
            restorePasteboard(savedItems)
            return .failed(.clipboardWriteFailed)
        }

        guard target == .frontmostApp else {
            logger.info("ClipboardBatchOutput: leaving transcript on clipboard (\(String(describing: target)))")
            return .delivered(target: target, delivery: .clipboardOnly)
        }

        guard isAccessibilityTrusted() else {
            logger.info("ClipboardBatchOutput: Accessibility permission not granted; triggering system prompt and leaving transcript on clipboard for manual Cmd+V")
            requestAccessibilityPrompt()
            return .delivered(target: target, delivery: .clipboardOnly)
        }

        guard pasteShortcutPoster() else {
            return .delivered(target: target, delivery: .clipboardOnly)
        }

        scheduleRestore(restoreDelay) { [pasteboard] in
            pasteboard.clearContents()
            if !savedItems.isEmpty {
                pasteboard.writeObjects(savedItems)
            }
        }

        return .delivered(target: target, delivery: .paste)
    }

    private func resolveTarget() -> OutputTarget {
        let pasteMode = PasteMode.resolve(from: defaults)
        if pasteMode == .clipboardOnly {
            return .clipboardOnly
        }

        if frontmostAppProvider.frontmostApplicationBundleIdentifier == selfBundleIdentifier {
            return .selfFrontmost
        }

        return .frontmostApp
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

    private static func postPasteShortcut(logger: SeshatLogger) -> Bool {
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
}

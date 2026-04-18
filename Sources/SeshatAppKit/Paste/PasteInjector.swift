import AppKit
import ApplicationServices
import Foundation
import SeshatCore

@MainActor
protocol PasteInjecting {
    func paste(_ text: String)
}

@MainActor
public struct PasteInjector: PasteInjecting {
    public typealias RestoreScheduler = @MainActor (
        _ delay: TimeInterval,
        _ action: @escaping @MainActor () -> Void
    ) -> Void
    public typealias PasteShortcutPoster = @MainActor (_ logger: SeshatLogger) -> Bool

    private let logger: SeshatLogger
    private let pasteboard: NSPasteboard
    private let restoreDelay: TimeInterval
    private let scheduleRestore: RestoreScheduler
    private let isAccessibilityTrusted: @MainActor () -> Bool
    private let requestAccessibilityPrompt: @MainActor () -> Void
    private let pasteShortcutPoster: @MainActor () -> Bool

    public init(
        logger: SeshatLogger = SeshatLogger(category: SeshatLogCategory.ui),
        pasteboard: NSPasteboard = .general,
        restoreDelay: TimeInterval = 0.25,
        scheduleRestore: @escaping RestoreScheduler = { delay, action in
            DispatchQueue.main.asyncAfter(deadline: .now() + delay) {
                Task { @MainActor in
                    action()
                }
            }
        },
        isAccessibilityTrusted: @escaping @MainActor () -> Bool = { AXIsProcessTrusted() },
        requestAccessibilityPrompt: @escaping @MainActor () -> Void = {
            // Raw literal matches kAXTrustedCheckOptionPrompt; the CF-imported
            // symbol is flagged non-Sendable under Swift 6 strict concurrency.
            let options = ["AXTrustedCheckOptionPrompt": true] as CFDictionary
            _ = AXIsProcessTrustedWithOptions(options)
        },
        pasteShortcutPoster: @escaping PasteShortcutPoster = PasteInjector.postPasteShortcut
    ) {
        self.logger = logger
        self.pasteboard = pasteboard
        self.restoreDelay = restoreDelay
        self.scheduleRestore = scheduleRestore
        self.isAccessibilityTrusted = isAccessibilityTrusted
        self.requestAccessibilityPrompt = requestAccessibilityPrompt
        self.pasteShortcutPoster = {
            pasteShortcutPoster(logger)
        }
    }

    @MainActor
    static func live(
        logger: SeshatLogger = SeshatLogger(category: SeshatLogCategory.ui),
        pasteboard: NSPasteboard = .general,
        restoreDelay: TimeInterval = 0.25,
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
        pasteShortcutPoster: @escaping PasteShortcutPoster = PasteInjector.postPasteShortcut
    ) -> any PasteInjecting {
        PasteInjector(
            logger: logger,
            pasteboard: pasteboard,
            restoreDelay: restoreDelay,
            scheduleRestore: scheduleRestore,
            isAccessibilityTrusted: isAccessibilityTrusted,
            requestAccessibilityPrompt: requestAccessibilityPrompt,
            pasteShortcutPoster: pasteShortcutPoster
        )
    }

    public func paste(_ text: String) {
        guard !text.isEmpty else { return }

        let savedItems = savePasteboard()
        pasteboard.clearContents()

        guard pasteboard.setString(text, forType: .string) else {
            logger.info("PasteInjector: failed to write transcript to pasteboard; restoring previous clipboard contents")
            restorePasteboard(savedItems)
            return
        }

        guard isAccessibilityTrusted() else {
            logger.info("PasteInjector: Accessibility permission not granted; triggering system prompt and leaving transcript on clipboard for manual Cmd+V")
            requestAccessibilityPrompt()
            return
        }

        guard pasteShortcutPoster() else { return }

        scheduleRestore(restoreDelay) { [pasteboard] in
            pasteboard.clearContents()
            if !savedItems.isEmpty {
                pasteboard.writeObjects(savedItems)
            }
        }
    }

    @usableFromInline
    static func postPasteShortcut(logger: SeshatLogger) -> Bool {
        guard let source = CGEventSource(stateID: .combinedSessionState) else {
            logger.info("PasteInjector: failed to create CGEventSource; leaving transcript on clipboard as fallback")
            return false
        }

        let vKey: CGKeyCode = 9
        guard let down = CGEvent(keyboardEventSource: source, virtualKey: vKey, keyDown: true),
              let up = CGEvent(keyboardEventSource: source, virtualKey: vKey, keyDown: false) else {
            logger.info("PasteInjector: failed to create CGEvent; leaving transcript on clipboard as fallback")
            return false
        }

        logger.info("PasteInjector: posting synthetic Cmd+V to the frontmost app")
        down.flags = .maskCommand
        up.flags = .maskCommand
        down.post(tap: .cghidEventTap)
        up.post(tap: .cghidEventTap)

        return true
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
}

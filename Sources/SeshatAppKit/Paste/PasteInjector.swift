import AppKit
import ApplicationServices
import Foundation
import SeshatCore

@MainActor
public struct PasteInjector {
    public typealias RestoreScheduler = @MainActor (
        _ delay: TimeInterval,
        _ action: @escaping @MainActor () -> Void
    ) -> Void

    private let logger: SeshatLogger
    private let pasteboard: NSPasteboard
    private let restoreDelay: TimeInterval
    private let scheduleRestore: RestoreScheduler

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
        }
    ) {
        self.logger = logger
        self.pasteboard = pasteboard
        self.restoreDelay = restoreDelay
        self.scheduleRestore = scheduleRestore
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

        guard postCommandV() else { return }

        scheduleRestore(restoreDelay) { [pasteboard] in
            pasteboard.clearContents()
            if !savedItems.isEmpty {
                pasteboard.writeObjects(savedItems)
            }
        }
    }

    private func postCommandV() -> Bool {
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

        if !AXIsProcessTrusted() {
            logger.info("PasteInjector: Accessibility permission likely denied; synthetic paste may be ignored and transcript remains on the clipboard")
            return false
        }

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

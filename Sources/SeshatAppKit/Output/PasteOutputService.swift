import AppKit
import ApplicationServices
import Foundation
import SeshatCore

@MainActor
protocol PasteOutputServing: Sendable {
    func paste(text: String) async throws
}

@MainActor
final class PasteOutputService: PasteOutputServing, @unchecked Sendable {
    private static let seshatBundleIdentifier = "com.nitkrar.seshat"

    private let logger: SeshatLogger
    private let pasteboard: NSPasteboard
    private let defaults: UserDefaults
    private let frontmostAppProvider: any FrontmostAppProviding
    private let selfBundleIdentifier: String
    private let scheduleRestore: PasteInjector.RestoreScheduler
    private let isAccessibilityTrusted: @MainActor () -> Bool
    private let requestAccessibilityPrompt: @MainActor () -> Void
    private let pasteShortcutPoster: @MainActor () -> Bool

    init(
        logger: SeshatLogger = SeshatLogger(category: SeshatLogCategory.ui),
        pasteboard: NSPasteboard = .general,
        defaults: UserDefaults = .standard,
        frontmostAppProvider: any FrontmostAppProviding = WorkspaceFrontmostAppProvider(),
        selfBundleIdentifier: String = PasteOutputService.seshatBundleIdentifier,
        scheduleRestore: @escaping PasteInjector.RestoreScheduler = { delay, action in
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
        pasteShortcutPoster: @escaping PasteInjector.PasteShortcutPoster = PasteInjector.postPasteShortcut
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
    }

    func paste(text: String) async throws {
        guard !text.isEmpty else { return }

        let restoreDelay = PasteRestoreDelay.resolve(from: defaults).seconds
        let target = resolveTarget()
        let savedItems = savePasteboard()

        pasteboard.clearContents()

        guard pasteboard.setString(text, forType: .string) else {
            logger.info("PasteOutputService: failed to write transcript to pasteboard; restoring previous clipboard contents")
            restorePasteboard(savedItems)
            throw OutputError.clipboardWriteFailed
        }

        guard target == .frontmostApp else {
            logger.info("PasteOutputService: leaving transcript on clipboard (\(String(describing: target)))")
            throw OutputError.clipboardOnlyFallback
        }

        guard isAccessibilityTrusted() else {
            logger.info("PasteOutputService: Accessibility permission not granted; triggering system prompt and leaving transcript on clipboard for manual Cmd+V")
            requestAccessibilityPrompt()
            throw OutputError.clipboardOnlyFallback
        }

        guard pasteShortcutPoster() else {
            throw OutputError.clipboardOnlyFallback
        }

        scheduleRestore(restoreDelay) { [pasteboard] in
            pasteboard.clearContents()
            if !savedItems.isEmpty {
                pasteboard.writeObjects(savedItems)
            }
        }
    }

    private func resolveTarget() -> OutputTarget {
        let pasteMode = SeshatPasteMode.resolve(from: defaults)
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
}

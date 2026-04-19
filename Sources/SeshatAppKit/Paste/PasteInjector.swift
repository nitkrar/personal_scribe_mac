import AppKit
import ApplicationServices
import Foundation
import SeshatCore

@MainActor
enum PasteRoutingDecision: Equatable, Sendable {
    enum ClipboardOnlyReason: Equatable, Sendable {
        case clipboardOnlyMode
        case frontmostAppIsSeshat
    }

    case pasteAtCursor
    case clipboardOnly(reason: ClipboardOnlyReason)
}

@MainActor
protocol FrontmostAppProviding {
    var frontmostApplicationBundleIdentifier: String? { get }
}

struct WorkspaceFrontmostAppProvider: FrontmostAppProviding {
    var frontmostApplicationBundleIdentifier: String? {
        NSWorkspace.shared.frontmostApplication?.bundleIdentifier
    }
}

@MainActor
private struct PasteRoutingDecider {
    let defaults: UserDefaults
    let frontmostAppProvider: any FrontmostAppProviding
    let selfBundleIdentifier: String

    func resolve() -> PasteRoutingDecision {
        let pasteMode = PasteMode.resolve(from: defaults)
        if pasteMode == .clipboardOnly {
            return .clipboardOnly(reason: .clipboardOnlyMode)
        }

        if frontmostAppProvider.frontmostApplicationBundleIdentifier == selfBundleIdentifier {
            return .clipboardOnly(reason: .frontmostAppIsSeshat)
        }

        return .pasteAtCursor
    }
}

@MainActor
protocol PasteInjecting {
    @discardableResult
    func paste(_ text: String) -> PasteRoutingDecision
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
    private let defaults: UserDefaults
    private let frontmostAppProvider: any FrontmostAppProviding
    private let selfBundleIdentifier: String
    private let scheduleRestore: RestoreScheduler
    private let permissionService: PermissionServiceAdapter
    private let pasteShortcutPoster: @MainActor () -> Bool

    init(
        logger: SeshatLogger = SeshatLogger(category: SeshatLogCategory.ui),
        pasteboard: NSPasteboard = .general,
        defaults: UserDefaults = .standard,
        frontmostAppProvider: any FrontmostAppProviding = WorkspaceFrontmostAppProvider(),
        selfBundleIdentifier: String = AppBrand.bundleIdentifier,
        permissionService: PermissionServiceAdapter,
        scheduleRestore: @escaping RestoreScheduler = { delay, action in
            DispatchQueue.main.asyncAfter(deadline: .now() + delay) {
                Task { @MainActor in
                    action()
                }
            }
        },
        pasteShortcutPoster: @escaping PasteShortcutPoster = PasteInjector.postPasteShortcut
    ) {
        self.logger = logger
        self.pasteboard = pasteboard
        self.defaults = defaults
        self.frontmostAppProvider = frontmostAppProvider
        self.selfBundleIdentifier = selfBundleIdentifier
        self.permissionService = permissionService
        self.scheduleRestore = scheduleRestore
        self.pasteShortcutPoster = {
            pasteShortcutPoster(logger)
        }
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
        pasteShortcutPoster: @escaping PasteShortcutPoster = PasteInjector.postPasteShortcut
    ) {
        self.logger = logger
        self.pasteboard = pasteboard
        self.defaults = defaults
        self.frontmostAppProvider = frontmostAppProvider
        self.selfBundleIdentifier = selfBundleIdentifier
        self.permissionService = Self.makeCompatibilityPermissionService(
            isAccessibilityTrusted: isAccessibilityTrusted,
            requestAccessibilityPrompt: requestAccessibilityPrompt
        )
        self.scheduleRestore = scheduleRestore
        self.pasteShortcutPoster = {
            pasteShortcutPoster(logger)
        }
    }

    @MainActor
    static func live(
        logger: SeshatLogger = SeshatLogger(category: SeshatLogCategory.ui),
        pasteboard: NSPasteboard = .general,
        defaults: UserDefaults = .standard,
        frontmostAppProvider: any FrontmostAppProviding = WorkspaceFrontmostAppProvider(),
        selfBundleIdentifier: String = AppBrand.bundleIdentifier,
        permissionService: PermissionServiceAdapter,
        scheduleRestore: @escaping RestoreScheduler = { delay, action in
            DispatchQueue.main.asyncAfter(deadline: .now() + delay) {
                Task { @MainActor in
                    action()
                }
            }
        },
        pasteShortcutPoster: @escaping PasteShortcutPoster = PasteInjector.postPasteShortcut
    ) -> any PasteInjecting {
        PasteInjector(
            logger: logger,
            pasteboard: pasteboard,
            defaults: defaults,
            frontmostAppProvider: frontmostAppProvider,
            selfBundleIdentifier: selfBundleIdentifier,
            permissionService: permissionService,
            scheduleRestore: scheduleRestore,
            pasteShortcutPoster: pasteShortcutPoster
        )
    }

    @MainActor
    static func live(
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
        pasteShortcutPoster: @escaping PasteShortcutPoster = PasteInjector.postPasteShortcut
    ) -> any PasteInjecting {
        PasteInjector(
            logger: logger,
            pasteboard: pasteboard,
            defaults: defaults,
            frontmostAppProvider: frontmostAppProvider,
            selfBundleIdentifier: selfBundleIdentifier,
            scheduleRestore: scheduleRestore,
            isAccessibilityTrusted: isAccessibilityTrusted,
            requestAccessibilityPrompt: requestAccessibilityPrompt,
            pasteShortcutPoster: pasteShortcutPoster
        )
    }

    @discardableResult
    func paste(_ text: String) -> PasteRoutingDecision {
        guard !text.isEmpty else { return .pasteAtCursor }

        let restoreDelay = PasteRestoreDelay.resolve(from: defaults).seconds
        let route = PasteRoutingDecider(
            defaults: defaults,
            frontmostAppProvider: frontmostAppProvider,
            selfBundleIdentifier: selfBundleIdentifier
        ).resolve()

        let savedItems = savePasteboard()
        pasteboard.clearContents()

        guard pasteboard.setString(text, forType: .string) else {
            logger.info("PasteInjector: failed to write transcript to pasteboard; restoring previous clipboard contents")
            restorePasteboard(savedItems)
            return route
        }

        if case .clipboardOnly(let reason) = route {
            logger.info("PasteInjector: leaving transcript on clipboard (\(reason))")
            return route
        }

        guard permissionService.status(for: .accessibility) == .granted else {
            logger.info("PasteInjector: Accessibility permission not granted; triggering system prompt and leaving transcript on clipboard for manual Cmd+V")
            Task { @MainActor in
                _ = await permissionService.request(.accessibility)
            }
            return route
        }

        guard pasteShortcutPoster() else { return route }

        scheduleRestore(restoreDelay) { [pasteboard] in
            pasteboard.clearContents()
            if !savedItems.isEmpty {
                pasteboard.writeObjects(savedItems)
            }
        }

        return route
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

    private static func makeCompatibilityPermissionService(
        isAccessibilityTrusted: @escaping @MainActor () -> Bool,
        requestAccessibilityPrompt: @escaping @MainActor () -> Void
    ) -> PermissionServiceAdapter {
        let currentStatuses: @MainActor () -> [Permission: PermissionStatus] = {
            [
                .microphone: .granted,
                .inputMonitoring: .granted,
                .accessibility: isAccessibilityTrusted() ? .granted : .pending,
            ]
        }

        return PermissionServiceAdapter(
            initialStatuses: currentStatuses(),
            statusReader: { permission in
                currentStatuses()[permission] ?? .pending
            },
            requester: { permission in
                guard permission == .accessibility else {
                    return RequestOutcome(
                        prompted: false,
                        openedSettings: false,
                        requiresRelaunch: false,
                        finalStatus: currentStatuses()[permission] ?? .pending
                    )
                }

                requestAccessibilityPrompt()
                return RequestOutcome(
                    prompted: true,
                    openedSettings: false,
                    requiresRelaunch: false,
                    finalStatus: isAccessibilityTrusted() ? .granted : .pending
                )
            },
            refresher: currentStatuses
        )
    }
}

import AppKit
import Combine
import Foundation
import SeshatCore
import SeshatSession

/// Owns the menu-bar `NSStatusItem` and its `NSMenu`.
///
/// Replaces SwiftUI's `MenuBarExtra` + `MenuBarScene` popover per
/// `plans/seshat_agent_bundle/03_Surfaces/MenuBarMenu/IMPORTANT.md`:
/// native AppKit `NSMenu`, zero SwiftUI inside the menu. The pure
/// `StatusItemMenuModel` describes WHAT to render; this class does
/// the AppKit binding.
///
/// ## State flow
/// * Subscribes to `MenuBarSceneModel.$state` for status-item icon
///   tinting on recording.
/// * Rebuilds the menu from scratch on each `menuNeedsUpdate(_:)`
///   using the shared permission snapshot.
/// * Forwards clicks to injected handlers (record-toggle goes via
///   `MenuBarSceneModel.handleRecordButtonTap()` so the existing
///   permission-request flow keeps working).
///
/// ## Default handlers
/// `openHistory` remains a placeholder alert by default; app
/// composition now injects the live Settings window launcher.
@MainActor
final class StatusItemController: NSObject, NSMenuDelegate {
    private let statusItem: NSStatusItem
    private let sceneModel: MenuBarSceneModel
    private let permissionService: PermissionServiceAdapter
    private let openHistory: @MainActor () -> Void
    private let openSettings: @MainActor () -> Void
    private let isOnboardingCompleteProvider: @MainActor () -> Bool
    private let openURL: @MainActor (URL) -> Void
    private let logger: SeshatLogger

    private var stateCancellable: AnyCancellable?
    private var permissionStatusesCancellable: AnyCancellable?

    init(
        sceneModel: MenuBarSceneModel,
        permissionService: PermissionServiceAdapter? = nil,
        imPermissionProbe: any PermissionProbing = IOHIDPermissionProbe(),
        openHistory: @escaping @MainActor () -> Void = StatusItemController.defaultPhase3Placeholder(name: "History"),
        openSettings: @escaping @MainActor () -> Void = {},
        isOnboardingCompleteProvider: @escaping @MainActor () -> Bool = {
            SeshatOnboardingCompleted.resolve().rawValue
        },
        openURL: (@MainActor (URL) -> Void)? = nil,
        openMicrophoneSystemSettings: @escaping @MainActor () -> Void = StatusItemController.defaultOpenMicrophoneSettings,
        openInputMonitoringSystemSettings: @escaping @MainActor () -> Void = StatusItemController.defaultOpenInputMonitoringSettings,
        logger: SeshatLogger = SeshatLogger(category: SeshatLogCategory.ui)
    ) {
        self.sceneModel = sceneModel
        self.permissionService = permissionService
            ?? Self.makeCompatibilityPermissionService(
                sceneModel: sceneModel,
                imPermissionProbe: imPermissionProbe
            )
        self.openHistory = openHistory
        self.openSettings = openSettings
        self.isOnboardingCompleteProvider = isOnboardingCompleteProvider
        self.openURL = openURL ?? { url in
            switch url {
            case PermissionServiceAdapter.defaultSystemSettingsDeepLink(for: .microphone):
                openMicrophoneSystemSettings()
            case PermissionServiceAdapter.defaultSystemSettingsDeepLink(for: .inputMonitoring):
                openInputMonitoringSystemSettings()
            default:
                _ = NSWorkspace.shared.open(url)
            }
        }
        self.logger = logger
        self.statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)

        super.init()

        configureStatusItemButton()

        let menu = NSMenu()
        menu.delegate = self
        menu.autoenablesItems = false
        statusItem.menu = menu

        stateCancellable = sceneModel.$state
            .receive(on: DispatchQueue.main)
            .sink { [weak self] newState in
                self?.updateStatusItemAppearance(for: newState)
            }

        permissionStatusesCancellable = self.permissionService.$statuses
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                // If the menu is currently open, rebuild it so permission
                // warnings appear/disappear after prompts or Settings changes.
                guard let self else { return }
                if self.statusItem.menu?.numberOfItems ?? 0 > 0 {
                    self.rebuildMenu()
                }
            }

        updateStatusItemAppearance(for: sceneModel.state)
    }

    isolated deinit {
        // AnyCancellable auto-cancels on deinit — no explicit .cancel() needed.
        NSStatusBar.system.removeStatusItem(statusItem)
    }

    // MARK: - NSMenuDelegate

    func menuNeedsUpdate(_ menu: NSMenu) {
        rebuildMenu()
    }

    var isStatusItemVisible: Bool {
        statusItem.isVisible
    }

    func setStatusItemVisible(_ isVisible: Bool) {
        statusItem.isVisible = isVisible
    }

    func performMenuAction(_ id: StatusItemMenuModel.ActionID) {
        switch id {
        case .startStopRecording:
            Task { @MainActor in
                await sceneModel.handleRecordButtonTap()
            }
        case .openHistory:
            openHistory()
        case .openSettings:
            openSettings()
        case .openMicrophoneSystemSettings:
            openURL(permissionService.systemSettingsDeepLink(for: .microphone))
        case .openInputMonitoringSystemSettings:
            openURL(permissionService.systemSettingsDeepLink(for: .inputMonitoring))
        case .quit:
            NSApplication.shared.terminate(nil)
        }
    }

    // MARK: - Private

    private func configureStatusItemButton() {
        guard let button = statusItem.button else { return }

        // Load from `Bundle.module` — the SwiftPM resource bundle the
        // asset catalog lives in. `NSImage(named:)` only searches
        // `Bundle.main`, which is why the packaged `.app` was falling
        // back to the "S" text glyph.
        if let image = StatusItemIconLoader.loadStatusBarIcon() {
            button.image = image
        } else {
            // Defensive fallback so the app still launches if the
            // asset catalog is genuinely missing from the build.
            button.title = "S"
            logger.error("StatusBarIcon asset missing from Bundle.module — falling back to text glyph")
        }

        let label = statusItemLabel(for: .idle)
        button.toolTip = label
        button.accessibilityLabel = label
    }

    private func updateStatusItemAppearance(for sessionState: SessionState) {
        guard let button = statusItem.button else { return }

        // Swap between the two quill-pose assets so recording is
        // visually distinct from idle without relying on tint alone
        // (plan line 342 — "cycle between two frames" for the status
        // item during recording; second asset shipped 2026-04-18).
        let pose: StatusItemIconLoader.Pose = {
            switch sessionState {
            case .recording, .transcribing:
                return .listening
            case .idle, .error:
                return .idle
            }
        }()

        if let image = StatusItemIconLoader.loadStatusBarIcon(pose: pose) {
            button.image = image
        }

        switch sessionState {
        case .recording:
            button.contentTintColor = .systemRed
        case .transcribing:
            button.contentTintColor = .systemOrange
        case .idle, .error:
            button.contentTintColor = nil
        }
        let label = statusItemLabel(for: sessionState)
        button.toolTip = label
        button.accessibilityLabel = label

        // If the menu is currently showing, rebuild so the
        // Record/Stop title tracks state live.
        if statusItem.menu?.numberOfItems ?? 0 > 0 {
            rebuildMenu()
        }
    }

    private func rebuildMenu() {
        guard let menu = statusItem.menu else { return }

        let permissions = permissionService.statusSnapshot()
        let model = StatusItemMenuModel.makeUnified(
            sessionState: sceneModel.state,
            micPermission: permissions[.microphone] ?? .pending,
            inputMonitoringPermission: permissions[.inputMonitoring] ?? .pending,
            isOnboardingComplete: isOnboardingCompleteProvider()
        )

        menu.removeAllItems()

        for item in model.items {
            switch item {
            case .separator:
                menu.addItem(.separator())
            case .header(let title):
                let mi = NSMenuItem(title: title, action: nil, keyEquivalent: "")
                mi.isEnabled = false
                menu.addItem(mi)
            case .action(let action):
                let mi = NSMenuItem()
                mi.title = action.title
                mi.keyEquivalent = action.keyEquivalent
                if !action.keyEquivalent.isEmpty {
                    mi.keyEquivalentModifierMask =
                        action.id == .startStopRecording ? [.command, .option] : [.command]
                }
                mi.isEnabled = action.isEnabled
                mi.target = self
                mi.action = #selector(handleMenuAction(_:))
                mi.representedObject = action.id.rawValue
                menu.addItem(mi)
            }
        }
    }

    @objc private func handleMenuAction(_ sender: NSMenuItem) {
        guard let idString = sender.representedObject as? String,
              let id = StatusItemMenuModel.ActionID(rawValue: idString) else {
            logger.error("Menu action fired with unknown representedObject")
            return
        }

        performMenuAction(id)
    }

    private func statusItemLabel(for sessionState: SessionState) -> String {
        switch sessionState {
        case .recording:
            return "\(AppBrand.displayName) — recording"
        case .transcribing:
            return "\(AppBrand.displayName) — transcribing"
        case .idle, .error:
            return AppBrand.displayName
        }
    }

    // MARK: - Default handlers

    private static func defaultPhase3Placeholder(name: String) -> @MainActor () -> Void {
        return {
            let alert = NSAlert()
            alert.messageText = "\(name) — Coming in Phase 3"
            alert.informativeText = "This window lands alongside NotesWindow / SettingsWindow in Phase 3."
            alert.alertStyle = .informational
            alert.runModal()
        }
    }

    private static let defaultOpenMicrophoneSettings: @MainActor () -> Void = {
        guard let url = URL(
            string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Microphone"
        ) else { return }
        NSWorkspace.shared.open(url)
    }

    private static let defaultOpenInputMonitoringSettings: @MainActor () -> Void = {
        // macOS 14 anchor: ListenEvent. macOS 15 renamed to ListenEvent as well
        // but the parent pane changed. This URL works on 14+.
        guard let url = URL(
            string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ListenEvent"
        ) else { return }
        NSWorkspace.shared.open(url)
    }

    private static func makeCompatibilityPermissionService(
        sceneModel: MenuBarSceneModel,
        imPermissionProbe: any PermissionProbing
    ) -> PermissionServiceAdapter {
        let snapshot: @MainActor () -> [Permission: PermissionStatus] = {
            [
                .microphone: sceneModel.permissionState.unifiedPermissionStatus,
                .inputMonitoring: imPermissionProbe.checkInputMonitoring().unifiedPermissionStatus,
                .accessibility: .pending,
            ]
        }

        return PermissionServiceAdapter(
            initialStatuses: snapshot(),
            statusReader: { permission in
                snapshot()[permission] ?? .pending
            },
            requester: { permission in
                RequestOutcome(
                    prompted: false,
                    openedSettings: false,
                    requiresRelaunch: permission == .inputMonitoring,
                    finalStatus: snapshot()[permission] ?? .pending
                )
            },
            refresher: snapshot
        )
    }
}

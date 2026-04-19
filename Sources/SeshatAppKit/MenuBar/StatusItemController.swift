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
///   (re-probes Input Monitoring permission each time; mic state
///   comes from `sceneModel.permissionState`).
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
    private let imPermissionProbe: any PermissionProbing
    private let openHistory: @MainActor () -> Void
    private let openSettings: @MainActor () -> Void
    private let isOnboardingCompleteProvider: @MainActor () -> Bool
    private let openMicrophoneSystemSettings: @MainActor () -> Void
    private let openInputMonitoringSystemSettings: @MainActor () -> Void
    private let logger: SeshatLogger

    private var stateCancellable: AnyCancellable?
    private var micPermissionCancellable: AnyCancellable?

    init(
        sceneModel: MenuBarSceneModel,
        imPermissionProbe: any PermissionProbing = IOHIDPermissionProbe(),
        openHistory: @escaping @MainActor () -> Void = StatusItemController.defaultPhase3Placeholder(name: "History"),
        openSettings: @escaping @MainActor () -> Void = {},
        isOnboardingCompleteProvider: @escaping @MainActor () -> Bool = {
            SeshatOnboardingCompleted.resolve().rawValue
        },
        openMicrophoneSystemSettings: @escaping @MainActor () -> Void = StatusItemController.defaultOpenMicrophoneSettings,
        openInputMonitoringSystemSettings: @escaping @MainActor () -> Void = StatusItemController.defaultOpenInputMonitoringSettings,
        logger: SeshatLogger = SeshatLogger(category: SeshatLogCategory.ui)
    ) {
        self.sceneModel = sceneModel
        self.imPermissionProbe = imPermissionProbe
        self.openHistory = openHistory
        self.openSettings = openSettings
        self.isOnboardingCompleteProvider = isOnboardingCompleteProvider
        self.openMicrophoneSystemSettings = openMicrophoneSystemSettings
        self.openInputMonitoringSystemSettings = openInputMonitoringSystemSettings
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

        micPermissionCancellable = sceneModel.$permissionState
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                // Mic permission changed — if the menu is currently open,
                // rebuild it so the warning item appears/disappears. If
                // closed, the next open triggers menuNeedsUpdate.
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
            openMicrophoneSystemSettings()
        case .openInputMonitoringSystemSettings:
            openInputMonitoringSystemSettings()
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

        button.toolTip = "Seshat"
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
            button.toolTip = "Seshat — recording"
        case .transcribing:
            button.contentTintColor = .systemOrange
            button.toolTip = "Seshat — transcribing"
        case .idle, .error:
            button.contentTintColor = nil
            button.toolTip = "Seshat"
        }

        // If the menu is currently showing, rebuild so the
        // Record/Stop title tracks state live.
        if statusItem.menu?.numberOfItems ?? 0 > 0 {
            rebuildMenu()
        }
    }

    private func rebuildMenu() {
        guard let menu = statusItem.menu else { return }

        let imPermission = imPermissionProbe.checkInputMonitoring()
        let model = StatusItemMenuModel.make(
            sessionState: sceneModel.state,
            micPermission: sceneModel.permissionState,
            inputMonitoringPermission: imPermission,
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
}
